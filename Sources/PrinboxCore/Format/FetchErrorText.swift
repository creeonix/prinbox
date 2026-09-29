import Foundation

extension FetchError {
    /// One line for the popover warning line and the status item tooltip.
    public func message(lastSuccess: Date?, timeZone: TimeZone = .current) -> String {
        switch self {
        case .ghNotFound:
            "gh not found: brew install gh"
        case .loggedOut:
            "gh is not logged in: run gh auth login"
        case .offline:
            lastSuccess.map { "Offline, showing data from \(ClockText.hhmm($0, timeZone: timeZone))" } ?? "Offline"
        case .timedOut:
            "GitHub did not answer in time"
        case .rateLimited(let resetAt):
            resetAt.map { "Rate limited until \(ClockText.hhmm($0, timeZone: timeZone))" } ?? "Rate limited by GitHub"
        case .badResponse:
            "Unexpected response from gh"
        case .other(let message):
            message
        }
    }
}
