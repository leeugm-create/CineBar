import Foundation

enum UpdatePolicy {
    static let feedURL = "https://cinebar.cc/appcast.xml"
    static let automaticChecksDefaultsKey = "SUEnableAutomaticChecks"
    static let legacyAutomaticChecksDefaultsKey =
        "automaticallyChecksForUpdates"

    static func automaticChecksMigrationValue(
        legacyValue: Bool?,
        hasExistingSparkleValue: Bool
    ) -> Bool? {
        guard !hasExistingSparkleValue else { return nil }
        return legacyValue
    }

    static func migrateAutomaticChecks(
        defaults: UserDefaults = .standard
    ) {
        let value = automaticChecksMigrationValue(
            legacyValue: defaults.object(
                forKey: legacyAutomaticChecksDefaultsKey
            ) as? Bool,
            hasExistingSparkleValue: defaults.object(
                forKey: automaticChecksDefaultsKey
            ) != nil
        )
        if let value {
            defaults.set(value, forKey: automaticChecksDefaultsKey)
        }
    }
}

#if !CINEBAR_TEST
import Combine
import Sparkle

@MainActor
final class UpdaterService: ObservableObject {
    static let shared = UpdaterService()

    private let controller: SPUStandardUpdaterController
    private var canCheckForUpdatesObservation: NSKeyValueObservation?
    private var finalizationTask: Task<Void, Never>?
    @Published private(set) var canCheckForUpdates = false
    /// 存在可安装的新版本（菜单栏蓝点提示）。
    @Published private(set) var hasUpdateAvailable = false

    private init(defaults: UserDefaults = .standard) {
        UpdatePolicy.migrateAutomaticChecks(defaults: defaults)
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        canCheckForUpdatesObservation = controller.updater.observe(
            \.canCheckForUpdates,
            options: [.initial, .new]
        ) { [weak self] _, change in
            Task { @MainActor [weak self] in
                self?.canCheckForUpdates = change.newValue ?? false
            }
        }
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// 静默拉取 appcast 判断是否有可用更新，仅在二进制安装后才启动。
    func startSilentUpdateChecks() {
        guard finalizationTask == nil else { return }
        finalizationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshUpdateAvailability()
                try? await Task.sleep(nanoseconds: 30 * 60 * 1_000_000_000)
            }
        }
    }

    func refreshUpdateAvailability() async {
        guard let url = URL(string: UpdatePolicy.feedURL) else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            guard let xml = String(data: data, encoding: .utf8) else { return }
            let buildNumbers = Self.latestBuildNumbers(from: xml)
            guard let latest = buildNumbers.max() else { return }
            let installed = Int(
                Bundle.main.object(
                    forInfoDictionaryKey: "CFBundleVersion"
                ) as? String ?? "0"
            ) ?? 0
            hasUpdateAvailable = latest > installed
        } catch {
            // 网络不可用时保持现状，下一个周期再试。
        }
    }

    /// 从 appcast XML 提取所有 sparkle:version 构建号。
    static func latestBuildNumbers(from xml: String) -> [Int] {
        let pattern = #"sparkle:version="(\d+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let source = xml as NSString
        let matches = regex.matches(
            in: xml,
            range: NSRange(location: 0, length: source.length)
        )
        return matches.compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            let value = source.substring(with: match.range(at: 1))
            return Int(value)
        }
    }
}
#endif
