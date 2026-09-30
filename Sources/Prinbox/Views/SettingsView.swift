import PrinboxCore
import SwiftUI

/// Settings live inside the popover. A separate window would be managed by the tiling window manager.
struct SettingsView: View {
    let state: PopoverState
    let hotKeys: HotKeySettings
    let loginItem: LoginItem
    let info: AppInfo
    let actions: PopoverActions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: { state.leaveSettings() }) { Label("Inbox", systemImage: "chevron.left") }
                .buttonStyle(.borderless)
            SettingRow(title: "Global shortcut") {
                ShortcutRecorderView(state: state, hotKeys: hotKeys, actions: actions)
            }
            if hotKeys.isUnavailable {
                Text("Shortcut unavailable (in use by another app)").font(.caption).foregroundStyle(.orange)
            }
            SettingRow(title: "Launch at login") {
                Toggle("", isOn: Binding(get: { loginItem.isEnabled }, set: { actions.setLaunchAtLogin($0) }))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            if let note = loginItem.note {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            InfoLine(label: "gh", value: info.ghPath ?? "not found")
            InfoLine(label: "Version", value: info.version)
            HStack {
                Spacer()
                Button("Quit PRInbox", action: actions.quit)
            }
        }
        .padding(14)
    }
}

struct SettingRow<Control: View>: View {
    let title: String
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack {
            Text(title).font(.system(size: 12))
            Spacer()
            control()
        }
    }
}

struct InfoLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
        }
        .font(.system(size: 11))
    }
}
