import SwiftUI
import WebKit

/// 原版 Web UI 容器：用 WKWebView 加载打进 App 的 ARTEXX 前端静态文件。
/// 前端请求 /api/* 时，走本机内置服务端（127.0.0.1:8787），数据是真实流转。
struct WebUIView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    /// 当前该注入的 token：Go 后端起来了就用它签发的真 JWT；否则回落到 Swift 内置服务的 token。
    static func activeToken() -> String {
        GoBackend.shared.started ? GoBackend.shared.authToken : EmbeddedServer.shared.token
    }

    /// atDocumentStart 注入脚本：有 token 就写入（覆盖上一轮可能残留的陈旧 token），
    /// 无 token 就清除——否则陈旧的无效 token 会被后端判 401，前端在 /login 与主界面间
    /// 无限重定向（就是“一直闪”的根因）。
    static func tokenScript(_ token: String) -> String {
        if token.isEmpty {
            return "try{localStorage.removeItem('artex_token');document.cookie='artex_token=; path=/; max-age=0';}catch(e){}"
        }
        return "try{localStorage.setItem('artex_token','\(token)');"
            + "document.cookie='artex_token=\(token); path=/; max-age=31536000';}catch(e){}"
    }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []

        // 页面脚本执行前就把 token 落到 localStorage，用户不用在手机上再登录一次。
        // 持有 WKUserContentController 自己的引用：wv.configuration 返回的是副本，
        // 运行期要稳妥地增删脚本得用建视图时这一份。
        let ucc = WKUserContentController()
        cfg.userContentController = ucc
        let token = WebUIView.activeToken()
        ucc.addUserScript(
            WKUserScript(source: WebUIView.tokenScript(token), injectionTime: .atDocumentStart, forMainFrameOnly: false)
        )
        context.coordinator.ucc = ucc

        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = context.coordinator
        wv.uiDelegate = context.coordinator
        wv.allowsBackForwardNavigationGestures = true
        wv.scrollView.bounces = true
        wv.isOpaque = false
        wv.backgroundColor = UIColor(red: 0.039, green: 0.039, blue: 0.039, alpha: 1)
        wv.scrollView.backgroundColor = wv.backgroundColor
        context.coordinator.webView = wv

        // 从内置服务加载（真实 origin，前端绝对路径与 /api 全部天然可用）
        let port = EmbeddedServer.shared.port
        if let url = URL(string: "http://127.0.0.1:\(port)/") {
            wv.load(URLRequest(url: url))
        }
        // token 就绪通知：竞态下（WebView 先建、token 后到）刷新注入并重载。
        context.coordinator.observeAuthReady()
        // 建视图时 token 还空的话，下一拍再查一次（此刻 ensureAuthToken 可能刚写好）。
        if token.isEmpty {
            DispatchQueue.main.async { context.coordinator.applyFreshToken() }
        }
        context.coordinator.startWatchdog()
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        weak var webView: WKWebView?
        /// 建视图时这份注入脚本容器（wv.configuration 是副本，不可靠）。
        weak var ucc: WKUserContentController?
        private var retries = 0

        deinit { NotificationCenter.default.removeObserver(self) }

        func observeAuthReady() {
            NotificationCenter.default.addObserver(
                self, selector: #selector(onAuthReady), name: GoBackend.authReady, object: nil
            )
        }

        // 通知由 Go 后端后台线程发出，WKWebView 必须回主线程再动。
        @objc private func onAuthReady() {
            DispatchQueue.main.async { [weak self] in self?.applyFreshToken() }
        }

        /// 拿到真 token 后：替换注入脚本（供后续导航）、当场写入 localStorage 并重载一次，
        /// 让前端的登录守卫用真 token 重新判定，落到主界面。
        func applyFreshToken() {
            guard let wv = webView else { return }
            let token = WebUIView.activeToken()
            guard !token.isEmpty else { return }
            if let ucc {
                ucc.removeAllUserScripts()
                ucc.addUserScript(
                    WKUserScript(source: WebUIView.tokenScript(token), injectionTime: .atDocumentStart, forMainFrameOnly: false)
                )
            }
            wv.evaluateJavaScript(WebUIView.tokenScript(token)) { [weak wv] _, _ in
                wv?.reload()
            }
        }

        /// 服务端还没 ready 时自动重试加载
        func startWatchdog() { scheduleRetry() }

        private func scheduleRetry() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self, let wv = self.webView else { return }
                if wv.url == nil || (wv.url?.scheme ?? "") != "http" {
                    self.retries += 1
                    if self.retries <= 15 {
                        let port = EmbeddedServer.shared.port
                        if let u = URL(string: "http://127.0.0.1:\(port)/") {
                            wv.load(URLRequest(url: u))
                        }
                        self.scheduleRetry()
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            NSLog("[ARTEXX] Web UI loaded")
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            NSLog("[ARTEXX] Web UI fail: \(error.localizedDescription)")
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            NSLog("[ARTEXX] Web UI provisional fail: \(error.localizedDescription)")
            // 服务端可能还在启动，稍后重试一次
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak webView] in
                guard let wv = webView else { return }
                let port = EmbeddedServer.shared.port
                if let u = URL(string: "http://127.0.0.1:\(port)/") { wv.load(URLRequest(url: u)) }
            }
        }
        // 处理 target=_blank
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url { webView.load(URLRequest(url: url)) }
            return nil
        }
    }
}
