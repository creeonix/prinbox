import Foundation
import Testing

@testable import PrinboxCore

@Suite struct PullRequestTests {
    @Test func repoShortNameDropsTheOwner() {
        #expect(makePR(repository: "acme/web").repoShortName == "web")
    }

    @Test func repoShortNameWithoutOwnerIsUnchanged() {
        #expect(makePR(repository: "web").repoShortName == "web")
    }

    @Test func ownerLoginIsThePartBeforeTheSlash() {
        #expect(makePR(repository: "globex/billing").ownerLogin == "globex")
        #expect(makePR(repository: "solo").ownerLogin == "solo")
    }

    let verdict = ViewerReview(state: "APPROVED", submittedAt: date("2026-08-02T10:00:00Z"), commitOid: "aaa")

    @Test func nothingMovesWithoutAVerdictOrAHead() {
        #expect(makePR().movedSinceVerdict == false)
        #expect(makePR().commitsSinceVerdict == nil)
        #expect(makePR(headOid: "bbb").movedSinceVerdict == false)
        #expect(makePR(viewerVerdict: verdict).movedSinceVerdict == false)
        #expect(makePR().sinceReviewURL == nil)
        #expect(PullRequest.recentCommitWindow == 30)
    }

    @Test func theSameHeadMeansNothingMovedAndZeroCommitsSince() {
        // A rebase that keeps the diff: GitHub re-points the review, so the oids agree (spec 3.1, 3.2).
        let pr = makePR(headOid: "aaa", viewerVerdict: verdict, recentCommitOids: ["000", "aaa"], commitCount: 2)
        #expect(pr.movedSinceVerdict == false)
        #expect(pr.commitsSinceVerdict == 0)
        #expect(pr.rewrittenSinceVerdict == false)
        #expect(pr.sinceReviewURL == nil)
    }

    @Test func commitsAfterTheVerdictAreCountedAndTheDeltaURLBuilt() {
        let pr = makePR(
            number: 7, repository: "acme/api", headOid: "ccc", viewerVerdict: verdict,
            recentCommitOids: ["000", "aaa", "bbb", "ccc"], commitCount: 4)
        #expect(pr.movedSinceVerdict)
        #expect(pr.commitsSinceVerdict == 2)
        #expect(pr.rewrittenSinceVerdict == false)
        #expect(pr.sinceReviewURL == URL(string: "https://github.com/acme/api/pull/7/files/aaa..ccc"))
    }

    @Test func aMissingVerdictCommitIsARewriteUpToTheWindowAndUnknownBeyondIt() {
        let rewritten = makePR(
            headOid: "ccc", viewerVerdict: verdict, recentCommitOids: ["bbb", "ccc"], commitCount: 2)
        #expect(rewritten.commitsSinceVerdict == nil)
        #expect(rewritten.rewrittenSinceVerdict)
        let beyond = makePR(
            headOid: "ccc", viewerVerdict: verdict, recentCommitOids: Array(repeating: "x", count: 29) + ["ccc"],
            commitCount: 31)
        #expect(beyond.commitsSinceVerdict == nil)
        #expect(beyond.rewrittenSinceVerdict == false)
        // No list and no count (a 0.7 cache that somehow has a verdict): moved, and read as rewritten.
        let noCount = makePR(headOid: "ccc", viewerVerdict: verdict)
        #expect(noCount.commitsSinceVerdict == nil)
        #expect(noCount.rewrittenSinceVerdict)
        #expect(noCount.sinceReviewURL != nil)
    }

    @Test func aPullRequestFromAnOlderCacheDecodesWithoutTheNewFields() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let full = makePR(headOid: "aaa", viewerVerdict: verdict, recentCommitOids: ["aaa"], commitCount: 1)
        var object = try #require(JSONSerialization.jsonObject(with: encoder.encode(full)) as? [String: Any])
        for key in ["headOid", "viewerVerdict", "recentCommitOids", "commitCount"] { object[key] = nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PullRequest.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.headOid == nil)
        #expect(decoded.viewerVerdict == nil)
        #expect(decoded.recentCommitOids == nil)
        #expect(decoded.commitCount == nil)
        #expect(decoded.movedSinceVerdict == false)
        #expect(decoded.id == full.id)
    }
}
