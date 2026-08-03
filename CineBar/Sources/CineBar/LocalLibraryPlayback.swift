import AppKit
import Foundation

enum ExternalPlayerKind: Equatable, Hashable {
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

enum ExternalPlayerFailureReason: Equatable, Hashable {
    case notInstalled
    case launchFailed
    case timedOut
    case systemRejected
}

struct ExternalPlayerFailure: Equatable, Hashable {
    let player: ExternalPlayerKind
    let reason: ExternalPlayerFailureReason
    let detail: String?
}

enum ExternalPlayerAttemptResult: Equatable {
    case success
    case failure(ExternalPlayerFailureReason, String?)
}

enum ExternalPlayerLaunchResult: Equatable {
    case opened(ExternalPlayerKind)
    case failed([ExternalPlayerFailure])
    case invalidFileURL
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
    private let openWithApplication: ([URL], URL) async -> ExternalPlayerAttemptResult
    private let openSystem: (URL) -> ExternalPlayerAttemptResult

    init(
        applicationURLForBundleID: @escaping (String) -> URL? = {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        },
        openWithApplication: @escaping ([URL], URL) async -> ExternalPlayerAttemptResult = {
            urls, applicationURL in
            await Self.openAndObserve(urls, with: applicationURL)
        },
        openSystem: @escaping (URL) -> ExternalPlayerAttemptResult = {
            NSWorkspace.shared.open($0)
                ? .success
                : .failure(.systemRejected, nil)
        }
    ) {
        self.applicationURLForBundleID = applicationURLForBundleID
        self.openWithApplication = openWithApplication
        self.openSystem = openSystem
    }

    func open(fileURL: URL) async -> ExternalPlayerLaunchResult {
        guard fileURL.isFileURL else { return .invalidFileURL }
        let localFileURL = fileURL.standardizedFileURL
        var failures: [ExternalPlayerFailure] = []

        for player in [ExternalPlayerKind.iina, .vlc] {
            guard let bundleID = player.bundleID,
                  let applicationURL = applicationURLForBundleID(bundleID)
            else {
                failures.append(ExternalPlayerFailure(
                    player: player,
                    reason: .notInstalled,
                    detail: nil
                ))
                continue
            }
            switch await openWithApplication([localFileURL], applicationURL) {
            case .success:
                return .opened(player)
            case let .failure(reason, detail):
                failures.append(ExternalPlayerFailure(
                    player: player,
                    reason: reason,
                    detail: detail
                ))
            }
        }

        switch openSystem(localFileURL) {
        case .success:
            return .opened(.system)
        case let .failure(reason, detail):
            failures.append(ExternalPlayerFailure(
                player: .system,
                reason: reason,
                detail: detail
            ))
            return .failed(failures)
        }
    }

    private static func openAndObserve(
        _ fileURLs: [URL],
        with applicationURL: URL
    ) async -> ExternalPlayerAttemptResult {
        await withCheckedContinuation { continuation in
            let outcome = ExternalPlayerOpenOutcome(continuation: continuation)
            NSWorkspace.shared.open(
                fileURLs,
                withApplicationAt: applicationURL,
                configuration: NSWorkspace.OpenConfiguration()
            ) { application, error in
                if let error {
                    outcome.complete(.failure(
                        .launchFailed,
                        error.localizedDescription
                    ))
                } else if application != nil {
                    outcome.complete(.success)
                } else {
                    outcome.complete(.failure(.launchFailed, nil))
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                outcome.complete(.failure(.timedOut, nil))
            }
        }
    }
}

private final class ExternalPlayerOpenOutcome: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ExternalPlayerAttemptResult, Never>?

    init(
        continuation: CheckedContinuation<ExternalPlayerAttemptResult, Never>
    ) {
        self.continuation = continuation
    }

    func complete(_ result: ExternalPlayerAttemptResult) {
        lock.lock()
        let pendingContinuation = continuation
        continuation = nil
        lock.unlock()
        pendingContinuation?.resume(returning: result)
    }
}
