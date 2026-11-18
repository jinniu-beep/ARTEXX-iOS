import SwiftUI

@main
struct ArtExxApp: App {
    @StateObject private var store = AppStore()

    init() {
        CVEDatabase.shared.bootstrap()
        // 让控制台输出风格统一
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
    @Published var initializing = true
    @Published var lastError: String?
    @Published var config: ServerConfig = ServerConfig.load()
    @Published var refreshTick = 0

    func bootstrap() {
        APIClient.shared.update(config)
        Task {
            do {
                let st = try await AuthAPI.status()
                if st.needSetup == true || st.initialized == false {
                    loggedIn = false
                } else if !config.token.isEmpty {
                    loggedIn = true
                }
            } catch {
                lastError = error.localizedDescription
            }
            initializing = false
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
}
