import Foundation
import PrinboxCore
import ServiceManagement

/// Entry points that run without UI: `--print` (the live end-to-end check), `--print-query` (the phase 1
/// query) and `--print-details-query` (the phase 2 template with `__IDS__`), both used by
/// scripts/record-fixture.sh, and `--unregister-login-item` (used by `make uninstall`).
enum CommandLineMode {
    case printInbox
    case printQuery
    case printDetailsQuery
    case unregisterLoginItem

    init?(arguments: [String]) {
        if arguments.contains("--print") {
            self = .printInbox
        } else if arguments.contains("--print-query") {
            self = .printQuery
        } else if arguments.contains("--print-details-query") {
            self = .printDetailsQuery
        } else if arguments.contains("--unregister-login-item") {
            self = .unregisterLoginItem
        } else {
            return nil
        }
    }

    @MainActor
    func run() async -> Int32 {
        switch self {
        case .printQuery:
            print(SearchQuery.text(includeInvolved: true))
            return 0
        case .printDetailsQuery:
            print(DetailsQuery.template(includeConversation: true))
            return 0
        case .printInbox:
            return await CLI.run(
                Invocation(command: .print, settingsPath: nil, verbose: false), context: Self.makeContext(),
                stdout: { @Sendable in print($0, terminator: "") },
                stderr: { @Sendable in FileHandle.standardError.write(Data($0.utf8)) })
        case .unregisterLoginItem:
            do {
                try await SMAppService.mainApp.unregister()
                return 0
            } catch {
                FileHandle.standardError.write(Data("login item: \(error.localizedDescription)\n".utf8))
                return 1
            }
        }
    }

    /// The app's adapters for a command run: the same files, gh and logger as the running app.
    private static func makeContext() -> RunContext {
        let logger = OSLogging()
        let directories = MacDirectories()
        let settings = JSONKeyValueFile(url: directories.config.appendingPathComponent("settings.json"), logger: logger)
        let locator = GhLocator(overridePath: settings.object(forKey: GhLocator.overrideKey) as? String)
        let lock = FileLock(url: directories.state.appendingPathComponent("prinbox.lock"), logger: logger)
        return RunContext(
            fetcher: GhClient(locator: locator, logger: logger),
            cache: JSONCacheFile(
                url: directories.state.appendingPathComponent("cache.json"), lock: lock, logger: logger),
            persistence: JSONStateFile(url: JSONStateFile.url(in: directories)), lock: lock,
            followReviewThreads: settings.object(forKey: FetchSettings.key) as? Bool ?? true,
            scope: SearchScope.read(from: settings, logger: logger),
            ghOverride: locator.overridePath, delivery: NoDelivery(), opener: WorkspaceURLOpener(), notifyNote: nil,
            clock: { Date() }, logger: logger,
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")
    }
}
