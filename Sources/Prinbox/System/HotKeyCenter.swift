import Carbon.HIToolbox
import PrinboxCore

/// A global shortcut via Carbon RegisterEventHotKey. It needs no Accessibility permission.
/// Registration is exclusive: it fails when another app holds the same shortcut exclusively (for example a
/// second prinbox) and keeps later exclusive registrations out. Carbon lets apps that register
/// non-exclusively (Pullover, most Electron apps) share a shortcut undetectably; both then respond.
/// The coordinator keeps one instance for the whole app run, so the unretained Carbon context stays valid.
@MainActor
final class HotKeyCenter {
    private static let signature: OSType = 0x5052_4E42  // "PRNB"

    private let onPress: @MainActor () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init(onPress: @escaping @MainActor () -> Void) {
        self.onPress = onPress
        installHandler()
    }

    /// Replaces the current shortcut. nil removes it. Returns false when the shortcut is unavailable.
    func register(_ spec: HotKeySpec?) -> Bool {
        unregister()
        guard let spec else { return true }
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(
            spec.keyCode, spec.carbonModifiers, id, GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive),
            &hotKeyRef)
        return status == noErr
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    private func installHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, context in
                guard let context else { return OSStatus(eventNotHandledErr) }
                let center = Unmanaged<HotKeyCenter>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated { center.onPress() }
                return noErr
            }, 1, &eventType, context, &handlerRef)
    }
}
