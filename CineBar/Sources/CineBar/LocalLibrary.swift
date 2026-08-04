import Foundation

enum LocalLibraryFileState: String, Codable, Hashable {
    case available
    case missing
    case volumeUnavailable
}

enum LocalLibraryMatchState: String, Codable, Hashable {
    case unmatched
    case suggested
    case confirmed
}

enum LocalLibraryMediaKind: String, Codable, Hashable {
    case movie
    case television
}

enum LocalLibraryContentCategory: String, Codable, Hashable {
    case movie
    case television
    case other
}

enum LocalLibraryCategoryFilter: CaseIterable, Identifiable {
    case all
    case movie
    case television
    case other

    var id: Self { self }

    func includes(_ entry: LocalLibraryEntry) -> Bool {
        switch self {
        case .all: return true
        case .movie: return entry.contentCategory == .movie
        case .television: return entry.contentCategory == .television
        case .other: return entry.contentCategory == .other
        }
    }
}

enum LocalLibraryStatusFilter: CaseIterable, Identifiable {
    case all
    case unwatched
    case unmatched
    case unavailable

    var id: Self { self }

    func includes(_ entry: LocalLibraryEntry) -> Bool {
        switch self {
        case .all: return true
        case .unwatched: return !entry.isWatched
        case .unmatched: return entry.matchState != .confirmed
        case .unavailable: return entry.state != .available
        }
    }
}

struct LocalLibraryFileSignature: Codable, Hashable {
    let fileName: String
    let fileExtension: String
    let byteCount: Int64
    let modificationDate: Date?
    let resourceIdentifier: String?

    func matchesForReattachment(_ candidate: LocalLibraryFileSignature) -> Bool {
        if let resourceIdentifier,
           let candidateIdentifier = candidate.resourceIdentifier,
           resourceIdentifier == candidateIdentifier {
            return true
        }
        return fileName.precomposedStringWithCanonicalMapping ==
                candidate.fileName.precomposedStringWithCanonicalMapping &&
            fileExtension.lowercased() == candidate.fileExtension.lowercased() &&
            byteCount == candidate.byteCount &&
            modificationDate == candidate.modificationDate
    }
}

struct LocalLibraryMetadata: Codable, Hashable {
    let id: Int
    let kind: LocalLibraryMediaKind
    let title: String
    let year: String
    let posterPath: String?
    let overview: String
    let voteAverage: Double
    var genreIDs: [Int]? = nil
}

struct LocalLibraryEntry: Codable, Identifiable, Hashable {
    let id: UUID
    var folderID: UUID
    var relativePath: String
    var signature: LocalLibraryFileSignature
    var state: LocalLibraryFileState
    var matchState: LocalLibraryMatchState
    var contentCategory: LocalLibraryContentCategory = .other
    var metadata: LocalLibraryMetadata?
    var isWatched: Bool
    var isInWatchlist: Bool
    var lastOpenedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id, folderID, relativePath, signature, state, matchState
        case contentCategory, metadata, isWatched, isInWatchlist, lastOpenedAt
    }

    init(
        id: UUID,
        folderID: UUID,
        relativePath: String,
        signature: LocalLibraryFileSignature,
        state: LocalLibraryFileState,
        matchState: LocalLibraryMatchState,
        metadata: LocalLibraryMetadata?,
        isWatched: Bool,
        isInWatchlist: Bool,
        lastOpenedAt: Date?,
        contentCategory: LocalLibraryContentCategory = .other
    ) {
        self.id = id
        self.folderID = folderID
        self.relativePath = relativePath
        self.signature = signature
        self.state = state
        self.matchState = matchState
        self.contentCategory = contentCategory
        self.metadata = metadata
        self.isWatched = isWatched
        self.isInWatchlist = isInWatchlist
        self.lastOpenedAt = lastOpenedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        folderID = try container.decode(UUID.self, forKey: .folderID)
        relativePath = try container.decode(String.self, forKey: .relativePath)
        signature = try container.decode(
            LocalLibraryFileSignature.self,
            forKey: .signature
        )
        state = try container.decode(LocalLibraryFileState.self, forKey: .state)
        matchState = try container.decode(
            LocalLibraryMatchState.self,
            forKey: .matchState
        )
        contentCategory = try container.decodeIfPresent(
            LocalLibraryContentCategory.self,
            forKey: .contentCategory
        ) ?? .other
        metadata = try container.decodeIfPresent(
            LocalLibraryMetadata.self,
            forKey: .metadata
        )
        isWatched = try container.decode(Bool.self, forKey: .isWatched)
        isInWatchlist = try container.decode(Bool.self, forKey: .isInWatchlist)
        lastOpenedAt = try container.decodeIfPresent(Date.self, forKey: .lastOpenedAt)
    }
}

struct LocalLibraryFolder: Codable, Identifiable, Hashable {
    let id: UUID
    var displayName: String
    var pathHint: String
    var bookmarkData: Data
}

struct LocalLibraryFolderBookmark: Hashable {
    let bookmarkData: Data
    let pathHint: String

    static func make(from url: URL) throws -> LocalLibraryFolderBookmark {
        let bookmarkData = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        return LocalLibraryFolderBookmark(
            bookmarkData: bookmarkData,
            pathHint: url.lastPathComponent
        )
    }

    static func resolve(_ bookmarkData: Data) throws -> LocalLibraryResolvedFolder {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return LocalLibraryResolvedFolder(
            url: url,
            isStale: isStale,
            startedAccessing: url.startAccessingSecurityScopedResource()
        )
    }
}

final class LocalLibraryResolvedFolder {
    let url: URL
    let isStale: Bool
    private var startedAccessing: Bool

    fileprivate init(url: URL, isStale: Bool, startedAccessing: Bool) {
        self.url = url
        self.isStale = isStale
        self.startedAccessing = startedAccessing
    }

    func stopAccessing() {
        guard startedAccessing else { return }
        url.stopAccessingSecurityScopedResource()
        startedAccessing = false
    }

    deinit {
        stopAccessing()
    }
}

struct LocalLibraryParsedFilename: Hashable {
    let title: String
    let year: String?
    let fileExtension: String
    let category: LocalLibraryContentCategory
    let isTrustedTitle: Bool
}

enum LocalLibraryFilenameParser {
    static func parse(_ filename: String) -> LocalLibraryParsedFilename {
        guard !filename.isEmpty else {
            return LocalLibraryParsedFilename(
                title: "",
                year: nil,
                fileExtension: "",
                category: .other,
                isTrustedTitle: false
            )
        }
        let fileURL = URL(fileURLWithPath: filename)
        let fileExtension = fileURL.pathExtension.lowercased()
        let stem = fileURL.deletingPathExtension().lastPathComponent
        let year = extractedYear(from: stem)
        let hasEpisodeMarker = stem.range(
            of: "(?i)(?:s[0-9]{1,2}e[0-9]{1,2}|season[ ._-]*[0-9]{1,2})",
            options: .regularExpression
        ) != nil
        var title = stem.replacingOccurrences(
            of: "[._]+",
            with: " ",
            options: .regularExpression
        )
        title = title.replacingOccurrences(
            of: "[\\(\\[\\{]?(?:18(?:8[8-9]|9[0-9])|19[0-9]{2}|20[0-9]{2}|2100)[\\)\\]\\}]?",
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        title = title.replacingOccurrences(
            of: "(?i)\\b(?:2160p|1080p|720p|480p|4k|8k|web[ -]?dl|web[ -]?rip|blu[ -]?ray|bdrip|dvdrip|h\\.?26[45]|x26[45]|hevc|avc|av1|hdr10(?:\\+)?|dolby[ .-]?vision|atmos|truehd|dts(?:[ .-]?hd)?|aac|flac|remux|proper|repack|extended|unrated|chs|cht|eng|jpn|kor|中文字幕|中英字幕|国语|粤语)\\b",
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        title = title.replacingOccurrences(
            of: "(?i)\\b(?:s[0-9]{1,2}e[0-9]{1,2}|season[ ._-]*[0-9]{1,2})\\b",
            with: " ",
            options: .regularExpression
        )
        title = title.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        title = title.trimmingCharacters(
            in: CharacterSet(charactersIn: " -_.")
        )

        let trustedTitle = isTrustedTitle(title: title, stem: stem)
        let category: LocalLibraryContentCategory = trustedTitle
            ? (hasEpisodeMarker ? .television : .movie)
            : .other

        return LocalLibraryParsedFilename(
            title: title.isEmpty ? filename : title,
            year: year,
            fileExtension: fileExtension,
            category: category,
            isTrustedTitle: trustedTitle
        )
    }

    private static func extractedYear(from filename: String) -> String? {
        let pattern = "(?<![0-9])(18(?:8[8-9]|9[0-9])|19[0-9]{2}|20[0-9]{2}|2100)(?![0-9])"
        guard let range = filename.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        return String(filename[range])
    }

    private static func isTrustedTitle(title: String, stem: String) -> Bool {
        let personalPattern = "(?i)^(?:img|vid|pxl|dsc|mov|mvi|gopr|cimg|dji|screen[ ._-]*recording|截屏|屏幕录制|录屏|微信视频|whatsapp[ ._-]*video)[ ._-]*(?:[0-9]{4,}|$)"
        if stem.range(of: personalPattern, options: .regularExpression) != nil {
            return false
        }
        let timestampPattern = "^(?:[0-9]{4}[-_][0-9]{2}[-_][0-9]{2}(?:[-_][0-9]{2,6})?|[0-9]{8,})$"
        if title.range(of: timestampPattern, options: .regularExpression) != nil {
            return false
        }
        guard !title.isEmpty,
              title.rangeOfCharacter(from: .letters) != nil
        else {
            return false
        }
        return title.count >= 2
    }
}

enum LocalLibraryEntryMerge {
    static func key(folderID: UUID, relativePath: String) -> String {
        let normalizedPath = relativePath
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .reduce(into: [Substring]()) { components, component in
                switch component {
                case ".":
                    break
                case "..":
                    if !components.isEmpty {
                        components.removeLast()
                    }
                default:
                    components.append(component)
                }
            }
            .map(String.init)
            .joined(separator: "/")
            .precomposedStringWithCanonicalMapping
        return "\(folderID.uuidString.lowercased())/\(normalizedPath)"
    }
}

struct LocalLibrarySnapshot: Codable, Hashable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var folders: [LocalLibraryFolder]
    var entries: [LocalLibraryEntry]

    init(
        schemaVersion: Int = LocalLibrarySnapshot.currentSchemaVersion,
        folders: [LocalLibraryFolder] = [],
        entries: [LocalLibraryEntry] = []
    ) {
        self.schemaVersion = schemaVersion
        self.folders = folders
        self.entries = entries
    }

    func migrated() -> LocalLibrarySnapshot {
        guard schemaVersion < Self.currentSchemaVersion else { return self }
        var migratedEntries = entries
        for index in migratedEntries.indices {
            if let metadata = migratedEntries[index].metadata {
                migratedEntries[index].contentCategory = metadata.kind == .movie
                    ? .movie
                    : .television
                continue
            }
            let parsed = LocalLibraryFilenameParser.parse(
                migratedEntries[index].signature.fileName
            )
            migratedEntries[index].contentCategory = parsed.category
            if parsed.isTrustedTitle,
               migratedEntries[index].matchState == .unmatched {
                migratedEntries[index].matchState = .suggested
            }
        }
        return LocalLibrarySnapshot(
            schemaVersion: Self.currentSchemaVersion,
            folders: folders,
            entries: migratedEntries
        )
    }
}

struct LocalLibraryPersistence {
    let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
    }

    func load() -> LocalLibrarySnapshot {
        decodeSnapshot(at: fileURL) ?? decodeSnapshot(at: backupURL) ?? LocalLibrarySnapshot()
    }

    func save(_ snapshot: LocalLibrarySnapshot) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: fileURL.path) {
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }
            try fileManager.moveItem(at: fileURL, to: backupURL)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }

    private var backupURL: URL {
        fileURL.appendingPathExtension("bak")
    }

    private func decodeSnapshot(at url: URL) -> LocalLibrarySnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(LocalLibrarySnapshot.self, from: data).migrated()
    }

    private static func defaultFileURL() -> URL {
        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support")
        return applicationSupportURL
            .appendingPathComponent("CineBar", isDirectory: true)
            .appendingPathComponent("LocalLibrary.json")
    }
}
