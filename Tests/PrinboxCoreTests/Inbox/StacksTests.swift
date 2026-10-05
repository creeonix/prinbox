import Foundation
import Testing

@testable import PrinboxCore

@Suite struct StacksTests {
    func pr(_ id: String, _ number: Int, repo: String = "acme/web", head: String, base: String, cross: Bool = false)
        -> PullRequest
    {
        makePR(id: id, number: number, repository: repo, headRef: head, baseRef: base, isCrossRepository: cross)
    }

    @Test func aChainOfTwoNumbersFromTheRoot() {
        let a = pr("a", 10, head: "feature", base: "main")
        let b = pr("b", 11, head: "feature-2", base: "feature")
        let positions = Stacks.compute([b, a])
        #expect(positions["a"] == StackPosition(position: 1, size: 2, parentID: nil, parentNumber: nil, rootID: "a"))
        #expect(positions["b"] == StackPosition(position: 2, size: 2, parentID: "a", parentNumber: 10, rootID: "a"))
    }

    @Test func aChainOfThreeBesideAnUnrelatedPullRequest() {
        let a = pr("a", 1, head: "f1", base: "main")
        let b = pr("b", 2, head: "f2", base: "f1")
        let c = pr("c", 3, head: "f3", base: "f2")
        let d = pr("d", 4, head: "other", base: "main")
        let positions = Stacks.compute([d, c, b, a])
        #expect(positions.keys.sorted() == ["a", "b", "c"])
        #expect(positions["c"]?.position == 3)
        #expect(positions["c"]?.size == 3)
        #expect(positions["c"]?.parentID == "b")
        #expect(positions["c"]?.rootID == "a")
    }

    @Test func aLineOfOneIsNoStack() {
        #expect(Stacks.compute([pr("a", 1, head: "feature", base: "main")]).isEmpty)
    }

    @Test func aForkLeavesTheWholeGroupUnbadged() {
        let a = pr("a", 1, head: "feature", base: "main")
        let b = pr("b", 2, head: "left", base: "feature")
        let c = pr("c", 3, head: "right", base: "feature")
        #expect(Stacks.compute([a, b, c]).isEmpty)
    }

    @Test func aSharedHeadLeavesTheGroupUnbadged() {
        let a = pr("a", 1, head: "feature", base: "main")
        let a2 = pr("a2", 2, head: "feature", base: "develop")
        let b = pr("b", 3, head: "feature-2", base: "feature")
        #expect(Stacks.compute([a, a2, b]).isEmpty)
    }

    @Test func aCycleLeavesTheGroupUnbadged() {
        let a = pr("a", 1, head: "x", base: "y")
        let b = pr("b", 2, head: "y", base: "x")
        #expect(Stacks.compute([a, b]).isEmpty)
    }

    @Test func aCrossRepositoryPullRequestIsNeverAParent() {
        let fork = pr("f", 1, head: "feature", base: "main", cross: true)
        let child = pr("b", 2, head: "feature-2", base: "feature")
        #expect(Stacks.compute([fork, child]).isEmpty)
    }

    @Test func branchNamesMatchOnlyWithinARepository() {
        let a = pr("a", 1, repo: "acme/web", head: "feature", base: "main")
        let b = pr("b", 2, repo: "acme/api", head: "feature-2", base: "feature")
        #expect(Stacks.compute([a, b]).isEmpty)
    }

    @Test func aMissingParentMakesTheChildARoot() {
        let b = pr("b", 2, head: "f2", base: "f1")
        let c = pr("c", 3, head: "f3", base: "f2")
        let positions = Stacks.compute([b, c])
        #expect(positions["b"]?.position == 1)
        #expect(positions["c"] == StackPosition(position: 2, size: 2, parentID: "b", parentNumber: 2, rootID: "b"))
    }

    @Test func everyReturnedPullRequestCountsWhateverItsSearch() {
        let a = makePR(id: "a", number: 1, source: .review, headRef: "f1", baseRef: "main")
        let b = makePR(id: "b", number: 2, source: .involved, headRef: "f2", baseRef: "f1")
        let c = makePR(id: "c", number: 3, source: .mine, headRef: "f3", baseRef: "f2")
        #expect(Stacks.compute([a, b, c]).mapValues(\.position) == ["a": 1, "b": 2, "c": 3])
    }

    @Test func missingRefsNeverLink() {
        let a = makePR(id: "a", number: 1)
        let b = makePR(id: "b", number: 2, baseRef: "main")
        #expect(Stacks.compute([a, b]).isEmpty)
    }
}
