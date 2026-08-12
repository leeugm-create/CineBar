import Foundation

/// CineAI 通用消息：一条对话消息。`role` 取值 "system" / "user" / "assistant"。
/// `publishedAt` 为该消息产生时间（用于在气泡下方显示时间戳）；
/// 可选（历史持久化消息可能没有），解码未缺失时兼容。
struct AIChatMessage: Codable, Equatable {
    let role: String
    let content: String
    var publishedAt: Date?

    init(role: String, content: String, publishedAt: Date? = Date()) {
        self.role = role
        self.content = content
        self.publishedAt = publishedAt
    }

    enum CodingKeys: String, CodingKey {
        case role, content, publishedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.role = try c.decode(String.self, forKey: .role)
        self.content = try c.decode(String.self, forKey: .content)
        self.publishedAt = try c.decodeIfPresent(Date.self, forKey: .publishedAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(role, forKey: .role)
        try c.encode(content, forKey: .content)
        try c.encodeIfPresent(publishedAt, forKey: .publishedAt)
    }
}

/// 一次模型调用的结果：返回文本与 token 用量（供限额与成本统计）。
struct AIResult: Codable, Equatable {
    let text: String
    let inputTokens: Int
    let outputTokens: Int

    var totalTokens: Int { inputTokens + outputTokens }
}

/// 模型调用能力的抽象。业务层（意图路由/问答/推荐）只依赖本协议，
/// 不绑定任何具体厂商。换模型只新增一个遵守本协议的 Provider 实现。
protocol AIProvider {
    /// 发起一次 chat 补全。
    /// - Parameters:
    ///   - messages: 完整对话（system + 历史 + 当前询问）。
    ///   - maxTokens: 输出长度上限；nil 用 Provider 默认。
    ///   - reasoning: 是否启用深度思考模式（V1 一律 false，为未来复杂推荐预留）。
    func complete(
        messages: [AIChatMessage],
        maxTokens: Int?,
        reasoning: Bool
    ) async throws -> AIResult
}

// MARK: - 便于测试的替身

/// 测试用假 Provider：把给定的兜底文本当成回答，token 计数为 0。
/// 用于在不联网、不花钱的情况下跑通意图路由与 UI。
struct StubAIProvider: AIProvider {
    var fallback: String = "（测试占位回答）"

    func complete(
        messages: [AIChatMessage],
        maxTokens: Int?,
        reasoning: Bool
    ) async throws -> AIResult {
        AIResult(text: fallback, inputTokens: 0, outputTokens: 0)
    }
}
