import PrinboxCore
import SwiftUI

/// Root of the popover. All state lives in `PopoverState`; there is no view-local state, because the
/// SwiftUI state macro plugin ships only with Xcode.
struct InboxView: View {
    static let width: CGFloat = 420
    static let maxHeight: CGFloat = 600

    let state: PopoverState
    let avatars: AvatarImages
    let hotKeys: HotKeySettings
    let loginItem: LoginItem
    let info: AppInfo
    let actions: PopoverActions

    var body: some View {
        VStack(spacing: 0) {
            if state.showingSettings {
                SettingsView(state: state, hotKeys: hotKeys, loginItem: loginItem, info: info, actions: actions)
            } else {
                HeaderView(state: state, actions: actions)
                WarningLinesView(lines: state.store.warningLines)
                Divider()
                content
            }
        }
        .frame(width: Self.width)
    }

    @ViewBuilder private var content: some View {
        if let inbox = state.store.inbox, !inbox.isEmpty {
            InboxListView(state: state, inbox: inbox, avatars: avatars, actions: actions)
        } else if state.store.inbox != nil {
            EmptyStateView()
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
