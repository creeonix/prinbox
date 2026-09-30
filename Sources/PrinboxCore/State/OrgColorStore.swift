import Foundation
import Observation

/// A fixed palette index per organization, assigned the first time an org is seen and saved, so an org
/// keeps its color across sessions. Core deals in indices; the app's Theme owns the colors.
@MainActor
@Observable
public final class OrgColorStore {
    public static let key = "orgColors"
    public static let paletteSize = 8

    public private(set) var indices: [String: Int]
    @ObservationIgnored private let defaults: KeyValueStoring

    public init(defaults: KeyValueStoring) {
        self.defaults = defaults
        indices = defaults.object(forKey: Self.key) as? [String: Int] ?? [:]
    }

    /// 0 for an org that was never assigned; call `assign` when the inbox changes.
    public func index(for org: String) -> Int { indices[org] ?? 0 }

    /// Gives every new org the lowest index among the least-used ones, in the order given.
    public func assign(_ orgs: some Sequence<String>) {
        let assigned = orgs.reduce(into: indices) { table, org in
            guard table[org] == nil else { return }
            table[org] = Self.leastUsedIndex(in: table)
        }
        guard assigned != indices else { return }
        indices = assigned
        defaults.set(assigned, forKey: Self.key)
    }

    static func leastUsedIndex(in table: [String: Int]) -> Int {
        let uses = table.values.reduce(into: [Int](repeating: 0, count: paletteSize)) { $0[$1 % paletteSize] += 1 }
        return uses.indices.min { uses[$0] < uses[$1] } ?? 0
    }
}
