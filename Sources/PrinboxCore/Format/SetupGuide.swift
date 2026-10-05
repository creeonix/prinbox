import Foundation

public struct SetupStep: Equatable, Sendable {
    public let text: String
    /// A command to run in a terminal, shown with a Copy button.
    public let command: String?
}

public struct SetupLink: Equatable, Sendable {
    public let title: String
    public let url: URL
}

/// What to do when gh is missing or signed out: shown as the popover's setup panel and printed by
/// `--print`. Other errors need no setup and keep the normal warning line.
public struct SetupGuide: Equatable, Sendable {
    public static let settingsPath = "~/.config/prinbox/settings.json"

    public let title: String
    public let summary: String
    public let steps: [SetupStep]
    public let link: SetupLink?
    public let footnote: SetupStep?

    public static func `for`(_ error: FetchError, ghOverride: String?) -> SetupGuide? {
        switch error {
        case .ghNotFound: ghOverride.map(missingOverride) ?? missingGh
        case .loggedOut: signedOut
        default: nil
        }
    }

    static let missingGh = SetupGuide(
        title: "Install the GitHub CLI",
        summary: "PRInbox reads your pull requests through gh, GitHub's command-line tool. It never sees your token.",
        steps: [
            SetupStep(text: "Install gh", command: "brew install gh"),
            SetupStep(text: "Sign in to GitHub", command: "gh auth login"),
        ],
        link: SetupLink(title: "Other ways to install gh", url: URL(string: "https://cli.github.com")!),
        footnote: SetupStep(text: "Installed gh somewhere else? Set ghPath in \(settingsPath)", command: nil))

    static func missingOverride(_ path: String) -> SetupGuide {
        SetupGuide(
            title: "gh not found",
            summary: "PRInbox is set to use gh at \(path), but nothing runnable is there.",
            steps: [
                SetupStep(
                    text: "Remove ghPath from \(settingsPath) to use gh from Homebrew or PATH", command: nil),
                SetupStep(text: "Or install gh", command: "brew install gh"),
            ],
            link: nil, footnote: nil)
    }

    static let signedOut = SetupGuide(
        title: "Sign in to the GitHub CLI",
        summary: "gh is installed but not signed in to GitHub, or its sign-in has expired.",
        steps: [
            SetupStep(
                text: "Run this in a terminal, choose GitHub.com, then \"Login with a web browser\"",
                command: "gh auth login")
        ],
        link: nil,
        footnote: SetupStep(
            text: "If your organization uses single sign-on, authorize gh for it when the browser asks.", command: nil))

    /// The guide as terminal text for `Prinbox --print`.
    public var plainText: String {
        let stepLines = steps.enumerated().flatMap { index, step in
            ["\(index + 1). \(step.text)\(step.command == nil ? "" : ":")"] + Self.commandLines(step.command)
        }
        let linkLines = link.map { ["", "\($0.title): \($0.url.absoluteString)"] } ?? []
        let footnoteLines =
            footnote.map { ["", $0.text + ($0.command == nil ? "" : ":")] + Self.commandLines($0.command) } ?? []
        return ([title, summary, ""] + stepLines + linkLines + footnoteLines).joined(separator: "\n")
    }

    private static func commandLines(_ command: String?) -> [String] {
        command.map { ["     \($0)"] } ?? []
    }
}

extension FetchError {
    /// gh is missing or signed out: the user has to act before anything can load.
    public var needsSetup: Bool {
        self == .ghNotFound || self == .loggedOut
    }
}
