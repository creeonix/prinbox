import Testing

@testable import PrinboxCore

@Suite struct InboxQueryTests {
    @Test func everySearchExcludesArchivedRepositories() {
        #expect(InboxQuery.text.components(separatedBy: "archived:false").count - 1 == 3)
    }

    @Test func asksForTheViewerLogin() {
        #expect(InboxQuery.text.contains("viewer { login }"))
    }
}
