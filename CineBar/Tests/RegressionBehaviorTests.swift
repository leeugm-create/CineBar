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

private actor TelemetryRequestRecorder {
    private(set) var requests: [URLRequest] = []

    func record(_ request: URLRequest) {
        requests.append(request)
    }

    func count() -> Int {
        requests.count
    }

    func first() -> URLRequest? {
        requests.first
    }
}

@main
struct CineBarRegressionBehaviorTests {
    @MainActor
    static func main() async {
        precondition(MainBrowseSection.allCases.contains(.localLibrary))
        for language in AppLanguage.allCases {
            precondition(
                !MainBrowseSection.localLibrary.title(language: language).isEmpty
            )
        }
        let localLibraryNavigationStore = MovieStore()
        localLibraryNavigationStore.setMainBrowseSection(.localLibrary)
        precondition(localLibraryNavigationStore.isShowingLocalLibrary)
        precondition(
            localLibraryNavigationStore.mainBrowseSection == .localLibrary
        )
        precondition(localLibraryNavigationStore.searchText.isEmpty)
        precondition(!localLibraryNavigationStore.showCatalog)
        precondition(!localLibraryNavigationStore.showTVCatalog)
        precondition(
            LocalLibraryEmptyState.library(language: .enUS).systemImage ==
                "externaldrive.badge.plus"
        )
        precondition(
            LocalLibraryEmptyState.match(language: .enUS).systemImage == "magnifyingglass"
        )

        let slowEntryID = UUID()
        let fastEntryID = UUID()
        var matchSearchState = LocalLibraryMatchSearchState()
        precondition(!matchSearchState.hasSearched)
        let slowRequest = matchSearchState.begin(entryID: slowEntryID)
        let fastRequest = matchSearchState.begin(entryID: fastEntryID)
        precondition(slowRequest.entryID == slowEntryID)
        precondition(fastRequest.entryID == fastEntryID)
        precondition(
            matchSearchState.finish(
                request: fastRequest,
                receivedResults: true
            )
        )
        precondition(!matchSearchState.isSearching)
        precondition(matchSearchState.hasSearched)
        precondition(
            !matchSearchState.finish(
                request: slowRequest,
                receivedResults: true
            )
        )
        precondition(matchSearchState.hasSearched)
        matchSearchState.reset()
        precondition(!matchSearchState.isSearching)
        precondition(!matchSearchState.hasSearched)

        var closedMatchSearchState = LocalLibraryMatchSearchState()
        let closedRequest = closedMatchSearchState.begin(entryID: slowEntryID)
        closedMatchSearchState.cancel(entryID: slowEntryID)
        precondition(!closedMatchSearchState.isSearching)
        precondition(
            !closedMatchSearchState.finish(
                request: closedRequest,
                receivedResults: true
            )
        )

        var confirmedMatchSearchState = LocalLibraryMatchSearchState()
        let confirmedRequest = confirmedMatchSearchState.begin(entryID: slowEntryID)
        confirmedMatchSearchState.confirm(entryID: slowEntryID)
        precondition(!confirmedMatchSearchState.isSearching)
        precondition(
            !confirmedMatchSearchState.finish(
                request: confirmedRequest,
                receivedResults: true
            )
        )
        precondition(
            LocalLibraryMatchSearchState.isCancellation(CancellationError())
        )
        precondition(
            LocalLibraryMatchSearchState.isCancellation(URLError(.cancelled))
        )
        precondition(
            LocalLibraryMatchSearchState.isCancellation(
                NSError(
                    domain: NSURLErrorDomain,
                    code: NSURLErrorCancelled
                )
            )
        )
        precondition(
            !LocalLibraryMatchSearchState.isCancellation(URLError(.timedOut))
        )

        let automaticMatchSearchState = LocalLibraryMatchSearchState(
            initialHasSearched: true
        )
        precondition(automaticMatchSearchState.hasSearched)
        precondition(
            LocalLibraryGenreLocalization.title(id: 12, language: .zhCN) == "冒险"
        )
        precondition(
            LocalLibraryGenreLocalization.title(id: 12, language: .zhHK) == "冒險"
        )
        precondition(
            LocalLibraryGenreLocalization.title(id: 12, language: .zhTW) == "冒險"
        )
        precondition(
            LocalLibraryGenreLocalization.title(id: 12, language: .enUS) == "Adventure"
        )
        precondition(
            LocalLibraryGenreLocalization.title(id: 12, language: .jaJP) == "アドベンチャー"
        )
        precondition(
            LocalLibraryGenreLocalization.title(id: 12, language: .koKR) == "모험"
        )
        precondition(
            LocalLibraryGenreLocalization.title(id: 10765, language: .zhHK) ==
                "科幻與奇幻"
        )
        precondition(
            LocalLibraryGenreLocalization.title(id: 10765, language: .zhTW) ==
                "科幻與奇幻"
        )
        precondition(
            LocalLibraryGenreLocalization.title(id: 10770, language: .zhHK) ==
                "電視電影"
        )
        precondition(
            LocalLibraryGenreLocalization.title(id: 10770, language: .zhTW) ==
                "電視電影"
        )

        let personalVideo = LocalLibraryFilenameParser.parse(
            "IMG_20260803_142233.mov"
        )
        precondition(personalVideo.category == .other)
        precondition(!personalVideo.isTrustedTitle)

        let movieFilename = LocalLibraryFilenameParser.parse(
            "Interstellar.2014.2160p.mkv"
        )
        precondition(movieFilename.category == .movie)
        precondition(movieFilename.isTrustedTitle)

        let televisionFilename = LocalLibraryFilenameParser.parse(
            "The Bear S02E03.mkv"
        )
        precondition(televisionFilename.category == .television)
        precondition(televisionFilename.isTrustedTitle)

        let unnamedFilename = LocalLibraryFilenameParser.parse(
            "未命名.mov"
        )
        precondition(unnamedFilename.category == .other)
        precondition(!unnamedFilename.isTrustedTitle)

        let unnamedCopy = LocalLibraryFilenameParser.parse(
            "未命名 拷贝.mov"
        )
        precondition(unnamedCopy.category == .other)
        precondition(!unnamedCopy.isTrustedTitle)

        let untitledFilename = LocalLibraryFilenameParser.parse(
            "Untitled 3.mp4"
        )
        precondition(untitledFilename.category == .other)
        precondition(!untitledFilename.isTrustedTitle)

        let newFolderFilename = LocalLibraryFilenameParser.parse(
            "新建文件夹.mp4"
        )
        precondition(newFolderFilename.category == .other)
        precondition(!newFolderFilename.isTrustedTitle)

        // 方案C：多维置信度分类器 —— 真实误判样本应改判 other
        precondition(
            LocalLibraryClassifier.classify(fromFilename: "20220927_4ee819e797368e1c_379104934696_mp4_264_hd_taobao.mp4") == .other
        )
        precondition(
            LocalLibraryClassifier.classify(fromFilename: "20240629_247c474badbdfcc4_469876909661_137154554696673_published_mp4_264_hd_taobao.mp4") == .other
        )
        precondition(
            LocalLibraryClassifier.classify(fromFilename: "0bc35eaacaaaiiaiqgn35rsfb2odahuqaaia.f10002.mp4") == .other
        )
        precondition(
            LocalLibraryClassifier.classify(fromFilename: "kling_20260604_动作控制_让照片中的人物严格按_3844_0.mp4") == .other
        )
        precondition(
            LocalLibraryClassifier.classify(fromFilename: "kling_20260605_作品_这张照片很适合做成一_3769_0.mp4") == .other
        )
        precondition(
            LocalLibraryClassifier.classify(fromFilename: "2024_06_28_20_32_IMG_9285.MOV") == .other
        )
        precondition(
            LocalLibraryClassifier.classify(fromFilename: "dji_fly_20230527_115350_783_1685160038140_quickshot.MP4") == .other
        )
        precondition(
            LocalLibraryClassifier.classify(fromFilename: "ScreenRecording_07-17-2026 16-27-46_1.MP4") == .other
        )
        precondition(
            LocalLibraryClassifier.classify(fromFilename: "RPReplay_Final1682844639.MP4") == .other
        )
        precondition(
            LocalLibraryClassifier.classify(fromFilename: "一棵大树，太阳升起延时，光影变幻光明梦想希望未来春天清晨夕阳_爱给网_aigei_com.mp4") == .other
        )
        precondition(
            LocalLibraryClassifier.classify(fromFilename: "6月4日.mp4") == .other
        )
        precondition(
            LocalLibraryClassifier.classify(fromFilename: "鎏金沙.mov") == .other
        )
        precondition(
            LocalLibraryClassifier.classify(fromFilename: "video.mp4") == .other
        )
        // 真实影片仍应判定 movie
        precondition(
            LocalLibraryClassifier.classify(fromFilename: "Interstellar.2014.2160p.mkv") == .movie
        )
        precondition(
            LocalLibraryClassifier.classify(fromFilename: "Pirate.Radio.2009.1080p.BluRay.x264.DTS-FGT.mkv") == .movie
        )
        precondition(
            LocalLibraryClassifier.classify(fromFilename: "艾曼纽.1080p.BD中英双字[最新电影www.5266ys.com].mp4") == .movie
        )
        // 物理兜底：时长≥1小时归影片；无时长或不足1小时归 other
        precondition(
            LocalLibraryClassifier.classify(
                fileName: "some-ambiguous-name.mkv",
                physical: LocalLibraryPhysicalSignal(byteCount: 1_200_000_000, durationSeconds: 5400)
            ) == .movie
        )
        precondition(
            LocalLibraryClassifier.classify(
                fileName: "some-ambiguous-name.mkv",
                physical: LocalLibraryPhysicalSignal(byteCount: 60_000_000, durationSeconds: 1800)
            ) == .other
        )
        precondition(
            LocalLibraryClassifier.classify(
                fileName: "some-ambiguous-name.mkv",
                physical: LocalLibraryPhysicalSignal(byteCount: 1_200_000_000, durationSeconds: nil)
            ) == .other
        )

        let telemetryDefaultsName = "CineBarTelemetryRegressionTests-\(UUID().uuidString)"
        let telemetryDefaults = UserDefaults(suiteName: telemetryDefaultsName)!
        let fixedTelemetryDate = Date(timeIntervalSince1970: 1_754_214_400)
        let telemetryRecorder = TelemetryRequestRecorder()
        let telemetryClient = CineBarTelemetryClient(
            endpoint: URL(string: "https://telemetry.example.test/v1/telemetry/install")!,
            defaults: telemetryDefaults,
            now: { fixedTelemetryDate },
            send: { request in
                await telemetryRecorder.record(request)
            }
        )
        await telemetryClient.reportIfNeeded(
            appVersion: "0.8.3-test.10",
            build: 26,
            language: "zh-Hant-HK"
        )
        let firstTelemetryCount = await telemetryRecorder.count()
        precondition(firstTelemetryCount == 1)
        let telemetryRequest = await telemetryRecorder.first()!
        precondition(telemetryRequest.httpMethod == "POST")
        precondition(
            telemetryRequest.value(forHTTPHeaderField: "Content-Type") ==
                "application/json"
        )
        let telemetryPayload = try! JSONDecoder().decode(
            CineBarTelemetryPayload.self,
            from: telemetryRequest.httpBody!
        )
        precondition(UUID(uuidString: telemetryPayload.installID) != nil)
        precondition(telemetryPayload.language == "zh-Hant")
        precondition(telemetryPayload.platform == "macOS")
        precondition(telemetryPayload.build == 26)
        await telemetryClient.reportIfNeeded(
            appVersion: "0.8.3-test.10",
            build: 26,
            language: "zh-Hant-HK"
        )
        let sameDayTelemetryCount = await telemetryRecorder.count()
        precondition(sameDayTelemetryCount == 1)
        let nextDayClient = CineBarTelemetryClient(
            endpoint: URL(string: "https://telemetry.example.test/v1/telemetry/install")!,
            defaults: telemetryDefaults,
            now: { fixedTelemetryDate.addingTimeInterval(86_400) },
            send: { request in
                await telemetryRecorder.record(request)
            }
        )
        await nextDayClient.reportIfNeeded(
            appVersion: "0.8.3-test.10",
            build: 26,
            language: "zh-Hant-HK"
        )
        let nextDayTelemetryCount = await telemetryRecorder.count()
        precondition(nextDayTelemetryCount == 2)
        telemetryDefaults.removePersistentDomain(forName: telemetryDefaultsName)

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

        precondition(CertificationCardMetrics.minWidth < 128)
        precondition(CertificationCardMetrics.minHeight < 52)
        precondition(CertificationCardMetrics.width <= 130)
        precondition(CertificationCardMetrics.height <= 44)

        let calendarDetails = CalendarReleaseEventComposer.make(
            title: "奥德赛",
            dateText: "2026-08-14",
            region: "CN",
            language: .zhCN
        )
        precondition(calendarDetails?.title == "《奥德赛》上映")
        precondition(calendarDetails?.dateText == "2026-08-14")
        precondition(calendarDetails?.notes.contains("2026-08-14") == true)
        precondition(calendarDetails?.notes.contains("CN") == true)
        precondition(
            CalendarReleaseEventComposer.shouldOffer(
                dateText: "2026-08-14",
                today: "2026-08-14"
            )
        )
        precondition(
            !CalendarReleaseEventComposer.shouldOffer(
                dateText: "2026-08-14",
                today: "2026-08-15"
            )
        )
        precondition(
            CalendarReleaseEventComposer.make(
                title: "已上映影片",
                dateText: "2026-08-14",
                region: "GLOBAL",
                language: .zhCN,
                today: "2026-08-15"
            ) == nil
        )
        precondition(
            CalendarReleaseEventComposer.make(
                title: "无效日期",
                dateText: "2026-02-30",
                region: "CN",
                language: .zhCN
            ) == nil
        )

        let personImage = PersonImage(
            filePath: "/actor.jpg",
            width: 1_000,
            height: 1_500,
            voteAverage: 5
        )
        precondition(
            personImage.fullSizeURL?.absoluteString ==
                "https://image.tmdb.org/t/p/original/actor.jpg"
        )
        let movieStill = MovieStill(
            filePath: "/still.jpg",
            width: 1_920,
            height: 1_080,
            voteAverage: 5,
            voteCount: 10
        )
        precondition(
            movieStill.fullSizeURL?.absoluteString ==
                "https://image.tmdb.org/t/p/original/still.jpg"
        )
        precondition(
            PhotoLightboxNavigation.adjacentIndex(
                currentIndex: 1,
                offset: -1,
                count: 3
            ) == 0
        )
        precondition(
            PhotoLightboxNavigation.adjacentIndex(
                currentIndex: 1,
                offset: 1,
                count: 3
            ) == 2
        )
        precondition(
            PhotoDownloadFilename.suggestedName(
                for: URL(string: "https://image.tmdb.org/t/p/original/actor.jpg")!
            ) == "CineBar-actor.jpg"
        )
        precondition(
            PhotoDownloadFilename.suggestedName(
                for: URL(string: "https://image.tmdb.org/t/p/original/still")!
            ) == "CineBar-still.jpg"
        )
        precondition(
            PhotoLightboxNavigation.adjacentIndex(
                currentIndex: 0,
                offset: -1,
                count: 3
            ) == nil
        )
        precondition(
            PhotoLightboxNavigation.adjacentIndex(
                currentIndex: 2,
                offset: 1,
                count: 3
            ) == nil
        )

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
            ) == .dated("2026年7月31日（周五）")
        )
        precondition(
            UpcomingReleasePresentation.make(
                rawValue: "2026-07-31",
                language: .zhTW
            ) == .dated("2026年7月31日（週五）")
        )
        precondition(
            UpcomingReleasePresentation.make(
                rawValue: "2026-07-31",
                language: .enUS
            ) == .dated("Fri, Jul 31, 2026")
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
            ) == .dated("2026年7月31日（周五）")
        )
        precondition(
            MovieRowPresentation.upcomingRelease(
                section: .trending,
                rawValue: "2026-07-31",
                language: .zhCN
            ) == nil
        )

        let releaseEvents = [
            MovieReleaseEvent(
                type: 3,
                releaseDate: "2024-07-30T00:00:00.000Z",
                certification: nil,
                note: "首映"
            ),
            MovieReleaseEvent(
                type: 3,
                releaseDate: "2026-08-14T00:00:00.000Z",
                certification: nil,
                note: "中国大陆重映"
            )
        ]
        precondition(
            MovieReleaseDatePolicy.preferredDate(
                from: releaseEvents,
                today: "2026-08-02"
            ) == "2026-08-14"
        )
        precondition(
            MovieReleaseDatePolicy.preferredDate(
                from: releaseEvents,
                today: "2026-08-20"
            ) == "2026-08-14"
        )

        let earlierUpcomingMovie = Movie(
            id: 1,
            title: "Earlier",
            originalTitle: nil,
            overview: "",
            posterPath: nil,
            releaseDate: "2026-07-30",
            localizedReleaseDate: "2026-08-14",
            voteAverage: 7,
            voteCount: 1
        )
        let laterUpcomingMovie = Movie(
            id: 2,
            title: "Later",
            originalTitle: nil,
            overview: "",
            posterPath: nil,
            releaseDate: "2026-08-20",
            localizedReleaseDate: "2026-08-20",
            voteAverage: 7,
            voteCount: 1
        )
        precondition(
            UpcomingMovieSorting.sorted([
                laterUpcomingMovie,
                earlierUpcomingMovie
            ]).map(\.id) == [1, 2]
        )
        let undatedUpcomingMovie = Movie(
            id: 3,
            title: "Undated",
            originalTitle: nil,
            overview: "",
            posterPath: nil,
            releaseDate: "2026-07-01",
            localizedReleaseDate: nil,
            voteAverage: 10,
            voteCount: 1
        )
        precondition(
            UpcomingMovieSorting.sorted([
                undatedUpcomingMovie,
                laterUpcomingMovie
            ]).map(\.id) == [2, 3]
        )

        precondition(
            MainlandTrailerPlatform.bilibili.url(for: "奥德赛 预告")?.host
                == "search.bilibili.com"
        )
        precondition(
            MainlandTrailerPlatform.tencentVideo.url(for: "奥德赛 预告")?.host
                == "v.qq.com"
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

        let signatureDate = Date(timeIntervalSince1970: 12_345)
        let originalSignature = LocalLibraryFileSignature(
            fileName: "Film.mkv",
            fileExtension: "mkv",
            byteCount: 1_024,
            modificationDate: signatureDate,
            resourceIdentifier: "resource-a"
        )
        precondition(originalSignature.matchesForReattachment(
            LocalLibraryFileSignature(
                fileName: "Film.mkv",
                fileExtension: "MKV",
                byteCount: 1_024,
                modificationDate: signatureDate,
                resourceIdentifier: "resource-b"
            )
        ))
        precondition(originalSignature.matchesForReattachment(
            LocalLibraryFileSignature(
                fileName: "Renamed.mkv",
                fileExtension: "mkv",
                byteCount: 1_024,
                modificationDate: signatureDate,
                resourceIdentifier: "resource-a"
            )
        ))
        precondition(!originalSignature.matchesForReattachment(
            LocalLibraryFileSignature(
                fileName: "Different.mkv",
                fileExtension: "mkv",
                byteCount: 1_024,
                modificationDate: signatureDate,
                resourceIdentifier: nil
            )
        ))

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
        precondition(
            persistence.load().schemaVersion ==
                LocalLibrarySnapshot.currentSchemaVersion
        )

        let legacyMovieEntry = LocalLibraryEntry(
            id: UUID(),
            folderID: UUID(),
            relativePath: "Interstellar.2014.mkv",
            signature: LocalLibraryFileSignature(
                fileName: "Interstellar.2014.mkv",
                fileExtension: "mkv",
                byteCount: 0,
                modificationDate: nil,
                resourceIdentifier: nil
            ),
            state: .available,
            matchState: .confirmed,
            metadata: LocalLibraryMetadata(
                id: 157336,
                kind: .movie,
                title: "Interstellar",
                year: "2014",
                posterPath: nil,
                overview: "",
                voteAverage: 8.7,
                genreIDs: nil
            ),
            isWatched: true,
            isInWatchlist: true,
            lastOpenedAt: Date(timeIntervalSince1970: 1)
        )
        try! persistence.save(LocalLibrarySnapshot(
            schemaVersion: 1,
            entries: [legacyMovieEntry]
        ))
        let migratedSnapshot = persistence.load()
        precondition(migratedSnapshot.schemaVersion == 3)
        precondition(
            migratedSnapshot.entries.first?.contentCategory == .movie
        )
        precondition(migratedSnapshot.entries.first?.isWatched == true)
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

        let classificationDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CineBarLocalLibraryClassification-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(
            at: classificationDirectory,
            withIntermediateDirectories: true
        )
        let classificationFiles = [
            "Interstellar.2014.mkv",
            "Example.Show.S01E02.mp4",
            "IMG_20260803_142233.mov"
        ]
        for fileName in classificationFiles {
            FileManager.default.createFile(
                atPath: classificationDirectory.appendingPathComponent(fileName).path,
                contents: Data()
            )
        }
        let classificationRoot = LocalLibraryScanRoot(
            folderID: UUID(),
            url: classificationDirectory,
            displayName: "分类测试片库"
        )
        let classificationScan = await scanner.scan(
            roots: [classificationRoot],
            existing: [],
            progress: { _ in }
        )
        precondition(
            classificationScan.entries.first(where: {
                $0.signature.fileName == "Interstellar.2014.mkv"
            })?.contentCategory == .movie
        )
        precondition(
            classificationScan.entries.first(where: {
                $0.signature.fileName == "Example.Show.S01E02.mp4"
            })?.contentCategory == .television
        )
        precondition(
            classificationScan.entries.first(where: {
                $0.signature.fileName == "IMG_20260803_142233.mov"
            })?.contentCategory == .other
        )
        precondition(
            classificationScan.entries.first(where: {
                $0.signature.fileName == "Interstellar.2014.mkv"
            })?.matchState == .suggested
        )
        precondition(
            classificationScan.entries.first(where: {
                $0.signature.fileName == "IMG_20260803_142233.mov"
            })?.matchState == .unmatched
        )
        let classificationRefresh = LocalLibraryRefreshMerger.merge(
            existing: classificationScan.entries,
            scanned: classificationScan,
            roots: [classificationRoot]
        )
        precondition(
            classificationRefresh.first(where: {
                $0.signature.fileName == "Example.Show.S01E02.mp4"
            })?.contentCategory == .television
        )
        precondition(
            classificationRefresh.first(where: {
                $0.signature.fileName == "IMG_20260803_142233.mov"
            })?.contentCategory == .other
        )

        let categoryMovie = classificationScan.entries.first(where: {
            $0.signature.fileName == "Interstellar.2014.mkv"
        })!
        var categoryTelevision = classificationScan.entries.first(where: {
            $0.signature.fileName == "Example.Show.S01E02.mp4"
        })!
        categoryTelevision.isWatched = true
        categoryTelevision.matchState = .confirmed
        var categoryOther = classificationScan.entries.first(where: {
            $0.signature.fileName == "IMG_20260803_142233.mov"
        })!
        categoryOther.state = .volumeUnavailable

        precondition(LocalLibraryCategoryFilter.all.includes(categoryMovie))
        precondition(LocalLibraryCategoryFilter.movie.includes(categoryMovie))
        precondition(!LocalLibraryCategoryFilter.movie.includes(categoryTelevision))
        precondition(LocalLibraryCategoryFilter.television.includes(categoryTelevision))
        precondition(!LocalLibraryCategoryFilter.television.includes(categoryOther))
        precondition(LocalLibraryCategoryFilter.other.includes(categoryOther))
        precondition(!LocalLibraryCategoryFilter.other.includes(categoryMovie))
        precondition(categoryOther.metadata == nil)
        precondition(LocalLibraryCategoryFilter.all.includes(categoryOther))

        precondition(
            LocalLibraryCategoryFilter.movie.includes(categoryMovie) &&
                LocalLibraryStatusFilter.unmatched.includes(categoryMovie)
        )
        precondition(LocalLibraryStatusFilter.unwatched.includes(categoryMovie))
        precondition(!LocalLibraryStatusFilter.unmatched.includes(categoryTelevision))
        precondition(!LocalLibraryStatusFilter.unwatched.includes(categoryTelevision))
        precondition(LocalLibraryStatusFilter.unavailable.includes(categoryOther))
        try? FileManager.default.removeItem(at: classificationDirectory)

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

        var concurrentlyReattachedEntry = retainedEntry
        concurrentlyReattachedEntry.relativePath = "Movies/Renamed-A.mkv"
        let staleScannedEntry = retainedEntry
        let reattachedMerge = LocalLibraryRefreshMerger.merge(
            existing: [concurrentlyReattachedEntry],
            scanned: LocalLibraryScanResult(
                entries: [staleScannedEntry],
                availableFolderIDs: [libraryRoot.folderID],
                unavailableFolderIDs: [],
                wasCancelled: false
            ),
            roots: [libraryRoot]
        )
        precondition(reattachedMerge == [concurrentlyReattachedEntry])

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
            lastOpenedAt: nil,
            contentCategory: .movie
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

        let bookmarkedRoot = LocalLibraryScanRoot(
            folderID: UUID(),
            bookmarkData: bookmark.bookmarkData,
            displayName: "书签片库"
        )
        let bookmarkScan = await scanner.scan(
            roots: [bookmarkedRoot],
            existing: [],
            progress: { _ in }
        )
        precondition(bookmarkScan.entries.count == 2)

        let backgroundScan = await Task.detached {
            await LocalLibraryScanner().scan(
                roots: [libraryRoot],
                existing: [],
                progress: { _ in }
            )
        }.value
        precondition(backgroundScan.entries.count == 2)
        try? FileManager.default.removeItem(at: libraryDirectory)

        let cancellationDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CineBarCancellation-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(
            at: cancellationDirectory,
            withIntermediateDirectories: true
        )
        for index in 0..<10_000 {
            FileManager.default.createFile(
                atPath: cancellationDirectory
                    .appendingPathComponent("\(index).mkv").path,
                contents: Data()
            )
        }
        let cancellationRoot = LocalLibraryScanRoot(
            folderID: UUID(),
            url: cancellationDirectory,
            displayName: "取消测试"
        )
        let progressSignal = DispatchSemaphore(value: 0)
        let cancellationTask = Task.detached {
            await LocalLibraryScanner().scan(
                roots: [cancellationRoot],
                existing: [],
                progress: { _ in progressSignal.signal() }
            )
        }
        precondition(
            progressSignal.wait(timeout: .now() + 5) == .success
        )
        cancellationTask.cancel()
        let cancelledScan = await cancellationTask.value
        precondition(cancelledScan.wasCancelled)
        let cancellationExisting = LocalLibraryEntry(
            id: UUID(),
            folderID: cancellationRoot.folderID,
            relativePath: "not-visited.mkv",
            signature: LocalLibraryFileSignature(
                fileName: "not-visited.mkv",
                fileExtension: "mkv",
                byteCount: 0,
                modificationDate: nil,
                resourceIdentifier: nil
            ),
            state: .available,
            matchState: .unmatched,
            metadata: nil,
            isWatched: false,
            isInWatchlist: false,
            lastOpenedAt: nil,
            contentCategory: .television
        )
        precondition(
            LocalLibraryRefreshMerger.merge(
                existing: [cancellationExisting],
                scanned: cancelledScan,
                roots: [cancellationRoot]
            ).first?.state == .available
        )
        try? FileManager.default.removeItem(at: cancellationDirectory)

        let storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CineBarStore-\(UUID().uuidString)")
        let storeStateURL = storeDirectory.appendingPathComponent("Library.json")
        let storeRootURL = storeDirectory.appendingPathComponent("Library")
        try! FileManager.default.createDirectory(
            at: storeRootURL,
            withIntermediateDirectories: true
        )
        let originalURL = storeRootURL.appendingPathComponent("Original.mkv")
        FileManager.default.createFile(atPath: originalURL.path, contents: Data("movie".utf8))

        let firstStore = LocalLibraryStore(fileURL: storeStateURL)
        try! firstStore.addFolder(url: storeRootURL)
        let renewedFolderID = firstStore.folders[0].id
        try! firstStore.addFolder(url: storeRootURL)
        precondition(firstStore.folders.count == 1)
        precondition(firstStore.folders[0].id == renewedFolderID)
        var signatureReadWithinFolderScope = false
        try! LocalLibraryStore.withAuthorizedFolderScope(
            folders: firstStore.folders,
            containing: originalURL
        ) { _, resolvedFolder in
            precondition(
                resolvedFolder.url.standardizedFileURL ==
                    storeRootURL.standardizedFileURL
            )
            _ = try originalURL.resourceValues(forKeys: [.fileSizeKey])
            signatureReadWithinFolderScope = true
        }
        precondition(signatureReadWithinFolderScope)
        await firstStore.refresh()
        precondition(firstStore.entries.map(\.relativePath) == ["Original.mkv"])
        let storedEntryID = firstStore.entries[0].id
        let confirmedMetadata = LocalLibraryMetadata(
            id: 99,
            kind: .movie,
            title: "Persisted",
            year: "2026",
            posterPath: nil,
            overview: "",
            voteAverage: 8
        )
        firstStore.updateMetadata(entryID: storedEntryID, metadata: confirmedMetadata)
        precondition(firstStore.entries[0].contentCategory == .movie)
        firstStore.setWatched(entryID: storedEntryID, value: true)
        firstStore.toggleWatchlist(entryID: storedEntryID)
        firstStore.markOpened(entryID: storedEntryID)
        let openedAt = firstStore.entries[0].lastOpenedAt
        precondition(openedAt != nil)

        let mismatchedURL = storeRootURL.appendingPathComponent("Different.mkv")
        FileManager.default.createFile(
            atPath: mismatchedURL.path,
            contents: Data("different".utf8)
        )
        let entryBeforeRejectedReattach = firstStore.entries[0]
        do {
            try firstStore.reattach(entryID: storedEntryID, url: mismatchedURL)
            preconditionFailure("A different file must not be reattached.")
        } catch {}
        precondition(firstStore.entries[0] == entryBeforeRejectedReattach)
        try! FileManager.default.removeItem(at: mismatchedURL)

        let renamedURL = storeRootURL.appendingPathComponent("Renamed.mkv")
        try! FileManager.default.moveItem(at: originalURL, to: renamedURL)
        try! firstStore.reattach(entryID: storedEntryID, url: renamedURL)
        precondition(firstStore.entries[0].relativePath == "Renamed.mkv")
        precondition(firstStore.entries[0].metadata == confirmedMetadata)
        precondition(firstStore.entries[0].isWatched)
        precondition(firstStore.entries[0].isInWatchlist)
        precondition(firstStore.entries[0].lastOpenedAt == openedAt)

        let restoredStore = LocalLibraryStore(fileURL: storeStateURL)
        let restoredEntry = restoredStore.entries.first { $0.id == storedEntryID }
        precondition(restoredEntry?.relativePath == "Renamed.mkv")
        precondition(restoredEntry?.metadata == confirmedMetadata)
        precondition(restoredEntry?.isWatched == true)
        precondition(restoredEntry?.isInWatchlist == true)
        precondition(restoredEntry?.lastOpenedAt != nil)

        FileManager.default.createFile(
            atPath: storeRootURL.appendingPathComponent("Added.mp4").path,
            contents: Data()
        )
        async let firstRefresh: Void = restoredStore.refresh()
        async let overlappingRefresh: Void = restoredStore.refresh()
        _ = await (firstRefresh, overlappingRefresh)
        precondition(Set(restoredStore.entries.map(\.relativePath)) == [
            "Added.mp4", "Renamed.mkv"
        ])
        precondition(!restoredStore.isScanning)

        let staleStore = LocalLibraryStore(
            fileURL: storeDirectory.appendingPathComponent("StaleLibrary.json"),
            scanOperation: { roots, _, _ in
                LocalLibraryScanResult(
                    entries: [],
                    availableFolderIDs: Set(roots.map(\.folderID)),
                    unavailableFolderIDs: [],
                    staleFolderIDs: Set(roots.map(\.folderID)),
                    wasCancelled: false
                )
            }
        )
        try! staleStore.addFolder(url: storeRootURL)
        let staleFolderID = staleStore.folders[0].id
        await staleStore.refresh()
        precondition(staleStore.message == .folderAuthorizationStale)
        try! staleStore.addFolder(url: storeRootURL)
        precondition(staleStore.folders.count == 1)
        precondition(staleStore.folders[0].id == staleFolderID)

        let refreshGate = LocalLibraryRefreshGate()
        let concurrentStateURL = storeDirectory.appendingPathComponent(
            "ConcurrentLibrary.json"
        )
        let concurrentStore = LocalLibraryStore(
            fileURL: concurrentStateURL,
            scanOperation: { roots, existing, _ in
                await refreshGate.waitUntilReleased()
                return LocalLibraryScanResult(
                    entries: existing,
                    availableFolderIDs: Set(roots.map(\.folderID)),
                    unavailableFolderIDs: [],
                    wasCancelled: false
                )
            }
        )
        try! concurrentStore.addFolder(url: storeRootURL)
        var seededEntry = restoredStore.entries[0]
        seededEntry.folderID = concurrentStore.folders[0].id
        let seededSnapshot = LocalLibrarySnapshot(
            folders: concurrentStore.folders,
            entries: [seededEntry]
        )
        try! LocalLibraryPersistence(fileURL: concurrentStateURL).save(
            seededSnapshot
        )
        let mutatingStore = LocalLibraryStore(
            fileURL: concurrentStateURL,
            scanOperation: { roots, existing, _ in
                await refreshGate.waitUntilReleased()
                return LocalLibraryScanResult(
                    entries: existing,
                    availableFolderIDs: Set(roots.map(\.folderID)),
                    unavailableFolderIDs: [],
                    wasCancelled: false
                )
            }
        )
        let mutatingID = mutatingStore.entries[0].id
        mutatingStore.setWatched(entryID: mutatingID, value: false)
        if mutatingStore.entries[0].isInWatchlist {
            mutatingStore.toggleWatchlist(entryID: mutatingID)
        }
        async let concurrentRefresh: Void = mutatingStore.refresh()
        while !mutatingStore.isScanning { await Task.yield() }
        mutatingStore.setWatched(entryID: mutatingID, value: true)
        mutatingStore.toggleWatchlist(entryID: mutatingID)
        mutatingStore.markOpened(entryID: mutatingID)
        let concurrentOpenedAt = mutatingStore.entries[0].lastOpenedAt
        await refreshGate.release()
        await concurrentRefresh
        precondition(mutatingStore.entries[0].isWatched)
        precondition(mutatingStore.entries[0].isInWatchlist)
        precondition(mutatingStore.entries[0].lastOpenedAt == concurrentOpenedAt)
        try? FileManager.default.removeItem(at: storeDirectory)

        precondition(
            ExternalPlayerResolver.resolve(
                availableBundleIDs: ["org.videolan.vlc"]
            ) == [.vlc, .system]
        )
        precondition(
            ExternalPlayerResolver.resolve(
                availableBundleIDs: [
                    "com.colliderli.iina", "org.videolan.vlc"
                ]
            ) == [.iina, .vlc, .system]
        )
        precondition(
            ExternalPlayerResolver.resolve(availableBundleIDs: []) == [.system]
        )

        let playbackProbe = LocalLibraryPlaybackProbe()
        let launcher = ExternalPlayerLauncher(
            applicationURLForBundleID: { _ in nil },
            openWithApplication: { _, _ in
                playbackProbe.applicationOpenCount += 1
                return .success
            },
            openSystem: { url in
                playbackProbe.openedURLs.append(url)
                return .success
            }
        )
        let encodedFileURL = URL(string: "file:///tmp/My%20Movie.mkv")!
        let encodedOpenResult = await launcher.open(fileURL: encodedFileURL)
        precondition(encodedOpenResult == .opened(.system))
        precondition(playbackProbe.openedURLs == [
            URL(fileURLWithPath: "/tmp/My Movie.mkv")
        ])
        precondition(playbackProbe.applicationOpenCount == 0)
        let remoteOpenResult = await launcher.open(
            fileURL: URL(string: "https://example.com/movie.mkv")!
        )
        precondition(remoteOpenResult == .invalidFileURL)
        precondition(playbackProbe.openedURLs.count == 1)

        var attemptedPlayers: [String] = []
        let fallbackLauncher = ExternalPlayerLauncher(
            applicationURLForBundleID: { bundleID in
                URL(fileURLWithPath: bundleID == "com.colliderli.iina"
                    ? "/Applications/IINA.app"
                    : "/Applications/VLC.app")
            },
            openWithApplication: { _, applicationURL in
                await Task.yield()
                attemptedPlayers.append(applicationURL.lastPathComponent)
                return applicationURL.lastPathComponent == "VLC.app"
                    ? .success
                    : .failure(.launchFailed, "IINA rejected the file")
            },
            openSystem: { _ in .failure(.systemRejected, nil) }
        )
        let fallbackResult = await fallbackLauncher.open(fileURL: encodedFileURL)
        precondition(fallbackResult == .opened(.vlc))
        precondition(attemptedPlayers == ["IINA.app", "VLC.app"])

        let failedLauncher = ExternalPlayerLauncher(
            applicationURLForBundleID: { bundleID in
                URL(fileURLWithPath: "/Applications/\(bundleID).app")
            },
            openWithApplication: { _, _ in
                .failure(.launchFailed, "application error")
            },
            openSystem: { _ in .failure(.systemRejected, "system error") }
        )
        let failedResult = await failedLauncher.open(fileURL: encodedFileURL)
        guard case let .failed(failures) = failedResult else {
            preconditionFailure("All provider failures must be returned.")
        }
        precondition(failures.map(\.player) == [.iina, .vlc, .system])
        precondition(failures.map(\.reason) == [
            .launchFailed, .launchFailed, .systemRejected
        ])
        let playbackOpenedBeforeFailure = mutatingStore.entries[0].lastOpenedAt
        precondition(!mutatingStore.recordPlayback(
            result: failedResult,
            entryID: mutatingID
        ))
        precondition(
            mutatingStore.entries[0].lastOpenedAt == playbackOpenedBeforeFailure
        )
        precondition(mutatingStore.recordPlayback(
            result: .opened(.system),
            entryID: mutatingID
        ))
        precondition(
            mutatingStore.entries[0].lastOpenedAt != playbackOpenedBeforeFailure
        )

        let exactMovie = Movie(
            id: 157336,
            title: "Interstellar",
            originalTitle: "Interstellar",
            overview: "Space exploration",
            posterPath: "/poster.jpg",
            releaseDate: "2014-11-05",
            voteAverage: 8.5,
            voteCount: 10,
            genreIDs: [12, 878]
        )
        let confirmedMovieMetadata = LocalLibraryMetadata(
            id: 603,
            kind: .movie,
            title: "The Matrix",
            year: "1999",
            posterPath: "/matrix.jpg",
            overview: "A hacker learns the truth.",
            voteAverage: 8.2,
            genreIDs: [28, 878]
        )
        let bridgedMovie = LocalLibraryDetailBridge.movie(
            from: confirmedMovieMetadata
        )!
        precondition(bridgedMovie.id == confirmedMovieMetadata.id)
        precondition(bridgedMovie.title == confirmedMovieMetadata.title)
        precondition(bridgedMovie.overview == confirmedMovieMetadata.overview)
        precondition(bridgedMovie.year == confirmedMovieMetadata.year)
        precondition(bridgedMovie.posterPath == confirmedMovieMetadata.posterPath)

        let confirmedTelevisionMetadata = LocalLibraryMetadata(
            id: 1399,
            kind: .television,
            title: "Game of Thrones",
            year: "2011",
            posterPath: "/thrones.jpg",
            overview: "Nine families vie for power.",
            voteAverage: 8.5,
            genreIDs: [18, 10765]
        )
        let bridgedTelevision = LocalLibraryDetailBridge.television(
            from: confirmedTelevisionMetadata
        )!
        precondition(bridgedTelevision.id == confirmedTelevisionMetadata.id)
        precondition(bridgedTelevision.name == confirmedTelevisionMetadata.title)
        precondition(bridgedTelevision.overview == confirmedTelevisionMetadata.overview)
        precondition(bridgedTelevision.year == confirmedTelevisionMetadata.year)
        precondition(
            bridgedTelevision.posterPath == confirmedTelevisionMetadata.posterPath
        )

        let legacyPosterMetadata = LocalLibraryMetadata(
            id: 604,
            kind: .movie,
            title: "Legacy Poster",
            year: "2000",
            posterPath: "https://image.tmdb.org/t/p/w342/legacy.jpg",
            overview: "",
            voteAverage: 0
        )
        let bridgedLegacyPoster = LocalLibraryDetailBridge.movie(
            from: legacyPosterMetadata
        )!
        precondition(bridgedLegacyPoster.posterPath == "/legacy.jpg")
        precondition(
            bridgedLegacyPoster.posterURL?.absoluteString ==
                "https://image.tmdb.org/t/p/w342/legacy.jpg"
        )

        let unknownYearMovieMetadata = LocalLibraryMetadata(
            id: confirmedMovieMetadata.id,
            kind: confirmedMovieMetadata.kind,
            title: confirmedMovieMetadata.title,
            year: "年份未知",
            posterPath: confirmedMovieMetadata.posterPath,
            overview: confirmedMovieMetadata.overview,
            voteAverage: confirmedMovieMetadata.voteAverage,
            genreIDs: confirmedMovieMetadata.genreIDs
        )
        let unknownYearMovie = LocalLibraryDetailBridge.movie(
            from: unknownYearMovieMetadata
        )!
        precondition(unknownYearMovie.releaseDate == nil)

        let unknownYearTelevisionMetadata = LocalLibraryMetadata(
            id: confirmedTelevisionMetadata.id,
            kind: confirmedTelevisionMetadata.kind,
            title: confirmedTelevisionMetadata.title,
            year: "年份未知",
            posterPath: confirmedTelevisionMetadata.posterPath,
            overview: confirmedTelevisionMetadata.overview,
            voteAverage: confirmedTelevisionMetadata.voteAverage,
            genreIDs: confirmedTelevisionMetadata.genreIDs
        )
        let unknownYearTelevision = LocalLibraryDetailBridge.television(
            from: unknownYearTelevisionMetadata
        )!
        precondition(unknownYearTelevision.firstAirDate == nil)

        let otherRoutingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CineBarOtherRoute-\(UUID().uuidString)")
        let otherRoutingStateURL = otherRoutingDirectory
            .appendingPathComponent("Library.json")
        try! FileManager.default.createDirectory(
            at: otherRoutingDirectory,
            withIntermediateDirectories: true
        )
        let otherRoutingEntry = LocalLibraryEntry(
            id: UUID(),
            folderID: UUID(),
            relativePath: "Camera Clip.mov",
            signature: LocalLibraryFileSignature(
                fileName: "Camera Clip.mov",
                fileExtension: "mov",
                byteCount: 0,
                modificationDate: nil,
                resourceIdentifier: nil
            ),
            state: .available,
            matchState: .unmatched,
            metadata: nil,
            isWatched: false,
            isInWatchlist: false,
            lastOpenedAt: nil,
            contentCategory: .other
        )
        try! LocalLibraryPersistence(fileURL: otherRoutingStateURL).save(
            LocalLibrarySnapshot(folders: [], entries: [otherRoutingEntry])
        )
        let otherRoutingStore = LocalLibraryStore(fileURL: otherRoutingStateURL)
        otherRoutingStore.confirmMatch(
            entryID: otherRoutingEntry.id,
            metadata: unknownYearMovieMetadata
        )
        let confirmedOtherRoutingEntry = otherRoutingStore.entries[0]
        precondition(confirmedOtherRoutingEntry.matchState == .confirmed)
        precondition(confirmedOtherRoutingEntry.contentCategory == .movie)
        precondition(
            LocalLibraryDetailBridge.movie(
                from: confirmedOtherRoutingEntry.metadata!
            )?.releaseDate == nil
        )
        try? FileManager.default.removeItem(at: otherRoutingDirectory)

        let partialMovie = Movie(
            id: 2,
            title: "Interstellar Journey",
            originalTitle: nil,
            overview: "",
            posterPath: nil,
            releaseDate: "2016-01-01",
            voteAverage: 6,
            voteCount: 1
        )
        let exactCandidate = LocalLibraryMatchCandidate(
            movie: exactMovie,
            query: LocalLibraryFilenameParser.parse("Interstellar.2014.mkv")
        )
        precondition(exactCandidate.id == 157336)
        precondition(exactCandidate.kind == .movie)
        precondition(exactCandidate.year == "2014")
        precondition(exactCandidate.posterURL?.absoluteString ==
            "https://image.tmdb.org/t/p/w342/poster.jpg")
        precondition(exactCandidate.metadata.posterPath == "/poster.jpg")
        precondition(LocalLibraryPosterURL.resolve(
            exactCandidate.metadata.posterPath
        )?.absoluteString == "https://image.tmdb.org/t/p/w154/poster.jpg")
        precondition(exactCandidate.voteAverage == 8.5)
        precondition(exactCandidate.genreIDs == [12, 878])
        precondition(exactCandidate.metadata.genreIDs == [12, 878])
        precondition(exactCandidate.confidence == 1)
        precondition(
            exactCandidate.confidence > LocalLibraryMatchCandidate(
                movie: partialMovie,
                query: LocalLibraryFilenameParser.parse("Interstellar.2014.mkv")
            ).confidence
        )

        let containingMovie = Movie(
            id: 3,
            title: "Interstellar Journey",
            originalTitle: nil,
            overview: "",
            posterPath: nil,
            releaseDate: "2014-01-01",
            voteAverage: 10,
            voteCount: 1
        )

        let sameTitle1984 = Movie(
            id: 1984,
            title: "Dune",
            originalTitle: nil,
            overview: "",
            posterPath: nil,
            releaseDate: "1984-12-14",
            voteAverage: 1,
            voteCount: 1
        )
        let sameTitle2021 = Movie(
            id: 2021,
            title: "Dune",
            originalTitle: nil,
            overview: "",
            posterPath: nil,
            releaseDate: "2021-10-22",
            voteAverage: 10,
            voteCount: 1
        )
        let sameTitleEntry = LocalLibraryEntry(
            id: UUID(),
            folderID: UUID(),
            relativePath: "Dune.1984.mkv",
            signature: LocalLibraryFileSignature(
                fileName: "Dune.1984.mkv",
                fileExtension: "mkv",
                byteCount: 0,
                modificationDate: nil,
                resourceIdentifier: nil
            ),
            state: .available,
            matchState: .unmatched,
            metadata: nil,
            isWatched: false,
            isInWatchlist: false,
            lastOpenedAt: nil,
            contentCategory: .movie
        )
        let sameTitleMatchService = LocalLibraryMatchService(
            movieSearch: { _ in [sameTitle2021, sameTitle1984] },
            televisionSearch: { _ in [] }
        )
        let sameTitleSuggestions = try! await sameTitleMatchService.search(
            for: sameTitleEntry
        )
        precondition(sameTitleSuggestions.map(\.id) == [1984, 2021])
        precondition(
            sameTitleSuggestions[0].confidence >
                sameTitleSuggestions[1].confidence
        )

        let matchProbe = LocalLibraryMatchProbe()
        let matchService = LocalLibraryMatchService(
            movieSearch: { query in
                matchProbe.movieQueries.append(query)
                return [partialMovie, exactMovie]
            },
            televisionSearch: { query in
                matchProbe.televisionQueries.append(query)
                return []
            }
        )
        let unmatchedEntry = LocalLibraryEntry(
            id: UUID(),
            folderID: UUID(),
            relativePath: "Interstellar.2014.mkv",
            signature: LocalLibraryFileSignature(
                fileName: "Interstellar.2014.mkv",
                fileExtension: "mkv",
                byteCount: 0,
                modificationDate: nil,
                resourceIdentifier: nil
            ),
            state: .available,
            matchState: .unmatched,
            metadata: nil,
            isWatched: false,
            isInWatchlist: false,
            lastOpenedAt: nil,
            contentCategory: .movie
        )
        let suggestions = try! await matchService.search(for: unmatchedEntry)
        precondition(suggestions.map(\.id) == [157336, 2])
        precondition(matchProbe.movieQueries == ["Interstellar"])
        precondition(matchProbe.televisionQueries.isEmpty)
        precondition(unmatchedEntry.metadata == nil)
        precondition(unmatchedEntry.matchState == .unmatched)
        precondition(matchProbe.movieQueries.count == 1)

        let typoMatchService = LocalLibraryMatchService(
            movieSearch: { _ in [containingMovie, exactMovie] },
            televisionSearch: { _ in [] }
        )
        let typoSuggestions = try! await typoMatchService.search(
            query: LocalLibraryMatchQuery(text: "Interstelar 2014", kind: .movie)
        )
        precondition(typoSuggestions.map(\.id) == [157336, 3])

        let manualSuggestions = try! await matchService.search(
            query: LocalLibraryMatchQuery(text: "Interstellar", kind: .movie)
        )
        precondition(manualSuggestions.map(\.id) == [157336, 2])
        precondition(matchProbe.movieQueries == ["Interstellar", "Interstellar"])

        let manualTelevisionSuggestions = try! await matchService.search(
            query: LocalLibraryMatchQuery(text: "Example Show", kind: .television)
        )
        precondition(manualTelevisionSuggestions.isEmpty)
        precondition(matchProbe.televisionQueries == ["Example Show"])

        let televisionEntry = LocalLibraryEntry(
            id: UUID(),
            folderID: UUID(),
            relativePath: "Example.Show.S01E02.mkv",
            signature: LocalLibraryFileSignature(
                fileName: "Example.Show.S01E02.mkv",
                fileExtension: "mkv",
                byteCount: 0,
                modificationDate: nil,
                resourceIdentifier: nil
            ),
            state: .available,
            matchState: .unmatched,
            metadata: nil,
            isWatched: false,
            isInWatchlist: false,
            lastOpenedAt: nil,
            contentCategory: .television
        )
        _ = try! await matchService.search(for: televisionEntry)
        precondition(matchProbe.televisionQueries == ["Example Show", "Example Show"])

        var emptyEntry = unmatchedEntry
        emptyEntry.signature = LocalLibraryFileSignature(
            fileName: "",
            fileExtension: "",
            byteCount: 0,
            modificationDate: nil,
            resourceIdentifier: nil
        )
        let emptySuggestions = try! await matchService.search(for: emptyEntry)
        precondition(emptySuggestions.isEmpty)
        precondition(matchProbe.movieQueries.count == 2)

        var personalEntry = unmatchedEntry
        personalEntry.contentCategory = .other
        let personalSuggestions = try! await matchService.search(for: personalEntry)
        precondition(personalSuggestions.isEmpty)
        precondition(matchProbe.movieQueries.count == 2)

        let manualOtherSuggestions = try! await matchService.search(
            query: LocalLibraryMatchQuery(
                text: LocalLibraryFilenameParser.parse(
                    personalEntry.signature.fileName
                ).title,
                kind: .movie
            )
        )
        precondition(manualOtherSuggestions.map(\.id) == [157336, 2])
        precondition(matchProbe.movieQueries.count == 3)

        // —— 手动分类（右键）与远程源数据模型 ——
        let manualCategoryDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CineBarManualCategory-\(UUID().uuidString)")
        let manualCategoryURL = manualCategoryDir.appendingPathComponent("LocalLibrary.json")
        let manualFolder = LocalLibraryFolder(
            id: UUID(),
            displayName: "测试",
            pathHint: "folder",
            bookmarkData: Data([0x45, 0x46])
        )
        let manualEntry = LocalLibraryEntry(
            id: UUID(),
            folderID: manualFolder.id,
            relativePath: "video.mp4",
            signature: LocalLibraryFileSignature(
                fileName: "video.mp4",
                fileExtension: "mp4",
                byteCount: 0,
                modificationDate: nil,
                resourceIdentifier: nil
            ),
            state: .available,
            matchState: .unmatched,
            metadata: nil,
            isWatched: false,
            isInWatchlist: false,
            lastOpenedAt: nil,
            contentCategory: .other
        )
        try! LocalLibraryPersistence(fileURL: manualCategoryURL).save(
            LocalLibrarySnapshot(folders: [manualFolder], entries: [manualEntry])
        )
        let manualCategoryStore = LocalLibraryStore(fileURL: manualCategoryURL)
        manualCategoryStore.setContentCategory(entryID: manualEntry.id, category: .movie)
        precondition(manualCategoryStore.entries[0].contentCategory == .movie)
        precondition(manualCategoryStore.entries[0].matchState == .suggested)
        // 改回 other 应清除匹配并回落到 unmatched
        manualCategoryStore.setContentCategory(entryID: manualEntry.id, category: .other)
        precondition(manualCategoryStore.entries[0].contentCategory == .other)
        precondition(manualCategoryStore.entries[0].matchState == .unmatched)
        try? FileManager.default.removeItem(at: manualCategoryDir)

        // 远程占位 bookmark 识别：本地 bookmark 不是远程占位
        precondition(!LocalLibraryFolderBookmark.isRemotePlaceholder(Data([0x45, 0x46])))
        let remotePlaceholder = Data([0x52, 0x45, 0x4D, 0x4F, 0x54, 0x45])
            + (UUID().uuidString.data(using: .utf8)!)
        precondition(LocalLibraryFolderBookmark.isRemotePlaceholder(remotePlaceholder))

        // 远程源持久化（含 kind/凭据引用，不含明文密码）
        let remoteSourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CineBarRemoteSource-\(UUID().uuidString).json")
        let remoteFolder = LocalLibraryFolder(
            id: UUID(),
            displayName: "NAS",
            pathHint: "nas:5006/dav",
            bookmarkData: remotePlaceholder,
            storeType: .remoteMount,
            remote: LocalLibraryRemoteSource(
                kind: .webDAV,
                host: "nas.local",
                port: 5006,
                usesTLS: true,
                rootPath: "/dav",
                username: "user",
                keychainService: "com.indiedev.cinebar.remote",
                keychainAccount: "user@nas.local:5006",
                displayName: "NAS"
            )
        )
        do {
            let data = try JSONEncoder().encode(
                LocalLibrarySnapshot(folders: [remoteFolder], entries: [])
            )
            let decoded = try JSONDecoder().decode(
                LocalLibrarySnapshot.self,
                from: data
            )
            precondition(decoded.folders[0].storeType == .remoteMount)
            precondition(decoded.folders[0].remote?.kind == .webDAV)
            precondition(decoded.folders[0].remote?.username == "user")
            precondition(decoded.folders[0].remote?.rootPath == "/dav")
        } catch {
            preconditionFailure("远程源编解码失败")
        }
        try? FileManager.default.removeItem(at: remoteSourceURL)

        // —— NAS 品牌识别 ——
        precondition(
            LocalLibraryNASDiscovery.recognizeBrand(
                hostname: "mynas.local",
                serviceType: "_smb._tcp"
            ) == nil
        )
        precondition(
            LocalLibraryNASDiscovery.recognizeBrand(
                hostname: "diskstation.local",
                serviceType: "_smb._tcp"
            ) == .synology
        )
        precondition(
            LocalLibraryNASDiscovery.recognizeBrand(
                hostname: "UGREENnas.local",
                serviceType: "_smb._tcp"
            ) == .ugreen
        )
        precondition(
            LocalLibraryNASDiscovery.recognizeBrand(
                hostname: "tpnas-qnap.local",
                serviceType: "_smb._tcp"
            ) == .qnap
        )
        // 绿联默认 SMB 共享名
        precondition(NASBrand.ugreen.defaultSMBShare == "共享")
        // 品牌展示名非空
        for brand in [NASBrand.ugreen, .synology, .qnap] {
            precondition(!brand.displayName.isEmpty)
        }
    }
}

private final class LocalLibraryPlaybackProbe {
    var applicationOpenCount = 0
    var openedURLs: [URL] = []
}

private final class LocalLibraryMatchProbe {
    var movieQueries: [String] = []
    var televisionQueries: [String] = []
}

private actor LocalLibraryRefreshGate {
    private var isReleased = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func waitUntilReleased() async {
        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func release() {
        isReleased = true
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume() }
    }
}
#endif
