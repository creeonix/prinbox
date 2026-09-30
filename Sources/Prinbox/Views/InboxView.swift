import PrinboxCore
import SwiftUI

/// Root of the popover. All state lives in `PopoverState`; there is no view-local state, because the
/// SwiftUI state macro plugin ships only with Xcode.
struct InboxView: View {
    static let width: CGFloat = 460
    static let maxHeight: CGFloat = 600

    let state: PopoverState
    let avatars: AvatarImages
    let hotKeys: HotKeySettings
    let loginItem: LoginItem
    let info: AppInfo
    let updates: UpdateStore
    let notifications: NotificationSettings
    let notifier: Notifier
    let actions: PopoverActions

    var body: some View {
        VStack(spacing: 0) {
            if state.showingSettings {
                SettingsView(
                    state: state, hotKeys: hotKeys, loginItem: loginItem, info: info, notifications: notifications,
                    notifier: notifier, actions: actions)
            } else {
                HeaderView(state: state, actions: actions)
                WarningLinesView(lines: state.store.warningLines)
                UpdateLineView(updates: updates, actions: actions)
                Divider()
                content
            }
        }
        .frame(width: Self.width)
    }

    /// A missing or signed-out gh replaces the list with setup steps; stale PRs would be misleading then.
    @ViewBuilder private var content: some View {
        if let guide = state.store.error.flatMap({ SetupGuide.for($0, ghOverride: info.ghOverride) }) {
            SetupView(guide: guide, state: state, actions: actions)
        } else if let inbox = state.store.inbox, !inbox.isEmpty {
            InboxListView(state: state, inbox: inbox, avatars: avatars, actions: actions)
        } else if state.store.inbox != nil {
            EmptyStateView()
        } else if state.store.error != nil {
            UnavailableView()
        } else {
            ProgressView().padding(24)
        }
    }
}

struct WarningLinesView: View {
    let lines: [String]

    var body: some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(lines, id: \.self) { line in
                    Label(line, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .help(line)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
    }
}

/// First load failed for a reason that needs no setup (offline, timeout); the warning line says why.
struct UnavailableView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "icloud.slash").font(.system(size: 24)).foregroundStyle(.secondary)
            Text("Couldn't load your inbox").font(.headline)
            Text("PRInbox tries again on the next refresh, or press R.").font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle").font(.system(size: 24)).foregroundStyle(.secondary)
            Text("Inbox zero").font(.headline)
            Text("Nothing waiting on you.").font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
    }
}
