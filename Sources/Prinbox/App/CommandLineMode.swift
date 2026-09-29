import Foundation
import PrinboxCore

/// Entry points that run without UI: `--print` (the live end-to-end check) and `--print-query` (used by
/// scripts/record-fixture.sh).
enum CommandLineMode {
    case printInbox
    case printQuery

    init?(arguments: [String]) {
        if arguments.contains("--print") {
            self = .printInbox
        } else if arguments.contains("--print-query") {
            self = .printQuery
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
                FileHandle.standardError.write(Data((error.message(lastSuccess: nil) + "\n").utf8))
                return 1
            } catch {
                FileHandle.standardError.write(Data("\(error)\n".utf8))
                return 1
            }
        }
    }
}
