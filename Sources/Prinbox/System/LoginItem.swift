import Foundation
import Observation
import ServiceManagement

/// Launch at login via SMAppService.mainApp. The registration belongs to the app copy that made it, so
/// it is only offered from /Applications.
@MainActor
@Observable
final class LoginItem {
    private(set) var status: SMAppService.Status = SMAppService.mainApp.status
    private(set) var lastError: String?

    var isEnabled: Bool { status == .enabled || status == .requiresApproval }

    var isInstalled: Bool { Bundle.main.bundleURL.path.hasPrefix("/Applications/") }

    /// A hint under the toggle, or nil when everything is fine.
    var note: String? {
        if let lastError { return lastError }
        if !isInstalled { return "Install to /Applications (make install) to use this." }
        if status == .requiresApproval { return "Approve prinbox in System Settings > General > Login Items." }
        return nil
    }

    func setEnabled(_ enabled: Bool) {
        guard isInstalled else {
            lastError = "Install to /Applications (make install) first."
            return
        }
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            lastError = nil
        } catch {
            lastError = "Could not update the login item: \(error.localizedDescription)"
        }
        status = SMAppService.mainApp.status
    }
}
