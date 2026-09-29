import Foundation

/// Interprets GraphQL `errors` that came back next to (partial) `data`.
enum GraphQLErrors {
    static func isRateLimited(_ errors: [GraphQLError]) -> Bool {
        errors.contains { $0.type == "RATE_LIMITED" }
    }

    /// One readable warning per distinct error, in order.
    static func warnings(_ errors: [GraphQLError]) -> [String] {
        errors.map(warning(for:)).reduce(into: [String]()) { unique, line in
            if !unique.contains(line) { unique.append(line) }
        }
    }

    static func warning(for error: GraphQLError) -> String {
        if let org = restrictedOrg(error.message) {
            return "\(org) restricts gh (OAuth app access): results incomplete"
        }
        if error.message.contains("SAML") {
            return "An org requires SSO authorization for gh: results incomplete"
        }
        return "GitHub: " + String(error.message.prefix(120))
    }

    /// "the `acme` organization has enabled OAuth App access restrictions" -> "acme".
    static func restrictedOrg(_ message: String) -> String? {
        let pattern = /the `([^`]+)` organization has enabled OAuth App access restrictions/
        return message.firstMatch(of: pattern).map { String($0.1) }
    }
}
