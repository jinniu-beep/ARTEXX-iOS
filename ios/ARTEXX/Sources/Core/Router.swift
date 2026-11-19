import Foundation

/// 请求路由：`/api/*` → APICompat（本地实现，形状对齐原版后端），
/// 其余路径 → 打进 App 的 webui 静态文件。
///
/// 关键点：**必须先判断前缀再决定去哪**。旧实现先把 "api" 段丢掉再比较，
/// 导致所有 `/api/*` 都被当成静态文件路径返回 404 —— 原版前端因此整页空白。
@MainActor
enum Router {

    static func handle(method: String, path: String, body: Data) -> (Int, Data, String) {
        let clean = path.components(separatedBy: "?").first ?? path

        // 1) API
        if clean == "/api" || clean.hasPrefix("/api/") {
            if let res = APICompat.handle(method: method, rawPath: path, body: body) {
                return res
            }
            return (404, Data("{\"error\":\"not found\"}".utf8), "application/json; charset=utf-8")
        }

        // 2) 静态文件
        if let (data, mime) = StaticFiles.resolve(path: path) {
            return (200, data, mime)
        }
        return (404, Data("not found".utf8), "text/plain; charset=utf-8")
    }
}
