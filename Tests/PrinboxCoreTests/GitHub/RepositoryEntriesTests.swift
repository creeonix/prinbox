import Testing

@testable import PrinboxCore

@Suite struct RepositoryEntriesTests {
    @Test func entriesAreOwnersOwnerSlashStarOrOwnerSlashName() {
        for valid in ["acme", "acme/*", "acme/web", "a-b/x.y_z-1", "Initech/Repo", "7up/*"] {
            #expect(RepositoryEntries.isValid(valid), "\(valid)")
        }
        for invalid in ["", "-acme", "acme/", "/web", "*", "acme/**", "acme/web/x", "acme web", "org:acme", "é/x"] {
            #expect(!RepositoryEntries.isValid(invalid), "\(invalid)")
        }
    }

    @Test func normalizeTrimsRespellsDeduplicatesSubsumesAndSorts() {
        // acme becomes acme/*; ACME/* duplicates it; acme/web is covered by acme/*; Globex/Billing duplicates
        // globex/billing; org:bad and /x are invalid (2 dropped); the rest is sorted without regard to case.
        let (entries, dropped) = RepositoryEntries.normalize([
            " globex/billing ", "", "acme", "org:bad", "ACME/*", "acme/web", "Globex/Billing\n", "initech/docs", "/x",
        ])
        #expect(entries == ["acme/*", "globex/billing", "initech/docs"])
        #expect(dropped == 2)
        #expect(RepositoryEntries.normalize([]).entries.isEmpty)
        #expect(RepositoryEntries.normalize(["acme/web", "acme/api"]).entries == ["acme/api", "acme/web"])
        #expect(RepositoryEntries.normalize(["Zed/*", "acme/web"]).entries == ["acme/web", "Zed/*"])
    }

    @Test func qualifiersOwnersAndCoverage() {
        #expect(RepositoryEntries.qualifier(for: "acme/*") == " user:acme")
        #expect(RepositoryEntries.qualifier(for: "globex/billing") == " repo:globex/billing")
        #expect(RepositoryEntries.owner(of: "globex/billing") == "globex")
        #expect(RepositoryEntries.owner(of: "acme/*") == "acme")
        #expect(RepositoryEntries.isWildcard("acme/*"))
        #expect(!RepositoryEntries.isWildcard("acme/web"))
        #expect(RepositoryEntries.covers("acme/*", repository: "acme/web"))
        #expect(RepositoryEntries.covers("acme/*", repository: "ACME/api"))
        #expect(!RepositoryEntries.covers("acme/*", repository: "globex/billing"))
        #expect(RepositoryEntries.covers("globex/billing", repository: "globex/billing"))
        #expect(!RepositoryEntries.covers("globex/billing", repository: "globex/sync"))
    }
}
