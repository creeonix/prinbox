import PrinboxCore
import SwiftUI

/// The org avatar in the corner of the author avatar: a rounded square for organizations, a circle for
/// users, filled with the org color and initial until the image loads (always, in demo mode).
struct OrgBadgeView: View {
    static let size: CGFloat = 13

    let org: String
    let url: URL?
    let isOrganization: Bool
    let color: Color
    let avatars: AvatarImages

    var body: some View {
        Group {
            if let image = avatars.image(for: org) {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                ZStack {
                    color
                    Text(RowText.initials(String(org.prefix(1))))
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: Self.size, height: Self.size)
        .clipShape(shape)
        .overlay(shape.stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
        .task(id: org) { await avatars.load(login: org, url: url) }
    }

    private var shape: AnyShape {
        isOrganization ? AnyShape(RoundedRectangle(cornerRadius: 3.5)) : AnyShape(Circle())
    }
}

/// Thin separator above each org group: color dot, org, count, hairline.
struct OrgSeparatorView: View {
    let group: OrgGroup
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(group.org).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            Text("\(group.rows.count)").font(.system(size: 11).monospacedDigit()).foregroundStyle(.tertiary)
            Rectangle().fill(Color.secondary.opacity(0.18)).frame(height: 1)
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }
}
