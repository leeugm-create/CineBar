import AppKit
import Combine
import Foundation

#if CINEBAR_TEST
@MainActor
final class UpdaterService: ObservableObject {
    static let shared = UpdaterService()

    var automaticallyChecksForUpdates = true
    @Published var canCheckForUpdates = true

    func checkForUpdates() {}
}

private actor RecordingServiceLoader: ServiceDataLoading {
    enum Result {
        case failure(URLError)
        case response(statusCode: Int, body: Data)
    }

    private var results: [Result]
    private(set) var requestedURLs: [URL] = []

    init(results: [Result]) {
        self.results = results
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requestedURLs.append(request.url!)
        let result = results.removeFirst()
        switch result {
        case .failure(let error):
            throw error
        case .response(let statusCode, let body):
            return (
                body,
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: statusCode,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["content-type": "application/json"]
                )!
            )
        }
    }
}

@main
struct CineBarRegressionBehaviorTests {
    @MainActor
    static func main() async {
        precondition(
            UpdatePolicy.feedURL == "https://cinebar.cc/appcast.xml"
        )
        precondition(
            UpdatePolicy.automaticChecksDefaultsKey
                == "SUEnableAutomaticChecks"
        )
        precondition(
            UpdatePolicy.automaticChecksMigrationValue(
                legacyValue: false,
                hasExistingSparkleValue: false
            ) == false
        )
        precondition(
            UpdatePolicy.automaticChecksMigrationValue(
                legacyValue: true,
                hasExistingSparkleValue: false
            ) == true
        )
        precondition(
            UpdatePolicy.automaticChecksMigrationValue(
                legacyValue: false,
                hasExistingSparkleValue: true
            ) == nil
        )

        let serviceEndpoints = ServiceEndpointSet(
            primary: "https://api.cinebar.cc/",
            backups: [
                "",
                "ftp://invalid",
                "https://api.cinebar.cc",
                "https://api-hk.cinebar.cc/",
            ]
        )
        precondition(
            serviceEndpoints.urls.map(\.absoluteString) == [
                "https://api.cinebar.cc",
                "https://api-hk.cinebar.cc",
            ]
        )
        precondition(ServiceRequestPolicy.attemptsPerEndpoint == 2)
        precondition(
            ServiceRequestPolicy.isRetryable(
                error: URLError(.secureConnectionFailed)
            )
        )
        precondition(
            ServiceRequestPolicy.isRetryable(
                error: URLError(.cannotFindHost)
            )
        )
        precondition(
            ServiceRequestPolicy.isRetryable(
                error: URLError(.timedOut)
            )
        )
        precondition(ServiceRequestPolicy.isRetryable(statusCode: 503))
        precondition(!ServiceRequestPolicy.isRetryable(statusCode: 404))

        let diagnostic = ServiceDiagnostic(
            service: "data",
            category: .tls,
            timestamp: Date(timeIntervalSince1970: 0),
            appVersion: "0.8.2 (16)",
            requestURL: URL(
                string:
                    "https://api.cinebar.cc/omdb?i=tt0133093&apikey=secret"
            )!
        )
        precondition(diagnostic.redactedText.contains("api.cinebar.cc"))
        precondition(!diagnostic.redactedText.contains("apikey"))
        precondition(!diagnostic.redactedText.contains("secret"))
        precondition(!diagnostic.redactedText.contains("tt0133093"))
        precondition(
            ServiceFailureCategory.classify(
                URLError(.secureConnectionFailed)
            ) == .tls
        )
        precondition(
            ServiceFailureCategory.classify(
                URLError(.cannotFindHost)
            ) == .dns
        )
        precondition(
            ServiceFailureCategory.classify(
                URLError(.timedOut)
            ) == .timeout
        )
        precondition(
            ServiceFailureCategory.classify(
                ServiceHTTPError.statusCode(503, Data())
            ) == .server
        )
        precondition(
            ServiceFailureCategory.classify(
                ServiceHTTPError.statusCode(404, Data())
            ) == .client
        )

        let retryLoader = RecordingServiceLoader(
            results: [
                .failure(URLError(.secureConnectionFailed)),
                .response(statusCode: 503, body: Data()),
                .response(statusCode: 200, body: Data("{}".utf8)),
            ]
        )
        let retryClient = ResilientHTTPClient(loader: retryLoader)
        let retryResult = try! await retryClient.data(
            endpointSet: serviceEndpoints
        ) { baseURL in
            URLRequest(url: baseURL.appendingPathComponent("health"))
        }
        precondition(retryResult.1.statusCode == 200)
        let retryURLs = await retryLoader.requestedURLs
        precondition(retryURLs.count == 3)
        precondition(retryURLs[0].host == "api.cinebar.cc")
        precondition(retryURLs[1].host == "api.cinebar.cc")
        precondition(retryURLs[2].host == "api-hk.cinebar.cc")

        let clientErrorLoader = RecordingServiceLoader(
            results: [
                .response(statusCode: 404, body: Data()),
                .response(statusCode: 200, body: Data("{}".utf8)),
            ]
        )
        let clientErrorClient = ResilientHTTPClient(
            loader: clientErrorLoader
        )
        var clientErrorThrown = false
        do {
            _ = try await clientErrorClient.data(
                endpointSet: serviceEndpoints
            ) { baseURL in
                URLRequest(url: baseURL.appendingPathComponent("health"))
            }
        } catch {
            clientErrorThrown = true
        }
        precondition(clientErrorThrown)
        let clientErrorURLs = await clientErrorLoader.requestedURLs
        precondition(clientErrorURLs.count == 1)

        let cacheSuite = "CineBarBrowseCacheTests.\(UUID().uuidString)"
        let cacheDefaults = UserDefaults(suiteName: cacheSuite)!
        cacheDefaults.removePersistentDomain(forName: cacheSuite)
        let browseCache = LastSuccessfulBrowseCache(
            defaults: cacheDefaults
        )
        browseCache.saveMovies(Movie.demo)
        precondition(browseCache.loadMovies() == Movie.demo)
        browseCache.saveTelevision([TVShow.demo])
        precondition(browseCache.loadTelevision() == [TVShow.demo])
        cacheDefaults.set(
            Data("invalid".utf8),
            forKey: "lastSuccessfulMovies"
        )
        precondition(browseCache.loadMovies() == nil)
        precondition(
            cacheDefaults.data(forKey: "lastSuccessfulMovies") == nil
        )
        cacheDefaults.removePersistentDomain(forName: cacheSuite)

        precondition(
            ServiceErrorPresentation.message(
                language: .zhCN,
                hasCachedContent: true
            ) == "网络不稳定，正在显示上次更新内容"
        )
        precondition(
            ServiceErrorPresentation.message(
                language: .enUS,
                hasCachedContent: false
            ).contains("temporarily unavailable")
        )

        precondition(
            DataProxyConfiguration.normalizedBaseURL(
                "https://api.cinebar.cc/"
            ) == "https://api.cinebar.cc"
        )
        precondition(
            DataProxyConfiguration.normalizedBaseURL("ftp://invalid") == nil
        )

        let proxiedOMDbURL = OMDbEndpoint.url(
            proxyBaseURL: "https://api.cinebar.cc",
            apiKey: "",
            imdbID: "tt0133093"
        )
        precondition(
            proxiedOMDbURL?.absoluteString ==
                "https://api.cinebar.cc/omdb?i=tt0133093"
        )
        precondition(
            !(proxiedOMDbURL?.absoluteString.contains("apikey") ?? true)
        )
        precondition(
            OMDbEndpoint.url(
                proxyBaseURL: nil,
                apiKey: "",
                imdbID: "tt0133093"
            ) == nil
        )
        let legacyOMDbURL = OMDbEndpoint.url(
            proxyBaseURL: nil,
            apiKey: "developer-key",
            imdbID: "tt0133093"
        )
        precondition(
            legacyOMDbURL?.host == "www.omdbapi.com"
        )
        precondition(
            legacyOMDbURL?.query?.contains("apikey=developer-key") == true
        )
        precondition(
            OMDbEndpoint.url(
                proxyBaseURL: "https://api.cinebar.cc",
                apiKey: "",
                imdbID: "603"
            ) == nil
        )

        let builtInSettings = DataSettingsPresentation(
            proxyBaseURL: "https://api.cinebar.cc"
        )
        precondition(builtInSettings.usesBuiltInService)
        precondition(!builtInSettings.showsCredentialFields)
        let developerSettings = DataSettingsPresentation(proxyBaseURL: "")
        precondition(!developerSettings.usesBuiltInService)
        precondition(developerSettings.showsCredentialFields)

        precondition(
            RatingPresentation.shouldShowEditor(
                myScore: nil,
                isLoading: false
            )
        )
        precondition(
            !RatingPresentation.shouldShowEditor(
                myScore: 8.5,
                isLoading: false
            )
        )
        precondition(
            !RatingPresentation.shouldShowEditor(
                myScore: nil,
                isLoading: true
            )
        )

        let identitySuite = "CineBarIdentityTests.\(UUID().uuidString)"
        let identityDefaults = UserDefaults(suiteName: identitySuite)!
        identityDefaults.removePersistentDomain(forName: identitySuite)
        let firstIdentity = CineBarDeviceIdentity.value(
            defaults: identityDefaults
        )
        let secondIdentity = CineBarDeviceIdentity.value(
            defaults: identityDefaults
        )
        precondition(firstIdentity == secondIdentity)
        precondition(UUID(uuidString: firstIdentity) != nil)
        precondition(
            identityDefaults.string(
                forKey: CineBarDeviceIdentity.defaultsKey
            ) == firstIdentity
        )
        identityDefaults.removePersistentDomain(forName: identitySuite)

        let ratedPresentation = ContentRatingPresentation(
            ContentRatingSummary(
                region: "US",
                original: "PG-13",
                cineBar: "13+"
            )
        )
        precondition(ratedPresentation.regionLabel == "US")
        precondition(ratedPresentation.officialValue == "PG-13")
        precondition(ratedPresentation.cineBarValue == "13+")

        let unratedPresentation = ContentRatingPresentation(nil)
        precondition(unratedPresentation.regionLabel == "地区分级")
        precondition(unratedPresentation.officialValue == "未分级")
        precondition(unratedPresentation.cineBarValue == "未分级")

        precondition(GlassBackgroundOpacity.normalized(nil) == 0.85)
        precondition(GlassBackgroundOpacity.normalized(0.2) == 0.5)
        precondition(GlassBackgroundOpacity.normalized(0.73) == 0.73)
        precondition(GlassBackgroundOpacity.normalized(1.4) == 1.0)

        let movieShareURL = BrandedShareLink.url(
            baseURL: "https://share.example",
            mediaType: .movie,
            mediaID: 603
        )
        precondition(
            movieShareURL?.absoluteString ==
                "https://share.example/m/603"
        )
        let televisionShareURL = BrandedShareLink.url(
            baseURL: "https://share.example/",
            mediaType: .tv,
            mediaID: 1399
        )
        precondition(
            televisionShareURL?.absoluteString ==
                "https://share.example/t/1399"
        )
        precondition(movieShareURL?.query == nil)
        precondition(televisionShareURL?.query == nil)

        precondition(
            UpcomingReleasePresentation.make(
                rawValue: "2026-07-31",
                language: .zhCN
            ) == .dated("2026年7月31日")
        )
        precondition(
            UpcomingReleasePresentation.make(
                rawValue: "2026-07-31",
                language: .zhTW
            ) == .dated("2026年7月31日")
        )
        precondition(
            UpcomingReleasePresentation.make(
                rawValue: "2026-07-31",
                language: .enUS
            ) == .dated("Jul 31, 2026")
        )
        precondition(
            UpcomingReleasePresentation.make(
                rawValue: nil,
                language: .zhCN
            ) == .undated
        )
        precondition(
            UpcomingReleasePresentation.make(
                rawValue: "2026",
                language: .zhCN
            ) == .undated
        )
        precondition(
            UpcomingReleasePresentation.make(
                rawValue: "not-a-date",
                language: .zhCN
            ) == .undated
        )
        precondition(
            UpcomingReleasePresentation.make(
                rawValue: "2026/07/31",
                language: .zhCN
            ) == .undated
        )
        precondition(
            UpcomingReleasePresentation.make(
                rawValue: "2026-7-031",
                language: .zhCN
            ) == .undated
        )
        precondition(
            MovieRowPresentation.upcomingRelease(
                section: .upcoming,
                rawValue: "2026-07-31",
                language: .zhCN
            ) == .dated("2026年7月31日")
        )
        precondition(
            MovieRowPresentation.upcomingRelease(
                section: .trending,
                rawValue: "2026-07-31",
                language: .zhCN
            ) == nil
        )

        let moviePayload = SharePayload(
            mediaType: .movie,
            title: "沙丘2",
            url: movieShareURL!
        )
        let movieShareItems = moviePayload.systemItems
        precondition(movieShareItems.count == 1)
        precondition(movieShareItems[0] is NSURL)
        precondition(!(movieShareItems[0] is NSString))
        precondition(
            (movieShareItems[0] as? NSURL)?.absoluteString ==
                "https://share.example/m/603"
        )

        let televisionPayload = SharePayload(
            mediaType: .tv,
            title: "幕府将军",
            url: televisionShareURL!
        )
        let televisionShareItems = televisionPayload.systemItems
        precondition(televisionShareItems.count == 1)
        precondition(
            (televisionShareItems[0] as? NSURL)?.absoluteString ==
                "https://share.example/t/1399"
        )

        let store = MovieStore()
        store.communityRating = CommunityRatingSummary(
            mediaType: "movie",
            mediaID: 603,
            averageScore: 8.2,
            total: 14,
            myScore: 8.5
        )
        let movieRatings = store.ratings(for: Movie.demo[0])
        precondition(movieRatings.last?.source == "我的评分")
        precondition(movieRatings.last?.value == "8.5/10")

        store.communityRating = CommunityRatingSummary(
            mediaType: "tv",
            mediaID: 1399,
            averageScore: 9.0,
            total: 21,
            myScore: 9.5
        )
        let televisionRatings = store.ratings(for: TVShow.demo)
        precondition(televisionRatings.last?.source == "我的评分")
        precondition(televisionRatings.last?.value == "9.5/10")

        let slider = RatingNSSlider()
        precondition(slider.minValue == 0)
        precondition(slider.maxValue == 10)
        precondition(slider.numberOfTickMarks == 21)
        precondition(slider.allowsTickMarkValuesOnly)
        precondition(!slider.mouseDownCanMoveWindow)

        let secondDisplay = NSRect(
            x: 1_920,
            y: 0,
            width: 2_560,
            height: 1_440
        )
        let secondDisplayPanel = PanelPlacement.frame(
            anchorX: 2_200,
            currentFrame: NSRect(x: 0, y: 0, width: 520, height: 720),
            visibleFrame: secondDisplay,
            minHeight: 560
        )
        precondition(secondDisplay.contains(secondDisplayPanel))
        precondition(secondDisplayPanel.origin.x == 1_940)

        let smallDisplay = NSRect(x: 0, y: 0, width: 1_440, height: 900)
        let clampedPanel = PanelPlacement.frame(
            anchorX: 720,
            currentFrame: NSRect(x: 0, y: 0, width: 520, height: 1_200),
            visibleFrame: smallDisplay,
            minHeight: 560
        )
        precondition(clampedPanel.height == 884)
        precondition(clampedPanel.origin.y == 16)
        precondition(clampedPanel.origin.x == 460)

        let parsed = LocalLibraryFilenameParser.parse(
            "Interstellar (2014) 2160p.mkv"
        )
        precondition(parsed.title == "Interstellar")
        precondition(parsed.year == "2014")
        precondition(parsed.fileExtension == "mkv")

        let emptyFilename = LocalLibraryFilenameParser.parse("")
        precondition(emptyFilename.title == "")
        precondition(emptyFilename.year == nil)
        precondition(emptyFilename.fileExtension == "")

        let uppercaseExtension = LocalLibraryFilenameParser.parse(
            "Arrival (2016).MKV"
        )
        precondition(uppercaseExtension.title == "Arrival")
        precondition(uppercaseExtension.year == "2016")
        precondition(uppercaseExtension.fileExtension == "mkv")

        let taggedFilename = LocalLibraryFilenameParser.parse(
            "Dune.Part.Two.2024.2160p.WEB-DL.H265.Atmos.CHS-ENG.mkv"
        )
        precondition(taggedFilename.title == "Dune Part Two")
        precondition(taggedFilename.year == "2024")

        let noYearFilename = LocalLibraryFilenameParser.parse(
            "The Grand Budapest Hotel 1080p BluRay x264.mp4"
        )
        precondition(noYearFilename.title == "The Grand Budapest Hotel")
        precondition(noYearFilename.year == nil)

        let chineseFilename = LocalLibraryFilenameParser.parse(
            "流浪地球2 (2023) 4K 中文字幕.mkv"
        )
        precondition(chineseFilename.title == "流浪地球2")
        precondition(chineseFilename.year == "2023")

        let duplicateFolderID = UUID(
            uuidString: "00000000-0000-0000-0000-000000000001"
        )!
        let duplicateKeyA = LocalLibraryEntryMerge.key(
            folderID: duplicateFolderID,
            relativePath: "Movies/A.mkv"
        )
        let duplicateKeyB = LocalLibraryEntryMerge.key(
            folderID: duplicateFolderID,
            relativePath: "Movies/A.mkv"
        )
        precondition(duplicateKeyA == duplicateKeyB)
        precondition(
            LocalLibraryEntryMerge.key(
                folderID: duplicateFolderID,
                relativePath: "Movies/../A.mkv"
            ) == LocalLibraryEntryMerge.key(
                folderID: duplicateFolderID,
                relativePath: "A.mkv"
            )
        )
        precondition(
            LocalLibraryEntryMerge.key(
                folderID: duplicateFolderID,
                relativePath: "A.mkv"
            ) != LocalLibraryEntryMerge.key(
                folderID: duplicateFolderID,
                relativePath: "a.mkv"
            )
        )
        precondition(
            LocalLibraryEntryMerge.key(
                folderID: duplicateFolderID,
                relativePath: "Movies\\A.mkv"
            ) == LocalLibraryEntryMerge.key(
                folderID: duplicateFolderID,
                relativePath: "Movies/A.mkv"
            )
        )

        let persistenceDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CineBarPersistenceTests-\(UUID().uuidString)")
        let persistenceURL = persistenceDirectory.appendingPathComponent(
            "LocalLibrary.json"
        )
        let persistence = LocalLibraryPersistence(fileURL: persistenceURL)
        let firstSnapshot = LocalLibrarySnapshot(schemaVersion: 1)
        let secondSnapshot = LocalLibrarySnapshot(schemaVersion: 2)
        try! persistence.save(firstSnapshot)
        try! persistence.save(secondSnapshot)
        try! Data("corrupt".utf8).write(to: persistenceURL)
        precondition(persistence.load() == firstSnapshot)
        try? FileManager.default.removeItem(at: persistenceDirectory)

        let libraryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CineBarLocalLibrary-\(UUID().uuidString)")
        let moviesDirectory = libraryDirectory.appendingPathComponent("Movies")
        let showsDirectory = libraryDirectory.appendingPathComponent("Shows")
        try! FileManager.default.createDirectory(
            at: moviesDirectory,
            withIntermediateDirectories: true
        )
        try! FileManager.default.createDirectory(
            at: showsDirectory,
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(
            atPath: moviesDirectory.appendingPathComponent("A.mkv").path,
            contents: Data()
        )
        FileManager.default.createFile(
            atPath: showsDirectory.appendingPathComponent("B.mp4").path,
            contents: Data()
        )

        let libraryRoot = LocalLibraryScanRoot(
            folderID: UUID(),
            url: libraryDirectory,
            displayName: "测试片库"
        )
        let scanner = LocalLibraryScanner()
        let firstScan = await scanner.scan(
            roots: [libraryRoot],
            existing: [],
            progress: { _ in }
        )
        precondition(Set(firstScan.entries.map(\.relativePath)) == [
            "Movies/A.mkv", "Shows/B.mp4"
        ])

        FileManager.default.createFile(
            atPath: moviesDirectory.appendingPathComponent("C.mov").path,
            contents: Data()
        )
        let secondScan = await scanner.scan(
            roots: [libraryRoot],
            existing: firstScan.entries,
            progress: { _ in }
        )
        let refreshedEntries = LocalLibraryRefreshMerger.merge(
            existing: firstScan.entries,
            scanned: secondScan,
            roots: [libraryRoot]
        )
        precondition(refreshedEntries.count == 3)
        precondition(Set(refreshedEntries.map(\.relativePath)).count == 3)
        let aEntry = refreshedEntries.first(where: {
            $0.relativePath == "Movies/A.mkv"
        })!
        let retainedEntry = LocalLibraryEntry(
            id: aEntry.id,
            folderID: aEntry.folderID,
            relativePath: aEntry.relativePath,
            signature: aEntry.signature,
            state: aEntry.state,
            matchState: .confirmed,
            metadata: LocalLibraryMetadata(
                id: 42,
                kind: .movie,
                title: "A",
                year: "2026",
                posterPath: nil,
                overview: "",
                voteAverage: 9
            ),
            isWatched: true,
            isInWatchlist: true,
            lastOpenedAt: Date(timeIntervalSince1970: 1)
        )
        let thirdScan = await scanner.scan(
            roots: [libraryRoot],
            existing: refreshedEntries,
            progress: { _ in }
        )
        let thirdRefresh = LocalLibraryRefreshMerger.merge(
            existing: refreshedEntries.map {
                $0.id == retainedEntry.id ? retainedEntry : $0
            },
            scanned: thirdScan,
            roots: [libraryRoot]
        )
        precondition(thirdRefresh.count == 3)
        let refreshedRetainedEntry = thirdRefresh.first {
            $0.id == retainedEntry.id
        }
        precondition(refreshedRetainedEntry?.metadata?.id == 42)
        precondition(refreshedRetainedEntry?.isWatched == true)
        precondition(refreshedRetainedEntry?.isInWatchlist == true)
        precondition(
            refreshedRetainedEntry?.lastOpenedAt == retainedEntry.lastOpenedAt
        )

        try! FileManager.default.removeItem(
            at: showsDirectory.appendingPathComponent("B.mp4")
        )
        let missingScan = await scanner.scan(
            roots: [libraryRoot],
            existing: thirdRefresh,
            progress: { _ in }
        )
        let missingRefresh = LocalLibraryRefreshMerger.merge(
            existing: thirdRefresh,
            scanned: missingScan,
            roots: [libraryRoot]
        )
        precondition(missingRefresh.first(where: {
            $0.relativePath == "Shows/B.mp4"
        })?.state == .missing)
        let cancelledRefresh = LocalLibraryRefreshMerger.merge(
            existing: thirdRefresh,
            scanned: LocalLibraryScanResult(
                entries: [],
                availableFolderIDs: [libraryRoot.folderID],
                unavailableFolderIDs: [],
                wasCancelled: true
            ),
            roots: [libraryRoot]
        )
        precondition(cancelledRefresh.first(where: {
            $0.relativePath == "Movies/A.mkv"
        })?.state == .available)

        let unavailableRoot = LocalLibraryScanRoot(
            folderID: UUID(),
            url: libraryDirectory.appendingPathComponent("not-mounted"),
            displayName: "外置硬盘"
        )
        let unavailableEntry = LocalLibraryEntry(
            id: UUID(),
            folderID: unavailableRoot.folderID,
            relativePath: "Archive/D.m2ts",
            signature: LocalLibraryFileSignature(
                fileName: "D.m2ts",
                fileExtension: "m2ts",
                byteCount: 0,
                modificationDate: nil,
                resourceIdentifier: nil
            ),
            state: .available,
            matchState: .unmatched,
            metadata: nil,
            isWatched: false,
            isInWatchlist: false,
            lastOpenedAt: nil
        )
        let unavailableScan = await scanner.scan(
            roots: [unavailableRoot],
            existing: [unavailableEntry],
            progress: { _ in }
        )
        precondition(
            LocalLibraryRefreshMerger.merge(
                existing: [unavailableEntry],
                scanned: unavailableScan,
                roots: [unavailableRoot]
            ).first?.state == .volumeUnavailable
        )

        let bookmark = try! LocalLibraryFolderBookmark.make(
            from: libraryDirectory
        )
        let resolvedFolder = try! LocalLibraryFolderBookmark.resolve(
            bookmark.bookmarkData
        )
        precondition(
            resolvedFolder.url.standardizedFileURL ==
                libraryDirectory.standardizedFileURL
        )
        resolvedFolder.stopAccessing()

        let backgroundScan = await Task.detached {
            await LocalLibraryScanner().scan(
                roots: [libraryRoot],
                existing: [],
                progress: { _ in }
            )
        }.value
        precondition(backgroundScan.entries.count == 2)
        try? FileManager.default.removeItem(at: libraryDirectory)
    }
}
#endif
