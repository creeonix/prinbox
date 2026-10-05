import PrinboxCore
import SwiftUI

struct SectionView: View {
    let section: InboxSection
    let state: PopoverState
    let avatars: AvatarImages
    let actions: PopoverActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeaderView(
                section: section, isFolded: state.folds.isFolded(section.kind),
                isSelected: state.isSelected(.header(section.kind))
            ) {
                state.toggleFold(section.kind)
            }
            .id(InboxItemID.header(section.kind))
            .onHover { inside in if inside { state.select(.header(section.kind)) } }
            if !state.folds.isFolded(section.kind) {
                if state.showsSeparators {
                    ForEach(section.groups) { group in
                        OrgSeparatorView(group: group, color: Theme.orgColor(state.colors.index(for: group.org)))
                        ForEach(group.rows) { row in rowView(row) }
                    }
                } else if state.display.groupByOrganization {
                    ForEach(section.groups.flatMap(\.rows)) { row in rowView(row) }
                } else {
                    ForEach(section.rows) { row in rowView(row) }
                }
                if section.moreCount > 0 {
                    MoreRowView(count: section.moreCount, isSelected: state.isSelected(.more(section.kind))) {
                        actions.open(section.kind.moreURL)
                    }
                    .id(InboxItemID.more(section.kind))
                    .onHover { inside in if inside { state.select(.more(section.kind)) } }
                }
            }
        }
    }

    /// Waiting on others is always compact; "Compact rows" makes every section so.
    @ViewBuilder private func rowView(_ row: InboxRow) -> some View {
        let selected = state.isSelected(.row(row.id))
        Group {
            if section.kind.usesCompactRows || state.display.compactRows {
                CompactRowView(row: row, state: state, isSelected: selected) { actions.open(row.pullRequest.url) }
            } else {
                PullRequestRowView(row: row, state: state, avatars: avatars, isSelected: selected) {
                    actions.open(row.pullRequest.url)
                }
            }
        }
        .contextMenu { RowContextMenu(row: row, isSnoozed: state.store.state.isSnoozed(row.id), actions: actions) }
        .id(InboxItemID.row(row.id))
        .onHover { inside in if inside { state.select(.row(row.id)) } }
    }
}

struct SectionHeaderView: View {
    let section: InboxSection
    let isFolded: Bool
    let isSelected: Bool
    let onToggle: @MainActor () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Image(systemName: isFolded ? "chevron.right" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 12)
                Text(section.kind.title).font(.system(size: 12, weight: .semibold))
                Text("\(section.count)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.secondary.opacity(0.18)))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(RowHighlight(isSelected: isSelected))
        }
        .buttonStyle(.plain)
    }
}
