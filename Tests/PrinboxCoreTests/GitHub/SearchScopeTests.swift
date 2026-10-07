import Foundation
import Testing

@testable import PrinboxCore

@Suite struct SearchScopeTests {
    @Test func defaultsAreEmptyAndKeysAreTheSettingsNames() {
        #expect(SearchScope.none.isEmpty)
        #expect(SearchScope(hideDrafts: true).isEmpty == false)
        #expect(SearchScope(directReviewRequestsOnly: true).isEmpty == false)
        #expect(SearchScope(repositories: ["acme/*"]).isEmpty == false)
        #expect(SearchScope.directKey == "directReviewRequestsOnly")
        #expect(SearchScope.repositoriesKey == "defaultRepositories")
        #expect(SearchScope.hideDraftsKey == "hideDrafts")
    }

    @Test func repositoriesAreAlwaysNormalized() {
        var scope = SearchScope(repositories: ["acme", "acme/web", "org:bad"])
        #expect(scope.repositories == ["acme/*"])
        scope.repositories = ["Globex/Billing", "globex/billing", " initech/* "]
        #expect(scope.repositories == ["Globex/Billing", "initech/*"])
        #expect(SearchScope(repositories: ["org:bad"]).isEmpty)
    }

    @Test func readTakesTheThreeKeysFromTheStoreAndCountsInvalidEntries() {
        let store = MemoryDefaults()
        #expect(SearchScope.read(from: store) == .none)
        store.set(true, forKey: SearchScope.directKey)
        store.set(["acme", "globex/billing"], forKey: SearchScope.repositoriesKey)
        store.set(true, forKey: SearchScope.hideDraftsKey)
        let expected = SearchScope(
            directReviewRequestsOnly: true, repositories: ["acme/*", "globex/billing"], hideDrafts: true)
        #expect(SearchScope.read(from: store) == expected)
        let logger = MemoryLogging()
        store.set(["acme", "org:bad"], forKey: SearchScope.repositoriesKey)
        #expect(SearchScope.read(from: store, logger: logger).repositories == ["acme/*"])
        #expect(logger.messages(.notice) == ["default repositories: ignored 1 invalid entry"])
        store.set(["org:bad", "/x", "acme"], forKey: SearchScope.repositoriesKey)
        _ = SearchScope.read(from: store, logger: logger)
        #expect(logger.messages(.notice).last == "default repositories: ignored 2 invalid entries")
        #expect(logger.lines.allSatisfy { !$0.message.contains("org:bad") && $0.detail == nil })
        #expect(logger.lines.allSatisfy { $0.category == .state })
    }

    @Test func readFallsBackToDefaultsForWrongTypes() {
        let store = MemoryDefaults()
        store.set("yes", forKey: SearchScope.directKey)
        store.set("acme", forKey: SearchScope.repositoriesKey)
        store.set(1, forKey: SearchScope.hideDraftsKey)
        #expect(SearchScope.read(from: store) == .none)
    }

    @Test func codableKeysAreTheSettingsNamesAndAMissingListDecodesAsEmpty() throws {
        let scope = SearchScope(directReviewRequestsOnly: true, repositories: ["acme/*"], hideDrafts: false)
        let data = try JSONEncoder().encode(scope)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"directReviewRequestsOnly\":true"))
        #expect(text.contains("\"defaultRepositories\":[\"acme"))
        #expect(!text.contains("\"repositories\""))
        #expect(text.contains("\"hideDrafts\":false"))
        #expect(try JSONDecoder().decode(SearchScope.self, from: data) == scope)
        // A 0.6.0 cache's scope has the two switches only.
        let sixPointZero = Data("{\"directReviewRequestsOnly\":true,\"hideDrafts\":true}".utf8)
        let decoded = try JSONDecoder().decode(SearchScope.self, from: sixPointZero)
        #expect(decoded == SearchScope(directReviewRequestsOnly: true, hideDrafts: true))
        #expect(FetchShape() == FetchShape(includeConversation: true, scope: .none))
        #expect(FetchShape(scope: scope) != FetchShape())
    }
}
