import Foundation

// MARK: - 服务器配置（对齐 ARTEXX 后端 http://host:8787 + /api + Bearer JWT）
struct ServerConfig: Codable, Equatable {
    var baseURL: String = "http://127.0.0.1:8787"
    var token: String = ""
    var proxyURL: String = "http://127.0.0.1:8788"
    var gatewayMode: Bool = false      // true = 本机跑 gateway（iSH），false = 直连远端
    var gatewayPort: Int = 8787

    static let storageKey = "artex.server.config"
    static func load() -> ServerConfig {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let cfg = try? JSONDecoder().decode(ServerConfig.self, from: data) else { return ServerConfig() }
        return cfg
    }
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: ServerConfig.storageKey)
        }
    }
    var effectiveBase: String {
        if gatewayMode { return "http://127.0.0.1:\(gatewayPort)" }
        return baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    // MARK: - 地址辅助
    static func isLoopback(_ s: String) -> Bool {
        let t = s.lowercased()
        return t.contains("127.0.0.1") || t.contains("localhost") || t.contains("0.0.0.0")
    }

    static let recentKey = "artex.recent.addresses"
    static var recentAddresses: [String] {
        UserDefaults.standard.stringArray(forKey: recentKey) ?? []
    }
    static func remember(_ addr: String) {
        guard !addr.isEmpty else { return }
        var list = UserDefaults.standard.stringArray(forKey: recentKey) ?? []
        list.removeAll { $0 == addr }
        list.insert(addr, at: 0)
        UserDefaults.standard.set(Array(list.prefix(5)), forKey: recentKey)
    }

    /// 把系统错误翻译成人话
    static func humanize(_ raw: String) -> String {
        let t = raw.lowercased()
        if t.contains("超时") || t.contains("timed out") || t.contains("timeout") {
            return "连接超时：目标服务没响应。若填 127.0.0.1，请确认内置服务已启动"
        }
        if t.contains("拒绝") || t.contains("refused") || t.contains("could not connect") {
            return "连接被拒绝：服务器端口没开放，确认用 -addr :8787 启动"
        }
        if t.contains("找不到") || t.contains("not found") || t.contains("unsupported url") {
            return "地址格式不对，应形如 http://192.168.1.10:8787"
        }
        if t.contains("certificate") || t.contains("ssl") || t.contains("tls") {
            return "证书校验失败：自签证书需要先在系统里信任"
        }
        if t.contains("未授权") || t.contains("401") {
            return "密码错误或会话过期，请重新输入管理员密码"
        }
        return raw
    }
}

enum APIError: LocalizedError {
    case badURL(String)
    case http(Int, String)
    case decode(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .badURL(let s): return "URL 无效: \(s)"
        case .http(let c, let m): return "HTTP \(c): \(m)"
        case .decode(let m): return "解析失败: \(m)"
        case .transport(let m): return "网络错误: \(m)"
        }
    }
}

// MARK: - 客户端
final class APIClient {
    static let shared = APIClient()
    var config: ServerConfig = ServerConfig.load()
    static let serial = DispatchQueue(label: "artex.api.config")
    private let session: URLSession

    /// 常规请求会话（可等待网络恢复，但单请求有硬超时）
    private let probeSession: URLSession

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 120
        cfg.waitsForConnectivity = false      // 关键：不可达要立刻失败，不能挂住
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: cfg)

        // 探测专用：3 秒连不上就当失败，用于启动判断
        let p = URLSessionConfiguration.ephemeral
        p.timeoutIntervalForRequest = 3
        p.timeoutIntervalForResource = 5
        p.waitsForConnectivity = false
        probeSession = URLSession(configuration: p)
    }

    /// 轻量探活：3 秒内必须给出结论（成功或失败），绝不挂起
    func probe(path: String = "auth/status") async -> Bool {
        guard let url = URL(string: config.effectiveBase + "/api/" + path) else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 3
        if !config.token.isEmpty {
            req.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (_, resp) = try await probeSession.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return false }
            // 401 说明服务活着，只是 token 过期
            return (200..<500).contains(http.statusCode)
        } catch {
            return false
        }
    }

    func update(_ cfg: ServerConfig) { config = cfg; cfg.save() }

    private func request(path: String, method: String = "GET", body: Data? = nil, query: [String: String]? = nil) throws -> URLRequest {
        var comps = URLComponents(string: config.effectiveBase)
        guard comps != nil else { throw APIError.badURL(config.effectiveBase) }
        comps!.path = "/api" + (path.hasPrefix("/") ? path : "/" + path)
        if let query, !query.isEmpty {
            comps!.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = comps?.url else { throw APIError.badURL(path) }
        var req = URLRequest(url: url)
        req.httpMethod = method
        if !config.token.isEmpty {
            req.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return req
    }

    private func send(_ req: URLRequest) async throws -> Data {
        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return data }
            if http.statusCode == 401 { throw APIError.http(401, "未授权，请重新登录") }
            if http.statusCode >= 400 {
                let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
                    ?? String(data: data, encoding: .utf8)?.prefix(200).description ?? "请求失败"
                throw APIError.http(http.statusCode, msg)
            }
            return data
        } catch let e as APIError {
            throw e
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
    }

    func raw(path: String, method: String = "GET", query: [String: String]? = nil, json: Any? = nil) async throws -> Data {
        var body: Data? = nil
        if let json {
            body = try? JSONSerialization.data(withJSONObject: json, options: [])
        }
        let req = try request(path: path, method: method, body: body, query: query)
        return try await send(req)
    }

    func get<T: Decodable>(_ path: String, query: [String: String]? = nil, as type: T.Type) async throws -> T {
        let data = try await raw(path: path, query: query)
        return try decode(data, type)
    }

    func send<T: Decodable>(_ path: String, method: String = "POST", json: Any? = nil, as type: T.Type) async throws -> T {
        let data = try await raw(path: path, method: method, json: json)
        return try decode(data, type)
    }

    func decode<T: Decodable>(_ data: Data, _ type: T.Type) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch let e as DecodingError {
            throw APIError.decode("\(e)")
        }
    }

    // 宽松数组：后端有时返回 {items:[...]} 或直接 []
    func list<T: Decodable>(_ path: String, query: [String: String]? = nil, as type: T.Type) async throws -> [T] {
        let data = try await raw(path: path, query: query)
        if let arr = try? JSONDecoder().decode([T].self, from: data) { return arr }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["items", "data", "list", "tasks", "assets", "findings", "records", "skills", "agents", "tools", "profiles"] {
                if let sub = obj[key], JSONSerialization.isValidJSONObject(sub),
                   let subData = try? JSONSerialization.data(withJSONObject: sub) {
                    if let arr = try? JSONDecoder().decode([T].self, from: subData) { return arr }
                }
            }
        }
        return []
    }

    // 任意 JSON 字典（用于尚未建模的端点）
    func dict(_ path: String, query: [String: String]? = nil) async throws -> [String: AnyJSON] {
        let data = try await raw(path: path, query: query)
        if let d = try? JSONDecoder().decode([String: AnyJSON].self, from: data) { return d }
        return [:]
    }
}
