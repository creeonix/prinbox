import Foundation
import PrinboxCore

struct AppInfo {
    let ghPath: String?
    let version: String

    static func current(client: GhClient) -> AppInfo {
        AppInfo(
            ghPath: client.ghPath(),
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")
    }
}
