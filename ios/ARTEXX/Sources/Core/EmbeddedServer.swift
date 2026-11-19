import Foundation
import Network

/// 内置 ARTEXX 服务端：在 App 内监听 127.0.0.1:8787，
/// 让客户端可以像连远端一样连「手机自己」。
/// 数据全部来自本地（LocalTaskStore / CVEDatabase / SkillLibrary / NativeScanner）。
final class EmbeddedServer {
    static let shared = EmbeddedServer()

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "artex.server", qos: .userInitiated)
    private(set) var running = false
    private(set) var port: UInt16 = 8787
    private(set) var lastError: String?
    /// 极简鉴权：密码存本地，token 用固定派生值
    private let passwordKey = "artex.server.password"
    private let tokenKey = "artex.server.token"

    // MARK: - 生命周期
    /// 只绑 127.0.0.1：Web UI 与内置客户端都在本机，
    /// 绑回环既不需要「本地网络」权限弹窗，也不会把服务暴露到局域网。
    func start(port: UInt16 = 8787) {
        guard !running else { return }
        self.port = port
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
            params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: nwPort)
            let l = try NWListener(using: params)
            l.newConnectionHandler = { [weak self] conn in
                self?.handle(conn)
            }
            l.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.running = true
                    self?.lastError = nil
                    NSLog("[ARTEXX] 内置服务已启动 127.0.0.1:\(port)")
                case .failed(let e):
                    self?.running = false
                    self?.lastError = e.localizedDescription
                    NSLog("[ARTEXX] 内置服务失败: \(e.localizedDescription)")
                default: break
                }
            }
            listener = l
            l.start(queue: queue)
        } catch {
            lastError = error.localizedDescription
            NSLog("[ARTEXX] 无法监听 \(port): \(error.localizedDescription)")
        }
    }

    /// 给 Web UI 注入用的 token（首次访问时生成，保证前端能直接进入主界面）
    var token: String {
        if let t = UserDefaults.standard.string(forKey: tokenKey), !t.isEmpty { return t }
        let t = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        UserDefaults.standard.set(t, forKey: tokenKey)
        return t
    }

    func stop() {
        listener?.cancel()
        listener = nil
        running = false
    }

    // MARK: - 连接处理
    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(conn, buffer: Data())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buf = buffer
            if let data { buf.append(data) }

            // 请求头收齐？
            if let range = buf.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = buf.subdata(in: buf.startIndex..<range.lowerBound)
                let headerText = String(decoding: headerData, as: UTF8.self)
                let lines = headerText.components(separatedBy: "\r\n")
                guard let requestLine = lines.first else { conn.cancel(); return }
                let parts = requestLine.components(separatedBy: " ")
                guard parts.count >= 2 else { conn.cancel(); return }
                let method = parts[0]
                let fullPath = parts[1]

                // Content-Length
                var contentLength = 0
                for l in lines.dropFirst() {
                    let kv = l.components(separatedBy: ":")
                    if kv.count == 2, kv[0].lowercased() == "content-length" {
                        contentLength = Int(kv[1].trimmingCharacters(in: .whitespaces)) ?? 0
                    }
                }
                let bodyStart = range.upperBound
                let haveBody = buf.distance(from: bodyStart, to: buf.endIndex)
                if haveBody < contentLength {
                    self.receive(conn, buffer: buf)
                    return
                }
                let body = buf.subdata(in: bodyStart..<buf.index(bodyStart, offsetBy: contentLength))

                // 异步处理并回包
                DispatchQueue.main.async {
                    let (status, payload, contentType) = Router.handle(method: method, path: fullPath, body: body)
                    self.respond(conn, status: status, body: payload, contentType: contentType,
                                 headOnly: method == "HEAD")
                }
            } else if isComplete || error != nil {
                conn.cancel()
            } else {
                self.receive(conn, buffer: buf)
            }
        }
    }

    private func respond(_ conn: NWConnection, status: Int, body: Data, contentType: String, headOnly: Bool = false) {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 201: reason = "Created"
        case 204: reason = "No Content"
        case 400: reason = "Bad Request"
        case 401: reason = "Unauthorized"
        case 404: reason = "Not Found"
        default: reason = "Error"
        }
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Access-Control-Allow-Origin: *\r\n"
        head += "Access-Control-Allow-Headers: *\r\n"
        head += "Access-Control-Allow-Methods: GET,POST,PUT,PATCH,DELETE,HEAD,OPTIONS\r\n"
        head += "Cache-Control: no-store\r\n"
        head += "Connection: close\r\n\r\n"
        var out = Data(head.utf8)
        if !headOnly { out.append(body) }
        conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
    }

    // MARK: - 鉴权
    var hasPassword: Bool { UserDefaults.standard.string(forKey: passwordKey) != nil }

    /// 密码只决定「能不能改配置」，token 一旦生成就固定，
    /// 否则每次登录都会让 Web UI 里注入的 token 失效。
    @discardableResult
    func setPassword(_ p: String) -> String {
        UserDefaults.standard.set(p, forKey: passwordKey)
        return token
    }

    func verify(_ p: String) -> String? {
        guard UserDefaults.standard.string(forKey: passwordKey) == p else { return nil }
        if let t = UserDefaults.standard.string(forKey: tokenKey) { return t }
        return setPassword(p)
    }
}
