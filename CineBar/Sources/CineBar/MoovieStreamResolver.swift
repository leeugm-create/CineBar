import Foundation

/// 一条弹幕：time 为视频内秒数，mode 0=滚动 / 1=顶部 / 2=底部。
struct DanmakuItem: Decodable, Equatable {
    let time: Double
    let text: String
    let mode: Int
    let color: String?
}

/// Moovie 影牛（moovie.c2v2.com）在线正片源解析器。
/// 站点是全网影视聚合搜索站，搜索接口返回多家资源源的播放页链接，
/// 播放页内嵌 HLS（m3u8）直链，可直接用 AVPlayer 播放正片。
/// 用法：search(title:year:) 拿候选源 → resolveStreamURL(playPath:) 提取 m3u8。
enum MoovieStreamResolver {
    static let siteBase = URL(string: "https://moovie.c2v2.com")!
    private static let timeout: TimeInterval = 15
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
        + "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    /// 一个候选正片源（播放页路径，如 /play/魔都资源/42998?douban_id=...）。
    struct StreamCandidate {
        let playPath: String
        let sourceName: String
        let title: String
        let year: String
        let doubanID: String

        /// 是否疑似衍生内容（电影解说/预告片/花絮等），正片优先应排除。
        var isDerivative: Bool {
            title.localizedCaseInsensitiveContains("解说")
                || title.localizedCaseInsensitiveContains("预告")
                || title.localizedCaseInsensitiveContains("花絮")
        }
    }

    /// 按片名+年份搜索可播放的正片源。
    /// 过滤掉标题不含搜索词的衍生片（如《星际穿越中的科学》），
    /// 并按「正片 > 解说/预告」与豆瓣映射优先排序。
    static func search(
        title: String,
        year: String?
    ) async -> [StreamCandidate] {
        guard !title.isEmpty else { return [] }
        let query = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var components = URLComponents(
            url: siteBase.appendingPathComponent("api/htmx/search"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "q", value: query)
        ]
        if let year, !year.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "year", value: year))
        }
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("true", forHTTPHeaderField: "HX-Request")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else {
            return []
        }
        return parseSearchResults(html: html, forTitle: query)
    }

    /// 从搜索接口返回的 HTML 解析候选源列表（离线纯函数，供测试）。
    /// 站点用中文标题展示，搜英文片名时 contains 必然全滤空，
    /// 因此标题过滤滤空时退化为弱过滤（只剔衍生片，保年份匹配）。
    static func parseSearchResults(
        html: String,
        forTitle query: String
    ) -> [StreamCandidate] {
        // 每个结果卡片 <a href="/play/...">…<h3 class="card-title">片名</h3>…<span class="card-year">年份</span>
        var results: [StreamCandidate] = []
        let pattern = #"href="(/play/[^"]+)"[^>]*class="search-result-card"[\s\S]*?card-title">([^<]+)</h3>[\s\S]*?card-year">([^<]+)<"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else { return [] }
        let ns = html as NSString
        let matches = regex.matches(
            in: html,
            range: NSRange(location: 0, length: ns.length)
        )
        for match in matches {
            let playPath = ns.substring(with: match.range(at: 1))
            let cardTitle = ns.substring(with: match.range(at: 2))
            let cardYear = ns.substring(with: match.range(at: 3))
            // /play/<源名>/<vodId>?douban_id=<id>（前导空串不能省略）
            let segments = playPath.split(
                separator: "/",
                omittingEmptySubsequences: false
            )
            guard segments.count >= 3 else { continue }
            let sourceName = String(segments[2])
                .removingPercentEncoding ?? String(segments[2])
            guard !sourceName.isEmpty else { continue }
            let doubanID = {
                if let qi = playPath.range(of: "douban_id=") {
                    let suffix = playPath[qi.upperBound...]
                    if let amp = suffix.firstIndex(of: "&") {
                        return String(suffix[..<amp])
                    }
                    return String(suffix)
                }
                return ""
            }()
            results.append(StreamCandidate(
                playPath: playPath,
                sourceName: sourceName,
                title: cardTitle,
                year: cardYear,
                doubanID: doubanID
            ))
        }

        let queryLower = query.lowercased()
        let titleMatches = results.filter {
            $0.title.lowercased().contains(queryLower)
        }
        let filtered = titleMatches.isEmpty
            ? results.filter { !$0.isDerivative }
            : titleMatches
        return filtered.sorted { a, b in
            let aExact = a.title.lowercased() == queryLower
            let bExact = b.title.lowercased() == queryLower
            if aExact != bExact { return aExact }
            if a.isDerivative != b.isDerivative { return !a.isDerivative }
            let aMapped = !a.doubanID.isEmpty && a.doubanID != "0"
            let bMapped = !b.doubanID.isEmpty && b.doubanID != "0"
            if aMapped != bMapped { return aMapped }
            return false
        }
    }

    /// 打开播放页并提取 HLS 直链。播放页内嵌
    /// initPlayer('artplayer-app', 'https:\/\/host\/...\/index.m3u8', {...})
    static func resolveStreamURL(playPath: String) async -> URL? {
        guard let url = URL(string: playPath, relativeTo: siteBase) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else {
            return nil
        }
        return extractStreamURL(from: html)
    }

    /// 探测一个 m3u8 直链的分片能否被拉到（客户端同环境，较准确）。
    /// 聚合站分片常带 .png 伪装/防盗链，分片可拉则该源浏览器/播放器大概率可播。
    /// 用于给"能播放的线路"优先排序。
    static func probePlayable(streamURL: URL) async -> Bool {
        var request = URLRequest(url: streamURL)
        request.timeoutInterval = 12
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let text = String(data: data, encoding: .utf8) else {
            return false
        }
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        var segmentURL: URL?
        for i in 0..<(lines.count - 1) where lines[i].hasPrefix("#EXTINF") {
            let seg = lines[i + 1]
            if !seg.isEmpty, !seg.hasPrefix("#") {
                segmentURL = URL(string: seg, relativeTo: streamURL)?.absoluteURL
                break
            }
        }
        guard let segmentURL else { return false }
        var segRequest = URLRequest(url: segmentURL)
        segRequest.timeoutInterval = 12
        segRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        segRequest.setValue("https://moovie.c2v2.com/", forHTTPHeaderField: "Referer")
        guard let (segData, segResponse) = try? await URLSession.shared.data(for: segRequest),
              (segResponse as? HTTPURLResponse)?.statusCode == 200 else {
            return false
        }
        // 分片返回纯文本 "404 ..." 视为防盗链失败。
        if segData.count < 16 { return false }
        return true
    }

    /// 从播放页 HTML 提取 m3u8 直链（离线纯函数，供测试）。
    static func extractStreamURL(from html: String) -> URL? {
        // initPlayer('artplayer-app', 'URL', { → URL 里斜杠被转义成 \/
        let pattern = #"initPlayer\('[^']*',\s*'((?:https?:)?\\?/\\?/[^']*)'"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = html as NSString
        guard let match = regex.firstMatch(
            in: html,
            range: NSRange(location: 0, length: ns.length)
        ) else { return nil }
        var raw = ns.substring(with: match.range(at: 1))
        raw = raw.replacingOccurrences(of: "\\/", with: "/")
        return URL(string: raw)
    }

    /// 依次尝试候选源，返回第一个成功解析出 m3u8 直链的（含来源名）。
    static func firstPlayable(
        candidates: [StreamCandidate]
    ) async -> (candidate: StreamCandidate, streamURL: URL)? {
        for candidate in candidates {
            if let url = await resolveStreamURL(playPath: candidate.playPath) {
                return (candidate, url)
            }
        }
        return nil
    }

    /// 一集电视剧的播放入口（播放页路径 + 展示名）。
    struct PlaybackEpisode: Identifiable, Hashable {
        var id: String { playPath }
        let label: String
        let playPath: String

        /// 从"第X集"文本提取数字（第36集完结 → 36），失败返回 nil。
        var numericOrder: Int? {
            let trimmed = label
                .replacingOccurrences(of: "完结", with: "")
                .trimmingCharacters(in: .whitespaces)
            let digits = trimmed.filter(\.isNumber)
            return Int(digits)
        }
    }

    /// 从播放页 HTML 提取剧集列表（离线纯函数，供测试）。
    /// 播放页内嵌 `var episodeList = [...]`，元素形如：
    /// { "title": "第01集", "url": "/play/源/id?source=..&ep=第01集&douban_id=.." }
    static func parseEpisodeList(from html: String) -> [PlaybackEpisode] {
        // 先精确提取 episodeList 数组文本，避免误匹配其它 JS 数组。
        guard let listRange = html.range(of: "episodeList = [") ??
                html.range(of: "episodeList=[") else { return [] }
        var scanIndex = listRange.upperBound
        var bracketDepth = 1
        while scanIndex < html.endIndex {
            let ch = html[scanIndex]
            if ch == "[" { bracketDepth += 1 }
            if ch == "]" {
                bracketDepth -= 1
                if bracketDepth == 0 { break }
            }
            scanIndex = html.index(after: scanIndex)
        }
        guard bracketDepth == 0 else { return [] }
        let listText = String(html[listRange.upperBound...scanIndex])

        var episodes: [PlaybackEpisode] = []
        // 站点 JS 用双引号 JSON 风格；兼容单引号 label 风格。
        let patterns = [
            #""title":\s*"([^"]+)",\s*"url":\s*"([^"]+)""#,
            #"'label':\s*'([^']*)'\s*,\s*'url':\s*'([^']*)'"#,
            #"label:\s*'([^']*)'\s*,\s*url:\s*'([^']*)'"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            let ns = listText as NSString
            let matches = regex.matches(
                in: listText,
                range: NSRange(location: 0, length: ns.length)
            )
            var seen = Set<String>()
            for match in matches {
                let label = ns.substring(with: match.range(at: 1))
                let path = ns.substring(with: match.range(at: 2))
                let decoded = path.replacingOccurrences(of: "\\/", with: "/")
                guard !label.isEmpty, !decoded.isEmpty else { continue }
                if seen.insert(decoded).inserted {
                    episodes.append(
                        PlaybackEpisode(label: label, playPath: decoded)
                    )
                }
            }
            if !episodes.isEmpty { break }
        }
        return episodes.sorted { a, b in
            let (na, nb) = (a.numericOrder, b.numericOrder)
            if let na, let nb, na != nb { return na < nb }
            return a.label < b.label
        }
    }

    /// 拉取播放页并解析剧集列表；失败返回空数组。
    static func loadEpisodes(playPath: String) async -> [PlaybackEpisode] {
        guard let url = URL(string: playPath, relativeTo: siteBase) else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else {
            return []
        }
        return parseEpisodeList(from: html)
    }

    /// 从片名提取季信息（"庆余年 第二季"→"第二季"，"Show S02"→"S02"）。
    /// 没有明确季标识时返回 nil。
    static func seasonLabel(from title: String) -> String? {
        let patterns = [
            #"第[一二三四五六七八九十0-9]+季"#,
            #"\bS\d{1,2}\b"#,
            #"\bSeason\s*\d{1,2}\b"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(
                   in: title,
                   range: NSRange(location: 0, length: (title as NSString).length)
               ) {
                return (title as NSString).substring(with: match.range)
            }
        }
        return nil
    }

    /// 把季标签解析为季号整数；无季标识或无法解析时返回 nil。
    /// "第二季"→2、"第十季"→10、"S02"/"S2"→2、"Season 3"→3。
    static func seasonNumber(from title: String) -> Int? {
        guard let label = seasonLabel(from: title) else { return nil }
        // S02 / S2 / Season 3 形式
        let asciiPattern = #"(\d+)"#
        if let regex = try? NSRegularExpression(pattern: asciiPattern),
           let match = regex.firstMatch(
               in: label,
               range: NSRange(location: 0, length: (label as NSString).length)
           ) {
            let digits = (label as NSString).substring(with: match.range)
            if let n = Int(digits), n > 0 { return n }
        }
        // 中文数字：第X季
        let cnDigits: [Character: Int] = [
            "一": 1, "二": 2, "三": 3, "四": 4, "五": 5,
            "六": 6, "七": 7, "八": 8, "九": 9
        ]
        let cn = ["十": 10, "二十": 20, "三十": 30]
        for (word, value) in cn {
            if label.contains(word) { return value }
        }
        for (ch, value) in cnDigits {
            if label.contains(ch) { return value }
        }
        return nil
    }

    /// 从播放页 HTML 提取正片片名（initPlayer 里的 vodName），供弹幕匹配。
    static func vodName(playPath: String) async -> String? {
        guard let url = URL(string: playPath, relativeTo: siteBase) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else {
            return nil
        }
        let pattern = #"vodName:\s*'([^']+)'"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = html as NSString
        guard let match = regex.firstMatch(
            in: html,
            range: NSRange(location: 0, length: ns.length)
        ) else { return nil }
        return ns.substring(with: match.range(at: 1))
    }

    /// 拉取某片的弹幕列表（moovie 弹幕接口，按片名+分集匹配）。
    /// 元素字段：time(秒)、text、mode(0滚动/1顶部/2底部)、color。
    static func loadDanmaku(
        title: String,
        episode: String? = nil
    ) async -> [DanmakuItem] {
        var components = URLComponents(
            url: siteBase.appendingPathComponent("api/danmaku"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "title", value: title)]
        if let episode, !episode.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "episode", value: episode))
        }
        guard let url = components.url else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let items = try? JSONDecoder().decode([DanmakuItem].self, from: data)
        else {
            return []
        }
        return items.filter { !$0.text.isEmpty }
    }

    /// 一个热门影视条目（discover 页卡片：标题 + 豆瓣评分 + 海报）。
    struct TrendingItem: Identifiable, Hashable {
        var id: String { doubanID }
        let title: String
        let doubanID: String
        /// 豆瓣评分文本（可能为空）。
        let ratingText: String
        /// 海报地址（站点图片代理，可直接下载）。
        let posterURL: URL?

        var rating: Double? {
            Double(ratingText)
        }
    }

    /// 拉取热门电影榜（/discover/movie，约 50 部）。
    static func trendingMovies() async -> [TrendingItem] {
        var components = URLComponents(
            url: siteBase.appendingPathComponent("discover/movie"),
            resolvingAgainstBaseURL: false
        )
        components?.port = 443
        guard let url = components?.url else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("true", forHTTPHeaderField: "HX-Request")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else {
            return []
        }
        return parseTrendingMovies(from: html)
    }

    /// 从热门榜 HTML 解析卡片（离线纯函数，供测试）。
    /// 卡片形如：
    /// <a href="/search?kw=<标题>&doubanId=<id>"><div class="movie-poster">
    /// <img src="/api/proxy/image/…" alt="标题">…<span class="movie-rating">7.6</span>
    /// …<h3 class="movie-title" title="标题">
    static func parseTrendingMovies(from html: String) -> [TrendingItem] {
        var items: [TrendingItem] = []
        let cardPattern = #"<a href="/search\?kw=([^"]+)&doubanId=(\d+)"[\s\S]*?<span class="movie-rating">([\d.]+)</span>[\s\S]*?<h3 class="movie-title" title="([^"]*)"#
        guard let regex = try? NSRegularExpression(
            pattern: cardPattern
        ) else { return [] }
        let ns = html as NSString
        let matches = regex.matches(
            in: html,
            range: NSRange(location: 0, length: ns.length)
        )
        var seen = Set<String>()
        for match in matches {
            let doubanID = ns.substring(with: match.range(at: 2))
            guard seen.insert(doubanID).inserted else { continue }
            let rating = ns.substring(with: match.range(at: 3))
            let title = ns.substring(with: match.range(at: 4))
            guard !title.isEmpty else { continue }
            let cardText = ns.substring(with: match.range)
            items.append(TrendingItem(
                title: title,
                doubanID: doubanID,
                ratingText: rating,
                posterURL: posterURL(in: cardText)
            ))
        }
        return items
    }

    /// 从单张卡片 HTML 提取海报代理地址（img src="/api/proxy/image/…"）。
    private static func posterURL(in cardHTML: String) -> URL? {
        let pattern = #"src="(/api/proxy/image/[^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let ns = cardHTML as NSString
        guard let match = regex.firstMatch(
            in: cardHTML,
            range: NSRange(location: 0, length: ns.length)
        ) else { return nil }
        let src = ns.substring(with: match.range(at: 1))
        return URL(string: src, relativeTo: siteBase)?.absoluteURL
    }
}

