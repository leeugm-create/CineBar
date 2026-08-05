import AVFoundation
import Foundation

struct LocalLibraryScanRoot: Hashable {
    let folderID: UUID
    let url: URL?
    let bookmarkData: Data?
    let displayName: String

    init(folderID: UUID, url: URL, displayName: String) {
        self.folderID = folderID
        self.url = url
        self.bookmarkData = nil
        self.displayName = displayName
    }

    init(folderID: UUID, bookmarkData: Data, displayName: String) {
        self.folderID = folderID
        self.url = nil
        self.bookmarkData = bookmarkData
        self.displayName = displayName
    }
}

struct LocalLibraryScanProgress: Hashable {
    let folderID: UUID
    let displayName: String
    let filesVisited: Int
    let mediaFilesFound: Int
}

struct LocalLibraryScanResult: Hashable {
    let entries: [LocalLibraryEntry]
    let availableFolderIDs: Set<UUID>
    let unavailableFolderIDs: Set<UUID>
    let staleFolderIDs: Set<UUID>
    let wasCancelled: Bool

    init(
        entries: [LocalLibraryEntry],
        availableFolderIDs: Set<UUID>,
        unavailableFolderIDs: Set<UUID>,
        staleFolderIDs: Set<UUID> = [],
        wasCancelled: Bool
    ) {
        self.entries = entries
        self.availableFolderIDs = availableFolderIDs
        self.unavailableFolderIDs = unavailableFolderIDs
        self.staleFolderIDs = staleFolderIDs
        self.wasCancelled = wasCancelled
    }
}

final class LocalLibraryScanner {
    private static let supportedExtensions: Set<String> = [
        "mp4", "m4v", "mov", "mkv", "avi", "webm", "ts", "m2ts"
    ]

    func scan(
        roots: [LocalLibraryScanRoot],
        existing: [LocalLibraryEntry],
        progress: @escaping @Sendable (LocalLibraryScanProgress) -> Void
    ) async -> LocalLibraryScanResult {
        await withTaskGroup(of: LocalLibraryScanResult.self) { group in
            group.addTask(priority: .utility) {
                Self.scanSynchronously(
                    roots: roots,
                    existing: existing,
                    progress: progress
                )
            }
            return await group.next()!
        }
    }

    private static func scanSynchronously(
        roots: [LocalLibraryScanRoot],
        existing: [LocalLibraryEntry],
        progress: @escaping @Sendable (LocalLibraryScanProgress) -> Void
    ) -> LocalLibraryScanResult {
        let fileManager = FileManager.default
        var entriesByKey: [String: LocalLibraryEntry] = [:]
        var availableFolderIDs = Set<UUID>()
        var unavailableFolderIDs = Set<UUID>()
        var staleFolderIDs = Set<UUID>()
        var wasCancelled = false
        var scopedFolders: [LocalLibraryResolvedFolder] = []
        defer {
            scopedFolders.forEach { $0.stopAccessing() }
        }

        for root in roots {
            if Task.isCancelled {
                wasCancelled = true
                break
            }

            let rootURL: URL
            if let bookmarkData = root.bookmarkData {
                guard let resolvedFolder = try? LocalLibraryFolderBookmark
                    .resolve(bookmarkData) else {
                    unavailableFolderIDs.insert(root.folderID)
                    continue
                }
                scopedFolders.append(resolvedFolder)
                if resolvedFolder.isStale {
                    staleFolderIDs.insert(root.folderID)
                }
                rootURL = resolvedFolder.url.standardizedFileURL
            } else if let url = root.url {
                rootURL = url.standardizedFileURL
            } else {
                unavailableFolderIDs.insert(root.folderID)
                continue
            }

            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(
                atPath: rootURL.path,
                isDirectory: &isDirectory
            ), isDirectory.boolValue else {
                unavailableFolderIDs.insert(root.folderID)
                progress(LocalLibraryScanProgress(
                    folderID: root.folderID,
                    displayName: root.displayName,
                    filesVisited: 0,
                    mediaFilesFound: 0
                ))
                continue
            }

            availableFolderIDs.insert(root.folderID)
            var filesVisited = 0
            var mediaFilesFound = 0
            let properties: Set<URLResourceKey> = [
                .isRegularFileKey,
                .fileSizeKey,
                .contentModificationDateKey,
                .fileResourceIdentifierKey
            ]
            let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: Array(properties),
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )

            while let fileURL = enumerator?.nextObject() as? URL {
                if Task.isCancelled {
                    wasCancelled = true
                    break
                }
                filesVisited += 1
                guard let values = try? fileURL.resourceValues(
                    forKeys: properties
                ), values.isRegularFile == true else {
                    continue
                }
                let fileExtension = fileURL.pathExtension.lowercased()
                guard supportedExtensions.contains(fileExtension) else {
                    continue
                }

                let relativePath = relativePath(of: fileURL, from: rootURL)
                let signature = LocalLibraryFileSignature(
                    fileName: fileURL.lastPathComponent,
                    fileExtension: fileExtension,
                    byteCount: Int64(values.fileSize ?? 0),
                    modificationDate: values.contentModificationDate,
                    resourceIdentifier: values.fileResourceIdentifier.map {
                        String(describing: $0)
                    }
                )
                // 方案C：文件名优先，无法判定时读取时长兜底
                let existing = existingEntry(
                    in: existing,
                    folderID: root.folderID,
                    relativePath: relativePath
                )
                let fileName = fileURL.lastPathComponent
                var duration = existing?.durationSeconds
                let classifierDecision: LocalLibraryMediaDecision
                if LocalLibraryClassifier.confidence(fromFilename: fileName) == .decisive {
                    classifierDecision = LocalLibraryClassifier.classify(fromFilename: fileName)
                } else {
                    let byteCount = Int64(values.fileSize ?? 0)
                    // 小文件在合理码率下几乎不可能满足 1 小时影片底线，跳过网络/磁盘时长读取，
                    // 缺省按 other 处理，避免为海量小片段付出读时长的开销。
                    let shouldReadDuration = duration == nil && byteCount >= 300_000_000
                    if shouldReadDuration {
                        duration = Self.readDuration(from: fileURL)
                    }
                    classifierDecision = LocalLibraryClassifier.classify(
                        fileName: fileName,
                        physical: LocalLibraryPhysicalSignal(
                            byteCount: byteCount,
                            durationSeconds: duration
                        )
                    )
                }
                let contentCategory: LocalLibraryContentCategory
                let matchState: LocalLibraryMatchState
                switch classifierDecision {
                case .movie:
                    contentCategory = .movie
                    matchState = .suggested
                case .television:
                    contentCategory = .television
                    matchState = .suggested
                case .other:
                    contentCategory = .other
                    matchState = .unmatched
                }
                let entry = LocalLibraryEntry(
                    id: existing?.id ?? UUID(),
                    folderID: root.folderID,
                    relativePath: relativePath,
                    signature: signature,
                    state: .available,
                    matchState: matchState,
                    metadata: nil,
                    isWatched: false,
                    isInWatchlist: false,
                    lastOpenedAt: nil,
                    contentCategory: contentCategory,
                    durationSeconds: duration
                )
                entriesByKey[LocalLibraryEntryMerge.key(
                    folderID: root.folderID,
                    relativePath: relativePath
                )] = entry
                mediaFilesFound += 1
                progress(LocalLibraryScanProgress(
                    folderID: root.folderID,
                    displayName: root.displayName,
                    filesVisited: filesVisited,
                    mediaFilesFound: mediaFilesFound
                ))
            }
            if wasCancelled { break }
        }

        return LocalLibraryScanResult(
            entries: entriesByKey.values.sorted {
                LocalLibraryEntryMerge.key(
                    folderID: $0.folderID,
                    relativePath: $0.relativePath
                ) < LocalLibraryEntryMerge.key(
                    folderID: $1.folderID,
                    relativePath: $1.relativePath
                )
            },
            availableFolderIDs: availableFolderIDs,
            unavailableFolderIDs: unavailableFolderIDs,
            staleFolderIDs: staleFolderIDs,
            wasCancelled: wasCancelled
        )
    }

    /// 读取视频时长（秒）。失败/异常返回 nil。
    /// 仅在文件名无法判定时调用，避免为每个文件支付 AVAsset 开销。
    private static func readDuration(from fileURL: URL) -> Double? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let asset = AVURLAsset(url: fileURL)
        let semaphore = DispatchSemaphore(value: 0)
        var duration: Double?
        let task = Task(priority: .utility) {
            let seconds = try? await asset.load(.duration)
            duration = seconds.map { CMTimeGetSeconds($0) }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 60)
        task.cancel()
        guard let value = duration, value.isFinite, value > 0 else { return nil }
        return value
    }

    private static func existingEntry(
        in entries: [LocalLibraryEntry],
        folderID: UUID,
        relativePath: String
    ) -> LocalLibraryEntry? {        let key = LocalLibraryEntryMerge.key(
            folderID: folderID,
            relativePath: relativePath
        )
        return entries.first {
            LocalLibraryEntryMerge.key(
                folderID: $0.folderID,
                relativePath: $0.relativePath
            ) == key
        }
    }

    private static func relativePath(of fileURL: URL, from rootURL: URL) -> String {
        let rootComponents = rootURL.pathComponents
        let fileComponents = fileURL.standardizedFileURL.pathComponents
        return fileComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }
}

enum LocalLibraryRefreshMerger {
    static func merge(
        existing: [LocalLibraryEntry],
        scanned: LocalLibraryScanResult,
        roots: [LocalLibraryScanRoot]
    ) -> [LocalLibraryEntry] {
        var existingByKey: [String: LocalLibraryEntry] = [:]
        var existingByID: [UUID: LocalLibraryEntry] = [:]
        for entry in existing {
            let key = LocalLibraryEntryMerge.key(
                folderID: entry.folderID,
                relativePath: entry.relativePath
            )
            if existingByKey[key] == nil {
                existingByKey[key] = entry
            }
            existingByID[entry.id] = entry
        }

        var mergedByKey: [String: LocalLibraryEntry] = [:]
        for scannedEntry in scanned.entries {
            let key = LocalLibraryEntryMerge.key(
                folderID: scannedEntry.folderID,
                relativePath: scannedEntry.relativePath
            )
            if let currentEntry = existingByID[scannedEntry.id] {
                let currentKey = LocalLibraryEntryMerge.key(
                    folderID: currentEntry.folderID,
                    relativePath: currentEntry.relativePath
                )
                if currentKey != key {
                    existingByKey.removeValue(forKey: currentKey)
                    mergedByKey[currentKey] = currentEntry
                    continue
                }
            }
            if let oldEntry = existingByKey.removeValue(forKey: key) {
                var updatedEntry = oldEntry
                updatedEntry.relativePath = scannedEntry.relativePath
                updatedEntry.signature = scannedEntry.signature
                updatedEntry.state = .available
                updatedEntry.durationSeconds = scannedEntry.durationSeconds
                if oldEntry.metadata == nil,
                   oldEntry.matchState != .confirmed {
                    updatedEntry.contentCategory = scannedEntry.contentCategory
                    updatedEntry.matchState = scannedEntry.matchState
                }
                mergedByKey[key] = updatedEntry
            } else {
                mergedByKey[key] = scannedEntry
            }
        }

        let knownFolderIDs = Set(roots.map(\.folderID))
        for (key, entry) in existingByKey {
            guard knownFolderIDs.contains(entry.folderID) else {
                mergedByKey[key] = entry
                continue
            }
            guard !scanned.wasCancelled else {
                mergedByKey[key] = entry
                continue
            }
            var unavailableEntry = entry
            if scanned.unavailableFolderIDs.contains(entry.folderID) {
                unavailableEntry.state = .volumeUnavailable
            } else if scanned.availableFolderIDs.contains(entry.folderID) {
                unavailableEntry.state = .missing
            }
            mergedByKey[key] = unavailableEntry
        }

        return mergedByKey.values.sorted {
            LocalLibraryEntryMerge.key(
                folderID: $0.folderID,
                relativePath: $0.relativePath
            ) < LocalLibraryEntryMerge.key(
                folderID: $1.folderID,
                relativePath: $1.relativePath
            )
        }
    }
}
