import SwiftUI

struct TaskListView: View {
    @EnvironmentObject var store: AppStore
    @State private var tasks: [TaskItem] = []
    @State private var loading = false
    @State private var showNew = false
    @State private var filter = "全部"

    private var filters: [String] { ["全部", "running", "paused", "done", "failed"] }

    var body: some View {
        NavigationStack {
            if store.offlineMode {
                OfflineNotice(what: "任务列表")
            } else {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(filters, id: \.self) { f in
                            Button {
                                filter = f
                            } label: {
                                Pill(text: f, color: filter == f ? ArtexTheme.accent : ArtexTheme.dim)
                            }
                        }
                    }.padding(.horizontal, 14).padding(.vertical, 8)
                }

                if loading && tasks.isEmpty {
                    Spacer(); ProgressView().tint(ArtexTheme.accent); Spacer()
                } else if visible.isEmpty {
                    EmptyHint(text: "还没有任务。点右上角 + 新建一个渗透任务。")
                    Spacer()
                } else {
                    List {
                        ForEach(visible) { t in
                            NavigationLink {
                                TaskDetailView(task: t)
                            } label: {
                                row(t)
                            }
                            .listRowBackground(ArtexTheme.surface)
                        }
                        .onDelete { idx in
                            let items = idx.map { visible[$0] }
                            Task {
                                for t in items { try? await TaskAPI.remove(t.id) }
                                await load()
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .refreshable { await load() }
                }
            }
            .background(ArtexTheme.bg)
            .navigationTitle("任务")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showNew = true } label: { Image(systemName: "plus") }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                }
            }
            .sheet(isPresented: $showNew) {
                NewTaskView { await load() }
            }
            .task { await load() }
            }
        }
    }

    private var visible: [TaskItem] {
        filter == "全部" ? tasks : tasks.filter { ($0.status ?? "") == filter }
    }

    private func row(_ t: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(t.displayTitle).font(.system(size: 15, weight: .semibold)).foregroundStyle(ArtexTheme.text).lineLimit(1)
                Spacer()
                Pill(text: t.displayStatus, color: statusColor(t.displayStatus))
            }
            HStack(spacing: 10) {
                Label(t.displayPhase, systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                Text(t.updated_at?.text ?? t.created_at?.text ?? "-")
                Text("#\(t.id)")
            }
            .font(.system(size: 11, design: .monospaced)).foregroundStyle(ArtexTheme.dim)
            if let obj = t.objective, !obj.isEmpty {
                Text(obj).font(.system(size: 12)).foregroundStyle(ArtexTheme.dim).lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private func statusColor(_ s: String) -> Color {
        switch s {
        case "running": return ArtexTheme.ok
        case "paused": return ArtexTheme.medium
        case "failed", "error": return ArtexTheme.critical
        case "done", "completed": return ArtexTheme.low
        default: return ArtexTheme.dim
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        tasks = (try? await TaskAPI.list()) ?? []
    }
}

struct NewTaskView: View {
    @Environment(\.dismiss) var dismiss
    var onCreated: () async -> Void
    @State private var title = ""
    @State private var objective = ""
    @State private var scope = ""
    @State private var busy = false
    @State private var error: String?
    @State private var picked: [Skill] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("任务标题", text: $title)
                    TextField("目标（一句话）", text: $objective, axis: .vertical).lineLimit(2...4)
                    TextField("范围，每行一个域名/IP/CIDR", text: $scope, axis: .vertical).lineLimit(3...8)
                }
                Section("套用技能编排（可选）") {
                    NavigationLink {
                        SkillPickerView(picked: $picked)
                    } label: {
                        HStack {
                            Text("已选 \(picked.count) 项技能")
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(ArtexTheme.dim)
                        }
                    }
                }
                if !picked.isEmpty {
                    Section("作战序列预览") {
                        Text(Playbook(skills: picked).briefMarkdown)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(ArtexTheme.dim)
                    }
                }
                if let error { Section { Text(error).foregroundStyle(ArtexTheme.critical) } }
            }
            .scrollContentBackground(.hidden)
            .background(ArtexTheme.bg)
            .navigationTitle("新建任务")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "创建中…" : "创建") { Task { await create() } }
                        .disabled(busy || title.isEmpty)
                }
            }
        }
    }

    private func create() async {
        busy = true; defer { busy = false }
        let lines = scope.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var body = objective
        if !picked.isEmpty {
            body += "\n\n【技能编排】\n" + picked.map { "- \($0.n)(\($0.id)): \($0.d)" }.joined(separator: "\n")
        }
        do {
            _ = try await TaskAPI.create(title: title, objective: body, scope: lines)
            await onCreated()
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct SkillPickerView: View {
    @Binding var picked: [Skill]
    @State private var query = ""
    @State private var category: String?
    private let lib = SkillLibrary.shared

    var body: some View {
        List {
            ForEach(lib.filtered(category: category, query: query)) { s in
                Button {
                    if let i = picked.firstIndex(where: { $0.id == s.id }) { picked.remove(at: i) }
                    else { picked.append(s) }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: picked.contains(where: { $0.id == s.id }) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(picked.contains(where: { $0.id == s.id }) ? ArtexTheme.accent : ArtexTheme.dim)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(s.n).font(.system(size: 14, weight: .medium)).foregroundStyle(ArtexTheme.text)
                            Text(s.d).font(.system(size: 11)).foregroundStyle(ArtexTheme.dim).lineLimit(2)
                            HStack(spacing: 6) {
                                Pill(text: s.cat, color: ArtexTheme.low)
                                Pill(text: s.phase, color: ArtexTheme.dim)
                            }
                        }
                    }
                }
                .listRowBackground(ArtexTheme.surface)
            }
        }
        .searchable(text: $query, prompt: "搜技能名 / 工具 / 标签")
        .scrollContentBackground(.hidden)
        .background(ArtexTheme.bg)
        .navigationTitle("选技能")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("全部") { category = nil }
                    ForEach(lib.categories, id: \.0) { c in
                        Button("\(c.0) (\(c.1))") { category = c.0 }
                    }
                } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
            }
        }
    }
}
