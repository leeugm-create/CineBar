import Foundation

/// hao6v（6v电影网）磁力解析器。站点搜索接口实测全部失效（任何关键词都
/// 返回"没有搜索到相关内容"），因此全量走"分类列表页 + 详情页"扫描链路。
/// 抓到的磁力统一写入 Hao6vMagnetStore 落盘，绝不重复请求已入库条目。
enum Hao6vMagnetResolver {
    static let siteHost = "www.hao6v.cc"
    private static let siteBase = URL(string: "https://\(siteHost)")!
    private static let timeout: TimeInterval = 12

    /// 全站分类（path, 展示名），顺序固定，扫描依次翻页直到空页/404。
    static let categories: [(path: String, label: String)] = [
        ("dy", "电影"),
        ("gydy", "国语配音"),
        ("zydy", "动漫新番"),
        ("gq", "经典高清"),
        ("jddy", "动画电影"),
        ("3D", "3D电影"),
        ("rj", "日韩剧"),
        ("mj", "欧美剧"),
        ("dlz", "国剧"),
        ("zy", "综艺"),
    ]

    struct ListEntry {
        let url: URL
        let rawTitle: String
    }

    static func categoryURL(path: String, page: Int) -> URL {
        guard page > 1 else {
            return URL(string: "https://\(siteHost)/\(path)/")!
        }
        return URL(string: "https://\(siteHost)/\(path)/index_\(page).html")!
    }

    // MARK: - 查询（本地库优先）

    /// 按标题查磁力。先查磁盘库；未命中则在线扫一遍全部分类最新页兜底并入库。
    static func magnetFor(title: String, year: String?) async -> String? {
        if let hit = matchLocal(title: title) {
            return hit.magnet
        }
        for cat in categories {
            let items = await fetchListPage(path: cat.path, page: 1)
            if let entry = matchCurrent(items, title: title, year: year),
               let magnet = await fetchMagnet(url: entry.url) {
                Hao6vMagnetStore.shared.merge(newEntries: [
                    Hao6vMagnetStore.Entry(
                        rawTitle: entry.rawTitle,
                        magnet: magnet,
                        scrapedAt: Date()
                    )
                ])
                return magnet
            }
        }
        return nil
    }

    private static func matchLocal(title: String) -> Hao6vMagnetStore.Entry? {
        guard !title.isEmpty else { return nil }
        let chinese = extractChineseStrict(from: title)
        var best: (entry: Hao6vMagnetStore.Entry, score: Int)?
        for entry in Hao6vMagnetStore.shared.allEntries() {
            let entryName = extractChineseStrict(from: entry.rawTitle)
            let clean = entryName.isEmpty ? entry.rawTitle : entryName
            let n1 = normalize(title)
            let n2 = normalize(clean)
            let n3 = normalize(chinese)
            var score = 0
            if n2 == n1 || n2 == n3 { score = 100 }
            else if n1.contains(n2) || n2.contains(n1)
                        || (n3.count > 1 && (n3.contains(n2) || n2.contains(n3))) {
                score = 40
            } else {
                continue
            }
            if best == nil || score > best!.score {
                best = (entry, score)
            }
        }
        return best?.entry
    }

    /// 在当前列表条目里找最匹配的。
    private static func matchCurrent(
        _ items: [ListEntry],
        title: String,
        year: String?
    ) -> ListEntry? {
        let chinese = extractChineseStrict(from: title)
        let n1 = normalize(chinese.isEmpty ? title : chinese)
        let targetYear = year.flatMap { Int($0) }
        var best: (entry: ListEntry, score: Int)?
        for item in items {
            let cleanName = extractChineseStrict(from: item.rawTitle)
            let clean = cleanName.isEmpty ? item.rawTitle : cleanName
            let n2 = normalize(clean)
            var score = 0
            if n2 == n1 { score = 100 }
            else if n1.contains(n2) || n2.contains(n1) {
                score = 40
            } else {
                continue
            }
            if let ty = targetYear, let ey = yearOf(item.rawTitle) {
                if ty == ey { score += 20 }
                else if abs(ty - ey) <= 1 { score += 8 }
            }
            if best == nil || score > best!.score {
                best = (item, score)
            }
        }
        return best?.entry
    }

    // MARK: - 建库扫描

    /// 全站扫描建库：枚举全部分类的全部分页（直到页面为空），逐个抓详情磁力入
    /// 库。progress 回调 (完成的页数, 总页数, 当前分类标签)。
    static func scanIndex(progress: ((Int, Int, String) -> Void)? = nil) async {
        var pages: [(cat: String, url: URL)] = []
        for cat in categories {
            var page = 1
            while true {
                if Task.isCancelled { return }
                let url = categoryURL(path: cat.path, page: page)
                let items = await fetchListPage(url: url)
                if items.isEmpty { break }
                pages.append((cat.path, url))
                page += 1
                if page > 100 { break }
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
        }
        let total = pages.count
        var done = 0
        for (cat, url) in pages {
            if Task.isCancelled { return }
            let items = await fetchListPage(url: url)
            var batch: [Hao6vMagnetStore.Entry] = []
            for entry in items {
                if Task.isCancelled { return }
                let key = normalize(entry.rawTitle)
                if Hao6vMagnetStore.shared.allEntries().contains(
                    where: { normalize($0.rawTitle) == key }
                ) {
                    continue
                }
                if let magnet = await fetchMagnet(url: entry.url) {
                    batch.append(Hao6vMagnetStore.Entry(
                        rawTitle: entry.rawTitle,
                        magnet: magnet,
                        scrapedAt: Date()
                    ))
                }
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
            if !batch.isEmpty {
                Hao6vMagnetStore.shared.merge(newEntries: batch)
            }
            done += 1
            progress?(done, total, cat)
        }
    }

    /// 启动增量：全部分类最新一页入库，只抓新增。
    static func refreshLatest() async {
        for cat in categories {
            if Task.isCancelled { return }
            let items = await fetchListPage(path: cat.path, page: 1)
            var batch: [Hao6vMagnetStore.Entry] = []
            for item in items {
                let key = normalize(item.rawTitle)
                if Hao6vMagnetStore.shared.allEntries().contains(
                    where: { normalize($0.rawTitle) == key }
                ) {
                    continue
                }
                if let magnet = await fetchMagnet(url: item.url) {
                    batch.append(Hao6vMagnetStore.Entry(
                        rawTitle: item.rawTitle,
                        magnet: magnet,
                        scrapedAt: Date()
                    ))
                }
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
            if !batch.isEmpty {
                Hao6vMagnetStore.shared.merge(newEntries: batch)
            }
        }
    }

    // MARK: - 页面解析

    static func fetchListPage(path: String, page: Int) async -> [ListEntry] {
        await fetchListPage(url: categoryURL(path: path, page: page))
    }

    static func fetchListPage(url: URL) async -> [ListEntry] {
        guard let data = await httpData(url: url) else { return [] }
        guard let html = decodeGB18030(data) else { return [] }
        return parseList(html: html)
    }

    static func parseList(html: String) -> [ListEntry] {
        // 形如 <a href="/分类/2026-08-07/50167.html" ...>标题</a>
        let pattern = #"<a href="(/[a-z0-9]+/\d{4}-\d{2}-\d{2}/\d+\.html)"[^>]*>(.*?)</a>"#
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
            guard let url = URL(string: path, relativeTo: siteBase) else { continue }
            let absURL = url.absoluteURL
            guard !seen.contains(absURL.absoluteString) else { continue }
            seen.insert(absURL.absoluteString)
            let title = stripHTML(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            // 过滤公告/榜单/帮助等非影片条目
            let noise = ["公告", "榜单", "排行榜", "帮助", "教程", "留言"]
            if noise.contains(where: { title.contains($0) }) {
                continue
            }
            result.append(ListEntry(url: absURL, rawTitle: title))
        }
        return result
    }

    static func fetchMagnet(url: URL) async -> String? {
        guard let data = await httpData(url: url),
              let html = decodeGB18030(data) else {
            return nil
        }
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

    // MARK: - 标题工具

    /// 从 "2026动作科幻《最后孤屋》1080p.HD中英双字" 提取《》内片名。
    static func extractChineseStrict(from raw: String) -> String {
        let pattern = #"《([^》]+)》"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return "" }
        let ns = raw as NSString
        guard let match = regex.firstMatch(in: raw, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1 else {
            return ""
        }
        return ns.substring(with: match.range(at: 1))
    }

    private static func yearOf(_ raw: String) -> Int? {
        let pattern = #"\b(19|20)\d{2}\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = raw as NSString
        guard let match = regex.firstMatch(in: raw, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        return Int(ns.substring(with: match.range))
    }

    private static func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// 按 gb18030 解码网页（站点是 gb2312 老编码）。
    static func decodeGB18030(_ data: Data) -> String? {
        let cfEncoding = CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        let enc = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        )
        return String(data: data, encoding: enc)
    }

    private static func stripHTML(_ s: String) -> String {
        s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
    }

    // MARK: - 网络

    private static func httpData(url: URL) async -> Data? {
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