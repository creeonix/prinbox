import Testing

@testable import PrinboxCore

@Suite struct RepositoryPickerTests {
    let known: Set<String> = ["acme/web", "acme/api", "globex/billing", "globex/sync", "initech/docs"]

    func picker(_ pinned: [String], known: Set<String>? = nil) -> RepositoryPicker {
        RepositoryPicker(
            known: known ?? self.known,
            shape: FetchShape(includeConversation: true, scope: SearchScope(repositories: pinned)))
    }

    @Test func groupsByOwnerWithTheWildcardFirstAndEverythingSorted() {
        let picker = picker([])
        #expect(picker.groups.map(\.owner) == ["acme", "globex", "initech"])
        #expect(picker.groups[0].items.map(\.entry) == ["acme/*", "acme/api", "acme/web"])
        #expect(picker.groups[1].items.map(\.entry) == ["globex/*", "globex/billing", "globex/sync"])
        #expect(picker.groups[2].items.map(\.entry) == ["initech/*", "initech/docs"])
        let items = picker.groups.flatMap(\.items)
        #expect(items.allSatisfy { !$0.isPinned && !$0.isCovered && $0.overflow == 0 && $0.isEnabled })
        #expect(RepositoryPicker(known: [], shape: FetchShape()).groups.isEmpty)
    }

    @Test func pinnedAndCoveredItemsAreMarkedAndPinsOutsideTheKnownSetAreListed() {
        let picker = picker(["acme/*", "globex/billing", "umbrella/lab"])
        let acme = picker.groups[0].items
        #expect(acme.map(\.isPinned) == [true, false, false])
        #expect(acme.map(\.isCovered) == [false, true, true])
        #expect(acme.map(\.isEnabled) == [true, false, false])
        let globex = picker.groups[1].items
        #expect(globex.map(\.entry) == ["globex/*", "globex/billing", "globex/sync"])
        #expect(globex.map(\.isPinned) == [false, true, false])
        #expect(globex.map(\.isCovered) == [false, false, false])
        #expect(picker.groups.map(\.owner) == ["acme", "globex", "initech", "umbrella"])
        #expect(picker.groups[3].items.map(\.entry) == ["umbrella/*", "umbrella/lab"])
        #expect(picker.groups[3].items.map(\.isPinned) == [false, true])
        // A pin spelled in another case still marks the known repository.
        let upper = self.picker(["ACME/*"])
        #expect(upper.groups[0].owner == "acme")
        #expect(upper.groups[0].items.map(\.isPinned) == [true, false, false])
        #expect(upper.groups[0].items.map(\.isCovered) == [false, true, true])
    }

    @Test func anEntryThatWouldOverflowIsDimmedWithTheCount() {
        // The `involved` base with both switches on is 122 characters; " user:" plus a 128-letter owner lands on
        // 256, so a 129-letter one is one over. " repo:" plus "<129 letters>/x" is 6 + 131 = 137: 259, three over.
        let long = String(repeating: "a", count: 129)
        let shape = FetchShape(
            includeConversation: true, scope: SearchScope(directReviewRequestsOnly: true, hideDrafts: true))
        let picker = RepositoryPicker(known: ["\(long)/x"], shape: shape)
        #expect(picker.groups[0].items[0].entry == "\(long)/*")
        #expect(picker.groups[0].items[0].overflow == 1)
        #expect(picker.groups[0].items[0].isEnabled == false)
        #expect(picker.groups[0].items[1].overflow == 3)
        let fits = String(repeating: "a", count: 128)
        #expect(RepositoryPicker(known: ["\(fits)/x"], shape: shape).groups[0].items[0].overflow == 0)
    }

    @Test func togglingPinsUnpinsAndDropsCoveredRepositories() {
        #expect(RepositoryPicker.toggled("acme/*", in: []) == ["acme/*"])
        #expect(
            RepositoryPicker.toggled("acme/*", in: ["acme/web", "globex/billing"]) == ["acme/*", "globex/billing"])
        #expect(RepositoryPicker.toggled("acme/*", in: ["acme/*", "globex/billing"]) == ["globex/billing"])
        #expect(RepositoryPicker.toggled("acme/web", in: ["globex/billing"]) == ["acme/web", "globex/billing"])
        #expect(RepositoryPicker.toggled("acme/web", in: ["acme/web"]) == [])
        #expect(RepositoryPicker.toggled("acme/web", in: ["acme/*"]) == ["acme/*"])
        #expect(RepositoryPicker.toggled("ACME/web", in: ["acme/web"]) == [])
    }
}
