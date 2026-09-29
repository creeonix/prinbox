import Foundation

public protocol DataLoading: Sendable {
    func load(_ url: URL) async throws -> Data
}

public struct URLSessionDataLoader: DataLoading {
    public init() {}

    public func load(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }
}
