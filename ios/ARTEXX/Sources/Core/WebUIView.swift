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

        // 注入：把 fetch 的 /api 请求指向本机端口
        let js = """
        (function(){
          const BASE = 'http://127.0.0.1:8787';
          const origFetch = window.fetch;
          window.fetch = function(input, init){
            try {
              let url = (typeof input === 'string') ? input : (input && input.url) || '';
              if (url.startsWith('/api/')) {
                const full = BASE + url;
                if (typeof input === 'string') input = full;
                else input = new Request(full, input);
              }
            } catch(e) {}
            return origFetch.call(this, input, init);
          };
          const OrigXHR = window.XMLHttpRequest;
          window.XMLHttpRequest = function(){
            const x = new OrigXHR();
            const open = x.open;
            x.open = function(m, u, ...rest){
              if (typeof u === 'string' && u.startsWith('/api/')) u = BASE + u;
              return open.call(x, m, u, ...rest);
            };
            return x;
          };
          window.XMLHttpRequest.prototype = OrigXHR.prototype;
          // EventSource（SSE）
          const OrigES = window.EventSource;
          if (OrigES) {
            window.EventSource = function(u, c){
              if (typeof u === 'string' && u.startsWith('/api/')) u = BASE + u;
              return new OrigES(u, c);
            };
            window.EventSource.prototype = OrigES.prototype;
          }
        })();
        """
        let script = WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        wv.configuration.userContentController.addUserScript(script)

        // 加载打包的 index.html
        if let index = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "webui") {
            wv.loadFileURL(index, allowingReadAccessTo: index.deletingLastPathComponent())
        } else if let index = Bundle.main.url(forResource: "index", withExtension: "html") {
            wv.loadFileURL(index, allowingReadAccessTo: index.deletingLastPathComponent())
        } else {
            let html = "<h1 style='color:#fff;font-family:-apple-system'>webui 资源未打包</h1>"
            wv.loadHTMLString(html, baseURL: nil)
        }
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        weak var webView: WKWebView?
        var proxy: LocalAPIProxy?

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
