import AppKit
import Foundation

#if CINEBAR_TEST
@main
struct CineBarRegressionBehaviorTests {
    @MainActor
    static func main() {
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
