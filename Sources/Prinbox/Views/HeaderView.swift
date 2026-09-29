import PrinboxCore
import SwiftUI

struct HeaderView: View {
    let state: PopoverState
    let actions: PopoverActions

    var body: some View {
        HStack(spacing: 8) {
            Text(RowText.header(badgeCount: state.store.inbox?.badgeCount ?? 0, lastSuccess: state.store.lastSuccess))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if state.store.isRefreshing {
                ProgressView().controlSize(.small)
            } else {
                IconButton(symbol: "arrow.clockwise", help: "Refresh (R)", action: actions.refresh)
            }
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
