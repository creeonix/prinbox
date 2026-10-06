import Foundation
import Testing

@testable import PrinboxCore

@Suite struct SectionKindTests {
    @Test func anEmptyScopeKeepsThePagesOfToday() {
        for kind in SectionKind.allCases {
            #expect(kind.moreURL(scope: .none) == kind.moreURL, "\(kind)")
        }
        #expect(SectionKind.needsReview.moreURL == URL(string: "https://github.com/pulls/review-requested"))
    }

    @Test func aScopeMakesASearchURLWithTheSectionsQualifier() throws {
        let scope = SearchScope(directReviewRequestsOnly: true, hideDrafts: true)
        func query(_ kind: SectionKind) throws -> String {
            let url = kind.moreURL(scope: scope)
            #expect(url.host == "github.com")
            #expect(url.path == "/pulls")
            let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
            #expect(items.count == 1)
            return try #require(items.first { $0.name == "q" }?.value)
        }
        let needsReview = try query(.needsReview)
        let takeAnotherLook = try query(.takeAnotherLook)
        let mentions = try query(.mentions)
        let replies = try query(.repliesToYou)
        let yours = try query(.yourPRs)
        let waiting = try query(.waitingOnOthers)
        #expect(needsReview == "is:open is:pr user-review-requested:@me -is:draft sort:updated-desc")
        #expect(takeAnotherLook == needsReview)
        #expect(
            mentions
                == "is:open is:pr mentions:@me -author:@me -user-review-requested:@me -is:draft sort:updated-desc"
        )
        #expect(
            replies
                == "is:open is:pr involves:@me -author:@me -user-review-requested:@me -mentions:@me -is:draft sort:updated-desc"
        )
        #expect(yours == "is:open is:pr author:@me sort:updated-desc")
        #expect(waiting == yours)
        let text = SectionKind.needsReview.moreURL(scope: scope).absoluteString
        #expect(!text.contains(" "))
        #expect(
            text.hasPrefix("https://github.com/pulls?q=is:open%20is:pr%20")
                || text.hasPrefix("https://github.com/pulls?q=is%3Aopen%20is%3Apr%20"))
    }
}
