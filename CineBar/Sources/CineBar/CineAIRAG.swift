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
        /// 联网搜索：片库/TMDB 查不到时的兜底（如未上映、冷门、新网信息）。返回网页摘要文本块；空表示抓不到。
        var webSearch: (String) async -> String = { _ in "" }
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
            var web = ""
            if facts.isEmpty {
                // 片库/TMDB 查不到（未上映、影库没有、冷门新片）→ 联网搜索兜底。
                web = await data.webSearch(input)
            }
            let factsPrompt: String
            if !facts.isEmpty {
                factsPrompt = "候选资料：\(facts)"
            } else if !web.isEmpty {
                factsPrompt = "片库没有对应候选，以下是联网搜索到的真实资料（可据此回答，不要编造）：\n\(web)"
            } else {
                factsPrompt = "（片库与联网都未检索到，请据实说明，不要编造。）"
            }
            built = [
                system("你是 CineAI，一个影视助手。用户要的是连续剧还是电影，就按提供的信息回答；不要凭空编造不存在的作品。回答用中文，简洁，要点如下。"),
                user("用户想找（\(isTV ? "连续剧" : "电影")）：\(input)\n\n\(factsPrompt)"),
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
            var web = ""
            if facts.isEmpty {
                web = await data.webSearch(input)
            }
            let dataPrompt: String
            if !facts.isEmpty {
                dataPrompt = "影视资料：\n\(facts)"
            } else if !web.isEmpty {
                dataPrompt = "片库暂无资料，以下是联网搜索到的真实信息（据此回答，不要编造）：\n\(web)"
            } else {
                dataPrompt = "（暂无资料）"
            }
            built = [
                system("你是 CineAI。根据提供的影视资料回答，资料未提及的细节不要编造。若资料来自联网搜索结果，请如实说明信息来自网络。回答用中文、简洁。"),
                user("\(dataPrompt)\n\n用户问：\(input)"),
            ]
        case .recommend:
            let isTV = Self.mediaTarget(of: input) == .tv
            // 主题推荐（励志/温情/悬疑等）以模型影片知识为准，候选只是参考补充，
            // 绝不限制模型只能从候选里挑，避免被 TMDB discover 的跑题高分片带偏。
            // 候选仍请求（供海报补图管线复用），但 prompt 不强制模型使用。
            let facts = isTV
                ? await data.recommendSeries()
                : await data.recommendMovies(input)
            let candidateNote = facts.isEmpty
                ? "（没有可用的片库候选，请完全依据你自己的影片知识推荐）"
                : "\n\n以下是从片库检索到的候选（仅供海报/评分补全时参考，务必不要只从这些里选；如果它们不符合用户主题直接忽略）：\n\(facts)"
            built = [
                system("你是 CineAI，一个很懂影视的中文助手，尤其熟悉中国观众的片单喜好。用户要 \(isTV ? "剧" : "电影") 推荐。请先准确理解用户偏好的主题（如励志、爱情、悬疑、科幻、温情、热血、历史等），然后**完全依据你自己的影视知识**，推荐 \(isTV ? "3-5 部剧" : "3-5 部电影")，题材必须贴合用户要求的主题。每部必须写成《片名》（如《阿甘正传》），优先选知名、经典、易找到海报的作品；宁选公认佳作也不要编造冷门片名。每部用一句话说明推荐理由。回答用中文，列表输出，控制在 \(isTV ? "3-5" : "3-5") 部，不要多列。"),
                user("用户想：\(input)\(candidateNote)"),
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
