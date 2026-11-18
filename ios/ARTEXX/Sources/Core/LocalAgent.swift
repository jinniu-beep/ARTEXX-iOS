import Foundation
import SwiftUI

/// 本地 Agent：在手机上直接跑「规划 → 调工具 → 观察 → 再规划」循环。
/// 工具全部由 iOS 原生网络实现，不依赖任何后端。
@MainActor
final class LocalAgent: ObservableObject {
    static let shared = LocalAgent()

    @Published private(set) var running = false
    @Published private(set) var steps: [AgentStep] = []
    @Published private(set) var findings: [LocalFinding] = []
    @Published private(set) var assets: [String] = []
    @Published var currentTask: String = ""
    @Published var lastError: String?

    struct AgentStep: Identifiable, Hashable {
        let id = UUID()
        var index: Int
        var role: String       // plan / tool / result / final
        var title: String
        var detail: String
        var ts: Date = Date()
    }

    struct LocalFinding: Identifiable, Hashable {
        let id = UUID()
        var title: String
        var severity: String
        var asset: String
        var detail: String
        var cveId: String?
        var ts: Date = Date()
    }

    private var history: [LLMMessage] = []
    private var stepIndex = 0

    // MARK: - 系统提示词
    private var systemPrompt: String {
        """
        你是 ARTEXX 的自主渗透测试 Agent，运行在 iPhone 上，通过 iOS 原生网络直接测试目标。
        规划时先做侦察（DNS/端口/指纹），再按指纹匹配技能库与 CVE 知识库，最后给出验证结论。

        可用工具：
        - dns_resolve(host)                    解析域名
        - scan_ports(host, ports?)             端口扫描（默认常用端口）
        - http_probe(url)                      HTTP 指纹（状态码/标题/Server/技术栈）
        - subdomain_enum(domain)               子域枚举
        - search_skills(keyword)               检索内置 (SkillLibrary.shared.all.count) 条渗透技能
        - search_cve(keyword, min_score?)      检索内置 20 万条 CVE（含四段式攻击指引）
        - report_finding(title, severity, asset, detail, cve_id?)  记录漏洞
        - list_assets()                        查看已发现资产

        规则：
        1. 每次只调 1~3 个工具，看到结果再决定下一步。
        2. 发现 open 端口后必须做 http_probe 拿指纹。
        3. 拿到指纹就去 search_cve 查对应漏洞，不要凭记忆编造 CVE。
        4. 只对授权目标操作；每条发现都要能对应到具体资产。
        5. 结束时用中文总结：目标、开放端口、技术栈、可能漏洞、下一步建议。
        """
    }

    // MARK: - 工具定义（OpenAI 格式）
    private var toolSchemas: [[String: Any]] {
        func fn(_ name: String, _ desc: String, _ props: [String: Any], _ required: [String]) -> [String: Any] {
            ["type": "function", "function": [
                "name": name, "description": desc,
                "parameters": ["type": "object", "properties": props, "required": required],
            ]]
        }
        let s: (String) -> [String: Any] = { ["type": "string", "description": $0] }
        return [
            fn("dns_resolve", "解析域名的 A/AAAA 记录", ["host": s("域名或主机名")], ["host"]),
            fn("scan_ports", "TCP 端口扫描，返回开放端口与 banner",
               ["host": s("IP 或域名"),
                "ports": ["type": "array", "items": ["type": "integer"], "description": "端口列表，留空则扫常用端口"]],
               ["host"]),
            fn("http_probe", "HTTP 指纹探测，返回状态码、标题、Server、技术栈",
               ["url": s("完整 URL，如 http://1.2.3.4:80")], ["url"]),
            fn("subdomain_enum", "子域枚举", ["domain": s("主域名")], ["domain"]),
            fn("search_skills", "检索内置渗透技能库", ["keyword": s("关键词，如 sql注入 / tomcat / 提权")], ["keyword"]),
            fn("search_cve", "检索内置 CVE 知识库",
               ["keyword": s("产品名或 CVE 编号"),
                "min_score": ["type": "number", "description": "CVSS 下限，默认 7"]],
               ["keyword"]),
            fn("report_finding", "记录一条漏洞发现",
               ["title": s("漏洞标题"), "severity": s("critical/high/medium/low"),
                "asset": s("受影响资产"), "detail": s("复现依据与证据"),
                "cve_id": s("关联 CVE，可选")],
               ["title", "severity", "asset", "detail"]),
            fn("list_assets", "列出本次已发现的资产", [:], []),
        ]
    }

    // MARK: - 主循环
    func start(objective: String, maxSteps: Int = 12) {
        guard !running else { return }
        guard LLMClient.shared.config.ready else {
            lastError = "请先到「模型」页配置 API Key"
            return
        }
        running = true
        lastError = nil
        steps.removeAll()
        findings.removeAll()
        assets.removeAll()
        stepIndex = 0
        currentTask = objective
        history = [
            LLMMessage(role: "system", content: systemPrompt),
            LLMMessage(role: "user", content: "任务目标：\(objective)\n请开始。"),
        ]

        Task { await loop(maxSteps: maxSteps) }
    }

    func stop() { running = false }

    private func loop(maxSteps: Int) async {
        var step = 0
        while running && step < maxSteps {
            step += 1
            do {
                let reply = try await LLMClient.shared.complete(messages: history, tools: toolSchemas)

                if !reply.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    append(role: "plan", title: "思考", detail: reply.content)
                }

                if reply.toolCalls.isEmpty {
                    append(role: "final", title: "结论", detail: reply.content)
                    running = false
                    return
                }

                // assistant 回合（含工具调用意图）
                history.append(LLMMessage(role: "assistant", content: reply.content.isEmpty ? " " : reply.content))

                for call in reply.toolCalls {
                    guard running else { return }
                    append(role: "tool", title: call.name, detail: call.arguments)
                    let result = await execute(call)
                    append(role: "result", title: call.name + " 结果", detail: String(result.prefix(1200)))
                    history.append(LLMMessage(role: "user", content: "[工具 \(call.name) 返回]\n\(result)"))
                }
            } catch {
                lastError = error.localizedDescription
                append(role: "final", title: "中断", detail: error.localizedDescription)
                running = false
                return
            }
        }
        running = false
    }

    private func append(role: String, title: String, detail: String) {
        stepIndex += 1
        steps.append(AgentStep(index: stepIndex, role: role, title: title, detail: detail))
    }

    // MARK: - 工具执行
    private func execute(_ call: ToolCall) async -> String {
        let args = (try? JSONSerialization.jsonObject(with: Data(call.arguments.utf8)) as? [String: Any]) ?? [:]

        switch call.name {
        case "dns_resolve":
            let host = args["host"] as? String ?? ""
            let r = NativeScanner.resolve(host)
            return r.addresses.isEmpty ? "\(host) 无解析结果" : "\(host) → " + r.addresses.joined(separator: ", ")

        case "scan_ports":
            let host = args["host"] as? String ?? ""
            var ports = NativeScanner.topPorts
            if let list = args["ports"] as? [Int], !list.isEmpty {
                ports = list.compactMap { UInt16(exactly: $0) }
            }
            let results = NativeScanner.scanPorts(host: host, ports: ports, timeout: 1.5, concurrency: 64)
            if results.isEmpty { return "\(host) 在 \(ports.count) 个端口上无开放" }
            for r in results {
                let a = "\(host):\(r.port)"
                if !assets.contains(a) { assets.append(a) }
            }
            return results.map { r in
                "\(r.port)/tcp open \(r.ms)ms" + (r.banner.map { " | " + $0.prefix(80) } ?? "")
            }.joined(separator: "\n")

        case "http_probe":
            let url = args["url"] as? String ?? ""
            guard let fp = NativeScanner.fingerprint(url) else { return "\(url) 探测失败" }
            if !assets.contains(url) { assets.append(url) }
            var out = "HTTP \(fp.status)\n"
            if let t = fp.title { out += "标题: \(t)\n" }
            if let s = fp.server { out += "Server: \(s)\n" }
            if let p = fp.poweredBy { out += "X-Powered-By: \(p)\n" }
            if !fp.tech.isEmpty { out += "技术栈: " + fp.tech.joined(separator: ", ") + "\n" }
            return out

        case "subdomain_enum":
            let domain = args["domain"] as? String ?? ""
            let found = NativeScanner.enumerateSubdomains(domain: domain)
            if found.isEmpty { return "\(domain) 未发现子域" }
            for (h, _) in found where !assets.contains(h) { assets.append(h) }
            return found.map { "\($0.key) → " + $0.value.joined(separator: ",") }.joined(separator: "\n")

        case "search_skills":
            let kw = args["keyword"] as? String ?? ""
            let hits = SkillLibrary.shared.filtered(category: nil, query: kw).prefix(6)
            if hits.isEmpty { return "无匹配技能" }
            return hits.map { s in
                "[\(s.id)] \(s.n) | \(s.cat) | \(s.d)\n  命令: " + s.cmds.joined(separator: " ; ")
            }.joined(separator: "\n\n")

        case "search_cve":
            let kw = args["keyword"] as? String ?? ""
            let minScore = args["min_score"] as? Double ?? 7.0
            let rows = CVEDatabase.shared.search(kw, minScore: minScore, limit: 8)
            if rows.isEmpty { return "无匹配 CVE（\(kw)）" }
            var out: [String] = []
            for r in rows {
                var block = "\(r.id) | CVSS \(String(format: "%.1f", r.score)) \(r.severity) | \(r.vendor)\n\(r.title)"
                if let g = CVEDatabase.shared.guidance(r.id) {
                    block += "\n  类型: \(g.type)"
                    block += "\n  前提: " + g.prereq.prefix(2).joined(separator: " / ")
                    block += "\n  载荷: " + (g.payload.first ?? "")
                }
                out.append(block)
            }
            return out.joined(separator: "\n\n---\n\n")

        case "report_finding":
            let f = LocalFinding(
                title: args["title"] as? String ?? "未命名",
                severity: args["severity"] as? String ?? "info",
                asset: args["asset"] as? String ?? "-",
                detail: args["detail"] as? String ?? "",
                cveId: args["cve_id"] as? String
            )
            findings.append(f)
            return "已记录：\(f.title)（\(f.severity)）@ \(f.asset)"

        case "list_assets":
            return assets.isEmpty ? "暂无资产" : assets.joined(separator: "\n")

        default:
            return "未知工具：\(call.name)"
        }
    }
}
