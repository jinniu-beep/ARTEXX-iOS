import SwiftUI

// MARK: - LLM（对齐 system/llm/page.tsx）
// Tabs: 模型配置 / 重试与退避
struct LLMView: View {
    @EnvironmentObject var store: AppStore
    @State private var tab = 0
    @State private var profiles: [LLMProfile] = []
    @State private var pool: [String: AnyJSON] = [:]
    @State private var cfg = LLMClient.shared.config

    var body: some View {
        VStack(spacing: 0) {
            PageTitle("LLM", sub: "模型配置与轮询")
            ArtexTabs(items: ["模型配置", "重试与退避"], selection: $tab)

            ScrollView {
                if tab == 0 {
                    VStack(spacing: 12) {
                        Card(title: "本机模型") {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 6) {
                                    Pill(text: cfg.provider.label, color: ArtexTheme.accent)
                                    Pill(text: cfg.ready ? "已配置" : "未配置",
                                         color: cfg.ready ? ArtexTheme.ok : ArtexTheme.medium)
                                    Spacer()
                                }
                                FieldRow(label: "模型", value: cfg.model)
                                FieldRow(label: "Base URL", value: cfg.baseURL)
                                FieldRow(label: "API Key", value: cfg.apiKey.isEmpty ? "未设置" : String(repeating: "•", count: 8))
                                NavigationLink { LLMConfigView() } label: {
                                    Text("编辑配置")
                                        .font(.system(size: 12, weight: .medium))
                                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                                        .background(ArtexTheme.surfaceHi).foregroundStyle(ArtexTheme.text)
                                        .clipShape(RoundedRectangle(cornerRadius: ArtexTheme.radiusSm))
                                }
                            }
                        }

                        if !store.offlineMode {
                            Card(title: "服务端配置") {
                                if profiles.isEmpty {
                                    Text("未连接服务端").font(.system(size: 11)).foregroundStyle(ArtexTheme.dim)
                                } else {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(profiles) { p in
                                            HStack {
                                                Text(p.name ?? "-").font(.system(size: 12)).foregroundStyle(ArtexTheme.text)
                                                Spacer()
                                                if p.active == true { Pill(text: "生效", color: ArtexTheme.ok) }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }.padding(16)
                } else {
                    VStack(spacing: 12) {
                        Card(title: "重试策略") {
                            VStack(alignment: .leading, spacing: 8) {
                                FieldRow(label: "最大重试", value: "3 次")
                                FieldRow(label: "退避基数", value: "1.5s")
                                FieldRow(label: "最大退避", value: "30s")
                                FieldRow(label: "轮询", value: pool["active"]?.stringValue ?? "0")
                            }
                        }
                    }.padding(16)
                }
            }
        }
        .background(ArtexTheme.bg)
        .onAppear { cfg = LLMClient.shared.config }
        .task {
            guard !store.offlineMode else { return }
            profiles = (try? await LLMAPI.profiles()) ?? []
            pool = (try? await LLMAPI.pool()) ?? [:]
        }
    }
}

// MARK: - Agent（对齐 system/agents/page.tsx）
struct AgentsView: View {
    @EnvironmentObject var store: AppStore
    @State private var agents: [AgentItem] = []

    private var builtin: [(String, String, String)] {
        [("planner", "规划者", "唯一意图生成者"),
         ("worker", "执行者", "工具执行 ×N"),
         ("mainagent", "主控", "人在环路对话"),
         ("goals", "目标拆解", "目标分解与范围提取"),
         ("retester", "漏洞复测", "验证修复是否生效")]
    }

    var body: some View {
        VStack(spacing: 0) {
            PageTitle("Agent", sub: "(builtin.count) 个内置 Agent", action: AnyView(
                ArtexButton(title: "新建", icon: "plus", compact: true) {}
            ))
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(builtin, id: \.0) { a in
                        HStack(spacing: 10) {
                            Circle().fill(ArtexTheme.surfaceHi).frame(width: 30, height: 30)
                                .overlay(Text(String(a.1.prefix(1))).font(.system(size: 13, weight: .semibold)).foregroundStyle(ArtexTheme.text))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.1).font(.system(size: 12, weight: .medium)).foregroundStyle(ArtexTheme.text)
                                Text(a.2).font(.system(size: 10)).foregroundStyle(ArtexTheme.dim)
                            }
                            Spacer()
                            Pill(text: a.0, color: ArtexTheme.low)
                        }
                        .padding(11)
                        .background(ArtexTheme.surface)
                        .overlay(RoundedRectangle(cornerRadius: ArtexTheme.radius).stroke(ArtexTheme.border, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: ArtexTheme.radius))
                    }
                }.padding(16)
            }
        }
        .background(ArtexTheme.bg)
    }
}

// MARK: - 工具（对齐 system/tools/page.tsx）
// Tabs: 系统工具 / 自定义工具
struct ToolsView: View {
    @EnvironmentObject var store: AppStore
    @State private var tab = 0
    @State private var tools: [ToolItem] = []

    private var builtin: [(String, String)] {
        [("dns_resolve", "DNS 解析：A/AAAA/CNAME 记录"),
         ("scan_ports", "TCP 端口扫描 + banner 抓取"),
         ("http_probe", "HTTP 指纹：状态码/标题/Server/技术栈"),
         ("subdomain_enum", "子域枚举：90 词高命中字典"),
         ("search_skills", "检索内置 319 条渗透技能"),
         ("search_cve", "检索内置 20 万条 CVE（含四段式指引）"),
         ("report_finding", "记录漏洞发现"),
         ("list_assets", "列出已发现资产")]
    }

    var body: some View {
        VStack(spacing: 0) {
            PageTitle("工具", sub: "Agent 可调用的能力")
            ArtexTabs(items: ["系统工具", "自定义工具"], selection: $tab)
            ScrollView {
                LazyVStack(spacing: 8) {
                    if tab == 0 {
                        ForEach(builtin, id: \.0) { t in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(t.0).font(.system(size: 12, design: .monospaced)).foregroundStyle(ArtexTheme.accent)
                                    Spacer()
                                    Pill(text: "启用", color: ArtexTheme.ok)
                                }
                                Text(t.1).font(.system(size: 10)).foregroundStyle(ArtexTheme.dim)
                            }
                            .padding(11)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(ArtexTheme.surface)
                            .overlay(RoundedRectangle(cornerRadius: ArtexTheme.radius).stroke(ArtexTheme.border, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: ArtexTheme.radius))
                        }
                    } else {
                        EmptyHint(text: "暂无自定义工具\n支持 shell / script / http 三种类型")
                    }
                }.padding(16)
            }
        }
        .background(ArtexTheme.bg)
    }
}

// MARK: - MCP（对齐 system/mcp/page.tsx）
// Tabs: 配置 / 工具列表
struct MCPView: View {
    @State private var tab = 0
    @State private var servers: [String: AnyJSON] = [:]

    var body: some View {
        VStack(spacing: 0) {
            PageTitle("MCP", sub: "Model Context Protocol 服务")
            ArtexTabs(items: ["配置", "工具列表"], selection: $tab)
            if servers.isEmpty {
                EmptyHint(text: "暂无 MCP 服务\n支持 stdio / sse / http 三种传输方式")
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(servers.keys.sorted(), id: \.self) { k in
                            FieldRow(label: k, value: servers[k]?.display ?? "-")
                        }
                    }.padding(16)
                }
            }
        }
        .background(ArtexTheme.bg)
    }
}

// MARK: - 通知推送（对齐 system/notify/page.tsx）
// Tabs: 渠道 / 投递记录
struct NotifyView: View {
    @State private var tab = 0
    var body: some View {
        VStack(spacing: 0) {
            PageTitle("通知推送", sub: "漏洞实时推送")
            ArtexTabs(items: ["渠道", "投递记录"], selection: $tab)
            if tab == 0 {
                ScrollView {
                    VStack(spacing: 12) {
                        Card(title: "全局设置") {
                            VStack(alignment: .leading, spacing: 8) {
                                FieldRow(label: "推送时机", value: "实时 · 每条漏洞单独发一条")
                                FieldRow(label: "汇总周期", value: "60 分钟")
                                FieldRow(label: "限流", value: "20 条/分钟")
                                FieldRow(label: "最低级别", value: "medium")
                            }
                        }
                    }.padding(16)
                }
            } else {
                EmptyHint(text: "暂无投递记录")
                Spacer()
            }
        }
        .background(ArtexTheme.bg)
    }
}

// MARK: - 命令拦截（对齐 system/intercept/page.tsx）
// Tabs: 拦截规则 / 模型配置；表头：优先级/名称/目标/类型/模式/策略/启用
struct InterceptView: View {
    @State private var tab = 0
    var body: some View {
        VStack(spacing: 0) {
            PageTitle("命令拦截", sub: "工具调用审批门", action: AnyView(
                ArtexButton(title: "新建规则", icon: "plus", compact: true) {}
            ))
            ArtexTabs(items: ["拦截规则", "模型配置"], selection: $tab)
            if tab == 0 {
                ScrollView {
                    VStack(spacing: 12) {
                        Card(title: "默认策略") {
                            VStack(alignment: .leading, spacing: 8) {
                                FieldRow(label: "放行", value: "直接放行，跳过后续规则")
                                FieldRow(label: "转人工", value: "等待审批")
                                FieldRow(label: "拦截", value: "阻断并返回拒绝消息")
                            }
                        }
                        Card(title: "匹配方式") {
                            VStack(alignment: .leading, spacing: 8) {
                                FieldRow(label: "目标", value: "工具名（tool_name）")
                                FieldRow(label: "输入", value: "输入内容（tool_input JSON）")
                                FieldRow(label: "模式", value: "字符串包含 / 正则表达式")
                            }
                        }
                    }.padding(16)
                }
            } else {
                EmptyHint(text: "审批模型配置")
                Spacer()
            }
        }
        .background(ArtexTheme.bg)
    }
}

// MARK: - 日志（对齐 system/logs/page.tsx）
struct LogsView: View {
    @EnvironmentObject var store: AppStore
    @State private var filter = ""
    @State private var data: [String: AnyJSON] = [:]

    var body: some View {
        VStack(spacing: 0) {
            PageTitle("系统日志", sub: "后端实时输出")
            VStack(spacing: 8) {
                SearchField(placeholder: "过滤(文本 / tag)…", text: $filter)
            }.padding(.horizontal, 16).padding(.vertical, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if data.isEmpty {
                        EmptyHint(text: "暂无日志\n日志流需要连接 ARTEXX 服务端")
                    } else {
                        ForEach(data.keys.sorted(), id: \.self) { k in
                            Text(k + ": " + (data[k]?.display ?? ""))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(ArtexTheme.text)
                        }
                    }
                }.padding(16)
            }
        }
        .background(ArtexTheme.bg)
        .task {
            guard !store.offlineMode else { return }
            data = (try? await OpsAPI.logs()) ?? [:]
        }
    }
}

// MARK: - 系统配置（对齐 system/settings/page.tsx）
struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var host = APIClient.shared.config.baseURL
    @State private var token = APIClient.shared.config.token
    @State private var workers = 3
    @State private var data: [String: AnyJSON] = [:]
    @State private var saved: String?

    var body: some View {
        VStack(spacing: 0) {
            PageTitle("系统配置", sub: "连接与运行参数")
            ScrollView {
                VStack(spacing: 12) {
                    Card(title: "服务器") {
                        VStack(alignment: .leading, spacing: 10) {
                            ArtexField(label: "地址", placeholder: "http://127.0.0.1:8787", text: $host)
                            ArtexField(label: "Token", placeholder: "登录后自动填充", text: $token, secure: true)
                            HStack(spacing: 8) {
                                ArtexButton(title: "保存并重连", compact: true) {
                                    var cfg = store.config
                                    cfg.baseURL = host
                                    cfg.token = token
                                    store.apply(cfg)
                                    saved = "已保存"
                                }
                                Spacer()
                            }
                        }
                    }

                    Card(title: "运行") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("并发 Agent 数").font(.system(size: 12)).foregroundStyle(ArtexTheme.text)
                                Spacer()
                                Text("(workers)").font(.system(size: 12, design: .monospaced)).foregroundStyle(ArtexTheme.dim)
                            }
                            Stepper("", value: $workers, in: 1...8).labelsHidden()
                        }
                    }

                    Card(title: "内置知识库") {
                        VStack(alignment: .leading, spacing: 6) {
                            FieldRow(label: "CVE", value: "(CVEDatabase.shared.totalRows) 条")
                            FieldRow(label: "技能", value: "(SkillLibrary.shared.all.count) 条")
                            FieldRow(label: "版本", value: "1.0.0")
                        }
                    }

                    if let saved {
                        Text(saved).font(.system(size: 11)).foregroundStyle(ArtexTheme.ok)
                    }
                }.padding(16)
            }
        }
        .background(ArtexTheme.bg)
        .task {
            guard !store.offlineMode else { return }
            data = (try? await OpsAPI.settings()) ?? [:]
        }
    }
}

// MARK: - 资产同步 / 资产拦截（对齐 sync + asset-intercept）
struct SyncView: View {
    @State private var host = ""
    @State private var apiKey = ""
    var body: some View {
        VStack(spacing: 0) {
            PageTitle("资产同步", sub: "从 ScopeSentry 导入资产")
            ScrollView {
                Card(title: "选择数据同步") {
                    VStack(alignment: .leading, spacing: 10) {
                        ArtexField(label: "ScopeSentry 地址", placeholder: "http://host:8082", text: $host)
                        ArtexField(label: "API Key", placeholder: "ssk_...", text: $apiKey, secure: true)
                        Text("按项目或任务维度选择要同步的目标与资产类型")
                            .font(.system(size: 10)).foregroundStyle(ArtexTheme.dim)
                    }
                }.padding(16)
            }
        }
        .background(ArtexTheme.bg)
    }
}

struct AssetInterceptView: View {
    var body: some View {
        VStack(spacing: 0) {
            PageTitle("资产拦截", sub: "禁止/允许测试的资产范围")
            EmptyHint(text: "暂无资产拦截规则\n可按域名、IP、CIDR 设置禁止或允许")
            Spacer()
        }
        .background(ArtexTheme.bg)
    }
}

struct ApprovalsView2: View {
    var body: some View {
        VStack(spacing: 0) {
            PageTitle("审批记录", sub: "拦截审批历史")
            EmptyHint(text: "暂无审批记录")
            Spacer()
        }
        .background(ArtexTheme.bg)
    }
}
