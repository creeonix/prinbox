import PrinboxCore
import SwiftUI

/// Right-click menu shared by both row styles. A Reviewed row has no Snooze item: it has nothing to wait for
/// (ruling 12.10).
struct RowContextMenu: View {
    let row: InboxRow
    let isSnoozed: Bool
    let actions: PopoverActions

    var body: some View {
        Button("Open on GitHub") { actions.open(row.openURL) }
        if row.classification.section != .reviewed {
            if isSnoozed {
                Button("Unsnooze") { actions.unsnooze(row.id) }
            } else {
                Button("Snooze until it changes") { actions.snooze(row.id) }
            }
        }
        Divider()
        Button("Copy link") { actions.copyLink(row.pullRequest.url) }
    }
}
