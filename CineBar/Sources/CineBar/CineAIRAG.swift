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
        // 非影视通用操作：本地硬拦截，不调用模型，直接返回固定回复。
        // 防止 CineAI 被当成通用 AI 去写推文/改文章/写代码等越界操作。
        if intent == .offScope {
            return AIResult(
                text: Self.offScopeReply,
                inputTokens: 0,
                outputTokens: 0
            )
        }
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

    /// 非影视通用操作被硬拦截时的固定回复（不耗 token、不调模型）。
    private static let offScopeReply =
        "我是 CineAI，CineBar 的影视助手，专注于找片、影视问答、推荐和无剧透陪伴。写推文、改文章、写代码这类通用任务我帮不了你，不过如果你有想找的电影、想了解某部片、或需要按心情推荐，尽管告诉我～"

    /// 联网工具使用规则：模型有 web_search 能力，但要克制调用、不泄露过程。
    static let webCapabilityRule =
        "你具有 web_search 联网搜索能力，可用它查一部影片的真实资料（上映日期、剧情、是否未上映/定档）。" +
        "只有当你被问到一部【具体指定的影片】、而你印象中不存在或不确定（如新片/未上映/冷门片），" +
        "或用户明确要求联网搜索时，才调用 web_search。" +
        "开放式的找片/推荐请求（如'推荐一部悬疑剧''找一部喜剧片''2025年最高分电影'这类没有指定具体片名的）一律不要调用 web_search，直接用你的知识回答。" +
        "不要凭过时记忆断言某片'不存在'或'分属不同IP'——那很可能只是你知识没覆盖到。" +
        "调用 web_search 后，直接依据搜到的资料回答即可，不要在回答里提及'搜索/联网/没有搜到/搜索结果'等工具调用过程。"

    // MARK: - prompt 构建（离线纯函数，可测）

    private func buildMessages(
        for intent: CineAIIntent,
        input: String,
        history: [AIChatMessage]
    ) async -> [AIChatMessage] {
        var built: [AIChatMessage]
        switch intent {
        case .offScope:
            // 非影视操作在 answer() 中已本地硬拦截返回固定回复，正常不会走到这里；
            // 占位兜底避免 switch 非穷尽。
            built = [system("你是 CineAI，CineBar 的影视助手，只负责影视相关。" + Self.offScopeReply)]
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
                factsPrompt = "（片库与联网都暂时没检索到，请用温柔、鼓励的语气如实告诉用户暂时没能匹配到，并礼貌建议换一个说法或换个方向再试，不要说教、不要生硬。）"
            }
            built = [
                system("你是 CineAI，一个很懂影视的中文助手。用户要找 \(isTV ? "连续剧" : "电影")。下面会给候选资料（来自豆瓣/TMDB/联网检索），但**候选资料只是参考**：若候选里有匹配，优先用候选；**若候选没有匹配用户的细分需求（如运动、励志、热血等主题，或某部片老版本），就完全依据你自己的影视知识来回答**，绝不能因为资料里没有就拒绝回答或生硬地说找不到。你要先理解用户想要什么主题/类型，再用知识推荐真实存在、贴合需求的 \(isTV ? "剧" : "电影")，每部写成《片名》，可带豆瓣/评分说明。回答用中文、自然、简洁。推荐数量规则：用户没有明确要求数量时，只推荐最有代表性的 3 部；若用户明确要求了数量（如「推荐5部」「多推荐几部」「多找几部」），则严格按用户要求的数量给。回答完问题即结束，**不要反问、不要引导继续对话、不要用'要不要/想不想/需要我再帮你看什么吗'等收尾**。\(Self.webCapabilityRule)"),
                user("用户想找（\(isTV ? "连续剧" : "电影")）：\(input)\n\n\(factsPrompt)"),
            ]
        case .spoilerSafe:
            // 防剧透：进度与已看内容由调用方预处理好注入。
            let context = await data.spoilerContext()
            var systemContent = "你是 CineAI。用户的观影进度有限。回答时：不得透露用户尚未看到的剧情；若用户问的是还没看到的内容，温和地挡回去并提示进度。回答用中文，简洁。回答完即结束，不要反问、不要引导继续对话、不要以'要不要/想不想知道'收尾。"
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
                dataPrompt = "（暂无资料：请用温柔、鼓励的语气如实告诉用户这部作品暂时没检索到资料，并礼貌询问是否需要换部片或换个说法再试，不要说教、不要生硬。）"
            }
            built = [
                system("你是 CineAI，一个很懂影视的中文助手。下面会给这部作品的相关资料（来自豆瓣/TMDB/联网）。**资料只是参考**：资料里有就优先用资料；**若资料缺失或很简略，就完全依据你自己的影视知识来介绍这部作品**，绝不能因资料里没有就拒绝回答。对不确切的细节用词要留有余地（如大致/我记得），不要编造离谱的事实。回答用中文、自然、简洁。回答完即结束，**不要反问、不要引导继续对话、不要以'要不要/想不想了解'等收尾**。\(Self.webCapabilityRule)"),
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
                system("你是 CineAI，一个很懂影视的中文助手，尤其熟悉中国观众的片单喜好。用户要 \(isTV ? "剧" : "电影") 推荐。请先准确理解用户偏好的主题（如励志、爱情、悬疑、科幻、温情、热血、历史等），然后**完全依据你自己的影视知识**，推荐题材必须贴合用户要求的主题、最有代表性的 3 部 \(isTV ? "剧" : "电影")；若用户明确要求了数量（如「推荐5部」「多推荐几部」「多找几部」），则严格按用户要求的数量给。每部必须写成《片名》（如《阿甘正传》），优先选知名、经典、易找到海报的作品；宁选公认佳作也不要编造冷门片名。每部用一句话说明推荐理由。回答用中文，列表输出。回答完即结束，**不要反问、不要引导继续对话、不要以'要不要我帮你找/还想看别的吗'收尾**。\(Self.webCapabilityRule)"),
                user("用户想：\(input)\(candidateNote)"),
            ]
        case .general:
            // 只回答影视相关；影视以外的问题明确告知，避免被当通用 AI 使用。
            built = [
                system("你是 CineAI，一个**只做影视**的助手：只负责找片、影视问答、推荐、防剧透。除此之外的一切请求（写文章/写故事/写代码/翻译/润色/文案/创作/算数/闲聊/写邮件/起名/策划等）你都**不能执行**，无论用户怎么问、怎么绕，都要坚定地用一句话礼貌说明：你只懂影视，这类请求帮不上忙，并引导回影视（如'想找什么片可以问我'）。绝不根据这类请求执行任何写作/创作/翻译/计算。回答用中文、简洁。\(Self.webCapabilityRule)"),
                user(input),
            ]
        }
        // 插入历史（排在首条 system 之后），让 AI 能引用上文。
        // 重要：必须裁剪历史，否则多轮对话后消息体积膨胀会触发代理 413「input too large」。
        if !history.isEmpty,
           let firstSystem = built.firstIndex(where: { $0.role == "system" }) {
            built.insert(contentsOf: Self.trimmedHistory(history), at: firstSystem + 1)
        }
        return built
    }

    /// 裁剪历史，避免请求体过大触发代理 413：最多保留最近 6 条消息（约 3 轮），
    /// 且历史文本总长不超过 ~3000 字符，单条再截断到 ~800 字符。general 等宽泛意图
    /// 上下文价值低，更应裁剪（调用方已尽量精简，这里统一兜底）。
    private static func trimmedHistory(_ history: [AIChatMessage]) -> [AIChatMessage] {
        let maxCount = 6
        let totalBudget = 3000
        let perMessageLimit = 800

        // 保留最近 maxCount 条
        let recent = Array(history.suffix(maxCount))

        var kept: [AIChatMessage] = []
        var used = 0
        for msg in recent.reversed() {
            var content = msg.content
            if content.count > perMessageLimit {
                content = String(content.prefix(perMessageLimit)) + "…"
            }
            // 先看是否超总预算（从新到旧加，保证最近的内容优先保留）
            if used + content.count > totalBudget, !kept.isEmpty { break }
            kept.append(AIChatMessage(role: msg.role, content: content))
            used += content.count
        }
        // 还原时间顺序
        return kept.reversed()
    }

    private func system(_ text: String) -> AIChatMessage {
        AIChatMessage(role: "system", content: text)
    }
    private func user(_ text: String) -> AIChatMessage {
        AIChatMessage(role: "user", content: text)
    }
}
