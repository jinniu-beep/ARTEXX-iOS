import Foundation

/// 本地任务：离线模式下真正可用的任务系统，数据存本地 JSON。
struct LocalTask: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var objective: String
    var targets: [String]
    var status: String = "pending"   // pending / running / done / failed / stopped
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var steps: [LocalAgent.AgentStep] = []
    var findings: [LocalAgent.LocalFinding] = []
    var assets: [String] = []
    var summary: String = ""
    var skillIDs: [String] = []

    var severityCount: (critical: Int, high: Int, medium: Int, low: Int) {
        var c = 0, h = 0, m = 0, l = 0
        for f in findings {
            switch f.severity.lowercased() {
            case "critical": c += 1
            case "high": h += 1
            case "medium": m += 1
            default: l += 1
            }
        }
        return (c, h, m, l)
    }
}

@MainActor
final class LocalTaskStore: ObservableObject {
    static let shared = LocalTaskStore()
    @Published private(set) var tasks: [LocalTask] = []
    @Published var runningTaskID: UUID?

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ARTEXX", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("local-tasks.json")
    }()

    private init() { load() }

    // MARK: - 持久化
    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([LocalTask].self, from: data) else { return }
        tasks = list.sorted { $0.createdAt > $1.createdAt }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(tasks) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - 增删改
    @discardableResult
    func create(title: String, objective: String, targets: [String], skillIDs: [String] = []) -> LocalTask {
        let t = LocalTask(title: title, objective: objective, targets: targets, skillIDs: skillIDs)
        tasks.insert(t, at: 0)
        save()
        return t
    }

    func update(_ task: LocalTask) {
        guard let i = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var t = task
        t.updatedAt = Date()
        tasks[i] = t
        save()
    }

    func delete(_ id: UUID) {
        tasks.removeAll { $0.id == id }
        if runningTaskID == id { runningTaskID = nil }
        save()
    }

    func clear() {
        tasks.removeAll()
        save()
    }

    func task(_ id: UUID) -> LocalTask? { tasks.first { $0.id == id } }

    // MARK: - 运行
    func run(_ id: UUID) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        var t = tasks[idx]

        guard LLMClient.shared.config.ready else {
            t.status = "failed"
            t.summary = "未配置模型：请到「模型」页填写 API Key"
            tasks[idx] = t
            save()
            return
        }

        t.status = "running"
        t.steps = []
        t.findings = []
        t.assets = []
        t.summary = ""
        tasks[idx] = t
        save()
        runningTaskID = id

        let agent = LocalAgent.shared
        agent.onUpdate = { [weak self] steps, findings, assets in
            guard let self else { return }
            guard let i = self.tasks.firstIndex(where: { $0.id == id }) else { return }
            var task = self.tasks[i]
            task.steps = steps
            task.findings = findings
            task.assets = assets
            task.updatedAt = Date()
            self.tasks[i] = task
        }

        let objective = buildObjective(t)
        agent.start(objective: objective)

        // 轮询 agent 状态，结束后落盘
        Task {
            while agent.running {
                try? await Task.sleep(nanoseconds: 600_000_000)
            }
            if let i = self.tasks.firstIndex(where: { $0.id == id }) {
                var task = self.tasks[i]
                task.steps = agent.steps
                task.findings = agent.findings
                task.assets = agent.assets
                task.summary = agent.steps.last(where: { $0.role == "final" })?.detail ?? ""
                task.status = agent.lastError == nil ? "done" : "failed"
                if let e = agent.lastError, task.summary.isEmpty { task.summary = e }
                task.updatedAt = Date()
                self.tasks[i] = task
                self.save()
            }
            self.runningTaskID = nil
        }
    }

    func stop(_ id: UUID) {
        LocalAgent.shared.stop()
        if let i = tasks.firstIndex(where: { $0.id == id }) {
            tasks[i].status = "stopped"
            tasks[i].updatedAt = Date()
            save()
        }
        runningTaskID = nil
    }

    /// 把任务 + 技能编排拼成给 Agent 的完整目标
    private func buildObjective(_ t: LocalTask) -> String {
        var s = "任务：\(t.title)\n目标：\(t.objective)\n授权目标列表：\n"
        s += t.targets.map { "- \($0)" }.joined(separator: "\n")
        if !t.skillIDs.isEmpty {
            let lib = SkillLibrary.shared
            let skills = t.skillIDs.compactMap { lib.byID($0) }
            if !skills.isEmpty {
                s += "\n\n建议按以下技能顺序执行：\n"
                s += skills.map { "- \($0.n)：\($0.d)" }.joined(separator: "\n")
            }
        }
        s += "\n\n请依次侦察每个目标，发现漏洞用 report_finding 记录，最后给出总结。"
        return s
    }
}
