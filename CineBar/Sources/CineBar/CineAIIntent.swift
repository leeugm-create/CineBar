import Foundation

/// CineAI V1 的意图。
enum CineAIIntent: Equatable {
    /// 自然语言找电影
    case findMovie
    /// 进度感知防剧透问答
    case spoilerSafe
    /// 影视问答（这部剧/片讲什么）
    case mediaIntro
    /// 今晚看什么（推荐）
    case recommend
    /// 闲聊/其它：非影视问题，允许正常对话（避免被强行拉回影视而生硬/文不对题）。
    case general
}

/// 把用户输入路由到各意图（V1 用轻量关键词规则，离线、可测、零成本）。
/// 找片有明确触发词；识别不出则归 general（宽松对话），而不是硬塞找片。
enum CineAIIntentRouter {

    static func route(_ input: String) -> CineAIIntent {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .general }

        // 防剧透：含"剧透/剧透吗/结局/谁死了/最后.../别剧透"等。
        if contains(text, anyOf: [
            "剧透", "结局", "谁死", "最后", "活没活", "死了没", "别剧透",
            "凶手", "真相", "反转", "大结局",
        ]) {
            return .spoilerSafe
        }

        // 推荐："今晚看什么/推荐/看点什么/求推荐/有没有好看的"
        if contains(text, anyOf: [
            "今晚看什么", "推荐", "看点什么", "求推荐", "有什么好看", "片单",
        ]) {
            return .recommend
        }

        // 该剧/片讲什么："这部剧讲什么/介绍/剧情/讲什么/讲述"
        if contains(text, anyOf: [
            "讲什么", "讲的是", "剧情", "介绍", "简介", "讲述", "这是个",
        ]) {
            return .mediaIntro
        }

        // 找片：需要明确的"找/有没有...片/影视"语义，且提及影视内容。
        if contains(text, anyOf: ["电影", "影片", "片子", "影视", "动画片", "科幻片", "喜剧片", "剧集", "电视剧"]) {
            // 主题式求片（"想看励志类的电影"）优先走推荐：模型用知识出片单，
            // 避免被 findMovie 的 TMDB 候选（蜘蛛侠/奥德赛这类高分但跑题）带偏。
            // 只有当该短语能拆出 TMDB 可精确查的结构条件时，才走 findMovie。
            // 主题词（运动/励志/热血/治愈等细分）即使没有"想看"字眼，也归推荐，
            // 由模型按影视知识推荐，而不是硬塞 TMDB 搜索。
            if contains(text, anyOf: ["想看", "想找", "求", "有没有"]) ||
                Self.hasThemeWord(text) {
                let structured = CineMovieQueryParser.parse(text)
                let hasGenres = !structured.genreIDs.isEmpty
                let hasKeyword = structured.keyword != nil
                let hasCountry = structured.countryCode != nil
                let hasYear = structured.year != nil
                let hasDecade = structured.yearStart != nil
                if !(hasGenres || hasKeyword || hasCountry || hasYear || hasDecade) {
                    return .recommend
                }
            }
            if contains(text, anyOf: ["找", "有没有", "推荐一部", "类似", "想看", "求", "介绍几部", "给几部", "类型"]) {
                return .findMovie
            }
        }
        // "找一部时间循环的喜剧"这类（无"电影"二字但明确找片）→ 有"找" + 类型
        if contains(text, anyOf: ["找一部", "有没有类似", "推荐一部"]) {
            return .findMovie
        }

        // 其余归 general（宽松对话，避免文不对题）
        return .general
    }

    /// 命中即视为"主题式求片"的中文细分主题/题材词。这些词 TMDB 不一定有
    /// 独立 genre（如运动/励志/热血），但模型懂，应走推荐而非数据库硬搜。
    private static let themeWords: [String] = [
        "运动", "励志", "热血", "治愈", "温情", "悬疑", "烧脑", "科幻",
        "爱情", "浪漫", "犯罪", "警匪", "古装", "历史", "战争", "灾难",
        "喜剧", "搞笑", "恐怖", "惊悚", "奇幻", "魔幻", "青春", "校园",
        "体育", "足球", "篮球", "拳击", "赛车", "登山", "励志类",
    ]

    private static func hasThemeWord(_ text: String) -> Bool {
        themeWords.contains { text.localizedCaseInsensitiveContains($0) }
    }

    private static func contains(_ text: String, anyOf keywords: [String]) -> Bool {
        keywords.contains { text.localizedCaseInsensitiveContains($0) }
    }
}
