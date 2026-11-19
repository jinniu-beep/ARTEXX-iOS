import Foundation

/// 内置真·Go 后端（libartex.a）。在 App 内启动原版 ARTEXX 服务端，监听 127.0.0.1:port，
/// 由它提供真实 /api 接口 + 内置 Web UI（从 App Bundle 的 webui/ 读取），SQLite 作数据层。
/// 启动失败时由调用方回落到 Swift 版 `EmbeddedServer`。
final class GoBackend {
    static let shared = GoBackend()
    private(set) var started = false

    /// 真·Go 后端签发的 JWT。拿到后注入 WebView 的 localStorage，前端免登录直达主界面。
    /// 为空表示还没拿到（启动竞态或鉴权暂不可用）。
    /// 后台线程写、主线程读，故加锁避免 String 撕裂读。
    private let tokenLock = NSLock()
    private var _authToken = ""
    var authToken: String {
        tokenLock.lock(); defer { tokenLock.unlock() }
        return _authToken
    }
    private func setAuthToken(_ t: String) {
        tokenLock.lock(); _authToken = t; tokenLock.unlock()
    }

    /// token 就绪广播：WebView 若先于 token 建好，收到后刷新注入并重载。
    static let authReady = Notification.Name("ArtexAuthReady")

    /// 可写数据目录：Library/Application Support/artex（SQLite、jwt.key、skills 等）。
    static func dataDir() -> String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("artex", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    /// App Bundle 内随包的 webui 静态站点目录（folder reference，只读）。
    static func webuiDir() -> String {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("webui", isDirectory: true),
           FileManager.default.fileExists(atPath: url.path) {
            return url.path
        }
        return ""
    }

    /// 首次启动把随包的 skills 目录解包到可写数据目录（Go 侧要能写，不能直接读 bundle）。
    static func ensureSkills() {
        let fm = FileManager.default
        let dst = URL(fileURLWithPath: dataDir()).appendingPathComponent("skills", isDirectory: true)
        if fm.fileExists(atPath: dst.path) { return }
        guard let src = Bundle.main.resourceURL?.appendingPathComponent("skills", isDirectory: true),
              fm.fileExists(atPath: src.path) else { return }
        try? fm.copyItem(at: src, to: dst)
    }

    /// 启动后端。成功返回 true（服务已绑定并在应答），失败返回 false。
    @discardableResult
    func start(port: Int32 = 8787) -> Bool {
        guard !started else { return true }
        GoBackend.ensureSkills()
        let data = GoBackend.dataDir()
        let web = GoBackend.webuiDir()
        let rc = data.withCString { d in
            web.withCString { w in
                ArtexStart(port, UnsafeMutablePointer(mutating: d), UnsafeMutablePointer(mutating: w))
            }
        }
        started = (rc == 0)
        if started {
            // 服务已在应答：立刻换一个真实 token。首启时初始化管理员密码（/auth/init），
            // 之后用同一设备密码登录（/auth/login）。同步在本后台线程里跑完，
            // 这样 WebView（随启动页消失后才出现）建好时 authToken 基本已就绪。
            ensureAuthToken(port: port)
        }
        return started
    }

    /// 本机单用户的管理员密码：首次随机生成一串存 UserDefaults，之后固定。
    /// 仅用于 App 自己向内置后端换 token，用户看不到、也无需输入。
    private static func devicePassword() -> String {
        let key = "artex.go.adminPassword"
        if let p = UserDefaults.standard.string(forKey: key), p.count >= 8 { return p }
        let p = UUID().uuidString.replacingOccurrences(of: "-", with: "") // 32 hex，满足 >=8 位
        UserDefaults.standard.set(p, forKey: key)
        return p
    }

    /// 同步向内置 Go 后端换取真实 JWT。服务已确认在应答，故几次重试即可覆盖瞬时失败。
    private func ensureAuthToken(port: Int32) {
        guard authToken.isEmpty else { return }
        let base = "http://127.0.0.1:\(port)/api/auth"
        let pw = GoBackend.devicePassword()
        for _ in 0..<5 {
            guard let status = GoBackend.httpJSON("GET", base + "/status", nil) else {
                Thread.sleep(forTimeInterval: 0.3)
                continue
            }
            let initialized = (status["initialized"] as? Bool) ?? false
            // 未初始化→设密码并直接拿 token；已初始化→用同一设备密码登录。
            // init 若因竞态返回“已设置”(非 2xx→nil)，下一轮 status 会变 true 自动走 login。
            let endpoint = initialized ? "/login" : "/init"
            let body: [String: Any] = initialized
                ? ["username": "ARTEX", "password": pw]
                : ["password": pw]
            if let resp = GoBackend.httpJSON("POST", base + endpoint, body),
               let tok = resp["token"] as? String, !tok.isEmpty {
                setAuthToken(tok)
                NotificationCenter.default.post(name: GoBackend.authReady, object: nil)
                return
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
    }

    /// 极简同步 HTTP JSON（在后台线程调用，用信号量等结果）。非 2xx 或解析失败返回 nil。
    private static func httpJSON(_ method: String, _ urlStr: String, _ body: [String: Any]?) -> [String: Any]? {
        guard let url = URL(string: urlStr) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.httpMethod = method
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        var out: [String: Any]?
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            defer { sem.signal() }
            guard let data, let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
            out = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }.resume()
        _ = sem.wait(timeout: .now() + 10)
        return out
    }

    /// 优雅停止（App 一般不调用；进后台时让系统挂起即可）。
    func stop() {
        guard started else { return }
        ArtexStop()
        started = false
    }
}
