import Foundation

/// 豆瓣搜索结果条目（从搜索页 window.__DATA__ 解析）。
struct DoubanSearchItem: Decodable {
    let id: Int
    let title: String
    let rating: DoubanRatingData?
    let abstract: String?
    let url: String?
}

struct DoubanRatingData: Decodable {
    let value: Double?
    let starCount: Double?
    let count: Int?

    private enum CodingKeys: String, CodingKey {
        case value
        case starCount = "star_count"
        case count
    }
}

/// 豆瓣评分抓取结果。
struct DoubanRatingResult: Hashable {
    let doubanID: Int
    let title: String
    let score: Double
    let voteCount: Int?
    let pageURL: String
}

/// 豆瓣评分客户端：抓取 search.douban.com 搜索页，解析 window.__DATA__ JSON，
/// 按标题（可选年份）匹配返回豆瓣评分。抓取公开页、非登录，不保证稳定。
struct DoubanRatingClient {
    var session: URLSession = .shared

    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
        + "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    /// 搜索并返回匹配标题/年份的豆瓣评分。找不到返回 nil（不抛错，静默降级）。
    func search(
        title: String,
        year: Int?
    ) async throws -> DoubanRatingResult? {
        var components = URLComponents(
            string: "https://search.douban.com/movie/subject_search"
        )
        components?.queryItems = [
            URLQueryItem(name: "search_text", value: title),
            URLQueryItem(name: "cat", value: "1002")
        ]
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(
            "https://movie.douban.com/",
            forHTTPHeaderField: "Referer"
        )
        request.setValue(
            "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            forHTTPHeaderField: "Accept"
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200 else { return nil }
        let html = String(data: data, encoding: .utf8) ?? ""
        guard let items = Self.parseSearchJSON(from: html), !items.isEmpty else {
            return nil
        }
        return Self.match(items: items, title: title, year: year)
    }

    /// 从搜索页 HTML 提取并解析 window.__DATA__ 的 JSON 数据。
    static func parseSearchJSON(from html: String) -> [DoubanSearchItem]? {
        // 提取 window.__DATA__ = {...};
        guard let range = html.range(of: "window.__DATA__"),
              let openParen = html.range(of: "=", options: [], range: range.upperBound..<html.endIndex),
              let start = html.range(of: "{", options: [], range: openParen.upperBound..<html.endIndex) else {
            return nil
        }
        // 从 { 开始做括号配平提取 JSON
        var depth = 0
        var inString = false
        var escaped = false
        var endIndex = start.lowerBound
        let chars = Array(html[start.lowerBound...])
        for (i, ch) in chars.enumerated() {
            if inString {
                if escaped { escaped = false }
                else if ch == "\\" { escaped = true }
                else if ch == "\"" { inString = false }
            } else {
                switch ch {
                case "\"": inString = true
                case "{": depth += 1
                case "}":
                    depth -= 1
                    if depth == 0 {
                        endIndex = html.index(start.lowerBound, offsetBy: i)
                        break
                    }
                default: break
                }
            }
            if depth == 0 && endIndex != start.lowerBound { break }
        }
        guard depth == 0 else { return nil }
        let jsonText = String(html[start.lowerBound...endIndex])
        guard let data = jsonText.data(using: .utf8) else { return nil }
        // __DATA__ 顶层 { items: [...] }
        struct Wrapper: Decodable { let items: [DoubanSearchItem]? }
        guard let wrapper = try? JSONDecoder().decode(Wrapper.self, from: data) else {
            return nil
        }
        guard var result = wrapper.items else { return nil }
        // 去掉类型非影视的条目（is_tv 等）用 abstract 辅助
        result = result.filter { $0.rating?.value != nil }
        return result
    }

    static func match(
        items: [DoubanSearchItem],
        title: String,
        year: Int?
    ) -> DoubanRatingResult? {
        let normalized = normalize(title)
        guard !normalized.isEmpty else { return nil }

        // 先按标题精确匹配（去除标点/大小写后相等），再按包含匹配，各自优先年份一致的结果。
        struct Ranked {
            let item: DoubanSearchItem
            let rank: Int   // 越小越优先
        }
        func rank(_ item: DoubanSearchItem) -> Int? {
            guard item.rating?.value != nil else { return nil }
            let cNorm = normalize(item.title)
            guard !cNorm.isEmpty else { return nil }
            if cNorm == normalized {
                return year.map { abstractContains(item, year: $0) } ?? true ? 0 : 1
            }
            if cNorm.contains(normalized) || normalized.contains(cNorm) {
                return year.map { abstractContains(item, year: $0) } ?? true ? 2 : 3
            }
            return nil
        }

        let ranked = items.compactMap { item -> Ranked? in
            guard let r = rank(item) else { return nil }
            return Ranked(item: item, rank: r)
        }.sorted { $0.rank < $1.rank }

        guard let best = ranked.first else { return nil }
        return DoubanRatingResult(
            doubanID: best.item.id,
            title: best.item.title,
            score: best.item.rating?.value ?? 0,
            voteCount: best.item.rating?.count,
            pageURL: best.item.url ?? "https://movie.douban.com/subject/\(best.item.id)/"
        )
    }

    private static func abstractContains(_ item: DoubanSearchItem, year: Int) -> Bool {
        guard let abstract = item.abstract else { return false }
        return abstract.contains(String(year))
    }

    private static func normalize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "[^\\p{L}\\p{N}]", with: "", options: .regularExpression)
            .lowercased()
    }
}
