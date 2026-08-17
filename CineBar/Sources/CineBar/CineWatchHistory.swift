import Foundation

/// 本地观影记录（2026-08-18 新增，对标网页端「上次观看」）：
/// 播放过的影片/剧集存 UserDefaults，顶栏「观影记录」面板大海报展示，点击续播。
/// 纯本地存储，不注册、不上传。

struct WatchHistoryEntry: Codable, Identifiable, Equatable {
    var id: String { key }
    /// 唯一键：`movie:<标题>:<年份>` 或 `tv:<标题>:<年份>`。
    let key: String
    var type: String
    var title: String
    var year: String
    var posterURL: String?
    /// 播放源标签（如 "量子"、"Moovie"）。
    var sourceLabel: String
    var currentTime: Double
    var duration: Double
    var updatedAt: Double
}

enum CineWatchHistory {
    private static let storageKey = "cinebar.watch.history"
    private static let maxItems = 12
    /// 少于 5 秒的观看不记录（误点不算）。
    private static let minSeconds = 5.0
    /// 距片尾不足 20 秒视为看完，清掉记录。
    private static let endThreshold = 20.0

    /// 按更新时间倒序的全部记录。
    static func load() -> [WatchHistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
        guard let items = try? JSONDecoder().decode([WatchHistoryEntry].self, from: data) else { return [] }
        return items.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// 更新一条记录：同 key 覆盖并置顶，总量封顶；距片尾不足 20 秒视为看完清除。
    static func record(_ entry: WatchHistoryEntry) {
        guard entry.duration.isFinite, entry.duration > 0 else { return }
        if entry.duration - entry.currentTime < endThreshold {
            remove(key: entry.key)
            return
        }
        var items = load().filter { $0.key != entry.key }
        items.insert(entry, at: 0)
        save(Array(items.prefix(maxItems)))
    }

    static func remove(key: String) {
        save(load().filter { $0.key != key })
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    /// 节流：距上次写入超过 5 秒才落盘。
    static func shouldWrite(lastWriteAt: Double, now: Double) -> Bool {
        now - lastWriteAt >= 5
    }

    private static func save(_ items: [WatchHistoryEntry]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
