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

        // 把前端请求代理到内置服务
        let proxy = LocalAPIProxy()
        cfg.setURLSchemeHandler(proxy, forURLScheme: "artex")
        context.coordinator.proxy = proxy

        // 允许 localhost 与任意来源
        cfg.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

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
        var proxy: LocalAPIProxy?
        private var retries = 0

        /// 服务端还没 ready 时自动重试加载
        func startWatchdog() {
            scheduleRetry()
        }

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
        }
        // 处理 target=_blank
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url { webView.load(URLRequest(url: url)) }
            return nil
        }
    }
}

/// 自定义 scheme 处理器（保留给未来用 file:// 之外的资源加载）
final class LocalAPIProxy: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else { return }
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comps?.scheme = "http"
        comps?.host = "127.0.0.1"
        comps?.port = 8787
        guard let target = comps?.url else { return }
        URLSession.shared.dataTask(with: target) { data, resp, err in
            if let err {
                urlSchemeTask.didFailWithError(err)
                return
            }
            if let http = resp as? HTTPURLResponse {
                urlSchemeTask.didReceive(http)
            }
            if let data { urlSchemeTask.didReceive(data) }
            urlSchemeTask.didFinish()
        }.resume()
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
