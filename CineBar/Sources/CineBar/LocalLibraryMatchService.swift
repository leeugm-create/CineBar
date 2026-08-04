import Foundation

struct LocalLibraryMatchCandidate: Hashable, Identifiable {
    let id: Int
    let kind: LocalLibraryMediaKind
    let title: String
    let year: String
    let posterPath: String?
    let overview: String
    let voteAverage: Double
    let genreIDs: [Int]
    let confidence: Double

    init(movie: Movie, query: LocalLibraryParsedFilename) {
        self.init(
            id: movie.id,
            kind: .movie,
            title: movie.title,
            year: movie.year,
            posterPath: movie.posterPath,
            overview: movie.overview,
            voteAverage: movie.voteAverage,
            genreIDs: movie.genreIDs ?? [],
            confidence: Self.confidence(title: movie.title, year: movie.year, query: query)
        )
    }

    init(television show: TVShow, query: LocalLibraryParsedFilename) {
        self.init(
            id: show.id,
            kind: .television,
            title: show.name,
            year: show.year,
            posterPath: show.posterPath,
            overview: show.overview,
            voteAverage: show.voteAverage,
            genreIDs: show.genreIDs ?? [],
            confidence: Self.confidence(title: show.name, year: show.year, query: query)
        )
    }

    var metadata: LocalLibraryMetadata {
        LocalLibraryMetadata(
            id: id,
            kind: kind,
            title: title,
            year: year,
            posterPath: posterPath,
            overview: overview,
            voteAverage: voteAverage,
            genreIDs: genreIDs
        )
    }

    var posterURL: URL? {
        LocalLibraryDetailBridge.posterURL(for: posterPath)
    }

    private init(
        id: Int,
        kind: LocalLibraryMediaKind,
        title: String,
        year: String,
        posterPath: String?,
        overview: String,
        voteAverage: Double,
        genreIDs: [Int],
        confidence: Double
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.year = year
        self.posterPath = posterPath
        self.overview = overview
        self.voteAverage = voteAverage
        self.genreIDs = genreIDs
        self.confidence = confidence
    }

    private static func confidence(
        title: String,
        year: String,
        query: LocalLibraryParsedFilename
    ) -> Double {
        let queryTitle = normalized(query.title)
        let candidateTitle = normalized(title)
        guard !queryTitle.isEmpty, !candidateTitle.isEmpty else { return 0 }
        var score: Double
        if candidateTitle == queryTitle {
            score = 0.9
        } else {
            let queryTokens = Set(queryTitle.split(separator: " "))
            let candidateTokens = Set(candidateTitle.split(separator: " "))
            let overlap = Double(queryTokens.intersection(candidateTokens).count)
            let union = Double(queryTokens.union(candidateTokens).count)
            score = union == 0 ? 0 : overlap / union
            if candidateTitle.contains(queryTitle) || queryTitle.contains(candidateTitle) {
                score = max(score, 0.7)
            }
            score = min(
                0.89,
                max(score, editDistanceSimilarity(queryTitle, candidateTitle))
            )
        }
        if let queryYear = query.year, queryYear == year {
            score = min(1, score + 0.1)
        }
        return score
    }

    private static func editDistanceSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let lhsCharacters = Array(lhs)
        let rhsCharacters = Array(rhs)
        let longestLength = max(lhsCharacters.count, rhsCharacters.count)
        guard longestLength > 0 else { return 0 }

        var previousRow = Array(0...rhsCharacters.count)
        for (lhsIndex, lhsCharacter) in lhsCharacters.enumerated() {
            var currentRow = [lhsIndex + 1]
            for (rhsIndex, rhsCharacter) in rhsCharacters.enumerated() {
                let substitutionCost = lhsCharacter == rhsCharacter ? 0 : 1
                currentRow.append(min(
                    previousRow[rhsIndex + 1] + 1,
                    currentRow[rhsIndex] + 1,
                    previousRow[rhsIndex] + substitutionCost
                ))
            }
            previousRow = currentRow
        }
        return 1 - Double(previousRow[rhsCharacters.count]) / Double(longestLength)
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "[^[:alnum:]]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct LocalLibraryMatchQuery: Hashable {
    let text: String
    let kind: LocalLibraryMediaKind

    init(text: String, kind: LocalLibraryMediaKind) {
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.kind = kind
    }
}

struct LocalLibraryMatchService {
    private let movieSearch: (String) async throws -> [Movie]
    private let televisionSearch: (String) async throws -> [TVShow]

    init(client: TMDBClient) {
        movieSearch = { try await client.search($0) }
        televisionSearch = { try await client.searchTV($0) }
    }

    init(
        movieSearch: @escaping (String) async throws -> [Movie],
        televisionSearch: @escaping (String) async throws -> [TVShow]
    ) {
        self.movieSearch = movieSearch
        self.televisionSearch = televisionSearch
    }

    func search(for entry: LocalLibraryEntry) async throws -> [LocalLibraryMatchCandidate] {
        guard entry.contentCategory != .other else { return [] }
        let query = LocalLibraryFilenameParser.parse(entry.signature.fileName)
        guard !query.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        let kind = entry.metadata?.kind ?? mediaKind(for: entry.contentCategory)
        let candidates: [LocalLibraryMatchCandidate]
        switch kind {
        case .movie:
            candidates = try await movieSearch(query.title).map {
                LocalLibraryMatchCandidate(movie: $0, query: query)
            }
        case .television:
            candidates = try await televisionSearch(query.title).map {
                LocalLibraryMatchCandidate(television: $0, query: query)
            }
        }
        return candidates.sorted(by: Self.isPreferred)
    }

    func search(query: LocalLibraryMatchQuery) async throws -> [LocalLibraryMatchCandidate] {
        guard !query.text.isEmpty else { return [] }
        let parsedQuery = LocalLibraryFilenameParser.parse(query.text + ".mkv")
        let normalizedQuery = LocalLibraryParsedFilename(
            title: query.text,
            year: parsedQuery.year,
            fileExtension: "mkv",
            category: query.kind == .movie ? .movie : .television,
            isTrustedTitle: true
        )
        let candidates: [LocalLibraryMatchCandidate]
        switch query.kind {
        case .movie:
            candidates = try await movieSearch(query.text).map {
                LocalLibraryMatchCandidate(movie: $0, query: normalizedQuery)
            }
        case .television:
            candidates = try await televisionSearch(query.text).map {
                LocalLibraryMatchCandidate(television: $0, query: normalizedQuery)
            }
        }
        return candidates.sorted(by: Self.isPreferred)
    }

    private static func isPreferred(
        _ lhs: LocalLibraryMatchCandidate,
        _ rhs: LocalLibraryMatchCandidate
    ) -> Bool {
        if lhs.confidence != rhs.confidence { return lhs.confidence > rhs.confidence }
        if lhs.voteAverage != rhs.voteAverage { return lhs.voteAverage > rhs.voteAverage }
        let titleOrder = lhs.title.localizedStandardCompare(rhs.title)
        if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
        return lhs.id < rhs.id
    }

    private func mediaKind(
        for category: LocalLibraryContentCategory
    ) -> LocalLibraryMediaKind {
        category == .television ? .television : .movie
    }
}
