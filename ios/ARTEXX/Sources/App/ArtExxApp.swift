import SwiftUI

@main
struct ArtExxApp: App {
    @StateObject private var store = AppStore()

    init() {
        // 数据库在后台解压，不阻塞启动
        CVEDatabase.shared.bootstrap()
        // 内置服务：优先启动真·Go 后端（libartex.a → ArtexStart，提供真实 /api + 内置 Web UI）；
        // 启动失败再回落到 Swift 版 EmbeddedServer（静态文件 + 兼容层）。
        if !GoBackend.shared.start(port: 8787) {
            EmbeddedServer.shared.start()
        }
        UserDefaults.standard.set(true, forKey: "artex.webui.skipLogin")
        UINavigationBar.appearance().largeTitleTextAttributes = [.foregroundColor: UIColor.white]
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(ArtexTheme.accent)
                .onAppear { store.bootstrap() }
        }
    }
}

/// 全局状态：登录态、服务器配置、刷新计数。
@MainActor
final class AppStore: ObservableObject {
    @Published var loggedIn = false
    /// 离线模式：不连服务端，仅使用内置知识库 + 本地控制台
    @Published var offlineMode = false
    @Published var initializing = true
    @Published var lastError: String?
    @Published var config: ServerConfig = ServerConfig.load()
    @Published var refreshTick = 0

    func bootstrap() {
        APIClient.shared.update(config)

        // 看门狗：无论探测结果如何，最多 4 秒后必须放行到登录页
        let watchdog = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if self.initializing {
                self.initializing = false
                self.lastError = "服务器未响应，已进入登录页，可修改地址后重试"
            }
        }

        Task {
            // 先放行：有 token 就直接进主界面（离线也能看本地知识库）
            if !config.token.isEmpty {
                loggedIn = true
                initializing = false
                watchdog.cancel()
            }

            // 再异步校验服务端状态（最多 3 秒）
            let reachable = await APIClient.shared.probe()
            if !reachable {
                if config.token.isEmpty {
                    lastError = "无法连接服务器（3 秒超时），请检查地址"
                }
            } else if config.token.isEmpty {
                do {
                    let st = try await AuthAPI.status()
                    if st.needSetup == true || st.initialized == false {
                        lastError = "服务端尚未初始化，请设置管理员密码"
                    }
                } catch {
                    lastError = error.localizedDescription
                }
            }
            initializing = false
            watchdog.cancel()
        }
    }

    func apply(_ cfg: ServerConfig) {
        config = cfg
        APIClient.shared.update(cfg)
    }

    func logout() {
        config.token = ""
        apply(config)
        loggedIn = false
    }

    func bump() { refreshTick += 1 }

    /// 用户主动跳过启动等待
    func skipSplash() {
        initializing = false
        if !config.token.isEmpty { loggedIn = true }
    }

    /// 进入离线模式：跳过鉴权，直接使用内置能力
    func enterOffline() {
        offlineMode = true
        initializing = false
        lastError = nil
    }

    /// 退出离线模式回到登录页
    func leaveOffline() {
        offlineMode = false
        loggedIn = false
    }

    /// 是否需要显示登录页
    var needsLogin: Bool { !loggedIn && !offlineMode }
}
