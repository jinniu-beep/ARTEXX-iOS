import SwiftUI

/// 仪表盘 —— 严格对齐 dashboard/page.tsx
struct DashboardView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject private var localStore = LocalTaskStore.shared
    @ObservedObject private var sse = ActivityStream.shared
    @ObservedObject private var cve = CVEDatabase.shared

    // 远端数据（连服务端时）
    @State private var remoteTasks: [TaskItem] = []
    @State private var remoteFindings: [Finding] = []
    @State private var remoteStats: [String: AnyJSON] = [:]
    @State private var assetCounts: [String: AnyJSON] = [:]
    @State private var tokens: [String: AnyJSON] = [:]
    @State private var loading = false

    // ── 派生数据 ──────────────────────────────────────────
    private var tasksByStatus: (running: Int, paused: Int, done: Int) {
        if store.offlineMode {
            let t = localStore.tasks
            return (t.filter { $0.status == "running" }.count,
                    t.filter { $0.status == "pending" }.count,
                    t.filter { $0.status == "done" }.count)
        }
        return (remoteTasks.filter { $0.displayStatus == "running" }.count,
                remoteTasks.filter { $0.displayStatus == "paused" }.count,
                remoteTasks.filter { ["done", "completed"].contains($0.displayStatus) }.count)
    }

    private var totalTasks: Int { store.offlineMode ? localStore.tasks.count : remoteTasks.count }

    private var findingsBySev: (critical: Int, high: Int, medium: Int, low: Int) {
        var c = 0, h = 0, m = 0, l = 0
        if store.offlineMode {
            for t in localStore.tasks {
                for f in t.findings {
                    switch f.severity.lowercased() {
                    case "critical": c += 1
                    case "high": h += 1
                    case "medium": m += 1
                    default: l += 1
                    }
                }
            }
        } else {
            for f in remoteFindings {
                switch f.displaySeverity {
                case "critical": c += 1
                case "high": h += 1
                case "medium": m += 1
                default: l += 1
                }
            }
        }
        return (c, h, m, l)
    }

    private var totalFindings: Int {
        let s = findingsBySev
        return s.critical + s.high + s.medium + s.low
    }

    private var totalAssets: Int {
        if store.offlineMode {
            return Set(localStore.tasks.flatMap { $0.assets }).count
        }
        return assetCounts["total"]?.intValue ?? 0
    }

    private var tokenTotal: (input: Int, output: Int, cacheRead: Int) {
        (tokens["input"]?.intValue ?? 0,
         tokens["output"]?.intValue ?? 0,
         tokens["cacheRead"]?.intValue ?? 0)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PageTitle("总览", sub: "系统全局状态 · 实时刷新")

                // ── Row 1：5 张统计卡 ──────────────────────
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    StatCard(
                        icon: "scope", label: "活跃任务",
                        value: "\(tasksByStatus.running)", suffix: "/ \(totalTasks)",
                        footer: AnyView(
                            HStack(spacing: 8) {
                                if tasksByStatus.running > 0 {
                                    Text("探索 \(tasksByStatus.running)").foregroundStyle(ArtexTheme.accent)
                                }
                                if tasksByStatus.paused > 0 {
                                    Text("暂停 \(tasksByStatus.paused)").foregroundStyle(ArtexTheme.medium)
                                }
                                if tasksByStatus.done > 0 {
                                    Text("完成 \(tasksByStatus.done)").foregroundStyle(ArtexTheme.ok)
                                }
                                if totalTasks == 0 {
                                    Text("暂无任务").foregroundStyle(ArtexTheme.dim)
                                }
                            }
                            .font(.system(size: 10))
                        )
                    )

                    StatCard(
                        icon: "ladybug", label: "确认发现",
                        value: "\(totalFindings)",
                        footer: AnyView(
                            HStack(spacing: 7) {
                                Text("严重 \(findingsBySev.critical)").foregroundStyle(ArtexTheme.critical)
                                Text("高危 \(findingsBySev.high)").foregroundStyle(ArtexTheme.high)
                                Text("中危 \(findingsBySev.medium)").foregroundStyle(ArtexTheme.medium)
                                Text("低危 \(findingsBySev.low)").foregroundStyle(ArtexTheme.low)
                            }
                            .font(.system(size: 10))
                        )
                    )

                    StatCard(
                        icon: "network", label: "资产节点",
                        value: "\(totalAssets)",
                        footer: AnyView(
                            Text("跨任务共享").font(.system(size: 10)).foregroundStyle(ArtexTheme.dim)
                        )
                    )

                    StatCard(
                        icon: "waveform.path.ecg", label: "流量交互",
                        value: "\(store.offlineMode ? 0 : 0)",
                        footer: AnyView(
                            HStack(spacing: 5) {
                                LiveDot()
                                Text("录制中").font(.system(size: 10)).foregroundStyle(ArtexTheme.dim)
                            }
                        )
                    )

                    StatCard(
                        icon: "bolt", label: "Token 用量",
                        value: fmtTokens(tokenTotal.input + tokenTotal.output),
                        footer: AnyView(
                            Text("入 \(fmtTokens(tokenTotal.input))（含缓存 \(fmtTokens(tokenTotal.cacheRead))）· 出 \(fmtTokens(tokenTotal.output))")
                                .font(.system(size: 10)).foregroundStyle(ArtexTheme.dim)
                        )
                    )
                }
                .padding(.horizontal, 16)

                // ── 内置知识库（iOS 特有，替代无法获取的远端面板）──
                Card(title: "内置知识库") {
                    HStack(spacing: 0) {
                        knowledgeCell("CVE", "\(cve.totalRows)", "2023-01 ~ 2026-11", ArtexTheme.accent)
                        Divider().frame(height: 34).background(ArtexTheme.border)
                        knowledgeCell("严重", "\(cve.stats().critical)", "CVSS ≥ 9.0", ArtexTheme.critical)
                        Divider().frame(height: 34).background(ArtexTheme.border)
                        knowledgeCell("高危", "\(cve.stats().high)", "7.0 ~ 8.9", ArtexTheme.high)
                        Divider().frame(height: 34).background(ArtexTheme.border)
                        knowledgeCell("技能", "\(SkillLibrary.shared.all.count)", "13 大类", ArtexTheme.ok)
                    }
                }
                .padding(.horizontal, 16)

                // ── 实时活动流 ────────────────────────────
                Card(title: "实时活动", trailing: AnyView(
                    HStack(spacing: 5) {
                        Circle().fill(sse.connected ? ArtexTheme.ok : ArtexTheme.dim).frame(width: 5, height: 5)
                        Text(sse.connected ? "已连接" : "未连接")
                            .font(.system(size: 10)).foregroundStyle(ArtexTheme.dim)
                    }
                )) {
                    if sse.events.isEmpty {
                        EmptyHint(text: "暂无事件，任务开始后这里会实时滚动")
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(sse.events.suffix(30).reversed()) { e in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(e.ts?.text ?? "--:--")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(ArtexTheme.dim)
                                        .frame(width: 40, alignment: .leading)
                                    Text(e.display)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(ArtexTheme.text)
                                        .lineLimit(2)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)

                // ── 最近任务 ──────────────────────────────
                Card(title: "最近任务", trailing: AnyView(
                    Text("\(totalTasks)").font(.system(size: 10)).foregroundStyle(ArtexTheme.dim)
                )) {
                    let recent = Array(localStore.tasks.prefix(5))
                    if recent.isEmpty {
                        EmptyHint(text: "还没有任务")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(recent.enumerated()), id: \.element.id) { i, t in
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(statusTint(t.status))
                                        .frame(width: 5, height: 5)
                                    Text(t.title)
                                        .font(.system(size: 12))
                                        .foregroundStyle(ArtexTheme.text)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(fmtRel(t.updatedAt))
                                        .font(.system(size: 9)).foregroundStyle(ArtexTheme.dim)
                                }
                                .padding(.vertical, 7)
                                if i < recent.count - 1 {
                                    Rectangle().fill(ArtexTheme.border).frame(height: 0.5)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .background(ArtexTheme.bg)
        .refreshable { await load() }
        .task { await load() }
        .onAppear { if !store.offlineMode { sse.start() } }
        .onDisappear { sse.stop() }
    }

    private func knowledgeCell(_ title: String, _ value: String, _ sub: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 9)).foregroundStyle(ArtexTheme.dim)
            Text(value).font(.system(size: 16, weight: .semibold)).foregroundStyle(tint).monospacedDigit()
            Text(sub).font(.system(size: 8)).foregroundStyle(ArtexTheme.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusTint(_ s: String) -> Color {
        switch s {
        case "running": return ArtexTheme.accent
        case "done": return ArtexTheme.ok
        case "failed": return ArtexTheme.critical
        case "stopped": return ArtexTheme.medium
        default: return ArtexTheme.dim
        }
    }

    private func load() async {
        guard !store.offlineMode else { return }
        loading = true
        defer { loading = false }
        remoteTasks = (try? await TaskAPI.list()) ?? []
        remoteFindings = (try? await FindingAPI.list()) ?? []
        remoteStats = (try? await OpsAPI.stats()) ?? [:]
        assetCounts = (try? await AssetAPI.counts()) ?? [:]
        tokens = (try? await OpsAPI.tokensUsage()) ?? [:]
    }
}
