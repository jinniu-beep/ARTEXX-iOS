import Foundation

/// 与原版 Web UI 完全对齐的本地 API 层。
///
/// 原版前端（Next.js 静态导出）所有请求都走 `fetch("/api" + path)`，
/// 返回值形状由 `web/src/lib/types.ts` 定义。这里逐条实现这些形状，
/// 数据源换成 App 内的本地库（LocalTaskStore / SkillLibrary / CVEDatabase / LLMClient）。
///
/// 设计原则：
/// 1. 形状优先 —— 字段名、层级、可空性都按 types.ts，前端不需要改一行代码。
/// 2. 只读兜底 —— 未实现的端点返回同类型的空值（[] 或 {}），页面不会崩。
/// 3. 全部本地 —— 不依赖电脑上的 ARTEXX 服务，飞行模式也能跑。
@MainActor
enum APICompat {

    // MARK: - 入口

    static func handle(method: String, rawPath: String, body: Data) -> (Int, Data, String)? {
        var path = rawPath
        var query: [String: String] = [:]
        if let q = path.firstIndex(of: "?") {
            query = parseQuery(String(path[path.index(after: q)...]))
            path = String(path[..<q])
        }
        if let decoded = path.removingPercentEncoding { path = decoded }

        guard path == "/api" || path.hasPrefix("/api/") else { return nil }
        var rest = String(path.dropFirst(4))
        if rest.hasPrefix("/") { rest.removeFirst() }
        let seg = rest.split(separator: "/").map(String.init)

        if method == "OPTIONS" { return (204, Data(), "text/plain; charset=utf-8") }

        let s0 = seg.count > 0 ? seg[0] : ""
        let s1 = seg.count > 1 ? seg[1] : ""
        let s2 = seg.count > 2 ? seg[2] : ""
        let args = decodeBody(body)

        switch s0 {
        // ── 基础 ────────────────────────────────────────────────
        case "health":
            return json(["ok": true, "service": "artexx-ios", "version": "1.0.0", "embedded": true])

        case "auth":
            return auth(method: method, action: s1, args: args)

        case "stats":
            return json(statsJSON())

        // ── 任务 ────────────────────────────────────────────────
        case "tasks":
            return tasks(method: method, seg: seg, args: args)

        case "task-categories":
            if method == "GET" { return json(["categories": [Any]()]) }
            return json(["id": 1, "name": args["name"] as? String ?? "默认", "task_count": 0,
                         "created_at": nowISO(), "updated_at": nowISO()])

        case "task-templates":
            if method == "GET" { return json(["templates": [Any]()]) }
            return json(["id": 1, "name": args["name"] as? String ?? "模板",
                         "description": "", "goal": "", "created_at": nowISO(), "updated_at": nowISO()])

        case "task-archives":
            return json(["items": [Any](), "total": 0, "page": 1, "size": 20])

        case "active":
            return json(["active": LocalTaskStore.shared.runningTaskID?.uuidString ?? ""])

        // ── 探索图谱 / 发现 / 活动 ──────────────────────────────
        case "exploration":
            return exploration(method: method, action: s1, sub: s2, query: query, args: args)

        // ── 资产 / 企业 ─────────────────────────────────────────
        case "assets":
            return assets(method: method, action: s1, query: query, args: args)

        case "companies":
            return json([Any]())

        // ── Token / 用量 ────────────────────────────────────────
        case "tokens":
            switch s1 {
            case "usage": return json(["by_profile": [Any](), "daily": [Any]()])
            case "daily": return json([Any]())
            case "conversations": return json([Any]())
            default: return json(tokenTotal())
            }

        // ── 设置 ────────────────────────────────────────────────
        case "settings":
            if s1 == "web-search" { return json(["ok": true, "count": 0, "backend": "ddgs"]) }
            if method == "PUT" { return json(settingsJSON()) }
            return json(settingsJSON())

        // ── 流量 ────────────────────────────────────────────────
        case "traffic":
            if s1 == "hosts" { return json(["hosts": [Any]()]) }
            if s1 == "exchange" { return json(["req": "", "resp": ""]) }
            return json(["enabled": false, "proxy": "", "count": 0, "total": 0,
                         "page": 0, "size": 50, "exchanges": [Any]()])

        // ── 工具执行记录 ────────────────────────────────────────
        case "commands":
            if s1 == "stats" { return json(["stats": [Any]()]) }
            let cmds = commandRecords()
            return json(["commands": cmds, "total": cmds.count])

        // ── 日志 ────────────────────────────────────────────────
        case "logs":
            if s1 == "history" { return json(["lines": [Any](), "total": 0]) }
            return json(["lines": [Any]()])

        // ── 技能（原版页面用 { skills: [...] }） ────────────────
        case "skills":
            if method != "GET" { return json(["name": args["name"] as? String ?? "skill", "files": 0]) }
            return json(["skills": skillItems()])

        // ── Agent / 工具 / MCP ─────────────────────────────────
        case "agents":
            if method == "GET", s1.isEmpty { return json(["agents": agentItems()]) }
            if method == "GET" { return json(agentDetail(s1)) }
            return json(["ok": true])

        case "tools":
            if method == "GET", s1.isEmpty { return json(["tools": toolItems()]) }
            return json(["ok": true])

        case "mcp":
            if method == "GET" { return json(["servers": [Any]()]) }
            return json(["ok": true])

        // ── LLM ────────────────────────────────────────────────
        case "llm":
            return llm(method: method, action: s1, args: args)

        // ── 对话 ────────────────────────────────────────────────
        case "conversations":
            if method == "GET", s1.isEmpty { return json(["conversations": [Any]()]) }
            if s1 == "messages" || s2 == "messages" {
                return json(["items": [Any](), "cursor": 0, "running": false])
            }
            return json(["ok": true])

        case "chat":
            return json(["reply": "", "items": [Any](), "next_cursor": ""])

        // ── 拦截 / 审批 ─────────────────────────────────────────
        case "intercept":
            if s1 == "judge" { return json(["enabled": false, "profile_id": 0, "prompt": "",
                                            "timeout_seconds": 30, "fail_action": "deny"]) }
            if s1 == "tool-config" { return json(["tools": [Any]()]) }
            return json([Any]())

        case "asset-intercept":
            return json([Any]())

        case "approvals":
            return json(["items": [Any](), "total": 0])

        // ── 通知 ────────────────────────────────────────────────
        case "notify":
            switch s1 {
            case "channels": return json(["channels": [Any]()])
            case "deliveries": return json(["items": [Any](), "total": 0])
            default: return json(["enabled": false, "channel_count": 0])
            }

        case "llm-records":
            return json(["items": [Any](), "total": 0])

        // ── 工作空间 ────────────────────────────────────────────
        case "workspace":
            return workspace(method: method, action: s1, query: query, args: args)

        // ── 同步 / 更新 / 报告 ──────────────────────────────────
        case "sync":
            return json(["connected": false, "url": "", "projects": [Any](), "tasks": [Any]()])

        case "update":
            return json(["current": "1.0.0", "latest": "1.0.0", "available": false, "notes": ""])

        case "report":
            let text = reportMarkdown(query["task"])
            return (200, Data(text.utf8), "text/markdown; charset=utf-8")

        case "visibility":
            return json(["ok": true])

        default:
            // 未实现的端点：返回空数组，前端 arr() 会安全降级
            return json([Any]())
        }
    }

    // MARK: - 鉴权

    private static func auth(method: String, action: String, args: [String: Any]) -> (Int, Data, String) {
        let server = EmbeddedServer.shared
        switch (method, action) {
        case ("GET", "status"):
            return json(["initialized": true, "needSetup": false, "loggedIn": true])
        case ("POST", "init"):
            let pwd = args["password"] as? String ?? "artexx"
            let token = server.setPassword(pwd)
            return json(["token": token])
        case ("POST", "login"):
            let pwd = args["password"] as? String ?? ""
            if let t = server.verify(pwd) { return json(["token": t]) }
            // 本机模式：任何密码都放行（服务只监听 127.0.0.1）
            return json(["token": server.setPassword(pwd.isEmpty ? "artexx" : pwd)])
        case ("POST", "change-password"):
            let np = args["new_password"] as? String ?? "artexx"
            return json(["ok": true, "token": server.setPassword(np)])
        default:
            return json(["initialized": true])
        }
    }

    // MARK: - 任务

    private static func tasks(method: String, seg: [String], args: [String: Any]) -> (Int, Data, String) {
        let store = LocalTaskStore.shared
        let id = seg.count > 1 ? seg[1] : ""
        let sub = seg.count > 2 ? seg[2] : ""

        switch method {
        case "GET":
            if id.isEmpty {
                let list = store.tasks.map { taskJSON($0) }
                return json(["tasks": list, "active": store.runningTaskID?.uuidString ?? ""])
            }
            guard let uuid = UUID(uuidString: id), let t = store.task(uuid) else { return json([String: Any]()) }
            if sub == "goals" { return json(["goals": [Any]()]) }
            if sub == "constraints" { return json(["constraints": [Any]()]) }
            if sub == "coverage" {
                return json(["enabled": true, "scope_rows": t.targets.count, "denominator": t.targets.count,
                             "tested": t.assets.count, "pct": t.targets.isEmpty ? 0 : 100 * t.assets.count / max(t.targets.count, 1),
                             "by_type": [Any]()])
            }
            if sub == "coverage-graph" { return json(["nodes": [Any](), "edges": [Any]()]) }
            if sub == "asset-refs" { return json(["assets": [Any](), "total": 0]) }
            if sub == "intent-assets" { return json(["assets": [Any]()]) }
            if sub == "scope" { return json(["scope": t.targets]) }
            if sub == "llm" { return json(["resolution": [Any]()]) }
            return json(taskJSON(t))

        case "POST":
            if sub == "control" {
                guard let uuid = UUID(uuidString: id) else { return json(["ok": false]) }
                let action = args["action"] as? String ?? "resume"
                if action == "pause" || action == "stop" {
                    store.stop(uuid)
                } else {
                    store.run(uuid)
                }
                let status = store.task(uuid)?.status ?? "pending"
                return json(["id": id, "paused": status == "paused", "queued": status == "pending", "status": status])
            }
            if sub == "archive" { return json(["ok": true]) }
            if !id.isEmpty { return json(["ok": true]) }
            let title = args["name"] as? String ?? args["title"] as? String ?? "未命名任务"
            let goal = args["goal"] as? String ?? args["description"] as? String ?? title
            let desc = args["description"] as? String ?? goal
            let scope = (args["scope"] as? [String]) ?? (args["targets"] as? [String]) ?? []
            let t = store.create(title: title, objective: desc.isEmpty ? goal : desc, targets: scope)
            return json(taskJSON(t))

        case "PATCH":
            guard let uuid = UUID(uuidString: id), var t = store.task(uuid) else { return json([String: Any]()) }
            if let name = args["name"] as? String { t.title = name }
            if let goal = args["goal"] as? String { t.objective = goal }
            store.update(t)
            return json(taskJSON(t))

        case "DELETE":
            if let uuid = UUID(uuidString: id) { store.delete(uuid) }
            return json(["deleted": true, "id": id])

        default:
            return json(["ok": true])
        }
    }

    private static func taskJSON(_ t: LocalTask) -> [String: Any] {
        let sc = t.severityCount
        let status = webStatus(t.status)
        return [
            "id": t.id.uuidString,
            "name": t.title,
            "description": t.objective,
            "goal": t.objective,
            "status": status,
            "created_at": iso(t.createdAt),
            "created_unix": Int(t.createdAt.timeIntervalSince1970),
            "last_activity": iso(t.updatedAt),
            "last_activity_unix": Int(t.updatedAt.timeIntervalSince1970),
            "paused": status == "paused",
            "queued": status == "queued",
            "active": status == "running",
            "in_flight": t.steps.isEmpty ? 0 : 1,
            "findings": ["critical": sc.critical, "high": sc.high, "medium": sc.medium, "low": sc.low],
            "goals_total": t.targets.count,
            "goals_met": t.assets.count,
            "engine_mode": status == "running" ? "exploring" : "idle",
            "coverage_enabled": true,
            "tokens": tokenTotal(),
            "category_name": "",
            "pinned": false,
        ]
    }

    private static func webStatus(_ s: String) -> String {
        switch s {
        case "running": return "running"
        case "done": return "done"
        case "failed": return "failed"
        case "stopped", "paused": return "paused"
        default: return "queued"
        }
    }

    // MARK: - 探索 / 发现 / 活动

    private static func exploration(method: String, action: String, sub: String,
                                    query: [String: String], args: [String: Any]) -> (Int, Data, String) {
        switch action {
        case "findings":
            if sub == "stats" { return json(findingStats()) }
            if sub == "groups" { return json(["items": [Any](), "total": 0, "finding_total": 0, "page": 1, "page_size": 20]) }
            if sub == "asset-tree" { return json(["tree": [Any](), "total": 0]) }
            if sub == "retests" { return json(["retests": [Any]()]) }
            if sub == "export" { return (200, Data("# 发现导出\n".utf8), "text/markdown; charset=utf-8") }
            let all = findingList()
            // 带 page 参数 = 分页形态；否则是裸数组
            if query["page"] != nil {
                let page = Int(query["page"] ?? "1") ?? 1
                let limit = Int(query["limit"] ?? "20") ?? 20
                let start = max(0, (page - 1) * limit)
                let slice = start < all.count ? Array(all[start..<min(all.count, start + limit)]) : [Any]()
                return json(["items": slice, "total": all.count, "page": page, "page_size": limit])
            }
            if method == "PATCH" { return json([String: Any]()) }
            return json(all)

        case "activity":
            return json(["items": activityItems(), "cursor": 0])

        case "tokens":
            return json(["workers": [Any](), "sessions": [Any](), "total": tokenTotal()])

        case "nodes":
            return json(["items": [Any](), "total": 0, "page": 1, "size": 20, "edges": [Any](), "refs": [String: Any](), "assets": [String: Any]()])

        case "graph", "frontier", "intents":
            if action == "graph" { return json(["nodes": [Any](), "edges": [Any]()]) }
            return json([Any]())

        default:
            return json([Any]())
        }
    }

    private static func findingList() -> [[String: Any]] {
        var out: [[String: Any]] = []
        for t in LocalTaskStore.shared.tasks {
            for f in t.findings {
                out.append([
                    "id": f.id.uuidString,
                    "finding_id": f.id.uuidString,
                    "vulnclass": f.title,
                    "name": f.title,
                    "severity": f.severity.lowercased(),
                    "status": "confirmed",
                    "summary": f.detail,
                    "evidence": f.detail,
                    "task_id": t.id.uuidString,
                    "task_description": t.objective,
                    "assets": [["id": 0, "type": "service", "value": f.asset] as [String: Any]],
                    "ts": iso(f.ts),
                    "cve": f.cveId ?? "",
                ])
            }
        }
        return out
    }

    private static func findingStats() -> [String: Any] {
        var c = 0, h = 0, m = 0, l = 0
        var classes = Set<String>()
        var tasks: [[String: Any]] = []
        for t in LocalTaskStore.shared.tasks where !t.findings.isEmpty {
            for f in t.findings {
                switch f.severity.lowercased() {
                case "critical": c += 1
                case "high": h += 1
                case "medium": m += 1
                default: l += 1
                }
                classes.insert(f.title)
            }
            tasks.append(["task_id": t.id.uuidString, "task_name": t.title,
                          "task_description": t.objective, "count": t.findings.count])
        }
        return ["total": c + h + m + l, "pending": 0,
                "critical": c, "high": h, "medium": m, "low": l,
                "vulnclasses": Array(classes).sorted(), "tasks": tasks]
    }

    private static func activityItems() -> [[String: Any]] {
        var out: [[String: Any]] = []
        var seq = 0
        for t in LocalTaskStore.shared.tasks {
            for s in t.steps {
                seq += 1
                out.append([
                    "seq": seq,
                    "worker": s.role == "plan" ? "planner" : "worker",
                    "ts": iso(s.ts),
                    "kind": s.role == "tool" ? "tool_use" : "text",
                    "tool": s.title,
                    "summary": s.title,
                    "detail": s.detail,
                    "task_id": t.id.uuidString,
                ])
            }
        }
        return Array(out.suffix(60))
    }

    private static func commandRecords() -> [[String: Any]] {
        var out: [[String: Any]] = []
        var idx = 0
        for t in LocalTaskStore.shared.tasks {
            for s in t.steps where s.role == "tool" {
                idx += 1
                out.append([
                    "id": idx,
                    "exploration_id": idx,
                    "worker": "worker",
                    "tool": s.title,
                    "command": s.detail,
                    "output": "",
                    "is_error": false,
                    "ts": iso(s.ts),
                    "task_id": t.id.uuidString,
                ])
            }
        }
        return out
    }

    // MARK: - 资产

    private static func assets(method: String, action: String, query: [String: String],
                               args: [String: Any]) -> (Int, Data, String) {
        var rows: [[String: Any]] = []
        var counts: [String: Int] = ["root_domain": 0, "ip": 0, "subdomain": 0, "app": 0, "service": 0, "endpoint": 0, "total": 0]
        var idx = 0
        var seen = Set<String>()
        for t in LocalTaskStore.shared.tasks {
            for a in t.assets where !seen.contains(a) {
                seen.insert(a)
                idx += 1
                let type: String
                if a.contains("://") { type = "app" }
                else if a.contains(":") { type = "service" }
                else if a.range(of: "^[0-9.]+$", options: .regularExpression) != nil { type = "ip" }
                else { type = "subdomain" }
                counts[type, default: 0] += 1
                counts["total", default: 0] += 1
                rows.append([
                    "id": idx, "type": type, "domain": a, "root_domain": a,
                    "task_ids": [t.id.uuidString], "company_id": 0,
                    "last_seen": iso(t.updatedAt), "task_source": t.title,
                ])
            }
        }
        if action == "counts" { return json(counts) }
        if method == "DELETE" { return json(["deleted": 0]) }
        return json(["count": rows.count, "total": rows.count, "assets": rows])
    }

    // MARK: - 技能 / Agent / 工具

    private static func skillItems() -> [[String: Any]] {
        SkillLibrary.shared.all.map { s in
            [
                "name": s.id,
                "description": s.d,
                "license": "MIT",
                "compatibility": "",
                "mcps": [Any](),
                "files": ["SKILL.md"],
                "calls": 0,
                "tasks": 0,
                "usage_agents": [Any](),
                "category": s.cat,
                "phase": s.phase,
                "commands": s.cmds,
                "tools": s.tools,
                "tags": s.tags,
            ]
        }
    }

    private static func agentItems() -> [[String: Any]] {
        let llmReady = LLMClient.shared.config.ready
        func row(_ key: String, _ name: String, _ role: String, _ desc: String, _ builtin: Bool) -> [String: Any] {
            ["id": key, "key": key, "name": name, "description": desc, "role": role,
             "builtin": builtin, "enabled": true, "llm_profile_id": llmReady ? 1 : 0,
             "max_turns": 0, "run_seconds": 0, "web_search": false, "interactive_shell": false,
             "mcp_count": 0, "skill_count": SkillLibrary.shared.all.count, "tool_count": 7]
        }
        return [
            row("planner", "规划者", "规划", "唯一意图生成者，拆解目标并派发意图", true),
            row("worker", "执行者", "执行", "执行工具调用，可并发多个", true),
            row("mainagent", "主控", "人在环路", "与用户对话、编排与审批", true),
            row("goals", "目标拆解", "目标", "把任务目标拆成可验证的漏洞类别", true),
        ]
    }

    private static func agentDetail(_ key: String) -> [String: Any] {
        let base = agentItems().first { ($0["key"] as? String) == key } ?? agentItems()[0]
        var d = base
        d["prompt"] = "你是 ARTEXX 的 \(base["name"] as? String ?? "Agent")。"
        d["prompt_version"] = 1
        d["triggers"] = [Any]()
        return d
    }

    private static func toolItems() -> [[String: Any]] {
        func row(_ key: String, _ desc: String, _ agents: [String]) -> [String: Any] {
            ["key": key, "system": true, "description": desc,
             "schema": ["type": "object", "properties": [String: Any]()],
             "agents": agents, "enabled": true, "kind": "builtin", "deferred": false, "calls": 0]
        }
        return [
            row("dns_resolve", "DNS 解析", ["worker"]),
            row("scan_ports", "TCP 端口扫描", ["worker"]),
            row("http_probe", "HTTP 指纹识别", ["worker"]),
            row("subdomain_enum", "子域枚举", ["worker"]),
            row("search_skills", "检索技能库", ["worker", "planner"]),
            row("search_cve", "检索 CVE 知识库", ["worker", "planner"]),
            row("report_finding", "登记漏洞发现", ["worker"]),
        ]
    }

    // MARK: - LLM

    private static func llm(method: String, action: String, args: [String: Any]) -> (Int, Data, String) {
        let cfg = LLMClient.shared.config
        let profile: [String: Any] = [
            "id": "1",
            "name": cfg.ready ? "本机模型" : "未配置",
            "format": cfg.provider == .anthropic ? "anthropic" : "openai",
            "base_url": cfg.baseURL,
            "proxy": "",
            "model": cfg.model,
            "api_key_hint": cfg.apiKey.isEmpty ? "" : "已配置",
            "rate_per_second": 0,
            "rate_per_minute": 0,
            "context_window_k": 128,
            "thinking_type": "",
            "reasoning_effort": "",
            "is_default": true,
            "priority": 100,
            "pool_exclude": false,
            "streaming": true,
            "max_tokens": cfg.maxTokens,
        ]
        switch action {
        case "profiles":
            if method == "POST" { return json(["id": 1]) }
            if method == "PUT" { return json(["ok": true]) }
            if method == "DELETE" { return json(["deleted": 1]) }
            return json(["profiles": [profile]])
        case "pool":
            return json(["enabled": false, "chain": [profile], "status": [Any](), "active_id": 1])
        case "models":
            if method == "POST" {
                return json(["ok": !cfg.apiKey.isEmpty, "models": [cfg.model], "error": cfg.apiKey.isEmpty ? "未配置 API Key" : ""])
            }
            return json(["models": [cfg.model]])
        case "test":
            return json(["ok": cfg.ready, "error": cfg.ready ? "" : "未配置模型"])
        case "retry-policy":
            return json(["connect": [0, 0], "empty": [0, 0], "safe": [0, 0], "http": [0, 0], "stream": [0, 0]])
        case "records":
            return json(["items": [Any](), "total": 0])
        default:
            return json([Any]())
        }
    }

    // MARK: - 工作空间

    private static func workspace(method: String, action: String, query: [String: String],
                                  args: [String: Any]) -> (Int, Data, String) {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("workspace", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        switch action {
        case "list":
            let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            let entries = names.map { n -> [String: Any] in
                let full = dir.appendingPathComponent(n)
                let attrs = try? FileManager.default.attributesOfItem(atPath: full.path)
                let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
                return ["name": n, "path": n, "is_dir": false, "size": size]
            }
            return json(["path": dir.path, "entries": entries, "files": names])
        case "read":
            let name = query["path"] ?? ""
            let data = (try? Data(contentsOf: dir.appendingPathComponent(name))) ?? Data()
            return json(["path": name, "content": String(decoding: data, as: UTF8.self)])
        case "write":
            let name = args["path"] as? String ?? "note.txt"
            let content = args["content"] as? String ?? ""
            try? Data(content.utf8).write(to: dir.appendingPathComponent(name), options: .atomic)
            return json(["ok": true])
        default:
            return json(["ok": true])
        }
    }

    // MARK: - 统计

    private static func statsJSON() -> [String: Any] {
        let tasks = LocalTaskStore.shared.tasks
        let findings = tasks.reduce(0) { $0 + $1.findings.count }
        let assets = Set(tasks.flatMap { $0.assets }).count
        var active: [String: Any] = [:]
        if let t = tasks.first(where: { $0.status == "running" }) { active = taskJSON(t) }
        return [
            "assets": assets,
            "findings_confirmed": findings,
            "engine_mode": tasks.contains(where: { $0.status == "running" }) ? "exploring" : "idle",
            "llm_configured": LLMClient.shared.config.ready,
            "roe_enabled": true,
            "tasks": tasks.count,
            "skills": SkillLibrary.shared.all.count,
            "cve": CVEDatabase.shared.totalRows,
            "active_task": active,
        ]
    }

    private static func tokenTotal() -> [String: Any] {
        ["input_tokens": 0, "output_tokens": 0, "cache_read_tokens": 0, "cache_write_tokens": 0]
    }

    private static func settingsJSON() -> [String: Any] {
        [
            "traffic_capture": false,
            "agent_traffic_binding": false,
            "llm_record": false,
            "web_search_enabled": false,
            "web_search_backend": "ddgs",
            "brave_key_set": false,
            "tavily_key_set": false,
            "web_search_proxy": "",
            "global_proxy": "",
            "python_interpreter": "",
            "workers": 1,
            "task_concurrency_enabled": false,
            "task_concurrency_limit": 1,
            "llm_pool_enabled": false,
            "llm_pool_bind_fallback": false,
            "constraints_inject_planner": true,
            "constraints_inject_worker": true,
        ]
    }

    private static func reportMarkdown(_ taskID: String?) -> String {
        let tasks = LocalTaskStore.shared.tasks
        let scoped: [LocalTask]
        if let taskID, let uuid = UUID(uuidString: taskID), let t = tasks.first(where: { $0.id == uuid }) {
            scoped = [t]
        } else {
            scoped = tasks
        }
        if scoped.isEmpty { return "# ARTEXX 报告\n\n暂无任务数据。先在「任务」页新建一个任务并运行。\n" }

        var md = "# ARTEXX 渗透测试报告\n\n"
        for t in scoped {
            let sc = t.severityCount
            md += "## \(t.title)\n\n"
            md += "- 目标：\(t.objective)\n"
            md += "- 状态：\(t.status)\n"
            md += "- 范围：\(t.targets.isEmpty ? "未设置" : t.targets.joined(separator: "、"))\n"
            md += "- 发现：\(t.findings.count) 项（严重 \(sc.critical) · 高危 \(sc.high) · 中危 \(sc.medium) · 低危 \(sc.low)）\n\n"
            if t.findings.isEmpty {
                md += "> 该任务暂无已确认漏洞。\n\n"
            } else {
                for (i, f) in t.findings.enumerated() {
                    md += "### \(i + 1). [\(f.severity.uppercased())] \(f.title)\n\n"
                    md += "- 资产：\(f.asset)\n"
                    if let c = f.cveId, !c.isEmpty { md += "- CVE：\(c)\n" }
                    md += "\n\(f.detail)\n\n"
                }
            }
        }
        return md
    }

    // MARK: - 工具函数

    private static func decodeBody(_ body: Data) -> [String: Any] {
        guard !body.isEmpty else { return [:] }
        if let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any] { return obj }
        return [:]
    }

    private static func parseQuery(_ qs: String) -> [String: String] {
        var out: [String: String] = [:]
        for pair in qs.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let k = String(kv[0]).removingPercentEncoding ?? String(kv[0])
            let v = kv.count > 1 ? (String(kv[1]).removingPercentEncoding ?? String(kv[1])) : ""
            out[k] = v
        }
        return out
    }

    private static func iso(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: d)
    }

    private static func nowISO() -> String { iso(Date()) }

    private static func json(_ obj: Any) -> (Int, Data, String) {
        let data = (try? JSONSerialization.data(withJSONObject: obj, options: [.fragmentsAllowed]))
            ?? Data("{}".utf8)
        return (200, data, "application/json; charset=utf-8")
    }
}
