import AppKit
import Observation
import PrinboxCore

/// Decoded avatars for the views, backed by the on-disk `AvatarCache`.
@MainActor
@Observable
final class AvatarImages {
    private var images: [String: NSImage] = [:]
    @ObservationIgnored private var requested: Set<String> = []
    @ObservationIgnored private let cache: AvatarCache

    init(cache: AvatarCache) { self.cache = cache }

    func image(for login: String) -> NSImage? { images[login] }

    func load(login: String, url: URL?) async {
        guard !requested.contains(login) else { return }
        requested = requested.union([login])
        guard let data = await cache.data(login: login, url: url), let image = NSImage(data: data) else { return }
        images = images.merging([login: image]) { _, new in new }
    }
}
