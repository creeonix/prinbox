import PrinboxCore
import SwiftUI

enum Theme {
    static func color(for tone: ReasonTone) -> Color {
        switch tone {
        case .attention: .accentColor
        case .failure: .red
        case .success: .green
        case .neutral: .secondary
        }
    }

    /// One color per `OrgColorStore` index. No red or green: those mean status on the marks.
    static let orgPalette: [Color] = [.indigo, .orange, .teal, .purple, .pink, .mint, .brown, .cyan]

    /// The modulo is kept non-negative, so a corrupted saved index picks a color instead of trapping.
    static func orgColor(_ index: Int) -> Color {
        let count = orgPalette.count
        return orgPalette[((index % count) + count) % count]
    }
}

/// Shared highlight for hover and keyboard selection.
struct RowHighlight: View {
    let isSelected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            .padding(.horizontal, 4)
    }
}
