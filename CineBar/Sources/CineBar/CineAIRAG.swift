import Foundation

/// CineAI 的检索增强（RAG）层：把"查到的数据"拼进 prompt，再交给 AIProvider 组织回答。
///
/// 原则（见 CINEAI-PLAN §4/§6）：
///  - 影视事实一律从注入的检索闭包拿到结构化数据，再喂给模型，禁止模型凭记忆编。
///  - 防剧透：只把"用户进度以内"的剧集资料注入，之后的集绝不进上下文。
///
/// 本文件只做「prompt 构建 + 调度」，数据获取通过注入闭包，离线可测。
struct CineAIRAG {

    /// 用户想要的媒体类型：由输入是否含"剧/连续剧/电视剧/番剧"推断。
    enum MediaTarget { case movie, tv }

    /// 从输入推断电影还是连续剧。
    static func mediaTarget(of input: String) -> MediaTarget {
        let seriesWords = ["连续剧", "电视剧", "剧集", "番剧", "电视剧", "看剧", "连续电视剧"]
        if seriesWords.contains(where: { input.localizedCaseInsensitiveContains($0) }) {
            return .tv
        }
        return .movie
    }

    /// 数据提供方（由调用方接线到 TMDB / MovieStore / ProgressStore）。
    struct DataSource {
        /// 影视事实（简介/评分/年份等），以任意文本块返回。
        var fetchFacts: (String) async -> String = { _ in "" }
        /// 找片：把自然语言转成检索词，返回候选片名/简介文本块（电影）。
        var searchMovies: (String) async -> String = { _ in "" }
        /// 找剧：返回候选连续剧名/简介文本块。
        var searchSeries: (String) async -> String = { _ in "" }
        /// 推荐：按用户影视偏好返回候选（电影）。
        var recommendMovies: (String) async -> String = { _ in "" }
        /// 推荐连续剧：按偏好返回候选（剧集）。
        var recommendSeries: () async -> String = { "" }
        /// 防剧透：当前剧的上下文（进度 + 已看集资料）。返回文本块；空表示无。
        var spoilerContext: () async -> String = { "" }
    }

    let provider: AIProvider
    var data: DataSource = DataSource()

    // MARK: - 调度入口

    /// 发起一次回答。
    /// - Parameters:
    ///   - intent: 意图。
    ///   - input: 当前用户输入。
    ///   - history: 本轮之前的对话（不含 system，按先后顺序），用于让 AI 记住上文。
    func answer(
        _ intent: CineAIIntent,
        input: String,
        history: [AIChatMessage] = []
    ) async throws -> AIResult {
        var messages = await buildMessages(for: intent, input: input, history: history)
        // 确保首条是 system（供模型扮演设定）
        if messages.first?.role != "system" {
            messages.insert(
                AIChatMessage(role: "system", content: "你是 CineAI，CineBar 的影视助手。回答用中文、简洁；影视事实以提供的数据为准，不编造。"),
                at: 0
            )
        }
        return try await provider.complete(
            messages: messages,
            maxTokens: 900,
            reasoning: false
        )
    }

    // MARK: - prompt 构建（离线纯函数，可测）

    private func buildMessages(
        for intent: CineAIIntent,
        input: String,
        history: [AIChatMessage]
    ) async -> [AIChatMessage] {
        var built: [AIChatMessage]
        switch intent {
        case .findMovie:
            let isTV = Self.mediaTarget(of: input) == .tv
            let facts = isTV
                ? await data.searchSeries(input)
                : await data.searchMovies(input)
            built = [
                system("你是 CineAI，一个影视助手。用户要的是连续剧还是电影，就以提供的候选为准给对应的推荐；不要凭空编造不存在的作品。回答用中文，简洁，给出名称并说明理由，如需多部用列表。"),
                user("用户想找（\(isTV ? "连续剧" : "电影")）：\(input)\n\n候选资料：\(facts.isEmpty ? "（未检索到候选，请据实说明找不到匹配）" : facts)"),
            ]
        case .spoilerSafe:
            // 防剧透：进度与已看内容由调用方预处理好注入。
            let context = await data.spoilerContext()
            var systemContent = "你是 CineAI。用户的观影进度有限。回答时：不得透露用户尚未看到的剧情；若用户问的是还没看到的内容，温和地挡回去并提示进度。回答用中文，简洁。"
            var userContent = input
            if !context.isEmpty {
                systemContent += " 只能依据下面提供的已观看到的内容来回答，不得推测或透露其后的剧情。"
                userContent = "用户当前已看到的内容（以此为界，到此为止，之后的剧情严禁透露）：\n\(context)\n\n用户问：\(input)"
            }
            built = [system(systemContent), user(userContent)]
        case .mediaIntro:
            let facts = await data.fetchFacts(input)
            built = [
                system("你是 CineAI。只能根据提供的影视资料回答，不要编造资料以外的剧情细节。回答用中文，简洁。"),
                user("影视资料：\n\(facts.isEmpty ? "（暂无资料）" : facts)\n\n用户问：\(input)"),
            ]
        case .recommend:
            let isTV = Self.mediaTarget(of: input) == .tv
            // 候选仅供模型参考（可靠命中时），模型允许凭自身影片知识补足，
            // 尤其当用户给的是"励志/温情/悬疑"这类无法用 TMDB 精确查的主题词。
            let facts = isTV
                ? await data.recommendSeries()
                : await data.recommendMovies(input)
            built = [
                system("你是 CineAI，一个很懂影视的中文助手。用户要 \(isTV ? "剧" : "电影") 推荐。请先理解用户偏好里的主题（如励志、爱情、悬疑、科幻、温情、励志、历史等），结合你的影片知识推荐 \(isTV ? "3-5 部剧" : "3-5 部电影")，题材与用户要求贴合，且是真实存在的作品。每部必须写成《片名》（如《阿甘正传》），尽量知名、易找到海报；宁可选知名大片，也不要编造冷门片名。说明一句推荐理由。回答用中文，列表输出。若下方给了候选且候选更贴合主题，优先用候选；但不要让候选限制你只能推荐这些——不必都来自候选，可以补充你知识里更好的片。"),
                user("用户想：\(input)"
                    + (facts.isEmpty
                        ? ""
                        : "\n\n以下是从片库检索到的候选（仅供参考，不必都用）：\n\(facts)")),
            ]
        case .general:
            // 只回答影视相关；影视以外的问题明确告知，避免被当通用 AI 使用。
            built = [
                system("你是 CineAI，CineBar 的影视助手，只负责影视相关问题（找片、问答、推荐、防剧透）。对与本产品影视功能无关的问题，礼貌说明你只管影视、无法回答，不要自由延展。回答用中文、简洁。"),
                user(input),
            ]
        }
        // 插入历史（排在首条 system 之后），让 AI 能引用上文。
        if !history.isEmpty,
           let firstSystem = built.firstIndex(where: { $0.role == "system" }) {
            built.insert(contentsOf: history, at: firstSystem + 1)
        }
        return built
    }

    private func system(_ text: String) -> AIChatMessage {
        AIChatMessage(role: "system", content: text)
    }
    private func user(_ text: String) -> AIChatMessage {
        AIChatMessage(role: "user", content: text)
    }
}
