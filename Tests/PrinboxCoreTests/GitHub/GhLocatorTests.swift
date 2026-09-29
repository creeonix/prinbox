import Testing

@testable import PrinboxCore

@Suite struct GhLocatorTests {
    func locator(override: String? = nil, path: String?, executables: Set<String>) -> GhLocator {
        GhLocator(overridePath: override, environmentPath: path, isExecutable: { executables.contains($0) })
    }

    @Test func prefersTheOverride() {
        let found = locator(override: "/custom/gh", path: nil, executables: ["/custom/gh", "/opt/homebrew/bin/gh"])
        #expect(found.locate()?.path == "/custom/gh")
    }

    @Test func findsHomebrewGhWithMinimalPath() {
        let found = locator(path: "/usr/bin:/bin:/usr/sbin:/sbin", executables: ["/opt/homebrew/bin/gh"])
        #expect(found.locate()?.path == "/opt/homebrew/bin/gh")
    }

    @Test func fallsBackToUsrLocal() {
        #expect(locator(path: nil, executables: ["/usr/local/bin/gh"]).locate()?.path == "/usr/local/bin/gh")
    }

    @Test func searchesPathEntries() {
        #expect(locator(path: "/a:/b", executables: ["/b/gh"]).locate()?.path == "/b/gh")
    }

    @Test func returnsNilWhenGhIsMissing() {
        #expect(locator(path: "/a", executables: []).locate() == nil)
    }
}
