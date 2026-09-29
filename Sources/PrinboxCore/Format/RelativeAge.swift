import Foundation

public enum RelativeAge {
    /// Floored age, using the thresholds of the sketchybar prototype: <1m, Nm, Nh (under 48 h), Nd.
    /// Future timestamps (clock skew) read as "<1m".
    public static func format(from start: Date, to now: Date) -> String {
        let minutes = Int(max(0, now.timeIntervalSince(start)) / 60)
        if minutes < 1 { return "<1m" }
        if minutes < 60 { return "\(minutes)m" }
        if minutes < 48 * 60 { return "\(minutes / 60)h" }
        return "\(minutes / (24 * 60))d"
    }
}
