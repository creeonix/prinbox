import Foundation
import Observation

/// Which sections are folded, persisted through `KeyValueStoring` (settings.json in the app).
@MainActor
@Observable
public final class FoldStore {
    public nonisolated static let key = "foldedSections"
    /// First run: only "Needs your review" is open, as in the sketchybar prototype.
    public static let defaultFolded: Set<SectionKind> = [.takeAnotherLook, .mentions, .yourPRs, .waitingOnOthers]

    public private(set) var folded: Set<SectionKind>
    @ObservationIgnored private let defaults: KeyValueStoring

    public init(defaults: KeyValueStoring) {
        self.defaults = defaults
        let stored = defaults.object(forKey: Self.key) as? [String]
        folded = stored.map { Set($0.compactMap(SectionKind.init(rawValue:))) } ?? Self.defaultFolded
    }

    public func isFolded(_ kind: SectionKind) -> Bool { folded.contains(kind) }

    public func toggle(_ kind: SectionKind) {
        folded = folded.symmetricDifference([kind])
        defaults.set(folded.map(\.rawValue).sorted(), forKey: Self.key)
    }
}
