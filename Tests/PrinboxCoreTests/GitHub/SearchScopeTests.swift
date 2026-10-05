import Foundation
import Testing

@testable import PrinboxCore

@Suite struct SearchScopeTests {
    @Test func defaultsAreEmptyAndKeysAreTheSettingsNames() {
        #expect(SearchScope.none.isEmpty)
        #expect(SearchScope(hideDrafts: true).isEmpty == false)
        #expect(SearchScope(repositories: ["acme"]).isEmpty == false)
        #expect(SearchScope.directKey == "directReviewRequestsOnly")
        #expect(SearchScope.repositoriesKey == "repositories")
        #expect(SearchScope.hideDraftsKey == "hideDrafts")
    }

    @Test func readTakesTheThreeKeysFromTheStore() {
        let store = MemoryDefaults()
        #expect(SearchScope.read(from: store) == .none)
        store.set(true, forKey: SearchScope.directKey)
        store.set(["acme", "globex/billing"], forKey: SearchScope.repositoriesKey)
        store.set(true, forKey: SearchScope.hideDraftsKey)
        #expect(
            SearchScope.read(from: store)
                == SearchScope(
                    directReviewRequestsOnly: true, repositories: ["acme", "globex/billing"], hideDrafts: true))
    }

    @Test func readFallsBackToDefaultsForWrongTypes() {
        let store = MemoryDefaults()
        store.set("yes", forKey: SearchScope.directKey)
        store.set("acme", forKey: SearchScope.repositoriesKey)
        store.set(1, forKey: SearchScope.hideDraftsKey)
        #expect(SearchScope.read(from: store) == .none)
    }

    @Test func entriesAreOwnersOrOwnerSlashName() {
        for valid in ["acme", "globex/billing", "a-b", "x/y.z_w-1", "Initech/Repo", "7up"] {
            #expect(SearchScope.isValidEntry(valid), "\(valid)")
        }
        for invalid in [
            "", "-acme", "acme/", "/web", "acme/web/extra", "acme web", "org:acme", "acme/we b", "é", "acme/",
        ] {
            #expect(!SearchScope.isValidEntry(invalid), "\(invalid)")
        }
    }

    @Test func normalizeTrimsDropsAndDeduplicates() {
        let (kept, dropped) = SearchScope.normalize([
            " acme ", "", "globex/billing", "org:bad", "ACME", "acme/web", "acme/web",
        ])
        #expect(kept == ["acme", "globex/billing", "acme/web"])
        #expect(dropped == 1)
        #expect(SearchScope.normalize([]).kept.isEmpty)
    }

    @Test func qualifiersFollowTheKindOfEntry() {
        #expect(
            SearchScope(repositories: ["acme", "globex/billing"]).repositoryQualifiers
                == " user:acme repo:globex/billing")
        #expect(SearchScope.none.repositoryQualifiers == "")
        #expect(SearchScope(repositories: ["bad entry"]).repositoryQualifiers == "")
    }

    @Test func codableKeysAreTheSettingsNamesAndTheShapeDefaults() throws {
        let scope = SearchScope(directReviewRequestsOnly: true, repositories: ["acme"], hideDrafts: false)
        let data = try JSONEncoder().encode(scope)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"directReviewRequestsOnly\":true"))
        #expect(text.contains("\"repositories\":[\"acme\"]"))
        #expect(text.contains("\"hideDrafts\":false"))
        #expect(try JSONDecoder().decode(SearchScope.self, from: data) == scope)
        #expect(FetchShape() == FetchShape(includeConversation: true, scope: .none))
        #expect(FetchShape(scope: scope) != FetchShape())
    }
}
