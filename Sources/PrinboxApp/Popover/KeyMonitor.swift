import AppKit
import PrinboxCore

/// A local keyDown monitor that exists only while the popover is open. The handler returns true to
/// consume the event.
@MainActor
final class KeyMonitor {
    private let handler: @MainActor (NSEvent) -> Bool
    private var token: Any?

    init(handler: @escaping @MainActor (NSEvent) -> Bool) { self.handler = handler }

    func install() {
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let consumed = MainActor.assumeIsolated { self.handler(event) }
            return consumed ? nil : event
        }
    }

    func remove() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }
}

extension HotKeyModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        let pairs: [(NSEvent.ModifierFlags, HotKeyModifiers)] = [
            (.control, .control), (.option, .option), (.shift, .shift), (.command, .command),
        ]
        self = pairs.filter { flags.contains($0.0) }.reduce(HotKeyModifiers()) { $0.union($1.1) }
    }
}
