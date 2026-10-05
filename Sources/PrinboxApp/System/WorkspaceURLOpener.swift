import AppKit
import PrinboxCore

struct WorkspaceURLOpener: URLOpening {
    func open(_ url: URL) async {
        await MainActor.run { _ = NSWorkspace.shared.open(url) }
    }
}
