import AppKit
import Observation
import PrinboxCore

/// Decoded avatars for the views, backed by the on-disk `AvatarCache`. A failed load is retried after
/// `AvatarAttempts.defaultRetryAfter`, the next time a row with that login appears.
@MainActor
@Observable
final class AvatarImages {
    private var images: [String: NSImage] = [:]
    @ObservationIgnored private var attempts = AvatarAttempts()
    @ObservationIgnored private let cache: AvatarCache

    init(cache: AvatarCache) { self.cache = cache }

    func image(for login: String) -> NSImage? { images[login] }

    func load(login: String, url: URL?) async {
        guard attempts.shouldAttempt(login, now: Date()) else { return }
        attempts = attempts.recordingAttempt(login)
        if let data = await cache.data(login: login, url: url), let image = NSImage(data: data) {
            images = images.merging([login: image]) { _, new in new }
            attempts = attempts.recordingSuccess(login)
        } else {
            attempts = attempts.recordingFailure(login, at: Date())
        }
    }
}
