import Foundation
import Testing

@testable import PrinboxCore

@Suite struct ArrivalsTests {
    let old = date("2026-08-01T10:00:00Z")
    let newer = date("2026-08-02T10:00:00Z")

    func inbox(_ prs: [PullRequest]) -> Inbox { InboxBuilder.build(makeResult(prs)) }

    @Test func firstFetchAfterLaunchBringsNothing() {
        #expect(Arrivals.compute(previous: nil, current: inbox([makePR(id: "a")])).isEmpty)
    }

    @Test func newAndUpdatedReviewRequestsArrive() {
        let previous = ["a": old, "b": old]
        let current = inbox([
            makePR(id: "a", number: 1, updatedAt: newer),
            makePR(id: "b", number: 2, updatedAt: old),
            makePR(id: "c", number: 3, updatedAt: old),
        ])
        #expect(Arrivals.compute(previous: previous, current: current).map(\.id) == ["a", "c"])
    }

    @Test func onlyReviewSectionsCountAndDraftsDoNot() {
        let reviewed = ViewerReview(state: "COMMENTED", submittedAt: old)
        let current = inbox([
            makePR(id: "again", viewerReview: reviewed, reviewRequestedAt: newer, source: .review),
            makePR(id: "mention", source: .mentions),
            makePR(id: "mine", reviewDecision: .changesRequested, source: .mine),
            makePR(id: "draft", isDraft: true, source: .review),
        ])
        #expect(Arrivals.compute(previous: [:], current: current).map(\.id) == ["again"])
    }

    @Test func aMoveBetweenSectionsWithTheSameUpdatedAtIsNotAnArrival() {
        let previous = ["a": old]
        let current = inbox([makePR(id: "a", updatedAt: old, source: .review)])
        #expect(Arrivals.compute(previous: previous, current: current).isEmpty)
    }

    @Test func noticeForOnePullRequestOpensIt() {
        let pr = makePR(id: "a", number: 42, title: "Ship it", repository: "acme/web")
        let rows = Arrivals.compute(previous: [:], current: inbox([pr]))
        #expect(
            ArrivalNotice.make(rows)
                == ArrivalNotice(
                    title: "#42 Ship it", body: "acme/web · Needs your review", url: pr.url))
    }

    @Test func noticeForSeveralListsUpToThreeTitles() {
        let three = (1...3).map { makePR(id: "p\($0)", number: $0, title: "T\($0)") }
        let notice = ArrivalNotice.make(Arrivals.compute(previous: [:], current: inbox(three)))
        #expect(
            notice
                == ArrivalNotice(
                    title: "3 new review requests", body: "#1 T1\n#2 T2\n#3 T3", url: nil))
        let five = (1...5).map { makePR(id: "p\($0)", number: $0, title: "T\($0)") }
        let more = ArrivalNotice.make(Arrivals.compute(previous: [:], current: inbox(five)))
        #expect(more?.title == "5 new review requests")
        #expect(more?.body == "#1 T1\n#2 T2\n#3 T3\nand 2 more")
        #expect(ArrivalNotice.make([]) == nil)
    }
}
