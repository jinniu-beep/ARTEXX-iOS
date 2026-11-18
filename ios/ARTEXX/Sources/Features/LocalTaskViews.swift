import SwiftUI

/// 新建本地任务
struct NewLocalTaskView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var store = LocalTaskStore.shared
    @State private var title = ""
    @State private var objective = ""
    @State private var targets = ""
    @State private var picked: [Skill] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("任务标题", text: $title)
                    TextField("目标（一句话）", text: $objective, axis: .vertical).lineLimit(2...4)
                    TextField("授权目标，每行一个域名/IP", text: $targets, axis: .vertical).lineLimit(3...8)
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
                    Section("作战序列") {
                        Text(Playbook(skills: picked).briefMarkdown)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(ArtexTheme.dim)
                    }
                }
                Section {
                    if !LLMClient.shared.config.ready {
                        Text("⚠️ 还没配置模型，任务跑不起来")
                            .font(.system(size: 11)).foregroundStyle(ArtexTheme.medium)
                        NavigationLink("去配置模型") { LLMConfigView() }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(ArtexTheme.bg)
            .navigationTitle("新建本地任务")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") { create() }.disabled(title.isEmpty)
                }
            }
        }
    }

    private func create() {
        let list = targets.split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        store.create(title: title,
                     objective: objective.isEmpty ? title : objective,
                     targets: list,
                     skillIDs: picked.map { $0.id })
        dismiss()
    }
}

/// 本地任务详情：实时看 Agent 每一步
struct LocalTaskDetailView: View {
    let taskID: UUID
    @ObservedObject private var store = LocalTaskStore.shared
    @ObservedObject private var agent = LocalAgent.shared
    @State private var tab = 0

    private var task: LocalTask? { store.task(taskID) }
    private var isThisRunning: Bool { store.runningTaskID == taskID }

    var body: some View {
        Group {
            if let t = task {
                VStack(spacing: 0) {
                    Picker("", selection: $tab) {
                        Text("概览").tag(0)
                        Text("过程 \(t.steps.count)").tag(1)
                        Text("发现 \(t.findings.count)").tag(2)
                        Text("资产 \(t.assets.count)").tag(3)
                    }
                    .pickerStyle(.segmented).padding(12)

                    TabView(selection: $tab) {
                        overview(t).tag(0)
                        stepsTab(t).tag(1)
                        findingsTab(t).tag(2)
                        assetsTab(t).tag(3)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        if isThisRunning {
                            Button("停止") { store.stop(taskID) }
                                .foregroundStyle(ArtexTheme.critical)
                        } else {
                            Button("运行") { store.run(taskID) }
                        }
                    }
                }
            } else {
                EmptyHint(text: "任务已删除")
            }
        }
        .background(ArtexTheme.bg)
        .navigationTitle(task?.title ?? "任务")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func overview(_ t: LocalTask) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                Card(title: "状态") {
                    VStack(alignment: .leading, spacing: 6) {
                        kv("状态", statusText(t.status))
                        kv("创建", t.createdAt.formatted(date: .abbreviated, time: .shortened))
                        kv("步骤", "\(t.steps.count)")
                        kv("发现", "\(t.findings.count)")
                        kv("资产", "\(t.assets.count)")
                    }
                }
                if !t.objective.isEmpty {
                    Card(title: "目标") {
                        Text(t.objective).font(.system(size: 13)).foregroundStyle(ArtexTheme.text)
                    }
                }
                if !t.targets.isEmpty {
                    Card(title: "授权目标") {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(t.targets, id: \.self) { x in
                                Text("• " + x).font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(ArtexTheme.accent)
                            }
                        }
                    }
                }
                if !t.summary.isEmpty {
                    Card(title: "总结") {
                        Text(t.summary).font(.system(size: 12)).foregroundStyle(ArtexTheme.text)
                    }
                }
                if !isThisRunning {
                    Button {
                        store.run(taskID)
                    } label: {
                        Text(t.status == "pending" ? "开始运行" : "重新运行")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(ArtexTheme.accent).foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                } else {
                    HStack(spacing: 8) {
                        ProgressView().tint(ArtexTheme.accent)
                        Text("Agent 运行中，切到「过程」看实时输出")
                            .font(.system(size: 12)).foregroundStyle(ArtexTheme.dim)
                    }
                }
            }.padding(14)
        }
    }

    private func stepsTab(_ t: LocalTask) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(t.steps) { s in
                    Card {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Pill(text: s.role, color: roleColor(s.role))
                                Text(s.title).font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(ArtexTheme.text)
                                Spacer()
                                Text("#\(s.index)").font(.system(size: 9)).foregroundStyle(ArtexTheme.dim)
                            }
                            Text(s.detail).font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(ArtexTheme.dim).lineLimit(20)
                        }
                    }
                }
                if t.steps.isEmpty {
                    EmptyHint(text: isThisRunning ? "等待第一步…" : "还没运行")
                }
            }.padding(14)
        }
    }

    private func findingsTab(_ t: LocalTask) -> some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(t.findings) { f in
                    Card {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Pill(text: f.severity.uppercased(), color: ArtexTheme.severityColor(f.severity))
                                Spacer()
                                if let cve = f.cveId { Pill(text: cve, color: ArtexTheme.low) }
                            }
                            Text(f.title).font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(ArtexTheme.text)
                            Text(f.asset).font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(ArtexTheme.accent)
                            Text(f.detail).font(.system(size: 11)).foregroundStyle(ArtexTheme.dim)
                        }
                    }
                }
                if t.findings.isEmpty { EmptyHint(text: "暂无发现") }
            }.padding(14)
        }
    }

    private func assetsTab(_ t: LocalTask) -> some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(t.assets, id: \.self) { a in
                    HStack {
                        Text(a).font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(ArtexTheme.text)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = a
                        } label: { Image(systemName: "doc.on.doc").font(.system(size: 10)) }
                    }
                    .padding(10).background(ArtexTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                if t.assets.isEmpty { EmptyHint(text: "暂无资产") }
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

    private func statusText(_ s: String) -> String {
        switch s {
        case "pending": return "待运行"
        case "running": return "运行中"
        case "done": return "已完成"
        case "failed": return "失败"
        case "stopped": return "已停止"
        default: return s
        }
    }

    private func roleColor(_ r: String) -> Color {
        switch r {
        case "plan": return ArtexTheme.low
        case "tool": return ArtexTheme.medium
        case "result": return ArtexTheme.dim
        case "final": return ArtexTheme.ok
        default: return ArtexTheme.accent
        }
    }
}
