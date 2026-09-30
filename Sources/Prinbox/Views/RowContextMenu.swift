import PrinboxCore
import SwiftUI

/// Right-click menu shared by both row styles.
struct RowContextMenu: View {
    let row: InboxRow
    let isSnoozed: Bool
    let actions: PopoverActions

    var body: some View {
        Button("Open on GitHub") { actions.open(row.pullRequest.url) }
        if isSnoozed {
            Button("Unsnooze") { actions.unsnooze(row.id) }
        } else {
            Button("Snooze until it changes") { actions.snooze(row.id) }
        }
        Divider()
        Button("Copy link") { actions.copyLink(row.pullRequest.url) }
    }
}
