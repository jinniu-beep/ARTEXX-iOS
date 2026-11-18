import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var sse = ActivityStream()
    @State private var stats: [String: AnyJSON] = [:]
    @State private var counts: [String: AnyJSON] = [:]
    @State private var tokens: [String: AnyJSON] = [:]
    @State private var tasks: [TaskItem] = []
    @State private var loading = false

    private var cveStats: (total: Int, critical: Int, high: Int, medium: Int, vendors: Int) {
        CVEDatabase.shared.stats()
    }

    var body: some View {
        Group {
            if store.offlineMode { offlineDashboard } else {
            ScrollView {
                VStack(spacing: 14) {
                    header

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        MetricTile(label: "任务总数", value: "\(tasks.count)")
                        MetricTile(label: "运行中", value: "\(tasks.filter { ($0.status ?? "") == "running" }.count)", tint: ArtexTheme.ok)
                        MetricTile(label: "资产", value: counts["total"]?.stringValue ?? "\(counts.count)", tint: ArtexTheme.low)
                        MetricTile(label: "Token", value: tokens["total"]?.stringValue ?? "-", tint: ArtexTheme.medium)
                    }

                    Card(title: "内置知识库") {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("CVE").font(.system(size: 11)).foregroundStyle(ArtexTheme.dim)
                                Text("\(cveStats.total)").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(ArtexTheme.accent)
                                Text("2023-01 ~ 2026-11 · 中危以上").font(.system(size: 10)).foregroundStyle(ArtexTheme.dim)
                            }
                            Divider().frame(height: 40)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("严重").font(.system(size: 11)).foregroundStyle(ArtexTheme.dim)
                                Text("\(cveStats.critical)").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(ArtexTheme.critical)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text("高危").font(.system(size: 11)).foregroundStyle(ArtexTheme.dim)
                                Text("\(cveStats.high)").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(ArtexTheme.high)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text("技能").font(.system(size: 11)).foregroundStyle(ArtexTheme.dim)
                                Text("\(SkillLibrary.shared.all.count)").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(ArtexTheme.ok)
                            }
                            Spacer()
                        }
                    }

                    Card(title: "实时活动流", trailing: AnyView(
                        HStack(spacing: 8) {
                            Circle().fill(sse.connected ? ArtexTheme.ok : ArtexTheme.dim).frame(width: 7, height: 7)
                            Text(sse.connected ? "已连接" : "未连接").font(.system(size: 11)).foregroundStyle(ArtexTheme.dim)
                        }
                    )) {
                        if sse.events.isEmpty {
                            EmptyHint(text: "暂无事件，任务开始后这里会实时滚动")
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(sse.events.suffix(40).reversed()) { e in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text(e.ts?.text ?? "--:--").font(.system(size: 10, design: .monospaced)).foregroundStyle(ArtexTheme.dim)
                                        Text(e.display).font(.system(size: 12, design: .monospaced)).foregroundStyle(ArtexTheme.text).lineLimit(3)
                                        Spacer(minLength: 0)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(14)
            }
            .background(ArtexTheme.bg)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await load() }
                    } label: { Image(systemName: "arrow.clockwise") }
                }
            }
            .refreshable { await load() }
            .task {
                await load()
                sse.start()
            }
            .onDisappear { sse.stop() }
            }
        }
    }

    /// 离线版仪表盘：展示内置知识库统计（不依赖服务端）
    private var offlineDashboard: some View {
        ScrollView {
            VStack(spacing: 14) {
                OfflineBadge()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ARTEXX").font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(ArtexTheme.accent)
                        Text("离线模式 · 内置知识库").font(.system(size: 10)).foregroundStyle(ArtexTheme.dim)
                    }
                    Spacer()
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    MetricTile(label: "CVE 条数", value: "\(cveStats.total)")
                    MetricTile(label: "严重", value: "\(cveStats.critical)", tint: ArtexTheme.critical)
                    MetricTile(label: "高危", value: "\(cveStats.high)", tint: ArtexTheme.high)
                    MetricTile(label: "技能", value: "\(SkillLibrary.shared.all.count)", tint: ArtexTheme.ok)
                }
                Card(title: "离线可用") {
                    VStack(alignment: .leading, spacing: 8) {
                        offlineRow("shield.lefthalf.filled", "CVE 知识库", "\(cveStats.total) 条，含四段式攻击指引")
                        offlineRow("square.stack.3d.up", "技能库", "\(SkillLibrary.shared.all.count) 条，可编排")
                        offlineRow("terminal", "cmd 控制台", "本地命令 + dig/port/banner/curl")
                        offlineRow("doc.text.magnifyingglass", "SQL 检索", "FTS5 全文索引，毫秒级")
                    }
                }
                Card(title: "需要服务端") {
                    Text("任务、发现、资产、流量、对话等需要连上 ARTEXX 服务端。点上方「连接服务器」切换。")
                        .font(.system(size: 12)).foregroundStyle(ArtexTheme.dim)
                }
            }.padding(14)
        }
        .background(ArtexTheme.bg)
    }

    private func offlineRow(_ icon: String, _ title: String, _ sub: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(ArtexTheme.accent).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(ArtexTheme.text)
                Text(sub).font(.system(size: 10)).foregroundStyle(ArtexTheme.dim)
            }
            Spacer()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("ARTEXX").font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(ArtexTheme.accent)
                Text(APIClient.shared.config.effectiveBase).font(.system(size: 10, design: .monospaced)).foregroundStyle(ArtexTheme.dim)
            }
            Spacer()
            if loading { ProgressView().tint(ArtexTheme.accent) }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        tasks = (try? await TaskAPI.list()) ?? []
        stats = (try? await OpsAPI.stats()) ?? [:]
        counts = (try? await AssetAPI.counts()) ?? [:]
        tokens = (try? await OpsAPI.tokensUsage()) ?? [:]
    }
}
