import SwiftUI

/// 导航项：严格对齐 sidebar-items.ts 的 id / title / icon
enum NavEntry: String, CaseIterable, Identifiable {
    // 功能组
    case dashboard, chat, tasks, findings, traffic, commands, llmRecords, assets, sync, workspace
    // 系统组
    case llm, agents, mcp, skills, tools, notify, intercept, assetIntercept, approvals, logs, settings
    // 本地新增
    case localScan, cve, console

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "仪表盘"
        case .chat: return "对话"
        case .tasks: return "任务"
        case .findings: return "发现"
        case .traffic: return "流量"
        case .commands: return "工具执行"
        case .llmRecords: return "LLM 录制"
        case .assets: return "资产"
        case .sync: return "资产同步"
        case .workspace: return "工作空间"
        case .llm: return "LLM"
        case .agents: return "Agent"
        case .mcp: return "MCP"
        case .skills: return "Skill"
        case .tools: return "工具"
        case .notify: return "通知推送"
        case .intercept: return "拦截规则"
        case .assetIntercept: return "资产拦截"
        case .approvals: return "审批记录"
        case .logs: return "日志"
        case .settings: return "系统配置"
        case .localScan: return "本地扫描"
        case .cve: return "CVE 知识库"
        case .console: return "控制台"
        }
    }

    /// 对应 sidebar-items.ts 的 lucide 图标
    var icon: String {
        switch self {
        case .dashboard: return "gauge.medium"
        case .chat: return "message.square"
        case .tasks: return "scope"
        case .findings: return "ladybug"
        case .traffic: return "waveform.path.ecg"
        case .commands: return "terminal"
        case .llmRecords: return "dot.radiowaves.left.and.right"
        case .assets: return "network"
        case .sync: return "arrow.triangle.2.circlepath"
        case .workspace: return "folder"
        case .llm: return "brain"
        case .agents: return "cpu"
        case .mcp: return "puzzlepiece"
        case .skills: return "sparkles"
        case .tools: return "wrench.and.screwdriver"
        case .notify: return "bell"
        case .intercept: return "shield.lefthalf.filled"
        case .assetIntercept: return "nosign"
        case .approvals: return "list.clipboard"
        case .logs: return "doc.plaintext"
        case .settings: return "gearshape"
        case .localScan: return "dot.scope"
        case .cve: return "shield.checkered"
        case .console: return "apple.terminal"
        }
    }

    static let featureGroup: [NavEntry] = [.dashboard, .chat, .tasks, .findings, .traffic,
                                           .commands, .llmRecords, .assets, .sync, .workspace]
    static let systemGroup: [NavEntry] = [.llm, .agents, .mcp, .skills, .tools, .notify,
                                          .intercept, .assetIntercept, .approvals, .logs, .settings]
    static let localGroup: [NavEntry] = [.localScan, .cve, .console]
}

/// 主框架：对齐 ARTEXX 的侧边栏 + 内容区布局
struct AppShell: View {
    @EnvironmentObject var store: AppStore
    @State private var selection: NavEntry = .dashboard
    @State private var showSidebar = false
    @State private var showModel = false

    var body: some View {
        ZStack(alignment: .leading) {
            ArtexTheme.bg.ignoresSafeArea()

            // 内容区（对应 SidebarInset）
            VStack(spacing: 0) {
                topBar
                OfflineBadge()
                content
            }

            // 抽屉侧边栏
            if showSidebar {
                Color.black.opacity(0.5).ignoresSafeArea()
                    .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { showSidebar = false } }
                SidebarPanel(selection: $selection, close: {
                    withAnimation(.easeOut(duration: 0.2)) { showSidebar = false }
                })
                .frame(width: 272)
                .transition(.move(edge: .leading))
                .zIndex(2)
            }
        }
        .sheet(isPresented: $showModel) { NavigationStack { LLMConfigView() } }
    }

    // 顶栏：汉堡 + 当前页标题 + 操作
    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { showSidebar = true }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ArtexTheme.dim)
                    .frame(width: 32, height: 32)
            }

            HStack(spacing: 6) {
                Image(systemName: selection.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(ArtexTheme.dim)
                Text(selection.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ArtexTheme.surfaceText)
            }

            Spacer()

            Button { showModel = true } label: {
                Image(systemName: "brain")
                    .font(.system(size: 14))
                    .foregroundStyle(LLMClient.shared.config.ready ? ArtexTheme.ok : ArtexTheme.dim)
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        .background(ArtexTheme.bg)
        .overlay(Rectangle().frame(height: 0.5).foregroundStyle(ArtexTheme.border), alignment: .bottom)
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .dashboard: DashboardView()
        case .tasks: TaskListView()
        case .findings: FindingsView()
        case .chat: ChatListView()
        case .traffic: TrafficView()
        case .commands: CommandsView()
        case .assets: AssetsView()
        case .workspace: WorkspaceView()
        case .llm: LLMView()
        case .agents: AgentsView()
        case .tools: ToolsView()
        case .approvals: ApprovalsView2()
        case .logs: LogsView()
        case .settings: SettingsView()
        case .skills: SkillLibraryView()
        case .cve: CVEView()
        case .console: ConsoleView()
        case .localScan: LocalScanView()
        case .sync: SyncView()
        case .mcp: MCPView()
        case .notify: NotifyView()
        case .intercept: InterceptView()
        case .assetIntercept: AssetInterceptView()
        case .llmRecords: LLMRecordsView()
        }
    }
}

/// 给自带 NavigationStack 的子页面去掉多余标题栏
struct NAVWrapper<Content: View>: View {
    let content: () -> Content
    init(@ViewBuilder content: @escaping () -> Content) { self.content = content }
    var body: some View { content() }
}

/// 侧边栏
struct SidebarPanel: View {
    @Binding var selection: NavEntry
    var close: () -> Void
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header：logo + 名称
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(ArtexTheme.surfaceHi)
                    .frame(width: 34, height: 34)
                    .overlay(
                        Text("A")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(ArtexTheme.text)
                    )
                Text("ARTEX")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ArtexTheme.surfaceText)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    group("本地", NavEntry.localGroup)
                    group("功能", NavEntry.featureGroup)
                    group("系统", NavEntry.systemGroup)
                }
                .padding(.bottom, 20)
            }

            Divider().background(ArtexTheme.border)

            // Footer：用户
            HStack(spacing: 10) {
                Circle()
                    .fill(ArtexTheme.surfaceHi)
                    .frame(width: 30, height: 30)
                    .overlay(Image(systemName: "person.fill").font(.system(size: 12)).foregroundStyle(ArtexTheme.dim))
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.offlineMode ? "离线模式" : "admin")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ArtexTheme.surfaceText)
                    Text(store.offlineMode ? "本地知识库" : APIClient.shared.config.effectiveBase)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(ArtexTheme.dim)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .background(ArtexTheme.sidebar)
        .overlay(Rectangle().frame(width: 0.5).foregroundStyle(ArtexTheme.border), alignment: .trailing)
        .ignoresSafeArea()
    }

    private func group(_ label: String, _ items: [NavEntry]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(ArtexTheme.dim)
                .padding(.horizontal, 22)
                .padding(.bottom, 4)

            ForEach(items) { item in
                Button {
                    selection = item
                    close()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.icon)
                            .font(.system(size: 13))
                            .frame(width: 18)
                            .foregroundStyle(selection == item ? ArtexTheme.surfaceText : ArtexTheme.dim)
                        Text(item.title)
                            .font(.system(size: 13))
                            .foregroundStyle(selection == item ? ArtexTheme.surfaceText : ArtexTheme.dim)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(selection == item ? ArtexTheme.sidebarAccent : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: ArtexTheme.radiusSm))
                    .padding(.horizontal, 8)
                }
            }
        }
    }
}

/// 未实现的远端页面占位
struct PlaceholderPage: View {
    let entry: NavEntry
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: entry.icon).font(.system(size: 30)).foregroundStyle(ArtexTheme.dim.opacity(0.5))
            Text(entry.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(ArtexTheme.text)
            Text("该页面需连接 ARTEXX 服务端")
                .font(.system(size: 11)).foregroundStyle(ArtexTheme.dim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ArtexTheme.bg)
    }
}
