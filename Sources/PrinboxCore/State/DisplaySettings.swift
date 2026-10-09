import Foundation
import Observation

/// How a row shows your verdict (spec 0.8 4.1): not at all, a faint background, or the title's color. The
/// settings value for "not at all" is "none"; the case is `plain` so it never reads as `Optional.none`.
public enum RowColor: String, CaseIterable, Sendable {
    case plain = "none"
    case background
    case title
}

/// How the inbox is shown, persisted through `KeyValueStoring` (settings.json in the app).
@MainActor
@Observable
public final class DisplaySettings {
    public nonisolated static let groupKey = "groupByOrganization"
    public nonisolated static let orgAvatarsKey = "showOrganizationAvatars"
    public nonisolated static let compactKey = "compactRows"
    public nonisolated static let rowColorKey = "rowColor"
    public nonisolated static let sinceReviewKey = "sinceReviewLine"
    public nonisolated static let showReviewedKey = "showReviewed"

    public private(set) var groupByOrganization: Bool
    public private(set) var showOrganizationAvatars: Bool
    public private(set) var compactRows: Bool
    public private(set) var rowColor: RowColor
    public private(set) var sinceReviewLine: Bool
    public private(set) var showReviewed: Bool
    @ObservationIgnored private let defaults: KeyValueStoring

    public init(defaults: KeyValueStoring) {
        self.defaults = defaults
        groupByOrganization = defaults.object(forKey: Self.groupKey) as? Bool ?? false
        showOrganizationAvatars = defaults.object(forKey: Self.orgAvatarsKey) as? Bool ?? true
        compactRows = defaults.object(forKey: Self.compactKey) as? Bool ?? false
        rowColor =
            (defaults.object(forKey: Self.rowColorKey) as? String).flatMap(RowColor.init(rawValue:)) ?? .background
        sinceReviewLine = defaults.object(forKey: Self.sinceReviewKey) as? Bool ?? true
        showReviewed = defaults.object(forKey: Self.showReviewedKey) as? Bool ?? false
    }

    public func setGroupByOrganization(_ on: Bool) {
        groupByOrganization = on
        defaults.set(on, forKey: Self.groupKey)
    }

    public func setShowOrganizationAvatars(_ on: Bool) {
        showOrganizationAvatars = on
        defaults.set(on, forKey: Self.orgAvatarsKey)
    }

    public func setCompactRows(_ on: Bool) {
        compactRows = on
        defaults.set(on, forKey: Self.compactKey)
    }

    public func setRowColor(_ color: RowColor) {
        rowColor = color
        defaults.set(color.rawValue, forKey: Self.rowColorKey)
    }

    public func setSinceReviewLine(_ on: Bool) {
        sinceReviewLine = on
        defaults.set(on, forKey: Self.sinceReviewKey)
    }

    public func setShowReviewed(_ on: Bool) {
        showReviewed = on
        defaults.set(on, forKey: Self.showReviewedKey)
    }
}
