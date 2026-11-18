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
    func start(port: UInt16 = 8787) {
        guard !running else { return }
        self.port = port
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            params.requiredInterfaceType = .loopback
            let l = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
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
                    self.respond(conn, status: status, body: payload, contentType: contentType)
                }
            } else if isComplete || error != nil {
                conn.cancel()
            } else {
                self.receive(conn, buffer: buf)
            }
        }
    }

    private func respond(_ conn: NWConnection, status: Int, body: Data, contentType: String) {
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
        head += "Connection: close\r\n\r\n"
        var out = Data(head.utf8)
        out.append(body)
        conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
    }

    // MARK: - 鉴权
    var hasPassword: Bool { UserDefaults.standard.string(forKey: passwordKey) != nil }

    @discardableResult
    func setPassword(_ p: String) -> String {
        UserDefaults.standard.set(p, forKey: passwordKey)
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        UserDefaults.standard.set(token, forKey: tokenKey)
        return token
    }

    func verify(_ p: String) -> String? {
        guard UserDefaults.standard.string(forKey: passwordKey) == p else { return nil }
        if let t = UserDefaults.standard.string(forKey: tokenKey) { return t }
        return setPassword(p)
    }
}
