import Combine
import Foundation

@MainActor
final class LocalLibraryStore: ObservableObject {
    @Published private(set) var folders: [LocalLibraryFolder]
    @Published private(set) var entries: [LocalLibraryEntry]
    @Published private(set) var isScanning = false
    @Published private(set) var scanProgress: LocalLibraryScanProgress?
    @Published private(set) var message: String?

    private let persistence: LocalLibraryPersistence

    init(fileURL: URL? = nil) {
        persistence = LocalLibraryPersistence(fileURL: fileURL)
        let snapshot = persistence.load()
        folders = snapshot.folders
        entries = snapshot.entries
    }

    func addFolder(url: URL) throws {
        let standardizedURL = url.standardizedFileURL
        guard !containsFolder(at: standardizedURL) else { return }

        let bookmark = try LocalLibraryFolderBookmark.make(from: standardizedURL)
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
            message = String(localized: "所选文件夹已不在片库中。")
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
            guard signaturesMatch(oldEntry.signature, fileSignature) else {
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

    func updateMetadata(entryID: UUID, metadata: LocalLibraryMetadata?) {
        mutateEntry(entryID) {
            $0.metadata = metadata
            $0.matchState = metadata == nil ? .unmatched : .confirmed
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
        let result = await LocalLibraryScanner().scan(
            roots: roots,
            existing: existingEntries,
            progress: { [weak self] progress in
                Task { @MainActor in self?.scanProgress = progress }
            }
        )
        let mergedEntries = LocalLibraryRefreshMerger.merge(
            existing: existingEntries,
            scanned: result,
            roots: roots
        )
        do {
            try persistence.save(LocalLibrarySnapshot(
                folders: folders,
                entries: mergedEntries
            ))
            entries = mergedEntries
            if result.wasCancelled {
                message = String(localized: "片库刷新已取消。")
            }
        } catch {
            message = String(localized: "无法保存本地片库。")
        }
        isScanning = false
    }

    private func mutateEntry(
        _ entryID: UUID,
        mutation: (inout LocalLibraryEntry) -> Void
    ) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else {
            message = String(localized: "所选片库项目已不存在。")
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
            message = String(localized: "无法保存本地片库。")
        }
    }

    private func containsFolder(at url: URL) -> Bool {
        folders.contains { folder in
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

    private func signaturesMatch(
        _ original: LocalLibraryFileSignature,
        _ candidate: LocalLibraryFileSignature
    ) -> Bool {
        if let originalID = original.resourceIdentifier,
           let candidateID = candidate.resourceIdentifier {
            return originalID == candidateID
        }
        return original.byteCount == candidate.byteCount &&
            original.modificationDate == candidate.modificationDate
    }
}

private enum LocalLibraryStoreError: LocalizedError {
    case entryNotFound
    case signatureMismatch
    case fileOutsideAuthorizedFolders
    case notAFile

    var errorDescription: String? {
        switch self {
        case .entryNotFound:
            return String(localized: "片库项目已不存在。")
        case .signatureMismatch:
            return String(localized: "所选文件与片库项目不匹配。")
        case .fileOutsideAuthorizedFolders:
            return String(localized: "所选文件不在已授权的文件夹中。")
        case .notAFile:
            return String(localized: "所选项目不是文件。")
        }
    }
}
