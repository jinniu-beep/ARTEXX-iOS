import SwiftUI

/// 本地扫描：不依赖服务端，直接用手机网络打目标。
struct LocalScanView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var agent = LocalAgent.shared
    @State private var target = ""
    @State private var mode: Mode = .agent
    @State private var busy = false
    @State private var portResults: [NativeScanner.PortResult] = []
    @State private var fingerprint: NativeScanner.HTTPFingerprint?
    @State private var dnsInfo: NativeScanner.DNSResult?
    @State private var subdomains: [String: [String]] = [:]
    @State private var log: [String] = []

    enum Mode: String, CaseIterable {
        case agent = "AI Agent"
        case manual = "手动扫描"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                OfflineBadge()
                Card(title: "目标") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("域名 / IP / URL", text: $target)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .font(.system(size: 14, design: .monospaced))
                            .padding(10)
                            .background(ArtexTheme.surfaceHi)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        Picker("", selection: $mode) {
                            ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented)

                        if mode == .manual {
                            HStack(spacing: 8) {
                                actionButton("DNS") { runDNS() }
                                actionButton("端口") { runPorts() }
                                actionButton("指纹") { runFingerprint() }
                                actionButton("子域") { runSubdomains() }
                            }
                        } else {
                            Button {
                                startAgent()
                            } label: {
                                HStack {
                                    if agent.running { ProgressView().tint(.black) }
                                    Text(agent.running ? "Agent 运行中…" : "启动 AI Agent")
                                        .font(.system(size: 15, weight: .semibold))
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(ArtexTheme.accent).foregroundStyle(.black)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .disabled(agent.running || target.isEmpty)
                        }
                    }
                }

                if let e = agent.lastError {
                    Card { Text(e).font(.system(size: 12)).foregroundStyle(ArtexTheme.critical) }
                }

                if mode == .agent && !agent.steps.isEmpty {
                    agentStepsCard
                }
                if mode == .agent && !agent.findings.isEmpty {
                    findingsCard
                }
                if mode == .manual {
                    manualResults
                }
                if !log.isEmpty {
                    Card(title: "日志") {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(log.suffix(30).enumerated()), id: \.offset) { _, l in
                                Text(l).font(.system(size: 10, design: .monospaced)).foregroundStyle(ArtexTheme.dim)
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
                NavigationLink { LLMConfigView() } label: { Image(systemName: "brain") }
            }
        }
    }

    private func actionButton(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity).padding(.vertical, 9)
                .background(ArtexTheme.surfaceHi).foregroundStyle(ArtexTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .disabled(busy || target.isEmpty)
    }

    private var agentStepsCard: some View {
        Card(title: "执行过程 \(agent.steps.count) 步") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(agent.steps) { s in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Pill(text: s.role, color: roleColor(s.role))
                            Text(s.title).font(.system(size: 11, weight: .medium)).foregroundStyle(ArtexTheme.text)
                            Spacer()
                            Text(s.ts.formatted(date: .omitted, time: .standard))
                                .font(.system(size: 8)).foregroundStyle(ArtexTheme.dim)
                        }
                        Text(s.detail).font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(ArtexTheme.dim).lineLimit(12)
                    }
                    Divider().background(ArtexTheme.border)
                }
            }
        }
    }

    private var findingsCard: some View {
        Card(title: "发现 \(agent.findings.count)") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(agent.findings) { f in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Pill(text: f.severity.uppercased(), color: ArtexTheme.severityColor(f.severity))
                            Text(f.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(ArtexTheme.text)
                            Spacer()
                        }
                        Text(f.asset).font(.system(size: 10, design: .monospaced)).foregroundStyle(ArtexTheme.accent)
                        Text(f.detail).font(.system(size: 10)).foregroundStyle(ArtexTheme.dim).lineLimit(4)
                    }
                    Divider().background(ArtexTheme.border)
                }
            }
        }
    }

    private var manualResults: some View {
        VStack(spacing: 14) {
            if let d = dnsInfo {
                Card(title: "DNS") {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(d.host).font(.system(size: 12, design: .monospaced)).foregroundStyle(ArtexTheme.accent)
                        Text(d.addresses.isEmpty ? "无记录" : d.addresses.joined(separator: ", "))
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(ArtexTheme.text)
                    }
                }
            }
            if !portResults.isEmpty {
                Card(title: "开放端口 \(portResults.count)") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(portResults, id: \.port) { p in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(p.port)").font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(ArtexTheme.ok).frame(width: 50, alignment: .leading)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(p.banner ?? "—").font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(ArtexTheme.dim).lineLimit(2)
                                    Text("\(p.ms)ms").font(.system(size: 8)).foregroundStyle(ArtexTheme.dim)
                                }
                            }
                        }
                    }
                }
            }
            if let f = fingerprint {
                Card(title: "HTTP 指纹") {
                    VStack(alignment: .leading, spacing: 4) {
                        kv("状态", "\(f.status)")
                        kv("标题", f.title ?? "-")
                        kv("Server", f.server ?? "-")
                        kv("X-Powered-By", f.poweredBy ?? "-")
                        kv("技术栈", f.tech.isEmpty ? "-" : f.tech.joined(separator: ", "))
                    }
                }
            }
            if !subdomains.isEmpty {
                Card(title: "子域 \(subdomains.count)") {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(subdomains.keys.sorted(), id: \.self) { h in
                            Text(h + "  " + (subdomains[h]?.first ?? ""))
                                .font(.system(size: 10, design: .monospaced)).foregroundStyle(ArtexTheme.text)
                        }
                    }
                }
            }
        }
    }

    private func kv(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).font(.system(size: 10)).foregroundStyle(ArtexTheme.dim).frame(width: 78, alignment: .leading)
            Text(v).font(.system(size: 11, design: .monospaced)).foregroundStyle(ArtexTheme.text)
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

    // MARK: - Actions
    private func startAgent() {
        agent.start(objective: "对目标 \(target) 做授权渗透测试：先侦察端口与指纹，再匹配 CVE 与技能，给出发现与建议。")
    }

    private func runDNS() {
        busy = true; log.append("DNS 解析 \(target)…")
        DispatchQueue.global().async {
            let r = NativeScanner.resolve(target)
            DispatchQueue.main.async { dnsInfo = r; busy = false; log.append("DNS 完成：\(r.addresses.count) 条") }
        }
    }

    private func runPorts() {
        busy = true; portResults = []
        log.append("端口扫描 \(target)（\(NativeScanner.topPorts.count) 个）…")
        DispatchQueue.global().async {
            let r = NativeScanner.scanPorts(host: target, ports: NativeScanner.topPorts, timeout: 1.5, concurrency: 80)
            DispatchQueue.main.async {
                portResults = r; busy = false
                log.append("扫描完成：\(r.count) 个开放")
            }
        }
    }

    private func runFingerprint() {
        busy = true
        let url = target.hasPrefix("http") ? target : "http://\(target)"
        log.append("指纹探测 \(url)…")
        DispatchQueue.global().async {
            let f = NativeScanner.fingerprint(url)
            DispatchQueue.main.async {
                fingerprint = f; busy = false
                log.append(f == nil ? "指纹失败" : "指纹完成：HTTP \(f!.status)")
            }
        }
    }

    private func runSubdomains() {
        busy = true; subdomains = [:]
        log.append("子域枚举 \(target)（\(NativeScanner.subdomainWordlist.count) 词）…")
        DispatchQueue.global().async {
            let r = NativeScanner.enumerateSubdomains(domain: target)
            DispatchQueue.main.async {
                subdomains = r; busy = false
                log.append("子域完成：\(r.count) 个")
            }
        }
    }
}

/// 模型配置
struct LLMConfigView: View {
    @State private var cfg = LLMClient.shared.config
    @State private var testing = false
    @State private var testResult: String?
    @State private var testOk = false

    private let presets: [(String, String, String)] = [
        ("DeepSeek", "https://api.deepseek.com/v1", "deepseek-chat"),
        ("Kimi", "https://api.moonshot.cn/v1", "moonshot-v1-8k"),
        ("通义千问", "https://dashscope.aliyuncs.com/compatible-mode/v1", "qwen-plus"),
        ("OpenAI", "https://api.openai.com/v1", "gpt-4o-mini"),
        ("Anthropic", "https://api.anthropic.com", "claude-sonnet-4-20250514"),
    ]

    var body: some View {
        Form {
            Section("快速选择") {
                ForEach(presets, id: \.0) { p in
                    Button {
                        cfg.baseURL = p.1
                        cfg.model = p.2
                        cfg.provider = p.0 == "Anthropic" ? .anthropic : .openai
                    } label: {
                        HStack {
                            Text(p.0)
                            Spacer()
                            Text(p.2).font(.system(size: 10, design: .monospaced)).foregroundStyle(ArtexTheme.dim)
                        }
                    }
                }
            }
            Section("连接") {
                Picker("协议", selection: $cfg.provider) {
                    ForEach(LLMConfig.Provider.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                TextField("Base URL", text: $cfg.baseURL)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                TextField("模型名", text: $cfg.model)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                SecureField("API Key", text: $cfg.apiKey)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
            }
            Section("参数") {
                HStack { Text("温度"); Spacer(); Text(String(format: "%.1f", cfg.temperature)).foregroundStyle(ArtexTheme.dim) }
                Slider(value: $cfg.temperature, in: 0...1, step: 0.1)
                Stepper("最大 Token：\(cfg.maxTokens)", value: $cfg.maxTokens, in: 512...8192, step: 512)
            }
            Section {
                Button(testing ? "测试中…" : "测试连接") { test() }
                    .disabled(testing || cfg.apiKey.isEmpty)
                if let r = testResult {
                    Text(r).font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(testOk ? ArtexTheme.ok : ArtexTheme.critical)
                }
            } footer: {
                Text("Key 只存在本机 UserDefaults，不会上传到任何服务器。")
            }
        }
        .scrollContentBackground(.hidden)
        .background(ArtexTheme.bg)
        .onDisappear { LLMClient.shared.update(cfg) }
    }

    private func test() {
        testing = true; testResult = nil
        LLMClient.shared.update(cfg)
        Task {
            do {
                let r = try await LLMClient.shared.complete(
                    messages: [LLMMessage(role: "user", content: "回复 OK 两个字母")], tools: [])
                testResult = "连接成功：" + r.content.prefix(60)
                testOk = true
            } catch {
                testResult = error.localizedDescription
                testOk = false
            }
            testing = false
        }
    }
}
