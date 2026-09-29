import PrinboxCore
import SwiftUI

/// Shows the shortcut. Click it, then press a new one. Esc cancels. The popover's key monitor does the
/// capturing (see AppCoordinator.recordShortcut).
struct ShortcutRecorderView: View {
    let state: PopoverState
    let hotKeys: HotKeySettings
    let actions: PopoverActions

    var body: some View {
        HStack(spacing: 6) {
            Button(action: actions.toggleShortcutRecording) {
                Text(label)
                    .font(.system(size: 12, weight: .medium).monospaced())
                    .frame(minWidth: 110)
            }
            .help("Click, then press the new shortcut. Esc cancels.")
            if hotKeys.spec != nil && !state.isRecordingShortcut {
                Button(action: { actions.setShortcut(nil) }) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .help("Remove shortcut")
            }
        }
    }

    private var label: String {
        if state.isRecordingShortcut { return "Press shortcut…" }
        return hotKeys.spec?.displayString ?? "None"
    }
}
