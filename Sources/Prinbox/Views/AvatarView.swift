import PrinboxCore
import SwiftUI

/// Round 28 pt avatar with an initials placeholder until the image loads, and an optional org badge.
struct AvatarView: View {
    static let size: CGFloat = 28

    let login: String
    let url: URL?
    let avatars: AvatarImages
    let badge: OrgBadgeView?

    var body: some View {
        Group {
            if let image = avatars.image(for: login) {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                ZStack {
                    Circle().fill(Color.secondary.opacity(0.2))
                    Text(RowText.initials(login))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: Self.size, height: Self.size)
        .clipShape(Circle())
        .overlay(alignment: .bottomTrailing) {
            if let badge { badge.offset(x: 3, y: 3) }
        }
        .task(id: login) { await avatars.load(login: login, url: url) }
    }
}
