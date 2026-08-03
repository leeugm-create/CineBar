import AppKit
import Foundation

enum ExternalPlayerKind: Equatable {
    case iina
    case vlc
    case system

    fileprivate var bundleID: String? {
        switch self {
        case .iina: return "com.colliderli.iina"
        case .vlc: return "org.videolan.vlc"
        case .system: return nil
        }
    }
}

enum ExternalPlayerResolver {
    static func resolve(availableBundleIDs: some Sequence<String>) -> [ExternalPlayerKind] {
        let available = Set(availableBundleIDs)
        var players: [ExternalPlayerKind] = []
        if available.contains("com.colliderli.iina") {
            players.append(.iina)
        }
        if available.contains("org.videolan.vlc") {
            players.append(.vlc)
        }
        players.append(.system)
        return players
    }
}

struct ExternalPlayerLauncher {
    private let applicationURLForBundleID: (String) -> URL?
    private let openWithApplication: ([URL], URL) -> Bool
    private let openSystem: (URL) -> Bool

    init(
        applicationURLForBundleID: @escaping (String) -> URL? = {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        },
        openWithApplication: @escaping ([URL], URL) -> Bool = { urls, applicationURL in
            NSWorkspace.shared.open(
                urls,
                withApplicationAt: applicationURL,
                configuration: NSWorkspace.OpenConfiguration()
            )
            return true
        },
        openSystem: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) {
        self.applicationURLForBundleID = applicationURLForBundleID
        self.openWithApplication = openWithApplication
        self.openSystem = openSystem
    }

    @discardableResult
    func open(fileURL: URL) -> Bool {
        guard fileURL.isFileURL else { return false }
        let localFileURL = fileURL.standardizedFileURL
        let availableBundleIDs: [String] = [
            ExternalPlayerKind.iina, .vlc
        ].compactMap {
            guard let bundleID = $0.bundleID,
                  applicationURLForBundleID(bundleID) != nil
            else { return nil }
            return bundleID
        }

        for player in ExternalPlayerResolver.resolve(
            availableBundleIDs: availableBundleIDs
        ) {
            switch player {
            case .iina, .vlc:
                guard let bundleID = player.bundleID,
                      let applicationURL = applicationURLForBundleID(bundleID)
                else { continue }
                if openWithApplication([localFileURL], applicationURL) {
                    return true
                }
            case .system:
                if openSystem(localFileURL) {
                    return true
                }
            }
        }
        return false
    }
}
