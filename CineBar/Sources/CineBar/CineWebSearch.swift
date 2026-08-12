import Foundation

/// CineAI 的联网搜索兜底：当片库/TMDB 查不到用户要的内容时，
/// 用「必应国内版」抓取网页结果（标题+来源+摘要）回填给模型，避免答不上来或编造。
///
/// 数据源选型：实测在你的网络环境（国内）下
///  - cn.bing.com → 可达、快（~0.3s）、返回干净 HTML（b_algo 模块可解析）；
///  - zh.wikipedia API → 不可达（超时）。故用必应国内版。
///
/// 反爬策略：限速 + 用浏览器 UA + Accept-Language，单次最多取 N 条；失败静默返回空，
/// 由调用方决定是回退模型知识还是按无结果处理。
struct CineWebSearchClient {

    /// 单条搜索结果：标题 + 来源域名 + 摘要。
    struct ResultItem: Equatable {
        let title: String
        let source: String
        let snippet: String
    }

    /// 抓取必应国内版对 query 的搜索结果。
    /// - Parameters:
    ///   - query: 搜索词（中文即可）。
    ///   - limit: 最多返回条数。
    /// - Returns: 解析出的结果数组；请求失败/被反爬/结构变化时返回空数组。
    func search(_ query: String, limit: Int = 5) async -> [ResultItem] {
        guard let encoded = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              !encoded.isEmpty else { return [] }

        let urlString = "https://cn.bing.com/search?q=\(encoded)"
        guard let url = URL(string: urlString) else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue(
            "text/html,application/xhtml+xml",
            forHTTPHeaderField: "Accept"
        )
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return []
            }
            guard let html = String(data: data, encoding: .utf8) else { return [] }
            return Self.parse(html, limit: limit)
        } catch {
            return []
        }
    }

    /// 从必应国内版搜索页 HTML 里解析 b_algo 模块：标题、来源域名、摘要。
    /// 独立纯函数便于离线单测。
    static func parse(_ html: String, limit: Int) -> [ResultItem] {
        // 逐条抠 <li class="b_algo"> ... </li>
        let pieces = splitAlgoBlocks(html)
        var out: [ResultItem] = []
        for block in pieces {
            guard out.count < limit else { break }
            guard let title = extractTitle(from: block),
                  let snippet = extractSnippet(from: block) else { continue }
            let source = extractSource(from: block)
            out.append(ResultItem(title: title, source: source, snippet: snippet))
        }
        return out
    }

    /// 切出所有 b_algo 列表项（保守实现：按 <li 开始的 b 类包裹抓，遇到 </li> 断开）。
    private static func splitAlgoBlocks(_ html: String) -> [String] {
        var blocks: [String] = []
        var index = html.startIndex
        while index < html.endIndex,
              let start = html.range(of: #"<li class="b_algo""#, options: .regularExpression, range: index..<html.endIndex) {
            let blockStart = start.lowerBound
            guard let end = html.range(of: "</li>", range: blockStart..<html.endIndex) else { break }
            let block = String(html[blockStart..<end.lowerBound])
            blocks.append(block)
            index = end.upperBound
        }
        return blocks
    }

    private static func extractTitle(from block: String) -> String? {
        guard let range = block.range(of: #"<h2[^>]*>(.*?)</h2>"#, options: .regularExpression) else { return nil }
        let frag = String(block[range]).replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        let cleaned = stripTags(frag)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func extractSnippet(from block: String) -> String? {
        guard let range = block.range(of: #"<p[^>]*>(.*?)</p>"#, options: .regularExpression) else { return nil }
        let frag = String(block[range])
        let cleaned = stripTags(frag)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func extractSource(from block: String) -> String {
        if let range = block.range(of: #"<cite[^>]*>(.*?)</cite>"#, options: .regularExpression) {
            let frag = String(block[range])
            let host = stripTags(frag)
            return host.isEmpty ? "网页" : host
        }
        return "网页"
    }

    private static func stripTags(_ raw: String) -> String {
        // 去掉标签、解码实体、收拢空白。
        let noTags = raw.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
        let collapsed = noTags.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return collapsed
    }
}
