import Foundation

/// DeepSeek V4 Flash 的 Provider 实现（OpenAI /v1/chat/completions 兼容接口）。
///
/// 计费策略为"开发者代付 + 服务端限额"：
///  - 生产：`baseURL` 指向开发者自己的限额代理（key 不进客户端），由代理转发并限额。
///  - 本地调试：可临时设 baseURL 到 DeepSeek 官方，并传入测试 key，直连验证。
/// 模型名、价格等不写死在业务层；换模型只需换 Provider。
final class DeepSeekProvider: AIProvider {

    /// 服务端代付代理地址，如 "https://cineai-proxy.example.com/v1"。
    private let baseURL: URL
    private let apiKey: String?
    private let model: String
    private let session: URLSession

    init(
        baseURL: URL,
        apiKey: String? = nil,
        model: String = "deepseek-chat",
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    func complete(
        messages: [AIChatMessage],
        maxTokens: Int?,
        reasoning: Bool
    ) async throws -> AIResult {
        let endpoint = baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        var body: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
        ]
        if let maxTokens {
            body["max_tokens"] = maxTokens
        }
        if reasoning {
            // V1 一律非思考；此开关为未来复杂推荐预留。
            body["reasoning"] = true
        }
        request.httpBody = try JSONSerialization.data(
            withJSONObject: body,
            options: []
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CineAIError.invalidResponse
        }
        guard http.statusCode == 200 else {
            throw CineAIError.server(status: http.statusCode, body: String(data: data, encoding: .utf8))
        }

        let payload = try JSONDecoder().decode(ChatCompletion.self, from: data)
        let text = payload.choices.first?.message.content ?? ""
        let usage = payload.usage
        return AIResult(
            text: text,
            inputTokens: usage?.promptTokens ?? 0,
            outputTokens: usage?.completionTokens ?? 0
        )
    }
}

// MARK: - DeepSeek/OpenAI chat completions 响应模型

private struct ChatCompletion: Decodable {
    struct Choice: Decodable {
        struct Msg: Decodable {
            let content: String?
        }
        let message: Msg
    }
    struct Usage: Decodable {
        let promptTokens: Int?
        let completionTokens: Int?
        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
        }
    }
    let choices: [Choice]
    let usage: Usage?
}

enum CineAIError: LocalizedError {
    case invalidResponse
    case server(status: Int, body: String?)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "AI 服务返回了无效响应"
        case .server(let status, let body):
            return "AI 服务错误（\(status)）\(body ?? "")"
        }
    }
}
