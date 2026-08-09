import AppKit
import Combine
import EventKit
import Foundation
import ServiceManagement
import SwiftUI
import UserNotifications
import UniformTypeIdentifiers
import WebKit

private let posterImageCache = NSCache<NSURL, NSImage>()

private func cachedPosterImage(for url: URL) async -> NSImage? {
    let key = url as NSURL
    if let cached = posterImageCache.object(forKey: key) {
        return cached
    }
    var request = URLRequest(url: url)
    request.cachePolicy = .returnCacheDataElseLoad
    request.timeoutInterval = 30
    do {
        let (data, _) = try await URLSession.shared.data(for: request)
        if let image = NSImage(data: data) {
            posterImageCache.setObject(image, forKey: key)
            return image
        }
    } catch {
        return nil
    }
    return nil
}

private func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

private func providerSearchURL(
    providerName: String,
    title: String
) -> URL? {
    let name = providerName.lowercased()
    if name.contains("爱奇艺") || name.contains("iqiyi") {
        let encoded = title.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? title
        return URL(string: "https://so.iqiyi.com/so/q_\(encoded)")
    }
    if name.contains("优酷") || name.contains("youku") {
        let encoded = title.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) ?? title
        return URL(string: "https://so.youku.com/search_video/q_\(encoded)")
    }
    let configuration: (String, String, String)?
    if name.contains("netflix") {
        configuration = ("https://www.netflix.com/search", "q", title)
    } else if name.contains("disney") {
        configuration = ("https://www.disneyplus.com/search", "q", title)
    } else if name.contains("amazon") || name.contains("prime video") {
        configuration = (
            "https://www.primevideo.com/search/ref=atv_nb_sr",
            "phrase",
            title
        )
    } else if name.contains("apple tv") {
        configuration = ("https://tv.apple.com/search", "term", title)
    } else if name == "max" || name.contains("hbo max") {
        configuration = ("https://www.max.com/search", "q", title)
    } else if name.contains("hulu") {
        configuration = ("https://www.hulu.com/search", "query", title)
    } else if name.contains("paramount") {
        configuration = ("https://www.paramountplus.com/search/", "q", title)
    } else if name.contains("youtube") {
        configuration = ("https://www.youtube.com/results", "search_query", title)
    } else if name.contains("bilibili") {
        configuration = ("https://search.bilibili.com/all", "keyword", title)
    } else if name.contains("腾讯") || name.contains("tencent") {
        configuration = ("https://v.qq.com/x/search/", "q", title)
    } else if name.contains("芒果") || name.contains("mango") {
        configuration = ("https://so.mgtv.com/so", "k", title)
    } else {
        configuration = nil
    }
    guard let configuration,
          var components = URLComponents(string: configuration.0)
    else { return nil }
    components.queryItems = [
        URLQueryItem(name: configuration.1, value: configuration.2)
    ]
    return components.url
}

enum MainlandTrailerPlatform: String, CaseIterable, Identifiable {
    case bilibili
    case tencentVideo
    case youku
    case iqiyi

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch (self, language) {
        case (.bilibili, _): return "哔哩哔哩"
        case (.tencentVideo, .zhCN): return "腾讯视频"
        case (.tencentVideo, .zhHK), (.tencentVideo, .zhTW): return "騰訊視頻"
        case (.tencentVideo, .enUS): return "Tencent Video"
        case (.tencentVideo, .jaJP): return "Tencent Video"
        case (.tencentVideo, .koKR): return "Tencent Video"
        case (.youku, .zhCN): return "优酷"
        case (.youku, .zhHK), (.youku, .zhTW): return "優酷"
        case (.youku, _): return "Youku"
        case (.iqiyi, .zhCN): return "爱奇艺"
        case (.iqiyi, .zhHK), (.iqiyi, .zhTW): return "愛奇藝"
        case (.iqiyi, _): return "iQIYI"
        }
    }

    func url(for title: String) -> URL? {
        let query = title.localizedCaseInsensitiveContains("预告") ||
            title.localizedCaseInsensitiveContains("trailer")
            ? title
            : "\(title) 预告"
        switch self {
        case .bilibili:
            return providerSearchURL(
                providerName: "bilibili",
                title: query
            )
        case .tencentVideo:
            return providerSearchURL(
                providerName: "腾讯视频",
                title: query
            )
        case .youku:
            return providerSearchURL(
                providerName: "优酷",
                title: query
            )
        case .iqiyi:
            return providerSearchURL(
                providerName: "爱奇艺",
                title: query
            )
        }
    }
}

struct Movie: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let originalTitle: String?
    let overview: String
    let posterPath: String?
    let releaseDate: String?
    var localizedReleaseDate: String? = nil
    var localizedReleaseNote: String? = nil
    let voteAverage: Double
    let voteCount: Int
    var genreIDs: [Int]? = nil

    enum CodingKeys: String, CodingKey {
        case id, title, overview
        case originalTitle = "original_title"
        case posterPath = "poster_path"
        case releaseDate = "release_date"
        case localizedReleaseDate = "cinebar_localized_release_date"
        case localizedReleaseNote = "cinebar_localized_release_note"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case genreIDs = "genre_ids"
    }

    var year: String {
        guard let releaseDate, releaseDate.count >= 4 else { return "年份未知" }
        return String(releaseDate.prefix(4))
    }

    var posterURL: URL? {
        guard let posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w342\(posterPath)")
    }

    var tmdbURL: URL? {
        guard id > 0 else { return nil }
        return URL(string: "https://www.themoviedb.org/movie/\(id)")
    }

    var shareText: String {
        "\(title)（\(year)） · TMDB \(String(format: "%.1f", voteAverage))/10"
    }

    static let demo: [Movie] = [
        Movie(
            id: -1,
            title: "演示影片：远方",
            originalTitle: "Demo Movie",
            overview: "这是界面演示数据。填写免费的 TMDB API Read Access Token 后，即可显示真实热门影片、简介与评分。",
            posterPath: nil,
            releaseDate: "2026-01-01",
            voteAverage: 8.2,
            voteCount: 1280
        ),
        Movie(
            id: -2,
            title: "演示影片：周末影院",
            originalTitle: "Weekend Cinema",
            overview: "搜索、影片详情和正版观看平台查询都会在配置 API Token 后启用。",
            posterPath: nil,
            releaseDate: "2025-06-18",
            voteAverage: 7.6,
            voteCount: 864
        )
    ]
}

struct MovieResponse: Codable {
    let results: [Movie]
    let page: Int?
    let totalPages: Int?

    enum CodingKeys: String, CodingKey {
        case results, page
        case totalPages = "total_pages"
    }
}

struct MoviePageResult {
    let movies: [Movie]
    let page: Int
    let totalPages: Int
}

enum UpcomingMovieSorting {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }()

    static func sorted(_ movies: [Movie]) -> [Movie] {
        movies.sorted { lhs, rhs in
            let leftDate = dateFormatter.date(
                from: MovieReleaseDatePolicy.normalizedDate(
                    lhs.localizedReleaseDate ?? ""
                ) ?? ""
            )
            let rightDate = dateFormatter.date(
                from: MovieReleaseDatePolicy.normalizedDate(
                    rhs.localizedReleaseDate ?? ""
                ) ?? ""
            )
            switch (leftDate, rightDate) {
            case let (left?, right?) where left != right:
                return left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                if lhs.voteAverage != rhs.voteAverage {
                    return lhs.voteAverage > rhs.voteAverage
                }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
        }
    }
}

enum CatalogSortMode: String, CaseIterable, Identifiable {
    case popularity
    case rating

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch (self, language) {
        case (.popularity, .zhCN): return "按热度"
        case (.popularity, .zhHK), (.popularity, .zhTW): return "按熱度"
        case (.popularity, .enUS): return "Popularity"
        case (.popularity, .jaJP): return "人気順"
        case (.popularity, .koKR): return "인기순"
        case (.rating, .zhCN): return "按评分高低"
        case (.rating, .zhHK), (.rating, .zhTW): return "按評分高低"
        case (.rating, .enUS): return "Highest rated"
        case (.rating, .jaJP): return "評価の高い順"
        case (.rating, .koKR): return "평점 높은순"
        }
    }

    var apiValue: String {
        self == .rating ? "vote_average.desc" : "popularity.desc"
    }
}

enum MediaSection: String, CaseIterable, Identifiable {
    case movies
    case television

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch (self, language) {
        case (.movies, .zhCN): return "电影"
        case (.movies, .zhHK), (.movies, .zhTW): return "電影"
        case (.movies, .enUS): return "Movies"
        case (.movies, .jaJP): return "映画"
        case (.movies, .koKR): return "영화"
        case (.television, .zhCN): return "电视剧"
        case (.television, .zhHK), (.television, .zhTW): return "電視劇"
        case (.television, .enUS): return "TV"
        case (.television, .jaJP): return "テレビ"
        case (.television, .koKR): return "TV"
        }
    }
}

enum MovieBrowseSection: String, CaseIterable, Identifiable {
    case trending
    case recommendations
    case upcoming

    var id: String { rawValue }

    var title: String {
        switch self {
        case .upcoming: return "即将上映"
        case .recommendations: return "每日电影推荐"
        case .trending: return "本周热门"
        }
    }
}

enum TVBrowseSection: String, CaseIterable, Identifiable {
    case trending
    case recommendations
    case airingToday

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trending: return "本周热门电视剧"
        case .recommendations: return "每日电视剧推荐"
        case .airingToday: return "今日播出"
        }
    }
}

enum MainBrowseSection: String, CaseIterable, Identifiable {
    case movies
    case television
    case watchlist
    case localLibrary

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch (self, language) {
        case (.movies, .zhCN): return "电影"
        case (.movies, .zhHK), (.movies, .zhTW): return "電影"
        case (.movies, .enUS): return "Movies"
        case (.movies, .jaJP): return "映画"
        case (.movies, .koKR): return "영화"
        case (.television, .zhCN): return "电视剧"
        case (.television, .zhHK), (.television, .zhTW): return "電視劇"
        case (.television, .enUS): return "TV"
        case (.television, .jaJP): return "テレビ"
        case (.television, .koKR): return "TV"
        case (.watchlist, .zhCN): return "我的片单"
        case (.watchlist, .zhHK), (.watchlist, .zhTW): return "我的片單"
        case (.watchlist, .enUS): return "Watchlist"
        case (.watchlist, .jaJP): return "マイリスト"
        case (.watchlist, .koKR): return "내 목록"
        case (.localLibrary, .zhCN): return "本地片库"
        case (.localLibrary, .zhHK), (.localLibrary, .zhTW): return "本機片庫"
        case (.localLibrary, .enUS): return "Local Library"
        case (.localLibrary, .jaJP): return "ローカルライブラリ"
        case (.localLibrary, .koKR): return "로컬 라이브러리"
        }
    }
}

struct TVShow: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let originalName: String?
    let overview: String
    let posterPath: String?
    let firstAirDate: String?
    let voteAverage: Double
    let voteCount: Int
    var genreIDs: [Int]? = nil

    enum CodingKeys: String, CodingKey {
        case id, name, overview
        case originalName = "original_name"
        case posterPath = "poster_path"
        case firstAirDate = "first_air_date"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case genreIDs = "genre_ids"
    }

    var year: String {
        guard let firstAirDate, firstAirDate.count >= 4 else { return "年份未知" }
        return String(firstAirDate.prefix(4))
    }

    var posterURL: URL? {
        guard let posterPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w342\(posterPath)")
    }

    static let demo = TVShow(
        id: -101,
        name: "演示剧集：银幕之外",
        originalName: "Beyond the Screen",
        overview: "填写影片数据 Token 后，即可浏览热门电视剧、季数、演员、预告与正版观看平台。",
        posterPath: nil,
        firstAirDate: "2026-01-01",
        voteAverage: 8.4,
        voteCount: 930
    )
}

struct TVResponse: Codable {
    let results: [TVShow]
    let page: Int?
    let totalPages: Int?

    enum CodingKeys: String, CodingKey {
        case results, page
        case totalPages = "total_pages"
    }
}

struct TVPageResult {
    let shows: [TVShow]
    let page: Int
    let totalPages: Int
}

struct TVSeason: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let seasonNumber: Int
    let episodeCount: Int
    let airDate: String?
    let posterPath: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case seasonNumber = "season_number"
        case episodeCount = "episode_count"
        case airDate = "air_date"
        case posterPath = "poster_path"
    }
}

struct TVNetwork: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
}

struct TVEpisodeSummary: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let airDate: String?
    let episodeNumber: Int
    let seasonNumber: Int

    enum CodingKeys: String, CodingKey {
        case id, name
        case airDate = "air_date"
        case episodeNumber = "episode_number"
        case seasonNumber = "season_number"
    }

    var code: String {
        String(format: "S%02dE%02d", seasonNumber, episodeNumber)
    }
}

struct TVEpisode: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let overview: String
    let airDate: String?
    let episodeNumber: Int
    let seasonNumber: Int
    let voteAverage: Double
    let voteCount: Int
    let runtime: Int?
    let stillPath: String?

    enum CodingKeys: String, CodingKey {
        case id, name, overview, runtime
        case airDate = "air_date"
        case episodeNumber = "episode_number"
        case seasonNumber = "season_number"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case stillPath = "still_path"
    }

    var code: String {
        String(format: "S%02dE%02d", seasonNumber, episodeNumber)
    }

    var stillURL: URL? {
        guard let stillPath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w300\(stillPath)")
    }

    var reminderSummary: TVEpisodeSummary {
        TVEpisodeSummary(
            id: id,
            name: name,
            airDate: airDate,
            episodeNumber: episodeNumber,
            seasonNumber: seasonNumber
        )
    }
}

struct TVSeasonDetails: Codable {
    let id: Int
    let name: String
    let overview: String
    let seasonNumber: Int
    let episodes: [TVEpisode]

    enum CodingKeys: String, CodingKey {
        case id, name, overview, episodes
        case seasonNumber = "season_number"
    }
}

struct TVDetails: Codable {
    let status: String
    let firstAirDate: String?
    let lastAirDate: String?
    let numberOfSeasons: Int
    let numberOfEpisodes: Int
    let episodeRunTime: [Int]
    let originCountry: [String]
    let productionCountries: [ProductionCountry]
    let networks: [TVNetwork]
    let seasons: [TVSeason]
    let nextEpisodeToAir: TVEpisodeSummary?

    enum CodingKeys: String, CodingKey {
        case status, networks, seasons
        case firstAirDate = "first_air_date"
        case lastAirDate = "last_air_date"
        case numberOfSeasons = "number_of_seasons"
        case numberOfEpisodes = "number_of_episodes"
        case episodeRunTime = "episode_run_time"
        case originCountry = "origin_country"
        case productionCountries = "production_countries"
        case nextEpisodeToAir = "next_episode_to_air"
    }
}

struct TVExternalIDs: Codable {
    let imdbID: String?
    let tvdbID: Int?

    enum CodingKeys: String, CodingKey {
        case imdbID = "imdb_id"
        case tvdbID = "tvdb_id"
    }
}

struct TVAiringInfo: Hashable {
    let airDate: String
    let airTime: String?
    let localDateTime: Date?
    let platform: String?
    let sourceURL: URL?

    var localDisplayText: String {
        guard let localDateTime else {
            return [airDate, airTime].compactMap { $0 }.joined(separator: " ")
        }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: localDateTime)
    }
}

private struct TVMazeLookupShow: Decodable {
    struct Channel: Decodable {
        let name: String
    }

    struct Link: Decodable {
        let href: String
    }

    struct Links: Decodable {
        let nextEpisode: Link?

        enum CodingKeys: String, CodingKey {
            case nextEpisode = "nextepisode"
        }
    }

    let id: Int
    let url: String?
    let network: Channel?
    let webChannel: Channel?
    let links: Links

    enum CodingKeys: String, CodingKey {
        case id, url, network
        case webChannel = "webChannel"
        case links = "_links"
    }
}

private struct TVMazeEpisode: Decodable {
    let airdate: String
    let airtime: String?
    let airstamp: String?
}

struct ReleaseReminder: Codable, Identifiable, Hashable {
    enum MediaType: String, Codable {
        case movie
        case television
        case tvEpisode
        case tvSeason
    }

    let mediaType: MediaType
    let mediaID: Int
    let title: String
    var knownReleaseDate: String?
    var subID: String? = nil
    var reminderDayOffset: Int? = nil
    var reminderHour: Int? = nil

    var id: String {
        [mediaType.rawValue, String(mediaID), subID]
            .compactMap { $0 }
            .joined(separator: "-")
    }
}

enum EpisodeReminderOption: String, CaseIterable, Identifiable {
    case dayBefore
    case sameDay08
    case sameDay09
    case sameDay12
    case sameDay18
    case sameDay20
    case sameDay21

    var id: String { rawValue }

    var dayOffset: Int {
        self == .dayBefore ? -1 : 0
    }

    var hour: Int {
        switch self {
        case .dayBefore: return 9
        case .sameDay08: return 8
        case .sameDay09: return 9
        case .sameDay12: return 12
        case .sameDay18: return 18
        case .sameDay20: return 20
        case .sameDay21: return 21
        }
    }

    var title: String {
        self == .dayBefore
            ? "提前 1 天 · 09:00"
            : String(format: "播出当天 · %02d:00", hour)
    }
}

struct TVGenre: Identifiable, Hashable {
    let id: Int
    let title: String
    let symbol: String

    static let options: [TVGenre] = [
        TVGenre(id: 10759, title: "动作与冒险", symbol: "bolt.fill"),
        TVGenre(id: 16, title: "动画", symbol: "paintbrush.fill"),
        TVGenre(id: 35, title: "喜剧", symbol: "face.smiling"),
        TVGenre(id: 80, title: "犯罪", symbol: "hand.raised.fill"),
        TVGenre(id: 99, title: "纪录片", symbol: "globe.asia.australia.fill"),
        TVGenre(id: 18, title: "剧情", symbol: "theatermasks.fill"),
        TVGenre(id: 10751, title: "家庭", symbol: "figure.2.and.child.holdinghands"),
        TVGenre(id: 10762, title: "儿童", symbol: "figure.child"),
        TVGenre(id: 9648, title: "悬疑", symbol: "magnifyingglass"),
        TVGenre(id: 10763, title: "新闻", symbol: "newspaper.fill"),
        TVGenre(id: 10764, title: "真人秀", symbol: "person.3.fill"),
        TVGenre(id: 10765, title: "科幻与奇幻", symbol: "sparkles"),
        TVGenre(id: 10766, title: "肥皂剧", symbol: "bubble.left.and.bubble.right.fill"),
        TVGenre(id: 10767, title: "脱口秀", symbol: "mic.fill"),
        TVGenre(id: 10768, title: "战争与政治", symbol: "building.columns.fill"),
        TVGenre(id: 37, title: "西部", symbol: "sun.dust.fill")
    ]
}

struct MovieShelf: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let year: Int?
    let genreID: Int?
    let keywordQuery: String?
    let releaseDateFrom: String?
    let releaseDateTo: String?

    init(
        id: String,
        title: String,
        subtitle: String,
        symbol: String,
        year: Int? = nil,
        genreID: Int? = nil,
        keywordQuery: String? = nil,
        releaseDateFrom: String? = nil,
        releaseDateTo: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.year = year
        self.genreID = genreID
        self.keywordQuery = keywordQuery
        self.releaseDateFrom = releaseDateFrom
        self.releaseDateTo = releaseDateTo
    }

    static var yearOptions: [MovieShelf] {
        let currentYear = Calendar.current.component(.year, from: Date())
        return (0..<6).map { offset in
            let year = currentYear - offset
            return MovieShelf(
                id: "year-\(year)",
                title: "\(year) 年",
                subtitle: "年度电影",
                symbol: "calendar",
                year: year,
                genreID: nil,
                releaseDateFrom: nil,
                releaseDateTo: nil
            )
        } + [
            MovieShelf(
                id: "decade-2020",
                title: "2020 年代",
                subtitle: "近年佳作",
                symbol: "clock.arrow.circlepath",
                year: nil,
                genreID: nil,
                releaseDateFrom: "2020-01-01",
                releaseDateTo: "2029-12-31"
            ),
            MovieShelf(
                id: "classic",
                title: "经典老片",
                subtitle: "2000 年以前",
                symbol: "theatermasks",
                year: nil,
                genreID: nil,
                releaseDateFrom: "1900-01-01",
                releaseDateTo: "1999-12-31"
            )
        ]
    }

    static let genreOptions: [MovieShelf] = [
        MovieShelf(id: "genre-drama", title: "剧情", subtitle: "人物与故事", symbol: "theatermasks.fill", genreID: 18),
        MovieShelf(id: "genre-comedy", title: "喜剧", subtitle: "轻松一下", symbol: "face.smiling", genreID: 35),
        MovieShelf(id: "genre-thriller", title: "惊悚", subtitle: "紧张刺激", symbol: "exclamationmark.triangle.fill", genreID: 53),
        MovieShelf(id: "genre-action", title: "动作", subtitle: "热血时刻", symbol: "bolt.fill", genreID: 28),
        MovieShelf(id: "genre-romance", title: "爱情", subtitle: "浪漫故事", symbol: "heart.fill", genreID: 10749),
        MovieShelf(id: "genre-crime", title: "犯罪", subtitle: "迷雾追踪", symbol: "hand.raised.fill", genreID: 80),
        MovieShelf(id: "genre-horror", title: "恐怖", subtitle: "惊悚夜晚", symbol: "moon.stars.fill", genreID: 27),
        MovieShelf(id: "genre-mystery", title: "悬疑", subtitle: "寻找真相", symbol: "magnifyingglass", genreID: 9648),
        MovieShelf(id: "genre-adventure", title: "冒险", subtitle: "未知旅途", symbol: "map.fill", genreID: 12),
        MovieShelf(id: "genre-scifi", title: "科幻", subtitle: "奔赴未来", symbol: "sparkles", genreID: 878),
        MovieShelf(id: "genre-fantasy", title: "奇幻", subtitle: "想象世界", symbol: "wand.and.stars", genreID: 14),
        MovieShelf(id: "genre-documentary", title: "纪录片", subtitle: "真实世界", symbol: "globe.asia.australia.fill", genreID: 99),
        MovieShelf(id: "genre-family", title: "家庭", subtitle: "合家观赏", symbol: "figure.2.and.child.holdinghands", genreID: 10751),
        MovieShelf(id: "keyword-biography", title: "传记", subtitle: "真实人物", symbol: "person.text.rectangle", keywordQuery: "biography"),
        MovieShelf(id: "genre-war", title: "战争", subtitle: "战争史诗", symbol: "shield.fill", genreID: 10752),
        MovieShelf(id: "genre-history", title: "历史", subtitle: "回望时代", symbol: "building.columns.fill", genreID: 36),
        MovieShelf(id: "genre-music", title: "音乐", subtitle: "旋律人生", symbol: "music.note", genreID: 10402),
        MovieShelf(id: "keyword-sport", title: "运动", subtitle: "竞技热血", symbol: "sportscourt.fill", keywordQuery: "sport"),
        MovieShelf(id: "keyword-lgbt", title: "同性", subtitle: "多元情感", symbol: "rainbow", keywordQuery: "lgbt"),
        MovieShelf(id: "keyword-musical", title: "歌舞", subtitle: "歌舞银幕", symbol: "music.mic", keywordQuery: "musical"),
        MovieShelf(id: "keyword-costume", title: "古装", subtitle: "古代故事", symbol: "crown.fill", keywordQuery: "costume drama"),
        MovieShelf(id: "genre-western", title: "西部", subtitle: "荒野传奇", symbol: "sun.dust.fill", genreID: 37),
        MovieShelf(id: "keyword-short", title: "短片", subtitle: "短小精悍", symbol: "film.stack", keywordQuery: "short film"),
        MovieShelf(id: "keyword-wuxia", title: "武侠", subtitle: "江湖侠义", symbol: "figure.martial.arts", keywordQuery: "wuxia"),
        MovieShelf(id: "keyword-disaster", title: "灾难", subtitle: "极限求生", symbol: "tornado", keywordQuery: "disaster"),
        MovieShelf(id: "genre-animation", title: "动画", subtitle: "动画世界", symbol: "paintbrush.fill", genreID: 16)
    ]
}

struct ReleasePeriod: Identifiable, Hashable {
    let id: String
    let startYear: Int?
    let endYear: Int?

    static var options: [ReleasePeriod] {
        let currentYear = Calendar.current.component(.year, from: Date())
        return [
            ReleasePeriod(id: "all", startYear: nil, endYear: nil),
            ReleasePeriod(id: "before-2000", startYear: nil, endYear: 1999)
        ] + (2000...max(2000, currentYear)).map { year in
            ReleasePeriod(id: "year-\(year)", startYear: year, endYear: year)
        }
    }

    func title(language: AppLanguage) -> String {
        if id == "all" {
            switch language {
            case .zhCN: return "不限年代"
            case .zhHK, .zhTW: return "不限年代"
            case .enUS: return "Any year"
            case .jaJP: return "すべての年代"
            case .koKR: return "전체 연도"
            }
        }
        if id == "before-2000" {
            switch language {
            case .zhCN: return "2000 年以前"
            case .zhHK, .zhTW: return "2000 年以前"
            case .enUS: return "Before 2000"
            case .jaJP: return "2000年以前"
            case .koKR: return "2000년 이전"
            }
        }
        let year = startYear ?? 2000
        switch language {
        case .zhCN: return "\(year) 年"
        case .zhHK, .zhTW: return "\(year) 年"
        case .enUS: return "\(year)"
        case .jaJP: return "\(year)年"
        case .koKR: return "\(year)년"
        }
    }
}

struct TMDBKeyword: Codable {
    let id: Int
    let name: String
}

struct KeywordResponse: Codable {
    let results: [TMDBKeyword]
}

struct Provider: Codable, Identifiable, Hashable {
    let providerID: Int
    let providerName: String
    let logoPath: String?

    enum CodingKeys: String, CodingKey {
        case providerID = "provider_id"
        case providerName = "provider_name"
        case logoPath = "logo_path"
    }

    var id: Int { providerID }
}

struct RegionProviders: Codable {
    let link: String?
    let flatrate: [Provider]?
    let rent: [Provider]?
    let buy: [Provider]?

    var all: [Provider] {
        var seen = Set<Int>()
        return ((flatrate ?? []) + (rent ?? []) + (buy ?? [])).filter {
            seen.insert($0.providerID).inserted
        }
    }
}

struct ProviderResponse: Codable {
    let results: [String: RegionProviders]
}

struct CastMember: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let character: String
    let profilePath: String?
    let order: Int

    enum CodingKeys: String, CodingKey {
        case id, name, character, order
        case profilePath = "profile_path"
    }

    var profileURL: URL? {
        guard let profilePath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w185\(profilePath)")
    }
}

struct CrewMember: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let job: String
    let department: String

    enum CodingKeys: String, CodingKey {
        case id, name, job
        case department = "department"
    }
}

struct CreditsResponse: Codable {
    let cast: [CastMember]
    let crew: [CrewMember]?
}

struct PersonDetails: Codable, Identifiable {
    let id: Int
    let name: String
    let biography: String
    let birthday: String?
    let deathday: String?
    let placeOfBirth: String?
    let profilePath: String?
    let alsoKnownAs: [String]

    enum CodingKeys: String, CodingKey {
        case id, name, biography, birthday, deathday
        case placeOfBirth = "place_of_birth"
        case profilePath = "profile_path"
        case alsoKnownAs = "also_known_as"
    }

    var profileURL: URL? {
        guard let profilePath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/h632\(profilePath)")
    }
}

struct PersonMovieCredits: Codable {
    let cast: [Movie]
}

struct PersonTVCredits: Codable {
    let cast: [TVShow]
}

struct PersonSearchResult: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let profilePath: String?
    let knownForDepartment: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case profilePath = "profile_path"
        case knownForDepartment = "known_for_department"
    }

    var profileURL: URL? {
        guard let profilePath else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w185\(profilePath)")
    }
}

struct PersonSearchResponse: Codable {
    let results: [PersonSearchResult]
}

struct PersonImage: Codable, Identifiable, Hashable {
    let filePath: String
    let width: Int
    let height: Int
    let voteAverage: Double

    enum CodingKeys: String, CodingKey {
        case width, height
        case filePath = "file_path"
        case voteAverage = "vote_average"
    }

    var id: String { filePath }

    var imageURL: URL? {
        URL(string: "https://image.tmdb.org/t/p/w342\(filePath)")
    }

    var fullSizeURL: URL? {
        URL(string: "https://image.tmdb.org/t/p/original\(filePath)")
    }
}

enum PhotoLightboxNavigation {
    static func adjacentIndex(
        currentIndex: Int,
        offset: Int,
        count: Int
    ) -> Int? {
        guard count > 0 else { return nil }
        let nextIndex = currentIndex + offset
        guard (0..<count).contains(nextIndex) else { return nil }
        return nextIndex
    }
}

enum PhotoDownloadFilename {
    static func suggestedName(for url: URL) -> String {
        let candidate = url.lastPathComponent
        guard !candidate.isEmpty, candidate != "/" else {
            return "CineBar-photo.jpg"
        }

        let extensionName = (candidate as NSString).pathExtension
        if extensionName.isEmpty {
            return "CineBar-\(candidate).jpg"
        }
        return "CineBar-\(candidate)"
    }
}

enum PersonPhotoNavigation {
    static func adjacentIndex(
        currentIndex: Int,
        offset: Int,
        count: Int
    ) -> Int? {
        PhotoLightboxNavigation.adjacentIndex(
            currentIndex: currentIndex,
            offset: offset,
            count: count
        )
    }
}

struct PersonImagesResponse: Codable {
    let profiles: [PersonImage]
}

struct PersonExternalIDs: Codable {
    let instagramID: String?
    let twitterID: String?

    enum CodingKeys: String, CodingKey {
        case instagramID = "instagram_id"
        case twitterID = "twitter_id"
    }

    var instagramURL: URL? {
        guard let instagramID, !instagramID.isEmpty else { return nil }
        return URL(string: "https://www.instagram.com")?
            .appendingPathComponent(instagramID)
    }

    var xURL: URL? {
        guard let twitterID, !twitterID.isEmpty else { return nil }
        return URL(string: "https://x.com")?
            .appendingPathComponent(twitterID)
    }
}

struct MovieVideo: Codable, Identifiable, Hashable {
    let id: String
    let key: String
    let name: String
    let site: String
    let type: String
    let official: Bool

    var watchURL: URL? {
        guard site.caseInsensitiveCompare("YouTube") == .orderedSame else {
            return nil
        }
        return URL(string: "https://www.youtube.com/watch?v=\(key)")
    }

    func displayName(language: AppLanguage) -> String {
        let lowered = name.lowercased()
        let trailingToken = name.split(separator: " ").last.map(String.init) ?? ""
        let number = trailingToken.trimmingCharacters(
            in: CharacterSet.decimalDigits.inverted
        )
        let label: String

        if lowered.contains("international") {
            switch language {
            case .zhCN: label = "国际版预告"
            case .zhHK, .zhTW: label = "國際版預告"
            case .enUS: label = "International Trailer"
            case .jaJP: label = "海外版予告"
            case .koKR: label = "인터내셔널 예고편"
            }
        } else if lowered.contains("final") && lowered.contains("official") {
            switch language {
            case .zhCN: label = "官方终极预告"
            case .zhHK, .zhTW: label = "官方終極預告"
            case .enUS: label = "Official Final Trailer"
            case .jaJP: label = "公式最終予告"
            case .koKR: label = "공식 최종 예고편"
            }
        } else if lowered.contains("teaser") && lowered.contains("official") {
            switch language {
            case .zhCN: label = "官方先导预告"
            case .zhHK, .zhTW: label = "官方前導預告"
            case .enUS: label = "Official Teaser"
            case .jaJP: label = "公式ティザー予告"
            case .koKR: label = "공식 티저 예고편"
            }
        } else if lowered.contains("official") && lowered.contains("trailer") {
            switch language {
            case .zhCN: label = "官方正式预告"
            case .zhHK, .zhTW: label = "官方正式預告"
            case .enUS: label = "Official Trailer"
            case .jaJP: label = "公式予告"
            case .koKR: label = "공식 예고편"
            }
        } else if lowered.contains("final") {
            switch language {
            case .zhCN: label = "终极预告"
            case .zhHK, .zhTW: label = "終極預告"
            case .enUS: label = "Final Trailer"
            case .jaJP: label = "最終予告"
            case .koKR: label = "최종 예고편"
            }
        } else if lowered.contains("teaser") {
            switch language {
            case .zhCN: label = "先导预告"
            case .zhHK, .zhTW: label = "前導預告"
            case .enUS: label = "Teaser"
            case .jaJP: label = "ティザー予告"
            case .koKR: label = "티저 예고편"
            }
        } else if lowered == "trailer" {
            switch language {
            case .zhCN: label = "预告片"
            case .zhHK, .zhTW: label = "預告片"
            case .enUS: label = "Trailer"
            case .jaJP: label = "予告編"
            case .koKR: label = "예고편"
            }
        } else {
            return localizedQualifiers(language: language)
        }

        return number.isEmpty ? label : "\(label) #\(number)"
    }

    private func localizedQualifiers(language: AppLanguage) -> String {
        let replacements: [(String, String)]
        switch language {
        case .zhCN:
            replacements = [
                ("English Subtitles", "英文字幕版"),
                ("Subtitled", "字幕版"),
                ("Dubbed", "配音版"),
                ("Official Clip", "官方片段")
            ]
        case .zhHK, .zhTW:
            replacements = [
                ("English Subtitles", "英文字幕版"),
                ("Subtitled", "字幕版"),
                ("Dubbed", "配音版"),
                ("Official Clip", "官方片段")
            ]
        case .enUS:
            replacements = [
                ("English Subtitles", "English Subtitles"),
                ("Subtitled", "Subtitled"),
                ("Dubbed", "Dubbed"),
                ("Official Clip", "Official Clip")
            ]
        case .jaJP:
            replacements = [
                ("English Subtitles", "英語字幕版"),
                ("Subtitled", "字幕版"),
                ("Dubbed", "吹替版"),
                ("Official Clip", "公式クリップ")
            ]
        case .koKR:
            replacements = [
                ("English Subtitles", "영어 자막판"),
                ("Subtitled", "자막판"),
                ("Dubbed", "더빙판"),
                ("Official Clip", "공식 클립")
            ]
        }

        return replacements.reduce(name) { result, replacement in
            result.replacingOccurrences(
                of: replacement.0,
                with: replacement.1,
                options: .caseInsensitive
            )
        }
    }
}

struct VideoResponse: Codable {
    let results: [MovieVideo]
}

struct ProductionCountry: Codable, Hashable {
    let isoCode: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case isoCode = "iso_3166_1"
        case name
    }
}

struct MovieFinancials: Codable {
    let revenue: Int64
    let budget: Int64
    let runtime: Int?
    let imdbID: String?
    let releaseDate: String?
    let productionCountries: [ProductionCountry]?

    enum CodingKeys: String, CodingKey {
        case revenue, budget, runtime
        case imdbID = "imdb_id"
        case releaseDate = "release_date"
        case productionCountries = "production_countries"
    }
}

struct MovieReleaseEvent: Codable {
    let type: Int
    let releaseDate: String
    let certification: String?
    let note: String?

    enum CodingKeys: String, CodingKey {
        case type, certification
        case releaseDate = "release_date"
        case note
    }
}

struct CountryReleaseDates: Codable {
    let isoCode: String
    let releaseDates: [MovieReleaseEvent]

    enum CodingKeys: String, CodingKey {
        case isoCode = "iso_3166_1"
        case releaseDates = "release_dates"
    }
}

struct MovieReleaseDatesResponse: Codable {
    let results: [CountryReleaseDates]
}

enum MovieReleaseDatePolicy {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }()

    static func normalizedDate(_ rawValue: String) -> String? {
        let value = String(rawValue.prefix(10))
        guard value.count == 10,
              let date = dateFormatter.date(from: value),
              dateFormatter.string(from: date) == value
        else { return nil }
        return value
    }

    static func todayString(_ date: Date = Date()) -> String {
        dateFormatter.string(from: date)
    }

    static func preferredDate(
        from events: [MovieReleaseEvent],
        today: String? = nil
    ) -> String? {
        let dates = events
            .filter { (1...3).contains($0.type) }
            .compactMap { normalizedDate($0.releaseDate) }
        return preferredDate(from: dates, today: today)
    }

    static func preferredDate(
        from dates: [String],
        today: String? = nil
    ) -> String? {
        let sorted = Set(dates.compactMap(normalizedDate)).sorted()
        guard !sorted.isEmpty else { return nil }
        let reference = today ?? todayString()
        return sorted.first(where: { $0 >= reference }) ?? sorted.last
    }
}

struct MovieReleaseSummary {
    let globalPremiere: String?
    let localizedRelease: String?
    let localizedReleaseDates: [String]
    let localizedRegion: String
    let contentRating: ContentRatingSummary?
}

struct CalendarReleaseEventDetails: Equatable {
    let title: String
    let dateText: String
    let region: String
    let notes: String
    let alarmOffset: TimeInterval
}

enum CalendarReleaseEventComposer {
    static func shouldOffer(
        dateText: String,
        today: String? = nil
    ) -> Bool {
        guard let normalizedDate = MovieReleaseDatePolicy.normalizedDate(
            dateText
        ) else { return false }
        let reference = MovieReleaseDatePolicy.normalizedDate(
            today ?? MovieReleaseDatePolicy.todayString()
        )
        guard let reference else { return false }
        return normalizedDate >= reference
    }

    static func make(
        title: String,
        dateText: String,
        region: String,
        language: AppLanguage,
        today: String? = nil
    ) -> CalendarReleaseEventDetails? {
        guard let normalizedDate = MovieReleaseDatePolicy.normalizedDate(
            dateText
        ), shouldOffer(dateText: normalizedDate, today: today) else {
            return nil
        }

        let eventTitle: String
        let notes: String
        switch language {
        case .zhCN:
            eventTitle = "《\(title)》上映"
            notes = "CineBar 上映提醒\n地区：\(region)\n上映日期：\(normalizedDate)"
        case .zhHK, .zhTW:
            eventTitle = "《\(title)》上映"
            notes = "CineBar 上映提醒\n地區：\(region)\n上映日期：\(normalizedDate)"
        case .enUS:
            eventTitle = "\(title) release"
            notes = "CineBar release reminder\nRegion: \(region)\nRelease date: \(normalizedDate)"
        case .jaJP:
            eventTitle = "\(title) 公開"
            notes = "CineBar 公開リマインダー\n地域：\(region)\n公開日：\(normalizedDate)"
        case .koKR:
            eventTitle = "\(title) 개봉"
            notes = "CineBar 개봉 알림\n지역: \(region)\n개봉일: \(normalizedDate)"
        }

        return CalendarReleaseEventDetails(
            title: eventTitle,
            dateText: normalizedDate,
            region: region,
            notes: notes,
            alarmOffset: -86_400
        )
    }
}

enum CalendarReleaseEventError: LocalizedError {
    case accessDenied
    case noCalendar
    case invalidDate

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "没有获得日历访问权限，请在系统设置中允许 CineBar 访问日历。"
        case .noCalendar:
            return "没有可写入的日历，请先在日历 App 中添加一个日历。"
        case .invalidDate:
            return "上映日期格式无效，无法创建日历事件。"
        }
    }
}

@MainActor
final class CalendarReleaseEventService {
    static let shared = CalendarReleaseEventService()

    private init() {}

    func add(_ details: CalendarReleaseEventDetails) async throws {
        let eventStore = EKEventStore()
        let granted: Bool
        if #available(macOS 14.0, *) {
            granted = try await eventStore.requestFullAccessToEvents()
        } else {
            granted = try await requestLegacyAccess(eventStore)
        }
        guard granted else { throw CalendarReleaseEventError.accessDenied }
        guard let calendar = eventStore.defaultCalendarForNewEvents else {
            throw CalendarReleaseEventError.noCalendar
        }

        let calendarSystem = Calendar(identifier: .gregorian)
        let components = details.dateText.split(separator: "-").compactMap {
            Int($0)
        }
        guard components.count == 3,
              let startDate = calendarSystem.date(
                  from: DateComponents(
                      calendar: calendarSystem,
                      timeZone: .current,
                      year: components[0],
                      month: components[1],
                      day: components[2]
                  )
              ),
              let endDate = calendarSystem.date(
                  byAdding: .day,
                  value: 1,
                  to: startDate
              ) else {
            throw CalendarReleaseEventError.invalidDate
        }

        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = details.title
        event.notes = details.notes
        event.startDate = startDate
        event.endDate = endDate
        event.isAllDay = true
        event.addAlarm(EKAlarm(relativeOffset: details.alarmOffset))
        try eventStore.save(event, span: .thisEvent)

        let calendarURL = URL(fileURLWithPath: "/System/Applications/Calendar.app")
        if !NSWorkspace.shared.open(calendarURL) {
            _ = NSWorkspace.shared.open(
                URL(fileURLWithPath: "/Applications/Calendar.app")
            )
        }
    }

    @available(macOS, deprecated: 14.0)
    private func requestLegacyAccess(_ eventStore: EKEventStore) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            eventStore.requestAccess(to: .event) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }
}

struct MovieStill: Codable, Identifiable, Hashable {
    let filePath: String
    let width: Int
    let height: Int
    let voteAverage: Double
    let voteCount: Int

    enum CodingKeys: String, CodingKey {
        case width, height
        case filePath = "file_path"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
    }

    var id: String { filePath }

    var imageURL: URL? {
        URL(string: "https://image.tmdb.org/t/p/w780\(filePath)")
    }

    var fullSizeURL: URL? {
        URL(string: "https://image.tmdb.org/t/p/original\(filePath)")
    }
}

struct MovieImagesResponse: Codable {
    let backdrops: [MovieStill]
}

struct ExternalIDsResponse: Codable {
    let imdbID: String?

    enum CodingKeys: String, CodingKey {
        case imdbID = "imdb_id"
    }
}

struct OMDbRating: Codable {
    let source: String
    let value: String

    enum CodingKeys: String, CodingKey {
        case source = "Source"
        case value = "Value"
    }
}

struct OMDbMovieResponse: Codable {
    let ratings: [OMDbRating]?
    let response: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case ratings = "Ratings"
        case response = "Response"
        case error = "Error"
    }
}

struct MovieRating: Identifiable, Hashable {
    let source: String
    let value: String
    let note: String
    var url: URL? = nil
    var id: String { source }

    /// 只保留分数本体（去掉 “/10” 与空格），如 “8.2/10” → “8.2”。
    var compactValue: String {
        value
            .replacingOccurrences(of: " / 10", with: "")
            .replacingOccurrences(of: "/10", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
}

struct TMDBCountry: Codable, Identifiable, Hashable {
    let isoCode: String
    let englishName: String
    let nativeName: String

    enum CodingKeys: String, CodingKey {
        case isoCode = "iso_3166_1"
        case englishName = "english_name"
        case nativeName = "native_name"
    }

    var id: String { isoCode }

    func displayName(language: AppLanguage) -> String {
        let locale = Locale(identifier: language.localeIdentifier)
        return locale.localizedString(forRegionCode: isoCode) ??
            (nativeName.isEmpty ? englishName : nativeName)
    }
}

struct TVContentRating: Codable {
    let isoCode: String
    let rating: String

    enum CodingKeys: String, CodingKey {
        case isoCode = "iso_3166_1"
        case rating
    }
}

struct TVContentRatingsResponse: Codable {
    let results: [TVContentRating]
}

struct ContentRatingSummary: Hashable {
    let region: String
    let original: String
    let cineBar: String

    var displayText: String {
        original.isEmpty ? cineBar : "\(region) \(original) · CineBar \(cineBar)"
    }

    static func normalizedAge(for value: String) -> String {
        let rating = value.uppercased()
            .replacingOccurrences(of: " ", with: "")
        if rating.isEmpty { return "未分级" }
        if ["G", "TV-G", "TV-Y", "U", "0", "ALL", "TP"].contains(rating) {
            return "全年龄"
        }
        if rating.contains("18") || ["NC-17", "TV-MA", "R18+", "R21"].contains(rating) {
            return "18+"
        }
        if rating.contains("16") || rating == "MA15+" { return "16+" }
        if rating.contains("15") || rating == "R" { return "15+" }
        if rating.contains("14") || rating == "TV-14" { return "14+" }
        if rating.contains("13") || rating == "PG-13" { return "13+" }
        if rating.contains("12") || rating == "12A" { return "12+" }
        if rating.contains("10") { return "10+" }
        if rating.contains("7") || ["PG", "TV-PG", "TV-Y7"].contains(rating) {
            return "家长指导"
        }
        return "未分级"
    }
}

struct ContentRatingPresentation {
    let regionLabel: String
    let officialValue: String
    let cineBarValue: String

    init(_ rating: ContentRatingSummary?) {
        regionLabel = rating?.region.isEmpty == false
            ? rating?.region ?? "地区分级"
            : "地区分级"
        officialValue = rating?.original.isEmpty == false
            ? rating?.original ?? "未分级"
            : "未分级"
        cineBarValue = rating?.cineBar.isEmpty == false
            ? rating?.cineBar ?? "未分级"
            : "未分级"
    }
}

struct CommunityRatingSummary: Codable, Hashable {
    let mediaType: String
    let mediaID: Int
    let averageScore: Double?
    let total: Int
    let myScore: Double?

    enum CodingKeys: String, CodingKey {
        case total
        case mediaType = "media_type"
        case mediaID = "media_id"
        case averageScore = "average_score"
        case myScore = "my_score"
    }
}

enum RatingPresentation {
    static func shouldShowEditor(
        myScore: Double?,
        isLoading: Bool
    ) -> Bool {
        myScore == nil && !isLoading
    }
}

enum GlassBackgroundOpacity {
    static let defaultsKey = "glassBackgroundOpacity"
    static let defaultValue = 0.85
    static let range = 0.5...1.0

    static func normalized(_ value: Double?) -> Double {
        min(
            max(value ?? defaultValue, range.lowerBound),
            range.upperBound
        )
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "白天"
        case .dark: return "夜晚"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case zhCN
    case zhHK
    case zhTW
    case enUS
    case jaJP
    case koKR

    var id: String { rawValue }

    var title: String {
        switch self {
        case .zhCN: return "中文（简体）"
        case .zhHK: return "中文（繁體・香港）"
        case .zhTW: return "中文（繁體・台灣）"
        case .enUS: return "English (US)"
        case .jaJP: return "日本語"
        case .koKR: return "한국어"
        }
    }

    var apiCode: String {
        switch self {
        case .zhCN: return "zh-CN"
        case .zhHK: return "zh-HK"
        case .zhTW: return "zh-TW"
        case .enUS: return "en-US"
        case .jaJP: return "ja-JP"
        case .koKR: return "ko-KR"
        }
    }

    var localeIdentifier: String {
        switch self {
        case .zhCN: return "zh-Hans"
        case .zhHK: return "zh-Hant-HK"
        case .zhTW: return "zh-Hant-TW"
        case .enUS: return "en"
        case .jaJP: return "ja"
        case .koKR: return "ko"
        }
    }

    var releaseRegion: String {
        switch self {
        case .zhCN: return "CN"
        case .zhHK: return "HK"
        case .zhTW: return "TW"
        case .enUS: return "US"
        case .jaJP: return "JP"
        case .koKR: return "KR"
        }
    }
}

enum AutoHideInterval: Int, CaseIterable, Identifiable {
    case fifteenSeconds = 15
    case thirtySeconds = 30
    case oneMinute = 60
    case twoMinutes = 120
    case fiveMinutes = 300
    case never = 0

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .fifteenSeconds: return "15 秒"
        case .thirtySeconds: return "30 秒"
        case .oneMinute: return "1 分钟"
        case .twoMinutes: return "2 分钟"
        case .fiveMinutes: return "5 分钟"
        case .never: return "永不"
        }
    }
}

extension Notification.Name {
    static let cineBarAppearanceDidChange = Notification.Name(
        "CineBarAppearanceDidChange"
    )
    static let cineBarAutoHideDidChange = Notification.Name(
        "CineBarAutoHideDidChange"
    )
    static let cineBarPanelMovementDidChange = Notification.Name(
        "CineBarPanelMovementDidChange"
    )
    static let cineBarMediaPlaybackDidChange = Notification.Name(
        "CineBarMediaPlaybackDidChange"
    )
    static let cineBarPanelWillHide = Notification.Name(
        "CineBarPanelWillHide"
    )
    static let cineBarOpenSettings = Notification.Name(
        "CineBarOpenSettings"
    )
    static let cineBarShowMainPanel = Notification.Name(
        "CineBarShowMainPanel"
    )
}

enum CineBarError: LocalizedError {
    case missingToken
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "请先填写 TMDB API Read Access Token"
        case .invalidResponse:
            return "服务器返回了无法识别的数据"
        case .server(let message):
            return message
        }
    }
}

enum CommunityRatingError: LocalizedError {
    case alreadyRated

    var errorDescription: String? {
        switch self {
        case .alreadyRated:
            return "这部影片已经评分，不能重复评分"
        }
    }
}

enum DataProxyConfiguration {
    static func normalizedBaseURL(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.hasPrefix("https://") ||
                cleaned.hasPrefix("http://localhost") else {
            return nil
        }
        while cleaned.hasSuffix("/") {
            cleaned.removeLast()
        }
        guard let components = URLComponents(string: cleaned),
              components.host != nil
        else { return nil }
        return cleaned
    }
}

enum OMDbEndpoint {
    static func url(
        proxyBaseURL: String?,
        apiKey: String,
        imdbID: String
    ) -> URL? {
        guard imdbID.range(
            of: #"^tt\d{7,10}$"#,
            options: .regularExpression
        ) != nil else { return nil }

        if let proxy = DataProxyConfiguration.normalizedBaseURL(
            proxyBaseURL
        ), var components = URLComponents(string: "\(proxy)/omdb") {
            components.queryItems = [
                URLQueryItem(name: "i", value: imdbID)
            ]
            return components.url
        }

        let cleanedKey = apiKey.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !cleanedKey.isEmpty,
              var components = URLComponents(
                string: "https://www.omdbapi.com/"
              )
        else { return nil }
        components.queryItems = [
            URLQueryItem(name: "apikey", value: cleanedKey),
            URLQueryItem(name: "i", value: imdbID),
            URLQueryItem(name: "r", value: "json")
        ]
        return components.url
    }
}

struct DataSettingsPresentation {
    let proxyBaseURL: String?

    var usesBuiltInService: Bool {
        DataProxyConfiguration.normalizedBaseURL(proxyBaseURL) != nil
    }

    var showsCredentialFields: Bool {
        !usesBuiltInService
    }

    func serviceTitle(language: AppLanguage) -> String {
        switch language {
        case .zhCN: return "内置影片与评分服务已启用"
        case .zhHK, .zhTW: return "內建影片與評分服務已啟用"
        case .enUS: return "Built-in movie and rating service enabled"
        case .jaJP: return "内蔵の作品・評価サービスが有効です"
        case .koKR: return "내장 영화 및 평점 서비스가 활성화되었습니다"
        }
    }

    func serviceDetail(language: AppLanguage) -> String {
        switch language {
        case .zhCN: return "无需申请密钥或部署服务，TMDB 与 OMDb 已由 CineBar 安全连接。"
        case .zhHK, .zhTW: return "無需申請金鑰或部署服務，TMDB 與 OMDb 已由 CineBar 安全連線。"
        case .enUS: return "No API keys or deployment required. CineBar securely connects TMDB and OMDb."
        case .jaJP: return "APIキーや導入作業は不要です。CineBarがTMDBとOMDbへ安全に接続します。"
        case .koKR: return "API 키나 배포가 필요하지 않습니다. CineBar가 TMDB와 OMDb에 안전하게 연결합니다."
        }
    }
}

struct TMDBClient {
    let token: String
    let language: String

    private var proxyBaseURL: String? {
        let raw = Bundle.main.object(
            forInfoDictionaryKey: "CineBarDataProxyURL"
        ) as? String
        return DataProxyConfiguration.normalizedBaseURL(raw)
    }

    func trending(page: Int = 1) async throws -> MoviePageResult {
        let response: MovieResponse = try await request(
            path: "/trending/movie/week",
            query: [
                URLQueryItem(name: "language", value: language),
                URLQueryItem(name: "page", value: String(page))
            ]
        )
        return MoviePageResult(
            movies: response.results,
            page: response.page ?? page,
            totalPages: response.totalPages ?? page
        )
    }

    func upcomingMovies(
        region: String,
        page: Int = 1
    ) async throws -> MoviePageResult {
        let response: MovieResponse = try await request(
            path: "/movie/upcoming",
            query: [
                URLQueryItem(name: "language", value: language),
                URLQueryItem(name: "region", value: region),
                URLQueryItem(name: "page", value: String(page))
            ]
        )
        let movies = await enrichUpcomingReleaseDates(
            response.results,
            region: region
        )
        return MoviePageResult(
            movies: movies,
            page: response.page ?? page,
            totalPages: response.totalPages ?? page
        )
    }

    private func enrichUpcomingReleaseDates(
        _ movies: [Movie],
        region: String
    ) async -> [Movie] {
        guard !movies.isEmpty, !region.isEmpty else {
            return UpcomingMovieSorting.sorted(movies)
        }

        var enriched = movies
        let batchSize = 6
        var start = 0
        while start < movies.count {
            let end = min(start + batchSize, movies.count)
            let batch = Array(movies[start..<end])
            await withTaskGroup(of: (Int, String?, String?).self) { group in
                for movie in batch {
                    group.addTask {
                        guard movie.id > 0 else {
                            return (movie.id, nil, nil)
                        }
                        do {
                            let response = try await self.releaseDates(
                                movieID: movie.id
                            )
                            let events = response.results
                                .first { $0.isoCode == region }?
                                .releaseDates ?? []
                            let date = MovieReleaseDatePolicy.preferredDate(
                                from: events
                            )
                            let note = events.first {
                                MovieReleaseDatePolicy.normalizedDate(
                                    $0.releaseDate
                                ) == date &&
                                    (1...3).contains($0.type)
                            }?.note
                            return (movie.id, date, note)
                        } catch {
                            return (movie.id, nil, nil)
                        }
                    }
                }

                for await (id, date, note) in group {
                    guard let index = enriched.firstIndex(where: { $0.id == id })
                    else { continue }
                    enriched[index].localizedReleaseDate = date
                    enriched[index].localizedReleaseNote = note
                }
            }
            start = end
        }
        return UpcomingMovieSorting.sorted(enriched)
    }

    func search(_ text: String) async throws -> [Movie] {
        let response: MovieResponse = try await request(
            path: "/search/movie",
            query: [
                URLQueryItem(name: "language", value: language),
                URLQueryItem(name: "query", value: text),
                URLQueryItem(name: "include_adult", value: "false")
            ]
        )
        return response.results
    }

    func discover(_ shelf: MovieShelf) async throws -> [Movie] {
        var query = [
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "include_adult", value: "false"),
            URLQueryItem(name: "include_video", value: "false"),
            URLQueryItem(name: "sort_by", value: "popularity.desc"),
            URLQueryItem(name: "vote_count.gte", value: "80")
        ]
        if let year = shelf.year {
            query.append(URLQueryItem(name: "primary_release_year", value: String(year)))
        }
        if let genreID = shelf.genreID {
            query.append(URLQueryItem(name: "with_genres", value: String(genreID)))
        }
        if let releaseDateFrom = shelf.releaseDateFrom {
            query.append(URLQueryItem(name: "primary_release_date.gte", value: releaseDateFrom))
        }
        if let releaseDateTo = shelf.releaseDateTo {
            query.append(URLQueryItem(name: "primary_release_date.lte", value: releaseDateTo))
        }

        let response: MovieResponse = try await request(
            path: "/discover/movie",
            query: query
        )
        return response.results
    }

    func discover(
        startYear: Int?,
        endYear: Int?,
        genreIDs: [Int],
        keywordQueries: [String],
        originCountry: String?,
        sortMode: CatalogSortMode,
        page: Int = 1
    ) async throws -> MoviePageResult {
        var query = [
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "include_adult", value: "false"),
            URLQueryItem(name: "include_video", value: "false"),
            URLQueryItem(name: "sort_by", value: sortMode.apiValue),
            URLQueryItem(name: "vote_count.gte", value: "80"),
            URLQueryItem(name: "page", value: String(page))
        ]
        if let startYear {
            query.append(
                URLQueryItem(
                    name: "primary_release_date.gte",
                    value: "\(startYear)-01-01"
                )
            )
        }
        if let endYear {
            query.append(
                URLQueryItem(
                    name: "primary_release_date.lte",
                    value: "\(endYear)-12-31"
                )
            )
        }
        if !genreIDs.isEmpty {
            query.append(
                URLQueryItem(
                    name: "with_genres",
                    value: genreIDs.map(String.init).joined(separator: "|")
                )
            )
        }
        if let originCountry, !originCountry.isEmpty {
            query.append(
                URLQueryItem(name: "with_origin_country", value: originCountry)
            )
        }
        var keywordIDs: [Int] = []
        for keywordQuery in keywordQueries {
            if let keywordID = try await keywordID(matching: keywordQuery) {
                keywordIDs.append(keywordID)
            }
        }
        if !keywordIDs.isEmpty {
            query.append(
                URLQueryItem(
                    name: "with_keywords",
                    value: keywordIDs.map(String.init).joined(separator: "|")
                )
            )
        }
        let response: MovieResponse = try await request(
            path: "/discover/movie",
            query: query
        )
        return MoviePageResult(
            movies: response.results,
            page: response.page ?? page,
            totalPages: response.totalPages ?? page
        )
    }

    private func keywordID(matching text: String) async throws -> Int? {
        let response: KeywordResponse = try await request(
            path: "/search/keyword",
            query: [
                URLQueryItem(name: "query", value: text),
                URLQueryItem(name: "page", value: "1")
            ]
        )
        let normalized = text.lowercased()
        return response.results.first {
            $0.name.lowercased() == normalized
        }?.id ?? response.results.first?.id
    }

    func recommendationCandidates(
        genreIDs: [Int],
        originCountries: [String],
        page: Int,
        latestReleaseDate: String
    ) async throws -> [Movie] {
        var query = [
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "include_adult", value: "false"),
            URLQueryItem(name: "include_video", value: "false"),
            URLQueryItem(name: "sort_by", value: "vote_average.desc"),
            URLQueryItem(name: "vote_count.gte", value: "600"),
            URLQueryItem(name: "primary_release_date.lte", value: latestReleaseDate),
            URLQueryItem(name: "page", value: String(page))
        ]
        if !genreIDs.isEmpty {
            query.append(
                URLQueryItem(
                    name: "with_genres",
                    value: genreIDs.map(String.init).joined(separator: "|")
                )
            )
        }
        if !originCountries.isEmpty {
            query.append(
                URLQueryItem(
                    name: "with_origin_country",
                    value: originCountries.joined(separator: "|")
                )
            )
        }
        let response: MovieResponse = try await request(
            path: "/discover/movie",
            query: query
        )
        return response.results
    }

    func providers(movieID: Int) async throws -> [String: RegionProviders] {
        let response: ProviderResponse = try await request(
            path: "/movie/\(movieID)/watch/providers",
            query: []
        )
        return response.results
    }

    func releaseDates(movieID: Int) async throws -> MovieReleaseDatesResponse {
        try await request(
            path: "/movie/\(movieID)/release_dates",
            query: []
        )
    }

    func credits(movieID: Int) async throws -> CreditsResponse {
        try await request(
            path: "/movie/\(movieID)/credits",
            query: [URLQueryItem(name: "language", value: language)]
        )
    }

    func cast(movieID: Int) async throws -> [CastMember] {
        let response: CreditsResponse = try await request(
            path: "/movie/\(movieID)/credits",
            query: [URLQueryItem(name: "language", value: language)]
        )
        return response.cast
            .filter { !$0.name.isEmpty }
            .sorted { $0.order < $1.order }
    }

    func personDetails(personID: Int) async throws -> PersonDetails {
        let localized: PersonDetails = try await request(
            path: "/person/\(personID)",
            query: [URLQueryItem(name: "language", value: language)]
        )
        guard localized.biography.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty, language != "en-US" else {
            return localized
        }
        let english: PersonDetails = try await request(
            path: "/person/\(personID)",
            query: [URLQueryItem(name: "language", value: "en-US")]
        )
        return PersonDetails(
            id: localized.id,
            name: localized.name,
            biography: english.biography,
            birthday: localized.birthday ?? english.birthday,
            deathday: localized.deathday ?? english.deathday,
            placeOfBirth: localized.placeOfBirth ?? english.placeOfBirth,
            profilePath: localized.profilePath ?? english.profilePath,
            alsoKnownAs: localized.alsoKnownAs.isEmpty
                ? english.alsoKnownAs
                : localized.alsoKnownAs
        )
    }

    func personMovies(personID: Int) async throws -> [Movie] {
        let response: PersonMovieCredits = try await request(
            path: "/person/\(personID)/movie_credits",
            query: [URLQueryItem(name: "language", value: language)]
        )
        var seen = Set<Int>()
        return response.cast
            .filter { movie in
                movie.id > 0 && seen.insert(movie.id).inserted
            }
            .sorted {
                if $0.voteCount != $1.voteCount {
                    return $0.voteCount > $1.voteCount
                }
                return ($0.releaseDate ?? "") > ($1.releaseDate ?? "")
            }
    }

    func personTelevision(personID: Int) async throws -> [TVShow] {
        let response: PersonTVCredits = try await request(
            path: "/person/\(personID)/tv_credits",
            query: [URLQueryItem(name: "language", value: language)]
        )
        var seen = Set<Int>()
        return response.cast
            .filter { show in
                show.id > 0 && seen.insert(show.id).inserted
            }
            .sorted {
                if $0.voteCount != $1.voteCount {
                    return $0.voteCount > $1.voteCount
                }
                return ($0.firstAirDate ?? "") > ($1.firstAirDate ?? "")
            }
    }

    func searchPeople(_ text: String) async throws -> [PersonSearchResult] {
        let response: PersonSearchResponse = try await request(
            path: "/search/person",
            query: [
                URLQueryItem(name: "language", value: language),
                URLQueryItem(name: "query", value: text),
                URLQueryItem(name: "include_adult", value: "false")
            ]
        )
        return response.results
            .filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    func personImages(personID: Int) async throws -> [PersonImage] {
        let response: PersonImagesResponse = try await request(
            path: "/person/\(personID)/images",
            query: []
        )
        return response.profiles.sorted {
            if $0.voteAverage != $1.voteAverage {
                return $0.voteAverage > $1.voteAverage
            }
            return $0.width * $0.height > $1.width * $1.height
        }
    }

    func personExternalIDs(personID: Int) async throws -> PersonExternalIDs {
        try await request(
            path: "/person/\(personID)/external_ids",
            query: []
        )
    }

    func trailers(movieID: Int) async throws -> [MovieVideo] {
        let localized: VideoResponse = try await request(
            path: "/movie/\(movieID)/videos",
            query: [URLQueryItem(name: "language", value: language)]
        )
        var candidates = localized.results
        if candidates.isEmpty && language != "en-US" {
            let english: VideoResponse = try await request(
                path: "/movie/\(movieID)/videos",
                query: [URLQueryItem(name: "language", value: "en-US")]
            )
            candidates = english.results
        }
        return candidates
            .filter {
                $0.site.caseInsensitiveCompare("YouTube") == .orderedSame &&
                ($0.type == "Trailer" || $0.type == "Teaser")
            }
            .sorted {
                if $0.official != $1.official {
                    return $0.official && !$1.official
                }
                if $0.type != $1.type {
                    return $0.type == "Trailer"
                }
                return $0.name < $1.name
            }
    }

    func financials(movieID: Int) async throws -> MovieFinancials {
        try await request(
            path: "/movie/\(movieID)",
            query: [URLQueryItem(name: "language", value: language)]
        )
    }

    func releaseSummary(
        movieID: Int,
        localizedRegion: String,
        certificationRegion: String? = nil,
        originRegions: [String] = []
    ) async throws -> MovieReleaseSummary {
        let response = try await releaseDates(movieID: movieID)
        let theatricalTypes = 1...3
        let globalDates = response.results.flatMap(\.releaseDates)
            .filter { theatricalTypes.contains($0.type) }
            .compactMap { MovieReleaseDatePolicy.normalizedDate($0.releaseDate) }
            .sorted()
        let localEvents = response.results
            .first { $0.isoCode == localizedRegion }?
            .releaseDates
            .filter { theatricalTypes.contains($0.type) }
            ?? []
        let localDates = localEvents.compactMap {
            MovieReleaseDatePolicy.normalizedDate($0.releaseDate)
        }.sorted()
        let preferredRegions = [
            certificationRegion ?? localizedRegion
        ] + originRegions + ["US"]
        let selectedCertification = preferredRegions.lazy.compactMap { code in
            response.results.first { $0.isoCode == code }?
                .releaseDates
                .compactMap(\.certification)
                .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .map { (code, $0) }
        }.first
        return MovieReleaseSummary(
            globalPremiere: globalDates.first,
            localizedRelease: MovieReleaseDatePolicy.preferredDate(
                from: localEvents
            ),
            localizedReleaseDates: localDates,
            localizedRegion: localizedRegion,
            contentRating: selectedCertification.map {
                ContentRatingSummary(
                    region: $0.0,
                    original: $0.1,
                    cineBar: ContentRatingSummary.normalizedAge(for: $0.1)
                )
            }
        )
    }

    func countries() async throws -> [TMDBCountry] {
        let result: [TMDBCountry] = try await request(
            path: "/configuration/countries",
            query: [URLQueryItem(name: "language", value: language)]
        )
        return result
    }

    func stills(movieID: Int) async throws -> [MovieStill] {
        let languageCode = String(language.prefix(2))
        let response: MovieImagesResponse = try await request(
            path: "/movie/\(movieID)/images",
            query: [
                URLQueryItem(name: "language", value: language),
                URLQueryItem(
                    name: "include_image_language",
                    value: "\(languageCode),en,null"
                )
            ]
        )
        return response.backdrops.sorted {
            if $0.voteCount != $1.voteCount {
                return $0.voteCount > $1.voteCount
            }
            return $0.voteAverage > $1.voteAverage
        }
    }

    func externalIDs(movieID: Int) async throws -> ExternalIDsResponse {
        try await request(
            path: "/movie/\(movieID)/external_ids",
            query: []
        )
    }

    func trendingTV(page: Int = 1) async throws -> TVPageResult {
        let response: TVResponse = try await request(
            path: "/trending/tv/week",
            query: [
                URLQueryItem(name: "language", value: language),
                URLQueryItem(name: "page", value: String(page))
            ]
        )
        return TVPageResult(
            shows: response.results,
            page: response.page ?? page,
            totalPages: response.totalPages ?? page
        )
    }

    func airingTodayTV(
        region: String,
        page: Int = 1
    ) async throws -> TVPageResult {
        let response: TVResponse = try await request(
            path: "/tv/airing_today",
            query: [
                URLQueryItem(name: "language", value: language),
                URLQueryItem(name: "timezone", value: TimeZone.current.identifier),
                URLQueryItem(name: "page", value: String(page))
            ]
        )
        return TVPageResult(
            shows: response.results,
            page: response.page ?? page,
            totalPages: response.totalPages ?? page
        )
    }

    func tvRecommendationCandidates(
        genreIDs: [Int],
        originCountries: [String],
        page: Int
    ) async throws -> [TVShow] {
        var query = [
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "include_adult", value: "false"),
            URLQueryItem(name: "sort_by", value: "vote_average.desc"),
            URLQueryItem(name: "vote_count.gte", value: "250"),
            URLQueryItem(name: "page", value: String(page))
        ]
        if !genreIDs.isEmpty {
            query.append(
                URLQueryItem(
                    name: "with_genres",
                    value: genreIDs.map(String.init).joined(separator: "|")
                )
            )
        }
        if !originCountries.isEmpty {
            query.append(
                URLQueryItem(
                    name: "with_origin_country",
                    value: originCountries.joined(separator: "|")
                )
            )
        }
        let response: TVResponse = try await request(
            path: "/discover/tv",
            query: query
        )
        return response.results
    }

    func searchTV(_ text: String) async throws -> [TVShow] {
        let response: TVResponse = try await request(
            path: "/search/tv",
            query: [
                URLQueryItem(name: "language", value: language),
                URLQueryItem(name: "query", value: text),
                URLQueryItem(name: "include_adult", value: "false")
            ]
        )
        return response.results
    }

    func discoverTV(
        startYear: Int?,
        endYear: Int?,
        genreID: Int?,
        originCountry: String?,
        sortMode: CatalogSortMode,
        page: Int = 1
    ) async throws -> TVPageResult {
        var query = [
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "include_adult", value: "false"),
            URLQueryItem(name: "sort_by", value: sortMode.apiValue),
            URLQueryItem(name: "vote_count.gte", value: "40"),
            URLQueryItem(name: "page", value: String(page))
        ]
        if let startYear {
            query.append(
                URLQueryItem(
                    name: "first_air_date.gte",
                    value: "\(startYear)-01-01"
                )
            )
        }
        if let endYear {
            query.append(
                URLQueryItem(
                    name: "first_air_date.lte",
                    value: "\(endYear)-12-31"
                )
            )
        }
        if let genreID {
            query.append(
                URLQueryItem(name: "with_genres", value: String(genreID))
            )
        }
        if let originCountry, !originCountry.isEmpty {
            query.append(
                URLQueryItem(name: "with_origin_country", value: originCountry)
            )
        }
        let response: TVResponse = try await request(
            path: "/discover/tv",
            query: query
        )
        return TVPageResult(
            shows: response.results,
            page: response.page ?? page,
            totalPages: response.totalPages ?? page
        )
    }

    func tvDetails(showID: Int) async throws -> TVDetails {
        try await request(
            path: "/tv/\(showID)",
            query: [URLQueryItem(name: "language", value: language)]
        )
    }

    func tvContentRating(
        showID: Int,
        localizedRegion: String,
        originRegions: [String]
    ) async throws -> ContentRatingSummary? {
        let response: TVContentRatingsResponse = try await request(
            path: "/tv/\(showID)/content_ratings",
            query: []
        )
        let preferredRegions = [localizedRegion] + originRegions + ["US"]
        guard let selected = preferredRegions.lazy.compactMap({ code in
            response.results.first {
                $0.isoCode == code &&
                    !$0.rating.trimmingCharacters(in: .whitespaces).isEmpty
            }
        }).first else { return nil }
        return ContentRatingSummary(
            region: selected.isoCode,
            original: selected.rating,
            cineBar: ContentRatingSummary.normalizedAge(for: selected.rating)
        )
    }

    func tvSeason(
        showID: Int,
        seasonNumber: Int
    ) async throws -> TVSeasonDetails {
        try await request(
            path: "/tv/\(showID)/season/\(seasonNumber)",
            query: [URLQueryItem(name: "language", value: language)]
        )
    }

    func tvCredits(showID: Int) async throws -> [CastMember] {
        let response: CreditsResponse = try await request(
            path: "/tv/\(showID)/credits",
            query: [URLQueryItem(name: "language", value: language)]
        )
        return response.cast
            .filter { !$0.name.isEmpty }
            .sorted { $0.order < $1.order }
    }

    func tvTrailers(showID: Int) async throws -> [MovieVideo] {
        let localized: VideoResponse = try await request(
            path: "/tv/\(showID)/videos",
            query: [URLQueryItem(name: "language", value: language)]
        )
        var candidates = localized.results
        if candidates.isEmpty && language != "en-US" {
            let english: VideoResponse = try await request(
                path: "/tv/\(showID)/videos",
                query: [URLQueryItem(name: "language", value: "en-US")]
            )
            candidates = english.results
        }
        return candidates
            .filter {
                $0.site.caseInsensitiveCompare("YouTube") == .orderedSame &&
                ($0.type == "Trailer" || $0.type == "Teaser")
            }
            .sorted {
                if $0.official != $1.official {
                    return $0.official && !$1.official
                }
                return $0.name < $1.name
            }
    }

    func tvProviders(showID: Int) async throws -> [String: RegionProviders] {
        let response: ProviderResponse = try await request(
            path: "/tv/\(showID)/watch/providers",
            query: []
        )
        return response.results
    }

    func tvExternalIDs(showID: Int) async throws -> TVExternalIDs {
        try await request(
            path: "/tv/\(showID)/external_ids",
            query: []
        )
    }

    func tvStills(showID: Int) async throws -> [MovieStill] {
        let languageCode = String(language.prefix(2))
        let response: MovieImagesResponse = try await request(
            path: "/tv/\(showID)/images",
            query: [
                URLQueryItem(name: "language", value: language),
                URLQueryItem(
                    name: "include_image_language",
                    value: "\(languageCode),en,null"
                )
            ]
        )
        return response.backdrops.sorted {
            if $0.voteCount != $1.voteCount {
                return $0.voteCount > $1.voteCount
            }
            return $0.voteAverage > $1.voteAverage
        }
    }

    private func request<T: Decodable>(
        path: String,
        query: [URLQueryItem]
    ) async throws -> T {
        let cleanedToken = token.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let proxy = proxyBaseURL
        guard !cleanedToken.isEmpty || proxy != nil else {
            throw CineBarError.missingToken
        }
        let endpointSet = ServiceEndpointSet(
            primary: proxy ?? "https://api.themoviedb.org/3",
            backups: proxy == nil
                ? []
                : ServiceBundleConfiguration.stringArray(
                    forInfoDictionaryKey: "CineBarDataBackupURLs"
                )
        )
        let data: Data
        do {
            (data, _) = try await ResilientHTTPClient().data(
                endpointSet: endpointSet
            ) { baseURL in
                var components = URLComponents(
                    string: "\(baseURL.absoluteString)\(path)"
                )
                components?.queryItems = query
                guard let url = components?.url else {
                    throw CineBarError.invalidResponse
                }
                var request = URLRequest(url: url)
                if proxy == nil {
                    request.setValue(
                        "Bearer \(cleanedToken)",
                        forHTTPHeaderField: "Authorization"
                    )
                }
                request.setValue(
                    "application/json",
                    forHTTPHeaderField: "Accept"
                )
                request.timeoutInterval = 15
                return request
            }
        } catch ServiceHTTPError.statusCode(let statusCode, _) {
            if statusCode == 401 {
                throw CineBarError.server(
                    "API Token 无效，请检查后重试"
                )
            }
            throw CineBarError.server(
                "TMDB 请求失败（\(statusCode)）"
            )
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

struct TVMazeClient {
    func nextAiring(externalIDs: TVExternalIDs) async throws -> TVAiringInfo? {
        let queryItem: URLQueryItem?
        if let tvdbID = externalIDs.tvdbID {
            queryItem = URLQueryItem(name: "thetvdb", value: String(tvdbID))
        } else if let imdbID = externalIDs.imdbID, !imdbID.isEmpty {
            queryItem = URLQueryItem(name: "imdb", value: imdbID)
        } else {
            queryItem = nil
        }
        guard let queryItem,
              var components = URLComponents(
                string: "https://api.tvmaze.com/lookup/shows"
              )
        else { return nil }
        components.queryItems = [queryItem]
        guard let lookupURL = components.url else { return nil }

        let show: TVMazeLookupShow = try await request(lookupURL)
        guard let href = show.links.nextEpisode?.href,
              let episodeURL = URL(string: href)
        else { return nil }
        let episode: TVMazeEpisode = try await request(episodeURL)
        let localDateTime = episode.airstamp.flatMap {
            ISO8601DateFormatter().date(from: $0)
        }
        return TVAiringInfo(
            airDate: episode.airdate,
            airTime: episode.airtime,
            localDateTime: localDateTime,
            platform: show.webChannel?.name ?? show.network?.name,
            sourceURL: show.url.flatMap(URL.init(string:))
        )
    }

    private func request<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .returnCacheDataElseLoad
        request.setValue(
            "CineBar/0.8 (macOS; TV schedule integration)",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode)
        else { throw CineBarError.invalidResponse }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

struct OMDbClient {
    let apiKey: String
    let proxyBaseURL: String?

    func ratings(
        imdbID: String,
        title: String? = nil
    ) async throws -> [MovieRating] {
        let proxy = DataProxyConfiguration.normalizedBaseURL(proxyBaseURL)
        let endpointSet: ServiceEndpointSet
        if let proxy {
            endpointSet = ServiceEndpointSet(
                primary: proxy,
                backups: ServiceBundleConfiguration.stringArray(
                    forInfoDictionaryKey: "CineBarDataBackupURLs"
                )
            )
        } else {
            guard let directURL = OMDbEndpoint.url(
                proxyBaseURL: nil,
                apiKey: apiKey,
                imdbID: imdbID
            ) else { throw CineBarError.invalidResponse }
            endpointSet = ServiceEndpointSet(
                primary: directURL.absoluteString,
                backups: []
            )
        }
        let data: Data
        do {
            (data, _) = try await ResilientHTTPClient().data(
                endpointSet: endpointSet
            ) { endpoint in
                let url: URL
                if proxy != nil {
                    guard let proxiedURL = OMDbEndpoint.url(
                        proxyBaseURL: endpoint.absoluteString,
                        apiKey: "",
                        imdbID: imdbID
                    ) else { throw CineBarError.invalidResponse }
                    url = proxiedURL
                } else {
                    url = endpoint
                }
                var request = URLRequest(url: url)
                request.timeoutInterval = 15
                return request
            }
        } catch ServiceHTTPError.statusCode {
            throw CineBarError.server("OMDb 请求失败")
        }

        let result = try JSONDecoder().decode(OMDbMovieResponse.self, from: data)
        if result.response == "False" {
            throw CineBarError.server(result.error ?? "OMDb 没有收录这部影片")
        }

        return (result.ratings ?? []).compactMap { rating in
            switch rating.source {
            case "Internet Movie Database":
                var url: URL?
                if !imdbID.isEmpty {
                    url = URL(string: "https://www.imdb.com/title/\(imdbID)/")
                }
                return MovieRating(
                    source: "IMDb",
                    value: rating.value,
                    note: "用户评分",
                    url: url
                )
            case "Rotten Tomatoes":
                return MovieRating(
                    source: "烂番茄",
                    value: rating.value,
                    note: "影评人分",
                    url: Self.searchURL(
                        base: "https://www.rottentomatoes.com/search",
                        query: title ?? imdbID
                    )
                )
            case "Metacritic":
                return MovieRating(
                    source: "Metacritic",
                    value: rating.value,
                    note: "媒体评分",
                    url: Self.searchURL(
                        base: "https://www.metacritic.com/search/movie/",
                        query: title ?? imdbID
                    )
                )
            default:
                return nil
            }
        }
    }

    private static func searchURL(base: String, query: String) -> URL? {
        guard !query.isEmpty,
              var components = URLComponents(string: base) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "q", value: query)
        ]
        return components.url
    }
}

enum CommunityMediaType: String {
    case movie
    case tv
}

enum BrandedShareLink {
    static func url(
        baseURL: String,
        mediaType: CommunityMediaType,
        mediaID: Int
    ) -> URL? {
        guard mediaID > 0,
              var components = URLComponents(string: baseURL)
        else { return nil }
        let root = components.path.hasSuffix("/")
            ? String(components.path.dropLast())
            : components.path
        let prefix = mediaType == .movie ? "m" : "t"
        components.path = "\(root)/\(prefix)/\(mediaID)"
        components.query = nil
        components.fragment = nil
        return components.url
    }
}

struct SharePayload {
    let mediaType: CommunityMediaType
    let title: String
    let url: URL

    var systemItems: [Any] {
        [url as NSURL]
    }
}

enum CineBarDeviceIdentity {
    static let defaultsKey = "communityAnonymousInstallID"

    static func value(defaults: UserDefaults = .standard) -> String {
        if let saved = defaults.string(forKey: defaultsKey),
           UUID(uuidString: saved) != nil {
            return saved
        }

        let created = UUID().uuidString
        defaults.set(created, forKey: defaultsKey)
        return created
    }
}

struct CommunityRatingClient {
    let baseURL: String
    let publicKey: String
    let deviceID: String

    func summary(
        mediaType: CommunityMediaType,
        mediaID: Int
    ) async throws -> CommunityRatingSummary {
        try await request(
            mediaType: mediaType,
            mediaID: mediaID,
            method: "GET",
            score: nil
        )
    }

    func save(
        mediaType: CommunityMediaType,
        mediaID: Int,
        score: Double
    ) async throws -> CommunityRatingSummary {
        try await request(
            mediaType: mediaType,
            mediaID: mediaID,
            method: "POST",
            score: score
        )
    }

    private func request(
        mediaType: CommunityMediaType,
        mediaID: Int,
        method: String,
        score: Double?
    ) async throws -> CommunityRatingSummary {
        guard let primary = DataProxyConfiguration.normalizedBaseURL(
            baseURL
        ) else {
            throw CineBarError.server("发布者尚未配置 CineBar 评分服务")
        }
        let endpointSet = ServiceEndpointSet(
            primary: primary,
            backups: ServiceBundleConfiguration.stringArray(
                forInfoDictionaryKey: "CineBarCommunityBackupURLs"
            )
        )
        let data: Data
        do {
            (data, _) = try await ResilientHTTPClient().data(
                endpointSet: endpointSet
            ) { endpoint in
                guard let url = URL(
                    string:
                        "\(endpoint.absoluteString)/v1/\(mediaType.rawValue)/\(mediaID)/rating"
                ) else { throw CineBarError.invalidResponse }
                var request = URLRequest(url: url)
                request.httpMethod = method
                request.timeoutInterval = 12
                request.setValue(
                    "application/json",
                    forHTTPHeaderField: "Accept"
                )
                request.setValue(
                    deviceID,
                    forHTTPHeaderField: "x-cinebar-device"
                )
                if !publicKey.isEmpty {
                    request.setValue(
                        publicKey,
                        forHTTPHeaderField: "x-cinebar-key"
                    )
                }
                if let score {
                    request.setValue(
                        "application/json",
                        forHTTPHeaderField: "Content-Type"
                    )
                    request.httpBody = try JSONSerialization.data(
                        withJSONObject: ["score": score]
                    )
                }
                return request
            }
        } catch ServiceHTTPError.statusCode(409, _) {
            throw CommunityRatingError.alreadyRated
        } catch ServiceHTTPError.statusCode(_, let responseData) {
            let payload = try? JSONSerialization.jsonObject(
                with: responseData
            ) as? [String: Any]
            throw CineBarError.server(
                payload?["error"] as? String ?? "CineBar 评分服务暂时不可用"
            )
        }
        return try JSONDecoder().decode(CommunityRatingSummary.self, from: data)
    }
}

@MainActor
final class MovieStore: ObservableObject {
    @Published var movies: [Movie] = Movie.demo
    @Published var televisionShows: [TVShow] = [TVShow.demo]
    @Published var mediaSection: MediaSection = .movies
    @Published var movieBrowseSection: MovieBrowseSection = .trending
    @Published var tvBrowseSection: TVBrowseSection = .trending
    @Published var isShowingWatchlist = false
    @Published var isShowingLocalLibrary = false
    @Published var selectedTVShow: TVShow?
    @Published var tvDetails: TVDetails?
    @Published var tvCast: [CastMember] = []
    @Published var tvTrailers: [MovieVideo] = []
    @Published var tvProviders: [Provider] = []
    @Published var tvProviderLink: URL?
    @Published var tvStills: [MovieStill] = []
    @Published var tvAiringInfo: TVAiringInfo?
    @Published var isLoadingTVDetails = false
    @Published var expandedSeasonNumber: Int?
    @Published var seasonEpisodes: [Int: [TVEpisode]] = [:]
    @Published var isLoadingSeason = false
    @Published var dailyMovie: Movie? = Movie.demo.first
    @Published var dailyMovies: [Movie] = Movie.demo
    @Published var dailyTVShow: TVShow? = TVShow.demo
    @Published var dailyTVShows: [TVShow] = [TVShow.demo]
    @Published var isLoadingDaily = false
    @Published var searchText = ""
    @Published var isLoading = false
    @Published var message = "演示模式 · 配置 TMDB Token 后显示真实数据"
    @Published var selectedMovie: Movie?
    @Published var selectedPerson: CastMember?
    @Published var providers: [Provider] = []
    @Published var providerLink: URL?
    @Published var isLoadingProviders = false
    @Published var cast: [CastMember] = []
    @Published var directors: [CrewMember] = []
    @Published var isLoadingCast = false
    @Published var personDetails: PersonDetails?
    @Published var personMovies: [Movie] = []
    @Published var personTelevision: [TVShow] = []
    @Published var personImages: [PersonImage] = []
    @Published var peopleSearchResults: [PersonSearchResult] = []
    @Published var personExternalIDs: PersonExternalIDs?
    @Published var isLoadingPerson = false
    @Published var trailers: [MovieVideo] = []
    @Published var isLoadingTrailers = false
    @Published var financials: MovieFinancials?
    @Published var isLoadingFinancials = false
    @Published var releaseSummary: MovieReleaseSummary?
    @Published var movieContentRating: ContentRatingSummary?
    @Published var tvContentRating: ContentRatingSummary?
    @Published var isLoadingReleaseDates = false
    @Published var movieStills: [MovieStill] = []
    @Published var isLoadingStills = false
    @Published var showMovieStills = false
    @Published var externalRatings: [MovieRating] = []
    @Published var doubanRating: MovieRating?
    @Published var isLoadingRatings = false
    @Published private(set) var listDoubanRatings: [String: MovieRating] = [:]
    @Published private(set) var listExternalRatings: [String: [MovieRating]] = [:]
    @Published var showCatalog = false
    @Published var showTVCatalog = false
    @Published var selectedShelf: MovieShelf?
    @Published var catalogPeriod: ReleasePeriod = .options[0]
    @Published var catalogFilterIDs: Set<String> = []
    @Published var catalogCountryCode: String?
    @Published var catalogSortMode: CatalogSortMode = .popularity
    @Published var isCatalogResult = false
    @Published var canLoadMoreCatalog = false
    @Published var isLoadingMoreCatalog = false
    @Published var tvCatalogPeriod: ReleasePeriod = .options[0]
    @Published var tvCatalogGenreID: Int?
    @Published var tvCatalogCountryCode: String?
    @Published var tvCatalogSortMode: CatalogSortMode = .popularity
    @Published var isTVCatalogResult = false
    @Published var canLoadMoreTVCatalog = false
    @Published var isLoadingMoreTVCatalog = false
    @Published var token: String
    @Published var omdbKey: String
    @Published var region: String
    @Published var preferredMovieGenreIDs: Set<Int>
    @Published var preferredTVGenreIDs: Set<Int>
    @Published var preferredMovieCountryCodes: Set<String>
    @Published var preferredTVCountryCodes: Set<String>
    @Published var countries: [TMDBCountry] = []
    @Published var communityRating: CommunityRatingSummary?
    @Published var communityRatingDraft: Double = 0
    @Published var isLoadingCommunityRating = false
    @Published var communityRatingMessage = ""
    @Published var appearanceMode: AppearanceMode
    @Published var glassBackgroundOpacity: Double
    @Published var appLanguage: AppLanguage
    @Published var autoHideInterval: AutoHideInterval
    @Published var launchAtLogin: Bool
    @Published var isPanelMovable: Bool
    @Published private(set) var watchlistMovies: [Movie]
    @Published private(set) var watchlistTVShows: [TVShow]
    @Published private(set) var releaseReminders: [ReleaseReminder]
    @Published private(set) var shareServiceURL: String
    @Published private(set) var dataProxyURL: String
    @Published private(set) var communityServiceURL: String
    @Published private(set) var latestServiceDiagnostic:
        ServiceDiagnostic?
    @Published var diagnosticCopyMessage = ""
    private let defaults = UserDefaults.standard
    private var browseCache: LastSuccessfulBrowseCache {
        LastSuccessfulBrowseCache(defaults: defaults)
    }
    private var catalogNextPage = 2
    private var tvCatalogNextPage = 2
    private var movieBrowseNextPage = 2
    private var tvBrowseNextPage = 2
    @Published var canLoadMoreMovieBrowse = false
    @Published var canLoadMoreTVBrowse = false
    @Published var isLoadingMoreBrowse = false
    private var moviesBeforeFilter: [Movie] = []
    private var televisionBeforeFilter: [TVShow] = []
    private var messageBeforeFilter = ""

    init() {
        token = defaults.string(forKey: "tmdbToken") ?? ""
        omdbKey = defaults.string(forKey: "omdbKey") ?? ""
        region = defaults.string(forKey: "watchRegion") ?? "CN"
        let legacyGenres = defaults.array(forKey: "preferredGenreIDs") as? [Int] ?? []
        preferredMovieGenreIDs = Set(
            defaults.array(forKey: "preferredMovieGenreIDs") as? [Int] ??
                legacyGenres
        )
        preferredTVGenreIDs = Set(
            defaults.array(forKey: "preferredTVGenreIDs") as? [Int] ?? []
        )
        preferredMovieCountryCodes = Set(
            defaults.array(forKey: "preferredMovieCountryCodes") as? [String] ?? []
        )
        preferredTVCountryCodes = Set(
            defaults.array(forKey: "preferredTVCountryCodes") as? [String] ?? []
        )
        appearanceMode = AppearanceMode(
            rawValue: defaults.string(forKey: "appearanceMode") ?? ""
        ) ?? .system
        glassBackgroundOpacity = GlassBackgroundOpacity.normalized(
            defaults.object(
                forKey: GlassBackgroundOpacity.defaultsKey
            ) as? Double
        )
        appLanguage = AppLanguage(
            rawValue: defaults.string(forKey: "appLanguage") ?? ""
        ) ?? .zhCN
        let savedAutoHide = defaults.object(forKey: "autoHideInterval") as? Int ?? 30
        autoHideInterval = AutoHideInterval(rawValue: savedAutoHide) ?? .thirtySeconds
        launchAtLogin = SMAppService.mainApp.status == .enabled
        isPanelMovable = defaults.bool(forKey: "isPanelMovable")
        if let data = defaults.data(forKey: "watchlistMovies"),
           let saved = try? JSONDecoder().decode([Movie].self, from: data) {
            watchlistMovies = saved
        } else {
            watchlistMovies = []
        }
        if let data = defaults.data(forKey: "watchlistTVShows"),
           let saved = try? JSONDecoder().decode([TVShow].self, from: data) {
            watchlistTVShows = saved
        } else {
            watchlistTVShows = []
        }
        if let reminderData = defaults.data(forKey: "releaseReminders"),
           let savedReminders = try? JSONDecoder().decode(
               [ReleaseReminder].self,
               from: reminderData
           ) {
            releaseReminders = savedReminders
        } else {
            releaseReminders = []
        }
        shareServiceURL = Bundle.main.object(
            forInfoDictionaryKey: "CineBarShareURL"
        ) as? String ?? ""
        dataProxyURL = Bundle.main.object(
            forInfoDictionaryKey: "CineBarDataProxyURL"
        ) as? String ?? ""
        communityServiceURL = Bundle.main.object(
            forInfoDictionaryKey: "CineBarCommunityURL"
        ) as? String ?? ""
    }

    var hasToken: Bool {
        !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            hasDataProxy
    }

    var hasDataProxy: Bool {
        DataProxyConfiguration.normalizedBaseURL(dataProxyURL) != nil
    }

    var hasOMDbKey: Bool {
        hasDataProxy ||
            !omdbKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasShareService: Bool {
        let cleaned = shareServiceURL.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return cleaned.hasPrefix("https://") ||
            cleaned.hasPrefix("http://localhost")
    }

    var hasCommunityService: Bool {
        let cleaned = communityServiceURL.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return cleaned.hasPrefix("https://") ||
            cleaned.hasPrefix("http://localhost")
    }

    private var communityPublicKey: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CineBarCommunityPublicKey"
        ) as? String ?? ""
    }

    var todayAirDateLabel: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "播出日期 · \(formatter.string(from: Date()))"
    }

    var supportURL: URL? {
        guard let raw = Bundle.main.object(
            forInfoDictionaryKey: "CineBarSupportURL"
        ) as? String else { return nil }
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : URL(string: cleaned)
    }

    private func recordServiceDiagnostic(
        service: String,
        endpoint: String,
        error: Error
    ) {
        guard let requestURL = URL(string: endpoint) else { return }
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0"
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "0"
        latestServiceDiagnostic = ServiceDiagnostic(
            service: service,
            category: ServiceFailureCategory.classify(error),
            timestamp: Date(),
            appVersion: "\(version) (\(build))",
            requestURL: requestURL
        )
        diagnosticCopyMessage = ""
    }

    func copyLatestServiceDiagnostic() {
        guard let diagnostic = latestServiceDiagnostic else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            diagnostic.redactedText,
            forType: .string
        )
        diagnosticCopyMessage = "诊断信息已复制"
    }

    func saveSettings() {
        let cleanedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedOMDbKey = omdbKey.trimmingCharacters(in: .whitespacesAndNewlines)
        token = cleanedToken
        omdbKey = cleanedOMDbKey
        region = region.uppercased()
        defaults.set(cleanedToken, forKey: "tmdbToken")
        defaults.set(cleanedOMDbKey, forKey: "omdbKey")
        defaults.set(region, forKey: "watchRegion")
        defaults.set(
            preferredMovieGenreIDs.sorted(),
            forKey: "preferredMovieGenreIDs"
        )
        defaults.set(
            preferredTVGenreIDs.sorted(),
            forKey: "preferredTVGenreIDs"
        )
        defaults.set(
            preferredMovieCountryCodes.sorted(),
            forKey: "preferredMovieCountryCodes"
        )
        defaults.set(
            preferredTVCountryCodes.sorted(),
            forKey: "preferredTVCountryCodes"
        )
        defaults.set(appearanceMode.rawValue, forKey: "appearanceMode")
        defaults.set(appLanguage.rawValue, forKey: "appLanguage")
        defaults.set(autoHideInterval.rawValue, forKey: "autoHideInterval")
        loadTrending()
        loadDailyRecommendation()
        loadDailyTVRecommendation()
    }

    func setAppearance(_ mode: AppearanceMode) {
        appearanceMode = mode
        defaults.set(mode.rawValue, forKey: "appearanceMode")
        NotificationCenter.default.post(
            name: .cineBarAppearanceDidChange,
            object: mode.rawValue
        )
    }

    func setGlassBackgroundOpacity(_ value: Double) {
        let normalized = GlassBackgroundOpacity.normalized(value)
        glassBackgroundOpacity = normalized
        defaults.set(
            normalized,
            forKey: GlassBackgroundOpacity.defaultsKey
        )
    }

    func setLanguage(_ language: AppLanguage) {
        appLanguage = language
        region = language.releaseRegion
        defaults.set(language.rawValue, forKey: "appLanguage")
        defaults.set(region, forKey: "watchRegion")
        loadTrending()
        loadDailyRecommendation(forceRefresh: true)
        loadDailyTVRecommendation(forceRefresh: true)
    }

    func setAutoHideInterval(_ interval: AutoHideInterval) {
        autoHideInterval = interval
        defaults.set(interval.rawValue, forKey: "autoHideInterval")
        NotificationCenter.default.post(
            name: .cineBarAutoHideDidChange,
            object: interval.rawValue
        )
    }

    func setPanelMovable(_ enabled: Bool) {
        isPanelMovable = enabled
        defaults.set(enabled, forKey: "isPanelMovable")
        NotificationCenter.default.post(
            name: .cineBarPanelMovementDidChange,
            object: enabled
        )
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if enabled,
               SMAppService.mainApp.status == .requiresApproval {
                switch appLanguage {
                case .zhCN:
                    message = "请在“系统设置 → 通用 → 登录项”中允许 CineBar"
                case .zhHK, .zhTW:
                    message = "請在「系統設定 → 一般 → 登入項目」中允許 CineBar"
                case .enUS:
                    message = "Allow CineBar in System Settings → General → Login Items"
                case .jaJP:
                    message = "システム設定 → 一般 → ログイン項目でCineBarを許可してください"
                case .koKR:
                    message = "시스템 설정 → 일반 → 로그인 항목에서 CineBar를 허용하세요"
                }
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            message = "开机启动设置失败：\(error.localizedDescription)"
        }
    }

    func hasReleaseReminder(
        mediaType: ReleaseReminder.MediaType,
        mediaID: Int,
        subID: String? = nil
    ) -> Bool {
        releaseReminders.contains {
            $0.mediaType == mediaType &&
                $0.mediaID == mediaID &&
                $0.subID == subID
        }
    }

    func episodeReminderOption(
        showID: Int,
        episodeCode: String
    ) -> EpisodeReminderOption? {
        guard let reminder = releaseReminders.first(where: {
            $0.mediaType == .tvEpisode &&
                $0.mediaID == showID &&
                $0.subID == episodeCode
        }) else { return nil }
        return EpisodeReminderOption.allCases.first {
            $0.dayOffset == (reminder.reminderDayOffset ?? 0) &&
                $0.hour == (reminder.reminderHour ?? 9)
        }
    }

    func toggleReleaseReminder(for movie: Movie) {
        let detailDate = selectedMovie?.id == movie.id
            ? (
                releaseSummary?.localizedRelease ??
                    financials?.releaseDate
            )
            : nil
        toggleReleaseReminder(
            ReleaseReminder(
                mediaType: .movie,
                mediaID: movie.id,
                title: movie.title,
                knownReleaseDate: normalizedFutureDate(
                    detailDate ?? movie.localizedReleaseDate ?? movie.releaseDate
                )
            )
        )
    }

    func toggleReleaseReminder(for show: TVShow) {
        let detailDate = selectedTVShow?.id == show.id
            ? tvDetails?.firstAirDate
            : nil
        toggleReleaseReminder(
            ReleaseReminder(
                mediaType: .television,
                mediaID: show.id,
                title: show.name,
                knownReleaseDate: normalizedFutureDate(
                    detailDate ?? show.firstAirDate
                )
            )
        )
    }

    func toggleEpisodeReminder(
        show: TVShow,
        episode: TVEpisodeSummary,
        option: EpisodeReminderOption = .sameDay09
    ) {
        guard let date = normalizedFutureDate(episode.airDate) else { return }
        let reminder = ReleaseReminder(
            mediaType: .tvEpisode,
            mediaID: show.id,
            title: "《\(show.name)》\(episode.code) \(episode.name)",
            knownReleaseDate: date,
            subID: episode.code,
            reminderDayOffset: option.dayOffset,
            reminderHour: option.hour
        )
        if let index = releaseReminders.firstIndex(where: {
            $0.id == reminder.id
        }) {
            let current = releaseReminders[index]
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: ["release-day-\(reminder.id)"]
            )
            if current.reminderDayOffset == option.dayOffset,
               current.reminderHour == option.hour {
                releaseReminders.remove(at: index)
            } else {
                releaseReminders[index] = reminder
                Task {
                    _ = try? await UNUserNotificationCenter.current()
                        .requestAuthorization(options: [.alert, .sound, .badge])
                    scheduleReleaseDayNotification(for: reminder)
                }
            }
            persistReleaseReminders()
        } else {
            toggleReleaseReminder(reminder)
        }
    }

    func toggleSeasonReminder(show: TVShow, season: TVSeason) {
        guard let date = normalizedFutureDate(season.airDate) else { return }
        let subID = "S\(season.seasonNumber)"
        toggleReleaseReminder(
            ReleaseReminder(
                mediaType: .tvSeason,
                mediaID: show.id,
                title: "《\(show.name)》\(season.name)",
                knownReleaseDate: date,
                subID: subID
            )
        )
    }

    func checkReleaseReminders() {
        guard hasToken, !releaseReminders.isEmpty else { return }
        let snapshot = releaseReminders
        Task {
            var updated = snapshot
            let client = TMDBClient(
                token: token,
                language: appLanguage.apiCode
            )
            for index in updated.indices {
                let oldDate = updated[index].knownReleaseDate
                let currentDate: String?
                do {
                    switch updated[index].mediaType {
                    case .movie:
                        currentDate = normalizedFutureDate(
                            try await client.financials(
                                movieID: updated[index].mediaID
                            ).releaseDate
                        )
                    case .television:
                        currentDate = normalizedFutureDate(
                            try await client.tvDetails(
                                showID: updated[index].mediaID
                            ).firstAirDate
                        )
                    case .tvEpisode, .tvSeason:
                        currentDate = oldDate
                    }
                } catch {
                    continue
                }

                if let currentDate, currentDate != oldDate {
                    updated[index].knownReleaseDate = currentDate
                    sendDateConfirmedNotification(
                        reminder: updated[index],
                        date: currentDate
                    )
                    scheduleReleaseDayNotification(for: updated[index])
                }
            }
            releaseReminders = updated
            persistReleaseReminders()
        }
    }

    private func toggleReleaseReminder(_ reminder: ReleaseReminder) {
        guard reminder.mediaID > 0 else { return }
        if let index = releaseReminders.firstIndex(where: {
            $0.id == reminder.id
        }) {
            releaseReminders.remove(at: index)
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: ["release-day-\(reminder.id)"]
            )
        } else {
            releaseReminders.append(reminder)
            Task {
                _ = try? await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge])
                if reminder.knownReleaseDate != nil {
                    scheduleReleaseDayNotification(for: reminder)
                }
            }
        }
        persistReleaseReminders()
    }

    private func persistReleaseReminders() {
        if let data = try? JSONEncoder().encode(releaseReminders) {
            defaults.set(data, forKey: "releaseReminders")
        }
    }

    private func normalizedFutureDate(_ value: String?) -> String? {
        guard let value, value.count >= 10 else { return nil }
        let dateText = String(value.prefix(10))
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateText) else { return nil }
        let startOfToday = Calendar.current.startOfDay(for: Date())
        return date >= startOfToday ? dateText : nil
    }

    private func scheduleReleaseDayNotification(for reminder: ReleaseReminder) {
        guard let dateText = reminder.knownReleaseDate else { return }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let releaseDate = formatter.date(from: dateText),
              let date = Calendar.current.date(
                byAdding: .day,
                value: reminder.reminderDayOffset ?? 0,
                to: releaseDate
              )
        else { return }
        var components = Calendar.current.dateComponents(
            [.year, .month, .day],
            from: date
        )
        components.hour = reminder.reminderHour ?? 9

        let content = UNMutableNotificationContent()
        switch reminder.mediaType {
        case .tvEpisode:
            if (reminder.reminderDayOffset ?? 0) < 0 {
                content.title = "下一集明天播出"
                content.body = "\(reminder.title) 将于明天播出。"
            } else {
                content.title = "下一集今天播出"
                content.body = "\(reminder.title) 今天播出。"
            }
        case .tvSeason:
            content.title = "新一季今天开播"
            content.body = "\(reminder.title) 今天开播。"
        case .movie, .television:
            content.title = "今天上映"
            content.body = "你关注的《\(reminder.title)》已到上映/首播日期。"
        }
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "release-day-\(reminder.id)",
            content: content,
            trigger: UNCalendarNotificationTrigger(
                dateMatching: components,
                repeats: false
            )
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func sendDateConfirmedNotification(
        reminder: ReleaseReminder,
        date: String
    ) {
        let content = UNMutableNotificationContent()
        content.title = "已定档"
        content.body = "《\(reminder.title)》已确定于 \(date) 上映/首播。"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "date-confirmed-\(reminder.id)-\(date)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(
                timeInterval: 1,
                repeats: false
            )
        )
        UNUserNotificationCenter.current().add(request)
    }

    func togglePreferredMovieGenre(_ genreID: Int) {
        if preferredMovieGenreIDs.contains(genreID) {
            preferredMovieGenreIDs.remove(genreID)
        } else {
            preferredMovieGenreIDs.insert(genreID)
        }
    }

    func togglePreferredTVGenre(_ genreID: Int) {
        if preferredTVGenreIDs.contains(genreID) {
            preferredTVGenreIDs.remove(genreID)
        } else {
            preferredTVGenreIDs.insert(genreID)
        }
    }

    func togglePreferredMovieCountry(_ code: String) {
        if preferredMovieCountryCodes.contains(code) {
            preferredMovieCountryCodes.remove(code)
        } else {
            preferredMovieCountryCodes.insert(code)
        }
    }

    func togglePreferredTVCountry(_ code: String) {
        if preferredTVCountryCodes.contains(code) {
            preferredTVCountryCodes.remove(code)
        } else {
            preferredTVCountryCodes.insert(code)
        }
    }

    func countryName(_ code: String) -> String {
        countries.first { $0.isoCode == code }?
            .displayName(language: appLanguage) ?? code
    }

    func loadCountries() {
        if !countries.isEmpty { return }
        let cacheAge = Date().timeIntervalSince(
            defaults.object(forKey: "tmdbCountriesCacheDate") as? Date ?? .distantPast
        )
        if cacheAge < 30 * 24 * 60 * 60,
           let data = defaults.data(forKey: "tmdbCountriesCache"),
           let cached = try? JSONDecoder().decode([TMDBCountry].self, from: data) {
            countries = cached.sorted {
                $0.displayName(language: appLanguage)
                    .localizedStandardCompare(
                        $1.displayName(language: appLanguage)
                    ) == .orderedAscending
            }
            return
        }
        guard hasToken else { return }
        Task {
            do {
                let loaded = try await TMDBClient(
                    token: token,
                    language: appLanguage.apiCode
                ).countries()
                countries = loaded.sorted {
                    $0.displayName(language: appLanguage)
                        .localizedStandardCompare(
                            $1.displayName(language: appLanguage)
                        ) == .orderedAscending
                }
                if let data = try? JSONEncoder().encode(loaded) {
                    defaults.set(data, forKey: "tmdbCountriesCache")
                    defaults.set(Date(), forKey: "tmdbCountriesCacheDate")
                }
            } catch {
                // Country data is supplementary and must not block browsing.
            }
        }
    }

    private var communityClient: CommunityRatingClient {
        CommunityRatingClient(
            baseURL: communityServiceURL,
            publicKey: communityPublicKey,
            deviceID: CineBarDeviceIdentity.value()
        )
    }

    func loadCommunityRating(
        mediaType: CommunityMediaType,
        mediaID: Int
    ) {
        communityRating = nil
        communityRatingMessage = ""
        guard mediaID > 0, hasCommunityService else {
            if mediaID > 0 {
                communityRatingMessage = "发布者尚未配置 CineBar 评分服务"
            }
            return
        }
        isLoadingCommunityRating = true
        Task {
            do {
                let result = try await communityClient.summary(
                    mediaType: mediaType,
                    mediaID: mediaID
                )
                communityRating = result
                communityRatingDraft = result.myScore ?? 0
            } catch {
                communityRatingMessage = error.localizedDescription
                recordServiceDiagnostic(
                    service: "community",
                    endpoint: communityServiceURL,
                    error: error
                )
            }
            isLoadingCommunityRating = false
        }
    }

    func saveCommunityRating(
        mediaType: CommunityMediaType,
        mediaID: Int
    ) {
        guard mediaID > 0, hasCommunityService else { return }
        isLoadingCommunityRating = true
        communityRatingMessage = "正在保存评分…"
        Task {
            do {
                communityRating = try await communityClient.save(
                    mediaType: mediaType,
                    mediaID: mediaID,
                    score: communityRatingDraft
                )
                communityRatingMessage = "评分已保存，其他 CineBar 用户现在可以看到"
            } catch CommunityRatingError.alreadyRated {
                communityRatingMessage = "这部影片已经评分，不能重复评分"
                do {
                    communityRating = try await communityClient.summary(
                        mediaType: mediaType,
                        mediaID: mediaID
                    )
                    communityRatingDraft = communityRating?.myScore ?? 0
                } catch {
                    // Preserve the duplicate-rating message if refresh fails.
                }
            } catch {
                communityRatingMessage = error.localizedDescription
                recordServiceDiagnostic(
                    service: "community",
                    endpoint: communityServiceURL,
                    error: error
                )
            }
            isLoadingCommunityRating = false
        }
    }

    func loadTrending() {
        canLoadMoreCatalog = false
        isCatalogResult = false
        if mediaSection == .television {
            loadTVBrowseSection(tvBrowseSection)
            return
        }
        loadMovieBrowseSection(movieBrowseSection)
    }

    func setMovieBrowseSection(_ section: MovieBrowseSection) {
        movieBrowseSection = section
        isShowingWatchlist = false
        isShowingLocalLibrary = false
        searchText = ""
        peopleSearchResults = []
        loadMovieBrowseSection(section)
    }

    func loadMovieBrowseSection(_ section: MovieBrowseSection) {
        canLoadMoreCatalog = false
        isCatalogResult = false
        guard hasToken else {
            movies = Movie.demo
            message = "演示模式 · 配置 TMDB Token 后显示真实数据"
            return
        }
        movieBrowseSection = section
        isLoading = true
        message = "正在获取\(section.title)…"
        if section == .recommendations {
            loadDailyRecommendation()
            isLoading = false
            return
        }
        Task {
            do {
                let client = TMDBClient(
                    token: token,
                    language: appLanguage.apiCode
                )
                let result: MoviePageResult
                if section == .upcoming {
                    result = try await client.upcomingMovies(
                        region: region,
                        page: 1
                    )
                } else {
                    result = try await client.trending(page: 1)
                }
                movies = result.movies
                browseCache.saveMovies(result.movies)
                movieBrowseNextPage = result.page + 1
                canLoadMoreMovieBrowse = result.page < result.totalPages
                selectedShelf = nil
                message = "\(section.title) · \(result.movies.count) 部"
                if section == .upcoming, appLanguage == .zhCN {
                    correctUpcomingDatesWithDouban()
                }
            } catch {
                recordServiceDiagnostic(
                    service: "data",
                    endpoint: dataProxyURL,
                    error: error
                )
                if let cached = browseCache.loadMovies() {
                    movies = cached
                    message = ServiceErrorPresentation.message(
                        language: appLanguage,
                        hasCachedContent: true
                    )
                } else {
                    movies = Movie.demo
                    message = ServiceErrorPresentation.message(
                        language: appLanguage,
                        hasCachedContent: false
                    )
                }
            }
            isLoading = false
        }
    }

    /// 即将上映：拉豆瓣 coming 列表，按标题匹配覆盖中国大陆上映日期。
    /// TMDB 某些影片在中国大陆有多个日期条目（首映 / 重映），
    /// /movie/upcoming 可能因地区时序选出错误日期（如机器人总动员 4/16 vs 重映 8/19）。
    /// 豆瓣列表只含未来上映，用它校正 localizedReleaseDate 更贴近用户。
    func correctUpcomingDatesWithDouban() {
        Task {
            let items = (try? await DoubanComingClient().coming()) ?? []
            guard !items.isEmpty else { return }
            let byDate: [String: [DoubanComingItem]] = Dictionary(
                grouping: items,
                by: { $0.displayDate }
            )
            await MainActor.run {
                let sortedDates = byDate.keys.sorted()
                for date in sortedDates {
                    let candidates = byDate[date] ?? []
                    for item in candidates {
                        let normalized = DoubanRatingClient.normalize(item.title)
                        guard !normalized.isEmpty else { continue }
                        for idx in movies.indices {
                            let movieTitle = DoubanRatingClient.normalize(movies[idx].title)
                            guard movieTitle == normalized ||
                                  movieTitle.contains(normalized) ||
                                  normalized.contains(movieTitle) else { continue }
                            // 仅当 TMDB 日期缺失或不同才覆盖为豆瓣日期（当年）。
                            let doubanFull = DoubanComingDate.fullDate(item.displayDate)
                            guard let doubanFull else { continue }
                            if movies[idx].localizedReleaseDate != doubanFull {
                                var corrected = movies[idx]
                                corrected.localizedReleaseDate = doubanFull
                                movies[idx] = corrected
                            }
                        }
                    }
                }
            }
        }
    }

    func loadDailyRecommendation(forceRefresh: Bool = false) {
        guard hasToken else {
            dailyMovie = Movie.demo.first
            dailyMovies = Movie.demo
            return
        }

        isLoadingDaily = true
        Task {
            let dayNumber = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
            let page = forceRefresh ? Int.random(in: 1...10) : (dayNumber % 8) + 1
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            do {
                let candidates = try await TMDBClient(
                    token: token,
                    language: appLanguage.apiCode
                ).recommendationCandidates(
                    genreIDs: preferredMovieGenreIDs.sorted(),
                    originCountries: preferredMovieCountryCodes.sorted(),
                    page: page,
                    latestReleaseDate: formatter.string(from: Date())
                )
                updateDailyRecommendation(from: candidates, forceRefresh: forceRefresh)
            } catch {
                if dailyMovie?.id ?? -1 < 0 {
                    dailyMovie = Movie.demo.first
                }
            }
            if movieBrowseSection == .recommendations,
               mediaSection == .movies {
                movies = dailyMovies
                message = "每日电影推荐 · \(dailyMovies.count) 部"
            }
            isLoadingDaily = false
        }
    }

    func refreshDailyRecommendation() {
        loadDailyRecommendation(forceRefresh: true)
    }

    func loadDailyTVRecommendation(forceRefresh: Bool = false) {
        guard hasToken else {
            dailyTVShow = TVShow.demo
            dailyTVShows = [TVShow.demo]
            if tvBrowseSection == .recommendations,
               mediaSection == .television {
                televisionShows = dailyTVShows
            }
            return
        }
        isLoadingDaily = true
        Task {
            let dayNumber = Calendar.current.ordinality(
                of: .day,
                in: .era,
                for: Date()
            ) ?? 0
            let page = forceRefresh ? Int.random(in: 1...10) : (dayNumber % 8) + 1
            do {
                let candidates = try await TMDBClient(
                    token: token,
                    language: appLanguage.apiCode
                ).tvRecommendationCandidates(
                    genreIDs: preferredTVGenreIDs.sorted(),
                    originCountries: preferredTVCountryCodes.sorted(),
                    page: page
                )
                updateDailyTVRecommendation(
                    from: candidates,
                    forceRefresh: forceRefresh
                )
            } catch {
                if dailyTVShow?.id ?? -1 < 0 {
                    dailyTVShow = TVShow.demo
                    dailyTVShows = [TVShow.demo]
                }
            }
            if tvBrowseSection == .recommendations,
               mediaSection == .television {
                televisionShows = dailyTVShows
                message = "每日电视剧推荐 · \(dailyTVShows.count) 部"
            }
            isLoadingDaily = false
        }
    }

    func refreshDailyTVRecommendation() {
        loadDailyTVRecommendation(forceRefresh: true)
    }

    func loadMoreMovieBrowseIfNeeded() {
        guard canLoadMoreMovieBrowse,
              !isLoadingMoreBrowse,
              !isCatalogResult,
              movieBrowseSection != .recommendations,
              hasToken else { return }
        isLoadingMoreBrowse = true
        let requestedPage = movieBrowseNextPage
        let section = movieBrowseSection
        Task {
            do {
                let client = TMDBClient(
                    token: token,
                    language: appLanguage.apiCode
                )
                let result: MoviePageResult
                if section == .upcoming {
                    result = try await client.upcomingMovies(
                        region: region,
                        page: requestedPage
                    )
                } else {
                    result = try await client.trending(page: requestedPage)
                }
                var seen = Set(movies.map(\.id))
                movies.append(contentsOf: result.movies.filter {
                    seen.insert($0.id).inserted
                })
                if section == .upcoming {
                    movies = UpcomingMovieSorting.sorted(movies)
                }
                movieBrowseNextPage = result.page + 1
                canLoadMoreMovieBrowse = result.page < result.totalPages
                message = "\(section.title) · 已载入 \(movies.count) 部"
            } catch {
                message = error.localizedDescription
            }
            isLoadingMoreBrowse = false
        }
    }

    func performSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            clearSearch()
            return
        }
        guard hasToken else {
            message = "搜索需要先配置 TMDB Token"
            NotificationCenter.default.post(name: .cineBarOpenSettings, object: nil)
            return
        }

        isLoading = true
        isShowingWatchlist = false
        canLoadMoreCatalog = false
        isCatalogResult = false
        canLoadMoreTVCatalog = false
        isTVCatalogResult = false
        canLoadMoreMovieBrowse = false
        canLoadMoreTVBrowse = false
        message = "正在搜索“\(query)”…"
        Task {
            let client = TMDBClient(
                token: token,
                language: appLanguage.apiCode
            )
            async let peopleRequest = client.searchPeople(query)
            if mediaSection == .movies {
                do {
                    let result = try await client.search(query)
                    movies = result
                    selectedShelf = nil
                    message = result.isEmpty
                        ? "没有找到相关影片"
                        : "找到 \(result.count) 部影片"
                } catch {
                    movies = []
                    message = error.localizedDescription
                }
            } else {
                do {
                    let result = try await client.searchTV(query)
                    televisionShows = result
                    message = result.isEmpty
                        ? "没有找到相关电视剧"
                        : "找到 \(result.count) 部电视剧"
                } catch {
                    televisionShows = []
                    message = error.localizedDescription
                }
            }
            do {
                peopleSearchResults = try await peopleRequest
            } catch {
                peopleSearchResults = []
            }
            if !peopleSearchResults.isEmpty {
                message += " · 演员 \(peopleSearchResults.count) 位"
            }
            isLoading = false
        }
    }

    func clearSearch() {
        searchText = ""
        peopleSearchResults = []
        isShowingWatchlist = false
        isShowingLocalLibrary = false
        loadTrending()
    }

    func toggleWatchlist() {
        isShowingWatchlist.toggle()
        isShowingLocalLibrary = false
        searchText = ""
        peopleSearchResults = []
        showCatalog = false
        showTVCatalog = false
        message = isShowingWatchlist
            ? "我的片单 · \(watchlistMovies.count + watchlistTVShows.count) 项"
            : message
        if !isShowingWatchlist {
            loadTrending()
        }
    }

    var mainBrowseSection: MainBrowseSection {
        if isShowingLocalLibrary { return .localLibrary }
        if isShowingWatchlist { return .watchlist }
        return mediaSection == .movies ? .movies : .television
    }

    func setMainBrowseSection(_ section: MainBrowseSection) {
        switch section {
        case .movies:
            isShowingLocalLibrary = false
            if mediaSection != .movies {
                setMediaSection(.movies)
            } else if isShowingWatchlist {
                toggleWatchlist()
            }
        case .television:
            isShowingLocalLibrary = false
            if mediaSection != .television {
                setMediaSection(.television)
            } else if isShowingWatchlist {
                toggleWatchlist()
            }
        case .watchlist:
            isShowingLocalLibrary = false
            if !isShowingWatchlist {
                toggleWatchlist()
            }
        case .localLibrary:
            showLocalLibrary()
        }
    }

    private func showLocalLibrary() {
        guard !isShowingLocalLibrary else { return }
        TrailerPlaybackController.shared.close()
        isShowingLocalLibrary = true
        isShowingWatchlist = false
        selectedMovie = nil
        selectedTVShow = nil
        selectedPerson = nil
        showMovieStills = false
        showCatalog = false
        showTVCatalog = false
        peopleSearchResults = []
        searchText = ""
        trailers = []
        tvTrailers = []
    }

    func isInWatchlist(_ movie: Movie) -> Bool {
        watchlistMovies.contains { $0.id == movie.id }
    }

    func isInWatchlist(_ show: TVShow) -> Bool {
        watchlistTVShows.contains { $0.id == show.id }
    }

    func toggleWatchlist(_ movie: Movie) {
        if let index = watchlistMovies.firstIndex(where: {
            $0.id == movie.id
        }) {
            watchlistMovies.remove(at: index)
        } else {
            watchlistMovies.insert(movie, at: 0)
        }
        persistWatchlist()
    }

    func toggleWatchlist(_ show: TVShow) {
        if let index = watchlistTVShows.firstIndex(where: {
            $0.id == show.id
        }) {
            watchlistTVShows.remove(at: index)
        } else {
            watchlistTVShows.insert(show, at: 0)
        }
        persistWatchlist()
    }

    private func persistWatchlist() {
        if let data = try? JSONEncoder().encode(watchlistMovies) {
            defaults.set(data, forKey: "watchlistMovies")
        }
        if let data = try? JSONEncoder().encode(watchlistTVShows) {
            defaults.set(data, forKey: "watchlistTVShows")
        }
    }

    func loadShelf(_ shelf: MovieShelf) {
        guard hasToken else {
            message = "分类选片需要先配置 TMDB Token"
            showCatalog = false
            NotificationCenter.default.post(name: .cineBarOpenSettings, object: nil)
            return
        }

        isLoading = true
        canLoadMoreCatalog = false
        isCatalogResult = false
        showCatalog = false
        selectedShelf = shelf
        searchText = ""
        message = "正在打开“\(shelf.title)”…"
        Task {
            do {
                let result = try await TMDBClient(
                    token: token,
                    language: appLanguage.apiCode
                ).discover(shelf)
                movies = result
                message = result.isEmpty ? "“\(shelf.title)”暂无结果" : "\(shelf.title) · \(result.count) 部"
            } catch {
                message = error.localizedDescription
            }
            isLoading = false
        }
    }

    func selectCatalogFilter(_ filterID: String) {
        if catalogFilterIDs.contains(filterID) {
            catalogFilterIDs = []
        } else {
            catalogFilterIDs = [filterID]
        }
    }

    func clearCatalogFilters() {
        catalogPeriod = .options[0]
        catalogFilterIDs = []
        catalogCountryCode = nil
    }

    func applyCatalogFilters() {
        guard hasToken else {
            message = "分类选片需要先配置影片数据 Token"
            showCatalog = false
            NotificationCenter.default.post(name: .cineBarOpenSettings, object: nil)
            return
        }

        if !isCatalogResult {
            moviesBeforeFilter = movies
            messageBeforeFilter = message
        }
        isLoading = true
        isCatalogResult = true
        canLoadMoreMovieBrowse = false
        showCatalog = false
        searchText = ""
        let periodTitle = catalogPeriod.title(language: appLanguage)
        let genreTitles = MovieShelf.genreOptions.compactMap { shelf -> String? in
            catalogFilterIDs.contains(shelf.id) ? shelf.title : nil
        }
        let genreIDs = MovieShelf.genreOptions.compactMap { shelf -> Int? in
            guard catalogFilterIDs.contains(shelf.id) else { return nil }
            return shelf.genreID
        }
        let keywordQueries = MovieShelf.genreOptions.compactMap { shelf -> String? in
            guard catalogFilterIDs.contains(shelf.id) else { return nil }
            return shelf.keywordQuery
        }
        let countryTitle = catalogCountryCode.map(countryName)
        let filterTitle = ([periodTitle] + genreTitles + [countryTitle])
            .compactMap { $0 }
            .joined(separator: " · ")
        message = "正在筛选 \(filterTitle)…"

        Task {
            do {
                let result = try await TMDBClient(
                    token: token,
                    language: appLanguage.apiCode
                ).discover(
                    startYear: catalogPeriod.startYear,
                    endYear: catalogPeriod.endYear,
                    genreIDs: genreIDs.sorted(),
                    keywordQueries: keywordQueries,
                    originCountry: catalogCountryCode,
                    sortMode: catalogSortMode,
                    page: 1
                )
                movies = result.movies
                catalogNextPage = 2
                canLoadMoreCatalog = result.page < result.totalPages
                selectedShelf = nil
                message = result.movies.isEmpty
                    ? "没有符合条件的影片"
                    : "\(filterTitle) · 已载入 \(result.movies.count) 部"
            } catch {
                message = error.localizedDescription
            }
            isLoading = false
        }
    }

    func clearAppliedCatalogFilters() {
        guard isCatalogResult else { return }
        isCatalogResult = false
        canLoadMoreCatalog = false
        isLoadingMoreCatalog = false
        if !moviesBeforeFilter.isEmpty {
            movies = moviesBeforeFilter
            message = messageBeforeFilter
            moviesBeforeFilter = []
        } else {
            loadTrending()
        }
    }

    func loadMoreCatalog() {
        guard canLoadMoreCatalog, !isLoadingMoreCatalog, hasToken else { return }
        isLoadingMoreCatalog = true
        let genreIDs = MovieShelf.genreOptions.compactMap { shelf -> Int? in
            guard catalogFilterIDs.contains(shelf.id) else { return nil }
            return shelf.genreID
        }
        let keywordQueries = MovieShelf.genreOptions.compactMap { shelf -> String? in
            guard catalogFilterIDs.contains(shelf.id) else { return nil }
            return shelf.keywordQuery
        }
        let requestedPage = catalogNextPage
        Task {
            do {
                let result = try await TMDBClient(
                    token: token,
                    language: appLanguage.apiCode
                ).discover(
                    startYear: catalogPeriod.startYear,
                    endYear: catalogPeriod.endYear,
                    genreIDs: genreIDs.sorted(),
                    keywordQueries: keywordQueries,
                    originCountry: catalogCountryCode,
                    sortMode: catalogSortMode,
                    page: requestedPage
                )
                var seen = Set(movies.map(\.id))
                movies.append(contentsOf: result.movies.filter {
                    seen.insert($0.id).inserted
                })
                if catalogSortMode == .rating {
                    movies.sort {
                        if $0.voteAverage != $1.voteAverage {
                            return $0.voteAverage > $1.voteAverage
                        }
                        return $0.voteCount > $1.voteCount
                    }
                }
                catalogNextPage = result.page + 1
                canLoadMoreCatalog = result.page < result.totalPages
                message = "\(catalogPeriod.title(language: appLanguage)) · 已载入 \(movies.count) 部"
            } catch {
                message = error.localizedDescription
            }
            isLoadingMoreCatalog = false
        }
    }

    func select(_ movie: Movie) {
        selectedPerson = nil
        selectedTVShow = nil
        selectedMovie = movie
        providers = []
        providerLink = nil
        cast = []
        directors = []
        trailers = []
        financials = nil
        releaseSummary = nil
        movieContentRating = nil
        movieStills = []
        showMovieStills = false
        externalRatings = []
        doubanRating = nil
        loadCommunityRating(mediaType: .movie, mediaID: movie.id)
        guard movie.id > 0, hasToken else { return }

        isLoadingProviders = true
        isLoadingCast = true
        isLoadingTrailers = true
        isLoadingFinancials = true
        isLoadingReleaseDates = true
        Task {
            do {
                let regions = try await TMDBClient(
                    token: token,
                    language: appLanguage.apiCode
                ).providers(movieID: movie.id)
                let selected = regions[region.uppercased()]
                providers = selected?.all ?? []
                if let link = selected?.link {
                    providerLink = URL(string: link)
                }
            } catch {
                message = error.localizedDescription
            }
            isLoadingProviders = false
        }

        Task {
            do {
                let credits = try await TMDBClient(
                    token: token,
                    language: appLanguage.apiCode
                ).credits(movieID: movie.id)
                cast = credits.cast
                    .filter { !$0.name.isEmpty }
                    .sorted { $0.order < $1.order }
                directors = (credits.crew ?? [])
                    .filter { $0.job.caseInsensitiveCompare("Director") == .orderedSame }
                    .sorted { $0.name < $1.name }
            } catch {
                cast = []
                directors = []
            }
            isLoadingCast = false
        }

        Task {
            do {
                trailers = try await TMDBClient(
                    token: token,
                    language: appLanguage.apiCode
                ).trailers(movieID: movie.id)
            } catch {
                trailers = []
            }
            isLoadingTrailers = false
        }

        Task {
            do {
                let client = TMDBClient(
                    token: token,
                    language: appLanguage.apiCode
                )
                let details = try await client.financials(movieID: movie.id)
                financials = details
                let originRegions = details.productionCountries?
                    .map(\.isoCode) ?? []
                let summary = try await client.releaseSummary(
                    movieID: movie.id,
                    localizedRegion: appLanguage.releaseRegion,
                    certificationRegion: region.uppercased(),
                    originRegions: originRegions
                )
                releaseSummary = summary
                movieContentRating = summary.contentRating
            } catch {
                financials = nil
                releaseSummary = nil
                movieContentRating = nil
            }
            isLoadingFinancials = false
            isLoadingReleaseDates = false
        }

        loadExternalRatings(movieID: movie.id)
        loadDoubanRating(
            title: movie.title,
            year: Self.year(from: movie.releaseDate)
        )
        loadStills(movieID: movie.id)
    }

    func setMediaSection(_ section: MediaSection) {
        guard mediaSection != section else { return }
        TrailerPlaybackController.shared.close()
        mediaSection = section
        selectedMovie = nil
        selectedTVShow = nil
        selectedPerson = nil
        showMovieStills = false
        showCatalog = false
        showTVCatalog = false
        isShowingWatchlist = false
        isShowingLocalLibrary = false
        peopleSearchResults = []
        searchText = ""
        loadTrending()
        if section == .television {
            loadDailyTVRecommendation()
        }
    }

    func setCatalogSortMode(_ sortMode: CatalogSortMode) {
        guard catalogSortMode != sortMode else { return }
        catalogSortMode = sortMode
        if isCatalogResult {
            applyCatalogFilters()
        }
    }

    func setTVBrowseSection(_ section: TVBrowseSection) {
        tvBrowseSection = section
        isShowingWatchlist = false
        isShowingLocalLibrary = false
        searchText = ""
        peopleSearchResults = []
        loadTVBrowseSection(section)
    }

    func loadTrendingTV() {
        loadTVBrowseSection(.trending)
    }

    func loadTVBrowseSection(_ section: TVBrowseSection) {
        canLoadMoreTVCatalog = false
        isTVCatalogResult = false
        guard hasToken else {
            televisionShows = [TVShow.demo]
            message = "演示模式 · 配置影片数据 Token 后显示真实电视剧"
            return
        }
        tvBrowseSection = section
        isLoading = true
        message = "正在获取\(section.title)…"
        if section == .recommendations {
            loadDailyTVRecommendation()
            isLoading = false
            return
        }
        Task {
            do {
                let client = TMDBClient(
                    token: token,
                    language: appLanguage.apiCode
                )
                let result: TVPageResult
                if section == .airingToday {
                    result = try await client.airingTodayTV(
                        region: region,
                        page: 1
                    )
                } else {
                    result = try await client.trendingTV(page: 1)
                }
                televisionShows = result.shows
                browseCache.saveTelevision(result.shows)
                tvBrowseNextPage = result.page + 1
                canLoadMoreTVBrowse = result.page < result.totalPages
                message = "\(section.title) · \(televisionShows.count) 部"
            } catch {
                recordServiceDiagnostic(
                    service: "data",
                    endpoint: dataProxyURL,
                    error: error
                )
                if let cached = browseCache.loadTelevision() {
                    televisionShows = cached
                    message = ServiceErrorPresentation.message(
                        language: appLanguage,
                        hasCachedContent: true
                    )
                } else {
                    televisionShows = [TVShow.demo]
                    message = ServiceErrorPresentation.message(
                        language: appLanguage,
                        hasCachedContent: false
                    )
                }
            }
            isLoading = false
        }
    }

    func loadMoreTVBrowseIfNeeded() {
        guard canLoadMoreTVBrowse,
              !isLoadingMoreBrowse,
              !isTVCatalogResult,
              tvBrowseSection != .recommendations,
              hasToken else { return }
        isLoadingMoreBrowse = true
        let requestedPage = tvBrowseNextPage
        let section = tvBrowseSection
        Task {
            do {
                let client = TMDBClient(
                    token: token,
                    language: appLanguage.apiCode
                )
                let result: TVPageResult
                if section == .airingToday {
                    result = try await client.airingTodayTV(
                        region: region,
                        page: requestedPage
                    )
                } else {
                    result = try await client.trendingTV(page: requestedPage)
                }
                var seen = Set(televisionShows.map(\.id))
                televisionShows.append(contentsOf: result.shows.filter {
                    seen.insert($0.id).inserted
                })
                tvBrowseNextPage = result.page + 1
                canLoadMoreTVBrowse = result.page < result.totalPages
                message = "\(section.title) · 已载入 \(televisionShows.count) 部"
            } catch {
                message = error.localizedDescription
            }
            isLoadingMoreBrowse = false
        }
    }

    func setTVCatalogSortMode(_ sortMode: CatalogSortMode) {
        guard tvCatalogSortMode != sortMode else { return }
        tvCatalogSortMode = sortMode
        if isTVCatalogResult {
            applyTVCatalogFilters()
        }
    }

    func applyTVCatalogFilters() {
        guard hasToken else {
            message = "分类选剧需要先配置影片数据 Token"
            showTVCatalog = false
            NotificationCenter.default.post(
                name: .cineBarOpenSettings,
                object: nil
            )
            return
        }
        if !isTVCatalogResult {
            televisionBeforeFilter = televisionShows
            messageBeforeFilter = message
        }
        isLoading = true
        isTVCatalogResult = true
        canLoadMoreTVBrowse = false
        showTVCatalog = false
        searchText = ""
        let periodTitle = tvCatalogPeriod.title(language: appLanguage)
        let genreTitle = TVGenre.options.first {
            $0.id == tvCatalogGenreID
        }?.title
        let countryTitle = tvCatalogCountryCode.map(countryName)
        let filterTitle = [periodTitle, genreTitle, countryTitle]
            .compactMap { $0 }
            .joined(separator: " · ")
        message = "正在筛选 \(filterTitle)…"
        Task {
            do {
                let result = try await TMDBClient(
                    token: token,
                    language: appLanguage.apiCode
                ).discoverTV(
                    startYear: tvCatalogPeriod.startYear,
                    endYear: tvCatalogPeriod.endYear,
                    genreID: tvCatalogGenreID,
                    originCountry: tvCatalogCountryCode,
                    sortMode: tvCatalogSortMode,
                    page: 1
                )
                televisionShows = result.shows
                tvCatalogNextPage = 2
                canLoadMoreTVCatalog = result.page < result.totalPages
                message = result.shows.isEmpty
                    ? "没有符合条件的电视剧"
                    : "\(filterTitle) · 已载入 \(result.shows.count) 部"
            } catch {
                message = error.localizedDescription
            }
            isLoading = false
        }
    }

    func loadMoreTVCatalog() {
        guard canLoadMoreTVCatalog,
              !isLoadingMoreTVCatalog,
              hasToken else { return }
        isLoadingMoreTVCatalog = true
        let requestedPage = tvCatalogNextPage
        Task {
            do {
                let result = try await TMDBClient(
                    token: token,
                    language: appLanguage.apiCode
                ).discoverTV(
                    startYear: tvCatalogPeriod.startYear,
                    endYear: tvCatalogPeriod.endYear,
                    genreID: tvCatalogGenreID,
                    originCountry: tvCatalogCountryCode,
                    sortMode: tvCatalogSortMode,
                    page: requestedPage
                )
                var seen = Set(televisionShows.map(\.id))
                televisionShows.append(contentsOf: result.shows.filter {
                    seen.insert($0.id).inserted
                })
                if tvCatalogSortMode == .rating {
                    televisionShows.sort {
                        if $0.voteAverage != $1.voteAverage {
                            return $0.voteAverage > $1.voteAverage
                        }
                        return $0.voteCount > $1.voteCount
                    }
                }
                tvCatalogNextPage = result.page + 1
                canLoadMoreTVCatalog = result.page < result.totalPages
                message = "\(tvCatalogPeriod.title(language: appLanguage)) · 已载入 \(televisionShows.count) 部"
            } catch {
                message = error.localizedDescription
            }
            isLoadingMoreTVCatalog = false
        }
    }

    func clearAppliedTVCatalogFilters() {
        guard isTVCatalogResult else { return }
        isTVCatalogResult = false
        canLoadMoreTVCatalog = false
        isLoadingMoreTVCatalog = false
        if !televisionBeforeFilter.isEmpty {
            televisionShows = televisionBeforeFilter
            message = messageBeforeFilter
            televisionBeforeFilter = []
        } else {
            loadTrendingTV()
        }
    }

    func selectTV(_ show: TVShow) {
        selectedTVShow = show
        selectedMovie = nil
        selectedPerson = nil
        tvDetails = nil
        tvCast = []
        tvTrailers = []
        tvProviders = []
        tvProviderLink = nil
        tvStills = []
        tvAiringInfo = nil
        tvContentRating = nil
        expandedSeasonNumber = nil
        seasonEpisodes = [:]
        loadCommunityRating(mediaType: .tv, mediaID: show.id)
        doubanRating = nil
        loadDoubanRating(
            title: show.name,
            year: Self.year(from: show.firstAirDate)
        )
        guard show.id > 0, hasToken else { return }

        isLoadingTVDetails = true
        Task {
            let client = TMDBClient(
                token: token,
                language: appLanguage.apiCode
            )
            async let detailsRequest = client.tvDetails(showID: show.id)
            async let castRequest = client.tvCredits(showID: show.id)
            async let trailerRequest = client.tvTrailers(showID: show.id)
            async let providerRequest = client.tvProviders(showID: show.id)
            async let stillsRequest = client.tvStills(showID: show.id)
            async let externalIDsRequest = client.tvExternalIDs(showID: show.id)
            do {
                let details = try await detailsRequest
                tvDetails = details
                tvContentRating = try await client.tvContentRating(
                    showID: show.id,
                    localizedRegion: region.uppercased(),
                    originRegions: details.originCountry
                )
            } catch {
                tvDetails = nil
                tvContentRating = nil
            }
            do { tvCast = try await castRequest } catch { tvCast = [] }
            do { tvTrailers = try await trailerRequest } catch { tvTrailers = [] }
            do { tvStills = try await stillsRequest } catch { tvStills = [] }
            do {
                let regions = try await providerRequest
                let selected = regions[region.uppercased()]
                tvProviders = selected?.all ?? []
                tvProviderLink = selected?.link.flatMap(URL.init(string:))
            } catch {
                tvProviders = []
                tvProviderLink = nil
            }
            do {
                let externalIDs = try await externalIDsRequest
                tvAiringInfo = try await TVMazeClient().nextAiring(
                    externalIDs: externalIDs
                )
            } catch {
                tvAiringInfo = nil
            }
            isLoadingTVDetails = false
        }
    }

    func toggleSeasonEpisodes(showID: Int, season: TVSeason) {
        if expandedSeasonNumber == season.seasonNumber {
            expandedSeasonNumber = nil
            return
        }
        expandedSeasonNumber = season.seasonNumber
        guard seasonEpisodes[season.seasonNumber] == nil,
              showID > 0,
              hasToken else { return }
        isLoadingSeason = true
        Task {
            do {
                let details = try await TMDBClient(
                    token: token,
                    language: appLanguage.apiCode
                ).tvSeason(
                    showID: showID,
                    seasonNumber: season.seasonNumber
                )
                seasonEpisodes[season.seasonNumber] = details.episodes
            } catch {
                seasonEpisodes[season.seasonNumber] = []
                message = error.localizedDescription
            }
            isLoadingSeason = false
        }
    }

    func openStills(for movie: Movie) {
        showMovieStills = true
        if movieStills.isEmpty {
            loadStills(movieID: movie.id)
        }
    }

    func loadStills(movieID: Int) {
        guard movieID > 0, hasToken, !isLoadingStills else { return }
        isLoadingStills = true
        Task {
            do {
                movieStills = try await TMDBClient(
                    token: token,
                    language: appLanguage.apiCode
                ).stills(movieID: movieID)
            } catch {
                movieStills = []
            }
            isLoadingStills = false
        }
    }

    func selectPerson(_ person: CastMember) {
        selectedPerson = person
        personDetails = nil
        personMovies = []
        personTelevision = []
        personImages = []
        personExternalIDs = nil
        isLoadingPerson = true
        Task {
            let client = TMDBClient(
                token: token,
                language: appLanguage.apiCode
            )
            async let detailsRequest = client.personDetails(personID: person.id)
            async let moviesRequest = client.personMovies(personID: person.id)
            async let televisionRequest = client.personTelevision(
                personID: person.id
            )
            async let imagesRequest = client.personImages(personID: person.id)
            async let socialRequest = client.personExternalIDs(personID: person.id)
            do {
                personDetails = try await detailsRequest
            } catch {
                personDetails = nil
            }
            do {
                personMovies = try await moviesRequest
            } catch {
                personMovies = []
            }
            do {
                personTelevision = try await televisionRequest
            } catch {
                personTelevision = []
            }
            do {
                personImages = try await imagesRequest
            } catch {
                personImages = []
            }
            do {
                personExternalIDs = try await socialRequest
            } catch {
                personExternalIDs = nil
            }
            isLoadingPerson = false
        }
    }

    func selectPerson(_ person: PersonSearchResult) {
        selectPerson(
            CastMember(
                id: person.id,
                name: person.name,
                character: person.knownForDepartment ?? "",
                profilePath: person.profilePath,
                order: 0
            )
        )
    }

    func brandedShareURL(for movie: Movie) -> URL? {
        guard hasShareService else { return nil }
        return BrandedShareLink.url(
            baseURL: shareServiceURL,
            mediaType: .movie,
            mediaID: movie.id
        )
    }

    func brandedShareURL(for show: TVShow) -> URL? {
        guard hasShareService else { return nil }
        return BrandedShareLink.url(
            baseURL: shareServiceURL,
            mediaType: .tv,
            mediaID: show.id
        )
    }

    func ratings(for movie: Movie) -> [MovieRating] {
        var result: [MovieRating] = []
        result.append(
            MovieRating(
                source: "TMDB",
                value: String(format: "%.1f/10", movie.voteAverage),
                note: "\(movie.voteCount) 人"
            )
        )
        result += externalRatings
        if let communityRating {
            result.append(
                MovieRating(
                    source: "CineBar",
                    value: communityRating.averageScore.map {
                        String(format: "%.1f/10", $0)
                    } ?? "暂无",
                    note: communityRating.total > 0
                        ? "\(communityRating.total) 人"
                        : "等待首个评分"
                )
            )
            if let myScore = communityRating.myScore {
                result.append(
                    MovieRating(
                        source: "我的评分",
                        value: String(format: "%.1f/10", myScore),
                        note: "提交后不可修改"
                    )
                )
            }
        }
        return result
    }

    func ratings(for show: TVShow) -> [MovieRating] {
        var result: [MovieRating] = []
        result.append(
            MovieRating(
                source: "TMDB",
                value: String(format: "%.1f/10", show.voteAverage),
                note: "\(show.voteCount) 人"
            )
        )
        if let communityRating {
            result.append(
                MovieRating(
                    source: "CineBar",
                    value: communityRating.averageScore.map {
                        String(format: "%.1f/10", $0)
                    } ?? "暂无",
                    note: communityRating.total > 0
                        ? "\(communityRating.total) 人"
                        : "等待首个评分"
                )
            )
            if let myScore = communityRating.myScore {
                result.append(
                    MovieRating(
                        source: "我的评分",
                        value: String(format: "%.1f/10", myScore),
                        note: "提交后不可修改"
                    )
                )
            }
        }
        return result
    }

    private func loadExternalRatings(movieID: Int) {
        guard hasOMDbKey else { return }
        isLoadingRatings = true
        Task {
            do {
                let ids = try await TMDBClient(
                    token: token,
                    language: appLanguage.apiCode
                ).externalIDs(movieID: movieID)
                if let imdbID = ids.imdbID, !imdbID.isEmpty {
                    externalRatings = try await OMDbClient(
                        apiKey: omdbKey,
                        proxyBaseURL: dataProxyURL
                    ).ratings(imdbID: imdbID)
                }
            } catch {
                externalRatings = []
            }
            isLoadingRatings = false
        }
    }

    /// 从 "YYYY-MM-DD" 或 "YYYY" 取出年份。
    private static func year(from dateText: String?) -> Int? {
        guard let dateText, dateText.count >= 4,
              let year = Int(dateText.prefix(4)) else { return nil }
        return year
    }

    /// 豆瓣抓取命中：评分 + 页面跳转信息。
    private struct DoubanHit {
        let rating: MovieRating
        let subjectID: Int
        let pageURL: URL
    }

    /// 按需抓取豆瓣评分并写入 doubanRating；失败或未匹配时置 nil，静默降级。
    private static var doubanCache: [String: DoubanHit?] = [:]

    @Published private(set) var doubanSubjectID: Int?
    @Published private(set) var doubanPageURL: URL?
    @Published private(set) var isLoadingDoubanTrailers = false
    @Published private(set) var doubanTrailers: [DoubanTrailerItem] = []

    private func loadDoubanRating(title: String, year: Int?) {
        let key = "\(title)\(year.map { "|\($0)" } ?? "")"
        if let cached = Self.doubanCache[key] {
            apply(hit: cached, title: title, year: year)
            return
        }
        Task {
            let client = DoubanRatingClient()
            let result: DoubanHit?
            do {
                if let hit = try await client.search(title: title, year: year) {
                    var valueText = String(format: "%.1f", hit.score)
                    valueText += " / 10"
                    result = DoubanHit(
                        rating: MovieRating(
                            source: "豆瓣",
                            value: valueText,
                            note: hit.voteCount.map { "\($0) 人" } ?? "",
                            url: URL(string: hit.pageURL)
                        ),
                        subjectID: hit.doubanID,
                        pageURL: URL(string: hit.pageURL) ?? URL(
                            string: "https://movie.douban.com/subject/\(hit.doubanID)/"
                        )!
                    )
                } else {
                    result = nil
                }
            } catch {
                result = nil
            }
            Self.doubanCache[key] = result
            await MainActor.run {
                apply(hit: result, title: title, year: year)
            }
        }
    }

    private func apply(hit: DoubanHit?, title: String, year: Int?) {
        doubanRating = hit?.rating
        doubanSubjectID = hit?.subjectID
        doubanPageURL = hit?.pageURL
        if let hit {
            let mediaKey = Self.doubanKey(title: title, year: year)
            listDoubanRatings[mediaKey] = hit.rating
        }
        if appLanguage == .zhCN {
            loadDoubanTrailers(subjectID: hit?.subjectID ?? 0)
        } else {
            doubanTrailers = []
        }
    }

    /// 简体中文预告：按豆瓣 subjectID 拉取预告片卡表。
    func loadDoubanTrailers(subjectID: Int) {
        guard appLanguage == .zhCN, subjectID > 0 else {
            doubanTrailers = []
            return
        }
        if isLoadingDoubanTrailers, !doubanTrailers.isEmpty { return }
        isLoadingDoubanTrailers = true
        Task {
            let result = try? await DoubanTrailerClient()
                .trailers(subjectID: subjectID)
            await MainActor.run {
                doubanTrailers = result ?? []
                isLoadingDoubanTrailers = false
            }
        }
    }

    private static func doubanKey(title: String, year: Int?) -> String {
        "\(title)\(year.map { "|\($0)" } ?? "")"
    }

    #if CINEBAR_TEST
    /// 测试辅助：注入豆瓣评分（与 apply 相同的写入路径）。
    func setDoubanRatingForTesting(_ rating: MovieRating) {
        doubanRating = rating
        doubanSubjectID = 1_292_001
        doubanPageURL = rating.url
        listDoubanRatings[
            Self.doubanKey(
                title: Movie.demo[0].title,
                year: Self.year(from: Movie.demo[0].releaseDate)
            )
        ] = rating
    }

    /// 测试辅助：注入外部评分（IMDb/烂番茄）与跳转 URL。
    func setExternalRatingsForTesting(
        movieID: Int,
        ratings: [MovieRating]
    ) {
        externalRatings = ratings
        listExternalRatings[String(movieID)] = ratings
    }
    #endif

    // MARK: - 列表行评分（按语言切换首选来源）

    private var listRatingLoadKeys: Set<String> = []

    /// 首页/列表行展示的评分：优先 IMDb/烂番茄，缺省回退 TMDB。
    func listRating(for movie: Movie) -> MovieRating? {
        if let external = listExternalRatings[String(movie.id)] {
            if let imdb = external.first(where: { $0.source == "IMDb" }) {
                return imdb
            }
            if let rotten = external.first(where: { $0.source == "烂番茄" }) {
                return rotten
            }
        }
        return MovieRating(
            source: "TMDB",
            value: String(format: "%.1f/10", movie.voteAverage),
            note: "\(movie.voteCount) 人"
        )
    }

    /// 首页/列表行展示的评分（剧集版）。
    func listRating(for show: TVShow) -> MovieRating? {
        if let external = listExternalRatings[String(show.id)] {
            if let imdb = external.first(where: { $0.source == "IMDb" }) {
                return imdb
            }
            if let rotten = external.first(where: { $0.source == "烂番茄" }) {
                return rotten
            }
        }
        return MovieRating(
            source: "TMDB",
            value: String(format: "%.1f/10", show.voteAverage),
            note: "\(show.voteCount) 人"
        )
    }

    /// 列表行评分右下角的人数文本。
    func listRatingCount(for movie: Movie) -> String? {
        if let external = listExternalRatings[String(movie.id)],
           let first = external.first(where: { $0.source == "IMDb" })
            ?? external.first(where: { $0.source == "烂番茄" }) {
            return first.note
        }
        return movie.voteCount > 0 ? "\(movie.voteCount)人" : nil
    }

    /// 列表行评分右下角的人数文本（剧集版）。
    func listRatingCount(for show: TVShow) -> String? {
        if let external = listExternalRatings[String(show.id)],
           let first = external.first(where: { $0.source == "IMDb" })
            ?? external.first(where: { $0.source == "烂番茄" }) {
            return first.note
        }
        return show.voteCount > 0 ? "\(show.voteCount)人" : nil
    }

    /// 行可见时触发加载首选评分（带去重，每个条目只请求一次）。
    func ensureListRating(for movie: Movie) {
        let key = Self.doubanKey(
            title: movie.title,
            year: Self.year(from: movie.releaseDate)
        )
        if appLanguage == .zhCN {
            guard listDoubanRatings[key] == nil,
                  !listRatingLoadKeys.contains(key) else { return }
            listRatingLoadKeys.insert(key)
            Task {
                let client = DoubanRatingClient()
                if let hit = try? await client.search(
                    title: movie.title,
                    year: Self.year(from: movie.releaseDate)
                ) {
                    var valueText = String(format: "%.1f", hit.score)
                    valueText += " / 10"
                    let rating = MovieRating(
                        source: "豆瓣",
                        value: valueText,
                        note: hit.voteCount.map { "\($0) 人" } ?? "",
                        url: URL(string: hit.pageURL)
                    )
                    await MainActor.run {
                        listDoubanRatings[key] = rating
                    }
                }
            }
        } else {
            let idKey = String(movie.id)
            guard listExternalRatings[idKey] == nil,
                  !listRatingLoadKeys.contains(idKey),
                  hasOMDbKey else { return }
            listRatingLoadKeys.insert(idKey)
            Task {
                let client = TMDBClient(
                    token: token,
                    language: appLanguage.apiCode
                )
                guard let ids = try? await client.externalIDs(movieID: movie.id),
                      let imdbID = ids.imdbID, !imdbID.isEmpty else { return }
                let ratings = try? await OMDbClient(
                    apiKey: omdbKey,
                    proxyBaseURL: dataProxyURL
                ).ratings(imdbID: imdbID, title: movie.title)
                await MainActor.run {
                    listExternalRatings[idKey] = ratings ?? []
                }
            }
        }
    }

    /// 行可见时触发加载首选评分（剧集版）。
    func ensureListRating(for show: TVShow) {
        let key = Self.doubanKey(
            title: show.name,
            year: Self.year(from: show.firstAirDate)
        )
        if appLanguage == .zhCN {
            guard listDoubanRatings[key] == nil,
                  !listRatingLoadKeys.contains(key) else { return }
            listRatingLoadKeys.insert(key)
            Task {
                let client = DoubanRatingClient()
                if let hit = try? await client.search(
                    title: show.name,
                    year: Self.year(from: show.firstAirDate)
                ) {
                    var valueText = String(format: "%.1f", hit.score)
                    valueText += " / 10"
                    let rating = MovieRating(
                        source: "豆瓣",
                        value: valueText,
                        note: hit.voteCount.map { "\($0) 人" } ?? "",
                        url: URL(string: hit.pageURL)
                    )
                    await MainActor.run {
                        listDoubanRatings[key] = rating
                    }
                }
            }
        } else {
            let idKey = String(show.id)
            guard listExternalRatings[idKey] == nil,
                  !listRatingLoadKeys.contains(idKey),
                  hasOMDbKey else { return }
            listRatingLoadKeys.insert(idKey)
            Task {
                let client = TMDBClient(
                    token: token,
                    language: appLanguage.apiCode
                )
                guard let ids = try? await client.tvExternalIDs(showID: show.id),
                      let imdbID = ids.imdbID, !imdbID.isEmpty else { return }
                let ratings = try? await OMDbClient(
                    apiKey: omdbKey,
                    proxyBaseURL: dataProxyURL
                ).ratings(imdbID: imdbID, title: show.name)
                await MainActor.run {
                    listExternalRatings[idKey] = ratings ?? []
                }
            }
        }
    }

    private func updateDailyRecommendation(
        from candidates: [Movie],
        forceRefresh: Bool = false
    ) {
        let eligible = candidates.filter { $0.voteAverage > 0 && !$0.overview.isEmpty }
        guard !eligible.isEmpty else { return }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        let preferenceKey = [
            preferredMovieGenreIDs.sorted().map(String.init).joined(separator: ","),
            preferredMovieCountryCodes.sorted().joined(separator: ",")
        ].joined(separator: "|")

        if !forceRefresh,
           defaults.string(forKey: "dailyMovieDate") == today,
           defaults.string(forKey: "dailyMoviePreferenceKey") == preferenceKey,
           let data = defaults.data(forKey: "dailyMovies"),
           let cached = try? JSONDecoder().decode([Movie].self, from: data),
           !cached.isEmpty {
            dailyMovies = cached
            dailyMovie = cached.first
            return
        }

        let dayNumber = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        let selected: [Movie]
        if forceRefresh {
            selected = Array(eligible.shuffled().prefix(3))
        } else {
            selected = (0..<min(3, eligible.count)).map { offset in
                eligible[(dayNumber * 37 + offset * 17) % eligible.count]
            }
        }
        dailyMovies = selected
        dailyMovie = selected.first
        defaults.set(today, forKey: "dailyMovieDate")
        defaults.set(preferenceKey, forKey: "dailyMoviePreferenceKey")
        if let data = try? JSONEncoder().encode(selected) {
            defaults.set(data, forKey: "dailyMovies")
        }
    }

    private func updateDailyTVRecommendation(
        from candidates: [TVShow],
        forceRefresh: Bool
    ) {
        let eligible = candidates.filter {
            $0.voteAverage > 0 && !$0.overview.isEmpty
        }
        guard !eligible.isEmpty else { return }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        let preferenceKey = [
            preferredTVGenreIDs.sorted().map(String.init).joined(separator: ","),
            preferredTVCountryCodes.sorted().joined(separator: ",")
        ].joined(separator: "|")
        if !forceRefresh,
           defaults.string(forKey: "dailyTVDate") == today,
           defaults.string(forKey: "dailyTVPreferenceKey") == preferenceKey,
           let data = defaults.data(forKey: "dailyTVShows"),
           let cached = try? JSONDecoder().decode([TVShow].self, from: data),
           !cached.isEmpty {
            dailyTVShows = cached
            dailyTVShow = cached.first
            return
        }
        let dayNumber = Calendar.current.ordinality(
            of: .day,
            in: .era,
            for: Date()
        ) ?? 0
        let selected: [TVShow]
        if forceRefresh {
            selected = Array(eligible.shuffled().prefix(3))
        } else {
            selected = (0..<min(3, eligible.count)).map { offset in
                eligible[(dayNumber * 29 + offset * 13) % eligible.count]
            }
        }
        dailyTVShows = selected
        dailyTVShow = selected.first
        defaults.set(today, forKey: "dailyTVDate")
        defaults.set(preferenceKey, forKey: "dailyTVPreferenceKey")
        if let data = try? JSONEncoder().encode(selected) {
            defaults.set(data, forKey: "dailyTVShows")
        }
    }
}

struct PosterView: View {
    let movie: Movie
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Group {
            if let url = movie.posterURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholder
                    default:
                        ZStack {
                            Color.secondary.opacity(0.12)
                            ProgressView().controlSize(.small)
                        }
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [.indigo.opacity(0.75), .purple.opacity(0.45)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "film.stack")
                .font(.system(size: width * 0.34))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}

/// 双列网格卡片：大图海报 + 片名 + 评分 + 简介（方案 B）。
/// 按用户确认：去掉年份与评分人数，简介最多 2 行，点击进详情。
/// 海报带类 Apple TV 的鼠标视差 3D 交互。
struct MovieCardView: View {
    @ObservedObject var store: MovieStore
    let movie: Movie
    @State private var isHovering = false
    @State private var hoverOffset = CGSize.zero
    @State private var posterImage: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardPoster
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(movie.title)
                        .font(.callout.bold())
                        .lineLimit(1)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                    if let rating = store.listRating(for: movie) {
                        Text(rating.compactValue)
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                            .help(rating.source)
                    }
                }
                Text(movie.overview.isEmpty ? "暂无中文简介" : movie.overview)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(.horizontal, 2)
            .padding(.top, 7)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("复制片名") {
                copyToPasteboard(movie.title)
            }
        }
        .onAppear {
            store.ensureListRating(for: movie)
        }
        .task(id: movie.posterURL) {
            if let url = movie.posterURL {
                posterImage = await cachedPosterImage(for: url)
            } else {
                posterImage = nil
            }
        }
    }

    private var cardPoster: some View {
        ZStack {
            GeometryReader { proxy in
                ZStack {
                    // 平面命中层：不随 3D 旋转，保证光标能在卡片任意位置触发 hover
                    ZStack {
                        // 3D 视觉层：多层视差（景深/主图/反光）+ 阴影 + 轻旋转
                        ZStack {
                            // 背景景深层：hover 时放大错位、压暗，造成纵深
                            if isHovering, let posterImage {
                                Image(nsImage: posterImage)
                                    .resizable()
                                    .scaledToFill()
                                    .scaleEffect(1.22)
                                    .offset(
                                        x: hoverOffset.width * 0.06,
                                        y: hoverOffset.height * 0.06
                                    )
                                    .brightness(-0.35)
                                    .saturation(0.85)
                                    .blur(radius: 1.5)
                            }

                            // 主图层：随鼠标平移，是立体感核心
                            Group {
                                if let posterImage {
                                    Image(nsImage: posterImage)
                                        .resizable()
                                        .scaledToFill()
                                } else if movie.posterURL != nil {
                                    ZStack {
                                        Color.secondary.opacity(0.12)
                                        ProgressView().controlSize(.small)
                                    }
                                } else {
                                    cardPlaceholder
                                }
                            }
                            .scaleEffect(isHovering ? 1.12 : 1.0)
                            .offset(
                                x: hoverOffset.width * 0.08,
                                y: hoverOffset.height * 0.08
                            )
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .rotation3DEffect(
                            .degrees(parallaxAngle(for: proxy.size, isYaw: true)),
                            axis: (x: 0, y: 1, z: 0),
                            perspective: 0.35
                        )
                        .rotation3DEffect(
                            .degrees(parallaxAngle(for: proxy.size, isYaw: false)),
                            axis: (x: 1, y: 0, z: 0),
                            perspective: 0.35
                        )
                        .clipShape(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                        .shadow(
                            color: .black.opacity(isHovering ? 0.30 : 0.10),
                            radius: isHovering ? 16 : 8,
                            y: isHovering ? 8 : 4
                        )
                        .animation(
                            .easeOut(duration: 0.18),
                            value: hoverOffset
                        )
                        .animation(
                            .easeOut(duration: 0.35),
                            value: isHovering
                        )
                        .allowsHitTesting(false)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .contentShape(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .onContinuousHover(coordinateSpace: .local) { phase in
                        switch phase {
                        case .active(let location):
                            isHovering = true
                            hoverOffset = CGSize(
                                width: location.x - proxy.size.width / 2,
                                height: location.y - proxy.size.height / 2
                            )
                        case .ended:
                            isHovering = false
                            hoverOffset = .zero
                        }
                    }
                }
            }
        }
        .aspectRatio(2 / 3, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }

    private func parallaxAngle(for size: CGSize, isYaw: Bool) -> CGFloat {
        guard isHovering, size.width > 0, size.height > 0 else { return 0 }
        let maxDegrees: CGFloat = 6
        let normalized = isYaw
            ? hoverOffset.width / (size.width / 2)
            : -hoverOffset.height / (size.height / 2)
        return max(-maxDegrees, min(maxDegrees, normalized * maxDegrees))
    }

    private var cardPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [.indigo.opacity(0.75), .purple.opacity(0.45)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "film.stack")
                .font(.system(size: 34))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}

/// 剧集版双列网格卡片。
struct TVCardView: View {
    @ObservedObject var store: MovieStore
    let show: TVShow
    @State private var isHovering = false
    @State private var hoverOffset = CGSize.zero
    @State private var posterImage: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardPoster
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(show.name)
                        .font(.callout.bold())
                        .lineLimit(1)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                    if let rating = store.listRating(for: show) {
                        Text(rating.compactValue)
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                            .help(rating.source)
                    }
                }
                Text(show.overview.isEmpty ? "暂无简介" : show.overview)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(.horizontal, 2)
            .padding(.top, 7)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("复制剧名") {
                copyToPasteboard(show.name)
            }
        }
        .onAppear {
            store.ensureListRating(for: show)
        }
        .task(id: show.posterURL) {
            if let url = show.posterURL {
                posterImage = await cachedPosterImage(for: url)
            } else {
                posterImage = nil
            }
        }
    }

    private var cardPoster: some View {
        ZStack {
            GeometryReader { proxy in
                ZStack {
                    // 平面命中层：不随 3D 旋转，保证光标能在卡片任意位置触发 hover
                    ZStack {
                        // 3D 视觉层：多层视差（景深/主图/反光）+ 阴影 + 轻旋转
                        ZStack {
                            // 背景景深层：hover 时放大错位、压暗，造成纵深
                            if isHovering, let posterImage {
                                Image(nsImage: posterImage)
                                    .resizable()
                                    .scaledToFill()
                                    .scaleEffect(1.22)
                                    .offset(
                                        x: hoverOffset.width * 0.06,
                                        y: hoverOffset.height * 0.06
                                    )
                                    .brightness(-0.35)
                                    .saturation(0.85)
                                    .blur(radius: 1.5)
                            }

                            // 主图层：随鼠标平移，是立体感核心
                            Group {
                                if let posterImage {
                                    Image(nsImage: posterImage)
                                        .resizable()
                                        .scaledToFill()
                                } else if show.posterURL != nil {
                                    ZStack {
                                        Color.secondary.opacity(0.12)
                                        ProgressView().controlSize(.small)
                                    }
                                } else {
                                    cardPlaceholder
                                }
                            }
                            .scaleEffect(isHovering ? 1.12 : 1.0)
                            .offset(
                                x: hoverOffset.width * 0.08,
                                y: hoverOffset.height * 0.08
                            )
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .rotation3DEffect(
                            .degrees(parallaxAngle(for: proxy.size, isYaw: true)),
                            axis: (x: 0, y: 1, z: 0),
                            perspective: 0.35
                        )
                        .rotation3DEffect(
                            .degrees(parallaxAngle(for: proxy.size, isYaw: false)),
                            axis: (x: 1, y: 0, z: 0),
                            perspective: 0.35
                        )
                        .clipShape(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                        .shadow(
                            color: .black.opacity(isHovering ? 0.30 : 0.10),
                            radius: isHovering ? 16 : 8,
                            y: isHovering ? 8 : 4
                        )
                        .animation(
                            .easeOut(duration: 0.18),
                            value: hoverOffset
                        )
                        .animation(
                            .easeOut(duration: 0.35),
                            value: isHovering
                        )
                        .allowsHitTesting(false)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .contentShape(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
                    .onContinuousHover(coordinateSpace: .local) { phase in
                        switch phase {
                        case .active(let location):
                            isHovering = true
                            hoverOffset = CGSize(
                                width: location.x - proxy.size.width / 2,
                                height: location.y - proxy.size.height / 2
                            )
                        case .ended:
                            isHovering = false
                            hoverOffset = .zero
                        }
                    }
                }
            }
        }
        .aspectRatio(2 / 3, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }

    private func parallaxAngle(for size: CGSize, isYaw: Bool) -> CGFloat {
        guard isHovering, size.width > 0, size.height > 0 else { return 0 }
        let maxDegrees: CGFloat = 6
        let normalized = isYaw
            ? hoverOffset.width / (size.width / 2)
            : -hoverOffset.height / (size.height / 2)
        return max(-maxDegrees, min(maxDegrees, normalized * maxDegrees))
    }

    private var cardPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [.indigo.opacity(0.75), .purple.opacity(0.45)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "film.stack")
                .font(.system(size: 34))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}

enum UpcomingReleasePresentation: Equatable {
    case dated(String)
    case undated

    static func make(
        rawValue: String?,
        language: AppLanguage
    ) -> UpcomingReleasePresentation {
        guard let rawValue,
              let normalized = MovieReleaseDatePolicy.normalizedDate(rawValue)
        else {
            return .undated
        }

        let input = DateFormatter()
        input.calendar = Calendar(identifier: .gregorian)
        input.locale = Locale(identifier: "en_US_POSIX")
        input.timeZone = TimeZone(secondsFromGMT: 0)
        input.dateFormat = "yyyy-MM-dd"
        input.isLenient = false
        guard let date = input.date(from: normalized) else {
            return .undated
        }
        let weekday = Calendar(identifier: .gregorian).component(
            .weekday,
            from: date
        )

        let output = DateFormatter()
        output.calendar = Calendar(identifier: .gregorian)
        output.timeZone = TimeZone(secondsFromGMT: 0)
        let weekdayText: String
        switch language {
        case .zhCN:
            output.locale = Locale(identifier: language.localeIdentifier)
            output.dateFormat = "yyyy年M月d日"
            weekdayText = ["", "周日", "周一", "周二", "周三", "周四", "周五", "周六"][weekday]
        case .zhHK, .zhTW:
            output.locale = Locale(identifier: language.localeIdentifier)
            output.dateFormat = "yyyy年M月d日"
            weekdayText = ["", "週日", "週一", "週二", "週三", "週四", "週五", "週六"][weekday]
        case .enUS:
            output.locale = Locale(identifier: "en_US")
            output.dateFormat = "MMM d, yyyy"
            weekdayText = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][weekday]
        case .jaJP:
            output.locale = Locale(identifier: "ja_JP")
            output.dateFormat = "yyyy年M月d日"
            weekdayText = ["", "日", "月", "火", "水", "木", "金", "土"][weekday]
        case .koKR:
            output.locale = Locale(identifier: "ko_KR")
            output.dateFormat = "yyyy년 M월 d일"
            weekdayText = ["", "일요일", "월요일", "화요일", "수요일", "목요일", "금요일", "토요일"][weekday]
        }
        let dateText = output.string(from: date)
        switch language {
        case .zhCN:
            return .dated("\(dateText)（\(weekdayText)）")
        case .zhHK, .zhTW:
            return .dated("\(dateText)（\(weekdayText)）")
        case .enUS:
            return .dated("\(weekdayText), \(dateText)")
        case .jaJP:
            return .dated("\(dateText)（\(weekdayText)）")
        case .koKR:
            return .dated("\(dateText)（\(weekdayText)）")
        }
    }
}

enum MovieRowPresentation {
    static func upcomingRelease(
        section: MovieBrowseSection,
        rawValue: String?,
        language: AppLanguage
    ) -> UpcomingReleasePresentation? {
        guard section == .upcoming else { return nil }
        return UpcomingReleasePresentation.make(
            rawValue: rawValue,
            language: language
        )
    }
}

struct MovieRow: View {
    @ObservedObject var store: MovieStore
    let movie: Movie
    var upcomingRelease: UpcomingReleasePresentation? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PosterView(movie: movie, width: 66, height: 96)

            VStack(alignment: .leading, spacing: 5) {
                if let upcomingRelease {
                    switch upcomingRelease {
                    case .dated(let date):
                        Label(date, systemImage: "calendar")
                            .font(.caption2.bold())
                            .foregroundStyle(.indigo)
                    case .undated:
                        Label(
                            "上映日期待定",
                            systemImage: "calendar.badge.questionmark"
                        )
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                    }
                }

                Text(movie.title)
                    .font(.headline)
                    .lineLimit(2)
                    .textSelection(.enabled)

                HStack(spacing: 8) {
                    if let rating = store.listRating(for: movie) {
                        Text(rating.compactValue)
                            .foregroundStyle(.primary)
                            .help(rating.source)
                    }
                    Text(movie.year)
                        .foregroundStyle(.secondary)
                    if let count = store.listRatingCount(for: movie) {
                        Text(count)
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.caption)

                Text(movie.overview.isEmpty ? "暂无中文简介" : movie.overview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 6)
        .contextMenu {
            Button("复制片名") {
                copyToPasteboard(movie.title)
            }
        }
        .onAppear {
            store.ensureListRating(for: movie)
        }
    }
}

struct RatingBadge: View {
    let rating: MovieRating
    @Environment(\.openURL) private var openURL

    private var accent: Color {
        switch rating.source {
        case "TMDB": return .green
        case "豆瓣": return .teal
        case "IMDb": return .yellow
        case "烂番茄": return .red
        case "Metacritic": return .blue
        default: return .orange
        }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(rating.source)
                .font(.caption2.bold())
                .foregroundStyle(accent)
            Text(rating.value)
                .font(.headline.monospacedDigit())
            Text(rating.note)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minWidth: 94, alignment: .leading)
        .background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
    }

    var body: some View {
        if let url = rating.url {
            Button {
                openURL(url)
            } label: {
                label.overlay(alignment: .topTrailing) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(3)
                }
            }
            .buttonStyle(.plain)
            .help("打开评分来源页面")
        } else {
            label
        }
    }
}

/// "磁力下载"按钮：按片名匹配磁力链接，点击后用系统默认
/// 下载器（迅雷等）打开 magnet。进入详情页自动预检一次：
/// 找到→可点击；找不到→灰色按钮提示"等待更新"。
struct Hao6vMagnetButton: View {
    let title: String
    let year: String

    @State private var status: Hao6vStatus = .resolving
    @State private var magnet: String?
    @State private var magnetTask: Task<Void, Never>?

    enum Hao6vStatus {
        case resolving
        case available
        case unavailable
    }

    var body: some View {
        HStack(spacing: 10) {
            if status == .available, let magnet, let url = URL(string: magnet) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("磁力下载", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    copyMagnet(magnet)
                } label: {
                    Label("复制磁力", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .help("把磁力链接复制到剪贴板")
            } else {
                Button {
                    // 未就绪时点击无效。
                } label: {
                    Label(labelText, systemImage: systemImageName)
                }
                .buttonStyle(.borderedProminent)
                .disabled(true)
            }

            Text(auxiliaryText)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .onAppear {
            guard status == .resolving, magnetTask == nil else { return }
            let year = year.isEmpty ? nil : year
            magnetTask = Task {
                let found = await Hao6vMagnetResolver.magnetFor(
                    title: title, year: year
                )
                guard !Task.isCancelled else { return }
                if let found {
                    magnet = found
                    status = .available
                } else {
                    status = .unavailable
                }
            }
        }
        .onDisappear {
            magnetTask?.cancel()
            magnetTask = nil
        }
    }

    private func copyMagnet(_ magnet: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(magnet, forType: .string)
    }

    private var labelText: String {
        switch status {
        case .resolving: return "正在匹配磁力…"
        case .available: return "磁力下载"
        case .unavailable: return "等待更新"
        }
    }

    private var systemImageName: String {
        switch status {
        case .resolving: return "arrow.triangle.2.circlepath"
        case .available: return "arrow.down.circle"
        case .unavailable: return "clock"
        }
    }

    private var auxiliaryText: String {
        switch status {
        case .available: return "将在下载器中打开磁力链接"
        case .unavailable: return "该片暂无磁力资源，等更新后再看"
        case .resolving: return "正在匹配磁力…"
        }
    }
}

/// 磁力索引库设置卡：显示容量与上次更新时间，可手动触发全站扫描建库。
struct MagnetIndexCard: View {
    @State private var total = 0
    @State private var done = 0
    @State private var isScanning = false
    @State private var scanTask: Task<Void, Never>?
    @State private var lastUpdatedText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("磁力下载索引库").font(.subheadline.bold())
            HStack(spacing: 12) {
                Label("已收录 \(total) 部", systemImage: "internaldrive")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    startScan()
                } label: {
                    Label(
                        isScanning
                            ? "抓取中 \(done)…"
                            : "全站抓取",
                        systemImage: isScanning
                            ? "arrow.triangle.2.circlepath"
                            : "icloud.and.arrow.down"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(isScanning)
            }
            if isScanning {
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                    .controlSize(.small)
                Text("正在抓取详情页，首次全站约需 20~60 分钟，期间可正常使用")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(lastUpdatedText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            refresh()
        }
        .onDisappear {
            scanTask?.cancel()
        }
    }

    private func refresh() {
        total = Hao6vMagnetStore.shared.count()
        let date = Hao6vMagnetStore.shared.lastUpdatedDate()
        if date.timeIntervalSince1970 > 0 {
            lastUpdatedText = "上次更新："
                + date.formatted(date: .abbreviated, time: .shortened)
        } else {
            lastUpdatedText = "尚未抓取过"
        }
    }

    private func startScan() {
        guard !isScanning else { return }
        isScanning = true
        total = Hao6vMagnetStore.shared.count()
        scanTask = Task {
            await Hao6vMagnetResolver.scanIndex { done, pageTotal, _ in
                Task { @MainActor in
                    self.total = max(
                        self.total, Hao6vMagnetStore.shared.count()
                    )
                    self.done = done
                    _ = pageTotal
                }
            }
            await MainActor.run {
                isScanning = false
                refresh()
            }
        }
    }
}

final class RatingNSSlider: NSSlider {
    convenience init() {
        self.init(frame: .zero)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    private func configure() {
        minValue = 0
        maxValue = 10
        numberOfTickMarks = 21
        tickMarkPosition = .below
        allowsTickMarkValuesOnly = true
        isContinuous = true
        controlSize = .large
    }
}

struct RatingSlider: NSViewRepresentable {
    @Binding var value: Double

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value)
    }

    func makeNSView(context: Context) -> RatingNSSlider {
        let slider = RatingNSSlider()
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.valueChanged(_:))
        slider.doubleValue = value
        return slider
    }

    func updateNSView(_ slider: RatingNSSlider, context: Context) {
        if slider.doubleValue != value {
            slider.doubleValue = value
        }
        context.coordinator.value = $value
    }

    final class Coordinator: NSObject {
        var value: Binding<Double>

        init(value: Binding<Double>) {
            self.value = value
        }

        @objc func valueChanged(_ sender: NSSlider) {
            value.wrappedValue = sender.doubleValue
        }
    }
}

struct CommunityRatingPanel: View {
    @ObservedObject var store: MovieStore
    let mediaType: CommunityMediaType
    let mediaID: Int
    @State private var isConfirmingRating = false

    @ViewBuilder
    var body: some View {
        if RatingPresentation.shouldShowEditor(
            myScore: store.communityRating?.myScore,
            isLoading: store.isLoadingCommunityRating
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("我的评分", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.headline)
                }
                Label(
                    "每部影片只能评分一次，提交后不可修改或删除，请谨慎评分。",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.callout.bold())
                .foregroundStyle(.red)
                RatingSlider(value: $store.communityRatingDraft)
                    .frame(height: 38)
                    .disabled(store.isLoadingCommunityRating)
                HStack {
                    Text("当前评分")
                        .font(.callout.bold())
                    Text(String(format: "%.1f", store.communityRatingDraft))
                        .font(.title2.bold().monospacedDigit())
                        .foregroundStyle(.orange)
                    Spacer()
                    Text("0–10")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button("保存评分") {
                        isConfirmingRating = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        !store.hasCommunityService ||
                            store.isLoadingCommunityRating
                    )
                }
                if !store.communityRatingMessage.isEmpty {
                    Text(store.communityRatingMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(
                Color.orange.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .confirmationDialog(
                "评分提交后不可修改",
                isPresented: $isConfirmingRating,
                titleVisibility: .visible
            ) {
                Button("确认提交评分", role: .destructive) {
                    store.saveCommunityRating(
                        mediaType: mediaType,
                        mediaID: mediaID
                    )
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("每部影片只能评分一次，提交后不可修改或删除，请谨慎评分。")
            }
        } else if store.isLoadingCommunityRating &&
                    store.communityRating == nil {
            ProgressView("正在加载 CineBar 评分…")
                .controlSize(.small)
        }
    }
}

struct CertificationCardMetrics {
    static let width: CGFloat = 112
    static let height: CGFloat = 38
    static let minWidth: CGFloat = width
    static let minHeight: CGFloat = height
    static let horizontalPadding: CGFloat = 6
    static let verticalPadding: CGFloat = 4
    static let cornerRadius: CGFloat = 8
}

struct ContentRatingBadge: View {
    let rating: ContentRatingSummary?

    var body: some View {
        let presentation = ContentRatingPresentation(rating)
        HStack(spacing: 10) {
            CertificationCard(
                label: presentation.regionLabel,
                value: presentation.officialValue,
                accent: .red,
                symbol: "person.badge.shield.checkmark.fill"
            )
            CertificationCard(
                label: "CineBar 分级",
                value: presentation.cineBarValue,
                accent: .orange,
                symbol: "play.rectangle.fill"
            )
        }
        .help("优先显示当前地区分级，其次制片地区、美国；CineBar 标签为统一年龄提示")
    }
}

private struct CertificationCard: View {
    let label: String
    let value: String
    let accent: Color
    let symbol: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(label))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(LocalizedStringKey(value))
                    .font(.title.bold())
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            Spacer(minLength: 0)
        }
        .frame(
            width: CertificationCardMetrics.width,
            height: CertificationCardMetrics.height
        )
        .padding(.horizontal, CertificationCardMetrics.horizontalPadding)
        .padding(.vertical, CertificationCardMetrics.verticalPadding)
        .background(
            accent.opacity(0.08),
            in: RoundedRectangle(
                cornerRadius: CertificationCardMetrics.cornerRadius
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: CertificationCardMetrics.cornerRadius
            )
                .stroke(accent.opacity(0.22), lineWidth: 1)
        }
    }
}

struct CastMemberCard: View {
    let member: CastMember

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let url = member.profileURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            castPlaceholder
                        default:
                            ZStack {
                                Color.secondary.opacity(0.10)
                                ProgressView().controlSize(.mini)
                            }
                        }
                    }
                } else {
                    castPlaceholder
                }
            }
            .frame(width: 74, height: 90)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(member.name)
                .font(.caption.bold())
                .lineLimit(1)
            Text(member.character.isEmpty ? "—" : member.character)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 84)
    }

    private var castPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [.secondary.opacity(0.16), .indigo.opacity(0.12)],
                startPoint: .top,
                endPoint: .bottom
            )
            Image(systemName: "person.crop.square.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }
}

struct BoxOfficeView: View {
    let financials: MovieFinancials?
    let isLoading: Bool
    var language: AppLanguage = .zhCN
    @State private var usdToCNY: Double?
    @State private var rateIsStale = false

    private static let rateCacheKey = "usd-cny-rate"
    private static let rateCacheDateKey = "usd-cny-rate-date"
    private static let rateRefreshInterval: TimeInterval = 24 * 60 * 60

    private func currency(_ value: Int64) -> String {
        if language == .zhCN, let rate = usdToCNY {
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.currencyCode = "CNY"
            formatter.maximumFractionDigits = 0
            let converted = Double(value) * rate
            return formatter.string(from: NSNumber(value: converted)) ?? "¥\(Int(converted))"
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$\(value)"
    }

    private func loadUSDCNYRate() {
        guard language == .zhCN else {
            usdToCNY = nil
            return
        }
        let defaults = UserDefaults.standard
        if let cached = defaults.object(forKey: Self.rateCacheKey) as? Double,
           let date = defaults.object(forKey: Self.rateCacheDateKey) as? Date,
           Date().timeIntervalSince(date) < Self.rateRefreshInterval {
            usdToCNY = cached
            rateIsStale = false
            return
        }
        Task {
            let rate = await fetchUSDCNYRate()
            await MainActor.run {
                usdToCNY = rate
                rateIsStale = rate == nil
                if let rate {
                    defaults.set(rate, forKey: Self.rateCacheKey)
                    defaults.set(Date(), forKey: Self.rateCacheDateKey)
                }
            }
        }
    }

    private func fetchUSDCNYRate() async -> Double? {
        let sources = [
            URL(string: "https://open.er-api.com/v6/latest/USD")!,
            URL(string: "https://api.frankfurter.app/latest?from=USD&to=CNY")!
        ]
        for source in sources {
            do {
                let (data, _) = try await URLSession.shared.data(from: source)
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let rates = json["rates"] as? [String: Any],
                       let rate = rates["CNY"] as? Double {
                        return rate
                    }
                    if let rate = json["rate"] as? Double {
                        return rate
                    }
                }
            } catch {
                continue
            }
        }
        return nil
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.title2)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("全球累计票房")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if isLoading {
                    ProgressView().controlSize(.mini)
                } else if let financials, financials.revenue > 0 {
                    Text(currency(financials.revenue))
                        .font(.headline.monospacedDigit())
                } else {
                    Text("暂无票房数据")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(unitFootnote)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .cineGlass(cornerRadius: 10)
        .task(id: language) {
            loadUSDCNYRate()
        }
    }

    private var unitFootnote: String {
        guard language == .zhCN else { return "美元 · 非实时" }
        return "人民币"
    }
}

struct MovieFactsView: View {
    let financials: MovieFinancials?
    let releaseSummary: MovieReleaseSummary?
    let directors: [CrewMember]
    let isLoading: Bool
    let language: AppLanguage
    let movieTitle: String

    private var globalRawDate: String? {
        MovieReleaseDatePolicy.normalizedDate(
            releaseSummary?.globalPremiere ?? financials?.releaseDate ?? ""
        )
    }

    private var localizedRawDate: String? {
        MovieReleaseDatePolicy.normalizedDate(
            releaseSummary?.localizedRelease ?? ""
        )
    }

    private var globalDate: String {
        formatDate(
            releaseSummary?.globalPremiere ?? financials?.releaseDate
        )
    }

    private var localizedDate: String {
        formatDate(releaseSummary?.localizedRelease)
    }

    private var runtimeText: String {
        guard let runtime = financials?.runtime, runtime > 0 else {
            return unavailable
        }
        let hours = runtime / 60
        let minutes = runtime % 60
        switch language {
        case .zhCN:
            return hours > 0 ? "\(hours) 小时 \(minutes) 分钟" : "\(minutes) 分钟"
        case .zhHK, .zhTW:
            return hours > 0 ? "\(hours) 小時 \(minutes) 分鐘" : "\(minutes) 分鐘"
        case .enUS:
            return hours > 0 ? "\(hours) hr \(minutes) min" : "\(minutes) min"
        case .jaJP:
            return hours > 0 ? "\(hours)時間\(minutes)分" : "\(minutes)分"
        case .koKR:
            return hours > 0 ? "\(hours)시간 \(minutes)분" : "\(minutes)분"
        }
    }

    private var countriesText: String {
        let countries = financials?.productionCountries ?? []
        guard !countries.isEmpty else { return unavailable }
        return countries.map {
            $0.name.isEmpty ? $0.isoCode : $0.name
        }.joined(separator: " · ")
    }

    private var unavailable: String {
        switch language {
        case .zhCN: return "暂无"
        case .zhHK, .zhTW: return "暫無"
        case .enUS: return "Not available"
        case .jaJP: return "情報なし"
        case .koKR: return "정보 없음"
        }
    }

    private var localizedReleaseLabel: String {
        let region = releaseSummary?.localizedRegion ?? language.releaseRegion
        switch language {
        case .zhCN: return "当前语言地区上映（\(region)）"
        case .zhHK, .zhTW: return "目前語言地區上映（\(region)）"
        case .enUS: return "Local release (\(region))"
        case .jaJP: return "選択言語地域の公開日（\(region)）"
        case .koKR: return "선택 언어 지역 개봉일 (\(region))"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("影片资料", systemImage: "info.circle.fill")
                    .font(.headline)
                Spacer()
                if isLoading {
                    ProgressView().controlSize(.small)
                }
            }
            if let globalRawDate,
               CalendarReleaseEventComposer.shouldOffer(
                   dateText: globalRawDate
               ) {
                ReleaseDateFactRow(
                    label: "全球首映",
                    value: globalDate,
                    rawDate: globalRawDate,
                    title: movieTitle,
                    region: "GLOBAL",
                    language: language
                )
            } else {
                FactRow(label: "全球首映", value: globalDate)
            }
            if let localizedRawDate,
               CalendarReleaseEventComposer.shouldOffer(
                   dateText: localizedRawDate
               ) {
                ReleaseDateFactRow(
                    label: localizedReleaseLabel,
                    value: localizedDate,
                    rawDate: localizedRawDate,
                    title: movieTitle,
                    region: releaseSummary?.localizedRegion ?? language.releaseRegion,
                    language: language
                )
            } else {
                FactRow(label: localizedReleaseLabel, value: localizedDate)
            }
            FactRow(label: "影片时长", value: runtimeText)
            FactRow(label: "制片国家/地区", value: countriesText)
            FactRow(
                label: "导演",
                value: directors.isEmpty
                    ? unavailable
                    : directors.map(\.name).joined(separator: " · ")
            )

            HStack(alignment: .firstTextBaseline) {
                Text("IMDb 编号")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let imdbID = financials?.imdbID,
                   !imdbID.isEmpty,
                   let url = URL(string: "https://www.imdb.com/title/\(imdbID)/") {
                    Link(imdbID, destination: url)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                } else {
                    Text(unavailable)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .cineGlass(cornerRadius: 12)
    }

    private func formatDate(_ value: String?) -> String {
        guard let value, value.count >= 10 else { return unavailable }
        let input = DateFormatter()
        input.locale = Locale(identifier: "en_US_POSIX")
        input.dateFormat = "yyyy-MM-dd"
        guard let date = input.date(from: String(value.prefix(10))) else {
            return String(value.prefix(10))
        }
        let output = DateFormatter()
        output.locale = Locale(identifier: language.localeIdentifier)
        output.dateStyle = .medium
        output.timeStyle = .none
        return output.string(from: date)
    }
}

struct FactRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(LocalizedStringKey(label))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.caption)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

struct CalendarReleaseEventButton: View {
    let title: String
    let dateText: String
    let displayText: String?
    let region: String
    let language: AppLanguage

    @State private var isSaving = false
    @State private var alertMessage: String?

    init(
        title: String,
        dateText: String,
        displayText: String? = nil,
        region: String,
        language: AppLanguage
    ) {
        self.title = title
        self.dateText = dateText
        self.displayText = displayText
        self.region = region
        self.language = language
    }

    var body: some View {
        Button {
            addReleaseEvent()
        } label: {
            if isSaving {
                ProgressView()
                    .controlSize(.small)
            } else if let displayText {
                HStack(spacing: 4) {
                    Text(displayText)
                        .underline()
                    Image(systemName: "calendar.badge.plus")
                }
            } else {
                Image(systemName: "calendar.badge.plus")
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.blue)
        .disabled(isSaving)
        .help(calendarHelp)
        .alert(
            "日历提醒",
            isPresented: Binding(
                get: { alertMessage != nil },
                set: { isPresented in
                    if !isPresented { alertMessage = nil }
                }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private var calendarHelp: String {
        switch language {
        case .zhCN: return "加入 macOS 日历并提前一天提醒"
        case .zhHK, .zhTW: return "加入 macOS 行事曆並提前一天提醒"
        case .enUS: return "Add to macOS Calendar with a one-day reminder"
        case .jaJP: return "macOSカレンダーに追加して1日前に通知"
        case .koKR: return "macOS 캘린더에 추가하고 하루 전에 알림"
        }
    }

    @MainActor
    private func addReleaseEvent() {
        guard let details = CalendarReleaseEventComposer.make(
            title: title,
            dateText: dateText,
            region: region,
            language: language
        ) else {
            alertMessage = CalendarReleaseEventError.invalidDate.localizedDescription
            return
        }

        isSaving = true
        Task { @MainActor in
            defer { isSaving = false }
            do {
                try await CalendarReleaseEventService.shared.add(details)
                alertMessage = successMessage
            } catch {
                alertMessage = error.localizedDescription
            }
        }
    }

    private var successMessage: String {
        switch language {
        case .zhCN: return "已添加到 macOS 日历，并设置提前一天提醒。"
        case .zhHK, .zhTW: return "已加入 macOS 行事曆，並設定提前一天提醒。"
        case .enUS: return "Added to macOS Calendar with a one-day reminder."
        case .jaJP: return "macOSカレンダーに追加し、1日前の通知を設定しました。"
        case .koKR: return "macOS 캘린더에 추가하고 하루 전 알림을 설정했습니다."
        }
    }
}

struct ReleaseDateFactRow: View {
    let label: String
    let value: String
    let rawDate: String
    let title: String
    let region: String
    let language: AppLanguage

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(LocalizedStringKey(label))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            CalendarReleaseEventButton(
                title: title,
                dateText: rawDate,
                displayText: value,
                region: region,
                language: language
            )
            .font(.caption)
        }
    }
}

struct MovieStillsView: View {
    @ObservedObject var store: MovieStore
    let movie: Movie
    @State private var selectedStill: MovieStill?
    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    store.showMovieStills = false
                } label: {
                    Label("返回影片", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)

                Spacer()
                Text("影片剧照").font(.headline)
                Spacer()
                Button {
                    store.loadStills(movieID: movie.id)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("刷新影片剧照")
                .disabled(store.isLoadingStills)
            }
            .padding()

            Divider()

            if store.isLoadingStills && store.movieStills.isEmpty {
                Spacer()
                ProgressView("正在获取影片剧照…")
                    .controlSize(.small)
                Spacer()
            } else if store.movieStills.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("暂无影片剧照")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(store.movieStills) { still in
                            Button {
                                selectedStill = still
                            } label: {
                                AsyncImage(url: still.imageURL) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image.resizable().scaledToFill()
                                    case .failure:
                                        ZStack {
                                            Color.secondary.opacity(0.10)
                                            Image(systemName: "photo")
                                                .foregroundStyle(.secondary)
                                        }
                                    default:
                                        ZStack {
                                            Color.secondary.opacity(0.08)
                                            ProgressView().controlSize(.small)
                                        }
                                    }
                                }
                                .frame(height: 128)
                                .clipShape(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("查看影片剧照大图")
                        }
                    }
                    .padding()
                }
            }
        }
        .overlay {
            if let selectedStill {
                PhotoLightboxOverlay(
                    photo: selectedStill,
                    photos: store.movieStills,
                    imageURL: { $0.fullSizeURL },
                    onClose: { self.selectedStill = nil }
                )
            }
        }
    }
}

struct YouTubePlayerView: NSViewRepresentable {
    let videoKey: String
    private let clientOrigin = "https://cinebar.app"

    final class PlayerContainerView: NSView {
        let webView: WKWebView

        init(configuration: WKWebViewConfiguration) {
            webView = WKWebView(frame: .zero, configuration: configuration)
            super.init(frame: .zero)
            webView.translatesAutoresizingMaskIntoConstraints = true
            webView.autoresizingMask = [.width, .height]
            webView.frame = bounds
            addSubview(webView)
        }

        required init?(coder: NSCoder) {
            nil
        }

        override func layout() {
            super.layout()
            if webView.superview === self {
                webView.frame = bounds
            }
        }
    }

    final class Coordinator {
        var loadedVideoKey: String?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> PlayerContainerView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.isElementFullscreenEnabled = true
        let container = PlayerContainerView(configuration: configuration)
        let webView = container.webView
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = false
        load(videoKey: videoKey, in: webView)
        context.coordinator.loadedVideoKey = videoKey
        return container
    }

    func updateNSView(_ container: PlayerContainerView, context: Context) {
        guard context.coordinator.loadedVideoKey != videoKey else { return }
        load(videoKey: videoKey, in: container.webView)
        context.coordinator.loadedVideoKey = videoKey
    }

    private func load(videoKey: String, in webView: WKWebView) {
        let encodedOrigin = clientOrigin.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ) ?? clientOrigin
        let source = [
            "https://www.youtube.com/embed/\(videoKey)",
            "?playsinline=1",
            "&autoplay=1",
            "&rel=0",
            "&enablejsapi=1",
            "&origin=\(encodedOrigin)",
            "&widget_referrer=\(encodedOrigin)"
        ].joined()
        let html = """
        <!doctype html>
        <html>
        <head>
          <meta name="referrer" content="strict-origin-when-cross-origin">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            html,body,iframe { width:100%; height:100%; margin:0; border:0; background:#000; }
          </style>
        </head>
        <body>
          <iframe
            src="\(source)"
            title="CineBar Trailer"
            referrerpolicy="strict-origin-when-cross-origin"
            allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
            allowfullscreen>
          </iframe>
        </body>
        </html>
        """
        webView.loadHTMLString(
            html,
            baseURL: URL(string: "\(clientOrigin)/")
        )
    }
}

struct MainlandTrailerFallbackView: View {
    let title: String
    let language: AppLanguage
    @Environment(\.openURL) private var openURL

    private var heading: String {
        switch language {
        case .zhCN: return "YouTube 无法播放？"
        case .zhHK, .zhTW: return "YouTube 無法播放？"
        case .enUS: return "Can't play YouTube?"
        case .jaJP: return "YouTubeを再生できませんか？"
        case .koKR: return "YouTube를 재생할 수 없나요?"
        }
    }

    private var detail: String {
        switch language {
        case .zhCN:
            return "可在以下平台搜索官方预告。CineBar 不抓取或托管视频，实际结果以平台为准。"
        case .zhHK, .zhTW:
            return "可在以下平台搜尋官方預告。CineBar 不抓取或託管影片，實際結果以平台為準。"
        case .enUS:
            return "Search for an official trailer on these platforms. CineBar does not scrape or host videos."
        case .jaJP:
            return "以下のプラットフォームで公式予告を検索できます。CineBarは動画を取得・ホストしません。"
        case .koKR:
            return "다음 플랫폼에서 공식 예고편을 검색할 수 있습니다. CineBar는 동영상을 수집하거나 호스팅하지 않습니다."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(heading)
                .font(.caption.bold())
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
            FlowLayout(spacing: 6) {
                ForEach(MainlandTrailerPlatform.allCases) { platform in
                    if let url = platform.url(for: title) {
                        Button {
                            openURL(url)
                        } label: {
                            Label(
                                platform.title(language: language),
                                systemImage: "arrow.up.right.square"
                            )
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.blue.opacity(0.12), in: Capsule())
                    }
                }
            }
        }
        .padding(10)
        .background(
            Color.secondary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }
}

/// 简体中文环境的预告片：豆瓣预告卡片式，点击卡片后用原生播放器播放。
struct DoubanTrailerSection: View {
    @ObservedObject var store: MovieStore
    let title: String
    @State private var playingURL: URL?
    @State private var playingTitle = ""
    @State private var playErrorMessage: String?

    private var trailerList: [DoubanTrailerItem] {
        store.doubanTrailers
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let playingURL {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(playingTitle)
                            .font(.caption.bold())
                            .lineLimit(1)
                        Spacer()
                        Button {
                            stop()
                        } label: {
                            Label("停止", systemImage: "stop.fill")
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }
                    DoubanTrailerPlayerView(url: playingURL)
                        .frame(height: 245)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding(8)
                .background(
                    Color.black.opacity(0.92),
                    in: RoundedRectangle(cornerRadius: 12)
                )
            } else if let playErrorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(playErrorMessage)
                        .font(.caption)
                    Spacer()
                    Button("重试") {
                        self.playErrorMessage = nil
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
                .padding(8)
                .background(
                    Color.orange.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 9)
                )
            }

            if store.isLoadingDoubanTrailers {
                ProgressView("正在获取豆瓣预告…")
                    .controlSize(.small)
            } else if trailerList.isEmpty {
                Text("暂无豆瓣预告")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(trailerList) { item in
                            Button {
                                play(item)
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    ZStack(alignment: .center) {
                                        AsyncImage(url: item.thumbnailURL) { phase in
                                            switch phase {
                                            case .success(let image):
                                                image.resizable().scaledToFill()
                                            case .failure:
                                                Color.secondary.opacity(0.12)
                                            default:
                                                ProgressView()
                                            }
                                        }
                                        .frame(width: 220, height: 124)
                                        .background(Color.secondary.opacity(0.08))
                                        .clipShape(
                                            RoundedRectangle(cornerRadius: 9)
                                        )
                                        Image(systemName: "play.circle.fill")
                                            .font(.system(size: 30))
                                            .foregroundStyle(.white, .black.opacity(0.35))
                                    }
                                    HStack(spacing: 5) {
                                        Text(item.title)
                                            .font(.caption.bold())
                                            .lineLimit(1)
                                        if !item.durationText.isEmpty {
                                            Text(item.durationText)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .help("播放豆瓣预告")
                        }
                    }
                    .padding(.vertical, 2)
                }
                Text("预告片来自豆瓣，实际可用性以豆瓣页面为准。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .onDisappear { stop() }
    }

    private func play(_ item: DoubanTrailerItem) {
        playErrorMessage = nil
        guard let url = item.playbackURL else {
            playErrorMessage = "该预告未能获取到可用源，可能已失效，请换一条重试"
            return
        }
        playingURL = url
        playingTitle = item.title
        NotificationCenter.default.post(
            name: .cineBarMediaPlaybackDidChange,
            object: true
        )
    }

    private func stop() {
        playingURL = nil
        playingTitle = ""
        NotificationCenter.default.post(
            name: .cineBarMediaPlaybackDidChange,
            object: false
        )
    }
}

enum TrailerPlaybackMode: Equatable {
    case floating
    case fullScreen
}

final class TrailerPlayerWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        TrailerPlaybackController.shared.closeAndRestoreMainPanel()
    }
}

struct TrailerPlayerWindowView: View {
    let videoKey: String
    let title: String
    let mode: TrailerPlaybackMode

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            YouTubePlayerView(videoKey: videoKey)

            if mode == .fullScreen {
                HStack(spacing: 10) {
                    Text(title)
                        .font(.callout.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        TrailerPlaybackController.shared.show(
                            videoKey: videoKey,
                            title: title,
                            mode: .floating
                        )
                    } label: {
                        Label("切换浮窗", systemImage: "pip.exit")
                    }
                    Button {
                        TrailerPlaybackController.shared
                            .closeAndRestoreMainPanel()
                    } label: {
                        Label("关闭播放", systemImage: "xmark.circle.fill")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(10)
                .background(
                    LinearGradient(
                        colors: [.black.opacity(0.78), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
    }
}

@MainActor
final class TrailerPlaybackController: NSObject, NSWindowDelegate {
    static let shared = TrailerPlaybackController()

    private var playerWindow: NSWindow?
    private var currentMode: TrailerPlaybackMode?
    private var previousPresentationOptions: NSApplication.PresentationOptions?
    private var isSwitchingOrClosing = false

    func show(
        videoKey: String,
        title: String,
        mode: TrailerPlaybackMode
    ) {
        close()
        NotificationCenter.default.post(
            name: .cineBarMediaPlaybackDidChange,
            object: true
        )
        NotificationCenter.default.post(
            name: .cineBarPanelWillHide,
            object: nil
        )
        NSApplication.shared.windows
            .first { $0 is CineBarPanel }?
            .orderOut(nil)

        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first {
            NSMouseInRect(pointer, $0.frame, false)
        } ?? NSScreen.main
        guard let screen else { return }

        let window: TrailerPlayerWindow
        switch mode {
        case .floating:
            let width = min(920, screen.visibleFrame.width * 0.78)
            let height = width * 9 / 16
            let frame = NSRect(
                x: screen.visibleFrame.midX - width / 2,
                y: screen.visibleFrame.midY - height / 2,
                width: width,
                height: height
            )
            window = TrailerPlayerWindow(
                contentRect: frame,
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.minSize = NSSize(width: 520, height: 292)
            window.level = .floating
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
        case .fullScreen:
            window = TrailerPlayerWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            previousPresentationOptions = NSApplication.shared.presentationOptions
            NSApplication.shared.presentationOptions = [
                .autoHideDock,
                .autoHideMenuBar
            ]
            window.level = .mainMenu
            window.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary
            ]
        }

        window.backgroundColor = .black
        window.isOpaque = true
        window.delegate = self
        window.contentView = NSHostingView(
            rootView: TrailerPlayerWindowView(
                videoKey: videoKey,
                title: title,
                mode: mode
            )
        )
        playerWindow = window
        currentMode = mode
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func close() {
        guard let window = playerWindow else { return }
        isSwitchingOrClosing = true
        playerWindow = nil
        currentMode = nil
        window.delegate = nil
        window.orderOut(nil)
        window.close()
        restorePresentationOptions()
        NotificationCenter.default.post(
            name: .cineBarMediaPlaybackDidChange,
            object: false
        )
        isSwitchingOrClosing = false
    }

    func closeAndRestoreMainPanel() {
        close()
        NotificationCenter.default.post(
            name: .cineBarShowMainPanel,
            object: nil
        )
    }

    func windowWillClose(_ notification: Notification) {
        guard !isSwitchingOrClosing else { return }
        playerWindow = nil
        currentMode = nil
        restorePresentationOptions()
        NotificationCenter.default.post(
            name: .cineBarMediaPlaybackDidChange,
            object: false
        )
        NotificationCenter.default.post(
            name: .cineBarShowMainPanel,
            object: nil
        )
    }

    private func restorePresentationOptions() {
        if let previousPresentationOptions {
            NSApplication.shared.presentationOptions = previousPresentationOptions
            self.previousPresentationOptions = nil
        }
    }
}

@MainActor
private enum SystemSharePresenter {
    private static var activePicker: NSSharingServicePicker?

    static func present(_ payload: SharePayload) {
        guard let anchor = NSApp.keyWindow?.contentView ??
                NSApp.mainWindow?.contentView
        else { return }
        let picker = NSSharingServicePicker(items: payload.systemItems)
        activePicker = picker
        picker.show(
            relativeTo: anchor.bounds,
            of: anchor,
            preferredEdge: .maxY
        )
    }
}

struct MediaShareButton: View {
    let payload: SharePayload?

    var body: some View {
        Button {
            if let payload {
                SystemSharePresenter.present(payload)
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .buttonStyle(.plain)
        .disabled(payload == nil)
        .help(payload == nil ? "分享服务暂不可用" : "分享")
        .accessibilityLabel("分享")
    }
}

struct MovieDetailView: View {
    @ObservedObject var store: MovieStore
    let movie: Movie
    var onPlayLocalFile: (() -> Void)? = nil
    @Environment(\.openURL) private var openURL
    @State private var inlineTrailerKey: String?
    @State private var inlineTrailerTitle = ""
    @State private var selectedMovieStill: MovieStill?

    private var detailReleaseDate: String? {
        store.releaseSummary?.localizedRelease ??
            store.financials?.releaseDate ??
            movie.localizedReleaseDate ??
            movie.releaseDate
    }

    private var sharePayload: SharePayload? {
        guard let url = store.brandedShareURL(for: movie) else {
            return nil
        }
        return SharePayload(
            mediaType: .movie,
            title: movie.title,
            url: url
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    stopInlineTrailer()
                    store.selectedMovie = nil
                } label: {
                    Label("返回", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)

                Spacer()
                Text("影片详情").font(.headline)
                Spacer()
                Button {
                    stopInlineTrailer()
                    TrailerPlaybackController.shared.close()
                    store.select(movie)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("重新加载影片详情")

                if let onPlayLocalFile {
                    Button {
                        stopInlineTrailer()
                        onPlayLocalFile()
                    } label: {
                        Label("本地播放", systemImage: "play.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .help("播放本地片库中的该影片文件")
                }

                MediaShareButton(payload: sharePayload)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        PosterView(movie: movie, width: 118, height: 172)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(movie.title)
                                    .font(.title2.bold())
                                    .textSelection(.enabled)
                                Button {
                                    store.toggleWatchlist(movie)
                                } label: {
                                    Image(
                                        systemName: store.isInWatchlist(movie)
                                            ? "heart.fill"
                                            : "heart"
                                    )
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.pink)
                                .help("添加到我的片单")
                            }
                            if let originalTitle = movie.originalTitle,
                               originalTitle != movie.title {
                                Text(originalTitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            Label(String(format: "%.1f", movie.voteAverage), systemImage: "star.fill")
                                .font(.title3.bold())
                                .foregroundStyle(.orange)
                            Text("TMDB评分 · \(movie.voteCount)人评价")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(movie.year)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ContentRatingBadge(rating: store.movieContentRating)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("多重评分").font(.headline)
                        FlowLayout(spacing: 8) {
                            ForEach(store.ratings(for: movie)) { rating in
                                RatingBadge(rating: rating)
                            }
                        }
                        if store.isLoadingRatings ||
                            store.isLoadingCommunityRating {
                            ProgressView("正在获取评分…")
                                .controlSize(.small)
                        } else if !store.hasOMDbKey, movie.id > 0 {
                            Text("在设置中填写 OMDb Key，可补充 IMDb、烂番茄影评人分和 Metacritic。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    CommunityRatingPanel(
                        store: store,
                        mediaType: .movie,
                        mediaID: movie.id
                    )

                    Hao6vMagnetButton(title: movie.title, year: movie.year)

                    BoxOfficeView(
                        financials: store.financials,
                        isLoading: store.isLoadingFinancials,
                        language: store.appLanguage
                    )

                    MovieFactsView(
                        financials: store.financials,
                        releaseSummary: store.releaseSummary,
                        directors: store.directors,
                        isLoading: store.isLoadingFinancials ||
                            store.isLoadingReleaseDates,
                        language: store.appLanguage,
                        movieTitle: movie.title
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text("简介").font(.headline)
                        Text(movie.overview.isEmpty ? "暂无中文简介" : movie.overview)
                            .font(.callout)
                            .textSelection(.enabled)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("影片剧照", systemImage: "photo.on.rectangle.angled")
                            Spacer()
                            Button {
                                store.loadStills(movieID: movie.id)
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.plain)
                            .disabled(store.isLoadingStills)
                        }
                        .font(.headline)
                        if store.isLoadingStills && store.movieStills.isEmpty {
                            ProgressView("正在获取影片剧照…")
                                .controlSize(.small)
                        } else if store.movieStills.isEmpty {
                            Text("暂无影片剧照")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 10) {
                                    ForEach(store.movieStills.prefix(16)) { still in
                                        Button {
                                            selectedMovieStill = still
                                        } label: {
                                            AsyncImage(url: still.imageURL) { phase in
                                                switch phase {
                                                case .success(let image):
                                                    image.resizable().scaledToFill()
                                                case .failure:
                                                    Color.secondary.opacity(0.12)
                                                default:
                                                    ProgressView()
                                                }
                                            }
                                            .frame(width: 250, height: 141)
                                            .background(Color.secondary.opacity(0.08))
                                            .clipShape(
                                                RoundedRectangle(cornerRadius: 9)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("查看影片剧照大图")
                                    }
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("影片预告").font(.headline)
                        if store.appLanguage == .zhCN {
                            DoubanTrailerSection(
                                store: store,
                                title: movie.title
                            )
                        } else {
                            if let inlineTrailerKey {
                                VStack(alignment: .leading, spacing: 7) {
                                    HStack {
                                        Text(inlineTrailerTitle)
                                            .font(.caption.bold())
                                            .lineLimit(1)
                                        Spacer()
                                        Button {
                                            stopInlineTrailer()
                                        } label: {
                                            Label("停止", systemImage: "stop.fill")
                                        }
                                        .buttonStyle(.borderless)
                                        .controlSize(.small)
                                    }
                                    YouTubePlayerView(videoKey: inlineTrailerKey)
                                        .frame(height: 245)
                                        .clipShape(
                                            RoundedRectangle(
                                                cornerRadius: 10,
                                                style: .continuous
                                            )
                                        )
                                }
                                .padding(8)
                                .background(
                                    Color.black.opacity(0.92),
                                    in: RoundedRectangle(cornerRadius: 12)
                                )
                            }
                            if store.isLoadingTrailers {
                                ProgressView("正在获取影片预告…")
                                    .controlSize(.small)
                            } else if store.trailers.isEmpty {
                                Text("暂无官方预告")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(store.trailers.prefix(3)) { trailer in
                                    if trailer.watchURL != nil {
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack(spacing: 8) {
                                                Image(systemName: "play.rectangle.fill")
                                                    .foregroundStyle(.red)
                                                Text(
                                                    trailer.displayName(
                                                        language: store.appLanguage
                                                    )
                                                )
                                                    .lineLimit(1)
                                                Spacer()
                                                if trailer.official {
                                                    Text("官方")
                                                        .font(.caption2.bold())
                                                        .foregroundStyle(.secondary)
                                                }
                                            }

                                            HStack {
                                                Spacer()
                                                Button(
                                                    inlineTrailerKey == trailer.key
                                                        ? "停止小屏"
                                                        : "小屏播放"
                                                ) {
                                                    if inlineTrailerKey == trailer.key {
                                                        stopInlineTrailer()
                                                    } else {
                                                        TrailerPlaybackController.shared.close()
                                                        inlineTrailerKey = trailer.key
                                                        inlineTrailerTitle = trailer.displayName(
                                                            language: store.appLanguage
                                                        )
                                                        NotificationCenter.default.post(
                                                            name: .cineBarMediaPlaybackDidChange,
                                                            object: true
                                                        )
                                                    }
                                                }
                                                .buttonStyle(.bordered)
                                                .controlSize(.small)
                                                Button("浮窗播放") {
                                                    stopInlineTrailer()
                                                    TrailerPlaybackController.shared.show(
                                                        videoKey: trailer.key,
                                                        title: trailer.displayName(
                                                            language: store.appLanguage
                                                        ),
                                                        mode: .floating
                                                    )
                                                }
                                                .buttonStyle(.bordered)
                                                .controlSize(.small)
                                                Button("全屏播放") {
                                                    stopInlineTrailer()
                                                    TrailerPlaybackController.shared.show(
                                                        videoKey: trailer.key,
                                                        title: trailer.displayName(
                                                            language: store.appLanguage
                                                        ),
                                                        mode: .fullScreen
                                                    )
                                                }
                                                .buttonStyle(.borderedProminent)
                                                .controlSize(.small)
                                            }
                                        }
                                        .font(.callout)
                                        .padding(10)
                                        .background(
                                            Color.secondary.opacity(0.08),
                                            in: RoundedRectangle(cornerRadius: 9)
                                        )
                                    }
                                }
                            }
                            MainlandTrailerFallbackView(
                                title: movie.title,
                                language: store.appLanguage
                            )
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("演员阵容").font(.headline)
                        if store.isLoadingCast {
                            ProgressView("正在获取演员阵容…")
                                .controlSize(.small)
                        } else if store.cast.isEmpty {
                            Text("暂无演员资料")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(alignment: .top, spacing: 10) {
                                    ForEach(store.cast.prefix(18)) { member in
                                        Button {
                                            store.selectPerson(member)
                                        } label: {
                                            CastMemberCard(member: member)
                                        }
                                        .buttonStyle(.plain)
                                        .help("查看演员详情")
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("正版观看").font(.headline)
                            Text(store.region)
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.secondary.opacity(0.12), in: Capsule())
                        }

                        if movie.id < 0 {
                            Text("演示影片不查询观看平台")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if store.isLoadingProviders {
                            ProgressView("正在查询…")
                                .controlSize(.small)
                        } else if store.providers.isEmpty {
                            Text("当前地区暂未收录正版观看平台")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            FlowLayout(spacing: 6) {
                                ForEach(store.providers) { provider in
                                    if let destination = providerSearchURL(
                                        providerName: provider.providerName,
                                        title: movie.title
                                    ) {
                                        Button {
                                            openURL(destination)
                                        } label: {
                                            Label(
                                                provider.providerName,
                                                systemImage: "arrow.up.right.square"
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .font(.caption)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 5)
                                        .background(.blue.opacity(0.12), in: Capsule())
                                        .help("在该平台搜索影片")
                                    } else {
                                        Text(provider.providerName)
                                            .font(.caption)
                                            .padding(.horizontal, 9)
                                            .padding(.vertical, 5)
                                            .background(.blue.opacity(0.12), in: Capsule())
                                    }
                                }
                            }
                        }

                        if let link = store.providerLink {
                            Button("查看正版观看入口") {
                                openURL(link)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }

                        Text("观看平台信息由 JustWatch 通过 TMDB 提供，实际可用性以平台页面为准。")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding()
            }
        }
        .onDisappear {
            stopInlineTrailer()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .cineBarPanelWillHide)
        ) { _ in
            stopInlineTrailer()
        }
        .overlay {
            if let selectedMovieStill {
                PhotoLightboxOverlay(
                    photo: selectedMovieStill,
                    photos: Array(store.movieStills.prefix(16)),
                    imageURL: { $0.fullSizeURL },
                    onClose: { self.selectedMovieStill = nil }
                )
            }
        }
    }

    private func stopInlineTrailer() {
        guard inlineTrailerKey != nil else { return }
        inlineTrailerKey = nil
        inlineTrailerTitle = ""
        NotificationCenter.default.post(
            name: .cineBarMediaPlaybackDidChange,
            object: false
        )
    }
}

struct TVPosterView: View {
    let show: TVShow
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Group {
            if let url = show.posterURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholder
                    default:
                        ZStack {
                            Color.secondary.opacity(0.08)
                            ProgressView().controlSize(.small)
                        }
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [.indigo.opacity(0.18), .orange.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "tv.fill")
                .font(.title)
                .foregroundStyle(.secondary)
        }
    }
}

struct TVShowRow: View {
    @ObservedObject var store: MovieStore
    let show: TVShow
    var airingLabel: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            TVPosterView(show: show, width: 58, height: 84)
            VStack(alignment: .leading, spacing: 5) {
                if let airingLabel {
                    Label(airingLabel, systemImage: "calendar")
                        .font(.caption2.bold())
                        .foregroundStyle(.indigo)
                }
                Text(show.name)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 10) {
                    if let rating = store.listRating(for: show) {
                        Text(rating.compactValue)
                            .foregroundStyle(.primary)
                            .help(rating.source)
                    }
                    Text(show.year)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                Text(show.overview.isEmpty ? "暂无简介" : show.overview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 9)
        .onAppear {
            store.ensureListRating(for: show)
        }
    }
}

struct PersonSearchRow: View {
    let person: PersonSearchResult

    var body: some View {
        HStack(spacing: 10) {
            AsyncImage(url: person.profileURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    ZStack {
                        Color.secondary.opacity(0.10)
                        Image(systemName: "person.crop.circle")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 48, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 3) {
                Text(person.name)
                    .font(.callout.bold())
                if let department = person.knownForDepartment,
                   !department.isEmpty {
                    Text(department)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 5)
    }
}

struct EpisodeReminderMenu: View {
    @ObservedObject var store: MovieStore
    let show: TVShow
    let episode: TVEpisodeSummary

    var selectedOption: EpisodeReminderOption? {
        store.episodeReminderOption(
            showID: show.id,
            episodeCode: episode.code
        )
    }

    private var availableOptions: [EpisodeReminderOption] {
        guard let airDate = episode.airDate else { return [] }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: airDate) else { return [] }
        return EpisodeReminderOption.allCases.filter { option in
            guard let targetDay = Calendar.current.date(
                byAdding: .day,
                value: option.dayOffset,
                to: date
            ) else { return false }
            var components = Calendar.current.dateComponents(
                [.year, .month, .day],
                from: targetDay
            )
            components.hour = option.hour
            return Calendar.current.date(from: components)
                .map { $0 > Date() } ?? false
        }
    }

    var body: some View {
        Menu {
            if availableOptions.isEmpty && selectedOption == nil {
                Text("已无可用提醒时间")
            }
            ForEach(availableOptions) { option in
                Button {
                    store.toggleEpisodeReminder(
                        show: show,
                        episode: episode,
                        option: option
                    )
                } label: {
                    if selectedOption == option {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
            if selectedOption != nil {
                Divider()
                Button("取消提醒", role: .destructive) {
                    if let selectedOption {
                        store.toggleEpisodeReminder(
                            show: show,
                            episode: episode,
                            option: selectedOption
                        )
                    }
                }
            }
        } label: {
            Label(
                selectedOption == nil ? "提醒" : "已提醒",
                systemImage: selectedOption == nil ? "bell" : "bell.fill"
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("选择提醒日期和时间")
    }
}

struct TVDetailView: View {
    @ObservedObject var store: MovieStore
    let show: TVShow
    var onPlayLocalFile: (() -> Void)? = nil
    @Environment(\.openURL) private var openURL
    @State private var inlineTrailerKey: String?
    @State private var inlineTrailerTitle = ""

    private var sharePayload: SharePayload? {
        guard let url = store.brandedShareURL(for: show) else {
            return nil
        }
        return SharePayload(
            mediaType: .tv,
            title: show.name,
            url: url
        )
    }

    private var runtimeText: String {
        guard let minutes = store.tvDetails?.episodeRunTime.first,
              minutes > 0 else { return "暂无" }
        return "约 \(minutes) 分钟/集"
    }

    private var countriesText: String {
        let names = store.tvDetails?.productionCountries.map {
            $0.name.isEmpty ? $0.isoCode : $0.name
        } ?? []
        return names.isEmpty ? "暂无" : names.joined(separator: " · ")
    }

    private var todayText: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private var upcomingSeason: TVSeason? {
        store.tvDetails?.seasons
            .filter {
                $0.seasonNumber > 0 &&
                    ($0.airDate ?? "") >= todayText
            }
            .sorted {
                ($0.airDate ?? "") < ($1.airDate ?? "")
            }
            .first
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    stopInlineTrailer()
                    store.selectedTVShow = nil
                } label: {
                    Label("返回", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                Spacer()
                Text("电视剧详情").font(.headline)
                Spacer()
                Button {
                    stopInlineTrailer()
                    TrailerPlaybackController.shared.close()
                    store.selectTV(show)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("重新加载电视剧详情")
                if let onPlayLocalFile {
                    Button {
                        stopInlineTrailer()
                        onPlayLocalFile()
                    } label: {
                        Label("本地播放", systemImage: "play.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .help("播放本地片库中的该剧集文件")
                }
                MediaShareButton(payload: sharePayload)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        TVPosterView(show: show, width: 118, height: 172)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(show.name)
                                    .font(.title2.bold())
                                    .textSelection(.enabled)
                                Button {
                                    store.toggleWatchlist(show)
                                } label: {
                                    Image(
                                        systemName: store.isInWatchlist(show)
                                            ? "heart.fill"
                                            : "heart"
                                    )
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.pink)
                                .help("添加到我的片单")
                            }
                            if let originalName = show.originalName,
                               originalName != show.name {
                                Text(originalName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            Label(
                                String(format: "%.1f", show.voteAverage),
                                systemImage: "star.fill"
                            )
                            .font(.title3.bold())
                            .foregroundStyle(.orange)
                            Text("TMDB评分 · \(show.voteCount)人评价")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(show.year)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ContentRatingBadge(rating: store.tvContentRating)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("多重评分").font(.headline)
                        FlowLayout(spacing: 8) {
                            ForEach(store.ratings(for: show)) { rating in
                                RatingBadge(rating: rating)
                            }
                        }
                    }

                    CommunityRatingPanel(
                        store: store,
                        mediaType: .tv,
                        mediaID: show.id
                    )

                    Hao6vMagnetButton(title: show.name, year: show.year)

                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Label("电视剧资料", systemImage: "info.circle.fill")
                                .font(.headline)
                            Spacer()
                            if store.isLoadingTVDetails {
                                ProgressView().controlSize(.small)
                            }
                        }
                        FactRow(
                            label: "首播日期",
                            value: store.tvDetails?.firstAirDate ?? show.firstAirDate ?? "暂无"
                        )
                        FactRow(
                            label: "最后播出",
                            value: store.tvDetails?.lastAirDate ?? "暂无"
                        )
                        FactRow(
                            label: "季数 / 集数",
                            value: "\(store.tvDetails?.numberOfSeasons ?? 0) 季 · \(store.tvDetails?.numberOfEpisodes ?? 0) 集"
                        )
                        FactRow(label: "单集时长", value: runtimeText)
                        FactRow(label: "制片国家/地区", value: countriesText)
                        FactRow(
                            label: "播出状态",
                            value: store.tvDetails?.status ?? "暂无"
                        )
                        HStack(alignment: .top) {
                            Text("播出平台")
                                .foregroundStyle(.secondary)
                            Spacer()
                            let networks = store.tvDetails?.networks ?? []
                            if networks.isEmpty {
                                Text("暂无")
                            } else {
                                FlowLayout(spacing: 5) {
                                    ForEach(networks) { network in
                                        if let destination = providerSearchURL(
                                            providerName: network.name,
                                            title: show.name
                                        ) ?? store.tvProviderLink ??
                                            store.tvAiringInfo?.sourceURL {
                                            Button {
                                                openURL(destination)
                                            } label: {
                                                Label(
                                                    network.name,
                                                    systemImage:
                                                        "arrow.up.right.square"
                                                )
                                            }
                                            .buttonStyle(.plain)
                                            .foregroundStyle(.blue)
                                        } else {
                                            Text(network.name)
                                        }
                                    }
                                }
                            }
                        }
                        .font(.callout)
                        if let airing = store.tvAiringInfo {
                            FactRow(
                                label: "下一集播出",
                                value: airing.localDisplayText
                            )
                            FactRow(
                                label: "时间数据来源",
                                value: "TVMaze"
                            )
                        }
                    }
                    .padding(12)
                    .cineGlass(cornerRadius: 12)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("简介").font(.headline)
                        Text(show.overview.isEmpty ? "暂无简介" : show.overview)
                            .font(.callout)
                            .textSelection(.enabled)
                        if store.isLoadingTVDetails && store.tvStills.isEmpty {
                            ProgressView("正在获取电视剧剧照…")
                                .controlSize(.small)
                                .padding(.top, 6)
                        } else if !store.tvStills.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 10) {
                                    ForEach(store.tvStills.prefix(18)) { still in
                                        AsyncImage(url: still.imageURL) { phase in
                                            switch phase {
                                            case .success(let image):
                                                image.resizable().scaledToFill()
                                            case .failure:
                                                ZStack {
                                                    Color.secondary.opacity(0.10)
                                                    Image(systemName: "photo")
                                                }
                                            default:
                                                ProgressView()
                                            }
                                        }
                                        .frame(width: 220, height: 124)
                                        .clipShape(
                                            RoundedRectangle(cornerRadius: 10)
                                        )
                                    }
                                }
                                .padding(.top, 6)
                            }
                        }
                    }

                    if store.tvDetails?.nextEpisodeToAir != nil ||
                        upcomingSeason != nil {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("接下来播出", systemImage: "calendar.badge.clock")
                                .font(.headline)
                            if let episode = store.tvDetails?.nextEpisodeToAir,
                               let airDate = episode.airDate {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("下一集 · \(episode.code)")
                                            .font(.callout.bold())
                                        Text("\(airDate) · \(episode.name)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                            if let season = upcomingSeason,
                               let airDate = season.airDate {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("下一季 · \(season.name)")
                                            .font(.callout.bold())
                                        Text("\(airDate) · \(season.episodeCount) 集")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                        }
                        .padding(12)
                        .cineGlass(cornerRadius: 12)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("预告片").font(.headline)
                        if store.appLanguage == .zhCN {
                            DoubanTrailerSection(
                                store: store,
                                title: show.name
                            )
                        } else {
                            if let inlineTrailerKey {
                                VStack(alignment: .leading, spacing: 7) {
                                    HStack {
                                        Text(inlineTrailerTitle)
                                            .font(.caption.bold())
                                            .lineLimit(1)
                                        Spacer()
                                        Button {
                                            stopInlineTrailer()
                                        } label: {
                                            Label("停止", systemImage: "stop.fill")
                                        }
                                        .buttonStyle(.borderless)
                                        .controlSize(.small)
                                    }
                                    YouTubePlayerView(videoKey: inlineTrailerKey)
                                        .frame(height: 245)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .padding(8)
                                .background(
                                    Color.black.opacity(0.92),
                                    in: RoundedRectangle(cornerRadius: 12)
                                )
                            }
                            if store.isLoadingTVDetails && store.tvTrailers.isEmpty {
                                ProgressView("正在获取预告片…").controlSize(.small)
                            } else if store.tvTrailers.isEmpty {
                                Text("暂无官方预告")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(store.tvTrailers.prefix(3)) { trailer in
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Image(systemName: "play.rectangle.fill")
                                                .foregroundStyle(.red)
                                            Text(trailer.displayName(language: store.appLanguage))
                                                .lineLimit(1)
                                            Spacer()
                                            if trailer.official {
                                                Text("官方")
                                                    .font(.caption2.bold())
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        HStack {
                                            Spacer()
                                            Button(
                                                inlineTrailerKey == trailer.key
                                                    ? "停止小屏"
                                                    : "小屏播放"
                                            ) {
                                                if inlineTrailerKey == trailer.key {
                                                    stopInlineTrailer()
                                                } else {
                                                    TrailerPlaybackController.shared.close()
                                                    inlineTrailerKey = trailer.key
                                                    inlineTrailerTitle = trailer.displayName(
                                                        language: store.appLanguage
                                                    )
                                                    NotificationCenter.default.post(
                                                        name: .cineBarMediaPlaybackDidChange,
                                                        object: true
                                                    )
                                                }
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                            Button("浮窗播放") {
                                                stopInlineTrailer()
                                                TrailerPlaybackController.shared.show(
                                                    videoKey: trailer.key,
                                                    title: trailer.displayName(
                                                        language: store.appLanguage
                                                    ),
                                                    mode: .floating
                                                )
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                            Button("全屏播放") {
                                                stopInlineTrailer()
                                                TrailerPlaybackController.shared.show(
                                                    videoKey: trailer.key,
                                                    title: trailer.displayName(
                                                        language: store.appLanguage
                                                    ),
                                                    mode: .fullScreen
                                                )
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .controlSize(.small)
                                        }
                                    }
                                    .font(.callout)
                                    .padding(10)
                                    .background(
                                        Color.secondary.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: 9)
                                    )
                                }
                            }
                            MainlandTrailerFallbackView(
                                title: show.name,
                                language: store.appLanguage
                            )
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("季与集").font(.headline)
                        let seasons = store.tvDetails?.seasons
                            .filter { $0.seasonNumber > 0 } ?? []
                        if seasons.isEmpty {
                            Text("暂无季数资料")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(seasons) { season in
                                VStack(alignment: .leading, spacing: 8) {
                                    Button {
                                        store.toggleSeasonEpisodes(
                                            showID: show.id,
                                            season: season
                                        )
                                    } label: {
                                        HStack {
                                            VStack(
                                                alignment: .leading,
                                                spacing: 2
                                            ) {
                                                Text(season.name)
                                                    .font(.callout.bold())
                                                if let airDate = season.airDate {
                                                    Text(airDate)
                                                        .font(.caption2)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                            Spacer()
                                            Text("\(season.episodeCount) 集")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Image(
                                                systemName:
                                                    store.expandedSeasonNumber ==
                                                        season.seasonNumber
                                                        ? "chevron.up"
                                                        : "chevron.down"
                                            )
                                            .font(.caption)
                                        }
                                    }
                                    .buttonStyle(.plain)

                                    if store.expandedSeasonNumber ==
                                        season.seasonNumber {
                                        if store.isLoadingSeason &&
                                            store.seasonEpisodes[
                                                season.seasonNumber
                                            ] == nil {
                                            ProgressView("正在获取分集资料…")
                                                .controlSize(.small)
                                        } else {
                                            let episodes = store.seasonEpisodes[
                                                season.seasonNumber
                                            ] ?? []
                                            if episodes.isEmpty {
                                                Text("暂无分集资料")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            } else {
                                                ForEach(episodes) { episode in
                                                    HStack(
                                                        alignment: .top,
                                                        spacing: 9
                                                    ) {
                                                        AsyncImage(
                                                            url: episode.stillURL
                                                        ) { phase in
                                                            switch phase {
                                                            case .success(let image):
                                                                image.resizable()
                                                                    .scaledToFill()
                                                            default:
                                                                Color.secondary
                                                                    .opacity(0.10)
                                                            }
                                                        }
                                                        .frame(
                                                            width: 92,
                                                            height: 52
                                                        )
                                                        .clipShape(
                                                            RoundedRectangle(
                                                                cornerRadius: 6
                                                            )
                                                        )
                                                        VStack(
                                                            alignment: .leading,
                                                            spacing: 3
                                                        ) {
                                                            Text(
                                                                "\(episode.code) · \(episode.name)"
                                                            )
                                                            .font(.caption.bold())
                                                            HStack(spacing: 7) {
                                                                if let airDate =
                                                                    episode.airDate {
                                                                    Text(airDate)
                                                                }
                                                                if episode.voteAverage >
                                                                    0 {
                                                                    Label(
                                                                        String(
                                                                            format: "%.1f",
                                                                            episode.voteAverage
                                                                        ),
                                                                        systemImage: "star.fill"
                                                                    )
                                                                    .foregroundStyle(
                                                                        .orange
                                                                    )
                                                                }
                                                            }
                                                            .font(.caption2)
                                                            .foregroundStyle(
                                                                .secondary
                                                            )
                                                            Text(
                                                                episode.overview
                                                                    .isEmpty
                                                                    ? "暂无本集简介"
                                                                    : episode.overview
                                                            )
                                                            .font(.caption2)
                                                            .foregroundStyle(
                                                                .secondary
                                                            )
                                                            .lineLimit(4)
                                                        }
                                                        Spacer(minLength: 4)
                                                    }
                                                    .padding(.vertical, 5)
                                                    Divider()
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding(10)
                                .background(
                                    Color.secondary.opacity(0.07),
                                    in: RoundedRectangle(cornerRadius: 9)
                                )
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("演员阵容").font(.headline)
                        if store.isLoadingTVDetails && store.tvCast.isEmpty {
                            ProgressView("正在获取演员阵容…").controlSize(.small)
                        } else if store.tvCast.isEmpty {
                            Text("暂无演员资料")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(alignment: .top, spacing: 10) {
                                    ForEach(store.tvCast.prefix(18)) { member in
                                        Button {
                                            store.selectPerson(member)
                                        } label: {
                                            CastMemberCard(member: member)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("正版观看").font(.headline)
                            Text(store.region)
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.secondary.opacity(0.12), in: Capsule())
                        }
                        if store.tvProviders.isEmpty {
                            Text("当前地区暂未收录正版观看平台")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            FlowLayout(spacing: 6) {
                                ForEach(store.tvProviders) { provider in
                                    if let destination = providerSearchURL(
                                        providerName: provider.providerName,
                                        title: show.name
                                    ) ?? store.tvProviderLink {
                                        Button {
                                            openURL(destination)
                                        } label: {
                                            Label(
                                                provider.providerName,
                                                systemImage: "arrow.up.right.square"
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .font(.caption)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 5)
                                        .background(.blue.opacity(0.12), in: Capsule())
                                        .help("在该平台搜索电视剧")
                                    }
                                }
                            }
                        }
                        if let link = store.tvProviderLink {
                            Button("查看正版观看入口") { openURL(link) }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                        }
                        Text(
                            "观看平台信息由 JustWatch 通过 TMDB 提供；播出时间由 TVMaze 提供，实际可用性与临时调档以平台官方页面为准。"
                        )
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    }
                }
                .padding()
            }
        }
        .onDisappear { stopInlineTrailer() }
        .onReceive(
            NotificationCenter.default.publisher(for: .cineBarPanelWillHide)
        ) { _ in
            stopInlineTrailer()
        }
    }

    private func stopInlineTrailer() {
        guard inlineTrailerKey != nil else { return }
        inlineTrailerKey = nil
        inlineTrailerTitle = ""
        NotificationCenter.default.post(
            name: .cineBarMediaPlaybackDidChange,
            object: false
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

struct PersonDetailView: View {
    @ObservedObject var store: MovieStore
    let person: CastMember
    @Environment(\.openURL) private var openURL
    @State private var selectedPersonPhoto: PersonImage?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    store.selectedPerson = nil
                } label: {
                    Label("返回详情", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)

                Spacer()
                Text("演员详情").font(.headline)
                Spacer()
                Color.clear.frame(width: 70, height: 1)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        Group {
                            if let url = store.personDetails?.profileURL ?? person.profileURL {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image.resizable().scaledToFill()
                                    case .failure:
                                        actorPlaceholder
                                    default:
                                        ProgressView()
                                    }
                                }
                            } else {
                                actorPlaceholder
                            }
                        }
                        .frame(width: 126, height: 166)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        VStack(alignment: .leading, spacing: 8) {
                            Text(store.personDetails?.name ?? person.name)
                                .font(.title2.bold())
                                .textSelection(.enabled)
                            if let birthday = store.personDetails?.birthday,
                               !birthday.isEmpty {
                                Label(
                                    ageText.map { "\(birthday)（\($0)）" } ??
                                        birthday,
                                    systemImage: "calendar"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            if let deathday = store.personDetails?.deathday,
                               !deathday.isEmpty {
                                Label(
                                    deathAgeText.map {
                                        "\(deathday)（享年 \($0) 岁）"
                                    } ?? deathday,
                                    systemImage: "leaf.fill"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            if let place = store.personDetails?.placeOfBirth,
                               !place.isEmpty {
                                Button {
                                    if let url = mapURL(place) {
                                        openURL(url)
                                    }
                                } label: {
                                    Label(
                                        place,
                                        systemImage: "mappin.and.ellipse"
                                    )
                                }
                                .buttonStyle(.plain)
                                .font(.caption)
                                .foregroundStyle(.blue)
                                .help("在地图中查看出生地")
                            }
                            if let aliases = store.personDetails?.alsoKnownAs,
                               !aliases.isEmpty {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("又名")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.secondary)
                                    Text(aliases.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                            HStack(spacing: 8) {
                                if let xURL = store.personExternalIDs?.xURL {
                                    Link(destination: xURL) {
                                        Label("X", systemImage: "link")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                                if let instagramURL = store.personExternalIDs?.instagramURL {
                                    Link(destination: instagramURL) {
                                        Label("Instagram", systemImage: "camera")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("演员照片").font(.headline)
                        if store.isLoadingPerson && store.personImages.isEmpty {
                            ProgressView("正在获取演员照片…")
                                .controlSize(.small)
                        } else if store.personImages.isEmpty {
                            Text("暂无演员照片")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 10) {
                                    ForEach(store.personImages.prefix(18)) { photo in
                                        Button {
                                            selectedPersonPhoto = photo
                                        } label: {
                                            AsyncImage(url: photo.imageURL) { phase in
                                                switch phase {
                                                case .success(let image):
                                                    image.resizable().scaledToFill()
                                                case .failure:
                                                    actorPlaceholder
                                                default:
                                                    ProgressView()
                                                }
                                            }
                                            .frame(width: 126, height: 178)
                                            .background(Color.secondary.opacity(0.08))
                                            .clipShape(
                                                RoundedRectangle(cornerRadius: 10)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("查看演员照片大图")
                                    }
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Text("人物简介").font(.headline)
                        if store.isLoadingPerson && store.personDetails == nil {
                            ProgressView("正在获取演员资料…")
                                .controlSize(.small)
                        } else {
                            Text(
                                store.personDetails?.biography.isEmpty == false
                                    ? store.personDetails?.biography ?? ""
                                    : "暂无人物简介"
                            )
                            .font(.callout)
                            .foregroundStyle(
                                store.personDetails?.biography.isEmpty == false
                                    ? .primary
                                    : .secondary
                            )
                            .textSelection(.enabled)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("参演电影").font(.headline)
                        if store.isLoadingPerson && store.personMovies.isEmpty {
                            ProgressView("正在获取参演电影…")
                                .controlSize(.small)
                        } else if store.personMovies.isEmpty {
                            Text("暂无参演电影资料")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(store.personMovies.prefix(40)) { movie in
                                HStack(spacing: 5) {
                                    Button {
                                        store.select(movie)
                                    } label: {
                                        MovieRow(store: store, movie: movie)
                                    }
                                    .buttonStyle(.plain)
                                    Button {
                                        store.toggleWatchlist(movie)
                                    } label: {
                                        Image(
                                            systemName:
                                                store.isInWatchlist(movie)
                                                ? "heart.fill"
                                                : "heart"
                                        )
                                        .foregroundStyle(.pink)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("参演电视剧").font(.headline)
                        if store.isLoadingPerson &&
                            store.personTelevision.isEmpty {
                            ProgressView("正在获取参演电视剧…")
                                .controlSize(.small)
                        } else if store.personTelevision.isEmpty {
                            Text("暂无参演电视剧资料")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(store.personTelevision.prefix(40)) { show in
                                HStack(spacing: 5) {
                                    Button {
                                        store.selectTV(show)
                                    } label: {
                                        TVShowRow(store: store, show: show)
                                    }
                                    .buttonStyle(.plain)
                                    Button {
                                        store.toggleWatchlist(show)
                                    } label: {
                                        Image(
                                            systemName:
                                                store.isInWatchlist(show)
                                                ? "heart.fill"
                                                : "heart"
                                        )
                                        .foregroundStyle(.pink)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .overlay {
            if let selectedPersonPhoto {
                PhotoLightboxOverlay(
                    photo: selectedPersonPhoto,
                    photos: Array(store.personImages.prefix(18)),
                    imageURL: { $0.fullSizeURL },
                    onClose: { self.selectedPersonPhoto = nil }
                )
            }
        }
    }

    private var actorPlaceholder: some View {
        ZStack {
            Color.secondary.opacity(0.10)
            Image(systemName: "person.crop.rectangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
        }
    }

    private var ageText: String? {
        guard store.personDetails?.deathday == nil else { return nil }
        return age(birthday: store.personDetails?.birthday, endDate: nil)
            .map { "\($0) 岁" }
    }

    private var deathAgeText: Int? {
        age(
            birthday: store.personDetails?.birthday,
            endDate: store.personDetails?.deathday
        )
    }

    private func age(birthday: String?, endDate: String?) -> Int? {
        guard let birthday else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let start = formatter.date(from: birthday) else { return nil }
        let end = endDate.flatMap { formatter.date(from: $0) } ?? Date()
        return Calendar.current.dateComponents(
            [.year],
            from: start,
            to: end
        ).year
    }

    private func mapURL(_ place: String) -> URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [URLQueryItem(name: "q", value: place)]
        return components?.url
    }

}

@MainActor
final class PhotoDownloadCoordinator: ObservableObject {
    @Published private(set) var isSaving = false
    @Published private(set) var message: String?

    func save(sourceURL: URL) {
        let panel = NSSavePanel()
        panel.title = "保存图片"
        panel.nameFieldStringValue = PhotoDownloadFilename.suggestedName(
            for: sourceURL
        )
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.image]

        panel.begin { [weak self, panel] response in
            guard response == .OK, let destination = panel.url else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isSaving = true
                self.message = nil
                defer { self.isSaving = false }

                do {
                    var request = URLRequest(url: sourceURL)
                    request.cachePolicy = .reloadIgnoringLocalCacheData
                    let (data, response) = try await URLSession.shared.data(
                        for: request
                    )
                    guard let httpResponse = response as? HTTPURLResponse,
                          (200..<300).contains(httpResponse.statusCode)
                    else {
                        throw URLError(.badServerResponse)
                    }
                    try data.write(to: destination, options: .atomic)
                    self.message = "已保存：\(destination.lastPathComponent)"
                } catch {
                    self.message = "保存失败：\(error.localizedDescription)"
                }
            }
        }
    }
}

struct PhotoLightboxOverlay<Photo: Hashable>: View {
    let photos: [Photo]
    let imageURL: (Photo) -> URL?
    let onClose: () -> Void
    @State private var currentIndex: Int
    @StateObject private var downloadCoordinator = PhotoDownloadCoordinator()

    init(
        photo: Photo,
        photos: [Photo],
        imageURL: @escaping (Photo) -> URL?,
        onClose: @escaping () -> Void
    ) {
        self.photos = photos
        self.imageURL = imageURL
        self.onClose = onClose
        _currentIndex = State(initialValue: photos.firstIndex(of: photo) ?? 0)
    }

    private var photo: Photo? {
        guard photos.indices.contains(currentIndex) else { return nil }
        return photos[currentIndex]
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.96)

            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Text("\(min(currentIndex + 1, photos.count)) / \(photos.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.82))
                    Spacer()
                    Button {
                        guard let photo, let sourceURL = imageURL(photo) else {
                            return
                        }
                        downloadCoordinator.save(sourceURL: sourceURL)
                    } label: {
                        Label(
                            downloadCoordinator.isSaving ? "保存中" : "下载",
                            systemImage: downloadCoordinator.isSaving
                                ? "hourglass"
                                : "arrow.down.circle"
                        )
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.94))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(
                            Color.white.opacity(0.14),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(photo == nil || downloadCoordinator.isSaving)
                    .accessibilityLabel("下载图片")
                    .help("保存当前图片")
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 25))
                            .foregroundStyle(.white.opacity(0.92))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭图片")
                    .help("关闭图片")
                }

                ZStack {
                    if let photo {
                        AsyncImage(url: imageURL(photo)) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFit()
                            case .failure:
                                Image(systemName: "photo")
                                    .font(.system(size: 54))
                                    .foregroundStyle(.white.opacity(0.65))
                            default:
                                ProgressView()
                                    .controlSize(.large)
                                    .tint(.white)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    HStack {
                        if PhotoLightboxNavigation.adjacentIndex(
                            currentIndex: currentIndex,
                            offset: -1,
                            count: photos.count
                        ) != nil {
                            Button { move(by: -1) } label: {
                                Image(systemName: "chevron.left.circle.fill")
                                    .font(.system(size: 34))
                                    .foregroundStyle(.white.opacity(0.90))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("上一张照片")
                        }
                        Spacer()
                        if PhotoLightboxNavigation.adjacentIndex(
                            currentIndex: currentIndex,
                            offset: 1,
                            count: photos.count
                        ) != nil {
                            Button { move(by: 1) } label: {
                                Image(systemName: "chevron.right.circle.fill")
                                    .font(.system(size: 34))
                                    .foregroundStyle(.white.opacity(0.90))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("下一张照片")
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.90))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if let message = downloadCoordinator.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.86))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .zIndex(1000)
    }

    private func move(by offset: Int) {
        guard let nextIndex = PhotoLightboxNavigation.adjacentIndex(
            currentIndex: currentIndex,
            offset: offset,
            count: photos.count
        ) else { return }
        currentIndex = nextIndex
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = proposal.width ?? 360
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct CineGlassModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.48), .white.opacity(0.08), .orange.opacity(0.16)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            }
            .shadow(color: .black.opacity(0.10), radius: 14, y: 6)
    }
}

extension View {
    func cineGlass(cornerRadius: CGFloat = 14) -> some View {
        modifier(CineGlassModifier(cornerRadius: cornerRadius))
    }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, recommendation, data, localLibrary, info, support
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "通用"
        case .recommendation: return "推荐偏好"
        case .data: return "数据来源"
        case .localLibrary: return "本地片库"
        case .info: return "检查更新"
        case .support: return "支持"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .recommendation: return "heart.text.square"
        case .data: return "server.rack"
        case .localLibrary: return "externaldrive.fill"
        case .info: return "info.circle"
        case .support: return "cup.and.saucer.fill"
        }
    }
}

struct SettingsRootView: View {
    @ObservedObject var store: MovieStore
    @ObservedObject var updaterService: UpdaterService
    @ObservedObject var localLibraryStore: LocalLibraryStore
    @State private var selection: SettingsSection = .general
    @Environment(\.openURL) private var openURL

    private let regions = [
        ("CN", "中国大陆"), ("HK", "中国香港"), ("TW", "中国台湾"),
        ("US", "美国"), ("GB", "英国"), ("JP", "日本"), ("KR", "韩国")
    ]

    private static var shortVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.8.3-test.15"
    }

    private static var buildNumber: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "0"
    }

    private static var displayVersion: String {
        shortVersion
    }

    private static var buildDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy 年 M 月"
        return formatter.string(from: Date())
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("CineBar").font(.headline)
                        Text("设置").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 16)

                List(SettingsSection.allCases, selection: $selection) { section in
                    Label(LocalizedStringKey(section.title), systemImage: section.symbol)
                        .tag(section)
                }
                .listStyle(.sidebar)
            }
            .frame(width: 190)
            .background(.ultraThinMaterial)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label(LocalizedStringKey(selection.title), systemImage: selection.symbol)
                        .font(.title2.bold())
                    switch selection {
                    case .general: generalSettings
                    case .recommendation: recommendationSettings
                    case .data: dataSettings
                    case .localLibrary: localLibrarySettings
                    case .info: infoSettings
                    case .support: support
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(26)
            }
        }
        .frame(width: 760, height: 560)
        .environment(\.locale, Locale(identifier: store.appLanguage.localeIdentifier))
    }

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsCard {
                Label("外观", systemImage: "circle.lefthalf.filled").font(.headline)
                Picker("外观", selection: Binding(
                    get: { store.appearanceMode },
                    set: { store.setAppearance($0) }
                )) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(LocalizedStringKey(mode.title)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Divider()
                HStack {
                    Text("玻璃背景不透明度")
                    Spacer()
                    Text(
                        "\(Int((store.glassBackgroundOpacity * 100).rounded()))%"
                    )
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { store.glassBackgroundOpacity },
                        set: { store.setGlassBackgroundOpacity($0) }
                    ),
                    in: GlassBackgroundOpacity.range,
                    step: 0.01
                )
                Button("恢复默认") {
                    store.setGlassBackgroundOpacity(
                        GlassBackgroundOpacity.defaultValue
                    )
                }
            }
            settingsCard {
                Label("语言与地区", systemImage: "globe").font(.headline)
                Picker("语言", selection: Binding(
                    get: { store.appLanguage },
                    set: { store.setLanguage($0) }
                )) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                Text("选择繁体中文时会自动对应香港或台湾的上映与观看地区。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            settingsCard {
                Label("自动隐藏", systemImage: "timer").font(.headline)
                Picker("自动隐藏", selection: Binding(
                    get: { store.autoHideInterval },
                    set: { store.setAutoHideInterval($0) }
                )) {
                    ForEach(AutoHideInterval.allCases) { interval in
                        Text(LocalizedStringKey(interval.title)).tag(interval)
                    }
                }
                Text("菜单栏窗口内操作会重新计时；独立设置窗口不受此计时影响。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            settingsCard {
                Label("窗口行为", systemImage: "macwindow").font(.headline)
                Toggle(
                    "允许拖动主窗口",
                    isOn: Binding(
                        get: { store.isPanelMovable },
                        set: { store.setPanelMovable($0) }
                    )
                )
                Text("开启后可按住窗口空白区域移动 CineBar；关闭后仍会跟随菜单栏图标所在屏幕。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            settingsCard {
                Label("启动", systemImage: "power").font(.headline)
                Toggle(
                    "登录 Mac 时自动启动 CineBar",
                    isOn: Binding(
                        get: { store.launchAtLogin },
                        set: { store.setLaunchAtLogin($0) }
                    )
                )
                Text("由 macOS 登录项管理，可随时在这里关闭。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var recommendationSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingsCard {
                Text("电影偏好")
                    .font(.headline)
                Text("用于每天推荐 3 部电影；可多选，不选择代表不限类型。")
                    .foregroundStyle(.secondary)
                FlowLayout(spacing: 7) {
                    ForEach(MovieShelf.genreOptions) { shelf in
                        if let genreID = shelf.genreID {
                            let selected = store.preferredMovieGenreIDs.contains(genreID)
                            Button {
                                store.togglePreferredMovieGenre(genreID)
                            } label: {
                                Label(
                                    LocalizedStringKey(shelf.title),
                                    systemImage: shelf.symbol
                                )
                                .font(.caption)
                                .padding(.horizontal, 9).padding(.vertical, 6)
                                .foregroundStyle(selected ? .white : .primary)
                                .background(
                                    selected
                                        ? Color.accentColor
                                        : Color.secondary.opacity(0.10),
                                    in: Capsule()
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Divider()
                CountryPreferenceSelector(
                    store: store,
                    title: "偏好国家 / 地区（可多选）",
                    selectedCodes: store.preferredMovieCountryCodes,
                    toggle: store.togglePreferredMovieCountry
                )
            }
            settingsCard {
                Text("电视剧偏好")
                    .font(.headline)
                Text("用于每日电视剧推荐；可多选，不选择代表不限类型。")
                    .foregroundStyle(.secondary)
                FlowLayout(spacing: 7) {
                    ForEach(TVGenre.options) { genre in
                        let selected = store.preferredTVGenreIDs.contains(genre.id)
                        Button {
                            store.togglePreferredTVGenre(genre.id)
                        } label: {
                            Label(
                                LocalizedStringKey(genre.title),
                                systemImage: genre.symbol
                            )
                            .font(.caption)
                            .padding(.horizontal, 9).padding(.vertical, 6)
                            .foregroundStyle(selected ? .white : .primary)
                            .background(
                                selected
                                    ? Color.accentColor
                                    : Color.secondary.opacity(0.10),
                                in: Capsule()
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                Divider()
                CountryPreferenceSelector(
                    store: store,
                    title: "偏好国家 / 地区（可多选）",
                    selectedCodes: store.preferredTVCountryCodes,
                    toggle: store.togglePreferredTVCountry
                )
            }
            HStack {
                Spacer()
                Button("保存并刷新推荐") {
                    store.saveSettings()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var dataSettings: some View {
        let presentation = DataSettingsPresentation(
            proxyBaseURL: store.dataProxyURL
        )
        return settingsCard {
            if presentation.usesBuiltInService {
                Label(
                    presentation.serviceTitle(language: store.appLanguage),
                    systemImage: "checkmark.seal.fill"
                )
                    .font(.headline)
                    .foregroundStyle(.green)
                Text(
                    presentation.serviceDetail(language: store.appLanguage)
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("影片与电视剧资料") {
                    Text("TMDB").foregroundStyle(.secondary)
                }
                LabeledContent("IMDb、烂番茄与 Metacritic 评分") {
                    Text("OMDb").foregroundStyle(.secondary)
                }
                LabeledContent("电视剧播出时间") {
                    Text("TVMaze").foregroundStyle(.secondary)
                }
            } else {
                SecureField("TMDB Read Access Token", text: $store.token)
                    .textFieldStyle(.roundedBorder)
                SecureField("OMDb API Key（可选）", text: $store.omdbKey)
                    .textFieldStyle(.roundedBorder)
            }
            Picker("观看地区", selection: $store.region) {
                ForEach(regions, id: \.0) { code, name in
                    Text("\(name)（\(code)）").tag(code)
                }
            }
            if presentation.showsCredentialFields {
                HStack {
                    Link("申请影片数据 Token", destination: URL(string: "https://www.themoviedb.org/settings/api")!)
                    Link("申请外部评分 Key", destination: URL(string: "https://www.omdbapi.com/apikey.aspx")!)
                    Link("TVMaze 数据说明", destination: URL(string: "https://www.tvmaze.com/api")!)
                }
                .font(.caption)
            }
            Text("电视剧下一集播出时间由 TVMaze 补充，无需用户申请账号或 API Key。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(LocalizedStringKey(
                "匿名安装统计：每天最多上报一次版本、构建号、macOS 主版本、芯片架构和界面语言。安装编号仅用于去重并在服务端转换为不可逆哈希；不会上传影片、文件路径、账号或原始安装编号。测试版不提供关闭开关。"
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let diagnostic = store.latestServiceDiagnostic {
                Divider()
                Label("最近一次服务异常", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                    .foregroundStyle(.orange)
                LabeledContent("服务") {
                    Text(diagnostic.service)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("错误类型") {
                    Text(
                        diagnostic.category.displayName(
                            language: store.appLanguage
                        )
                    )
                    .foregroundStyle(.secondary)
                }
                LabeledContent("服务地址") {
                    Text(diagnostic.requestURL.host ?? "—")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("复制诊断信息") {
                        store.copyLatestServiceDiagnostic()
                    }
                    if !store.diagnosticCopyMessage.isEmpty {
                        Text(LocalizedStringKey(store.diagnosticCopyMessage))
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
            HStack {
                Spacer()
                Button("保存并刷新") { store.saveSettings() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var localLibrarySettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("本地片库").font(.headline)
                    Text("在此添加和管理本地文件夹，扫描后可在本地片库中浏览与播放视频。")
                        .font(.caption).foregroundStyle(.secondary)

                    Divider()

                    HStack {
                        Text("本地文件夹").font(.subheadline.bold())
                        Spacer()
                        Button("添加文件夹", systemImage: "folder.badge.plus") {
                            chooseLocalFolder()
                        }
                    }
                    if localLibraryStore.folders.isEmpty {
                        Text("尚未添加本地文件夹。").font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(localLibraryStore.folders) { folder in
                            HStack {
                                Label(folder.displayName, systemImage: "externaldrive.fill")
                                Spacer()
                                Text(folder.pathHint).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func chooseLocalFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "添加"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            try? localLibraryStore.addFolder(url: url)
        }
    }

    /// 合并“新功能 / 关于 / 检查更新”为一栏。
    private var infoSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingsCard {
                HStack {
                    VStack(alignment: .leading) {
                        Text("CineBar \(Self.displayVersion)").font(.title3.bold())
                        Text("Build \(Self.buildNumber) · \(Self.buildDate)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(.orange)
                }
                HStack {
                    Text("自动检查更新")
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { updaterService.automaticallyChecksForUpdates },
                        set: { updaterService.automaticallyChecksForUpdates = $0 }
                    ))
                    .labelsHidden()

                    Button("检查更新") {
                        updaterService.checkForUpdates()
                    }
                    .disabled(!updaterService.canCheckForUpdates)
                    .opacity(updaterService.canCheckForUpdates ? 1 : 0.5)
                }
                Text("更新包会在安装前验证 CineBar 的独立签名。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            settingsCard {
                Text("版本更新记录").font(.subheadline.bold())
                VersionHistoryCard()
            }
            settingsCard {
                MagnetIndexCard()
            }
            settingsCard {
                Text("关于").font(.subheadline.bold())
                Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("OMDb 内容按非商业许可使用；观看平台信息由 JustWatch 提供。")
                    .font(.caption).foregroundStyle(.secondary)
                Link("电视剧播出时间由 TVMaze 提供（CC BY-SA）",
                     destination: URL(string: "https://www.tvmaze.com")!)
                Text("商业化前须分别确认各数据源授权。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var support: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                settingsCard {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(.orange)
                    Text("支持 CineBar").font(.title2.bold())
                    Text("CineBar 承诺完全免费、无广告、无订阅。若它为你省下了寻找影片的时间，欢迎通过网页支持我们，让项目持续更新。")
                        .foregroundStyle(.secondary)
                    Button {
                        if let url = store.supportURL { openURL(url) }
                    } label: {
                        Label("前往支持页", systemImage: "safari")
                            .frame(minWidth: 180)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(store.supportURL == nil)
                }
            }
        }
    }

    private func qrCodeCard(title: String, imageName: String) -> some View {
        VStack(spacing: 8) {
            let image = donationImage(named: imageName)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 140, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.quaternary)
                    Text("待配置")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(width: 140, height: 140)
            }
            Text(title).font(.subheadline)
        }
    }

    private func donationImage(named name: String) -> NSImage? {
        if let url = Bundle.main.url(forResource: name, withExtension: "png") {
            return NSImage(contentsOf: url)
        }
        if let url = Bundle.main.url(forResource: name, withExtension: "jpg") {
            return NSImage(contentsOf: url)
        }
        return nil
    }

    private func featureRow(_ text: String) -> some View {
        Label(LocalizedStringKey(text), systemImage: "checkmark.circle.fill")
    }

    private func settingsCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cineGlass(cornerRadius: 14)
    }
}

/// 单个版本发布说明条目。
struct VersionHistoryEntry: Identifiable {
    let version: Int
    let title: String
    let notes: [String]
    var id: Int { version }
}

/// 从 app bundle 的 ReleaseNotes 目录读取所有版本记录（按构建号降序）。
enum VersionHistoryLoader {
    static func loadAll() -> [VersionHistoryEntry] {
        guard let url = Bundle.main.resourceURL?
            .appendingPathComponent("ReleaseNotes", isDirectory: true)
        else { return [] }
        let manager = FileManager.default
        guard let urls = try? manager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil
        ) else { return [] }
        let txtFiles = urls.filter { $0.pathExtension == "txt" }
        let parsed = txtFiles.compactMap(parse(file:))
        return parsed.sorted { $0.version > $1.version }
    }

    static func parse(file url: URL) -> VersionHistoryEntry? {
        guard let content = try? String(
            contentsOf: url,
            encoding: .utf8
        ) else { return nil }
        let lines = content.split(separator: "\n").map(String.init)
        let title = lines.first ?? url.lastPathComponent
        let notes = lines.dropFirst()
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("-") }
            .map {
                $0.dropFirst().trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
        return VersionHistoryEntry(
            version: buildNumber(from: url.lastPathComponent),
            title: title,
            notes: notes
        )
    }

    static func buildNumber(from filename: String) -> Int {
        let parts = filename.split(separator: "-")
        guard let lastText = parts.last else { return 0 }
        return Int(lastText.dropLast(4)) ?? 0  // "Build-42.txt" → 42
    }
}

/// 设置-检查更新里的"版本更新记录"卡片。
struct VersionHistoryCard: View {
    private let entries = VersionHistoryLoader.loadAll()

    var body: some View {
        Group {
            if entries.isEmpty {
                Text("未找到版本记录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.title)
                            .font(.caption.bold())
                            .foregroundStyle(.primary)
                        ForEach(entry.notes, id: \.self) { note in
                            Label(note, systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if entry.id != entries[0].id {
                            Divider().padding(.vertical, 5)
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
        }
    }
}

struct DailyRecommendationCard: View {
    @ObservedObject var store: MovieStore
    let movie: Movie

    var body: some View {
        HStack(spacing: 13) {
            PosterView(movie: movie, width: 72, height: 104)
                .onTapGesture { store.select(movie) }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Label("每日电影推荐", systemImage: "sun.max.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                    Spacer()
                    Button {
                        store.refreshDailyRecommendation()
                    } label: {
                        if store.isLoadingDaily {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.plain)
                    .help("换一部推荐")
                    .disabled(store.isLoadingDaily)
                }

                Text(movie.title)
                    .font(.headline)
                    .lineLimit(1)
                    .onTapGesture { store.select(movie) }
                    .contextMenu {
                        Button("复制片名") {
                            copyToPasteboard(movie.title)
                        }
                    }

                HStack(spacing: 8) {
                    Label(String(format: "%.1f", movie.voteAverage), systemImage: "star.fill")
                        .foregroundStyle(.orange)
                    Text(movie.year)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)

                Text(movie.overview.isEmpty ? "今天就看这一部。" : movie.overview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .onTapGesture { store.select(movie) }
            }

            Button {
                store.select(movie)
            } label: {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            LinearGradient(
                colors: [.orange.opacity(0.13), .indigo.opacity(0.09)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.orange.opacity(0.18))
        }
        .cineGlass(cornerRadius: 12)
    }
}

struct DailyTVRecommendationCard: View {
    @ObservedObject var store: MovieStore
    let show: TVShow

    var body: some View {
        HStack(spacing: 13) {
            TVPosterView(show: show, width: 72, height: 104)
                .onTapGesture { store.selectTV(show) }
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Label("每日电视剧推荐", systemImage: "sparkles.tv.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.indigo)
                    Spacer()
                    Button {
                        store.refreshDailyTVRecommendation()
                    } label: {
                        if store.isLoadingDaily {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.plain)
                    .help("换一部推荐")
                    .disabled(store.isLoadingDaily)
                }
                Text(show.name)
                    .font(.headline)
                    .lineLimit(1)
                    .onTapGesture { store.selectTV(show) }
                HStack(spacing: 8) {
                    Label(
                        String(format: "%.1f", show.voteAverage),
                        systemImage: "star.fill"
                    )
                    .foregroundStyle(.orange)
                    Text(show.year).foregroundStyle(.secondary)
                }
                .font(.caption)
                Text(show.overview.isEmpty ? "今天追这一部。" : show.overview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .onTapGesture { store.selectTV(show) }
            }
            Button {
                store.toggleWatchlist(show)
            } label: {
                Image(
                    systemName: store.isInWatchlist(show)
                        ? "heart.fill"
                        : "heart"
                )
                .foregroundStyle(.pink)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            LinearGradient(
                colors: [.indigo.opacity(0.13), .orange.opacity(0.07)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .cineGlass(cornerRadius: 12)
    }
}

struct ShelfButton: View {
    let shelf: MovieShelf
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: shelf.symbol)
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? .white : .orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text(shelf.title)
                        .font(.caption.bold())
                    Text(shelf.subtitle)
                        .font(.caption2)
                        .foregroundStyle(isSelected ? .white.opacity(0.78) : .secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.secondary.opacity(0.08)),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct CountrySingleSelector: View {
    @ObservedObject var store: MovieStore
    @Binding var selection: String?
    @State private var searchText = ""

    private var filteredCountries: [TMDBCountry] {
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            let common = ["CN", "US", "GB", "JP", "KR", "FR", "DE", "IN", "CA", "AU"]
            return common.compactMap { code in
                store.countries.first { $0.isoCode == code }
            }
        }
        return Array(store.countries.filter {
            $0.isoCode.localizedCaseInsensitiveContains(text) ||
                $0.englishName.localizedCaseInsensitiveContains(text) ||
                $0.nativeName.localizedCaseInsensitiveContains(text) ||
                $0.displayName(language: store.appLanguage)
                    .localizedCaseInsensitiveContains(text)
        }.prefix(30))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                TextField("搜索国家或地区", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                if selection != nil {
                    Button("不限国家") { selection = nil }
                        .buttonStyle(.borderless)
                }
            }
            FlowLayout(spacing: 6) {
                Button {
                    selection = nil
                } label: {
                    Text("不限国家")
                        .countryChoiceStyle(selected: selection == nil)
                }
                .buttonStyle(.plain)
                ForEach(filteredCountries) { country in
                    Button {
                        selection = country.isoCode
                    } label: {
                        Text(
                            "\(country.displayName(language: store.appLanguage)) · \(country.isoCode)"
                        )
                        .countryChoiceStyle(
                            selected: selection == country.isoCode
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onAppear { store.loadCountries() }
    }
}

private extension View {
    func countryChoiceStyle(selected: Bool) -> some View {
        self
            .font(.caption)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .foregroundStyle(selected ? .white : .primary)
            .background(
                selected ? Color.accentColor : Color.secondary.opacity(0.10),
                in: Capsule()
            )
    }
}

struct CountryPreferenceSelector: View {
    @ObservedObject var store: MovieStore
    let title: String
    let selectedCodes: Set<String>
    let toggle: (String) -> Void
    @State private var searchText = ""

    private var filteredCountries: [TMDBCountry] {
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            let common = ["CN", "US", "GB", "JP", "KR", "FR", "DE", "IN", "CA", "AU"]
            return common.compactMap { code in
                store.countries.first { $0.isoCode == code }
            }
        }
        return Array(store.countries.filter {
            $0.isoCode.localizedCaseInsensitiveContains(text) ||
                $0.englishName.localizedCaseInsensitiveContains(text) ||
                $0.nativeName.localizedCaseInsensitiveContains(text) ||
                $0.displayName(language: store.appLanguage)
                    .localizedCaseInsensitiveContains(text)
        }.prefix(40))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.subheadline.bold())
            TextField("搜索全部国家或地区", text: $searchText)
                .textFieldStyle(.roundedBorder)
            if selectedCodes.isEmpty {
                Text("不限国家")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            FlowLayout(spacing: 6) {
                ForEach(filteredCountries) { country in
                    Button {
                        toggle(country.isoCode)
                    } label: {
                        Text(
                            "\(country.displayName(language: store.appLanguage)) · \(country.isoCode)"
                        )
                        .countryChoiceStyle(
                            selected: selectedCodes.contains(country.isoCode)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onAppear { store.loadCountries() }
    }
}

struct CatalogPanel: View {
    @ObservedObject var store: MovieStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("分类选片", systemImage: "square.grid.2x2.fill")
                    .font(.headline)
                Spacer()
                Button {
                    store.showCatalog = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("上映年代")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    FlowLayout(spacing: 6) {
                        ForEach(ReleasePeriod.options) { period in
                            let selected = store.catalogPeriod == period
                            Button {
                                store.catalogPeriod = period
                            } label: {
                                Text(period.title(language: store.appLanguage))
                            }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .foregroundStyle(selected ? .white : .primary)
                            .background(
                                selected ? Color.accentColor : Color.secondary.opacity(0.10),
                                in: Capsule()
                            )
                        }
                    }

                    Text("电影类型")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                    FlowLayout(spacing: 6) {
                        ForEach(MovieShelf.genreOptions) { shelf in
                            let selected = store.catalogFilterIDs.contains(shelf.id)
                            Button {
                                store.selectCatalogFilter(shelf.id)
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: shelf.symbol)
                                    Text(LocalizedStringKey(shelf.title))
                                }
                                    .font(.caption)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 6)
                                    .foregroundStyle(selected ? .white : .primary)
                                    .background(
                                        selected ? Color.accentColor : Color.secondary.opacity(0.10),
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Text("国家 / 地区")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    CountrySingleSelector(
                        store: store,
                        selection: $store.catalogCountryCode
                    )

                    HStack {
                        Button("清除筛选") {
                            store.clearCatalogFilters()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        Spacer()
                        Button("应用筛选") {
                            store.applyCatalogFilters()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .frame(minHeight: 170, maxHeight: 300)
        }
        .padding()
        .cineGlass()
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }
}

struct TVCatalogPanel: View {
    @ObservedObject var store: MovieStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("分类选剧", systemImage: "tv.fill")
                    .font(.headline)
                Spacer()
                Button {
                    store.showTVCatalog = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("首播年代")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    FlowLayout(spacing: 6) {
                        ForEach(ReleasePeriod.options) { period in
                            let selected = store.tvCatalogPeriod == period
                            Button {
                                store.tvCatalogPeriod = period
                            } label: {
                                Text(period.title(language: store.appLanguage))
                            }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .foregroundStyle(selected ? .white : .primary)
                            .background(
                                selected
                                    ? Color.accentColor
                                    : Color.secondary.opacity(0.10),
                                in: Capsule()
                            )
                        }
                    }

                    Text("电视剧类型")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    FlowLayout(spacing: 6) {
                        ForEach(TVGenre.options) { genre in
                            let selected = store.tvCatalogGenreID == genre.id
                            Button {
                                store.tvCatalogGenreID = selected ? nil : genre.id
                            } label: {
                                Label(
                                    LocalizedStringKey(genre.title),
                                    systemImage: genre.symbol
                                )
                                .font(.caption)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .foregroundStyle(selected ? .white : .primary)
                                .background(
                                    selected
                                        ? Color.accentColor
                                        : Color.secondary.opacity(0.10),
                                    in: Capsule()
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Text("国家 / 地区")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    CountrySingleSelector(
                        store: store,
                        selection: $store.tvCatalogCountryCode
                    )

                    HStack {
                        Button("清除选项") {
                            store.tvCatalogPeriod = .options[0]
                            store.tvCatalogGenreID = nil
                            store.tvCatalogCountryCode = nil
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        Spacer()
                        Button("应用筛选") {
                            store.applyTVCatalogFilters()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .frame(minHeight: 170, maxHeight: 300)
        }
        .padding()
        .cineGlass()
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }
}

struct ResizeTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

final class VerticalResizeHandleView: NSView {
    private var initialMouseLocation: NSPoint?
    private var initialWindowFrame: NSRect?

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeUpDown)
    }

    override func mouseDown(with event: NSEvent) {
        initialMouseLocation = NSEvent.mouseLocation
        initialWindowFrame = window?.frame
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window,
              let initialMouseLocation,
              let initialWindowFrame else { return }
        let deltaY = NSEvent.mouseLocation.y - initialMouseLocation.y
        let maximumHeight = min(
            window.maxSize.height,
            window.screen?.visibleFrame.height ?? window.maxSize.height
        )
        let height = min(
            max(initialWindowFrame.height - deltaY, window.minSize.height),
            maximumHeight
        )
        var frame = initialWindowFrame
        frame.size.height = height
        frame.origin.y = initialWindowFrame.maxY - height
        window.setFrame(frame, display: true)
    }

    override func mouseUp(with event: NSEvent) {
        initialMouseLocation = nil
        initialWindowFrame = nil
    }
}

struct VerticalResizeHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> VerticalResizeHandleView {
        VerticalResizeHandleView(frame: .zero)
    }

    func updateNSView(
        _ nsView: VerticalResizeHandleView,
        context: Context
    ) {}
}

struct ContentView: View {
    @ObservedObject var store: MovieStore
    @ObservedObject var localLibraryStore: LocalLibraryStore
    @State private var localLibrarySearchText = ""
    @State private var localLibraryCategoryFilter = LocalLibraryCategoryFilter.all
    @State private var localLibraryStatusFilter = LocalLibraryStatusFilter.all
    private let reminderCheckTimer = Timer.publish(
        every: 6 * 60 * 60,
        on: .main,
        in: .common
    ).autoconnect()

    private var isShowingDetail: Bool {
        store.showMovieStills ||
            store.selectedPerson != nil ||
            store.selectedMovie != nil ||
            store.selectedTVShow != nil ||
            store.isShowingLocalLibrary
    }

    var body: some View {
        ZStack {
            mainList
                .opacity(isShowingDetail ? 0 : 1)
                .allowsHitTesting(!isShowingDetail)
                .accessibilityHidden(isShowingDetail)

            if store.showMovieStills, let movie = store.selectedMovie {
                MovieStillsView(store: store, movie: movie)
            } else if let person = store.selectedPerson {
                PersonDetailView(store: store, person: person)
            } else if let movie = store.selectedMovie {
                MovieDetailView(
                    store: store,
                    movie: movie,
                    onPlayLocalFile: localPlayback(for: movie.id)
                )
            } else if let show = store.selectedTVShow {
                TVDetailView(
                    store: store,
                    show: show,
                    onPlayLocalFile: localPlayback(for: show.id)
                )
            } else if store.isShowingLocalLibrary {
                LocalLibraryView(
                    store: localLibraryStore,
                    movieStore: store,
                    searchText: $localLibrarySearchText,
                    categoryFilter: $localLibraryCategoryFilter,
                    statusFilter: $localLibraryStatusFilter
                )
            }
        }
        .frame(width: 520)
        .frame(minHeight: 560, idealHeight: 720, maxHeight: .infinity)
        .environment(
            \.locale,
            Locale(identifier: store.appLanguage.localeIdentifier)
        )
        .background {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                    .opacity(store.glassBackgroundOpacity)
                LinearGradient(
                    colors: [
                        Color.indigo.opacity(0.055),
                        Color.orange.opacity(0.035),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .onAppear {
            if store.hasToken, store.movies == Movie.demo {
                store.loadTrending()
            }
            store.loadDailyRecommendation()
            store.loadDailyTVRecommendation()
            store.loadCountries()
            store.checkReleaseReminders()
        }
        .onReceive(reminderCheckTimer) { _ in
            store.checkReleaseReminders()
        }
    }

    /// 供大页详情播放本地片库中对应影片/剧集文件。无匹配文件时返回 nil（隐藏按钮）。
    private func localPlayback(for mediaID: Int) -> (() -> Void)? {
        guard LocalLibraryFileResolver.hasAvailable(in: localLibraryStore, metadataID: mediaID) else {
            return nil
        }
        return {
            guard let fileURL = LocalLibraryFileResolver.resolveFileURL(
                in: self.localLibraryStore,
                metadataID: mediaID
            ) else { return }
            Task {
                _ = await ExternalPlayerLauncher().open(fileURL: fileURL)
            }
        }
    }

    private var mainList: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack {
                    Button {
                        NotificationCenter.default.post(
                            name: .cineBarPanelWillHide,
                            object: nil
                        )
                        NSApplication.shared.keyWindow?.orderOut(nil)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("关闭窗口")

                    VStack(alignment: .leading, spacing: 1) {
                        Text("CineBar").font(.title2.bold())
                        Text("找到下一部好片")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        if store.mediaSection == .movies {
                            store.setMovieBrowseSection(.trending)
                        } else {
                            store.setTVBrowseSection(.trending)
                        }
                    } label: {
                        Image(systemName: "flame")
                    }
                    .help("本周热门")
                    Button {
                        if store.mediaSection == .movies {
                            store.showCatalog.toggle()
                            store.showTVCatalog = false
                        } else {
                            store.showTVCatalog.toggle()
                            store.showCatalog = false
                        }
                    } label: {
                        Image(systemName: "square.grid.2x2")
                    }
                    .help(
                        store.mediaSection == .movies
                            ? "分类选片"
                            : "分类选剧"
                    )
                    Button {
                        NotificationCenter.default.post(
                            name: .cineBarOpenSettings,
                            object: nil
                        )
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .help("设置")
                }

                Picker(
                    "内容类型",
                    selection: Binding(
                        get: { store.mainBrowseSection },
                        set: { store.setMainBrowseSection($0) }
                    )
                ) {
                    ForEach(MainBrowseSection.allCases) { section in
                        Text(section.title(language: store.appLanguage))
                            .tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if !store.isShowingWatchlist {
                    if store.mediaSection == .movies {
                        Picker(
                            "电影栏目",
                            selection: Binding(
                                get: { store.movieBrowseSection },
                                set: { store.setMovieBrowseSection($0) }
                            )
                        ) {
                            ForEach(MovieBrowseSection.allCases) { section in
                                Text(LocalizedStringKey(section.title))
                                    .tag(section)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .controlSize(.small)
                    } else {
                        Picker(
                            "电视剧栏目",
                            selection: Binding(
                                get: { store.tvBrowseSection },
                                set: { store.setTVBrowseSection($0) }
                            )
                        ) {
                            ForEach(TVBrowseSection.allCases) { section in
                                Text(LocalizedStringKey(section.title))
                                    .tag(section)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .controlSize(.small)
                    }
                }

                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        TextField(
                            store.mediaSection == .movies
                                ? "搜索电影或演员"
                                : "搜索电视剧或演员",
                            text: $store.searchText
                        )
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { store.performSearch() }
                        if !store.searchText.isEmpty {
                            Button {
                                store.clearSearch()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("清除搜索")
                        }
                    }
                    Button {
                        store.performSearch()
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()

            if store.showCatalog {
                CatalogPanel(store: store)
                Divider()
            } else if store.showTVCatalog {
                TVCatalogPanel(store: store)
                Divider()
            }

            HStack {
                if store.isLoading {
                    ProgressView().controlSize(.small)
                }
                Text(store.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if store.mediaSection == .movies &&
                    store.movieBrowseSection == .recommendations &&
                    !store.isShowingWatchlist &&
                    !store.isCatalogResult {
                    Button {
                        store.refreshDailyRecommendation()
                    } label: {
                        Label("换一组", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(store.isLoadingDaily)
                }
                if store.mediaSection == .television &&
                    store.tvBrowseSection == .recommendations &&
                    !store.isShowingWatchlist &&
                    !store.isTVCatalogResult {
                    Button {
                        store.refreshDailyTVRecommendation()
                    } label: {
                        Label("换一组", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(store.isLoadingDaily)
                }
                if store.mediaSection == .movies && store.isCatalogResult {
                    Button("清除筛选") {
                        store.clearAppliedCatalogFilters()
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.orange)
                    Menu {
                        ForEach(CatalogSortMode.allCases) { mode in
                            Button {
                                store.setCatalogSortMode(mode)
                            } label: {
                                if store.catalogSortMode == mode {
                                    Label(
                                        mode.title(language: store.appLanguage),
                                        systemImage: "checkmark"
                                    )
                                } else {
                                    Text(mode.title(language: store.appLanguage))
                                }
                            }
                        }
                    } label: {
                        Label(
                            store.catalogSortMode.title(
                                language: store.appLanguage
                            ),
                            systemImage: "arrow.up.arrow.down"
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                } else if store.mediaSection == .television &&
                            store.isTVCatalogResult {
                    Button("清除筛选") {
                        store.clearAppliedTVCatalogFilters()
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.orange)
                    Menu {
                        ForEach(CatalogSortMode.allCases) { mode in
                            Button {
                                store.setTVCatalogSortMode(mode)
                            } label: {
                                if store.tvCatalogSortMode == mode {
                                    Label(
                                        mode.title(language: store.appLanguage),
                                        systemImage: "checkmark"
                                    )
                                } else {
                                    Text(mode.title(language: store.appLanguage))
                                }
                            }
                        }
                    } label: {
                        Label(
                            store.tvCatalogSortMode.title(
                                language: store.appLanguage
                            ),
                            systemImage: "arrow.up.arrow.down"
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            Divider()

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    if !store.peopleSearchResults.isEmpty {
                        HStack {
                            Label("演员搜索结果", systemImage: "person.2.fill")
                                .font(.caption.bold())
                            Spacer()
                        }
                        .padding(.vertical, 7)
                        ForEach(store.peopleSearchResults.prefix(20)) { person in
                            Button {
                                store.selectPerson(person)
                            } label: {
                                PersonSearchRow(person: person)
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading, 58)
                        }
                        Text(
                            store.mediaSection == .movies
                                ? "相关电影"
                                : "相关电视剧"
                        )
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 12)
                        .padding(.bottom, 5)
                    }

                    if store.isShowingWatchlist {
                        if store.watchlistMovies.isEmpty &&
                            store.watchlistTVShows.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "heart")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                                Text("我的片单还是空的")
                                    .font(.headline)
                                Text("点击影片或电视剧旁的爱心即可收藏")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        }
                        if !store.watchlistMovies.isEmpty {
                            Text("电影")
                                .font(.caption.bold())
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 7)
                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(), spacing: 12),
                                    GridItem(.flexible(), spacing: 12)
                                ],
                                spacing: 14
                            ) {
                                ForEach(store.watchlistMovies) { movie in
                                    VStack(alignment: .leading, spacing: 6) {
                                        Button {
                                            store.select(movie)
                                        } label: {
                                            MovieCardView(store: store, movie: movie)
                                        }
                                        .buttonStyle(.plain)
                                        HStack {
                                            Spacer()
                                            Button {
                                                store.toggleWatchlist(movie)
                                            } label: {
                                                Image(systemName: "heart.fill")
                                                    .foregroundStyle(.pink)
                                            }
                                            .buttonStyle(.plain)
                                            .help("从我的片单移除")
                                        }
                                        .font(.caption)
                                        .padding(.horizontal, 2)
                                    }
                                }
                            }
                            .padding(.bottom, 12)
                        }
                        if !store.watchlistTVShows.isEmpty {
                            Text("电视剧")
                                .font(.caption.bold())
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 7)
                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(), spacing: 12),
                                    GridItem(.flexible(), spacing: 12)
                                ],
                                spacing: 14
                            ) {
                                ForEach(store.watchlistTVShows) { show in
                                    VStack(alignment: .leading, spacing: 6) {
                                        Button {
                                            store.selectTV(show)
                                        } label: {
                                            TVCardView(store: store, show: show)
                                        }
                                        .buttonStyle(.plain)
                                        HStack {
                                            Spacer()
                                            Button {
                                                store.toggleWatchlist(show)
                                            } label: {
                                                Image(systemName: "heart.fill")
                                                    .foregroundStyle(.pink)
                                            }
                                            .buttonStyle(.plain)
                                            .help("从我的片单移除")
                                        }
                                        .font(.caption)
                                        .padding(.horizontal, 2)
                                    }
                                }
                            }
                            .padding(.bottom, 12)
                        }
                    } else if store.mediaSection == .movies {
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)
                            ],
                            spacing: 14
                        ) {
                            ForEach(store.movies) { movie in
                                VStack(alignment: .leading, spacing: 6) {
                                    Button {
                                        store.select(movie)
                                    } label: {
                                        MovieCardView(store: store, movie: movie)
                                    }
                                    .buttonStyle(.plain)
                                    if store.movieBrowseSection == .upcoming,
                                       let releaseDate = movie.localizedReleaseDate,
                                       CalendarReleaseEventComposer.shouldOffer(
                                           dateText: releaseDate
                                       ) {
                                        HStack(spacing: 10) {
                                            Button {
                                                store.toggleReleaseReminder(for: movie)
                                            } label: {
                                                Image(
                                                    systemName:
                                                        store.hasReleaseReminder(
                                                            mediaType: .movie,
                                                            mediaID: movie.id
                                                        )
                                                        ? "bell.fill"
                                                        : "bell"
                                                )
                                                .foregroundStyle(.orange)
                                            }
                                            .buttonStyle(.plain)
                                            .help("设置上映提醒")

                                            CalendarReleaseEventButton(
                                                title: movie.title,
                                                dateText: releaseDate,
                                                region: store.region,
                                                language: store.appLanguage
                                            )
                                        }
                                        .font(.caption)
                                        .padding(.horizontal, 2)
                                    }
                                }
                                .disabled(store.isLoading)
                                .onAppear {
                                    if movie.id == store.movies.last?.id {
                                        if store.canLoadMoreCatalog {
                                            store.loadMoreCatalog()
                                        } else if store.canLoadMoreMovieBrowse {
                                            store.loadMoreMovieBrowseIfNeeded()
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.top, 6)
                    } else {
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)
                            ],
                            spacing: 14
                        ) {
                            ForEach(store.televisionShows) { show in
                                VStack(alignment: .leading, spacing: 6) {
                                    Button {
                                        store.selectTV(show)
                                    } label: {
                                        TVCardView(store: store, show: show)
                                    }
                                    .buttonStyle(.plain)
                                    if store.tvBrowseSection == .airingToday {
                                        HStack(spacing: 10) {
                                            Label(
                                                store.todayAirDateLabel,
                                                systemImage: "calendar"
                                            )
                                            .font(.caption2.bold())
                                            .foregroundStyle(.indigo)
                                        }
                                        .font(.caption)
                                        .padding(.horizontal, 2)
                                    }
                                }
                                .disabled(store.isLoading)
                                .onAppear {
                                    if show.id == store.televisionShows.last?.id {
                                        if store.canLoadMoreTVCatalog {
                                            store.loadMoreTVCatalog()
                                        } else if store.canLoadMoreTVBrowse {
                                            store.loadMoreTVBrowseIfNeeded()
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.top, 6)
                    }

                    if store.isLoadingMoreCatalog ||
                        store.isLoadingMoreTVCatalog ||
                        store.isLoadingMoreBrowse {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("正在自动加载更多…")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                }
                .padding(.horizontal)
            }

            Divider()
            HStack {
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("退出", systemImage: "power")
                }
                .buttonStyle(.plain)
                .help("退出 CineBar")
                Spacer()
                ZStack {
                    ResizeTriangle()
                        .fill(.secondary.opacity(0.55))
                        .padding(3)
                    VerticalResizeHandle()
                }
                .frame(width: 24, height: 24)
                .help("拖动这里可上下拉伸")
            }
            .font(.caption)
            .padding(.horizontal)
            .frame(height: 36)
        }
    }
}

final class CineBarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

enum PanelPlacement {
    static func frame(
        anchorX: CGFloat,
        currentFrame: NSRect,
        visibleFrame: NSRect,
        minHeight: CGFloat
    ) -> NSRect {
        let width: CGFloat = 520
        let maximumHeight = max(minHeight, visibleFrame.height - 16)
        let height = min(
            max(currentFrame.height, minHeight),
            maximumHeight
        )
        let proposedX = anchorX - width / 2
        let maximumX = visibleFrame.maxX - width
        let x = min(max(proposedX, visibleFrame.minX), maximumX)
        return NSRect(
            x: x,
            y: max(visibleFrame.maxY - height, visibleFrame.minY),
            width: width,
            height: height
        )
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate,
    UNUserNotificationCenterDelegate {
    private let store = MovieStore()
    private let localLibraryStore = LocalLibraryStore()
    private lazy var updaterService = UpdaterService.shared
    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var settingsWindow: NSWindow?
    private var autoHideTimer: Timer?
    private var activityMonitor: Any?
    private var sparkleWindowObserver: NSObjectProtocol?
    private var isMediaPlaybackActive = false
    private var updateBadgeView: NSView?
    private var updateBadgeCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = updaterService
        NSApplication.shared.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self
        let telemetryLanguage: String = {
            switch store.appLanguage {
            case .zhCN: return "zh-Hans"
            case .zhHK, .zhTW: return "zh-Hant"
            case .enUS: return "en"
            case .jaJP: return "ja"
            case .koKR: return "ko"
            }
        }()
        Task {
            await CineBarTelemetryClient().reportIfNeeded(language: telemetryLanguage)
        }

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image: NSImage?
            if let iconURL = Bundle.main.url(
                forResource: "MenuBarIcon-template",
                withExtension: "png"
            ) {
                image = NSImage(contentsOf: iconURL)
            } else {
                image = NSImage(
                    systemSymbolName: "play.rectangle.fill",
                    accessibilityDescription: "CineBar"
                )
            }
            image?.size = NSSize(width: 18, height: 18)
            image?.isTemplate = true
            button.image = image
            button.toolTip = "CineBar · 找到下一部好片"
            button.target = self
            button.action = #selector(menuBarClicked)
        }
        self.statusItem = statusItem

        updateBadgeCancellable = updaterService.$hasUpdateAvailable
            .receive(on: RunLoop.main)
            .sink { [weak self] hasUpdate in
                self?.setUpdateBadge(visible: hasUpdate)
            }
        updaterService.startSilentUpdateChecks()

        // 磁力库启动增量：只抓全部分类最新一页新增内容。
        Task {
            await Hao6vMagnetResolver.refreshLatest()
        }

        let panel = CineBarPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 720),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.minSize = NSSize(width: 520, height: 560)
        panel.maxSize = NSSize(width: 520, height: 10_000)
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = store.isPanelMovable
        panel.acceptsMouseMovedEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.setFrameAutosaveName("CineBarMainPanel")
        var restoredFrame = panel.frame
        restoredFrame.size.width = 520
        panel.setFrame(restoredFrame, display: false)
        let hostingView = NSHostingView(
            rootView: ContentView(
                store: store,
                localLibraryStore: localLibraryStore
            )
        )
        let container = liquidGlassContainer(for: hostingView)
        container.wantsLayer = true
        container.layer?.cornerRadius = 18
        container.layer?.masksToBounds = true
        panel.contentView = container
        self.panel = panel

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appearanceDidChange(_:)),
            name: .cineBarAppearanceDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(autoHideDidChange(_:)),
            name: .cineBarAutoHideDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelMovementDidChange(_:)),
            name: .cineBarPanelMovementDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(mediaPlaybackDidChange(_:)),
            name: .cineBarMediaPlaybackDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openSettingsRequested(_:)),
            name: .cineBarOpenSettings,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showMainPanelRequested(_:)),
            name: .cineBarShowMainPanel,
            object: nil
        )
        activityMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel]
        ) { [weak self] event in
            if event.window === self?.panel, self?.panel?.isVisible == true {
                self?.scheduleAutoHide()
            }
            return event
        }
        // Sparkle 更新窗口是普通层级窗口，会被 .popUpMenu 的设置窗口压住；
        // 一旦出现这类窗口成为 key（例如"软件更新"面板），提到设置窗之上。
        sparkleWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { note in
            let settings = self.settingsWindow
            let panel = self.panel
            guard let window = note.object as? NSWindow else { return }
            guard window !== settings, window !== panel,
                  !(window is NSPanel),
                  window.level.rawValue < NSWindow.Level.popUpMenu.rawValue
            else { return }
            window.level = .popUpMenu
            window.orderFrontRegardless()
        }
        applyAppearance(
            rawValue: UserDefaults.standard.string(forKey: "appearanceMode") ?? ""
        )
    }

    private func liquidGlassContainer(for contentView: NSView) -> NSView {
        guard #available(macOS 26.0, *),
              let glassType = NSClassFromString("NSGlassEffectView") as? NSView.Type
        else {
            return contentView
        }

        let glassView = glassType.init(frame: .zero)
        let contentSelector = NSSelectorFromString("setContentView:")
        guard glassView.responds(to: contentSelector) else {
            return contentView
        }

        glassView.setValue(contentView, forKey: "contentView")
        if glassView.responds(to: NSSelectorFromString("setCornerRadius:")) {
            glassView.setValue(18.0, forKey: "cornerRadius")
        }
        return glassView
    }

    @objc private func appearanceDidChange(_ notification: Notification) {
        applyAppearance(rawValue: notification.object as? String ?? "")
    }

    private func applyAppearance(rawValue: String) {
        switch AppearanceMode(rawValue: rawValue) ?? .system {
        case .system:
            NSApplication.shared.appearance = nil
        case .light:
            NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        }
        panel?.appearance = nil
        settingsWindow?.appearance = nil
        panel?.contentView?.appearance = nil
        settingsWindow?.contentView?.appearance = nil
        for window in [panel, settingsWindow].compactMap({ $0 }) {
            window.contentView?.needsLayout = true
            window.contentView?.needsDisplay = true
            window.displayIfNeeded()
        }
    }

    @objc private func panelMovementDidChange(_ notification: Notification) {
        panel?.isMovableByWindowBackground =
            notification.object as? Bool ?? store.isPanelMovable
    }

    @objc private func openSettingsRequested(_ notification: Notification) {
        let window: NSWindow
        if let settingsWindow {
            window = settingsWindow
        } else {
            let created = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            created.title = "CineBar 设置"
            created.minSize = NSSize(width: 720, height: 520)
            created.isReleasedWhenClosed = false
            created.level = .popUpMenu
            created.setFrameAutosaveName("CineBarSettingsWindow")
            created.contentView = NSHostingView(
                rootView: SettingsRootView(
                    store: store,
                    updaterService: updaterService,
                    localLibraryStore: localLibraryStore
                )
            )
            settingsWindow = created
            window = created
            applyAppearance(
                rawValue: UserDefaults.standard.string(
                    forKey: "appearanceMode"
                ) ?? ""
            )
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc private func showMainPanelRequested(_ notification: Notification) {
        guard let panel else { return }
        positionPanelOnActiveScreen(panel)
        panel.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        scheduleAutoHide()
    }

    @objc private func autoHideDidChange(_ notification: Notification) {
        scheduleAutoHide()
    }

    @objc private func mediaPlaybackDidChange(_ notification: Notification) {
        isMediaPlaybackActive = notification.object as? Bool ?? false
        if isMediaPlaybackActive {
            autoHideTimer?.invalidate()
        } else {
            scheduleAutoHide()
        }
    }

    /// 菜单栏图标右上角蓝色圆点：有可用更新时显示，点击可跳转检查。
    private func setUpdateBadge(visible: Bool) {
        guard let button = statusItem?.button else { return }
        button.toolTip = visible
            ? "CineBar · 有新版本，点击图标进行更新"
            : "CineBar · 找到下一部好片"
        if visible {
            guard updateBadgeView == nil else { return }
            let badge = NSView(frame: NSRect(x: 0, y: 0, width: 6, height: 6))
            badge.wantsLayer = true
            badge.layer?.backgroundColor = NSColor.systemBlue.cgColor
            badge.layer?.cornerRadius = 3
            badge.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(badge)
            NSLayoutConstraint.activate([
                badge.topAnchor.constraint(
                    equalTo: button.topAnchor,
                    constant: 2
                ),
                badge.trailingAnchor.constraint(
                    equalTo: button.trailingAnchor,
                    constant: -2
                ),
                badge.widthAnchor.constraint(equalToConstant: 6),
                badge.heightAnchor.constraint(equalToConstant: 6)
            ])
            updateBadgeView = badge
        } else {
            updateBadgeView?.removeFromSuperview()
            updateBadgeView = nil
        }
    }

    @objc private func menuBarClicked() {
        togglePanel()
    }

    @objc private func togglePanel() {
        guard let panel else { return }
        if panel.isVisible {
            autoHideTimer?.invalidate()
            NotificationCenter.default.post(
                name: .cineBarPanelWillHide,
                object: nil
            )
            panel.orderOut(nil)
            return
        }

        positionPanelOnActiveScreen(panel)
        panel.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        scheduleAutoHide()
    }

    private func positionPanelOnActiveScreen(_ panel: NSPanel) {
        let pointer = NSEvent.mouseLocation
        let statusAnchor: (screen: NSScreen, x: CGFloat)? = {
            guard let button = statusItem?.button,
                  let window = button.window,
                  let screen = window.screen
            else { return nil }
            let windowRect = button.convert(button.bounds, to: nil)
            let screenRect = window.convertToScreen(windowRect)
            return (screen, screenRect.midX)
        }()
        let pointerScreen = NSScreen.screens.first {
            NSMouseInRect(pointer, $0.frame, false)
        }
        guard let targetScreen = statusAnchor?.screen ??
                pointerScreen ??
                NSScreen.main
        else { return }

        let visibleFrame = targetScreen.visibleFrame
        let maximumHeight = max(panel.minSize.height, visibleFrame.height - 16)
        panel.maxSize = NSSize(width: 520, height: maximumHeight)
        let frame = PanelPlacement.frame(
            anchorX: statusAnchor?.x ?? pointer.x,
            currentFrame: panel.frame,
            visibleFrame: visibleFrame,
            minHeight: panel.minSize.height
        )
        panel.setFrame(frame, display: true)
    }

    func windowWillResize(
        _ sender: NSWindow,
        to frameSize: NSSize
    ) -> NSSize {
        let visibleHeight = sender.screen?.visibleFrame.height ?? frameSize.height
        let maximumHeight = max(sender.minSize.height, visibleHeight - 16)
        return NSSize(
            width: 520,
            height: min(max(frameSize.height, sender.minSize.height), maximumHeight)
        )
    }

    private func scheduleAutoHide() {
        autoHideTimer?.invalidate()
        guard panel?.isVisible == true,
              !isMediaPlaybackActive
        else { return }
        let seconds = UserDefaults.standard.object(forKey: "autoHideInterval") as? Int ?? 30
        guard seconds > 0 else { return }
        autoHideTimer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(seconds),
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                NotificationCenter.default.post(
                    name: .cineBarPanelWillHide,
                    object: nil
                )
                self?.panel?.orderOut(nil)
            }
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        autoHideTimer?.invalidate()
        NotificationCenter.default.post(
            name: .cineBarPanelWillHide,
            object: nil
        )
        sender.orderOut(nil)
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (
            UNNotificationPresentationOptions
        ) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

#if !CINEBAR_TEST
@main
@MainActor
struct CineBarMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
        withExtendedLifetime(delegate) {}
    }
}
#endif
