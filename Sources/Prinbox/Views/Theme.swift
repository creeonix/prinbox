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
