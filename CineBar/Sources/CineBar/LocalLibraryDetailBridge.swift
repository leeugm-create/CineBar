import Foundation

enum LocalLibraryDetailBridge {
    static func movie(from metadata: LocalLibraryMetadata) -> Movie? {
        guard metadata.kind == .movie,
              metadata.id > 0,
              !metadata.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        return Movie(
            id: metadata.id,
            title: metadata.title,
            originalTitle: nil,
            overview: metadata.overview,
            posterPath: normalizedPosterPath(metadata.posterPath),
            releaseDate: date(for: metadata.year),
            voteAverage: metadata.voteAverage,
            voteCount: 0,
            genreIDs: metadata.genreIDs
        )
    }

    static func television(from metadata: LocalLibraryMetadata) -> TVShow? {
        guard metadata.kind == .television,
              metadata.id > 0,
              !metadata.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        return TVShow(
            id: metadata.id,
            name: metadata.title,
            originalName: nil,
            overview: metadata.overview,
            posterPath: normalizedPosterPath(metadata.posterPath),
            firstAirDate: date(for: metadata.year),
            voteAverage: metadata.voteAverage,
            voteCount: 0,
            genreIDs: metadata.genreIDs
        )
    }

    static func posterURL(for posterPath: String?) -> URL? {
        guard let posterPath,
              !posterPath.isEmpty
        else { return nil }

        if let url = URL(string: posterPath), url.scheme != nil {
            return url
        }
        if posterPath.hasPrefix("/t/p/") {
            return URL(string: "https://image.tmdb.org\(posterPath)")
        }
        return URL(string: "https://image.tmdb.org/t/p/w342\(posterPath)")
    }

    private static func date(for year: String) -> String? {
        guard year.range(of: "^[0-9]{4}$", options: .regularExpression) != nil
        else { return nil }
        return "\(year)-01-01"
    }

    private static func normalizedPosterPath(_ posterPath: String?) -> String? {
        guard let posterPath,
              let url = URL(string: posterPath),
              url.scheme != nil,
              url.host?.lowercased() == "image.tmdb.org",
              url.path.hasPrefix("/t/p/")
        else { return posterPath }

        let sizeAndPath = url.path.dropFirst("/t/p/".count)
        guard let pathStart = sizeAndPath.firstIndex(of: "/") else {
            return posterPath
        }
        return String(sizeAndPath[pathStart...])
    }
}
