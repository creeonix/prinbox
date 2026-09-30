import PrinboxCore
import SwiftUI

/// One accent-colored line under the header while a newer PRInbox exists; clicking opens its page.
struct UpdateLineView: View {
    let updates: UpdateStore
    let actions: PopoverActions

    var body: some View {
        if let release = updates.available {
            Button(action: { actions.open(release.url) }) {
                Label(
                    "PRInbox \(release.displayVersion) is available",
                    systemImage: "arrow.down.circle"
                )
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
            .help("Open the release page")
        }
    }
}
