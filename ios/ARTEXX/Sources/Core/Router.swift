import Foundation

/// 请求路由：返回 (状态码, JSON 数据, Content-Type)
/// 每个端点都从本地数据源取数，行为与远端 ARTEXX 保持一致。
@MainActor
enum Router {

    static func handle(method: String, path: String, body: Data) -> (Int, Data, String) {
        let json = "application/json; charset=utf-8"
        // 去掉 query
        let cleanPath = path.components(separatedBy: "?").first ?? path
        let comps = cleanPath.components(separatedBy: "/").filter { !$0.isEmpty }
        // 期望以 api 开头
        let seg = comps.first == "api" ? Array(comps.dropFirst()) : comps

        let args: [String: Any] = (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]

        switch (method, seg.first ?? "") {
        case ("GET", "health"):
            return ok(["status": "ok", "version": "1.0.0", "embedded": true])

        // ── 鉴权 ──────────────────────────────────────────────
        case ("GET", "auth"):
            if seg.count >= 2, seg[1] == "status" {
                return ok(["initialized": EmbeddedServer.shared.hasPassword,
                           "needSetup": !EmbeddedServer.shared.hasPassword,
                           "loggedIn": false])
            }
            return notFound()
        case ("POST", "auth"):
            guard seg.count >= 2 else { return notFound() }
            let pwd = args["password"] as? String ?? ""
            if seg[1] == "init" {
                guard !EmbeddedServer.shared.hasPassword else { return err(400, "已初始化") }
                guard pwd.count >= 4 else { return err(400, "密码至少 4 位") }
                let t = EmbeddedServer.shared.setPassword(pwd)
                return ok(["token": t])
            }
            if seg[1] == "login" {
                guard let t = EmbeddedServer.shared.verify(pwd) else { return err(401, "密码错误") }
                return ok(["token": t])
            }
            if seg[1] == "change-password" {
                let np = args["newPassword"] as? String ?? ""
                guard np.count >= 4 else { return err(400, "新密码至少 4 位") }
                _ = EmbeddedServer.shared.setPassword(np)
                return ok(["ok": true])
            }
            return notFound()

        // ── 任务 ──────────────────────────────────────────────
        case ("GET", "tasks"):
            let list = LocalTaskStore.shared.tasks.map { t -> [String: Any] in
                ["id": t.id.uuidString, "title": t.title, "status": t.status,
                 "objective": t.objective, "phase": phaseOf(t.status),
                 "created_at": Int(t.createdAt.timeIntervalSince1970),
                 "updated_at": Int(t.updatedAt.timeIntervalSince1970),
                 "workers": 1, "coverage_enabled": true,
                 "targets": t.targets, "steps": t.steps.count, "findings": t.findings.count]
            }
            return ok(["items": list, "tasks": list])
        case ("POST", "tasks"):
            let title = args["title"] as? String ?? "未命名任务"
            let obj = args["objective"] as? String ?? title
            let scope = args["scope"] as? [String] ?? []
            let t = LocalTaskStore.shared.create(title: title, objective: obj, targets: scope)
            return ok(["id": t.id.uuidString, "title": t.title])
        case ("DELETE", "tasks"):
            if seg.count >= 2, let id = UUID(uuidString: seg[1]) {
                LocalTaskStore.shared.delete(id)
            }
            return ok(["ok": true])
        case ("POST", "tasks"):
            // tasks/{id}/control
            if seg.count >= 3, seg[2] == "control", let id = UUID(uuidString: seg[1]) {
                let action = args["action"] as? String ?? ""
                if action == "stop" || action == "pause" { LocalTaskStore.shared.stop(id) }
                else { LocalTaskStore.shared.run(id) }
                return ok(["ok": true])
            }
            return notFound()

        // ── 发现 ──────────────────────────────────────────────
        case ("GET", "exploration"):
            if seg.count >= 2, seg[1] == "findings" {
                if seg.count >= 3, seg[2] == "stats" {
                    var c = 0, h = 0, m = 0, l = 0
                    for t in LocalTaskStore.shared.tasks {
                        for f in t.findings {
                            switch f.severity.lowercased() {
                            case "critical": c += 1
                            case "high": h += 1
                            case "medium": m += 1
                            default: l += 1
                            }
                        }
                    }
                    return ok(["critical": c, "high": h, "medium": m, "low": l,
                               "total": c + h + m + l])
                }
                var all: [[String: Any]] = []
                for t in LocalTaskStore.shared.tasks {
                    for f in t.findings {
                        all.append(["id": f.id.uuidString, "title": f.title,
                                    "severity": f.severity, "asset": f.asset,
                                    "detail": f.detail, "description": f.detail,
                                    "cve": f.cveId ?? "", "status": "open",
                                    "task_id": t.id.uuidString,
                                    "created_at": Int(f.ts.timeIntervalSince1970)])
                    }
                }
                return ok(all)
            }
            return notFound()

        // ── 资产 ──────────────────────────────────────────────
        case ("GET", "assets"):
            if seg.count >= 2, seg[1] == "counts" {
                var counts: [String: Int] = [:]
                for t in LocalTaskStore.shared.tasks {
                    for a in t.assets {
                        let kind = a.contains("://") ? "app" : (a.contains(":") ? "service" : "subdomain")
                        counts[kind, default: 0] += 1
                        counts["total", default: 0] += 1
                    }
                }
                return ok(counts)
            }
            var out: [[String: Any]] = []
            var seen = Set<String>()
            for t in LocalTaskStore.shared.tasks {
                for a in t.assets where !seen.contains(a) {
                    seen.insert(a)
                    out.append(["id": a, "value": a,
                                "kind": a.contains("://") ? "app" : (a.contains(":") ? "service" : "subdomain"),
                                "company": t.title, "tested": true, "status": "tested"])
                }
            }
            return ok(out)

        // ── 统计 ──────────────────────────────────────────────
        case ("GET", "stats"):
            let tasks = LocalTaskStore.shared.tasks
            let running = tasks.filter { $0.status == "running" }.count
            let findings = tasks.reduce(0) { $0 + $1.findings.count }
            let assets = Set(tasks.flatMap { $0.assets }).count
            return ok(["tasks": tasks.count, "running": running,
                       "findings": findings, "assets": assets,
                       "skills": SkillLibrary.shared.all.count,
                       "cve": CVEDatabase.shared.totalRows])

        case ("GET", "tokens"):
            return ok(["total": 0, "input": 0, "output": 0, "cacheRead": 0])

        // ── 工具执行 / 日志 ────────────────────────────────────
        case ("GET", "commands"):
            if seg.count >= 2, seg[1] == "stats" { return ok([String: Any]()) }
            var out: [[String: Any]] = []
            for t in LocalTaskStore.shared.tasks {
                for s in t.steps where s.role == "tool" {
                    out.append(["id": s.id.uuidString, "tool": s.title,
                                "command": s.detail, "status": "done",
                                "task_id": t.id.uuidString,
                                "created_at": Int(s.ts.timeIntervalSince1970)])
                }
            }
            return ok(out)
        case ("GET", "logs"):
            return ok(["lines": [], "embedded": true])
        case ("GET", "traffic"):
            if seg.count >= 2, seg[1] == "hosts" { return ok([String: Any]()) }
            return ok([String: Any]())

        // ── Skill / CVE ──────────────────────────────────────
        case ("GET", "skills"):
            let list = SkillLibrary.shared.all.map { s -> [String: Any] in
                ["id": s.id, "name": s.n, "category": s.cat, "phase": s.phase,
                 "description": s.d, "commands": s.cmds, "tools": s.tools, "tags": s.tags]
            }
            return ok(list)

        // ── Agent / 工具 / MCP / LLM ─────────────────────────
        case ("GET", "agents"):
            return ok([
                ["id": "planner", "key": "planner", "name": "规划者", "role": "唯一意图生成者"],
                ["id": "worker", "key": "worker", "name": "执行者", "role": "工具执行 ×N"],
                ["id": "mainagent", "key": "mainagent", "name": "主控", "role": "人在环路"],
                ["id": "goals", "key": "goals", "name": "目标拆解", "role": "目标分解"],
            ])
        case ("GET", "tools"):
            return ok([
                ["id": "dns_resolve", "key": "dns_resolve", "desc": "DNS 解析", "agents": ["worker"], "enabled": true],
                ["id": "scan_ports", "key": "scan_ports", "desc": "TCP 端口扫描", "agents": ["worker"], "enabled": true],
                ["id": "http_probe", "key": "http_probe", "desc": "HTTP 指纹", "agents": ["worker"], "enabled": true],
                ["id": "subdomain_enum", "key": "subdomain_enum", "desc": "子域枚举", "agents": ["worker"], "enabled": true],
                ["id": "search_skills", "key": "search_skills", "desc": "检索技能库", "agents": ["worker"], "enabled": true],
                ["id": "search_cve", "key": "search_cve", "desc": "检索 CVE 库", "agents": ["worker"], "enabled": true],
                ["id": "report_finding", "key": "report_finding", "desc": "记录发现", "agents": ["worker"], "enabled": true],
            ])
        case ("GET", "mcp"):
            return ok([Any]())

        case ("GET", "llm"):
            let c = LLMClient.shared.config
            return ok([
                ["id": 1, "name": "本机模型", "provider": c.provider.rawValue,
                 "model": c.model, "base_url": c.baseURL, "active": c.ready]
            ])
        case ("GET", "llm"):
            return ok([Any]())
        case ("POST", "llm"):
            if seg.count >= 2, seg[1] == "test" {
                return ok(["ok": LLMClient.shared.config.ready])
            }
            if seg.count >= 2, seg[1] == "profiles" {
                let c = LLMClient.shared.config
                return ok([["id": 1, "name": "本机模型", "provider": c.provider.rawValue,
                            "model": c.model, "base_url": c.baseURL, "active": c.ready]])
            }
            if seg.count >= 2, seg[1] == "models" { return ok([String: Any]()) }
            if seg.count >= 2, seg[1] == "pool" { return ok(["active": 0, "total": 1]) }
            return notFound()

        // ── 会话 ──────────────────────────────────────────────
        case ("GET", "conversations"):
            return ok([Any]())
        case ("POST", "conversations"):
            return ok(["id": 1, "title": args["title"] as? String ?? "新会话"])

        // ── 设置 / 拦截 / 通知 ────────────────────────────────
        case ("GET", "settings"):
            return ok(["traffic_capture": false, "embedded": true,
                        "version": "1.0.0", "workers": 1])
        case ("PUT", "settings"):
            return ok(["ok": true])
        case ("GET", "intercept"):
            if seg.count >= 2, seg[1] == "pending" { return ok([Any]()) }
            if seg.count >= 2, seg[1] == "rules" { return ok([Any]()) }
            return ok([Any]())
        case ("GET", "asset-intercept"):
            return ok([Any]())
        case ("GET", "notify"):
            return ok([Any]())
        case ("GET", "llm-records"):
            return ok([Any]())

        // ── 工作空间 ──────────────────────────────────────────
        case ("GET", "workspace"):
            if seg.count >= 2, seg[1] == "list" {
                let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("workspace")
                let items = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
                return ok(["path": dir.path, "files": items])
            }
            if seg.count >= 2, seg[1] == "read" { return ok(["content": ""]) }
            return notFound()
        case ("POST", "workspace"):
            return ok(["ok": true])

        default:
            // 兜底：返回空数组而不是 404，避免客户端报错
            return ok([Any]())
        }
    }

    // MARK: - helpers
    private static func phaseOf(_ status: String) -> String {
        switch status {
        case "running": return "exploit"
        case "done": return "report"
        default: return "recon"
        }
    }

    private static func ok(_ obj: Any) -> (Int, Data, String) {
        let data = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{}".utf8)
        return (200, data, "application/json; charset=utf-8")
    }

    private static func err(_ code: Int, _ msg: String) -> (Int, Data, String) {
        let data = (try? JSONSerialization.data(withJSONObject: ["error": msg])) ?? Data("{}".utf8)
        return (code, data, "application/json; charset=utf-8")
    }

    private static func notFound() -> (Int, Data, String) {
        err(404, "not found")
    }
}
