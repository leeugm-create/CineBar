import Combine
import Foundation

typealias LocalLibraryScanOperation = (
    [LocalLibraryScanRoot],
    [LocalLibraryEntry],
    @escaping @Sendable (LocalLibraryScanProgress) -> Void
) async -> LocalLibraryScanResult

enum LocalLibraryStoreMessage: Hashable {
    case selectedFolderRemoved
    case folderAuthorizationStale
    case refreshCancelled
    case saveFailed
    case selectedEntryRemoved
}

@MainActor
final class LocalLibraryStore: ObservableObject {
    @Published private(set) var folders: [LocalLibraryFolder]
    @Published private(set) var entries: [LocalLibraryEntry]
    @Published private(set) var isScanning = false
    @Published private(set) var scanProgress: LocalLibraryScanProgress?
    @Published private(set) var message: LocalLibraryStoreMessage?

    private let persistence: LocalLibraryPersistence
    private let scanOperation: LocalLibraryScanOperation

    init(
        fileURL: URL? = nil,
        scanOperation: @escaping LocalLibraryScanOperation = { roots, existing, progress in
            await LocalLibraryScanner().scan(
                roots: roots,
                existing: existing,
                progress: progress
            )
        }
    ) {
        persistence = LocalLibraryPersistence(fileURL: fileURL)
        self.scanOperation = scanOperation
        let snapshot = persistence.load()
        folders = snapshot.folders
        entries = snapshot.entries
    }

    func addFolder(url: URL) throws {
        let standardizedURL = url.standardizedFileURL
        let bookmark = try LocalLibraryFolderBookmark.make(from: standardizedURL)
        if let existingIndex = matchingFolderIndex(at: standardizedURL) {
            var updatedFolders = folders
            updatedFolders[existingIndex].displayName = standardizedURL.lastPathComponent
            updatedFolders[existingIndex].pathHint = bookmark.pathHint
            updatedFolders[existingIndex].bookmarkData = bookmark.bookmarkData
            try persistence.save(LocalLibrarySnapshot(
                folders: updatedFolders,
                entries: entries
            ))
            folders = updatedFolders
            message = nil
            return
        }
        let folder = LocalLibraryFolder(
            id: UUID(),
            displayName: standardizedURL.lastPathComponent,
            pathHint: bookmark.pathHint,
            bookmarkData: bookmark.bookmarkData
        )
        let updatedFolders = folders + [folder]
        try persistence.save(LocalLibrarySnapshot(
            folders: updatedFolders,
            entries: entries
        ))
        folders = updatedFolders
        message = nil
    }

    func refresh() async {
        await refresh(folderIDs: Set(folders.map(\.id)))
    }

    func refresh(folderID: UUID) async {
        guard folders.contains(where: { $0.id == folderID }) else {
            message = .selectedFolderRemoved
            return
        }
        await refresh(folderIDs: [folderID])
    }

    func reattach(entryID: UUID, url: URL) throws {
        guard let entryIndex = entries.firstIndex(where: { $0.id == entryID }) else {
            throw LocalLibraryStoreError.entryNotFound
        }
        let fileURL = url.standardizedFileURL
        let oldEntry = entries[entryIndex]
        try Self.withAuthorizedFolderScope(
            folders: folders,
            containing: fileURL
        ) { folder, resolvedFolder in
            let fileSignature = try signature(for: fileURL)
            guard oldEntry.signature.matchesForReattachment(fileSignature) else {
                throw LocalLibraryStoreError.signatureMismatch
            }

            let rootComponents = resolvedFolder.url.standardizedFileURL.pathComponents
            let relativePath = fileURL.pathComponents
                .dropFirst(rootComponents.count)
                .joined(separator: "/")
            var updatedEntries = entries
            updatedEntries[entryIndex].folderID = folder.id
            updatedEntries[entryIndex].relativePath = relativePath
            updatedEntries[entryIndex].signature = fileSignature
            updatedEntries[entryIndex].state = .available
            try persistence.save(LocalLibrarySnapshot(
                folders: folders,
                entries: updatedEntries
            ))
            entries = updatedEntries
            message = nil
        }
    }

    func setWatched(entryID: UUID, value: Bool) {
        mutateEntry(entryID) { $0.isWatched = value }
    }

    func toggleWatchlist(entryID: UUID) {
        mutateEntry(entryID) { $0.isInWatchlist.toggle() }
    }

    func markOpened(entryID: UUID) {
        mutateEntry(entryID) { $0.lastOpenedAt = Date() }
    }

    @discardableResult
    func recordPlayback(
        result: ExternalPlayerLaunchResult,
        entryID: UUID
    ) -> Bool {
        guard case .opened = result else { return false }
        markOpened(entryID: entryID)
        return true
    }

    func updateMetadata(entryID: UUID, metadata: LocalLibraryMetadata?) {
        mutateEntry(entryID) {
            $0.metadata = metadata
            $0.matchState = metadata == nil ? .unmatched : .confirmed
            if let metadata {
                $0.contentCategory = metadata.kind == .movie
                    ? .movie
                    : .television
            }
        }
    }

    func confirmMatch(entryID: UUID, metadata: LocalLibraryMetadata) {
        mutateEntry(entryID) {
            $0.metadata = metadata
            $0.matchState = .confirmed
            $0.contentCategory = metadata.kind == .movie
                ? .movie
                : .television
        }
    }

    private func refresh(folderIDs: Set<UUID>) async {
        guard !isScanning else { return }
        let roots = folders.compactMap { folder -> LocalLibraryScanRoot? in
            guard folderIDs.contains(folder.id) else { return nil }
            return LocalLibraryScanRoot(
                folderID: folder.id,
                bookmarkData: folder.bookmarkData,
                displayName: folder.displayName
            )
        }
        guard !roots.isEmpty else { return }

        isScanning = true
        scanProgress = nil
        message = nil
        let existingEntries = entries
        let result = await scanOperation(
            roots,
            existingEntries,
            { [weak self] progress in
                Task { @MainActor in self?.scanProgress = progress }
            }
        )
        let mergedEntries = LocalLibraryRefreshMerger.merge(
            existing: entries,
            scanned: result,
            roots: roots
        )
        do {
            try persistence.save(LocalLibrarySnapshot(
                folders: folders,
                entries: mergedEntries
            ))
            entries = mergedEntries
            if !result.staleFolderIDs.isEmpty {
                message = .folderAuthorizationStale
            } else if result.wasCancelled {
                message = .refreshCancelled
            }
        } catch {
            message = .saveFailed
        }
        isScanning = false
    }

    private func mutateEntry(
        _ entryID: UUID,
        mutation: (inout LocalLibraryEntry) -> Void
    ) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else {
            message = .selectedEntryRemoved
            return
        }
        var updatedEntries = entries
        mutation(&updatedEntries[index])
        do {
            try persistence.save(LocalLibrarySnapshot(
                folders: folders,
                entries: updatedEntries
            ))
            entries = updatedEntries
            message = nil
        } catch {
            message = .saveFailed
        }
    }

    private func matchingFolderIndex(at url: URL) -> Int? {
        folders.firstIndex { folder in
            guard let resolved = try? LocalLibraryFolderBookmark.resolve(
                folder.bookmarkData
            ) else { return false }
            defer { resolved.stopAccessing() }
            return resolved.url.standardizedFileURL == url
        }
    }

    static func withAuthorizedFolderScope<Result>(
        folders: [LocalLibraryFolder],
        containing fileURL: URL,
        operation: (LocalLibraryFolder, LocalLibraryResolvedFolder) throws -> Result
    ) throws -> Result {
        for folder in folders {
            guard let resolved = try? LocalLibraryFolderBookmark.resolve(
                folder.bookmarkData
            ) else { continue }
            let rootURL = resolved.url.standardizedFileURL
            let rootComponents = rootURL.pathComponents
            let fileComponents = fileURL.pathComponents
            guard fileComponents.starts(with: rootComponents),
                  fileComponents.count > rootComponents.count else {
                resolved.stopAccessing()
                continue
            }
            defer { resolved.stopAccessing() }
            return try operation(folder, resolved)
        }
        throw LocalLibraryStoreError.fileOutsideAuthorizedFolders
    }

    private func signature(for fileURL: URL) throws -> LocalLibraryFileSignature {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .fileResourceIdentifierKey
        ]
        let values = try fileURL.resourceValues(forKeys: keys)
        guard values.isRegularFile == true else {
            throw LocalLibraryStoreError.notAFile
        }
        return LocalLibraryFileSignature(
            fileName: fileURL.lastPathComponent,
            fileExtension: fileURL.pathExtension.lowercased(),
            byteCount: Int64(values.fileSize ?? 0),
            modificationDate: values.contentModificationDate,
            resourceIdentifier: values.fileResourceIdentifier.map {
                String(describing: $0)
            }
        )
    }

}

enum LocalLibraryStoreError: Error, Equatable {
    case entryNotFound
    case signatureMismatch
    case fileOutsideAuthorizedFolders
    case notAFile
}
