import PrinboxCore
import SwiftUI

/// Replaces the inbox while gh is missing or signed out: numbered steps with copyable commands, and a
/// footer that explains prinbox keeps checking by itself.
struct SetupView: View {
    let guide: SetupGuide
    let state: PopoverState
    let actions: PopoverActions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(guide.title, systemImage: "wrench.and.screwdriver")
                .font(.system(size: 14, weight: .semibold))
            Text(guide.summary)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(index + 1). \(step.text)").font(.system(size: 12, weight: .medium))
                    if let command = step.command {
                        CommandBox(command: command, state: state, actions: actions)
                    }
                }
            }
            if let link = guide.link {
                Button(link.title) { actions.open(link.url) }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
            }
            if let footnote = guide.footnote {
                VStack(alignment: .leading, spacing: 4) {
                    Text(footnote.text)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let command = footnote.command {
                        CommandBox(command: command, state: state, actions: actions)
                    }
                }
            }
            Divider()
            HStack {
                Text("PRInbox checks again every 10 seconds.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Check now", action: actions.refresh)
            }
        }
        .padding(14)
    }
}

/// A terminal command in a monospaced box with a Copy button.
struct CommandBox: View {
    let command: String
    let state: PopoverState
    let actions: PopoverActions

    var body: some View {
        HStack(spacing: 8) {
            Text(command)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 4)
            Button(state.copiedCommand == command ? "Copied" : "Copy") { actions.copy(command) }
                .controlSize(.small)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))
    }
}
