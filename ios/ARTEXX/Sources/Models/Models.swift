import Foundation

// MARK: - 任意 JSON（后端字段类型不固定时兜底）
enum AnyJSON: Codable, Hashable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([AnyJSON])
    case object([String: AnyJSON])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Int.self) { self = .int(v); return }
        if let v = try? c.decode(Double.self) { self = .double(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([AnyJSON].self) { self = .array(v); return }
        if let v = try? c.decode([String: AnyJSON].self) { self = .object(v); return }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    var stringValue: String {
        switch self {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return b ? "true" : "false"
        case .null: return ""
        case .array(let a): return a.map { $0.stringValue }.joined(separator: ", ")
        case .object(let o): return o.map { "\($0.key)=\($0.value.stringValue)" }.joined(separator: " ")
        }
    }

    var intValue: Int? {
        switch self {
        case .int(let i): return i
        case .double(let d): return Int(d)
        case .string(let s): return Int(s)
        default: return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .double(let d): return d
        case .int(let i): return Double(i)
        case .string(let s): return Double(s)
        default: return nil
        }
    }

    var display: String { stringValue }
}

// MARK: - 时间（unix 秒/毫秒 或 RFC3339 字符串）
struct FlexDate: Codable, Hashable {
    let date: Date?

    init(_ date: Date?) { self.date = date }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let n = try? c.decode(Double.self) {
            // 毫秒 / 秒
            let secs = n > 10_000_000_000 ? n / 1000 : n
            self.date = Date(timeIntervalSince1970: secs)
            return
        }
        if let s = try? c.decode(String.self) {
            let f1 = ISO8601DateFormatter()
            f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f1.date(from: s) { self.date = d; return }
            let f2 = ISO8601DateFormatter()
            if let d = f2.date(from: s) { self.date = d; return }
            let f3 = DateFormatter()
            f3.dateFormat = "yyyy-MM-dd HH:mm:ss"
            f3.timeZone = TimeZone(identifier: "UTC")
            self.date = f3.date(from: s)
            return
        }
        self.date = nil
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if let d = date { try c.encode(d.timeIntervalSince1970) } else { try c.encodeNil() }
    }

    var text: String {
        guard let d = date else { return "-" }
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: d)
    }
}

// MARK: - 任务
struct TaskItem: Codable, Identifiable, Hashable {
    var id: Int64
    var title: String?
    var status: String?
    var phase: String?
    var objective: String?
    var category: String?
    var created_at: FlexDate?
    var updated_at: FlexDate?
    var coverage_enabled: Bool?
    var workers: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, status, phase, objective, category, created_at, updated_at, coverage_enabled, workers
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int64.self, forKey: .id)) ?? 0
        title = try? c.decodeIfPresent(String.self, forKey: .title)
        status = try? c.decodeIfPresent(String.self, forKey: .status)
        phase = try? c.decodeIfPresent(String.self, forKey: .phase)
        objective = try? c.decodeIfPresent(String.self, forKey: .objective)
        category = try? c.decodeIfPresent(String.self, forKey: .category)
        created_at = try? c.decodeIfPresent(FlexDate.self, forKey: .created_at)
        updated_at = try? c.decodeIfPresent(FlexDate.self, forKey: .updated_at)
        coverage_enabled = try? c.decodeIfPresent(Bool.self, forKey: .coverage_enabled)
        workers = try? c.decodeIfPresent(Int.self, forKey: .workers)
    }

    var displayTitle: String { (title?.isEmpty == false ? title! : "未命名任务") }
    var displayStatus: String { status ?? "unknown" }
    var displayPhase: String { phase ?? "-" }
}

// MARK: - 发现（漏洞）
struct Finding: Codable, Identifiable, Hashable {
    var id: Int64
    var title: String?
    var severity: String?
    var status: String?
    var asset: String?
    var url: String?
    var summary: String?
    var description: String?
    var cve: String?
    var created_at: FlexDate?
    var task_id: Int64?

    enum CodingKeys: String, CodingKey { case id, title, severity, status, asset, url, summary, description, cve, created_at, task_id }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int64.self, forKey: .id)) ?? 0
        title = try? c.decodeIfPresent(String.self, forKey: .title)
        severity = try? c.decodeIfPresent(String.self, forKey: .severity)
        status = try? c.decodeIfPresent(String.self, forKey: .status)
        asset = try? c.decodeIfPresent(String.self, forKey: .asset)
        url = try? c.decodeIfPresent(String.self, forKey: .url)
        summary = try? c.decodeIfPresent(String.self, forKey: .summary)
        description = try? c.decodeIfPresent(String.self, forKey: .description)
        cve = try? c.decodeIfPresent(String.self, forKey: .cve)
        created_at = try? c.decodeIfPresent(FlexDate.self, forKey: .created_at)
        task_id = try? c.decodeIfPresent(Int64.self, forKey: .task_id)
    }

    var displayTitle: String { title ?? summary ?? "未命名发现" }
    var displaySeverity: String { (severity ?? "info").lowercased() }
}

// MARK: - 资产
struct Asset: Codable, Identifiable, Hashable {
    var id: String
    var kind: String?
    var value: String?
    var company: String?
    var status: String?
    var tested: Bool?
    var source: String?
    var updated_at: FlexDate?

    enum CodingKeys: String, CodingKey { case id, kind, value, company, status, tested, source, updated_at }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else if let i = try? c.decode(Int64.self, forKey: .id) { id = String(i) }
        else { id = UUID().uuidString }
        kind = try? c.decodeIfPresent(String.self, forKey: .kind)
        value = try? c.decodeIfPresent(String.self, forKey: .value)
        company = try? c.decodeIfPresent(String.self, forKey: .company)
        status = try? c.decodeIfPresent(String.self, forKey: .status)
        tested = try? c.decodeIfPresent(Bool.self, forKey: .tested)
        source = try? c.decodeIfPresent(String.self, forKey: .source)
        updated_at = try? c.decodeIfPresent(FlexDate.self, forKey: .updated_at)
    }

    var displayValue: String { value ?? id }
}

// MARK: - 命令执行记录
struct CommandRecord: Codable, Identifiable, Hashable {
    var id: Int64
    var tool: String?
    var command: String?
    var output: String?
    var status: String?
    var task_id: Int64?
    var created_at: FlexDate?

    enum CodingKeys: String, CodingKey { case id, tool, command, output, status, task_id, created_at }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int64.self, forKey: .id)) ?? 0
        tool = try? c.decodeIfPresent(String.self, forKey: .tool)
        command = try? c.decodeIfPresent(String.self, forKey: .command)
        output = try? c.decodeIfPresent(String.self, forKey: .output)
        status = try? c.decodeIfPresent(String.self, forKey: .status)
        task_id = try? c.decodeIfPresent(Int64.self, forKey: .task_id)
        created_at = try? c.decodeIfPresent(FlexDate.self, forKey: .created_at)
    }
}

// MARK: - 会话 / 消息
struct ConversationItem: Codable, Identifiable, Hashable {
    var id: Int64
    var title: String?
    var kind: String?
    var updated_at: FlexDate?
    var task_id: Int64?
    enum CodingKeys: String, CodingKey { case id, title, kind, updated_at, task_id }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int64.self, forKey: .id)) ?? 0
        title = try? c.decodeIfPresent(String.self, forKey: .title)
        kind = try? c.decodeIfPresent(String.self, forKey: .kind)
        updated_at = try? c.decodeIfPresent(FlexDate.self, forKey: .updated_at)
        task_id = try? c.decodeIfPresent(Int64.self, forKey: .task_id)
    }
}

struct ChatMessage: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var role: String
    var content: String
    var created_at: FlexDate?

    enum CodingKeys: String, CodingKey { case role, content, created_at, seq, id }
    init(role: String, content: String) { self.role = role; self.content = content; self.created_at = FlexDate(Date()) }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let i = try? c.decode(Int64.self, forKey: .seq) { id = "seq-\(i)" }
        else if let s = try? c.decode(String.self, forKey: .id) { id = s }
        role = (try? c.decode(String.self, forKey: .role)) ?? "assistant"
        content = (try? c.decodeIfPresent(String.self, forKey: .content)) ?? ""
        created_at = try? c.decodeIfPresent(FlexDate.self, forKey: .created_at)
    }
}

// MARK: - Activity（SSE 实时流）
struct ActivityEvent: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var kind: String?
    var summary: String?
    var detail: String?
    var task_id: Int64?
    var ts: FlexDate?
    var raw: String?

    enum CodingKeys: String, CodingKey { case kind, summary, detail, task_id, ts, seq, id, raw }
    init(text: String) { self.raw = text; self.summary = text; self.kind = "raw"; self.ts = FlexDate(Date()) }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let i = try? c.decode(Int64.self, forKey: .seq) { id = "seq-\(i)" }
        kind = try? c.decodeIfPresent(String.self, forKey: .kind)
        summary = try? c.decodeIfPresent(String.self, forKey: .summary)
        detail = try? c.decodeIfPresent(String.self, forKey: .detail)
        task_id = try? c.decodeIfPresent(Int64.self, forKey: .task_id)
        ts = try? c.decodeIfPresent(FlexDate.self, forKey: .ts)
    }
    var display: String { summary ?? detail ?? kind ?? "" }
}

// MARK: - Skill / CVE
struct Skill: Codable, Identifiable, Hashable {
    var id: String
    var n: String
    var cat: String
    var phase: String
    var d: String
    var cmds: [String]
    var tools: [String]
    var tags: [String]
    var name: String { n }
}

struct CVERow: Identifiable, Hashable {
    var id: String
    var title: String
    var severity: String
    var score: Double
    var cwe: String
    var vendor: String
    var published: String
    var refs: Int
    var skills: [String]
}

// MARK: - 设置/系统
struct LLMProfile: Codable, Identifiable, Hashable {
    var id: Int64
    var name: String?
    var provider: String?
    var model: String?
    var base_url: String?
    var active: Bool?
    enum CodingKeys: String, CodingKey { case id, name, provider, model, base_url, active }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int64.self, forKey: .id)) ?? 0
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        provider = try? c.decodeIfPresent(String.self, forKey: .provider)
        model = try? c.decodeIfPresent(String.self, forKey: .model)
        base_url = try? c.decodeIfPresent(String.self, forKey: .base_url)
        active = try? c.decodeIfPresent(Bool.self, forKey: .active)
    }
}

struct AgentItem: Codable, Identifiable, Hashable {
    var id: String
    var key: String?
    var name: String?
    var role: String?
    enum CodingKeys: String, CodingKey { case id, key, name, role }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .key) { id = s; key = s }
        else { id = UUID().uuidString; key = nil }
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        role = try? c.decodeIfPresent(String.self, forKey: .role)
    }
}

struct ToolItem: Codable, Identifiable, Hashable {
    var id: String
    var key: String?
    var desc: String?
    var agents: [String]?
    var enabled: Bool?
    enum CodingKeys: String, CodingKey { case id, key, desc, agents, enabled }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .key) { id = s; key = s }
        else { id = UUID().uuidString; key = nil }
        desc = try? c.decodeIfPresent(String.self, forKey: .desc)
        agents = try? c.decodeIfPresent([String].self, forKey: .agents)
        enabled = try? c.decodeIfPresent(Bool.self, forKey: .enabled)
    }
}
