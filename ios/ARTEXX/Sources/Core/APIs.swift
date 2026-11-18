import Foundation

enum AuthAPI {
    struct Status: Decodable { var initialized: Bool?; var needSetup: Bool?; var loggedIn: Bool? }
    struct LoginResp: Decodable { var token: String?; var error: String? }

    static func status() async throws -> Status {
        try await APIClient.shared.get("auth/status", as: Status.self)
    }
    @discardableResult
    static func initAdmin(password: String) async throws -> String? {
        struct Req: Encodable { let password: String }
        let data = try await APIClient.shared.raw(path: "auth/init", method: "POST", json: ["password": password])
        if let d = try? JSONDecoder().decode(LoginResp.self, from: data) { return d.token }
        if let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { return d["token"] as? String }
        return nil
    }
    @discardableResult
    static func login(password: String) async throws -> String? {
        let data = try await APIClient.shared.raw(path: "auth/login", method: "POST", json: ["password": password])
        if let d = try? JSONDecoder().decode(LoginResp.self, from: data) { return d.token }
        if let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { return d["token"] as? String }
        return nil
    }
    static func changePassword(old: String, new: String) async throws {
        _ = try await APIClient.shared.raw(path: "auth/change-password", method: "POST", json: ["oldPassword": old, "newPassword": new])
    }
}

enum TaskAPI {
    static func list() async throws -> [TaskItem] { try await APIClient.shared.list("tasks", as: TaskItem.self) as [TaskItem] }
    static func detail(_ id: Int64) async throws -> [String: AnyJSON] { try await APIClient.shared.dict("tasks/\(id)") }
    static func create(title: String, objective: String, scope: [String]) async throws -> [String: AnyJSON] {
        let data = try await APIClient.shared.raw(path: "tasks", method: "POST",
            json: ["title": title, "objective": objective, "scope": scope])
        return (try? JSONDecoder().decode([String: AnyJSON].self, from: data)) ?? [:]
    }
    static func control(_ id: Int64, action: String) async throws {
        _ = try await APIClient.shared.raw(path: "tasks/\(id)/control", method: "POST", json: ["action": action])
    }
    static func remove(_ id: Int64) async throws {
        _ = try await APIClient.shared.raw(path: "tasks/\(id)", method: "DELETE")
    }
    static func coverage(_ id: Int64) async throws -> [String: AnyJSON] { try await APIClient.shared.dict("tasks/\(id)/coverage") }
    static func goals(_ id: Int64) async throws -> [String: AnyJSON] { try await APIClient.shared.dict("tasks/\(id)/goals") }
    static func scope(_ id: Int64) async throws -> [String: AnyJSON] { try await APIClient.shared.dict("tasks/\(id)/scope") }
}

enum FindingAPI {
    static func list(task: Int64? = nil, page: Int = 1) async throws -> [Finding] {
        var q: [String: String] = ["page": "\(page)", "pageSize": "50"]
        if let task { q["task"] = "\(task)" }
        return try await APIClient.shared.list("exploration/findings", query: q, as: Finding.self)
    }
    static func stats() async throws -> [String: AnyJSON] { try await APIClient.shared.dict("exploration/findings/stats") }
    static func patch(_ id: Int64, status: String) async throws {
        _ = try await APIClient.shared.raw(path: "exploration/findings/\(id)", method: "PATCH", json: ["status": status])
    }
    static func retests(_ id: Int64) async throws -> [String: AnyJSON] { try await APIClient.shared.dict("exploration/findings/\(id)/retests") }
    static func startRetest(_ id: Int64) async throws {
        _ = try await APIClient.shared.raw(path: "exploration/findings/\(id)/retests", method: "POST", json: [:])
    }
}

enum AssetAPI {
    static func list(page: Int = 1) async throws -> [Asset] {
        try await APIClient.shared.list("assets", query: ["page": "\(page)", "pageSize": "100"], as: Asset.self)
    }
    static func counts() async throws -> [String: AnyJSON] { try await APIClient.shared.dict("assets/counts") }
    static func insert(_ values: [String]) async throws {
        _ = try await APIClient.shared.raw(path: "assets", method: "POST", json: ["assets": values])
    }
    static func delete(_ values: [String]) async throws {
        _ = try await APIClient.shared.raw(path: "assets", method: "DELETE", json: ["assets": values])
    }
}

enum OpsAPI {
    static func stats() async throws -> [String: AnyJSON] { try await APIClient.shared.dict("stats") }
    static func commands(page: Int = 1) async throws -> [CommandRecord] {
        try await APIClient.shared.list("commands", query: ["page": "\(page)"], as: CommandRecord.self)
    }
    static func commandStats() async throws -> [String: AnyJSON] { try await APIClient.shared.dict("commands/stats") }
    static func logs() async throws -> [String: AnyJSON] { try await APIClient.shared.dict("logs") }
    static func trafficHosts() async throws -> [String: AnyJSON] { try await APIClient.shared.dict("traffic/hosts") }
    static func traffic() async throws -> [String: AnyJSON] { try await APIClient.shared.dict("traffic") }
    static func health() async throws -> [String: AnyJSON] { try await APIClient.shared.dict("health") }
    static func audit() async throws -> [String: AnyJSON] { try await APIClient.shared.dict("audit") }
    static func tokensUsage() async throws -> [String: AnyJSON] { try await APIClient.shared.dict("tokens/usage") }
    static func gc() async throws { _ = try await APIClient.shared.raw(path: "gc", method: "POST") }
    static func settings() async throws -> [String: AnyJSON] { try await APIClient.shared.dict("settings") }
    static func putSettings(_ json: [String: Any]) async throws {
        _ = try await APIClient.shared.raw(path: "settings", method: "PUT", json: json)
    }
}

enum LLMAPI {
    static func profiles() async throws -> [LLMProfile] { try await APIClient.shared.list("llm/profiles", as: LLMProfile.self) as [LLMProfile] }
    static func saveProfile(_ json: [String: Any]) async throws {
        _ = try await APIClient.shared.raw(path: "llm/profiles", method: "POST", json: json)
    }
    static func activate(_ id: Int64) async throws {
        _ = try await APIClient.shared.raw(path: "llm/profiles/active", method: "POST", json: ["id": id])
    }
    static func deleteProfile(_ id: Int64) async throws {
        _ = try await APIClient.shared.raw(path: "llm/profiles/\(id)", method: "DELETE")
    }
    static func pool() async throws -> [String: AnyJSON] { try await APIClient.shared.dict("llm/pool") }
    static func models() async throws -> [String: AnyJSON] { try await APIClient.shared.dict("llm/models") }
    static func test(_ json: [String: Any]) async throws -> [String: AnyJSON] {
        let data = try await APIClient.shared.raw(path: "llm/test", method: "POST", json: json)
        return (try? JSONDecoder().decode([String: AnyJSON].self, from: data)) ?? [:]
    }
}

enum AgentAPI {
    static func list() async throws -> [AgentItem] { try await APIClient.shared.list("agents", as: AgentItem.self) as [AgentItem] }
    static func tools() async throws -> [ToolItem] { try await APIClient.shared.list("tools", as: ToolItem.self) as [ToolItem] }
    static func toggleTool(_ key: String, enabled: Bool) async throws {
        _ = try await APIClient.shared.raw(path: "tools/\(key)", method: "PUT", json: ["enabled": enabled])
    }
    static func mcp() async throws -> [String: AnyJSON] { try await APIClient.shared.dict("mcp") }
    static func saveMCP(_ json: [String: Any]) async throws {
        _ = try await APIClient.shared.raw(path: "mcp", method: "POST", json: json)
    }
    static func interceptRules() async throws -> [String: AnyJSON] { try await APIClient.shared.dict("intercept/rules") }
    static func approvals() async throws -> [String: AnyJSON] { try await APIClient.shared.dict("intercept/pending") }
    static func decide(_ id: String, approve: Bool) async throws {
        _ = try await APIClient.shared.raw(path: "intercept/pending/\(id)/decide", method: "POST", json: ["decision": approve ? "approve" : "deny"])
    }
    static func notifyChannels() async throws -> [String: AnyJSON] { try await APIClient.shared.dict("notify/channels") }
}

enum ChatAPI {
    static func conversations() async throws -> [ConversationItem] {
        try await APIClient.shared.list("conversations", as: ConversationItem.self) as [ConversationItem]
    }
    static func messages(_ id: Int64) async throws -> [ChatMessage] {
        try await APIClient.shared.list("conversations/\(id)/messages", as: ChatMessage.self) as [ChatMessage]
    }
    static func send(_ id: Int64, text: String) async throws {
        _ = try await APIClient.shared.raw(path: "conversations/\(id)/messages", method: "POST", json: ["content": text])
    }
    static func stop(_ id: Int64) async throws {
        _ = try await APIClient.shared.raw(path: "conversations/\(id)/stop", method: "POST")
    }
    static func create(_ title: String) async throws -> [String: AnyJSON] {
        let data = try await APIClient.shared.raw(path: "conversations", method: "POST", json: ["title": title])
        return (try? JSONDecoder().decode([String: AnyJSON].self, from: data)) ?? [:]
    }
}

enum WorkspaceAPI {
    static func list(_ path: String = "") async throws -> [String: AnyJSON] {
        try await APIClient.shared.dict("workspace/list", query: ["path": path])
    }
    static func read(_ path: String) async throws -> String {
        let data = try await APIClient.shared.raw(path: "workspace/read", query: ["path": path])
        if let s = String(data: data, encoding: .utf8), !s.hasPrefix("{") { return s }
        if let d = try? JSONDecoder().decode([String: AnyJSON].self, from: data) { return d["content"]?.stringValue ?? "" }
        return ""
    }
    static func write(_ path: String, content: String) async throws {
        _ = try await APIClient.shared.raw(path: "workspace/write", method: "POST", json: ["path": path, "content": content])
    }
}
