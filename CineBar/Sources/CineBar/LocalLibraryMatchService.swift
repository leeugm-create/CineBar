import Foundation

struct LocalLibraryMatchCandidate: Hashable, Identifiable {
    let id: Int
    let kind: LocalLibraryMediaKind
    let title: String
    let year: String
    let posterURL: URL?
    let overview: String
    let voteAverage: Double
    let confidence: Double

    init(movie: Movie, query: LocalLibraryParsedFilename) {
        self.init(
            id: movie.id,
            kind: .movie,
            title: movie.title,
            year: movie.year,
            posterURL: movie.posterURL,
            overview: movie.overview,
            voteAverage: movie.voteAverage,
            confidence: Self.confidence(title: movie.title, year: movie.year, query: query)
        )
    }

    init(television show: TVShow, query: LocalLibraryParsedFilename) {
        self.init(
            id: show.id,
            kind: .television,
            title: show.name,
            year: show.year,
            posterURL: show.posterURL,
            overview: show.overview,
            voteAverage: show.voteAverage,
            confidence: Self.confidence(title: show.name, year: show.year, query: query)
        )
    }

    var metadata: LocalLibraryMetadata {
        LocalLibraryMetadata(
            id: id,
            kind: kind,
            title: title,
            year: year,
            posterPath: posterURL?.path,
            overview: overview,
            voteAverage: voteAverage
        )
    }

    private init(
        id: Int,
        kind: LocalLibraryMediaKind,
        title: String,
        year: String,
        posterURL: URL?,
        overview: String,
        voteAverage: Double,
        confidence: Double
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.year = year
        self.posterURL = posterURL
        self.overview = overview
        self.voteAverage = voteAverage
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
        if candidateTitle == queryTitle { return 1 }

        let queryTokens = Set(queryTitle.split(separator: " "))
        let candidateTokens = Set(candidateTitle.split(separator: " "))
        let overlap = Double(queryTokens.intersection(candidateTokens).count)
        let union = Double(queryTokens.union(candidateTokens).count)
        var score = union == 0 ? 0 : overlap / union
        if candidateTitle.contains(queryTitle) || queryTitle.contains(candidateTitle) {
            score = max(score, 0.7)
        }
        if let queryYear = query.year, queryYear == year {
            score = min(0.95, score + 0.1)
        }
        return score
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "[^[:alnum:]]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
        let query = LocalLibraryFilenameParser.parse(entry.signature.fileName)
        guard !query.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        let kind = entry.metadata?.kind ?? inferredKind(for: entry.signature.fileName)
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
        return candidates.sorted {
            if $0.confidence != $1.confidence { return $0.confidence > $1.confidence }
            return $0.voteAverage > $1.voteAverage
        }
    }

    private func inferredKind(for filename: String) -> LocalLibraryMediaKind {
        let televisionPattern = "(?i)(?:s[0-9]{1,2}e[0-9]{1,2}|season[ ._-]*[0-9]{1,2})"
        return filename.range(of: televisionPattern, options: .regularExpression) == nil
            ? .movie
            : .television
    }
}
