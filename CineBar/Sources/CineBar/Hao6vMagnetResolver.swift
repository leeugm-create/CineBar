import Foundation

/// hao6v（6v电影网）磁力解析器：先抓"最新电影"列表页，用片名匹配条目，
/// 再进详情页提取 magnet 链接。站点搜索接口实测失效（任何关键词都返回
/// "没有搜索到相关内容"），因此只走列表匹配路径。
enum Hao6vMagnetResolver {
    static let siteHost = "www.hao6v.cc"
    private static let listURL = URL(string: "https://\(siteHost)/dy/")!
    private static let detailBaseURL = URL(string: "https://\(siteHost)")!
    private static let timeout: TimeInterval = 12

    /// 抓取单个条目的磁力链接。title 为影片主标题（不含年份/清晰度）。
    static func searchMagnet(for title: String, year: String? = nil) async -> String? {
        let list = await fetchLatestList()
        guard !list.isEmpty else { return nil }
        let candidates = matchCandidates(list: list, title: title, year: year)
        if candidates.isEmpty { return nil }
        for entry in candidates {
            if let magnet = await fetchMagnet(url: entry.url) {
                return magnet
            }
        }
        return nil
    }

    struct ListEntry {
        let url: URL
        let rawTitle: String
    }

    static func fetchLatestList() async -> [ListEntry] {
        guard let data = await fetchData(from: listURL) else { return [] }
        guard let html = decodeGB18030(data) else { return [] }
        return parseList(html: html)
    }

    static func parseList(html: String) -> [ListEntry] {
        // 形如 <a href="/dy/2026-08-07/50167.html" ...>2026动作科幻《最后孤屋》1080p.HD中英双字</a>
        let pattern = #"<a href="(/dy/\d{4}-\d{2}-\d{2}/\d+\.html)"[^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }
        let ns = html as NSString
        var result: [ListEntry] = []
        var seen = Set<String>()
        for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            guard match.numberOfRanges == 3 else { continue }
            let path = ns.substring(with: match.range(at: 1))
            let raw = ns.substring(with: match.range(at: 2))
            guard let url = URL(string: path, relativeTo: detailBaseURL) else { continue }
            let absURL = url.absoluteURL
            guard !seen.contains(absURL.absoluteString) else { continue }
            seen.insert(absURL.absoluteString)
            let title = stripHTMLTags(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            result.append(ListEntry(url: absURL, rawTitle: title))
        }
        return result
    }

    static func fetchMagnet(url: URL) async -> String? {
        let data = await HTTPData(url: url)
        guard let data, let html = decodeGB18030(data) else { return nil }
        return extractMagnet(html: html)
    }

    static func extractMagnet(html: String) -> String? {
        let pattern = #"magnet:\?[^\s"<&]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = html as NSString
        guard let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        var raw = ns.substring(with: match.range)
        raw = raw.replacingOccurrences(of: "&amp;", with: "&")
        return raw
    }

    /// 从列表标题里提取《片名》中文名，再与目标标题比对。
    private static func matchTitle(
        list: [ListEntry],
        title: String,
        year: String?
    ) -> [ListEntry] {
        let target = normalizeTitle(title)
        guard !target.isEmpty else { return [] }
        let targetYear = year.flatMap { Int($0) }
        var bump: [(entry: ListEntry, score: Int)] = []
        for entry in list {
            let curl = extractChineseTitle(from: entry.rawTitle)
            let clean = normalizeTitle(curl.isEmpty ? entry.rawTitle : curl)
            guard !clean.isEmpty else { continue }
            var score = 0
            if clean == target {
                score += 100
            } else if target.contains(clean) || clean.contains(target) {
                score += 40
            }
            let entryYear = extractYear(from: entry.rawTitle)
            if let targetYear = targetYear, let entryYear {
                if entryYear == targetYear { score += 20 }
                else if abs(entryYear - targetYear) <= 1 { score += 8 }
                else { score -= 30 }
            }
            if score > 0 {
                bump.append((entry, score))
            }
        }
        return bump.sorted { $0.score > $1.score }.map { $0.entry }
    }

    /// 从 "<2026动作科幻《最后孤屋》1080p.HD中英双字" 提取《》内片名。
    private static func extractChineseTitle(from raw: String) -> String {
        let pattern = #"《([^》]+)》"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return "" }
        let ns = raw as NSString
        guard let match = regex.firstMatch(in: raw, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1 else {
            return ""
        }
        return ns.substring(with: match.range(at: 1))
    }

    private static func extractYear(from raw: String) -> Int? {
        let pattern = #"\b(19|20)\d{2}\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = raw as NSString
        guard let match = regex.firstMatch(in: raw, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        return Int(ns.substring(with: match.range))
    }

    private static func normalizeTitle(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.lowercased()
    }

    /// 按 gb18030 解码网页（站点是 gb2312 老编码）。
    static func decodeGB18030(_ data: Data) -> String? {
        guard let enc = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )) else { return nil }
        return String(data: data, encoding: enc)
    }

    private static func stripHTMLTags(_ s: String) -> String {
        s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
    }

    private static func HTTPData(url: URL) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return data
        } catch {
            return nil
        }
    }
}