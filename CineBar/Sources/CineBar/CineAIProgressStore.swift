import Foundation

/// 一部剧的观影进度：记录"已看到哪一季哪一集"。
struct ShownProgress: Codable, Equatable {
    let seriesID: Int
    /// 这一季这一集（含）视为已看到。
    var seasonNumber: Int
    var episodeNumber: Int
    let updatedAt: Date

    /// 供展示：S03E05
    var code: String { String(format: "S%02dE%02d", seasonNumber, episodeNumber) }
}

/// CineAI 的本地进度 / 收藏 / 搜索历史 / 偏好标签存储。
/// 单 macOS 端用 UserDefaults + Codable 持久化（未来扩端再评估/改 CloudKit）。
///
/// 防剧透依据：
/// 记录某个 seriesID 的最新已看进度（SxxExx），RAG 层据此只取进度以内的剧集资料，
/// 不把之后的剧集资料交给 AI。
final class CineAIProgressStore {

    private let defaults: UserDefaults
    private let progressKey = "cineai.tv.progress"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - 剧集进度（观影进度，防剧透的核心）

    /// 某剧最新已看进度；没看过返回 nil。
    func progress(for seriesID: Int) -> ShownProgress? {
        all()[seriesID]
    }

    /// 记录（或推进）某剧进度：只有新进度 >= 旧进度才更新，防止倒退。
    func recordProgress(seriesID: Int, season: Int, episode: Int) {
        var map = all()
        if let old = map[seriesID],
           old.seasonNumber > season ||
           (old.seasonNumber == season && old.episodeNumber >= episode) {
            // 等或落后于已有进度，忽略倒退。
            return
        }
        map[seriesID] = ShownProgress(
            seriesID: seriesID,
            seasonNumber: season,
            episodeNumber: episode,
            updatedAt: Date()
        )
        persist(map)
    }

    /// 用户手动设置进度（允许任意设置，含回退）。
    func setProgress(seriesID: Int, season: Int, episode: Int) {
        var map = all()
        map[seriesID] = ShownProgress(
            seriesID: seriesID,
            seasonNumber: season,
            episodeNumber: episode,
            updatedAt: Date()
        )
        persist(map)
    }

    func removeProgress(seriesID: Int) {
        var map = all()
        map.removeValue(forKey: seriesID)
        persist(map)
    }

    private func all() -> [Int: ShownProgress] {
        guard let data = defaults.data(forKey: progressKey),
              let decoded = try? JSONDecoder().decode(
                  [Int: ShownProgress].self, from: data
              ) else {
            return [:]
        }
        return decoded
    }

    private func persist(_ map: [Int: ShownProgress]) {
        if let data = try? JSONEncoder().encode(map) {
            defaults.set(data, forKey: progressKey)
        }
    }
}
