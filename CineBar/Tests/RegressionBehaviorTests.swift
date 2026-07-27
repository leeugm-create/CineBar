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
    }
}
#endif
