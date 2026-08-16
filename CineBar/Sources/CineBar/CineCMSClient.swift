import Foundation

/// 苹果CMS（MacCMS）资源站聚合客户端。
/// 与 zip0.com 背后同类的影视资源站直接对接（标准 MacCMS 公开接口），
/// 用于补齐 Moovie 影牛覆盖不到的短板：短剧、动漫全集、同名多版本、冷门片。
///
/// 标准接口（所有源通用）：
///   GET {base}/api.php/provide/vod/?ac=detail&wd=片名   → 搜索
///   GET {base}/api.php/provide/vod/?ac=list&pg=N        → 全量列表（含最新更新）
/// 返回 JSON：{ code, total, list: [{ vod_id, vod_name, vod_year, vod_pic,
///   type_name, vod_play_url, vod_remarks, vod_time, ... }] }
/// vod_play_url 形如 "第01集$https://...m3u8#第02集$https://...m3u8"。
///
/// 域名 2026-08-16 实测可用；资源站常换域名，失效时更新 sources。
enum CineCMSClient {
    /// 一条已实测可用的资源站（对齐 zip0 的线路标识）。
    struct CMSource {
        let id: String
        let name: String
        let base: URL
    }

    /// 资源站清单：量子/暴风/最大/急速/非凡。
    static let sources: [CMSource] = [
        CMSource(id: "lzi", name: "量子", base: URL(string: "https://cj.lziapi.com")!),
        CMSource(id: "bfzy", name: "暴风", base: URL(string: "https://bfzyapi.com")!),
        CMSource(id: "zuid", name: "最大", base: URL(string: "https://zuidazy.com")!),
        CMSource(id: "jisu", name: "急速", base: URL(string: "https://jisuzy.com")!),
        CMSource(id: "ffzy", name: "非凡", base: URL(string: "https://ffzy5.tv")!),
    ]

    private static let timeout: TimeInterval = 12
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
        + "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    /// 一个资源站条目（对应 MacCMS 的 vod 字段）。
    struct CMSTitle: Decodable {
        let source: String
        let sourceName: String
        let id: String
        let title: String
        let year: String
        let poster: String?
        let category: String
        let playURL: String
        let remarks: String

        /// 总集数（由 vod_play_url 的 # 分段数推导）。
        var episodeCount: Int {
            let parts = playURL.split(separator: "#").map(String.init).filter { !$0.isEmpty }
            return parts.isEmpty ? 0 : parts.count
        }

        /// 是否为短剧（短剧更新快、命名随意，单独归类展示）。
        var isShortDrama: Bool {
            category.contains("短剧")
        }

        /// 是否为动漫（日韩/国产/欧美动漫统一归入）。
        var isAnime: Bool {
            category.contains("动漫")
        }
    }

    /// 并发搜索全部资源站，返回合并结果（每源前 6 条，总量封顶 30 条）。
    static func searchAll(title: String) async -> [CMSTitle] {
        let query = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        let batches = await withTaskGroup(
            of: [CMSTitle].self,
            returning: [[CMSTitle]].self
        ) { group in
            for source in sources {
                group.addTask {
                    await search(source: source, title: query)
                }
            }
            var collected: [[CMSTitle]] = []
            for await batch in group {
                collected.append(batch)
            }
            return collected
        }
        var merged: [CMSTitle] = []
        for batch in batches {
            merged.append(contentsOf: batch)
        }
        // 稳定排序：精确片名优先，其次短剧/动漫靠前（补齐 Moovie 短板），
        // 同源内保持返回顺序。
        let q = query.lowercased()
        return merged
            .enumerated()
            .sorted { a, b in
                let (ia, ta) = a
                let (ib, tb) = b
                let aExact = ta.title.lowercased() == q ? 1 : 0
                let bExact = tb.title.lowercased() == q ? 1 : 0
                if aExact != bExact { return bExact < aExact }
                let aCover = (ta.isShortDrama || ta.isAnime) ? 1 : 0
                let bCover = (tb.isShortDrama || tb.isAnime) ? 1 : 0
                if aCover != bCover { return bCover < aCover }
                return ia < ib
            }
            .map(\.element)
            .prefix(30)
            .map { $0 }
    }

    /// 在单个资源站搜索。
    static func search(source: CMSource, title: String) async -> [CMSTitle] {
        var components = URLComponents(
            url: source.base.appendingPathComponent("api.php/provide/vod/"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "ac", value: "detail"),
            URLQueryItem(name: "wd", value: title),
        ]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return []
            }
            let payload = try JSONDecoder().decode(CMSListPayload.self, from: data)
            guard payload.code == 1 else { return [] }
            return payload.list
                .prefix(6)
                .map { v in
                    CMSTitle(
                        source: source.id,
                        sourceName: source.name,
                        id: stringID(v.vod_id),
                        title: v.vod_name ?? "",
                        year: v.vod_year ?? "",
                        poster: v.vod_pic,
                        category: v.type_name ?? "",
                        playURL: v.vod_play_url ?? "",
                        remarks: v.vod_remarks ?? ""
                    )
                }
        } catch {
            return []
        }
    }

    /// 从 vod_play_url 提取指定集的 m3u8 直链（默认第 1 集）。
    static func streamURL(playURL: String, episode: Int = 1) -> URL? {
        let parts = playURL.split(separator: "#").map(String.init).filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        let index = min(max(episode, 1), parts.count) - 1
        let target = parts[index]
        let dollarIndex = target.firstIndex(of: "$")
        let raw: String
        if let dollarIndex {
            raw = String(target[target.index(after: dollarIndex)...]).trimmingCharacters(in: .whitespaces)
        } else {
            raw = target.trimmingCharacters(in: .whitespaces)
        }
        guard !raw.isEmpty, let url = URL(string: raw), url.scheme != nil else { return nil }
        return url
    }

    /// 探测直链是否可播（对标 MoovieStreamResolver.probePlayable）。
    /// 部分源需要 Referer 才能取到分片，探测时带本站域名更接近真实播放环境。
    static func probePlayable(streamURL: URL, sourceBase: URL?) async -> Bool {
        var request = URLRequest(url: streamURL)
        request.timeoutInterval = timeout
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let sourceBase {
            request.setValue(sourceBase.absoluteString, forHTTPHeaderField: "Referer")
        }
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            // 直播/点播 m3u8 一般 200；4xx/5xx 视为不可播。
            return http.statusCode >= 200 && http.statusCode < 400
        } catch {
            return false
        }
    }

    /// 便捷入口：按片名并发搜索全部源，返回第一个带可播直链的结果。
    /// 供「在线播放」按钮回退链调用（Moovie 无结果时使用）。
    static func firstPlayable(title: String) async -> (title: CMSTitle, url: URL)? {
        let results = await searchAll(title: title)
        for t in results {
            guard let url = streamURL(playURL: t.playURL, episode: 1) else { continue }
            let base = sources.first { $0.id == t.source }?.base
            if await probePlayable(streamURL: url, sourceBase: base) {
                return (t, url)
            }
        }
        return nil
    }

    /// 解码负载（MacCMS 标准 JSON 外壳）。
    private struct CMSListPayload: Decodable {
        let code: Int?
        let list: [CMSVod]
    }

    private struct CMSVod: Decodable {
        let vod_id: Int?
        let vod_name: String?
        let vod_year: String?
        let vod_pic: String?
        let type_name: String?
        let vod_play_url: String?
        let vod_remarks: String?
    }

    private static func stringID(_ value: Int?) -> String {
        guard let value else { return "" }
        return String(value)
    }
}
