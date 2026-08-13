import Foundation

// MARK: - 持久磁盘缓存（方案 A 补充：重启不丢，同片 7 天内零请求）

final class DoubanRatingCache {
    static let shared = DoubanRatingCache()

    private struct Entry: Codable {
        var score: Double
        var count: Int?
        var subjectID: Int
        var pageURL: String
        var savedAt: Date
    }

    private let ttl: TimeInterval = 7 * 86400
    private let lock = NSLock()
    private var mem: [String: DoubanRatingResult] = [:]
    private var diskLoaded = false
    private var disk: [String: Entry] = [:]

    private var diskURL: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let dir = base.appendingPathComponent("CineBar", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        return dir.appendingPathComponent("douban_cache.json")
    }

    func key(title: String, year: Int?) -> String {
        "\(title)|\(year.map(String.init) ?? "")"
    }

    /// 命中磁盘缓存（未过期）返回缓存结果；未命中返回 nil。
    func hit(_ key: String, now: Date = Date()) -> DoubanRatingResult? {
        lock.lock(); defer { lock.unlock() }
        if let m = mem[key] { return m }
        loadDiskLocked()
        guard let e = disk[key], now.timeIntervalSince(e.savedAt) < ttl else {
            return nil
        }
        let result = DoubanRatingResult(
            doubanID: e.subjectID,
            title: "",
            score: e.score,
            voteCount: e.count,
            pageURL: e.pageURL
        )
        mem[key] = result
        return result
    }

    /// 写入磁盘缓存。
    func store(_ key: String, _ result: DoubanRatingResult) {
        lock.lock(); defer { lock.unlock() }
        mem[key] = result
        loadDiskLocked()
        disk[key] = Entry(
            score: result.score,
            count: result.voteCount,
            subjectID: result.doubanID,
            pageURL: result.pageURL,
            savedAt: Date()
        )
        flushDiskLocked()
    }

    private func loadDiskLocked() {
        guard diskLoaded == false else { return }
        if let data = try? Data(contentsOf: diskURL),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            disk = decoded
        }
        diskLoaded = true
    }

    private func flushDiskLocked() {
        guard let data = try? JSONEncoder().encode(disk) else { return }
        try? data.write(to: diskURL, options: .atomic)
    }
}

// MARK: - 失败指数退避（方案 A 补充：被风控/必应失败后冷却，避免撞墙）

final class DoubanBackoff {
    static let shared = DoubanBackoff()

    private let lock = NSLock()
    private var cooldownUntil = Date.distantPast
    private var strikes = 0

    func isCooling() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return Date() < cooldownUntil
    }

    func recordFailure() {
        lock.lock(); defer { lock.unlock() }
        strikes = min(strikes + 1, 8)
        let wait = pow(2.0, Double(strikes)) * 60
        cooldownUntil = Date().addingTimeInterval(min(wait, 7200))
    }

    func recordSuccess() {
        lock.lock(); defer { lock.unlock() }
        strikes = max(strikes - 1, 0)
    }
}

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
/// minimumInterval 设为 5 秒：rexxar/必应实测 4 秒间隔仍偶发 403，5 秒稳妥。
actor DoubanSearchGate {
    static let shared = DoubanSearchGate()

    private var lastRequestAt = Date.distantPast
    private let minimumInterval: TimeInterval = 5.0

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

/// 豆瓣评分客户端。
///
/// 由于豆瓣把免登录的搜索接口（search.douban.com / movie.douban.com/j/*）
/// 全部加了风控（302→sec.douban.com→403），无法再直接搜索标题拿评分。
/// 现改用两步链路（均免登录、国内可访问、稳定）：
///  1) 必应站内搜 `site:movie.douban.com/subject <标题>`，从结果链接提取豆瓣 subjectID；
///  2) 豆瓣 rexxar 详情接口按 subjectID 返回当前评分（值常年稳定，接近快照）。
/// 不登录、不触发豆瓣风控。失败静默降级，不影响其他功能。
struct DoubanRatingClient {
    var session: URLSession = .shared

    private static let desktopUA =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
        + "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    private static let mobileUA =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) "
        + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 "
        + "Mobile/15E148 Safari/604.1"

    /// 搜索并返回匹配标题/年份的豆瓣评分。找不到返回 nil（不抛错，静默降级）。
    /// 顺序：磁盘缓存命中 → 退避冷却拦截 → 全局闸门串行节流 → 成功后写缓存。
    func search(
        title: String,
        year: Int?
    ) async throws -> DoubanRatingResult? {
        guard !Self.normalize(title).isEmpty else { return nil }

        let key = DoubanRatingCache.shared.key(title: title, year: year)
        if let cached = DoubanRatingCache.shared.hit(key) {
            return cached
        }
        guard !DoubanBackoff.shared.isCooling() else { return nil }

        let result: DoubanRatingResult? = try await DoubanSearchGate.shared.throttled {
            // 必应可能命中多个 subjectID：逐个校验年份，跳过同名异片。
            let subjectIDs = await self.bingSubjectIDs(title: title)
            guard !subjectIDs.isEmpty else {
                return nil
            }
            for subjectID in subjectIDs {
                guard let detail = await self.rexxarMovie(subjectID: subjectID),
                      let ratingValue = detail.ratingValue,
                      ratingValue > 0,
                      Self.matches(detail: detail, title: title, year: year) else {
                    continue
                }
                let pageURL = "https://movie.douban.com/subject/\(subjectID)/"
                return DoubanRatingResult(
                    doubanID: subjectID,
                    title: detail.title,
                    score: ratingValue,
                    voteCount: detail.ratingCount,
                    pageURL: pageURL
                )
            }
            return nil
        }
        if result == nil {
            // 搜索失败（必应空结果 / 详情失败 / 无匹配）：记一次退避增长
            DoubanBackoff.shared.recordFailure()
        } else {
            DoubanBackoff.shared.recordSuccess()
            DoubanRatingCache.shared.store(key, result!)
        }
        return result
    }

    /// 用豆瓣 rexxar 搜索接口查候选片单（电影），返回标题/年份/评分 文本块。
    /// 供 CineAI 的"候选资料"使用：豆瓣对中文片名匹配好，能覆盖 TMDB 搜不到的
    /// 老版本/冷门/未上映（如搜"蜘蛛侠"能列出 2002 托比版、新片等）。
    /// 一次请求返回多条，比逐条 bing+rexxar 高效。走全局闸门限流；失败返回空。
    func searchCandidates(_ query: String) async -> String {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty,
              let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return ""
        }
        guard let url = URL(string: "https://m.douban.com/rexxar/api/v2/search?type=movie&q=\(encoded)") else {
            return ""
        }
        let text: String = await (try? DoubanSearchGate.shared.throttled {
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            request.setValue(Self.mobileUA, forHTTPHeaderField: "User-Agent")
            request.setValue(
                "https://m.douban.com/movie/subject/",
                forHTTPHeaderField: "Referer"
            )
            let (data, response) = try await self.session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let s = String(data: data, encoding: .utf8) else { return "" }
            return s
        }) ?? ""

        // 解析 subjects.items[].target: title/year/rating.value/count
        var lines: [String] = []
        do {
            guard let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
                  let subjects = json["subjects"] as? [String: Any],
                  let items = subjects["items"] as? [[String: Any]] else {
                return ""
            }
            for item in items.prefix(8) {
                guard let target = item["target"] as? [String: Any],
                      let title = target["title"] as? String,
                      !title.isEmpty else { continue }
                var line = "《\(title)》"
                if let year = target["year"] as? Int { line += " (\(year))" }
                if let rating = target["rating"] as? [String: Any],
                   let value = rating["value"] as? Double, value > 0 {
                    line += String(format: " 豆瓣 %.1f", value)
                    if let count = rating["count"] as? Int { line += "/\(count)人" }
                }
                lines.append(line)
            }
        }
        return lines.joined(separator: "\n")
    }

    /// 标题→豆瓣 subjectID列表：扫必应站内搜结果里的 movie.douban.com/subject/数字。
    /// 返回全部候选项（去重、>0），由调用方逐个校验年份。
    private func bingSubjectIDs(title: String) async -> [Int] {
        let query = "site:movie.douban.com/subject \(title)"
        var components = URLComponents(
            string: "https://cn.bing.com/search"
        )
        components?.queryItems = [
            URLQueryItem(name: "q", value: query)
        ]
        guard let url = components?.url else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue(Self.desktopUA, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else {
            return []
        }
        let pattern = #"douban\.com/subject/(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let source = html as NSString
        let matches = regex.matches(
            in: html,
            range: NSRange(location: 0, length: source.length)
        )
        var seen = Set<Int>()
        var result: [Int] = []
        for m in matches where m.numberOfRanges > 1 {
            if let id = Int(source.substring(with: m.range(at: 1))),
               id > 0,
               !seen.contains(id) {
                seen.insert(id)
                result.append(id)
            }
        }
        return result
    }

    /// 豆瓣 subjectID → 详情（评分）。用 rexxar 接口，免登录、国内可访问。
    private func rexxarMovie(subjectID: Int) async -> RexxarDetail? {
        guard let url = URL(
            string: "https://m.douban.com/rexxar/api/v2/movie/\(subjectID)"
                + "?for_mobile=1"
        ) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue(Self.mobileUA, forHTTPHeaderField: "User-Agent")
        request.setValue(
            "https://m.douban.com/movie/subject/",
            forHTTPHeaderField: "Referer"
        )
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any] else {
            return nil
        }
        guard let rating = json["rating"] as? [String: Any] else {
            return nil
        }
        let title = json["title"] as? String ?? ""
        let year = RexxarDetail.year(from: json["card_subtitle"] as? String)
        let value = (rating["value"] as? NSNumber)?.doubleValue
        let count = (rating["count"] as? NSNumber)?.intValue
        return RexxarDetail(
            title: title,
            year: year,
            ratingValue: value,
            ratingCount: count
        )
    }

    /// 用标题和可选年份二次校验，避免必应匹配到同名异片（张冠李戴）。
    /// 标题：归一化后相等或互相包含；年份：给定时必须严格相等（防同名片误配）。
    private static func matches(
        detail: RexxarDetail,
        title: String,
        year: Int?
    ) -> Bool {
        let target = normalize(title)
        guard !target.isEmpty else { return false }
        let bean = normalize(detail.title)
        let matched = bean == target || bean.contains(target) || target.contains(bean)
        if let year, let detailYear = detail.year {
            return matched && detailYear == year
        }
        return matched
    }

    /// rexxar 详情里解析出的干净字段。
    private struct RexxarDetail {
        let title: String
        let year: Int?
        let ratingValue: Double?
        let ratingCount: Int?

        static func year(from subtitle: String?) -> Int? {
            guard let subtitle else { return nil }
            let years = subtitle.components(separatedBy: CharacterSet.letters.union(.whitespaces))
            for piece in years.reversed() {
                let digits = piece.filter { $0.isNumber }
                if digits.count == 4, let y = Int(digits), y > 1900, y < 2100 {
                    return y
                }
            }
            return nil
        }
    }

    /// 必应/豆瓣站内搜索结果里的候选条目。根据标题匹配+年份校验选出最佳项。
    /// 回归测试覆盖此方法；生产路径已改为逐条校验。
    static func match(
        items: [DoubanSearchItem],
        title: String,
        year: Int?
    ) -> DoubanRatingResult? {
        let normalized = normalize(title)
        guard !normalized.isEmpty else { return nil }

        func rank(_ item: DoubanSearchItem) -> Int? {
            guard item.rating?.value != nil else { return nil }
            let norm = normalize(item.title)
            guard !norm.isEmpty else { return nil }
            if norm == normalized {
                if let year { return abstractContains(item, year: year) ? 0 : 1 }
                return 0
            }
            if norm.contains(normalized) || normalized.contains(norm) {
                if let year { return abstractContains(item, year: year) ? 2 : 3 }
                return 2
            }
            return nil
        }

        let ranked = items.compactMap { item -> (item: DoubanSearchItem, rank: Int)? in
            guard let r = rank(item) else { return nil }
            return (item, r)
        }.sorted { $0.rank < $1.rank }

        guard let best = ranked.first else { return nil }
        return DoubanRatingResult(
            doubanID: best.item.id,
            title: best.item.title,
            score: best.item.rating?.value ?? 0,
            voteCount: best.item.rating?.count ?? nil,
            pageURL: "https://movie.douban.com/subject/\(best.item.id)/"
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