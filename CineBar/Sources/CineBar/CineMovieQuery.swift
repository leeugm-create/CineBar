import Foundation

/// 一道"自然语言找片"被拆解后的结构化查询。
/// 供 TMDB discover 组装过滤条件；无法结构化的保留原文做整句搜索兜底。
struct CineMovieQuery: Equatable {
    /// TMDB 类型 id（可能多个，取交集）
    var genreIDs: [Int] = []
    /// 可匹配的关键词（如时间循环、逆转），可空
    var keyword: String?
    /// 年份上限：近似"这类片子"的现代定位，可空；eg. 今年 → 当前年份
    var year: Int?
    /// 评分下限（高分/豆瓣8分 → 7.0；经典 → 7.5）
    var minVote: Double?
    /// 是否要"冷门/小众"（排序影响，不设条件）
    var wantObscure: Bool = false
}

/// 把中文影视自然语言拆成结构化查询（离线规则，V1；不依赖 LLM，成本为零、可测）。
/// 只做"能可靠识别"的拆解：类型/年份/评分限定/明确关键词；拆不出的保留为空，调用方回退整句搜索。
enum CineMovieQueryParser {

    /// TMDB 标准类型 id 词典（中文常见词 → id）
    private static let genreMap: [(Set<String>, Int)] = [
        (["喜剧", "搞笑", "欢乐"], 35),
        (["科幻", "未来", "科幻片"], 878),
        (["爱情", "恋爱", "言情", "浪漫"], 10749),
        (["恐怖", "惊悚", "吓人", "惊吓"], 27),       // 恐怖
        (["动作", "打斗", "武打", "武侠", "枪战"], 28),
        (["犯罪", "警匪", "破案"], 80),
        (["动画", "动漫"], 16),
        (["冒险", "探险", "夺宝"], 12),
        (["悬疑", "推理", "烧脑"], 9648),
        (["奇幻", "魔幻", "魔法"], 14),
        (["剧情", "温情", "文艺", "治愈"], 18),
        (["战争", "二战", "越战"], 10752),
        (["音乐", "歌舞", "演唱会"], 10402),
        (["家庭", "亲子"], 10751),
        (["历史", "传记", "古装"], 36),
        (["纪录片", "纪实"], 99),
        (["西部"], 37),
    ]

    /// 年份提取：中文/数字（"今年"→当前年，"2020年"→2020，"近年"→当前年-3）
    private static func extractYear(_ text: String) -> Int? {
        let now = Calendar.current.component(.year, from: Date())
        // 明确的四位数年份
        if let m = text.range(of: #"(19|20)\d{2}"#, options: .regularExpression) {
            return Int(text[m])
        }
        if text.contains("今年") { return now }
        if text.contains("近年") || text.contains("最近几年") { return now - 3 }
        return nil
    }

    /// 评分限定："高分/口碑好/豆瓣8分" → ≥7；"经典/神作" → ≥7.5；"豆瓣9" → 9
    private static func extractMinVote(_ text: String) -> Double? {
        if text.range(of: #"豆瓣\s?(\d+)"#, options: .regularExpression) != nil,
           let mc = text.range(of: #"(?<=豆瓣)\s?\d+"#, options: .regularExpression) {
            return Double(text[mc].filter(\.isNumber))
        }
        if text.contains("经典") || text.contains("神作") { return 7.5 }
        if text.contains("高分") || text.contains("口碑") || text.contains("好评") {
            return 7.0
        }
        return nil
    }

    private static func isObscure(_ text: String) -> Bool {
        ["冷门", "小众", "遗珠", "神作", "不热门", "被忽略"].contains {
            text.contains($0)
        }
    }

    /// 主入口：自然语言 → 结构化查询。
    static func parse(_ input: String) -> CineMovieQuery {
        var query = CineMovieQuery()
        let text = input.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return query }

        // 1) 抓类型
        var remaining = text
        for (words, id) in genreMap {
            if let word = words.first(where: { text.contains($0) }) {
                query.genreIDs.append(id)
                remaining = remaining.replacingOccurrences(of: word, with: " ")
            }
        }

        // 2) 年份
        query.year = extractYear(text)

        // 3) 评分限定
        query.minVote = extractMinVote(text)

        // 4) 冷门
        query.wantObscure = isObscure(text)

        // 5) 关键词：去掉类型/年份/限定词后剩余的非空词，作为关键词候选
        var cleaned = remaining
        // 去掉常见的"找一部/有没有/类似/推荐/喜剧/科幻"壳子和类型无关词
        let stopwords: [String] = [
            "找一部", "找一部电影", "有没有", "有没有类似", "推荐一下", "帮我", "推荐",
            "拍拍", "类似", "那种", "一部", "的电影", "的片", "的剧", "类型",
        ]
        for w in stopwords { cleaned = cleaned.replacingOccurrences(of: w, with: " ") }
        let tokens = cleaned
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .map(String.init)
            .filter { $0.count >= 2 && !$0.hasPrefix("豆瓣") && $0 != "评价" }
        if !tokens.isEmpty {
            query.keyword = tokens.joined(separator: " ")
        }

        return query
    }
}
