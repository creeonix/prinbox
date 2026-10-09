import PrinboxCore
import SwiftUI

enum Theme {
    /// One color per `OrgColorStore` index. No red or green: those mean status on the marks.
    static let orgPalette: [Color] = [.indigo, .orange, .teal, .purple, .pink, .mint, .brown, .cyan]

    /// The modulo is kept non-negative, so a corrupted saved index picks a color instead of trapping.
    static func orgColor(_ index: Int) -> Color {
        let count = orgPalette.count
        return orgPalette[((index % count) + count) % count]
    }

    /// The verdict's color on a row (spec 0.8 4.1): the marks' green and red.
    static func verdictColor(_ cue: VerdictCue) -> Color {
        switch cue {
        case .approved: .green
        case .changesRequested: .red
        }
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

/// The faint wash behind a row colored by your verdict; the hover and selection highlight draws over it.
struct VerdictWash: View {
    let color: Color?

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(color?.opacity(0.11) ?? Color.clear)
            .padding(.horizontal, 4)
    }
}
