import Testing

@testable import PrinboxCore

@Suite struct InboxQueryTests {
    @Test func everySearchExcludesArchivedRepositories() {
        #expect(InboxQuery.text.components(separatedBy: "archived:false").count - 1 == 3)
    }

    @Test func asksForTheViewerLogin() {
        #expect(InboxQuery.text.contains("viewer { login }"))
    }

    @Test func asksForTheNewFields() {
        #expect(InboxQuery.text.contains("totalCommentsCount"))
        #expect(InboxQuery.text.contains("owner { __typename login avatarUrl(size: 64) }"))
        #expect(InboxQuery.text.contains("latestOpinionatedReviews(first: 10) { nodes { state } }"))
    }
}
