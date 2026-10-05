import PrinboxCore
import SwiftUI

/// Scrolling list of sections. It measures its content so the popover is only as tall as needed (up to
/// `InboxView.maxHeight`), and scrolls to follow the keyboard selection.
struct InboxListView: View {
    let state: PopoverState
    let inbox: Inbox
    let avatars: AvatarImages
    let actions: PopoverActions

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(inbox.sections) { section in
                        SectionView(section: section, state: state, avatars: avatars, actions: actions)
                    }
                }
                .padding(.vertical, 6)
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(key: ContentHeightKey.self, value: geometry.size.height)
                    })
            }
            .onPreferenceChange(ContentHeightKey.self) { height in
                MainActor.assumeIsolated { state.contentHeight = height }
            }
            .onChange(of: state.selection.current) { _, id in
                if let id { proxy.scrollTo(id) }
            }
            .frame(height: min(max(state.contentHeight, 1), InboxView.maxHeight))
        }
    }
}

struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
