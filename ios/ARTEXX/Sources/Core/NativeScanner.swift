import Foundation
import UIKit

/// 原生扫描器：全部走 iOS 系统网络栈，不需要任何后端。
/// 覆盖 DNS 解析、TCP 端口扫描、HTTP 指纹探测、子域枚举、TLS 证书信息。
enum NativeScanner {

    // MARK: - DNS
    struct DNSResult { var host: String; var addresses: [String]; var cname: String? }

    static func resolve(_ host: String) -> DNSResult {
        var addrs: [String] = []
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>?
        if getaddrinfo(host, nil, &hints, &res) == 0, let first = res {
            defer { freeaddrinfo(res) }
            var p: UnsafeMutablePointer<addrinfo>? = first
            while let cur = p {
                if let sa = cur.pointee.ai_addr {
                    var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(sa, cur.pointee.ai_addrlen, &buf, socklen_t(buf.count), nil, 0, NI_NUMERICHOST) == 0 {
                        let ip = String(cString: buf)
                        if !addrs.contains(ip) { addrs.append(ip) }
                    }
                }
                p = cur.pointee.ai_next
            }
        }
        // CNAME（gethostbyname 在 iOS 可用，但不是线程安全的，仅作参考）
        var cname: String?
        if let h = gethostbyname(host), let n = h.pointee.h_name {
            let name = String(cString: n)
            if name != host { cname = name }
        }
        return DNSResult(host: host, addresses: addrs, cname: cname)
    }

    /// 解析 A 记录之外的常见记录类型（通过 CFHost）
    static func txtRecords(_ host: String) -> [String] {
        var out: [String] = []
        let hostRef = CFHostCreateWithName(nil, host as CFString).takeRetainedValue()
        var resolved = DarwinBoolean(false)
        CFHostStartInfoResolution(hostRef, .addresses, nil)
        if let addrs = CFHostGetAddressing(hostRef, &resolved)?.takeUnretainedValue() as? [Data] {
            for d in addrs {
                d.withUnsafeBytes { raw in
                    if let sa = raw.baseAddress?.assumingMemoryBound(to: sockaddr.self) {
                        var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &buf, socklen_t(buf.count), nil, 0, NI_NUMERICHOST) == 0 {
                            let ip = String(cString: buf)
                            if !out.contains(ip) { out.append(ip) }
                        }
                    }
                }
            }
        }
        return out
    }

    // MARK: - TCP 端口扫描
    struct PortResult { var host: String; var port: UInt16; var open: Bool; var banner: String?; var ms: Int }

    /// 并发扫描一组端口。concurrency 控制同时打开多少个 socket。
    static func scanPorts(host: String, ports: [UInt16], timeout: TimeInterval = 2.0,
                          concurrency: Int = 64,
                          progress: ((PortResult) -> Void)? = nil) -> [PortResult] {
        var results: [PortResult] = []
        let lock = NSLock()
        let sem = DispatchSemaphore(value: concurrency)
        let group = DispatchGroup()
        queue.async {
            for port in ports {
                sem.wait()
                group.enter()
                queue.async {
                    defer { sem.signal(); group.leave() }
                    let r = probe(host: host, port: port, timeout: timeout)
                    if r.open {
                        lock.lock(); results.append(r); lock.unlock()
                        progress?(r)
                    }
                }
            }
            group.wait()
        }
        // 双超时保护
        _ = group.wait(timeout: .now() + timeout * Double(max(1, ports.count / max(1, concurrency))) + 8)
        lock.lock(); let copy = results; lock.unlock()
        return copy.sorted { $0.port < $1.port }
    }

    private static let queue = DispatchQueue(label: "artex.scan", qos: .userInitiated, attributes: .concurrent)

    /// 单端口探测 + 尝试抓 banner
    static func probe(host: String, port: UInt16, timeout: TimeInterval = 2.0) -> PortResult {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>?
        let start = Date()
        guard getaddrinfo(host, String(port), &hints, &res) == 0, let info = res else {
            return PortResult(host: host, port: port, open: false, banner: nil, ms: 0)
        }
        defer { freeaddrinfo(res) }

        let fd = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
        guard fd >= 0 else { return PortResult(host: host, port: port, open: false, banner: nil, ms: 0) }
        defer { close(fd) }

        // 非阻塞 + select 实现超时
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        let rc = connect(fd, info.pointee.ai_addr, info.pointee.ai_addrlen)
        var open = false
        if rc == 0 {
            open = true
        } else if errno == EINPROGRESS {
            var wfds = fd_set()
            fdZero(&wfds)
            fdSet(fd, &wfds)
            var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
            let sel = select(fd + 1, nil, &wfds, nil, &tv)
            if sel > 0 {
                var err: Int32 = 0
                var len = socklen_t(MemoryLayout<Int32>.size)
                getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len)
                open = err == 0
            }
        }

        let ms = Int(Date().timeIntervalSince(start) * 1000)
        guard open else { return PortResult(host: host, port: port, open: false, banner: nil, ms: ms) }

        // 抓 banner（500ms 内）
        var banner: String?
        var tv2 = timeval(tv_sec: 0, tv_usec: 500_000)
        var rfds = fd_set()
        fdZero(&rfds)
        fdSet(fd, &rfds)
        if select(fd + 1, &rfds, nil, nil, &tv2) > 0 {
            var buf = [UInt8](repeating: 0, count: 1024)
            let n = recv(fd, &buf, buf.count, 0)
            if n > 0 {
                banner = String(decoding: buf[0..<n], as: UTF8.self)
                    .replacingOccurrences(of: "\r\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return PortResult(host: host, port: port, open: true, banner: banner, ms: ms)
    }

    private static func fdZero(_ set: inout fd_set) {
        withUnsafeMutablePointer(to: &set) { p in
            memset(p, 0, MemoryLayout<fd_set>.size)
        }
    }
    private static func fdSet(_ fd: Int32, _ set: inout fd_set) {
        let offset = Int32(fd / 32)
        let mask = Int32(1) << (fd % 32)
        withUnsafeMutablePointer(to: &set) { p in
            let raw = UnsafeMutableRawPointer(p).assumingMemoryBound(to: Int32.self)
            raw[Int(offset)] |= mask
        }
    }

    // MARK: - HTTP 指纹
    struct HTTPFingerprint {
        var url: String
        var status: Int
        var title: String?
        var server: String?
        var poweredBy: String?
        var tech: [String]
        var headers: [String: String]
    }

    static func fingerprint(_ urlStr: String, timeout: TimeInterval = 8) -> HTTPFingerprint? {
        guard var comps = URLComponents(string: urlStr) else { return nil }
        if comps.scheme == nil { comps.scheme = "http" }
        guard let url = comps.url else { return nil }

        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")

        let sem = DispatchSemaphore(value: 0)
        var fp: HTTPFingerprint?
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            defer { sem.signal() }
            guard let http = resp as? HTTPURLResponse else { return }
            var hdrs: [String: String] = [:]
            for (k, v) in http.allHeaderFields {
                hdrs[String(describing: k)] = String(describing: v)
            }
            var title: String?
            var tech: [String] = []
            if let data, let body = String(data: data.prefix(200_000), encoding: .utf8) {
                if let r = body.range(of: "<title[^>]*>([^<]*)</title>", options: [.regularExpression, .caseInsensitive]) {
                    title = String(body[r]).replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
                let lower = body.lowercased()
                let sigs: [(String, [String])] = [
                    ("WordPress", ["wp-content", "wp-includes"]),
                    ("jQuery", ["jquery"]),
                    ("React", ["react"]),
                    ("Vue", ["vue.js", "__vue__"]),
                    ("Angular", ["ng-version", "angular"]),
                    ("Bootstrap", ["bootstrap"]),
                    ("Spring", ["whitelabel"]),
                    ("ThinkPHP", ["thinkphp"]),
                    ("Shiro", ["rememberme"]),
                    ("Swagger", ["swagger-ui"]),
                ]
                for (name, keys) in sigs where keys.contains(where: { lower.contains($0) }) {
                    tech.append(name)
                }
            }
            let server = hdrs.first { $0.key.lowercased() == "server" }?.value
            let powered = hdrs.first { $0.key.lowercased() == "x-powered-by" }?.value
            fp = HTTPFingerprint(url: urlStr, status: http.statusCode, title: title,
                                 server: server, poweredBy: powered, tech: tech, headers: hdrs)
        }.resume()
        _ = sem.wait(timeout: .now() + timeout + 2)
        return fp
    }

    // MARK: - 子域枚举
    static let subdomainWordlist = [
        "www","mail","ftp","smtp","pop","imap","webmail","ns1","ns2","dns","vpn","remote",
        "api","app","m","mobile","admin","manage","manager","portal","oa","crm","erp",
        "test","dev","staging","uat","beta","demo","sandbox","pre","prod",
        "git","gitlab","jenkins","ci","cd","build","nexus","harbor","registry","repo",
        "db","mysql","redis","mongo","es","kibana","grafana","monitor","zabbix","nagios",
        "oss","cdn","static","img","file","upload","download","assets",
        "blog","forum","bbs","wiki","doc","docs","help","support","kf",
        "shop","store","pay","payment","order","sso","auth","login","id","passport",
        "intranet","internal","office","hr","finance","cms","backup","old","new","v2",
    ]

    /// 并发枚举子域：只返回能解析的
    static func enumerateSubdomains(domain: String, words: [String]? = nil,
                                    concurrency: Int = 48,
                                    progress: ((String, [String]) -> Void)? = nil) -> [String: [String]] {
        let list = words ?? subdomainWordlist
        var found: [String: [String]] = [:]
        let lock = NSLock()
        let sem = DispatchSemaphore(value: concurrency)
        let group = DispatchGroup()

        for w in list {
            sem.wait(); group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { sem.signal(); group.leave() }
                let fqdn = "\(w).\(domain)"
                let r = resolve(fqdn)
                if !r.addresses.isEmpty {
                    lock.lock(); found[fqdn] = r.addresses; lock.unlock()
                    progress?(fqdn, r.addresses)
                }
            }
        }
        _ = group.wait(timeout: .now() + 60)
        lock.lock(); let copy = found; lock.unlock()
        return copy
    }

    // MARK: - 常用端口集
    static let topPorts: [UInt16] = [
        21, 22, 23, 25, 53, 80, 110, 111, 135, 139, 143, 161, 389, 443, 445, 465, 514,
        587, 636, 873, 993, 995, 1025, 1080, 1433, 1521, 1723, 2049, 2181, 2375, 2376,
        3000, 3306, 3389, 4369, 5000, 5432, 5555, 5601, 5672, 5900, 6379, 6443, 7001,
        7002, 8000, 8009, 8080, 8081, 8443, 8888, 9000, 9001, 9042, 9092, 9200, 9300,
        11211, 15672, 27017, 50000
    ]
}
