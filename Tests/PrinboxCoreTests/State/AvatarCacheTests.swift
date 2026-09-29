import Foundation
import Testing

@testable import PrinboxCore

actor CountingLoader: DataLoading {
    private(set) var calls = 0
    private let result: Result<Data, URLError>

    init(_ result: Result<Data, URLError>) { self.result = result }

    func load(_ url: URL) async throws -> Data {
        calls += 1
        return try result.get()
    }
}

@Suite struct AvatarCacheTests {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let url = URL(string: "https://avatars.githubusercontent.com/u/1?s=64")!
    let png = Data([0x89, 0x50, 0x4E, 0x47])

    @Test func downloadsOnceAndServesFromDisk() async {
        let loader = CountingLoader(.success(png))
        let cache = AvatarCache(directory: directory, loader: loader)
        #expect(await cache.data(login: "alice", url: url) == png)
        #expect(await cache.data(login: "alice", url: url) == png)
        #expect(await loader.calls == 1)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("alice.png").path))
    }

    @Test func refreshesAfterMaxAge() async {
        let clock = TestClock(Date())
        let loader = CountingLoader(.success(png))
        let cache = AvatarCache(directory: directory, loader: loader, clock: { clock.now })
        _ = await cache.data(login: "alice", url: url)
        clock.advance(8 * 24 * 3600)
        _ = await cache.data(login: "alice", url: url)
        #expect(await loader.calls == 2)
    }

    @Test func fallsBackToAStaleCopyWhenTheDownloadFails() async throws {
        let clock = TestClock(Date())
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: directory.appendingPathComponent("alice.png"))
        clock.advance(8 * 24 * 3600)
        let cache = AvatarCache(
            directory: directory, loader: CountingLoader(.failure(URLError(.notConnectedToInternet))),
            clock: { clock.now })
        #expect(await cache.data(login: "alice", url: url) == png)
    }

    @Test func nothingWithoutURLOrCache() async {
        let cache = AvatarCache(directory: directory, loader: CountingLoader(.success(png)))
        #expect(await cache.data(login: "ghost", url: nil) == nil)
    }

    @Test func fileNamesCannotEscapeTheDirectory() {
        #expect(AvatarCache.fileName(for: "dependabot[bot]") == "dependabot_bot_.png")
        #expect(AvatarCache.fileName(for: "../evil") == "___evil.png")
    }
}
