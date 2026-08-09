import Foundation

/// 磁力链接磁盘索引：抓取到的 6v 磁力永久保存，重复查询不再请求网站。
/// 键为站内的完整列表标题（含《》与年份），值为 magnet 链接。漏洞本就只
/// 存编号、原始标题、磁力与抓取时间，匹配由调用方做。
final class Hao6vMagnetStore {
    static let shared = Hao6vMagnetStore()

    struct Entry: Codable {
        var rawTitle: String
        var magnet: String
        var scrapedAt: Date
        /// 条目在站内的发布日期（YYYY-MM-DD，来自列表 URL 路径），用于增量抓取。
        var publishDate: String? = nil
    }

    private struct Persisted: Codable {
        var entries: [Entry]
        var lastUpdated: Date
        /// 上次全量抓取覆盖到的最大站内发布日期（YYYY-MM-DD）。nil 表示从未全量抓过。
        var lastFullDate: String? = nil
    }

    private var entries: [Entry] = []
    private(set) var lastUpdated: Date = .distantPast
    private var lastFullDateString: String?
    private var loaded = false
    private let lock = NSLock()

    private static var fileURL: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("CineBar", isDirectory: true)
            .appendingPathComponent("Hao6vMagnetIndex.json")
    }

    private func ensureLoaded() {
        guard !loaded else { return }
        loaded = true
        if let data = try? Data(contentsOf: Self.fileURL),
           let persisted = try? JSONDecoder().decode(Persisted.self, from: data) {
            entries = persisted.entries
            lastUpdated = persisted.lastUpdated
            lastFullDateString = persisted.lastFullDate
            return
        }
        // 首次启动：从应用内置的初始索引导入，新用户无需先全站抓取。
        if let data = try? Data(contentsOf: Self.bundledIndexURL()),
           let persisted = try? JSONDecoder().decode(Persisted.self, from: data),
           !persisted.entries.isEmpty {
            entries = persisted.entries
            lastUpdated = persisted.lastUpdated
            lastFullDateString = persisted.lastFullDate
            saveLocked()
        }
    }

    /// 应用包内置的初始索引（打包时由脚本从本机全量库生成）。
    private static func bundledIndexURL() -> URL {
        return Bundle.main.url(
            forResource: "InitialHao6vMagnetIndex",
            withExtension: "json"
        ) ?? URL(fileURLWithPath: "InitialHao6vMagnetIndex.json")
    }

    /// 全部藏品。返回拷贝以防并发修改。
    func allEntries() -> [Entry] {
        lock.lock()
        defer { lock.unlock() }
        ensureLoaded()
        return entries
    }

    func count() -> Int {
        lock.lock()
        defer { lock.unlock() }
        ensureLoaded()
        return entries.count
    }

    func lastUpdatedDate() -> Date {
        lock.lock()
        defer { lock.unlock() }
        ensureLoaded()
        return lastUpdated
    }

    /// 上次全量抓取覆盖到的最大日期（YYYY-MM-DD）。
    func lastFullDate() -> String? {
        lock.lock()
        defer { lock.unlock() }
        ensureLoaded()
        return lastFullDateString
    }

    /// 批量新增/覆盖条目并落盘。
    func merge(newEntries: [Entry]) {
        lock.lock()
        defer { lock.unlock() }
        ensureLoaded()
        var byTitle: [String: Entry] = [:]
        for e in entries { byTitle[e.rawTitle] = e }
        for e in newEntries { byTitle[e.rawTitle] = e }
        entries = Array(byTitle.values)
            .sorted { $0.rawTitle < $1.rawTitle }
        lastUpdated = Date()
        saveLocked()
    }

    /// 更新全量抓取水位线并落盘。
    func setFullDate(_ date: String?) {
        lock.lock()
        defer { lock.unlock() }
        ensureLoaded()
        lastFullDateString = date
        saveLocked()
    }

    private func saveLocked() {
        let payload = Persisted(
            entries: entries,
            lastUpdated: lastUpdated,
            lastFullDate: lastFullDateString
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        let dir = Self.fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}