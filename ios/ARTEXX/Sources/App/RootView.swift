import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: AppStore
    @State private var tab: Int = 0
    @ObservedObject private var cve = CVEDatabase.shared

    var body: some View {
        ZStack {
            ArtexTheme.bg.ignoresSafeArea()
            if store.initializing {
                splash
            } else if store.needsLogin {
                LoginView()
            } else {
                AppShell()
            }
        }
    }

    /// 启动页：显示进度与「跳过」按钮，永不卡死
    private var splash: some View {
        VStack(spacing: 18) {
            Text("ARTEXX")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(ArtexTheme.accent)
            ProgressView().tint(ArtexTheme.accent)
            Text("正在连接服务器…")
                .font(.system(size: 12)).foregroundStyle(ArtexTheme.dim)

            switch cve.phase {
            case .preparing:
                Text("内置 CVE 知识库解压中（首次约 3 秒）")
                    .font(.system(size: 11)).foregroundStyle(ArtexTheme.medium)
            case .ready:
                Text("知识库就绪 · \(cve.totalRows) 条 CVE")
                    .font(.system(size: 11)).foregroundStyle(ArtexTheme.ok)
            case .failed(let msg):
                Text("知识库异常：" + msg)
                    .font(.system(size: 11)).foregroundStyle(ArtexTheme.critical)
            case .idle:
                EmptyView()
            }

            Button("直接进入") { store.skipSplash() }
                .font(.system(size: 13))
                .foregroundStyle(ArtexTheme.accent)
                .padding(.top, 8)
        }
    }
}

struct LoginView: View {
    @EnvironmentObject var store: AppStore
    @State private var host = ServerConfig.load().baseURL.isEmpty ? "http://127.0.0.1:8787" : ServerConfig.load().baseURL
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @State private var needSetup = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ARTEXX").font(.system(size: 34, weight: .heavy, design: .rounded)).foregroundStyle(ArtexTheme.accent)
                    Text("AI 自主渗透测试系统 · iOS 客户端").font(.system(size: 13)).foregroundStyle(ArtexTheme.dim)
                }
                .padding(.top, 60)

                Card(title: "服务器地址") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("http://192.168.x.x:8787", text: $host)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundStyle(ArtexTheme.text)
                            .padding(10)
                            .background(ArtexTheme.surfaceHi)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        HStack(spacing: 8) {
                            Button {
                                host = "http://127.0.0.1:8787"
                            } label: {
                                Pill(text: "用手机本机服务", color: ArtexTheme.ok)
                            }
                            Text("127.0.0.1 指向 App 内置服务（无需电脑）")
                                .font(.system(size: 9)).foregroundStyle(ArtexTheme.dim)
                        }

                        if !ServerConfig.recentAddresses.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(ServerConfig.recentAddresses, id: \.self) { addr in
                                        Button { host = addr } label: {
                                            Pill(text: addr.replacingOccurrences(of: "http://", with: ""),
                                                 color: host == addr ? ArtexTheme.accent : ArtexTheme.dim)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Card(title: needSetup ? "设置管理员密码" : "管理员密码") {
                    SecureField("密码", text: $password)
                        .font(.system(size: 14))
                        .foregroundStyle(ArtexTheme.text)
                        .padding(10)
                        .background(ArtexTheme.surfaceHi)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                if let raw = error ?? store.lastError {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ServerConfig.humanize(raw))
                            .font(.system(size: 12)).foregroundStyle(ArtexTheme.critical)

                    }
                }

                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        if busy { ProgressView().tint(.black) }
                        Text(busy ? "连接中…" : (needSetup ? "初始化并登录" : "登录"))
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(ArtexTheme.accent).foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(busy || password.isEmpty)

                Button {
                    Task { await probe() }
                } label: {
                    Text("检测服务器状态").font(.system(size: 13)).foregroundStyle(ArtexTheme.dim)
                }
                .frame(maxWidth: .infinity)

                Divider().background(ArtexTheme.border).padding(.vertical, 6)

                Button {
                    store.enterOffline()
                } label: {
                    VStack(spacing: 4) {
                        Text("跳过登录，离线使用")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(ArtexTheme.accent)
                        Text("不需要服务器 · 技能库 / CVE 知识库 / 本地控制台 全部可用")
                            .font(.system(size: 10))
                            .foregroundStyle(ArtexTheme.dim)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(ArtexTheme.surfaceHi)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Spacer(minLength: 40)
            }
            .padding(20)
        }
        .onAppear { Task { await probe() } }
    }

    private func probe() async {
        var cfg = store.config
        cfg.baseURL = host
        store.apply(cfg)
        do {
            let st = try await AuthAPI.status()
            needSetup = (st.needSetup == true || st.initialized == false)
            error = nil
        } catch {
            self.error = "无法连接：\(error.localizedDescription)"
        }
    }

    private func submit() async {
        busy = true; error = nil
        defer { busy = false }
        var cfg = store.config
        cfg.baseURL = host
        store.apply(cfg)
        do {
            let token = needSetup ? try await AuthAPI.initAdmin(password: password)
                                   : try await AuthAPI.login(password: password)
            guard let token, !token.isEmpty else { error = "服务端未返回 token"; return }
            cfg.token = token
            store.apply(cfg)
            ServerConfig.remember(host)
            store.loggedIn = true
        } catch {
            self.error = error.localizedDescription
        }
    }
}
