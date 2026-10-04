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
            let client = Self.makeClient()
            do {
                let result = try await client.fetch()
                let inbox = InboxBuilder.build(result, snoozed: Self.snoozedIDs(for: result))
                print(InboxPrinter.render(inbox, now: Date()))
                return 0
            } catch let error as FetchError {
                let text =
                    SetupGuide.for(error, ghOverride: client.ghOverride)?.plainText
                    ?? error.message(lastSuccess: nil)
                let link = error.helpURL.map { " (\($0.absoluteString))" } ?? ""
                FileHandle.standardError.write(Data((text + link + "\n").utf8))
                return 1
            } catch {
                FileHandle.standardError.write(Data("\(error)\n".utf8))
                return 1
            }
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

    /// The same gh as the app: the `ghPath` setting from settings.json, if any.
    private static func makeClient() -> GhClient {
        let settings = JSONKeyValueFile(url: MacDirectories().config.appendingPathComponent("settings.json"))
        let locator = GhLocator(overridePath: settings.object(forKey: GhLocator.overrideKey) as? String)
        return GhClient(locator: locator, logger: OSLogging())
    }

    /// Snoozes from state.json, woken in memory as the app would; the file is never written here.
    private static func snoozedIDs(for result: FetchResult) -> Set<String> {
        do {
            let state = try JSONStateFile(url: JSONStateFile.url(in: MacDirectories())).load() ?? AppState()
            return Set(Snooze.reconcile(state.snoozed, with: result).keys)
        } catch {
            FileHandle.standardError.write(Data("warning: state.json unreadable, ignoring snoozes\n".utf8))
            return []
        }
    }
}
