import Foundation

/// What a fetch asked for: Follow review threads and the scope. A cached fingerprint or arrivals baseline is
/// trusted only for the same shape (spec 4.3); a change of either means one full fetch and a quiet start.
public struct FetchShape: Codable, Equatable, Sendable {
    public var includeConversation: Bool
    public var scope: SearchScope

    public init(includeConversation: Bool = true, scope: SearchScope = .none) {
        self.includeConversation = includeConversation
        self.scope = scope
    }
}
