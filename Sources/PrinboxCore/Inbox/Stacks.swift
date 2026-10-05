import Foundation

/// A pull request's place in a stack: 1 is the root (its base matches no returned PR), `size` the chain's
/// length. `rootID` is the chain's identity, which keeps a chain contiguous inside a section.
public struct StackPosition: Sendable, Equatable, Codable {
    public let position: Int
    public let size: Int
    public let parentID: String?
    public let parentNumber: Int?
    public let rootID: String

    public init(position: Int, size: Int, parentID: String?, parentNumber: Int?, rootID: String) {
        self.position = position
        self.size = size
        self.parentID = parentID
        self.parentNumber = parentNumber
        self.rootID = rootID
    }
}

/// Stacked pull requests. A PR's parent is the PR in the same repository whose head branch is this PR's base
/// branch. Only simple chains count: a PR gets a position when the whole group of PRs linked to it through
/// parent and child links is one line. A fork (two PRs on one base), a shared head or a cycle leaves the
/// entire group without positions; a line of one is no stack. The graph covers every PR the fetch returned,
/// shown or not, so positions are true.
public enum Stacks {
    public static func compute(_ prs: [PullRequest]) -> [String: StackPosition] {
        let byID = Dictionary(prs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Who has which head, per repository. A fork's head lives elsewhere; only its name could collide.
        var heads: [String: [String]] = [:]
        for pr in prs where !pr.isCrossRepository {
            if let head = pr.headRef { heads[key(pr.repository, head), default: []].append(pr.id) }
        }
        var parent: [String: String] = [:]
        var children: [String: [String]] = [:]
        var tainted = Set<String>()
        for pr in prs {
            guard let base = pr.baseRef else { continue }
            let candidates = (heads[key(pr.repository, base)] ?? []).filter { $0 != pr.id }
            guard let first = candidates.first else { continue }
            if candidates.count > 1 {
                tainted.formUnion(candidates)
                tainted.insert(pr.id)
            }
            parent[pr.id] = first
            children[first, default: []].append(pr.id)
        }
        var positions: [String: StackPosition] = [:]
        var visited = Set<String>()
        for pr in prs where !visited.contains(pr.id) {
            let group = component(of: pr.id, parent: parent, children: children)
            visited.formUnion(group)
            let roots = group.filter { parent[$0] == nil }
            guard group.count > 1, group.isDisjoint(with: tainted), roots.count == 1,
                group.allSatisfy({ (children[$0] ?? []).count <= 1 }), let root = roots.first
            else { continue }
            var chain = [root]
            while let last = chain.last, let next = children[last]?.first, !chain.contains(next) { chain.append(next) }
            guard chain.count == group.count else { continue }
            for (index, id) in chain.enumerated() {
                let parentID = index == 0 ? nil : chain[index - 1]
                positions[id] = StackPosition(
                    position: index + 1, size: chain.count, parentID: parentID,
                    parentNumber: parentID.flatMap { byID[$0]?.number }, rootID: root)
            }
        }
        return positions
    }

    private static func key(_ repository: String, _ ref: String) -> String { "\(repository)\u{0}\(ref)" }

    /// Every PR reachable through parent and child links.
    private static func component(of id: String, parent: [String: String], children: [String: [String]]) -> Set<String>
    {
        var seen: Set<String> = [id]
        var queue = [id]
        while let current = queue.popLast() {
            var neighbors = children[current] ?? []
            if let up = parent[current] { neighbors.append(up) }
            for neighbor in neighbors where !seen.contains(neighbor) {
                seen.insert(neighbor)
                queue.append(neighbor)
            }
        }
        return seen
    }
}
