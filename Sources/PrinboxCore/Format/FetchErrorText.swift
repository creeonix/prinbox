import Foundation

extension FetchError {
    /// One line for the popover warning line and the status item tooltip.
    public func message(lastSuccess: Date?, timeZone: TimeZone = .current) -> String {
        switch self {
        case .ghNotFound:
            "gh not installed, click for setup"
        case .loggedOut:
            "gh not signed in, click for setup"
        case .offline:
            lastSuccess.map { "Offline, showing data from \(ClockText.hhmm($0, timeZone: timeZone))" } ?? "Offline"
        case .timedOut:
            "GitHub did not answer in time"
        case .rateLimited(let resetAt):
            resetAt.map { "Rate limited until \(ClockText.hhmm($0, timeZone: timeZone))" } ?? "Rate limited by GitHub"
        case .badResponse:
            "Unexpected response from gh"
        case .githubUnavailable(let status):
            lastSuccess.map {
                "GitHub is having trouble (HTTP \(status)), showing data from \(ClockText.hhmm($0, timeZone: timeZone))"
            } ?? "GitHub is having trouble (HTTP \(status))"
        case .other(let message):
            message
        }
    }

    public static let statusPage = URL(string: "https://www.githubstatus.com")!

    /// Where to look when GitHub itself is the problem; nil for every other error.
    public var helpURL: URL? {
        if case .githubUnavailable = self { return Self.statusPage }
        return nil
    }
}
