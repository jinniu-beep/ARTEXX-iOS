import SwiftUI

struct MoreView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        NavigationStack {
            List {
                Section("功能") {
                    NavigationLink("本地扫描（手机直连）", destination: LocalScanView())
                    NavigationLink("模型配置", destination: LLMConfigView())
                    NavigationLink("对话", destination: ChatListView())
                    NavigationLink("发现", destination: FindingsView())
                    NavigationLink("资产", destination: AssetsView())
                    NavigationLink("工具执行", destination: CommandsView())
                    NavigationLink("流量", destination: TrafficView())
                    NavigationLink("工作空间", destination: WorkspaceView())
                }
                Section("系统") {
                    NavigationLink("LLM 配置", destination: LLMView())
                    NavigationLink("Agent", destination: AgentsView())
                    NavigationLink("工具开关", destination: ToolsView())
                    NavigationLink("拦截审批", destination: ApprovalsView())
                    NavigationLink("日志", destination: LogsView())
                    NavigationLink("系统配置", destination: SettingsView())
                    NavigationLink("自检", destination: DiagnosticsView())
                }
                Section("账号") {
                    HStack {
                        Text("服务器")
                        Spacer()
                        Text(APIClient.shared.config.effectiveBase).font(.system(size: 11, design: .monospaced)).foregroundStyle(ArtexTheme.dim)
                    }
                    if store.offlineMode {
                        Text("当前：离线模式").foregroundStyle(ArtexTheme.medium)
                        Button("连接服务器") { store.leaveOffline() }
                    } else {
                        Button("退出登录") { store.logout() }.foregroundStyle(ArtexTheme.critical)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(ArtexTheme.bg)
            .navigationTitle("更多")
        }
    }
}

// MARK: - 对话
struct ChatListView: View {
    @EnvironmentObject var store: AppStore
    @State private var convs: [ConversationItem] = []
    var body: some View {
        if store.offlineMode {
            OfflineNotice(what: "对话")
        } else {
List {
            ForEach(convs) { c in
                NavigationLink {
                    ChatDetailView(conv: c)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(c.title ?? "会话 #\(c.id)").font(.system(size: 14)).foregroundStyle(ArtexTheme.text)
                        Text(c.updated_at?.text ?? "").font(.system(size: 10)).foregroundStyle(ArtexTheme.dim)
                    }
                }.listRowBackground(ArtexTheme.surface)
            }
        }
        .scrollContentBackground(.hidden).background(ArtexTheme.bg)
        .navigationTitle("对话")
        .task { convs = (try? await ChatAPI.conversations()) ?? [] }
        }
    }
}

struct ChatDetailView: View {
    let conv: ConversationItem
    @State private var msgs: [ChatMessage] = []
    @State private var input = ""
    var body: some View {
        VStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(msgs) { m in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(m.role).font(.system(size: 10)).foregroundStyle(ArtexTheme.dim)
                            Text(m.content).font(.system(size: 13)).foregroundStyle(ArtexTheme.text)
                                .padding(10)
                                .background(m.role == "user" ? ArtexTheme.surfaceHi : ArtexTheme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }.padding(12)
            }
            HStack {
                TextField("发消息", text: $input).textFieldStyle(.roundedBorder)
                Button("发送") {
                    let t = input; input = ""
                    Task {
                        try? await ChatAPI.send(conv.id, text: t)
                        msgs = (try? await ChatAPI.messages(conv.id)) ?? []
                    }
                }
            }.padding(10)
        }
        .background(ArtexTheme.bg)
        .navigationTitle(conv.title ?? "会话")
        .task { msgs = (try? await ChatAPI.messages(conv.id)) ?? [] }
    }
}

// MARK: - 发现
struct FindingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var items: [Finding] = []
    var body: some View {
        if store.offlineMode {
            OfflineNotice(what: "发现")
        } else {
List {
            ForEach(items) { f in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Pill(text: f.displaySeverity.uppercased(), color: ArtexTheme.severityColor(f.displaySeverity))
                        Spacer()
                        Text(f.created_at?.text ?? "").font(.system(size: 10)).foregroundStyle(ArtexTheme.dim)
                    }
                    Text(f.displayTitle).font(.system(size: 13)).foregroundStyle(ArtexTheme.text)
                    if let a = (f.asset ?? f.url), !a.isEmpty { Text(a).font(.system(size: 10, design: .monospaced)).foregroundStyle(ArtexTheme.dim) }
                }
            }.listRowBackground(ArtexTheme.surface)
        }
        .scrollContentBackground(.hidden).background(ArtexTheme.bg)
        .navigationTitle("发现")
        .task { items = (try? await FindingAPI.list()) ?? [] }
        }
    }
}

// MARK: - 资产
struct AssetsView: View {
    @EnvironmentObject var store: AppStore
    @State private var items: [Asset] = []
    var body: some View {
        if store.offlineMode {
            OfflineNotice(what: "资产")
        } else {
List {
            ForEach(items) { a in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.displayValue).font(.system(size: 13, design: .monospaced)).foregroundStyle(ArtexTheme.text)
                        Text((a.kind ?? "-") + " · " + (a.company ?? "-")).font(.system(size: 10)).foregroundStyle(ArtexTheme.dim)
                    }
                    Spacer()
                    Pill(text: (a.tested ?? false) ? "已测" : "未测", color: (a.tested ?? false) ? ArtexTheme.ok : ArtexTheme.dim)
                }
            }.listRowBackground(ArtexTheme.surface)
        }
        .scrollContentBackground(.hidden).background(ArtexTheme.bg)
        .navigationTitle("资产")
        .task { items = (try? await AssetAPI.list()) ?? [] }
        }
    }
}

// MARK: - 工具执行
struct CommandsView: View {
    @EnvironmentObject var store: AppStore
    @State private var items: [CommandRecord] = []
    var body: some View {
        if store.offlineMode {
            OfflineNotice(what: "工具执行")
        } else {
List {
            ForEach(items) { c in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Pill(text: c.tool ?? "-", color: ArtexTheme.accent)
                        Spacer()
                        Text(c.created_at?.text ?? "").font(.system(size: 10)).foregroundStyle(ArtexTheme.dim)
                    }
                    Text(c.command ?? "").font(.system(size: 11, design: .monospaced)).foregroundStyle(ArtexTheme.text).lineLimit(3)
                }
            }.listRowBackground(ArtexTheme.surface)
        }
        .scrollContentBackground(.hidden).background(ArtexTheme.bg)
        .navigationTitle("工具执行")
        .task { items = (try? await OpsAPI.commands()) ?? [] }
        }
    }
}

// MARK: - 流量
struct TrafficView: View {
    @EnvironmentObject var store: AppStore
    @State private var data: [String: AnyJSON] = [:]
    var body: some View {
        if store.offlineMode {
            OfflineNotice(what: "流量")
        } else {
List {
            ForEach(data.keys.sorted(), id: \.self) { k in
                HStack {
                    Text(k).font(.system(size: 12)).foregroundStyle(ArtexTheme.dim)
                    Spacer()
                    Text(data[k]?.display ?? "").font(.system(size: 11, design: .monospaced)).foregroundStyle(ArtexTheme.text).lineLimit(2)
                }
            }.listRowBackground(ArtexTheme.surface)
        }
        .scrollContentBackground(.hidden).background(ArtexTheme.bg)
        .navigationTitle("流量")
        .task { data = (try? await OpsAPI.trafficHosts()) ?? [:] }
        }
    }
}

// MARK: - 工作空间
struct WorkspaceView: View {
    @EnvironmentObject var store: AppStore
    @State private var content = ""
    @State private var path = ""
    var body: some View {
        if store.offlineMode {
            OfflineNotice(what: "工作空间")
        } else {
VStack(spacing: 0) {
            HStack {
                TextField("路径，留空为根目录", text: $path)
                    .textFieldStyle(.roundedBorder).font(.system(size: 12, design: .monospaced))
                Button("打开") { Task { content = (try? await WorkspaceAPI.read(path)) ?? "" } }
            }.padding(10)
            ScrollView {
                Text(content.isEmpty ? "（空）" : content)
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(ArtexTheme.text)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
        }
        .background(ArtexTheme.bg)
        .navigationTitle("工作空间")
        }
    }
}

// MARK: - 系统页
struct LLMView: View {
    @EnvironmentObject var store: AppStore
    @State private var profiles: [LLMProfile] = []
    @State private var pool: [String: AnyJSON] = [:]
    var body: some View {
        if store.offlineMode {
            OfflineNotice(what: "LLM 配置")
        } else {
List {
            Section("配置") {
                ForEach(profiles) { p in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name ?? "未命名").font(.system(size: 13)).foregroundStyle(ArtexTheme.text)
                            Text((p.provider ?? "-") + " / " + (p.model ?? "-")).font(.system(size: 10, design: .monospaced)).foregroundStyle(ArtexTheme.dim)
                        }
                        Spacer()
                        if p.active == true { Pill(text: "生效", color: ArtexTheme.ok) }
                        else {
                            Button("启用") { Task { try? await LLMAPI.activate(p.id); profiles = (try? await LLMAPI.profiles()) ?? [] } }
                                .font(.system(size: 11))
                        }
                    }
                }.listRowBackground(ArtexTheme.surface)
            }
            Section("池状态") {
                ForEach(pool.keys.sorted(), id: \.self) { k in
                    HStack {
                        Text(k).font(.system(size: 11)).foregroundStyle(ArtexTheme.dim)
                        Spacer()
                        Text(pool[k]?.display ?? "").font(.system(size: 11, design: .monospaced)).lineLimit(1)
                    }
                }.listRowBackground(ArtexTheme.surface)
            }
        }
        .scrollContentBackground(.hidden).background(ArtexTheme.bg)
        .navigationTitle("LLM")
        .task {
            profiles = (try? await LLMAPI.profiles()) ?? []
            pool = (try? await LLMAPI.pool()) ?? [:]
        }
        }
    }
}

struct AgentsView: View {
    @EnvironmentObject var store: AppStore
    @State private var agents: [AgentItem] = []
    var body: some View {
        if store.offlineMode {
            OfflineNotice(what: "Agent")
        } else {
List {
            ForEach(agents) { a in
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.name ?? a.key ?? a.id).font(.system(size: 13)).foregroundStyle(ArtexTheme.text)
                    Text(a.role ?? "").font(.system(size: 10)).foregroundStyle(ArtexTheme.dim)
                }
            }.listRowBackground(ArtexTheme.surface)
        }
        .scrollContentBackground(.hidden).background(ArtexTheme.bg)
        .navigationTitle("Agent")
        .task { agents = (try? await AgentAPI.list()) ?? [] }
        }
    }
}

struct ToolsView: View {
    @EnvironmentObject var store: AppStore
    @State private var tools: [ToolItem] = []
    var body: some View {
        if store.offlineMode {
            OfflineNotice(what: "工具开关")
        } else {
List {
            ForEach(tools) { t in
                VStack(alignment: .leading, spacing: 3) {
                    Text(t.key ?? t.id).font(.system(size: 13, design: .monospaced)).foregroundStyle(ArtexTheme.text)
                    Text(t.desc ?? "").font(.system(size: 10)).foregroundStyle(ArtexTheme.dim).lineLimit(2)
                    if let a = t.agents { Text(a.joined(separator: ",")).font(.system(size: 9)).foregroundStyle(ArtexTheme.low) }
                }
            }.listRowBackground(ArtexTheme.surface)
        }
        .scrollContentBackground(.hidden).background(ArtexTheme.bg)
        .navigationTitle("工具")
        .task { tools = (try? await AgentAPI.tools()) ?? [] }
        }
    }
}

struct ApprovalsView: View {
    @EnvironmentObject var store: AppStore
    @State private var data: [String: AnyJSON] = [:]
    var body: some View {
        if store.offlineMode {
            OfflineNotice(what: "拦截审批")
        } else {
List {
            ForEach(data.keys.sorted(), id: \.self) { k in
                HStack {
                    Text(k).font(.system(size: 11)).foregroundStyle(ArtexTheme.dim)
                    Spacer()
                    Text(data[k]?.display ?? "").font(.system(size: 11, design: .monospaced)).lineLimit(2)
                }
            }.listRowBackground(ArtexTheme.surface)
        }
        .scrollContentBackground(.hidden).background(ArtexTheme.bg)
        .navigationTitle("拦截审批")
        .task { data = (try? await AgentAPI.approvals()) ?? [:] }
        }
    }
}

struct LogsView: View {
    @EnvironmentObject var store: AppStore
    @State private var data: [String: AnyJSON] = [:]
    var body: some View {
        if store.offlineMode {
            OfflineNotice(what: "日志")
        } else {
ScrollView {
            Text(data.keys.sorted().map { "\($0): \(data[$0]?.display ?? "")" }.joined(separator: "\n"))
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(ArtexTheme.text)
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        }
        .background(ArtexTheme.bg)
        .navigationTitle("日志")
        .task { data = (try? await OpsAPI.logs()) ?? [:] }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var host = APIClient.shared.config.baseURL
    @State private var token = APIClient.shared.config.token
    @State private var data: [String: AnyJSON] = [:]
    @State private var saved: String?

    var body: some View {
        Form {
            Section("连接") {
                TextField("服务器地址", text: $host).autocorrectionDisabled().textInputAutocapitalization(.never)
                TextField("Token", text: $token).autocorrectionDisabled().textInputAutocapitalization(.never)
                Button("保存并重连") {
                    var cfg = store.config
                    cfg.baseURL = host
                    cfg.token = token
                    store.apply(cfg)
                    saved = "已保存"
                }
            }
            Section("服务端设置") {
                ForEach(data.keys.sorted(), id: \.self) { k in
                    HStack {
                        Text(k).font(.system(size: 11)).foregroundStyle(ArtexTheme.dim)
                        Spacer()
                        Text(data[k]?.display ?? "").font(.system(size: 11, design: .monospaced)).lineLimit(1)
                    }
                }
            }
            if let saved { Section { Text(saved).foregroundStyle(ArtexTheme.ok) } }
        }
        .scrollContentBackground(.hidden).background(ArtexTheme.bg)
        .navigationTitle("系统配置")
        .task { data = (try? await OpsAPI.settings()) ?? [:] }
    }
}
