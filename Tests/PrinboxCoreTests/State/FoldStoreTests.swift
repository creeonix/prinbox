import Testing

@testable import PrinboxCore

@MainActor
@Suite struct FoldStoreTests {
    @Test func firstRunOpensOnlyNeedsYourReview() {
        let folds = FoldStore(defaults: MemoryDefaults())
        #expect(!folds.isFolded(.needsReview))
        #expect(folds.isFolded(.takeAnotherLook))
        #expect(folds.isFolded(.waitingOnOthers))
    }

    @Test func togglePersistsAcrossInstances() {
        let defaults = MemoryDefaults()
        FoldStore(defaults: defaults).toggle(.mentions)
        #expect(!FoldStore(defaults: defaults).isFolded(.mentions))
    }

    @Test func unknownStoredValuesAreIgnored() {
        let defaults = MemoryDefaults()
        defaults.set(["mentions", "bogus"], forKey: FoldStore.key)
        #expect(FoldStore(defaults: defaults).folded == [.mentions])
    }

    @Test func repliesToYouIsOpenByDefault() {
        let folds = FoldStore(defaults: MemoryDefaults())
        #expect(!folds.isFolded(.repliesToYou))
        #expect(!folds.isFolded(.needsReview))
        #expect(folds.isFolded(.takeAnotherLook))
    }
}
