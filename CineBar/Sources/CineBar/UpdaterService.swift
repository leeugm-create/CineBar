import Foundation

enum UpdatePolicy {
    static let feedURL = "https://cinebar.cc/appcast.xml"
    static let automaticChecksDefaultsKey = "SUEnableAutomaticChecks"
}

#if !CINEBAR_TEST
import Sparkle

@MainActor
final class UpdaterService {
    static let shared = UpdaterService()

    private let controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
#endif
