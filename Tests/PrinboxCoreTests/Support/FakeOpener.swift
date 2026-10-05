import Foundation

@testable import PrinboxCore

/// Records every URL and streams it, so a test can await the open that `PopoverState.open` starts.
final class FakeOpener: URLOpening, @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    private let continuation: AsyncStream<URL>.Continuation
    let stream: AsyncStream<URL>

    init() {
        var continuation: AsyncStream<URL>.Continuation!
        stream = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    func open(_ url: URL) async {
        lock.withLock { urls.append(url) }
        continuation.yield(url)
    }

    var opened: [URL] { lock.withLock { urls } }
}
