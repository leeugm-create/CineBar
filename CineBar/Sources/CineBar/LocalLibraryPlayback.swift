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
    private let openWithApplication: ([URL], URL) async -> Bool
    private let openSystem: (URL) -> Bool

    init(
        applicationURLForBundleID: @escaping (String) -> URL? = {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        },
        openWithApplication: @escaping ([URL], URL) async -> Bool = {
            urls, applicationURL in
            await Self.openAndObserve(urls, with: applicationURL)
        },
        openSystem: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) {
        self.applicationURLForBundleID = applicationURLForBundleID
        self.openWithApplication = openWithApplication
        self.openSystem = openSystem
    }

    @discardableResult
    func open(fileURL: URL) async -> Bool {
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
                if await openWithApplication([localFileURL], applicationURL) {
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

    private static func openAndObserve(
        _ fileURLs: [URL],
        with applicationURL: URL
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            let outcome = ExternalPlayerOpenOutcome(continuation: continuation)
            NSWorkspace.shared.open(
                fileURLs,
                withApplicationAt: applicationURL,
                configuration: NSWorkspace.OpenConfiguration()
            ) { application, error in
                outcome.complete(application != nil && error == nil)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                outcome.complete(false)
            }
        }
    }
}

private final class ExternalPlayerOpenOutcome: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?

    init(continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func complete(_ result: Bool) {
        lock.lock()
        let pendingContinuation = continuation
        continuation = nil
        lock.unlock()
        pendingContinuation?.resume(returning: result)
    }
}
