import Foundation
import Observation
import PrinboxCore

/// The gh path, the override in effect and the app version. `refresh` re-locates gh, so Settings shows
/// a gh installed after launch.
@MainActor
@Observable
final class AppInfo {
    private(set) var ghPath: String?
    let ghOverride: String?
    let version: String
    @ObservationIgnored private let client: GhClient

    init(client: GhClient) {
        self.client = client
        ghPath = client.ghPath()
        ghOverride = client.ghOverride
        version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    func refresh() { ghPath = client.ghPath() }
}
