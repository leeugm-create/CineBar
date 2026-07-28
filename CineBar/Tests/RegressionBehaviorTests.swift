import AppKit
import Foundation

#if CINEBAR_TEST
@main
struct CineBarRegressionBehaviorTests {
    @MainActor
    static func main() {
        precondition(
            DataProxyConfiguration.normalizedBaseURL(
                "https://cinebar-data.leeugm.workers.dev/"
            ) == "https://cinebar-data.leeugm.workers.dev"
        )
        precondition(
            DataProxyConfiguration.normalizedBaseURL("ftp://invalid") == nil
        )

        let proxiedOMDbURL = OMDbEndpoint.url(
            proxyBaseURL: "https://cinebar-data.leeugm.workers.dev",
            apiKey: "",
            imdbID: "tt0133093"
        )
        precondition(
            proxiedOMDbURL?.absoluteString ==
                "https://cinebar-data.leeugm.workers.dev/omdb?i=tt0133093"
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
                proxyBaseURL: "https://cinebar-data.leeugm.workers.dev",
                apiKey: "",
                imdbID: "603"
            ) == nil
        )

        let builtInSettings = DataSettingsPresentation(
            proxyBaseURL: "https://cinebar-data.leeugm.workers.dev"
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
    }
}
#endif
