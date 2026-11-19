import Foundation

/// 内置真·Go 后端（libartex.a）。在 App 内启动原版 ARTEXX 服务端，监听 127.0.0.1:port，
/// 由它提供真实 /api 接口 + 内置 Web UI（从 App Bundle 的 webui/ 读取），SQLite 作数据层。
/// 启动失败时由调用方回落到 Swift 版 `EmbeddedServer`。
final class GoBackend {
    static let shared = GoBackend()
    private(set) var started = false

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

    /// 启动后端。成功返回 true（服务已绑定并在应答），失败返回 false。
    @discardableResult
    func start(port: Int32 = 8787) -> Bool {
        guard !started else { return true }
        let data = GoBackend.dataDir()
        let web = GoBackend.webuiDir()
        let rc = data.withCString { d in
            web.withCString { w in
                ArtexStart(port, UnsafeMutablePointer(mutating: d), UnsafeMutablePointer(mutating: w))
            }
        }
        started = (rc == 0)
        return started
    }

    /// 优雅停止（App 一般不调用；进后台时让系统挂起即可）。
    func stop() {
        guard started else { return }
        ArtexStop()
        started = false
    }
}
