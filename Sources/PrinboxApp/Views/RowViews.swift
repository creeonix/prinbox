import PrinboxCore
import SwiftUI

struct PullRequestRowView: View {
    let row: InboxRow
    let state: PopoverState
    let avatars: AvatarImages
    let isSelected: Bool
    let onOpen: @MainActor () -> Void

    var body: some View {
        let pr = row.pullRequest
        let marks = RowMarks.marks(for: pr)
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 10) {
                AvatarView(login: pr.authorLogin, url: pr.avatarURL, avatars: avatars, badge: badge)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(RowText.title(pr))
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 4)
                        MarksLineView(
                            marks: marks, top: true, pending: row.pendingReplies,
                            highlighted: row.classification.reason.highlightsComments)
                    }
                    // The schedule only triggers a redraw each minute. Its entry date is the start of the minute,
                    // up to 59 s in the past, which would floor "5h" to "4h", so ages use the current time.
                    TimelineView(.everyMinute) { _ in
                        HStack(spacing: 6) {
                            Text(RowText.meta(row, now: Date(), showOrg: state.showsOrgNames))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            MarksLineView(marks: marks, top: false)
                        }
                        .font(.system(size: 11))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(RowHighlight(isSelected: isSelected))
            .overlay(alignment: .leading) {
                if state.isNew(row) { NewBar() }
            }
            .opacity(pr.isDraft ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .help(RowText.help(row))
    }

    private var badge: OrgBadgeView? {
        guard state.showsOrgBadges else { return nil }
        let pr = row.pullRequest
        return OrgBadgeView(
            org: pr.ownerLogin, url: pr.ownerAvatarURL, isOrganization: pr.ownerIsOrganization,
            color: Theme.orgColor(state.colors.index(for: pr.ownerLogin)), avatars: avatars)
    }
}

/// One line: title, a fixed trailer (repo, Draft or Snoozed, and the age in the compact layout), marks.
/// Used by Waiting on others always and by every section when "Compact rows" is on.
struct CompactRowView: View {
    let row: InboxRow
    let state: PopoverState
    let isSelected: Bool
    let onOpen: @MainActor () -> Void

    var body: some View {
        let snoozed = row.classification.reason == .snoozed
        Button(action: onOpen) {
            HStack(spacing: 6) {
                Text(RowText.title(row.pullRequest))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(-1)
                if state.showsCompactAge(row.classification.section) {
                    TimelineView(.everyMinute) { _ in trailer(age: RowText.compactAge(row, now: Date())) }
                } else {
                    trailer(age: nil)
                }
                Spacer(minLength: 4)
                MarksInlineView(
                    marks: RowMarks.marks(for: row.pullRequest), pending: row.pendingReplies,
                    highlighted: row.classification.reason.highlightsComments)
            }
            .font(.system(size: 12))
            .padding(.leading, 30)
            .padding(.trailing, 12)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .background(RowHighlight(isSelected: isSelected))
            .overlay(alignment: .leading) {
                if state.isNew(row) { NewBar() }
                if snoozed { SnoozeGlyph().padding(.leading, 12) }
            }
            .opacity(row.pullRequest.isDraft || snoozed ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .help(RowText.help(row))
    }

    private func trailer(age: String?) -> some View {
        Text(RowText.compactTrailer(row, showOrg: state.showsOrgNames, age: age))
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .fixedSize()
    }
}

struct MoreRowView: View {
    let count: Int
    let isSelected: Bool
    let onOpen: @MainActor () -> Void

    var body: some View {
        Button(action: onOpen) {
            Text(RowText.more(count))
                .font(.system(size: 12))
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 50)
                .padding(.trailing, 12)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .background(RowHighlight(isSelected: isSelected))
        }
        .buttonStyle(.plain)
    }
}

/// The "new since last look" mark: a thin accent bar at the row's leading edge, the same in both row styles.
struct NewBar: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(Color.accentColor)
            .frame(width: 3)
            .padding(.vertical, 4)
            .accessibilityLabel("New since last look")
    }
}

/// Marks a snoozed row inside its indent.
struct SnoozeGlyph: View {
    var body: some View {
        Image(systemName: "moon.zzz.fill")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .accessibilityLabel("Snoozed")
    }
}
