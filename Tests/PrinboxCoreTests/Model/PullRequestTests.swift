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
}
