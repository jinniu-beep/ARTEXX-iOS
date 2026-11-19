import Foundation

/// 静态文件服务：把打进 App 的 webui 目录通过 HTTP 提供出去。
/// 这样原版前端运行在 http://127.0.0.1:8787 这个真实 origin 上，
/// 所有 /_next/static/... 绝对路径与 /api/* 请求都天然可用。
enum StaticFiles {

    private static let mimeTypes: [String: String] = [
        "html": "text/html; charset=utf-8",
        "js": "application/javascript; charset=utf-8",
        "mjs": "application/javascript; charset=utf-8",
        "css": "text/css; charset=utf-8",
        "json": "application/json; charset=utf-8",
        "txt": "text/plain; charset=utf-8",
        "svg": "image/svg+xml",
        "png": "image/png",
        "jpg": "image/jpeg",
        "jpeg": "image/jpeg",
        "gif": "image/gif",
        "webp": "image/webp",
        "ico": "image/x-icon",
        "woff": "font/woff",
        "woff2": "font/woff2",
        "ttf": "font/ttf",
        "map": "application/json",
        "wasm": "application/wasm",
    ]

    /// webui 根目录
    static var root: URL? {
        if let u = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "webui") {
            return u.deletingLastPathComponent()
        }
        if let u = Bundle.main.resourceURL?.appendingPathComponent("webui"),
           FileManager.default.fileExists(atPath: u.path) {
            return u
        }
        if let u = Bundle.main.url(forResource: "webui", withExtension: nil) {
            return u
        }
        return nil
    }

    /// 解析请求路径到实际文件；返回 (数据, MIME) 或 nil
    static func resolve(path rawPath: String) -> (Data, String)? {
        guard let base = root else { return nil }

        // 去掉 query
        var p = rawPath.components(separatedBy: "?").first ?? rawPath
        if p.hasPrefix("/") { p.removeFirst() }
        // 目录访问 → index.html（trailingSlash: true 的导出产物）
        if p.isEmpty || p.hasSuffix("/") { p += "index.html" }

        // 防目录穿越
        guard !p.contains("..") else { return nil }

        var fileURL = base.appendingPathComponent(p)

        // 文件不存在 → 尝试 目录/index.html
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            let alt = base.appendingPathComponent(p + "/index.html")
            if FileManager.default.fileExists(atPath: alt.path) {
                fileURL = alt
            } else if FileManager.default.fileExists(atPath: base.appendingPathComponent("404.html").path) {
                fileURL = base.appendingPathComponent("404.html")
            } else {
                return nil
            }
        }

        // 目录情况
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir), isDir.boolValue {
            fileURL = fileURL.appendingPathComponent("index.html")
        }

        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let ext = fileURL.pathExtension.lowercased()
        let mime = mimeTypes[ext] ?? "application/octet-stream"
        return (data, mime)
    }
}
