import PrinboxCore
import SwiftUI

struct PullRequestRowView: View {
    let row: InboxRow
    let avatars: AvatarImages
    let isSelected: Bool
    let onOpen: @MainActor () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 10) {
                AvatarView(login: row.pullRequest.authorLogin, url: row.pullRequest.avatarURL, avatars: avatars)
                VStack(alignment: .leading, spacing: 2) {
                    Text(RowText.title(row.pullRequest))
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    TimelineView(.everyMinute) { context in
                        HStack(spacing: 0) {
                            Text(RowText.meta(row, now: context.date) + " · ").foregroundStyle(.secondary)
                            Text(row.classification.reason.rawValue)
                                .foregroundStyle(Theme.color(for: row.classification.reason.tone))
                        }
                        .font(.system(size: 11))
                        .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(RowHighlight(isSelected: isSelected))
            .opacity(row.pullRequest.isDraft ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .help(row.pullRequest.repository)
    }
}

struct CompactRowView: View {
    let row: InboxRow
    let isSelected: Bool
    let onOpen: @MainActor () -> Void

    var body: some View {
        Button(action: onOpen) {
            Text(RowText.compact(row))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 30)
                .padding(.trailing, 12)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .background(RowHighlight(isSelected: isSelected))
                .opacity(row.pullRequest.isDraft ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .help(row.pullRequest.repository)
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
