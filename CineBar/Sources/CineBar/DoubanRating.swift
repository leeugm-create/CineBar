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

/// 豆瓣抓取全局闸门：串行执行所有豆瓣请求，避免并发触发频率限制。
actor DoubanSearchGate {
    static let shared = DoubanSearchGate()

    private var lastRequestAt = Date.distantPast
    private let minimumInterval: TimeInterval = 0.8

    func throttled<T>(_ operation: () async throws -> T) async throws -> T {
        let elapsed = Date().timeIntervalSince(lastRequestAt)
        if elapsed < minimumInterval {
            let wait = minimumInterval - elapsed
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
        lastRequestAt = Date()
        return try await operation()
    }
}

/// 豆瓣搜索结果页解析结果：条目列表 + 服务端错误信息。
struct DoubanSearchPage {
    let items: [DoubanSearchItem]?
    let errorInfo: String?

    var isRateLimited: Bool {
        guard let errorInfo else { return false }
        return errorInfo.contains("频繁")
    }
}

/// 豆瓣评分客户端：抓取 search.douban.com 搜索页，解析 window.__DATA__ JSON，
/// 按标题（可选年份）匹配返回豆瓣评分。抓取公开页、非登录，不保证稳定。
struct DoubanRatingClient {
    var session: URLSession = .shared

    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
        + "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    /// 搜索并返回匹配标题/年份的豆瓣评分。找不到返回 nil（不抛错，静默降级）。
    /// 请求经全局闸门串行节流；遇到豆瓣频率限制时指数退避重试，最多 3 次。
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

        return try await DoubanSearchGate.shared.throttled {
            var attempt = 0
            while attempt < 4 {
                attempt += 1
                let page = try await self.fetchSearchPage(url: url)
                if let items = page.items, !items.isEmpty {
                    return Self.match(items: items, title: title, year: year)
                }
                if page.isRateLimited, attempt < 4 {
                    let delay = UInt64(attempt) * 2_000_000_000
                    try? await Task.sleep(nanoseconds: delay)
                    continue
                }
                return nil
            }
            return nil
        }
    }

    private func fetchSearchPage(url: URL) async throws -> DoubanSearchPage {
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
              http.statusCode == 200 else {
            return DoubanSearchPage(items: nil, errorInfo: "HTTP 异常")
        }
        let html = String(data: data, encoding: .utf8) ?? ""
        return Self.parseSearchJSON(from: html)
    }

    /// 从搜索页 HTML 提取并解析 window.__DATA__ 的 JSON 数据。
    static func parseSearchJSON(from html: String) -> DoubanSearchPage {
        guard let range = html.range(of: "window.__DATA__"),
              let openParen = html.range(
                  of: "=",
                  options: [],
                  range: range.upperBound..<html.endIndex
              ),
              let start = html.range(
                  of: "{",
                  options: [],
                  range: openParen.upperBound..<html.endIndex
              ) else {
            return DoubanSearchPage(items: nil, errorInfo: nil)
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
        guard depth == 0 else {
            return DoubanSearchPage(items: nil, errorInfo: nil)
        }
        let jsonText = String(html[start.lowerBound...endIndex])
        guard let data = jsonText.data(using: .utf8) else {
            return DoubanSearchPage(items: nil, errorInfo: nil)
        }
        // __DATA__ 顶层 { items: [...], error_info: "..." }
        struct Wrapper: Decodable {
            let items: [DoubanSearchItem]?
            let errorInfo: String?

            enum CodingKeys: String, CodingKey {
                case items
                case errorInfo = "error_info"
            }
        }
        guard let wrapper = try? JSONDecoder().decode(Wrapper.self, from: data) else {
            return DoubanSearchPage(items: nil, errorInfo: nil)
        }
        return DoubanSearchPage(
            items: wrapper.items ?? [],
            errorInfo: wrapper.errorInfo
        )
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
            let norm = normalize(item.title)
            guard !norm.isEmpty else { return nil }
            if norm == normalized {
                if let year {
                    return abstractContains(item, year: year) ? 0 : 1
                }
                return 0
            }
            if norm.contains(normalized) || normalized.contains(norm) {
                if let year {
                    return abstractContains(item, year: year) ? 2 : 3
                }
                return 2
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

    static func normalize(_ value: String) -> String {
        value
            .replacingOccurrences(
                of: "[^\\p{L}\\p{N}]",
                with: "",
                options: .regularExpression
            )
            .lowercased()
    }
}

/// 豆瓣即将上映条目（来自 movie.douban.com/coming 表格）。
struct DoubanComingItem: Hashable {
    let title: String
    /// 如 "08月19日"，无年份。
    let displayDate: String
    let subjectID: Int
    let regions: String
    let genres: String
    let wantCount: Int
}

/// 豆瓣即将上映客户端：抓取 movie.douban.com/coming 表格（HTML 表格：
/// 上映日期 / 片名 / 类型 / 制片国家地区 / 想看数）。用于给 TMDB 即将上映
/// 列表校正中国大陆上映日期（如机器人总动员 CN 区首映 4 月 16 日、重映 8 月 19 日）。
/// 公开页、非登录，不保证稳定，失败静默降级。
struct DoubanComingClient {
    var session: URLSession = .shared

    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
        + "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    func coming() async throws -> [DoubanComingItem] {
        guard let url = URL(string: "https://movie.douban.com/coming") else {
            return []
        }
        return try await DoubanSearchGate.shared.throttled {
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(
                "https://movie.douban.com/",
                forHTTPHeaderField: "Referer"
            )
            let (data, response) = try await self.session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200 else {
                return []
            }
            let html = String(data: data, encoding: .utf8) ?? ""
            return Self.parse(html)
        }
    }

    /// 解析 coming 表格。每行：
    /// <tr>
    ///   <td>08月19日</td>
    ///   <td><a href=".../movie/subject/2131459/" title="机器人总动员 WALL·E">机器人总动员</a></td>
    ///   <td>科幻 / 动画 / 冒险</td>
    ///   <td>美国 / 中国大陆</td>
    ///   <td>135241人 想看</td>
    /// </tr>
    static func parse(_ html: String) -> [DoubanComingItem] {
        var items: [DoubanComingItem] = []
        var cursor = html.startIndex
        while let rowStart = html.range(
            of: "<tr>",
            range: cursor..<html.endIndex
        ) {
            let bodyStart = rowStart.upperBound
            let rowEnd = html.range(
                of: "</tr>",
                range: bodyStart..<html.endIndex
            )?.lowerBound ?? html.endIndex
            let row = String(html[bodyStart..<rowEnd])
            if let item = Self.parseRow(row) {
                items.append(item)
            }
            cursor = rowEnd < html.endIndex
                ? html.index(rowEnd, offsetBy: 5)
                : html.endIndex
        }
        return items
    }

    private static func parseRow(_ row: String) -> DoubanComingItem? {
        // 片名 & subjectID：<a href="https://movie.douban.com/subject/36791178/">
        guard let hrefMarker = row.range(of: "/subject/") else {
            return nil
        }
        var idDigits = ""
        for ch in row[hrefMarker.upperBound...] {
            guard ch.isNumber else { break }
            idDigits.append(ch)
        }
        guard let subjectID = Int(idDigits), subjectID > 0 else { return nil }

        let displayName: String
        if let t = extractQuoted(before: "title=\"", in: row) {
            // "<a title='机器人总动员 WALL·E'>机器人总动员</a>"
            let parts = t.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
            displayName = parts.first ?? t
        } else {
            displayName = ""
        }
        guard !displayName.isEmpty else { return nil }

        // 切出 </a> 之后的三列：类型 / 地区 / 想看
        let tail: String
        if let aEnd = row.range(of: "</a>") {
            tail = String(row[aEnd.upperBound...])
        } else {
            tail = ""
        }
        let cleaned = tail
            .replacingOccurrences(of: "<td>", with: "\n")
            .replacingOccurrences(of: "</td>", with: "\n")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let lines = cleaned
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let genres = lines.indices.contains(0) ? lines[0] : ""
        let regions = lines.indices.contains(1) ? lines[1] : ""
        let wantCount = Int(
            (lines.last ?? "").replacingOccurrences(
                of: "[^0-9]", with: "", options: .regularExpression
            )
        ) ?? 0

        return DoubanComingItem(
            title: displayName,
            displayDate: rowDate(row),
            subjectID: subjectID,
            regions: regions,
            genres: genres,
            wantCount: wantCount
        )
    }

    private static func rowDate(_ row: String) -> String {
        guard let tdStart = row.range(of: "<td>") else { return "" }
        guard let tdEnd = row.range(
            of: "</td>",
            range: tdStart.upperBound..<row.endIndex
        )?.lowerBound else { return "" }
        let raw = String(row[tdStart.upperBound..<tdEnd])
        let cleaned = raw.filter { $0.isNumber || $0 == "月" || $0 == "日" }
        guard cleaned.contains("月") else { return "" }
        return cleaned
    }

    private static func extractQuoted(before marker: String, in text: String) -> String? {
        guard let start = text.range(of: marker) else { return nil }
        guard let end = text.range(
            of: "\"",
            range: start.upperBound..<text.endIndex
        ) else { return nil }
        let value = String(text[start.upperBound..<end.lowerBound])
        return value.isEmpty ? nil : value
    }
}

/// 把豆瓣"MM月dd日"转成当年 "yyyy-MM-dd"。
enum DoubanComingDate {
    static func fullDate(_ displayDate: String) -> String? {
        let cleaned = displayDate
            .replacingOccurrences(of: "月", with: "-")
            .replacingOccurrences(of: "日", with: "")
        let parts = cleaned.split(separator: "-").map(String.init)
        guard parts.count == 2,
              let month = Int(parts[0]),
              let day = Int(parts[1]),
              (1...12).contains(month),
              (1...31).contains(day) else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: Date())
        return String(
            format: "%04d-%02d-%02d",
            year,
            month,
            day
        )
    }
}