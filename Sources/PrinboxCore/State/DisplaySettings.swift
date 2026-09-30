import Foundation
import Observation

/// How the inbox is shown, persisted in user defaults.
@MainActor
@Observable
public final class DisplaySettings {
    public static let groupKey = "groupByOrganization"
    public static let orgAvatarsKey = "showOrganizationAvatars"

    public private(set) var groupByOrganization: Bool
    public private(set) var showOrganizationAvatars: Bool
    @ObservationIgnored private let defaults: KeyValueStoring

    public init(defaults: KeyValueStoring) {
        self.defaults = defaults
        groupByOrganization = defaults.object(forKey: Self.groupKey) as? Bool ?? false
        showOrganizationAvatars = defaults.object(forKey: Self.orgAvatarsKey) as? Bool ?? true
    }

    public func setGroupByOrganization(_ on: Bool) {
        groupByOrganization = on
        defaults.set(on, forKey: Self.groupKey)
    }

    public func setShowOrganizationAvatars(_ on: Bool) {
        showOrganizationAvatars = on
        defaults.set(on, forKey: Self.orgAvatarsKey)
    }
}
