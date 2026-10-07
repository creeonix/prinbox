import PrinboxCore
import SwiftUI

struct HeaderView: View {
    let state: PopoverState
    let actions: PopoverActions
    let anchor: MenuAnchor

    var body: some View {
        HStack(spacing: 8) {
            Text(
                RowText.header(
                    badgeCount: state.store.inbox?.badgeCount ?? 0, lastSuccess: state.store.lastSuccess,
                    needsSetup: state.store.needsSetup, newCount: state.newCount)
            )
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            Spacer()
            RepositoryMenuButton(
                state: state, actions: actions,
                symbol: state.hasDefaultRepositories
                    ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle",
                help: "Default repositories (F)", tint: state.hasDefaultRepositories ? .systemGray : nil,
                anchor: anchor)
            if state.store.isRefreshing {
                ProgressView().controlSize(.small)
            } else {
                IconButton(symbol: "arrow.clockwise", help: "Refresh (R)", action: actions.refresh)
            }
            IconButton(symbol: "gearshape", help: "Settings") { state.openSettings() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(.borderless)
            .help(help)
    }
}
