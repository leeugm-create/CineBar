import Foundation

/// CineAI 的检索增强（RAG）层：把"查到的数据"拼进 prompt，再交给 AIProvider 组织回答。
///
/// 原则（见 CINEAI-PLAN §4/§6）：
///  - 影视事实一律从注入的检索闭包拿到结构化数据，再喂给模型，禁止模型凭记忆编。
///  - 防剧透：只把"用户进度以内"的剧集资料注入，之后的集绝不进上下文。
///
/// 本文件只做「prompt 构建 + 调度」，数据获取通过注入闭包，离线可测。
struct CineAIRAG {

    /// 数据提供方（由调用方接线到 TMDB / MovieStore / ProgressStore）。
    struct DataSource {
        /// 影视事实（简介/评分/年份等），以任意文本块返回。
        var fetchFacts: (String) async -> String = { _ in "" }
        /// 找片：把自然语言转成检索词，返回候选片名/简介文本块。
        var searchMovies: (String) async -> String = { _ in "" }
    }

    let provider: AIProvider
    var data: DataSource = DataSource()

    // MARK: - 调度入口

    func answer(_ intent: CineAIIntent, input: String) async throws -> AIResult {
        let messages = await buildMessages(for: intent, input: input)
        return try await provider.complete(
            messages: messages,
            maxTokens: 900,
            reasoning: false
        )
    }

    // MARK: - prompt 构建（离线纯函数，可测）

    private func buildMessages(
        for intent: CineAIIntent,
        input: String
    ) async -> [AIChatMessage] {
        switch intent {
        case .findMovie:
            let facts = await data.searchMovies(input)
            return [
                system("你是 CineAI，一个影视助手。只能根据提供的候选影片回答推荐，不要凭空编造不存在的影片。回答用中文，简洁，给片名并说明理由，如需多部用列表。"),
                user("用户想看的：\(input)\n\n候选影片资料：\n\(facts.isEmpty ? "（未检索到候选，请据实说明找不到匹配）" : facts)"),
            ]
        case .spoilerSafe:
            // 防剧透：进度与已看内容由调用方预处理好注入。
            return [
                system("你是 CineAI。用户的观影进度有限。回答时：不得透露用户尚未看到的剧情；若用户问的是还没看到的内容，温和地挡回去并提示进度。回答用中文，简洁。"),
                user(input),
            ]
        case .mediaIntro:
            let facts = await data.fetchFacts(input)
            return [
                system("你是 CineAI。只能根据提供的影视资料回答，不要编造资料以外的剧情细节。回答用中文，简洁。"),
                user("影视资料：\n\(facts.isEmpty ? "（暂无资料）" : facts)\n\n用户问：\(input)"),
            ]
        case .recommend:
            let facts = await data.fetchFacts(input)
            return [
                system("你是 CineAI。基于提供的影片库/片单推荐，说明理由；未提供的不要编造。回答用中文，列表给出 3-5 部。"),
                user("可推荐的范围：\n\(facts.isEmpty ? "（暂无片单）" : facts)\n\n用户想：\(input)"),
            ]
        }
    }

    private func system(_ text: String) -> AIChatMessage {
        AIChatMessage(role: "system", content: text)
    }
    private func user(_ text: String) -> AIChatMessage {
        AIChatMessage(role: "user", content: text)
    }
}
