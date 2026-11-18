import SwiftUI

struct TaskDetailView: View {
    let task: TaskItem
    @State private var tab = 0
    @State private var detail: [String: AnyJSON] = [:]
    @State private var findings: [Finding] = []
    @State private var commands: [CommandRecord] = []
    @State private var coverage: [String: AnyJSON] = [:]
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("概览").tag(0)
                Text("发现 \(findings.count)").tag(1)
                Text("执行 \(commands.count)").tag(2)
                Text("覆盖").tag(3)
            }
            .pickerStyle(.segmented)
            .padding(12)

            TabView(selection: $tab) {
                overview.tag(0)
                findingsTab.tag(1)
                commandsTab.tag(2)
                coverageTab.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .background(ArtexTheme.bg)
        .navigationTitle(task.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("启动 / 继续") { control("resume") }
                    Button("暂停") { control("pause") }
                    Button("停止") { control("stop") }
                    Divider()
                    Button("刷新") { Task { await load() } }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .task { await load() }
    }

    // MARK: - 概览
    private var overview: some View {
        ScrollView {
            VStack(spacing: 12) {
                Card(title: "任务信息") {
                    VStack(alignment: .leading, spacing: 6) {
                        kv("ID", "#\(task.id)")
                        kv("状态", task.displayStatus)
                        kv("阶段", task.displayPhase)
                        kv("分类", task.category ?? "-")
                        kv("创建", task.created_at?.text ?? "-")
                    }
                }
                if let obj = task.objective, !obj.isEmpty {
                    Card(title: "目标") {
                        Text(obj).font(.system(size: 13)).foregroundStyle(ArtexTheme.text)
                    }
                }
                Card(title: "原始数据") {
                    Text(detail.map { "\($0.key): \($0.value.display)" }.sorted().joined(separator: "\n"))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(ArtexTheme.dim)
                }
                if let message {
                    Text(message).font(.system(size: 12)).foregroundStyle(ArtexTheme.accent)
                }
            }.padding(14)
        }
    }

    private func kv(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.system(size: 12)).foregroundStyle(ArtexTheme.dim)
            Spacer()
            Text(v).font(.system(size: 12, design: .monospaced)).foregroundStyle(ArtexTheme.text)
        }
    }

    // MARK: - 发现
    private var findingsTab: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(findings) { f in
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Pill(text: f.displaySeverity.uppercased(), color: ArtexTheme.severityColor(f.displaySeverity))
                                Spacer()
                                if let cv = f.cve, !cv.isEmpty { Pill(text: cv, color: ArtexTheme.low) }
                            }
                            Text(f.displayTitle).font(.system(size: 14, weight: .semibold)).foregroundStyle(ArtexTheme.text)
                            if let a = f.asset ?? f.url, !a.isEmpty {
                                Text(a).font(.system(size: 11, design: .monospaced)).foregroundStyle(ArtexTheme.dim)
                            }
                            if let s = f.summary ?? f.description, !s.isEmpty {
                                Text(s).font(.system(size: 12)).foregroundStyle(ArtexTheme.dim).lineLimit(4)
                            }
                            HStack {
                                Button("复测") { Task { try? await FindingAPI.startRetest(f.id) } }
                                    .font(.system(size: 12)).foregroundStyle(ArtexTheme.accent)
                                Spacer()
                                Menu("状态") {
                                    Button("已修复") { Task { try? await FindingAPI.patch(f.id, status: "fixed") } }
                                    Button("仍存在") { Task { try? await FindingAPI.patch(f.id, status: "open") } }
                                    Button("已忽略") { Task { try? await FindingAPI.patch(f.id, status: "ignored") } }
                                }.font(.system(size: 12))
                            }
                        }
                    }
                }
                if findings.isEmpty { EmptyHint(text: "该任务还没有发现") }
            }.padding(14)
        }
    }

    // MARK: - 执行记录
    private var commandsTab: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(commands) { c in
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Pill(text: c.tool ?? "tool", color: ArtexTheme.accent)
                                Pill(text: c.status ?? "-", color: ArtexTheme.dim)
                                Spacer()
                                Text(c.created_at?.text ?? "").font(.system(size: 10)).foregroundStyle(ArtexTheme.dim)
                            }
                            Text(c.command ?? "").font(.system(size: 11, design: .monospaced)).foregroundStyle(ArtexTheme.text).lineLimit(4)
                            if let o = c.output, !o.isEmpty {
                                Text(String(o.prefix(600))).font(.system(size: 10, design: .monospaced)).foregroundStyle(ArtexTheme.dim).lineLimit(8)
                            }
                        }
                    }
                }
                if commands.isEmpty { EmptyHint(text: "暂无工具执行记录") }
            }.padding(14)
        }
    }

    // MARK: - 覆盖
    private var coverageTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Card(title: "覆盖数据") {
                    Text(coverage.map { "\($0.key): \($0.value.display)" }.sorted().joined(separator: "\n"))
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(ArtexTheme.text)
                }
            }.padding(14)
        }
    }

    private func control(_ action: String) {
        Task {
            do {
                try await TaskAPI.control(task.id, action: action)
                message = "已发送指令：\(action)"
                await load()
            } catch { message = error.localizedDescription }
        }
    }

    private func load() async {
        busy = true; defer { busy = false }
        detail = (try? await TaskAPI.detail(task.id)) ?? [:]
        findings = (try? await FindingAPI.list(task: task.id)) ?? []
        let all = (try? await OpsAPI.commands()) ?? []
        commands = all.filter { $0.task_id == task.id || $0.task_id == nil }
        coverage = (try? await TaskAPI.coverage(task.id)) ?? [:]
    }
}
