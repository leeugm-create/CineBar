import Foundation

/// 电视直播客户端：拉取 GitHub 开源源 best-fan/iptv-sources（国内直播源，每日自动构建）
/// 的频道列表。经 CineBar worker 的 GET /api/iptv 中转（服务端多镜像兜底 + D1 缓存 6 小时），
/// App 直接拿到分组 JSON，避免直连 GitHub raw 的稳定性问题。
///
/// 接口返回结构：
///   { "groups": [{ "name": "央视频道", "channels": [
///       { "name": "CCTV-1", "logo": "...", "url": "http://...m3u8",
///         "group": "央视频道", "responseTime": "120ms" } ] }],
///     "total": 423, "updatedAt": 1234567890 }
///
/// 直播流本身是标准 HLS（m3u8 live），直接喂给现有 AVPlayer（MooviePlayerView）即可播放，
/// AVPlayer 原生支持直播流。
enum CineBarIPTVClient {
    struct Channel: Codable, Identifiable, Hashable {
        let name: String
        let logo: String?
        let url: String
        let group: String
        let responseTime: String

        var id: String { "\(group)|\(name)|\(url)" }

        var streamURL: URL? {
            URL(string: url)
        }
    }

    struct IPTVGroup: Codable, Identifiable, Hashable {
        let name: String
        let channels: [Channel]

        var id: String { name }
    }

    private struct Response: Codable {
        let groups: [IPTVGroup]
        let total: Int
    }

    /// worker 中转端点（服务端已有 ghproxy 镜像兜底 + D1 缓存，App 端无需再处理源失效）。
    private static let endpoint = URL(string: "https://cinebar.cc/api/iptv")!
    private static let timeout: TimeInterval = 20

    /// 拉取分组频道列表。失败时抛出 URLError，调用方负责展示错误与重试。
    static func fetchGroups() async throws -> [IPTVGroup] {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = timeout
        request.setValue("CineBar/0.9.0 (macOS)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        // 服务端已按 URL 去重；这里再兜底一层，防止历史缓存里的重复频道。
        var seen = Set<String>()
        var normalized: [String: IPTVGroup] = [:]
        for group in decoded.groups {
            let name = Self.normalizedGroupName(group.name)
            let unique = group.channels.filter { seen.insert($0.url).inserted }
            if let existing = normalized[name] {
                var merged = existing
                merged = IPTVGroup(name: name, channels: existing.channels + unique)
                normalized[name] = merged
            } else {
                normalized[name] = IPTVGroup(name: name, channels: unique)
            }
        }
        // 央视优先、卫视其次，其余按名称排序，让侧边栏稳定。
        return normalized.values.sorted { lhs, rhs in
            let l = lhs.name == "央视频道" ? 0 : (lhs.name == "卫视频道" ? 1 : 2)
            let r = rhs.name == "央视频道" ? 0 : (rhs.name == "卫视频道" ? 1 : 2)
            if l != r { return l < r }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// 源里分组名不统一（央视台/央视频道、其他/其他频道），归一成固定集合。
    private static func normalizedGroupName(_ raw: String) -> String {
        switch raw {
        case "央视台": return "央视频道"
        case "其他频道": return "其他"
        default: return raw
        }
    }
}
