import Foundation
import Observation

/// How the inbox is shown, persisted through `KeyValueStoring` (settings.json in the app).
@MainActor
@Observable
public final class DisplaySettings {
    public nonisolated static let groupKey = "groupByOrganization"
    public nonisolated static let orgAvatarsKey = "showOrganizationAvatars"
    public nonisolated static let compactKey = "compactRows"

    public private(set) var groupByOrganization: Bool
    public private(set) var showOrganizationAvatars: Bool
    public private(set) var compactRows: Bool
    @ObservationIgnored private let defaults: KeyValueStoring

    public init(defaults: KeyValueStoring) {
        self.defaults = defaults
        groupByOrganization = defaults.object(forKey: Self.groupKey) as? Bool ?? false
        showOrganizationAvatars = defaults.object(forKey: Self.orgAvatarsKey) as? Bool ?? true
        compactRows = defaults.object(forKey: Self.compactKey) as? Bool ?? false
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
}
