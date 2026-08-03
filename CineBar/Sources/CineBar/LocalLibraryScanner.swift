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
                let entry = LocalLibraryEntry(
                    id: existingEntry(
                        in: existing,
                        folderID: root.folderID,
                        relativePath: relativePath
                    )?.id ?? UUID(),
                    folderID: root.folderID,
                    relativePath: relativePath,
                    signature: signature,
                    state: .available,
                    matchState: .unmatched,
                    metadata: nil,
                    isWatched: false,
                    isInWatchlist: false,
                    lastOpenedAt: nil
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

    private static func existingEntry(
        in entries: [LocalLibraryEntry],
        folderID: UUID,
        relativePath: String
    ) -> LocalLibraryEntry? {
        let key = LocalLibraryEntryMerge.key(
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
