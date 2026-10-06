import Foundation
import Testing

@testable import PrinboxCore

@Suite struct SearchScopeTests {
    @Test func defaultsAreEmptyAndKeysAreTheSettingsNames() {
        #expect(SearchScope.none.isEmpty)
        #expect(SearchScope(hideDrafts: true).isEmpty == false)
        #expect(SearchScope(directReviewRequestsOnly: true).isEmpty == false)
        #expect(SearchScope.directKey == "directReviewRequestsOnly")
        #expect(SearchScope.hideDraftsKey == "hideDrafts")
    }

    @Test func readTakesTheTwoKeysFromTheStore() {
        let store = MemoryDefaults()
        #expect(SearchScope.read(from: store) == .none)
        store.set(true, forKey: SearchScope.directKey)
        store.set(true, forKey: SearchScope.hideDraftsKey)
        #expect(SearchScope.read(from: store) == SearchScope(directReviewRequestsOnly: true, hideDrafts: true))
    }

    @Test func readFallsBackToDefaultsForWrongTypes() {
        let store = MemoryDefaults()
        store.set("yes", forKey: SearchScope.directKey)
        store.set(1, forKey: SearchScope.hideDraftsKey)
        #expect(SearchScope.read(from: store) == .none)
    }

    @Test func codableKeysAreTheSettingsNamesAndTheShapeDefaults() throws {
        let scope = SearchScope(directReviewRequestsOnly: true, hideDrafts: false)
        let data = try JSONEncoder().encode(scope)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"directReviewRequestsOnly\":true"))
        #expect(!text.contains("repositories"))
        #expect(text.contains("\"hideDrafts\":false"))
        #expect(try JSONDecoder().decode(SearchScope.self, from: data) == scope)
        #expect(FetchShape() == FetchShape(includeConversation: true, scope: .none))
        #expect(FetchShape(scope: scope) != FetchShape())
    }
}
