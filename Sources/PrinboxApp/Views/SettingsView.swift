import PrinboxCore
import SwiftUI

/// Settings live inside the popover. A separate window would be managed by the tiling window manager.
struct SettingsView: View {
    let state: PopoverState
    let hotKeys: HotKeySettings
    let loginItem: LoginItem
    let info: AppInfo
    let notifications: NotificationSettings
    let fetchSettings: FetchSettings
    let notifier: Notifier
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
            SettingRow(title: "Group by organization") {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { state.display.groupByOrganization },
                        set: { state.setGroupByOrganization($0) })
                )
                .toggleStyle(.switch)
                .labelsHidden()
            }
            SettingRow(title: "Show organization avatars") {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { state.display.showOrganizationAvatars },
                        set: { state.display.setShowOrganizationAvatars($0) })
                )
                .toggleStyle(.switch)
                .labelsHidden()
            }
            SettingRow(title: "Compact rows") {
                Toggle(
                    "",
                    isOn: Binding(get: { state.display.compactRows }, set: { state.display.setCompactRows($0) })
                )
                .toggleStyle(.switch)
                .labelsHidden()
            }
            SettingRow(title: "Follow review threads") {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { fetchSettings.followReviewThreads }, set: { actions.setFollowReviewThreads($0) })
                )
                .toggleStyle(.switch)
                .labelsHidden()
            }
            Text(
                fetchSettings.followReviewThreads
                    ? "Shows Replies to you and open threads on your PRs; snoozes wake on a reply, a new commit or a re-request."
                    : "A lighter refresh: rows only, and snoozes wake on any change."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            SettingRow(title: "Only direct review requests") {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { fetchSettings.scope.directReviewRequestsOnly },
                        set: { actions.setDirectReviewRequestsOnly($0) })
                )
                .toggleStyle(.switch)
                .labelsHidden()
            }
            Text("Requests that reach you through a team are left out").font(.caption).foregroundStyle(.secondary)
            SettingRow(title: "Hide draft pull requests") {
                Toggle("", isOn: Binding(get: { fetchSettings.scope.hideDrafts }, set: { actions.setHideDrafts($0) }))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            Text("Your own drafts stay").font(.caption).foregroundStyle(.secondary)
            SettingRow(title: "Notify about new review requests and replies") {
                Toggle("", isOn: Binding(get: { notifications.isEnabled }, set: { actions.setNotifications($0) }))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            if let note = notifier.status.note {
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
