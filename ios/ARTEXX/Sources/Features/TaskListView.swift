import SwiftUI

/// 任务页 —— 对齐 function/tasks/page.tsx
/// 结构：Tabs(当前任务/已归档) + 搜索 + 状态筛选 + 分类筛选 + 新建任务
struct TaskListView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject private var localStore = LocalTaskStore.shared

    @State private var activeTab = 0                 // 0=当前任务 1=已归档
    @State private var query = ""
    @State private var statusFilter = "全部状态"
    @State private var categoryFilter = "全部分类"
    @State private var showNewTask = false

    @State private var remoteTasks: [TaskItem] = []
    @State private var loading = false

    private let statusOptions = ["全部状态", "运行中", "待运行", "已完成", "失败", "已停止"]

    var body: some View {
        VStack(spacing: 0) {
            PageTitle("任务", sub: "管理渗透测试任务 · \(visibleCount) 个", action: AnyView(
                ArtexButton(title: "新建任务", icon: "plus", compact: true) { showNewTask = true }
            ))

            ArtexTabs(items: ["当前任务", "已归档"], selection: $activeTab)

            // 筛选栏
            VStack(spacing: 8) {
                SearchField(placeholder: "搜索任务名称 / 描述 / ID", text: $query)
                HStack(spacing: 8) {
                    FilterMenu(label: "状态", options: statusOptions, selection: $statusFilter)
                    FilterMenu(label: "任务分类", options: ["全部分类", "Web 渗透", "内网", "云原生", "红队"], selection: $categoryFilter)
                    Spacer()
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)

            if loading && rows.isEmpty {
                Spacer(); ProgressView().tint(ArtexTheme.accent); Spacer()
            } else if rows.isEmpty {
                EmptyHint(text: activeTab == 0 ? "还没有任务，点右上角新建" : "暂无归档任务")
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(rows) { t in
                            taskCard(t)
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 20)
                }
            }
        }
        .background(ArtexTheme.bg)
        .sheet(isPresented: $showNewTask) { NewTaskSheet() }
        .task { await load() }
    }

    // MARK: - 行数据（统一成本地结构）
    struct Row: Identifiable {
        var id: String
        var title: String
        var objective: String
        var status: String
        var targets: Int
        var steps: Int
        var findings: Int
        var sev: (c: Int, h: Int, m: Int)
        var updated: Date?
        var category: String
        var localID: UUID?
    }

    private var rows: [Row] {
        var list: [Row] = []

        if store.offlineMode {
            list = localStore.tasks.map { t in
                let s = t.severityCount
                return Row(id: t.id.uuidString, title: t.title, objective: t.objective,
                           status: t.status, targets: t.targets.count, steps: t.steps.count,
                           findings: t.findings.count, sev: (s.critical, s.high, s.medium),
                           updated: t.updatedAt, category: "", localID: t.id)
            }
        } else {
            list = remoteTasks.map { t in
                Row(id: String(t.id), title: t.displayTitle, objective: t.objective ?? "",
                    status: t.displayStatus, targets: 0, steps: 0, findings: 0,
                    sev: (0, 0, 0), updated: t.updated_at?.date,
                    category: t.category ?? "", localID: nil)
            }
        }

        // 搜索
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            list = list.filter {
                $0.title.lowercased().contains(q) || $0.objective.lowercased().contains(q) || $0.id.lowercased().contains(q)
            }
        }
        // 状态
        if statusFilter != "全部状态" {
            list = list.filter { statusLabel($0.status) == statusFilter }
        }
        // 归档 Tab
        if activeTab == 1 {
            list = list.filter { ["done", "failed", "stopped"].contains($0.status) }
        } else {
            list = list.filter { !["done", "failed", "stopped"].contains($0.status) || store.offlineMode }
        }
        return list
    }

    private var visibleCount: Int { rows.count }

    private func taskCard(_ t: Row) -> some View {
        NavigationLink {
            if let lid = t.localID {
                LocalTaskDetailView(taskID: lid)
            } else {
                RemoteTaskDetailView(taskID: Int64(t.id) ?? 0, title: t.title)
            }
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Circle().fill(statusTint(t.status)).frame(width: 6, height: 6)
                    Text(t.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(ArtexTheme.text)
                        .lineLimit(1)
                    Spacer()
                    Pill(text: statusLabel(t.status), color: statusTint(t.status))
                }

                if !t.objective.isEmpty {
                    Text(t.objective)
                        .font(.system(size: 11))
                        .foregroundStyle(ArtexTheme.dim)
                        .lineLimit(2)
                }

                HStack(spacing: 10) {
                    if t.targets > 0 { metric("scope", "\(t.targets)") }
                    if t.steps > 0 { metric("list.number", "\(t.steps)") }
                    if t.findings > 0 { metric("ladybug", "\(t.findings)") }
                    Spacer()
                    Text(fmtRel(t.updated)).font(.system(size: 9)).foregroundStyle(ArtexTheme.dim)
                }

                if t.sev.c + t.sev.h + t.sev.m > 0 {
                    HStack(spacing: 5) {
                        if t.sev.c > 0 { Pill(text: "C \(t.sev.c)", color: ArtexTheme.critical) }
                        if t.sev.h > 0 { Pill(text: "H \(t.sev.h)", color: ArtexTheme.high) }
                        if t.sev.m > 0 { Pill(text: "M \(t.sev.m)", color: ArtexTheme.medium) }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ArtexTheme.surface)
            .overlay(RoundedRectangle(cornerRadius: ArtexTheme.radius).stroke(ArtexTheme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: ArtexTheme.radius))
        }
        .buttonStyle(.plain)
    }

    private func metric(_ icon: String, _ v: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 8))
            Text(v).font(.system(size: 9, design: .monospaced))
        }.foregroundStyle(ArtexTheme.dim)
    }

    private func statusLabel(_ s: String) -> String {
        switch s {
        case "running": return "运行中"
        case "pending": return "待运行"
        case "done", "completed": return "已完成"
        case "failed", "error": return "失败"
        case "stopped", "paused": return "已停止"
        default: return s
        }
    }

    private func statusTint(_ s: String) -> Color {
        switch s {
        case "running": return ArtexTheme.accent
        case "pending": return ArtexTheme.dim
        case "done", "completed": return ArtexTheme.ok
        case "failed", "error": return ArtexTheme.critical
        case "stopped", "paused": return ArtexTheme.medium
        default: return ArtexTheme.dim
        }
    }

    private func load() async {
        guard !store.offlineMode else { return }
        loading = true
        defer { loading = false }
        remoteTasks = (try? await TaskAPI.list()) ?? []
    }
}

// MARK: - 新建任务（对齐 SheetContent：名称/分类/描述/目标）
struct NewTaskSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var localStore = LocalTaskStore.shared
    @State private var name = ""
    @State private var category = "Web 渗透"
    @State private var description = ""
    @State private var goal = ""
    @State private var scope = ""
    @State private var picked: [Skill] = []

    private let categories = ["Web 渗透", "内网", "云原生", "红队", "其他"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("新建任务").font(.system(size: 17, weight: .semibold)).foregroundStyle(ArtexTheme.text)
                        Text("填写测试对象与目标，高级参数可按需展开。")
                            .font(.system(size: 11)).foregroundStyle(ArtexTheme.dim)
                    }

                    ArtexField(label: "名称（可选）",
                               placeholder: "给任务起个便于识别的名字，例如：Acme 官网渗透",
                               text: $name)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("任务分类").font(.system(size: 11, weight: .medium)).foregroundStyle(ArtexTheme.text)
                        FilterMenu(label: "选择分类", options: categories, selection: $category)
                        Text("用于任务列表筛选和归档，不影响 Agent 执行。")
                            .font(.system(size: 10)).foregroundStyle(ArtexTheme.dim)
                    }

                    ArtexField(label: "描述",
                               placeholder: "测试对象与背景，例如：测试 example.com 这个站点",
                               text: $description, multiline: true)

                    ArtexField(label: "授权目标",
                               placeholder: "每行一个域名 / IP，如 example.com 或 192.168.1.10",
                               text: $scope, multiline: true,
                               desc: "Agent 只测试这些目标")

                    ArtexField(label: "目标",
                               placeholder: "要达成什么，例如：拿下后台管理权限、获取服务器权限",
                               text: $goal, multiline: true)

                    // 技能编排
                    VStack(alignment: .leading, spacing: 6) {
                        Text("套用技能编排").font(.system(size: 11, weight: .medium)).foregroundStyle(ArtexTheme.text)
                        NavigationLink { SkillPickerView(picked: $picked) } label: {
                            HStack {
                                Text(picked.isEmpty ? "未选择" : "已选 \(picked.count) 项")
                                    .font(.system(size: 12)).foregroundStyle(ArtexTheme.text)
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(ArtexTheme.dim)
                            }
                            .padding(.horizontal, 9).padding(.vertical, 9)
                            .background(ArtexTheme.bg)
                            .overlay(RoundedRectangle(cornerRadius: ArtexTheme.radiusSm).stroke(ArtexTheme.input, lineWidth: 0.8))
                            .clipShape(RoundedRectangle(cornerRadius: ArtexTheme.radiusSm))
                        }
                    }

                    if !LLMClient.shared.config.ready {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle").font(.system(size: 10))
                            Text("还没配置模型，任务跑不起来").font(.system(size: 11))
                            Spacer()
                        }
                        .foregroundStyle(ArtexTheme.medium)
                        .padding(9)
                        .background(ArtexTheme.medium.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: ArtexTheme.radiusSm))
                    }
                }
                .padding(16)
            }
            .background(ArtexTheme.bg)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.foregroundStyle(ArtexTheme.dim)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") { create() }
                        .font(.system(size: 12, weight: .semibold))
                        .disabled(description.isEmpty && goal.isEmpty)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func create() {
        let targets = scope.split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let title = name.isEmpty ? (description.isEmpty ? "未命名任务" : String(description.prefix(24))) : name
        let t = localStore.create(title: title,
                                  objective: goal.isEmpty ? description : goal,
                                  targets: targets,
                                  skillIDs: picked.map { $0.id })
        // 建完直接开跑
        localStore.run(t.id)
        dismiss()
    }
}

/// 远端任务详情（连服务端时）
struct RemoteTaskDetailView: View {
    let taskID: Int64
    let title: String
    @State private var detail: [String: AnyJSON] = [:]
    @State private var findings: [Finding] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Card(title: "任务信息") {
                    VStack(alignment: .leading, spacing: 6) {
                        FieldRow(label: "ID", value: "#\(taskID)")
                        FieldRow(label: "名称", value: title)
                    }
                }
                Card(title: "发现 \(findings.count)") {
                    if findings.isEmpty {
                        EmptyHint(text: "暂无发现")
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(findings) { f in
                                HStack(spacing: 6) {
                                    Pill(text: f.displaySeverity.uppercased(), color: ArtexTheme.severityColor(f.displaySeverity))
                                    Text(f.displayTitle).font(.system(size: 11)).foregroundStyle(ArtexTheme.text).lineLimit(1)
                                    Spacer()
                                }
                            }
                        }
                    }
                }
            }.padding(16)
        }
        .background(ArtexTheme.bg)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            detail = (try? await TaskAPI.detail(taskID)) ?? [:]
            findings = (try? await FindingAPI.list(task: taskID)) ?? []
        }
    }
}
