import Foundation

/// 手机端直连大模型：支持 OpenAI 兼容接口（DeepSeek/Kimi/通义/自建）与 Anthropic。
struct LLMConfig: Codable, Equatable {
    enum Provider: String, Codable, CaseIterable {
        case openai = "openai"
        case anthropic = "anthropic"
        var label: String { self == .openai ? "OpenAI 兼容" : "Anthropic" }
    }
    var provider: Provider = .openai
    var baseURL: String = "https://api.deepseek.com/v1"
    var apiKey: String = ""
    var model: String = "deepseek-chat"
    var temperature: Double = 0.3
    var maxTokens: Int = 4096

    static let key = "artex.llm.config"
    static func load() -> LLMConfig {
        guard let d = UserDefaults.standard.data(forKey: key),
              let c = try? JSONDecoder().decode(LLMConfig.self, from: d) else { return LLMConfig() }
        return c
    }
    func save() {
        if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: LLMConfig.key) }
    }
    var ready: Bool { !apiKey.isEmpty && !baseURL.isEmpty && !model.isEmpty }
}

enum LLMError: LocalizedError {
    case notConfigured, http(Int, String), decode(String)
    var errorDescription: String? {
        switch self {
        case .notConfigured: return "未配置模型，请到「模型」页填写 API Key"
        case .http(let c, let m): return "模型返回 HTTP \(c)：\(m)"
        case .decode(let m): return "响应解析失败：\(m)"
        }
    }
}

struct LLMMessage {
    var role: String   // system / user / assistant / tool
    var content: String
    var toolCallId: String?
}

struct ToolCall {
    var id: String
    var name: String
    var arguments: String
}

struct LLMReply {
    var content: String
    var toolCalls: [ToolCall]
}

final class LLMClient {
    static let shared = LLMClient()
    var config = LLMConfig.load()

    func update(_ c: LLMConfig) { config = c; c.save() }

    /// 一次补全（含工具定义）
    func complete(messages: [LLMMessage], tools: [[String: Any]]) async throws -> LLMReply {
        guard config.ready else { throw LLMError.notConfigured }
        switch config.provider {
        case .openai: return try await openai(messages, tools: tools)
        case .anthropic: return try await anthropic(messages, tools: tools)
        }
    }

    // MARK: - OpenAI 兼容
    private func openai(_ messages: [LLMMessage], tools: [[String: Any]]) async throws -> LLMReply {
        var urlStr = config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !urlStr.hasSuffix("/chat/completions") { urlStr += "/chat/completions" }
        guard let url = URL(string: urlStr) else { throw LLMError.decode("baseURL 无效") }

        var msgs: [[String: Any]] = []
        for m in messages {
            var d: [String: Any] = ["role": m.role, "content": m.content]
            if let id = m.toolCallId { d["tool_call_id"] = id }
            msgs.append(d)
        }
        var body: [String: Any] = [
            "model": config.model,
            "messages": msgs,
            "temperature": config.temperature,
            "max_tokens": config.maxTokens,
        ]
        if !tools.isEmpty { body["tools"] = tools; body["tool_choice"] = "auto" }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 180
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw LLMError.decode("无响应") }
        guard (200..<300).contains(http.statusCode) else {
            throw LLMError.http(http.statusCode, String(data: data, encoding: .utf8)?.prefix(300).description ?? "")
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let first = choices.first,
              let msg = first["message"] as? [String: Any] else {
            throw LLMError.decode("结构不符")
        }
        let content = msg["content"] as? String ?? ""
        var calls: [ToolCall] = []
        if let tcs = msg["tool_calls"] as? [[String: Any]] {
            for tc in tcs {
                let id = tc["id"] as? String ?? UUID().uuidString
                guard let fn = tc["function"] as? [String: Any] else { continue }
                let name = fn["name"] as? String ?? ""
                let args = fn["arguments"] as? String ?? "{}"
                calls.append(ToolCall(id: id, name: name, arguments: args))
            }
        }
        return LLMReply(content: content, toolCalls: calls)
    }

    // MARK: - Anthropic
    private func anthropic(_ messages: [LLMMessage], tools: [[String: Any]]) async throws -> LLMReply {
        var urlStr = config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !urlStr.hasSuffix("/messages") { urlStr += "/v1/messages" }
        guard let url = URL(string: urlStr) else { throw LLMError.decode("baseURL 无效") }

        let system = messages.first { $0.role == "system" }?.content ?? ""
        var msgs: [[String: Any]] = []
        for m in messages where m.role != "system" {
            msgs.append(["role": m.role == "assistant" ? "assistant" : "user", "content": m.content])
        }
        var body: [String: Any] = [
            "model": config.model,
            "max_tokens": config.maxTokens,
            "messages": msgs,
        ]
        if !system.isEmpty { body["system"] = system }
        if !tools.isEmpty {
            body["tools"] = tools.map { t -> [String: Any] in
                let fn = t["function"] as? [String: Any] ?? [:]
                return [
                    "name": fn["name"] as? String ?? "",
                    "description": fn["description"] as? String ?? "",
                    "input_schema": fn["parameters"] as? [String: Any] ?? ["type": "object"],
                ]
            }
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 180
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw LLMError.decode("无响应") }
        guard (200..<300).contains(http.statusCode) else {
            throw LLMError.http(http.statusCode, String(data: data, encoding: .utf8)?.prefix(300).description ?? "")
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let blocks = obj["content"] as? [[String: Any]] else {
            throw LLMError.decode("结构不符")
        }
        var text = ""
        var calls: [ToolCall] = []
        for b in blocks {
            let type = b["type"] as? String ?? ""
            if type == "text" { text += b["text"] as? String ?? "" }
            if type == "tool_use" {
                let id = b["id"] as? String ?? UUID().uuidString
                let name = b["name"] as? String ?? ""
                let input = b["input"] as? [String: Any] ?? [:]
                let args = (try? JSONSerialization.data(withJSONObject: input))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                calls.append(ToolCall(id: id, name: name, arguments: args))
            }
        }
        return LLMReply(content: text, toolCalls: calls)
    }
}
