import Foundation

/// What the default-repositories menu shows (spec 4.2): the owners and repositories the inbox knows, grouped by
/// owner, each marked pinned, covered by a pinned owner, or too long to pin. Pure: the shell renders it as a menu.
public struct RepositoryPicker: Equatable, Sendable {
    public struct Item: Equatable, Sendable, Identifiable {
        /// `owner/*` or `owner/name`.
        public let entry: String
        public let isPinned: Bool
        /// An `owner/name` whose `owner/*` is pinned: shown checked and dimmed, never written.
        public let isCovered: Bool
        /// Characters by which pinning this entry would push a search past the limit; 0 when it fits.
        public let overflow: Int
        public var id: String { entry }
        public var isEnabled: Bool { !isCovered && overflow == 0 }
    }

    public struct Group: Equatable, Sendable, Identifiable {
        public let owner: String
        public let items: [Item]
        public var id: String { owner }
    }

    public let groups: [Group]

    /// `known` holds `owner/name` strings (the last unfiltered fetch); the pins are `shape.scope.repositories`.
    public init(known: Set<String>, shape: FetchShape) {
        let pinned = shape.scope.repositories
        let pinnedLower = Set(pinned.map { $0.lowercased() })
        let pinnedOwners = Set(
            pinned.filter(RepositoryEntries.isWildcard).map { RepositoryEntries.owner(of: $0).lowercased() })
        var repositoriesByOwner: [String: Set<String>] = [:]
        var ownerSpelling: [String: String] = [:]
        // A pinned `owner/name` joins only when GitHub's spelling of it is not known (spec 4.2).
        let knownLower = Set(known.map { $0.lowercased() })
        let repositories = known.union(
            pinned.filter { !RepositoryEntries.isWildcard($0) && !knownLower.contains($0.lowercased()) })
        for repository in repositories.sorted() {
            let owner = RepositoryEntries.owner(of: repository)
            let key = owner.lowercased()
            ownerSpelling[key] = ownerSpelling[key] ?? owner
            repositoriesByOwner[key, default: []].insert(repository)
        }
        for entry in pinned where RepositoryEntries.isWildcard(entry) {
            let owner = RepositoryEntries.owner(of: entry)
            let key = owner.lowercased()
            ownerSpelling[key] = ownerSpelling[key] ?? owner
            repositoriesByOwner[key] = repositoriesByOwner[key] ?? []
        }
        func overflow(toggling entry: String) -> Int {
            var next = shape
            next.scope.repositories = RepositoryPicker.toggled(entry, in: pinned)
            return SearchQuery.overflow(includeInvolved: shape.includeConversation, scope: next.scope)
        }
        func item(_ entry: String) -> Item {
            let isPinned = pinnedLower.contains(entry.lowercased())
            let isCovered =
                !RepositoryEntries.isWildcard(entry)
                && pinnedOwners.contains(RepositoryEntries.owner(of: entry).lowercased())
            return Item(
                entry: entry, isPinned: isPinned, isCovered: isCovered,
                overflow: isPinned || isCovered ? 0 : overflow(toggling: entry))
        }
        groups = repositoriesByOwner.keys.sorted().map { key in
            let owner = ownerSpelling[key] ?? key
            let names = repositoriesByOwner[key, default: []].sorted { $0.lowercased() < $1.lowercased() }
            return Group(owner: owner, items: [item("\(owner)/*")] + names.map(item))
        }
    }

    /// The pins after a click on `entry`: an `owner/*` that is pinned is unpinned, else pinned (its repositories
    /// drop out as covered); an `owner/name` that is pinned is unpinned, else pinned; a covered one is left alone.
    /// The result is normalized.
    public static func toggled(_ entry: String, in pinned: [String]) -> [String] {
        let lower = entry.lowercased()
        if pinned.contains(where: { $0.lowercased() == lower }) {
            return RepositoryEntries.normalize(pinned.filter { $0.lowercased() != lower }).entries
        }
        let owner = RepositoryEntries.owner(of: entry).lowercased()
        let covered =
            !RepositoryEntries.isWildcard(entry)
            && pinned.contains {
                RepositoryEntries.isWildcard($0) && RepositoryEntries.owner(of: $0).lowercased() == owner
            }
        if covered { return pinned }
        return RepositoryEntries.normalize(pinned + [entry]).entries
    }
}
