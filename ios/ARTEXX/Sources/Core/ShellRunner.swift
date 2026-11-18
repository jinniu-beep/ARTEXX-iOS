import Foundation
import SwiftUI
import UIKit

/// 控制台引擎。
/// iOS 不允许 fork/exec 任意二进制（Process 不可用），因此本地模式实现了一个
/// busybox 风格的命令解释器：文件系统操作、文本处理、DNS/HTTP 探测走原生实现，
/// 语义与桌面端 shell 对齐（同一套命令名、相似输出格式）。
/// 需要真实 nmap/sqlmap 等外部工具时，把「远端」模式指向自建 ARTEXX 服务即可。
enum ConsoleKind { case input, output, error, system }

final class ShellRunner: ObservableObject {
    static let shared = ShellRunner()

    @Published private(set) var lines: [ConsoleLine] = []
    @Published private(set) var running = false
    @Published var cwd: String = ""
    private let queue = DispatchQueue(label: "artex.shell", qos: .userInitiated)

    struct ConsoleLine: Identifiable, Hashable {
        let id = UUID()
        var text: String
        var kind: ConsoleKind
    }

    init() {
        cwd = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("workspace", isDirectory: true).path
        try? FileManager.default.createDirectory(atPath: cwd, withIntermediateDirectories: true)
    }

    var root: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("workspace", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    func clear() { lines.removeAll() }

    func append(_ text: String, kind: ConsoleKind) {
        let chunks = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for c in chunks {
            lines.append(ConsoleLine(text: c, kind: kind))
        }
        if lines.count > 5000 { lines.removeFirst(lines.count - 5000) }
    }

    func run(_ command: String) {
        let raw = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        append("artex@ios:" + shortPath + "$ " + raw, kind: .input)
        running = true
        queue.async { [weak self] in
            guard let self else { return }
            let out = Interpreter(cwd: self.cwd, root: self.root).execute(raw)
            DispatchQueue.main.async {
                for (text, kind) in out { self.append(text, kind: kind) }
                self.running = false
            }
        }
    }

    var shortPath: String {
        let p = cwd
        if p == root.path { return "~" }
        return "~" + p.replacingOccurrences(of: root.path, with: "")
    }
}

/// busybox 风格解释器：支持管道 |、重定向 >、&& 与 ;。
final class Interpreter {
    let cwd: String
    let root: URL
    private var env: [String: String]

    init(cwd: String, root: URL) {
        self.cwd = cwd
        self.root = root
        var e = ProcessInfo.processInfo.environment
        e["HOME"] = root.path
        e["PWD"] = cwd
        e["TERM"] = "xterm-256color"
        e["ARTEXX_APP"] = "ios"
        env = e
    }

    func execute(_ line: String) -> [(String, ConsoleKind)] {
        var results: [(String, ConsoleKind)] = []
        // 拆 && 与 ;
        let segments = line.components(separatedBy: "&&").flatMap { $0.components(separatedBy: ";") }
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        for seg in segments {
            let (text, kind) = runPipeline(seg)
            if !text.isEmpty { results.append((text, kind)) }
        }
        return results
    }

    private func runPipeline(_ seg: String) -> (String, ConsoleKind) {
        // 重定向
        var body = seg
        var redirect: String? = nil
        if let r = seg.range(of: " > ") {
            redirect = String(seg[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            body = String(seg[..<r.lowerBound])
        } else if let r = seg.range(of: " >> ") {
            redirect = String(seg[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            body = String(seg[..<r.lowerBound])
        }

        let stages = body.components(separatedBy: " | ").map { $0.trimmingCharacters(in: .whitespaces) }
        var input = ""
        var out = ""
        var kind: ConsoleKind = .output

        for (i, stage) in stages.enumerated() {
            let (o, k) = runSingle(stage, stdin: input)
            if i == stages.count - 1 { out = o; kind = k } else { input = o }
        }

        if let redirect {
            let path = resolvePath(redirect)
            do {
                try out.write(toFile: path, atomically: true, encoding: .utf8)
                return ("已写入 " + path, .system)
            } catch {
                return ("写入失败: \(error.localizedDescription)", .error)
            }
        }
        return (out, kind)
    }

    private func runSingle(_ stage: String, stdin: String) -> (String, ConsoleKind) {
        var tokens = tokenize(stage)
        guard let cmd = tokens.first else { return ("", .output) }
        let args = Array(tokens.dropFirst())

        switch cmd {
        case "help":
            return (Self.helpText, .system)
        case "clear", "cls":
            DispatchQueue.main.async { ShellRunner.shared.clear() }
            return ("", .system)
        case "echo":
            return (args.joined(separator: " "), .output)
        case "pwd":
            return (cwd, .output)
        case "cd":
            let target = args.first ?? root.path
            let p = resolvePath(target)
            if FileManager.default.fileExists(atPath: p) {
                DispatchQueue.main.async { ShellRunner.shared.cwd = p }
                return ("-> " + p, .system)
            }
            return ("cd: 目录不存在: " + p, .error)
        case "ls":
            let p = resolvePath(args.first ?? ".")
            let items = (try? FileManager.default.contentsOfDirectory(atPath: p).sorted()) ?? []
            if items.isEmpty { return ("", .output) }
            let decorated = items.map { name -> String in
                var isDir: ObjCBool = false
                let full = p + "/" + name
                FileManager.default.fileExists(atPath: full, isDirectory: &isDir)
                if isDir.boolValue { return name + "/" }
                var size = 0
                if let attrs = try? FileManager.default.attributesOfItem(atPath: full),
                   let n = attrs[.size] as? NSNumber { size = n.intValue }
                return name + "  " + String(size)
            }
            return (decorated.joined(separator: "\n"), .output)
        case "cat":
            guard let f = args.first else { return ("cat: 缺少文件参数", .error) }
            let p = resolvePath(f)
            if let s = try? String(contentsOfFile: p, encoding: .utf8) {
                let lines = s.split(separator: "\n", omittingEmptySubsequences: false)
                return (lines.prefix(400).joined(separator: "\n"), .output)
            }
            return ("cat: 无此文件: " + p, .error)
        case "head":
            let n = Int(args.first(where: { Int($0) != nil }) ?? "10") ?? 10
            let content = stdin.isEmpty ? readFile(args.last) : stdin
            return (content.split(separator: "\n").prefix(n).joined(separator: "\n"), .output)
        case "tail":
            let n = Int(args.first(where: { Int($0) != nil }) ?? "10") ?? 10
            let content = stdin.isEmpty ? readFile(args.last) : stdin
            return (content.split(separator: "\n").suffix(n).joined(separator: "\n"), .output)
        case "wc":
            let content = stdin.isEmpty ? readFile(args.last) : stdin
            let l = content.split(separator: "\n", omittingEmptySubsequences: false).count
            return ("\(l) 行  \(content.count) 字符", .output)
        case "grep":
            guard let pat = args.first(where: { !$0.hasPrefix("-") }) else { return ("grep: 缺少模式", .error) }
            let content = stdin.isEmpty ? readFile(args.last) : stdin
            let hits = content.split(separator: "\n").filter { $0.contains(pat) }
            return (hits.joined(separator: "\n"), .output)
        case "mkdir":
            guard let d = args.first else { return ("mkdir: 缺少参数", .error) }
            try? FileManager.default.createDirectory(atPath: resolvePath(d), withIntermediateDirectories: true)
            return ("", .system)
        case "touch":
            guard let f = args.first else { return ("touch: 缺少参数", .error) }
            FileManager.default.createFile(atPath: resolvePath(f), contents: Data())
            return ("", .system)
        case "rm":
            let force = args.contains("-rf") || args.contains("-f")
            let targets = args.filter { !$0.hasPrefix("-") }
            for t in targets {
                let p = resolvePath(t)
                if FileManager.default.fileExists(atPath: p) {
                    try? FileManager.default.removeItem(atPath: p)
                } else if !force { return ("rm: 无此文件: " + p, .error) }
            }
            return ("", .system)
        case "cp":
            let t = args.filter { !$0.hasPrefix("-") }
            guard t.count >= 2 else { return ("cp: 需要源与目标", .error) }
            try? FileManager.default.copyItem(atPath: resolvePath(t[0]), toPath: resolvePath(t[1]))
            return ("", .system)
        case "mv":
            let t = args.filter { !$0.hasPrefix("-") }
            guard t.count >= 2 else { return ("mv: 需要源与目标", .error) }
            try? FileManager.default.moveItem(atPath: resolvePath(t[0]), toPath: resolvePath(t[1]))
            return ("", .system)
        case "env":
            return (env.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "\n"), .output)
        case "whoami":
            return ("artex-ios", .output)
        case "uname":
            return ("ARTEXX-iOS Darwin/\(UIDevice.current.systemVersion) arm64", .output)
        case "date":
            return (ISO8601DateFormatter().string(from: Date()), .output)
        case "cve":
            guard let kw = args.first else { return ("用法: cve <keyword>", .error) }
            let rows = CVEDatabase.shared.search(kw, limit: 25)
            if rows.isEmpty { return ("无匹配结果", .system) }
            return (rows.map { r in
                String(Int(r.score)) + "." + String(Int((r.score * 10).rounded()) % 10) + "  " + r.id + "  " + r.severity + "  " + r.vendor + "  " + String(r.title.prefix(56))
            }.joined(separator: "\n"), .output)
        case "skill":
            let kws = args.joined(separator: " ")
            let hits = SkillLibrary.shared.filtered(category: nil, query: kws).prefix(20)
            if hits.isEmpty { return ("无匹配技能", .system) }
            return (hits.map { "\($0.id)  [\($0.cat)]  \($0.n)" }.joined(separator: "\n"), .output)
        case "playbook":
            guard !args.isEmpty else { return ("用法: playbook <skillId>[,<id>...]", .error) }
            let ids = args.joined(separator: " ").split(separator: ",").map(String.init)
            let lib = SkillLibrary.shared
            var picked: [Skill] = []
            for id in ids { if let s = lib.byID(id.trimmingCharacters(in: .whitespaces)) { picked.append(s) } }
            if picked.isEmpty { return ("未找到技能", .error) }
            return (Playbook(skills: picked).shellScript, .output)
        case "dig", "nslookup", "host":
            guard let host = args.first(where: { !$0.hasPrefix("-") && $0 != cmd }) else { return ("用法: dig <domain>", .error) }
            return (DNS.resolve(host), .output)
        case "curl":
            let url = args.first { $0.hasPrefix("http") }
            guard let url else { return ("用法: curl <url>", .error) }
            let headers = args.contains("-I") || args.contains("-i")
            return (HTTPProbe.fetch(url, headersOnly: headers), .output)
        case "ping":
            return ("iOS 沙箱禁止 ICMP 原始套接字；可用 curl <http://host> 或 nmap 语义的 port <ip:port> 探测。", .system)
        case "port", "nc":
            guard let target = args.first else { return ("用法: port <host:port>", .error) }
            return (TCPProbe.check(target), .output)
        case "http":
            guard let url = args.first else { return ("用法: http <url>", .error) }
            return (HTTPProbe.fetch(url, headersOnly: false), .output)
        case "banner":
            guard let target = args.first else { return ("用法: banner <host:port>", .error) }
            return (TCPProbe.banner(target), .output)
        default:
            return ("sh: " + cmd + ": command not found（输入 help 查看内置命令；真实工具请切到『远端』模式）", .error)
        }
    }

    private func readFile(_ path: String?) -> String {
        guard let path else { return "" }
        return (try? String(contentsOfFile: resolvePath(path), encoding: .utf8)) ?? ""
    }

    private func resolvePath(_ p: String) -> String {
        if p.hasPrefix("/") { return p }
        if p == "~" { return root.path }
        if p.hasPrefix("~/") { return root.path + "/" + p.dropFirst(2) }
        return (cwd as NSString).appendingPathComponent(p)
    }

    private func tokenize(_ s: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var quote: Character? = nil
        for ch in s {
            if let q = quote {
                if ch == q { quote = nil } else { cur.append(ch) }
            } else if ch == "\"" || ch == "'" {
                quote = ch
            } else if ch == " " {
                if !cur.isEmpty { out.append(cur); cur = "" }
            } else { cur.append(ch) }
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    static let helpText = """
    ARTEXX iOS 控制台 · 内置命令（busybox 风格，语义对齐桌面端）
      文件      ls  cd  pwd  cat  head  tail  wc  grep  mkdir  touch  rm  cp  mv
      系统      help  clear  env  whoami  uname  date
      网络      dig <domain>            DNS 解析（A/AAAA/CNAME/MX/TXT/NS）
                port <host:port>       TCP 连通性探测
                banner <host:port>     读取服务 banner
                curl <url> [-I]        HTTP 请求（-I 只看响应头）
      知识库    cve <keyword>          检索内置 20 万条 CVE
                skill <keyword>        检索 319 条渗透技能
                playbook <id1,id2>     生成技能编排脚本
      管道      支持  cmd | grep xx   与  cmd > file
    真实 nmap/sqlmap/hydra 等二进制请切到『远端』模式，由自建 ARTEXX 服务执行。
    """
}

// MARK: - 原生网络探测
enum DNS {
    static func resolve(_ host: String) -> String {
        var out: [String] = []
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = 0
        var res: UnsafeMutablePointer<addrinfo>? = nil
        let rc = getaddrinfo(host, nil, &hints, &res)
        if rc != 0 { return "解析失败: \(String(cString: gai_strerror(rc)))" }
        defer { freeaddrinfo(res) }
        var p = res
        while let cur = p {
            if let sa = cur.pointee.ai_addr {
                var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(sa, cur.pointee.ai_addrlen, &buf, socklen_t(buf.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let ip = String(cString: buf)
                    if !out.contains(ip) { out.append(ip) }
                }
            }
            p = cur.pointee.ai_next
        }
        return out.isEmpty ? "无记录" : host + " -> " + out.joined(separator: ", ")
    }
}

enum TCPProbe {
    static func split(_ target: String) -> (String, UInt32)? {
        let parts = target.components(separatedBy: ":")
        guard parts.count == 2, let port = UInt32(parts[1]) else { return nil }
        return (parts[0], port)
    }

    static func check(_ target: String) -> String {
        guard let (host, port) = split(target) else { return "格式错误，应为 host:port" }
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = 0
        var res: UnsafeMutablePointer<addrinfo>? = nil
        guard getaddrinfo(host, String(port), &hints, &res) == 0, let info = res else { return "解析失败" }
        defer { freeaddrinfo(res) }
        let fd = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
        if fd < 0 { return "socket 创建失败" }
        defer { close(fd) }
        let start = Date()
        let rc = connect(fd, info.pointee.ai_addr, info.pointee.ai_addrlen)
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        return rc == 0 ? "\(target) 开放 (\(ms)ms)" : "\(target) 关闭/过滤 (\(ms)ms)"
    }

    static func banner(_ target: String) -> String {
        guard let (host, port) = split(target) else { return "格式错误，应为 host:port" }
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = 0
        var res: UnsafeMutablePointer<addrinfo>? = nil
        guard getaddrinfo(host, String(port), &hints, &res) == 0, let info = res else { return "解析失败" }
        defer { freeaddrinfo(res) }
        let fd = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
        guard fd >= 0 else { return "socket 创建失败" }
        defer { close(fd) }
        guard connect(fd, info.pointee.ai_addr, info.pointee.ai_addrlen) == 0 else { return "连接失败" }
        var buf = [UInt8](repeating: 0, count: 1024)
        let n = recv(fd, &buf, buf.count, 0)
        guard n > 0 else { return "无 banner 返回（该服务可能等待客户端先说话）" }
        return String(decoding: buf[0..<n], as: UTF8.self)
    }
}

enum HTTPProbe {
    static func fetch(_ urlStr: String, headersOnly: Bool) -> String {
        guard let url = URL(string: urlStr) else { return "URL 无效" }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        if headersOnly { req.httpMethod = "HEAD" }
        let sem = DispatchSemaphore(value: 0)
        var out = "请求超时"
        URLSession.shared.dataTask(with: req) { data, resp, err in
            defer { sem.signal() }
            if let err { out = "错误: \(err.localizedDescription)"; return }
            guard let http = resp as? HTTPURLResponse else { out = "无响应"; return }
            var s = "HTTP \(http.statusCode)\n"
            for (k, v) in http.allHeaderFields { s += "\(k): \(v)\n" }
            if let data, !headersOnly {
                s += "\n" + String(decoding: data.prefix(6000), as: UTF8.self)
            }
            out = s
        }.resume()
        _ = sem.wait(timeout: .now() + 25)
        return out
    }
}
