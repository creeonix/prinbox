import Foundation

/// A release version such as 0.2.0, from `CFBundleShortVersionString` or a release tag (a leading "v"
/// is allowed). "dev" builds and suffixed tags (v0.3.0-beta) do not parse, so they are never compared.
public struct AppVersion: Sendable, Equatable, Comparable, CustomStringConvertible {
    public let components: [Int]

    public init?(_ string: String) {
        let plain = string.hasPrefix("v") ? String(string.dropFirst()) : string
        let parts = plain.split(separator: ".", omittingEmptySubsequences: false)
        let digitsOnly = parts.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }
        let numbers = parts.map { Int($0) }
        guard !plain.isEmpty, digitsOnly, numbers.allSatisfy({ $0 != nil }) else { return nil }
        components = numbers.compactMap { $0 }
    }

    public var description: String { components.map(String.init).joined(separator: ".") }

    /// Missing components count as 0, so 1.0 equals 1.0.0.
    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool { padded(lhs, rhs).0 == padded(lhs, rhs).1 }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let (left, right) = padded(lhs, rhs)
        return left.lexicographicallyPrecedes(right)
    }

    private static func padded(_ lhs: AppVersion, _ rhs: AppVersion) -> ([Int], [Int]) {
        let count = max(lhs.components.count, rhs.components.count)
        return (
            lhs.components + Array(repeating: 0, count: count - lhs.components.count),
            rhs.components + Array(repeating: 0, count: count - rhs.components.count)
        )
    }
}
