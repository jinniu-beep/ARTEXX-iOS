import SwiftUI

/// LLM 页 —— 严格对齐 system/llm/page.tsx
/// 结构：标题 + 轮询配置/新建 按钮 + Tabs(模型配置/重试与退避) + 卡片网格
struct LLMView: View {
    @EnvironmentObject var store: AppStore
    @State private var tab = 0
    @State private var profiles: [LLMProfile] = []
    @State private var pool: [String: AnyJSON] = [:]
    @State private var editing: LLMProfileDraft?
    @State private var showPool = false

    private var poolOn: Bool { (pool["enabled"]?.intValue ?? 0) != 0 }

    var body: some View {
        VStack(spacing: 0) {
            // ── 页头 ──
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("LLM").font(.system(size: 18, weight: .semibold)).foregroundStyle(ArtexTheme.text)
                    Text("全 Agent 共享的格式 / 模型 / 限速配置。点击卡片编辑，星标为当前激活配置。")
                        .font(.system(size: 11)).foregroundStyle(ArtexTheme.dim)
                }
                Spacer()
                HStack(spacing: 6) {
                    ArtexButton(title: "轮询配置", icon: "bolt", style: .outline, compact: true) { showPool = true }
                    ArtexButton(title: "新建", icon: "plus", style: .outline, compact: true) {
                        editing = LLMProfileDraft.newDraft()
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10)

            ArtexTabs(items: ["模型配置", "重试与退避"], selection: $tab)

            ScrollView {
                if tab == 0 {
                    profileGrid
                } else {
                    retryPanel
                }
            }
        }
        .background(ArtexTheme.bg)
        .sheet(item: $editing) { d in
            ProfileSheet(draft: d) { await load() }
        }
        .sheet(isPresented: $showPool) { PoolSheet(pool: pool) { await load() } }
        .task { await load() }
    }

    // MARK: - 卡片网格（grid-cols-1 md:grid-cols-2 xl:grid-cols-3）
    private var profileGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10)], spacing: 10) {
            // 本机模型卡（离线可用）
            localCard

            // 服务端配置卡
            ForEach(profiles) { p in
                serverCard(p)
            }

            if store.offlineMode && profiles.isEmpty {
                EmptyView()
            }
        }
        .padding(16)
    }

    /// 本机模型卡：编辑直接跳 LLMConfigView
    private var localCard: some View {
        let c = LLMClient.shared.config
        return NavigationLink { LLMConfigView() } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: c.ready ? "star.fill" : "star")
                        .font(.system(size: 13))
                        .foregroundStyle(c.ready ? ArtexTheme.medium : ArtexTheme.dim)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Text("本机模型").font(.system(size: 12, weight: .medium)).foregroundStyle(ArtexTheme.text)
                            Pill(text: c.provider.rawValue.uppercased(), color: ArtexTheme.low)
                            Spacer()
                            Pill(text: c.ready ? "可用" : "未配置",
                                 color: c.ready ? ArtexTheme.ok : ArtexTheme.medium)
                        }
                        Text(c.model.isEmpty ? "未设置模型" : c.model)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(ArtexTheme.dim).lineLimit(1)
                    }
                }
                HStack(spacing: 10) {
                    Text(c.apiKey.isEmpty ? "未设置 Key" : String(repeating: "•", count: 6))
                    Text("0/s · 0/min")
                    if !c.baseURL.isEmpty {
                        Text(c.baseURL.replacingOccurrences(of: "https://", with: ""))
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 9)).foregroundStyle(ArtexTheme.dim)
                .padding(.leading, 19)

                HStack(spacing: 6) {
                    Text(c.ready ? "已激活" : "去配置")
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(c.ready ? ArtexTheme.surfaceHi : ArtexTheme.text)
                        .foregroundStyle(c.ready ? ArtexTheme.dim : ArtexTheme.bg)
                        .clipShape(RoundedRectangle(cornerRadius: ArtexTheme.radiusSm))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ArtexTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: ArtexTheme.radius)
                    .stroke(c.ready ? ArtexTheme.medium.opacity(0.5) : ArtexTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: ArtexTheme.radius))
        }
        .buttonStyle(.plain)
    }

    private func serverCard(_ p: LLMProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: p.active == true ? "star.fill" : "star")
                    .font(.system(size: 13))
                    .foregroundStyle(p.active == true ? ArtexTheme.medium : ArtexTheme.dim)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(p.name ?? "-").font(.system(size: 12, weight: .medium))
                            .foregroundStyle(ArtexTheme.text).lineLimit(1)
                        Pill(text: (p.provider ?? "-").uppercased(), color: ArtexTheme.low)
                        Spacer()
                    }
                    Text(p.model ?? "-")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(ArtexTheme.dim).lineLimit(1)
                }
            }
            HStack(spacing: 10) {
                Text("0/s · 0/min")
                if let b = p.base_url, !b.isEmpty {
                    Text(b.replacingOccurrences(of: "https://", with: "")).lineLimit(1)
                }
            }
            .font(.system(size: 9)).foregroundStyle(ArtexTheme.dim)
            .padding(.leading, 19)

            HStack(spacing: 6) {
                Button {
                    Task { try? await LLMAPI.activate(p.id); await load() }
                } label: {
                    Text(p.active == true ? "已激活" : "设为激活")
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(ArtexTheme.bg).foregroundStyle(ArtexTheme.text)
                        .overlay(RoundedRectangle(cornerRadius: ArtexTheme.radiusSm).stroke(ArtexTheme.input, lineWidth: 0.8))
                        .clipShape(RoundedRectangle(cornerRadius: ArtexTheme.radiusSm))
                }
                .disabled(p.active == true)

                Button {
                    Task { try? await LLMAPI.deleteProfile(p.id); await load() }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11)).foregroundStyle(ArtexTheme.critical)
                        .frame(width: 30, height: 28)
                        .overlay(RoundedRectangle(cornerRadius: ArtexTheme.radiusSm).stroke(ArtexTheme.input, lineWidth: 0.8))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ArtexTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: ArtexTheme.radius)
                .stroke(p.active == true ? ArtexTheme.medium.opacity(0.5) : ArtexTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: ArtexTheme.radius))
    }

    // MARK: - 重试与退避
    private var retryPanel: some View {
        VStack(spacing: 12) {
            Card(title: "重试策略") {
                VStack(alignment: .leading, spacing: 8) {
                    FieldRow(label: "最大重试", value: "3 次")
                    FieldRow(label: "退避基数", value: "1.5s")
                    FieldRow(label: "最大退避", value: "30s")
                    FieldRow(label: "重试条件", value: "429 / 5xx / 网络错误")
                }
            }
            Card(title: "轮询") {
                VStack(alignment: .leading, spacing: 8) {
                    FieldRow(label: "状态", value: poolOn ? "已开启" : "未开启")
                    FieldRow(label: "顺序", value: pool["order"]?.stringValue ?? "按优先级")
                    Text("轮询开启后，指定模型失败会自动兜底到下一个优先级配置。")
                        .font(.system(size: 10)).foregroundStyle(ArtexTheme.dim)
                }
            }
        }
        .padding(16)
    }

    private func load() async {
        guard !store.offlineMode else { return }
        profiles = (try? await LLMAPI.profiles()) ?? []
        pool = (try? await LLMAPI.pool()) ?? [:]
    }
}

// MARK: - 编辑抽屉（对齐 ProfileSheet 全部字段）

struct LLMProfileDraft: Identifiable {
    var id = UUID()
    var serverID: Int64?
    var name = ""
    var format = "anthropic"
    var model = ""
    var baseURL = ""
    var proxy = ""
    var apiKey = ""
    var keyHint = ""
    var rps = 0
    var rpm = 0
    var contextWindowK = 0
    var thinkingType = ""
    var reasoningEffort = ""
    var priority = 0
    var poolExclude = false
    var streaming = true
    var maxTokens = 0
    var maxTokensField = ""
    var sessionHeaderKey = ""

    static func newDraft() -> LLMProfileDraft {
        var d = LLMProfileDraft()
        d.name = "新配置"
        return d
    }
}

struct ProfileSheet: View {
    @State var draft: LLMProfileDraft
    var onSaved: () async -> Void
    @Environment(\.dismiss) var dismiss
    @State private var testing = false
    @State private var testResult: String?
    @State private var testOK = false
    @State private var saving = false

    private let formats = ["anthropic", "openai", "openai-responses"]
    private let thinkingOptions = ["", "enabled", "disabled"]
    private let effortOptions = ["", "low", "medium", "high"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 基础
                    ArtexField(label: "名称", placeholder: "例如：DeepSeek 官方", text: $draft.name)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("格式").font(.system(size: 11, weight: .medium)).foregroundStyle(ArtexTheme.text)
                        HStack(spacing: 6) {
                            ForEach(formats, id: \.self) { f in
                                Button { draft.format = f } label: {
                                    Pill(text: f, color: draft.format == f ? ArtexTheme.accent : ArtexTheme.dim)
                                }
                            }
                        }
                    }

                    ArtexField(label: "模型", placeholder: "例如：deepseek-chat", text: $draft.model)
                    ArtexField(label: "Base URL（可选）", placeholder: "https://api.deepseek.com/v1", text: $draft.baseURL)
                    ArtexField(label: "代理（可选）", placeholder: "http://127.0.0.1:7890", text: $draft.proxy)
                    ArtexField(label: "API Key", placeholder: draft.keyHint.isEmpty ? "sk-..." : draft.keyHint,
                               text: $draft.apiKey, secure: true,
                               desc: draft.keyHint.isEmpty ? nil : "留空则沿用已保存的 Key")

                    Divider().background(ArtexTheme.border)

                    // 限速
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("每秒限速").font(.system(size: 10)).foregroundStyle(ArtexTheme.dim)
                            TextField("0", value: $draft.rps, format: .number)
                                .font(.system(size: 12)).keyboardType(.numberPad)
                                .padding(8).background(ArtexTheme.bg)
                                .overlay(RoundedRectangle(cornerRadius: ArtexTheme.radiusSm).stroke(ArtexTheme.input, lineWidth: 0.8))
                                .clipShape(RoundedRectangle(cornerRadius: ArtexTheme.radiusSm))
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("每分钟限速").font(.system(size: 10)).foregroundStyle(ArtexTheme.dim)
                            TextField("0", value: $draft.rpm, format: .number)
                                .font(.system(size: 12)).keyboardType(.numberPad)
                                .padding(8).background(ArtexTheme.bg)
                                .overlay(RoundedRectangle(cornerRadius: ArtexTheme.radiusSm).stroke(ArtexTheme.input, lineWidth: 0.8))
                                .clipShape(RoundedRectangle(cornerRadius: ArtexTheme.radiusSm))
                        }
                    }

                    ArtexField(label: "上下文窗口（K）", placeholder: "0 = 默认 200K",
                               text: Binding(get: { String(draft.contextWindowK) },
                                             set: { draft.contextWindowK = Int($0) ?? 0 }))

                    // 思考
                    VStack(alignment: .leading, spacing: 5) {
                        Text("思考类型").font(.system(size: 11, weight: .medium)).foregroundStyle(ArtexTheme.text)
                        HStack(spacing: 6) {
                            ForEach(thinkingOptions, id: \.self) { o in
                                Button { draft.thinkingType = o } label: {
                                    Pill(text: o.isEmpty ? "默认" : o,
                                         color: draft.thinkingType == o ? ArtexTheme.accent : ArtexTheme.dim)
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text("思考强度").font(.system(size: 11, weight: .medium)).foregroundStyle(ArtexTheme.text)
                        HStack(spacing: 6) {
                            ForEach(effortOptions, id: \.self) { o in
                                Button { draft.reasoningEffort = o } label: {
                                    Pill(text: o.isEmpty ? "关" : o,
                                         color: draft.reasoningEffort == o ? ArtexTheme.accent : ArtexTheme.dim)
                                }
                            }
                        }
                    }

                    Divider().background(ArtexTheme.border)

                    // 轮询
                    ArtexToggle(label: "不参与轮询", on: $draft.poolExclude)
                    ArtexField(label: "轮询优先级", placeholder: "越大越先",
                               text: Binding(get: { String(draft.priority) },
                                             set: { draft.priority = Int($0) ?? 0 }))

                    ArtexToggle(label: "流式输出", on: $draft.streaming)

                    ArtexField(label: "单次回复上限（Token）", placeholder: "0 = 不发送",
                               text: Binding(get: { String(draft.maxTokens) },
                                             set: { draft.maxTokens = Int($0) ?? 0 }))

                    ArtexField(label: "自定义会话头（可选）", placeholder: "留空则不发送", text: $draft.sessionHeaderKey)

                    // 测试
                    Button {
                        test()
                    } label: {
                        HStack(spacing: 5) {
                            if testing { ProgressView().tint(ArtexTheme.text).scaleEffect(0.6) }
                            Text(testing ? "测试中…" : "测试连接").font(.system(size: 12, weight: .medium))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(ArtexTheme.bg).foregroundStyle(ArtexTheme.text)
                        .overlay(RoundedRectangle(cornerRadius: ArtexTheme.radiusSm).stroke(ArtexTheme.input, lineWidth: 0.8))
                        .clipShape(RoundedRectangle(cornerRadius: ArtexTheme.radiusSm))
                    }
                    .disabled(testing || draft.apiKey.isEmpty)

                    if let r = testResult {
                        Text(r).font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(testOK ? ArtexTheme.ok : ArtexTheme.critical)
                    }
                }
                .padding(16)
            }
            .background(ArtexTheme.bg)
            .navigationTitle(draft.serverID == nil ? "新建模型配置" : "编辑：\(draft.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "保存中…" : "保存") { save() }
                        .font(.system(size: 12, weight: .semibold))
                        .disabled(saving || draft.name.isEmpty || draft.model.isEmpty)
                }
            }
        }
    }

    private func test() {
        testing = true; testResult = nil
        var cfg = LLMConfig()
        cfg.provider = draft.format == "anthropic" ? .anthropic : .openai
        cfg.baseURL = draft.baseURL.isEmpty ? (draft.format == "anthropic" ? "https://api.anthropic.com" : "https://api.openai.com/v1") : draft.baseURL
        cfg.model = draft.model
        cfg.apiKey = draft.apiKey
        LLMClient.shared.update(cfg)
        Task {
            do {
                let r = try await LLMClient.shared.complete(
                    messages: [LLMMessage(role: "user", content: "回复 OK")], tools: [])
                testResult = "连接成功 · 回复：\(r.content.prefix(40))"
                testOK = true
            } catch {
                testResult = "连接失败：" + error.localizedDescription
                testOK = false
            }
            testing = false
        }
    }

    private func save() {
        saving = true
        Task {
            // 本机模型直接写 LLMClient
            var cfg = LLMClient.shared.config
            cfg.provider = draft.format == "anthropic" ? .anthropic : .openai
            if !draft.baseURL.isEmpty { cfg.baseURL = draft.baseURL }
            cfg.model = draft.model
            if !draft.apiKey.isEmpty { cfg.apiKey = draft.apiKey }
            LLMClient.shared.update(cfg)

            // 同时尝试保存到服务端
            if !APIClient.shared.config.token.isEmpty {
                _ = try? await LLMAPI.saveProfile([
                    "name": draft.name,
                    "format": draft.format,
                    "model": draft.model,
                    "base_url": draft.baseURL,
                    "proxy": draft.proxy,
                    "api_key": draft.apiKey,
                    "rate_per_second": draft.rps,
                    "rate_per_minute": draft.rpm,
                    "context_window_k": draft.contextWindowK,
                    "thinking_type": draft.thinkingType,
                    "reasoning_effort": draft.reasoningEffort,
                    "priority": draft.priority,
                    "pool_exclude": draft.poolExclude,
                    "streaming": draft.streaming,
                    "max_tokens": draft.maxTokens,
                    "session_header_key": draft.sessionHeaderKey,
                ])
            }
            await onSaved()
            saving = false
            dismiss()
        }
    }
}

// MARK: - 轮询配置抽屉
struct PoolSheet: View {
    var pool: [String: AnyJSON]
    var onReload: () async -> Void
    @Environment(\.dismiss) var dismiss
    @State private var enabled = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ArtexToggle(label: "启用轮询", on: $enabled)
                    Text("开启后，指定模型失败会自动兜底到下一个优先级配置；关闭时只用星标激活的那一个。")
                        .font(.system(size: 10)).foregroundStyle(ArtexTheme.dim)
                    Divider().background(ArtexTheme.border)
                    FieldRow(label: "当前状态", value: (pool["enabled"]?.intValue ?? 0) != 0 ? "已开启" : "未开启")
                    FieldRow(label: "配置数", value: pool["total"]?.stringValue ?? "-")
                }.padding(16)
            }
            .background(ArtexTheme.bg)
            .navigationTitle("轮询配置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { Task { await onReload(); dismiss() } }
                }
            }
            .onAppear { enabled = (pool["enabled"]?.intValue ?? 0) != 0 }
        }
    }
}
