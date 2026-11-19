import SwiftUI
import WebKit

/// 原版 Web UI 容器：用 WKWebView 加载打进 App 的 ARTEXX 前端静态文件。
/// 前端请求 /api/* 时，走本机内置服务端（127.0.0.1:8787），数据是真实流转。
struct WebUIView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []

        // 关键：前端登录守卫读 localStorage.artex_token，
        // 页面脚本执行前就注入，用户不用在手机上再登录一次。
        let token = EmbeddedServer.shared.token
        let inject = """
        try {
          localStorage.setItem('artex_token', '\(token)');
          document.cookie = 'artex_token=\(token); path=/; max-age=31536000';
        } catch (e) {}
        """
        cfg.userContentController.addUserScript(
            WKUserScript(source: inject, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        )

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
        context.coordinator.startWatchdog()
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        weak var webView: WKWebView?
        private var retries = 0

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
