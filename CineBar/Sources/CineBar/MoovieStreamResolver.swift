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
            URLQueryItem(name: "kw", value: query)
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
}
