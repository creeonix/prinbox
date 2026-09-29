import Foundation
import PrinboxCore
import ServiceManagement

/// Entry points that run without UI: `--print` (the live end-to-end check), `--print-query` (used by
/// scripts/record-fixture.sh) and `--unregister-login-item` (used by `make uninstall`).
enum CommandLineMode {
    case printInbox
    case printQuery
    case unregisterLoginItem

    init?(arguments: [String]) {
        if arguments.contains("--print") {
            self = .printInbox
        } else if arguments.contains("--print-query") {
            self = .printQuery
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
            print(InboxQuery.text)
            return 0
        case .printInbox:
            do {
                let result = try await GhClient().fetch()
                print(InboxPrinter.render(InboxBuilder.build(result), now: Date()))
                return 0
            } catch let error as FetchError {
                let client = GhClient()
                let text =
                    SetupGuide.for(error, ghOverride: client.ghOverride)?.plainText
                    ?? error.message(lastSuccess: nil)
                FileHandle.standardError.write(Data((text + "\n").utf8))
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
}
