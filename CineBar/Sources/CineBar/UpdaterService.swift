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
    @Published private(set) var canCheckForUpdates = false

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
}
#endif
