import PrinboxCore
import SwiftUI

/// A mark as drawn: symbol, color, optional count before it, tooltip.
struct MarkGlyph {
    let symbol: String
    let color: Color
    let count: Int?
    let help: String
    var countColor: Color = .secondary

    /// The comment bubble. On a row whose reason highlights the conversation (Awaiting your reply, Open
    /// threads) the bubble and its count take the accent color and the tooltip names the threads waiting.
    static func comments(_ count: Int?, pending: Int = 0, highlighted: Bool = false) -> MarkGlyph? {
        count.map {
            MarkGlyph(
                symbol: "bubble.left", color: highlighted ? .accentColor : .secondary, count: $0,
                help: RowMarks.commentsHelp($0, pending: pending), countColor: highlighted ? .accentColor : .secondary)
        }
    }

    static func ci(_ mark: CIMark?) -> MarkGlyph? {
        mark.map { mark in
            switch mark {
            case .passed: MarkGlyph(symbol: "checkmark.circle.fill", color: .green, count: nil, help: mark.help)
            case .failed: MarkGlyph(symbol: "xmark.circle.fill", color: .red, count: nil, help: mark.help)
            case .running: MarkGlyph(symbol: "circle.dotted", color: .orange, count: nil, help: mark.help)
            }
        }
    }

    static func review(_ mark: ReviewMark?) -> MarkGlyph? {
        mark.map { mark in
            switch mark {
            case .approved: MarkGlyph(symbol: "person.fill.checkmark", color: .green, count: nil, help: mark.help)
            case .changesRequested: MarkGlyph(symbol: "person.fill.xmark", color: .red, count: nil, help: mark.help)
            }
        }
    }

    static func merge(_ mark: MergeMark?) -> MarkGlyph? {
        mark.map { mark in
            switch mark {
            case .ready: MarkGlyph(symbol: "arrow.triangle.merge", color: .green, count: nil, help: mark.help)
            case .conflicts: MarkGlyph(symbol: "arrow.triangle.merge", color: .red, count: nil, help: mark.help)
            }
        }
    }
}

/// One fixed-width cell of the mark block, trailing aligned so icons line up down the list. An empty
/// cell keeps its width but has no tooltip.
struct MarkCell: View {
    static let countWidth: CGFloat = 36
    static let iconWidth: CGFloat = 16

    let glyph: MarkGlyph?
    let width: CGFloat

    var body: some View {
        if let glyph {
            HStack(spacing: 3) {
                if let count = glyph.count {
                    Text("\(count)").foregroundStyle(glyph.countColor).monospacedDigit()
                }
                Image(systemName: glyph.symbol).foregroundStyle(glyph.color)
            }
            .frame(width: width, alignment: .trailing)
            .help(glyph.help)
            .accessibilityLabel(glyph.help)
        } else {
            Color.clear.frame(width: width, height: 1)
        }
    }
}

/// The marks on one line of a full row: the title line carries comments and review, the fact line CI
/// and merge. Both lines use the same cell widths, which makes the 2 by 2 block.
struct MarksLineView: View {
    let marks: RowMarks
    let top: Bool
    var pending = 0
    var highlighted = false

    var body: some View {
        HStack(spacing: 6) {
            MarkCell(
                glyph: top ? .comments(marks.comments, pending: pending, highlighted: highlighted) : .ci(marks.ci),
                width: MarkCell.countWidth)
            MarkCell(glyph: top ? .review(marks.review) : .merge(marks.merge), width: MarkCell.iconWidth)
        }
        .font(.system(size: 11, weight: .medium))
    }
}

/// Compact rows: the same cells on one line, in the block's reading order.
struct MarksInlineView: View {
    let marks: RowMarks
    var pending = 0
    var highlighted = false

    var body: some View {
        HStack(spacing: 6) {
            MarkCell(
                glyph: .comments(marks.comments, pending: pending, highlighted: highlighted), width: MarkCell.countWidth
            )
            MarkCell(glyph: .review(marks.review), width: MarkCell.iconWidth)
            MarkCell(glyph: .ci(marks.ci), width: MarkCell.iconWidth)
            MarkCell(glyph: .merge(marks.merge), width: MarkCell.iconWidth)
        }
        .font(.system(size: 11, weight: .medium))
    }
}
