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

struct LocalLibraryFileSignature: Codable, Hashable {
    let fileName: String
    let fileExtension: String
    let byteCount: Int64
    let modificationDate: Date?
    let resourceIdentifier: String?
}

struct LocalLibraryMetadata: Codable, Hashable {
    let id: Int
    let kind: LocalLibraryMediaKind
    let title: String
    let year: String
    let posterPath: String?
    let overview: String
    let voteAverage: Double
}

struct LocalLibraryEntry: Codable, Identifiable, Hashable {
    let id: UUID
    var folderID: UUID
    var relativePath: String
    var signature: LocalLibraryFileSignature
    var state: LocalLibraryFileState
    var matchState: LocalLibraryMatchState
    var metadata: LocalLibraryMetadata?
    var isWatched: Bool
    var isInWatchlist: Bool
    var lastOpenedAt: Date?
}

struct LocalLibraryFolder: Codable, Identifiable, Hashable {
    let id: UUID
    var displayName: String
    var pathHint: String
    var bookmarkData: Data
}

struct LocalLibraryParsedFilename: Hashable {
    let title: String
    let year: String?
    let fileExtension: String
}

enum LocalLibraryFilenameParser {
    static func parse(_ filename: String) -> LocalLibraryParsedFilename {
        guard !filename.isEmpty else {
            return LocalLibraryParsedFilename(
                title: "",
                year: nil,
                fileExtension: ""
            )
        }
        let fileURL = URL(fileURLWithPath: filename)
        let fileExtension = fileURL.pathExtension.lowercased()
        let stem = fileURL.deletingPathExtension().lastPathComponent
        let year = extractedYear(from: stem)
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
            of: "\\s+",
            with: " ",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        title = title.trimmingCharacters(
            in: CharacterSet(charactersIn: " -_.")
        )

        return LocalLibraryParsedFilename(
            title: title.isEmpty ? filename : title,
            year: year,
            fileExtension: fileExtension
        )
    }

    private static func extractedYear(from filename: String) -> String? {
        let pattern = "(?<![0-9])(18(?:8[8-9]|9[0-9])|19[0-9]{2}|20[0-9]{2}|2100)(?![0-9])"
        guard let range = filename.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        return String(filename[range])
    }
}

enum LocalLibraryEntryMerge {
    static func key(folderID: UUID, relativePath: String) -> String {
        let normalizedPath = relativePath
            .replacingOccurrences(of: "\\\\", with: "/")
            .split(separator: "/")
            .filter { !$0.isEmpty && $0 != "." }
            .joined(separator: "/")
            .precomposedStringWithCanonicalMapping
            .lowercased()
        return "\(folderID.uuidString.lowercased())/\(normalizedPath)"
    }
}

struct LocalLibrarySnapshot: Codable, Hashable {
    static let currentSchemaVersion = 1

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
        return try? decoder.decode(LocalLibrarySnapshot.self, from: data)
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
