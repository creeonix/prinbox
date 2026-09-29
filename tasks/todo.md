# prinbox v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build prinbox v1, a native macOS menu-bar code-review inbox that authenticates only through the GitHub CLI.

**Architecture:** The SwiftPM package has two targets:
- `PrinboxCore` is a library with no AppKit. It holds all testable logic: the gh subprocess, GraphQL decoding, classification, sorting and caps, formatting, the refresh store, and navigation state.
- `Prinbox` is a thin AppKit and SwiftUI executable: the `NSStatusItem`, an `NSPopover` hosting SwiftUI views, the Carbon hotkey, and `SMAppService`.

All view state lives in `@Observable` models from Core, because `@State` cannot compile without Xcode.

**Tech Stack:** Swift 6.4 (Swift 6 language mode), SwiftPM, AppKit, SwiftUI, Observation, Carbon.HIToolbox, ServiceManagement, Swift Testing, jq, and the `gh` CLI. There are no third-party packages.

**Spec:** `docs/specs/2026-09-29-prinbox-v1-design.md`

## Global Constraints

- Build with Command Line Tools only (no Xcode). Swift tools 6.0, Swift 6 language mode. macOS deployment target 14.0.
- Do not use `@State`, `#Preview` or any other SwiftUI macro. Keep view state in `@Observable` classes. Use `Binding(get:set:)` instead of `@Bindable`.
- Tests use Swift Testing (`import Testing`) only. XCTest is unavailable.
- No third-party dependencies.
- `PrinboxCore` imports only Foundation, Observation and os (for `Logger`). Never import AppKit, SwiftUI, Carbon or ServiceManagement there.
- GitHub access goes only through `gh api graphql`. Never read, store, pass or log a token. Never log gh stdout.
- Bundle id `io.github.creeonix.prinbox`, app bundle `Prinbox.app`, executable `Prinbox`, display name `prinbox`.
- Constants:
  - row cap: 8
  - refresh interval: 300 s
  - stale threshold: 60 s
  - gh timeout: 30 s
  - rate-limit fallback pause: 15 min
  - avatar TTL: 7 days
  - default hotkey: ⌃⌥P (key code 35, control + option)
- No emojis in code, comments or docs. Typographic symbols such as `·`, `−`, `⌃` and `…` are fine.
- Keep files focused: 200-400 lines typical, 800 max. Functions under 50 lines.
- Every file that ports Pullover logic starts with this two-line attribution header:
  `// Ported from Pullover (https://github.com/omgovich/pullover), <path>.`
  `// MIT License, Copyright (c) 2026 Vlad Shilov.`
- Commits use Conventional Commits and are small, one per task unless a step says otherwise. Run `make format` and `make lint` before each commit once the Makefile exists.
- `make lint` has two parts:
  - The `@State`/`#Preview` guard fails the build.
  - swift-format lint findings are advisory, because long string literals such as the GraphQL text cannot be wrapped. Fix the findings that are fixable in files you touched.

## Review Focus

Inputs the spec implies but that no happy-path test exercises. Each line has a pinned test in the owning task.

1. **Launched from Finder or at login, where `PATH` is `/usr/bin:/bin:/usr/sbin:/sbin`.** gh must still be found in `/opt/homebrew/bin`. Test: Task 4, `findsHomebrewGhWithMinimalPath`.
2. **PR titles with newlines, tabs or great length.** Rows must stay on one line. Test: Task 7, `titleCollapsesLineBreaksAndTabs`.
3. **Timestamps in the future (clock skew between Mac and GitHub).** Ages must read `<1m`, never negative. Test: Task 7, `futureTimestampsReadAsJustNow`.
4. **A refresh that empties the inbox while an item is selected.** Selection clears and Enter does nothing, with no crash. Test: Task 10, `reconcileWithEmptyInboxClearsSelection`.
5. **Large responses (many PRs with timeline events, well over 64 KB).** The subprocess must not deadlock on a full pipe. Test: Task 4, `drainsLargeOutputWithoutDeadlock`.

---

## File Map

```
Package.swift
Makefile
.gitignore
.swift-format
LICENSE
THIRD_PARTY_NOTICES.md
README.md
Resources/Info.plist
scripts/anonymize.jq
scripts/record-fixture.sh
scripts/coverage.sh
Sources/PrinboxCore/
  Model/PullRequest.swift              domain value + small enums
  GitHub/InboxQuery.swift              GraphQL text
  GitHub/InboxResponse.swift           Decodable DTOs of the gh response
  GitHub/PullRequestMapper.swift       DTO -> FetchResult (dedupe, field derivations)
  GitHub/FetchResult.swift             FetchResult, FetchError
  GitHub/GhErrorClassifier.swift       exit code + stderr -> FetchError
  GitHub/GraphQLErrors.swift           partial-data warnings, RATE_LIMITED
  GitHub/CommandRunning.swift          protocol + CommandOutput
  GitHub/ProcessCommandRunner.swift    Process-based runner with timeout
  GitHub/GhLocator.swift               finds the gh binary
  GitHub/GhClient.swift                InboxFetching over gh api graphql
  Inbox/SectionKind.swift              SectionKind, Reason, ReasonTone
  Inbox/WaitingSince.swift             waiting-since rules
  Inbox/Classifier.swift               PR -> Classification
  Inbox/Inbox.swift                    Inbox, InboxSection, InboxRow
  Inbox/InboxBuilder.swift             filter, classify, sort, cap, badge
  Format/RelativeAge.swift             "6h", "<1m"
  Format/ClockText.swift               "14:05"
  Format/RowText.swift                 row, header and placeholder strings
  Format/FetchErrorText.swift          FetchError.message(...)
  Format/InboxPrinter.swift            text rendering for --print
  State/StatusBadge.swift              status item state
  State/InboxStore.swift               refresh orchestration
  State/KeyValueStoring.swift          UserDefaults seam
  State/HotKeySpec.swift               shortcut value, display, Carbon mask
  State/HotKeySettings.swift           persisted shortcut
  State/InboxItemID.swift              focusable items + layout
  State/Selection.swift                keyboard/hover selection
  State/FoldStore.swift                persisted fold state
  State/KeyCommand.swift               key press -> command
  State/PopoverState.swift             popover view model
  State/DataLoading.swift              avatar download seam
  State/AvatarCache.swift              on-disk avatar cache
Sources/Prinbox/
  App/main.swift
  App/CommandLineMode.swift            --print, --print-query, --unregister-login-item
  App/AppDelegate.swift
  App/AppCoordinator.swift
  App/AppInfo.swift
  App/RefreshTriggers.swift
  StatusItem/StatusItemController.swift
  Popover/PopoverController.swift
  Popover/KeyMonitor.swift
  System/AvatarImages.swift
  System/HotKeyCenter.swift
  System/LoginItem.swift
  Views/PopoverActions.swift
  Views/InboxView.swift
  Views/HeaderView.swift
  Views/InboxListView.swift
  Views/SectionView.swift
  Views/RowViews.swift
  Views/AvatarView.swift
  Views/Theme.swift
  Views/SettingsView.swift
  Views/ShortcutRecorderView.swift
Tests/PrinboxCoreTests/
  Support/Factory.swift, Fixture.swift, TestClock.swift, ScriptedFetcher.swift, MemoryDefaults.swift
  Fixtures/review-mix.json, Fixtures/live-2026-09-29.json
  Model/, GitHub/, Inbox/, Format/, State/   (one test file per source file)
```

---

### Task 1: Repository skeleton and domain model

**Files:**
- Create: `Package.swift`, `.gitignore`, `.swift-format`, `Makefile`, `LICENSE`, `THIRD_PARTY_NOTICES.md`
- Create: `Sources/PrinboxCore/Model/PullRequest.swift`
- Create: `Tests/PrinboxCoreTests/Support/Factory.swift`
- Test: `Tests/PrinboxCoreTests/Model/PullRequestTests.swift`

**Interfaces:**
- Produces:
  - `SearchSource` (`.review`, `.mentions`, `.mine`; CaseIterable, in that order)
  - `ReviewDecision` (`.approved`, `.changesRequested`, `.reviewRequired`, `.none`)
  - `Mergeable` (`.mergeable`, `.conflicting`, `.unknown`)
  - `CIState` (`.success`, `.failure`, `.pending`, `.none`)
  - `ViewerReview(state:submittedAt:)`
  - `PullRequest`, with every spec field plus `repoShortName`
  - Test helpers: `makePR(...)`, `date(_:)`, `testViewer`

- [x] **Step 1: Create the package and tooling files**

`Package.swift`:
```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Prinbox",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "PrinboxCore"),
        .testTarget(name: "PrinboxCoreTests", dependencies: ["PrinboxCore"]),
    ]
)
```

`.gitignore`:
```
.build/
build/
.swiftpm/
.DS_Store
```

`.swift-format`:
```json
{
  "version": 1,
  "lineLength": 120,
  "indentation": { "spaces": 4 }
}
```

`Makefile` (indent recipes with tabs):
```make
.PHONY: test lint format

test:
	swift test

lint:
	swift format lint --recursive Sources Tests Package.swift
	@if grep -rnE '@State( |$$)|#Preview' Sources; then \
		echo "error: @State and #Preview need Xcode's SwiftUI macro plugin; keep view state in @Observable models"; \
		exit 1; \
	fi

format:
	swift format --in-place --recursive Sources Tests Package.swift
```

`LICENSE`: the standard MIT License text with the line `Copyright (c) 2026 creeonix`.

`THIRD_PARTY_NOTICES.md`:
```markdown
# Third-party notices

## Pullover

https://github.com/omgovich/pullover

prinbox ports these pieces from Pullover's `src/core` and their tests: the
classification order for your own pull requests, the waiting-since rules, and
how the review-request time is chosen (direct request first, then a team
request).

MIT License

Copyright (c) 2026 Vlad Shilov

<full MIT permission and warranty text, copied from Pullover's LICENSE>

## omarchy-pullover

https://github.com/igor-alexandrov/omarchy-pullover

prinbox follows its approach of using the GitHub CLI's credentials for the
GraphQL inbox query, and its handling of partial GraphQL errors.

MIT License

Copyright (c) 2026 Vlad Shilov
Copyright (c) 2026 Igor Alexandrov

<full MIT permission and warranty text>
```
Copy the MIT body verbatim from `https://github.com/omgovich/pullover/blob/main/LICENSE`. It is the standard MIT text.

- [x] **Step 2: Write the failing test**

`Tests/PrinboxCoreTests/Support/Factory.swift`:
```swift
import Foundation

@testable import PrinboxCore

let testViewer = "me"

func date(_ iso: String) -> Date {
    guard let value = ISO8601DateFormatter().date(from: iso) else {
        fatalError("bad test date \(iso)")
    }
    return value
}

func makePR(
    id: String = "PR_1",
    number: Int = 1,
    title: String = "Add feature",
    repository: String = "acme/web",
    isArchived: Bool = false,
    authorLogin: String = "alice",
    isDraft: Bool = false,
    additions: Int = 10,
    deletions: Int = 2,
    createdAt: Date = date("2026-08-01T10:00:00Z"),
    updatedAt: Date = date("2026-08-01T10:00:00Z"),
    reviewDecision: ReviewDecision = .reviewRequired,
    mergeable: Mergeable = .mergeable,
    ci: CIState = .success,
    viewerReview: ViewerReview? = nil,
    reviewRequestedAt: Date? = nil,
    readyForReviewAt: Date? = nil,
    source: SearchSource = .review
) -> PullRequest {
    PullRequest(
        id: id,
        number: number,
        title: title,
        url: URL(string: "https://github.com/\(repository)/pull/\(number)")!,
        repository: repository,
        isArchived: isArchived,
        authorLogin: authorLogin,
        avatarURL: URL(string: "https://avatars.githubusercontent.com/u/1"),
        isDraft: isDraft,
        additions: additions,
        deletions: deletions,
        createdAt: createdAt,
        updatedAt: updatedAt,
        reviewDecision: reviewDecision,
        mergeable: mergeable,
        ci: ci,
        viewerReview: viewerReview,
        reviewRequestedAt: reviewRequestedAt,
        readyForReviewAt: readyForReviewAt,
        source: source
    )
}
```

`Tests/PrinboxCoreTests/Model/PullRequestTests.swift`:
```swift
import Testing

@testable import PrinboxCore

@Suite struct PullRequestTests {
    @Test func repoShortNameDropsTheOwner() {
        #expect(makePR(repository: "acme/web").repoShortName == "web")
    }

    @Test func repoShortNameWithoutOwnerIsUnchanged() {
        #expect(makePR(repository: "web").repoShortName == "web")
    }
}
```

- [x] **Step 3: Run the test and confirm it fails**

Run: `swift test`
Expected: the build fails with `cannot find 'PullRequest' in scope`. The package also has no source files yet.

- [x] **Step 4: Implement the model**

`Sources/PrinboxCore/Model/PullRequest.swift`:
```swift
import Foundation

/// Which search in `InboxQuery` returned a pull request. Declaration order is the dedupe priority.
public enum SearchSource: String, Sendable, CaseIterable {
    case review
    case mentions
    case mine
}

public enum ReviewDecision: Sendable, Equatable {
    case approved
    case changesRequested
    case reviewRequired
    case none
}

public enum Mergeable: Sendable, Equatable {
    case mergeable
    case conflicting
    case unknown
}

public enum CIState: Sendable, Equatable {
    case success
    case failure
    case pending
    case none
}

/// The viewer's latest submitted review. Pending (unsubmitted) reviews are never represented.
public struct ViewerReview: Sendable, Equatable {
    public let state: String
    public let submittedAt: Date?

    public init(state: String, submittedAt: Date?) {
        self.state = state
        self.submittedAt = submittedAt
    }
}

public struct PullRequest: Sendable, Equatable, Identifiable {
    public let id: String
    public let number: Int
    public let title: String
    public let url: URL
    /// "owner/name".
    public let repository: String
    public let isArchived: Bool
    public let authorLogin: String
    public let avatarURL: URL?
    public let isDraft: Bool
    public let additions: Int
    public let deletions: Int
    public let createdAt: Date
    public let updatedAt: Date
    public let reviewDecision: ReviewDecision
    public let mergeable: Mergeable
    public let ci: CIState
    public let viewerReview: ViewerReview?
    public let reviewRequestedAt: Date?
    public let readyForReviewAt: Date?
    public let source: SearchSource

    public init(
        id: String, number: Int, title: String, url: URL, repository: String, isArchived: Bool,
        authorLogin: String, avatarURL: URL?, isDraft: Bool, additions: Int, deletions: Int,
        createdAt: Date, updatedAt: Date, reviewDecision: ReviewDecision, mergeable: Mergeable,
        ci: CIState, viewerReview: ViewerReview?, reviewRequestedAt: Date?, readyForReviewAt: Date?,
        source: SearchSource
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.url = url
        self.repository = repository
        self.isArchived = isArchived
        self.authorLogin = authorLogin
        self.avatarURL = avatarURL
        self.isDraft = isDraft
        self.additions = additions
        self.deletions = deletions
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.reviewDecision = reviewDecision
        self.mergeable = mergeable
        self.ci = ci
        self.viewerReview = viewerReview
        self.reviewRequestedAt = reviewRequestedAt
        self.readyForReviewAt = readyForReviewAt
        self.source = source
    }

    /// Repository name without the owner: "web" for "acme/web".
    public var repoShortName: String {
        repository.split(separator: "/").last.map(String.init) ?? repository
    }
}
```

- [x] **Step 5: Run the tests and confirm they pass**

Run: `swift test`
Expected: `Test run with 2 tests ... passed`.

- [x] **Step 6: Format, lint, commit**

```bash
make format && make lint
git add Package.swift .gitignore .swift-format Makefile LICENSE THIRD_PARTY_NOTICES.md Sources Tests
git commit -m "chore: add package skeleton and pull request model"
```

---

### Task 2: GraphQL query, response decoding and mapping

**Files:**
- Create: `Sources/PrinboxCore/GitHub/InboxQuery.swift`
- Create: `Sources/PrinboxCore/GitHub/InboxResponse.swift`
- Create: `Sources/PrinboxCore/GitHub/FetchResult.swift`
- Create: `Sources/PrinboxCore/GitHub/PullRequestMapper.swift`
- Create: `Tests/PrinboxCoreTests/Support/Fixture.swift`
- Create: `Tests/PrinboxCoreTests/Fixtures/review-mix.json`
- Test: `Tests/PrinboxCoreTests/GitHub/InboxQueryTests.swift`, `Tests/PrinboxCoreTests/GitHub/PullRequestMapperTests.swift`

**Interfaces:**
- Consumes: `PullRequest` and the enums from Task 1.
- Produces:
  - `public enum InboxQuery { public static let text: String }`
  - `struct InboxResponse: Decodable` with `static func decode(_ bytes: Data) throws -> InboxResponse`
  - `public struct GraphQLError: Decodable, Sendable, Equatable { type: String?; message: String }`
  - `public struct FetchResult { viewerLogin, pullRequests, totals: [SearchSource: Int], fetched: [SearchSource: Int], warnings: [String] }`
  - `public enum FetchError: Error, Sendable, Equatable { ghNotFound, loggedOut, offline, timedOut, rateLimited(resetAt: Date?), badResponse, other(String) }`
  - `enum PullRequestMapper { static func map(_ response: InboxResponse) throws -> FetchResult }`
  - Test helper: `Fixture.data(_ name: String) throws -> Data`

- [x] **Step 1: Write the fixture**

`Tests/PrinboxCoreTests/Fixtures/review-mix.json`:
```json
{
  "data": {
    "viewer": { "login": "me" },
    "rateLimit": { "cost": 2, "remaining": 4990, "resetAt": "2026-08-10T13:00:00Z" },
    "review": {
      "issueCount": 5,
      "nodes": [
        {
          "id": "PR_A", "number": 101, "title": "Direct review request",
          "url": "https://github.com/acme/web/pull/101", "isDraft": false,
          "additions": 120, "deletions": 4,
          "createdAt": "2026-08-01T09:00:00Z", "updatedAt": "2026-08-06T09:00:00Z",
          "author": { "login": "alice", "avatarUrl": "https://avatars.githubusercontent.com/u/1?s=64" },
          "repository": { "nameWithOwner": "acme/web", "isArchived": false },
          "reviewDecision": "REVIEW_REQUIRED", "mergeable": "MERGEABLE",
          "viewerLatestReview": null,
          "commits": { "nodes": [{ "commit": { "committedDate": "2026-08-01T08:00:00Z", "statusCheckRollup": { "state": "SUCCESS" } } }] },
          "timelineItems": { "nodes": [
            { "__typename": "ReviewRequestedEvent", "createdAt": "2026-08-01T12:00:00Z", "requestedReviewer": { "__typename": "Team" } },
            { "__typename": "ReviewRequestedEvent", "createdAt": "2026-08-02T10:00:00Z", "requestedReviewer": { "__typename": "User", "login": "ME" } },
            { "__typename": "ReviewRequestedEvent", "createdAt": "2026-08-03T10:00:00Z", "requestedReviewer": { "__typename": "User", "login": "bob" } }
          ] }
        },
        {
          "id": "PR_B", "number": 102, "title": "Team review request",
          "url": "https://github.com/acme/api/pull/102", "isDraft": false,
          "additions": 5, "deletions": 50,
          "createdAt": "2026-08-02T09:00:00Z", "updatedAt": "2026-08-04T09:00:00Z",
          "author": { "login": "bob", "avatarUrl": "https://avatars.githubusercontent.com/u/2?s=64" },
          "repository": { "nameWithOwner": "acme/api", "isArchived": false },
          "reviewDecision": "REVIEW_REQUIRED", "mergeable": "MERGEABLE",
          "viewerLatestReview": { "state": "PENDING", "submittedAt": null },
          "commits": { "nodes": [{ "commit": { "committedDate": "2026-08-02T08:00:00Z", "statusCheckRollup": { "state": "PENDING" } } }] },
          "timelineItems": { "nodes": [
            { "__typename": "ReadyForReviewEvent", "createdAt": "2026-08-03T07:00:00Z" },
            { "__typename": "ReviewRequestedEvent", "createdAt": "2026-08-03T08:00:00Z", "requestedReviewer": { "__typename": "Team" } }
          ] }
        },
        {
          "id": "PR_C", "number": 103, "title": "Re-requested review",
          "url": "https://github.com/acme/web/pull/103", "isDraft": false,
          "additions": 1, "deletions": 1,
          "createdAt": "2026-08-01T09:00:00Z", "updatedAt": "2026-08-05T10:00:00Z",
          "author": { "login": "carol", "avatarUrl": "https://avatars.githubusercontent.com/u/3?s=64" },
          "repository": { "nameWithOwner": "acme/web", "isArchived": false },
          "reviewDecision": "CHANGES_REQUESTED", "mergeable": "MERGEABLE",
          "viewerLatestReview": { "state": "COMMENTED", "submittedAt": "2026-08-04T09:00:00Z" },
          "commits": { "nodes": [{ "commit": { "committedDate": "2026-08-01T08:00:00Z", "statusCheckRollup": null } }] },
          "timelineItems": { "nodes": [
            { "__typename": "ReviewRequestedEvent", "createdAt": "2026-08-05T09:00:00Z", "requestedReviewer": { "__typename": "User", "login": "me" } }
          ] }
        },
        null,
        {}
      ]
    },
    "mentions": {
      "issueCount": 2,
      "nodes": [
        {
          "id": "PR_D", "number": 7, "title": "Mentioned by a deleted user",
          "url": "https://github.com/acme/docs/pull/7", "isDraft": false,
          "additions": 3, "deletions": 0,
          "createdAt": "2026-08-01T09:00:00Z", "updatedAt": "2026-08-02T09:00:00Z",
          "author": null,
          "repository": { "nameWithOwner": "acme/docs", "isArchived": false },
          "reviewDecision": null, "mergeable": "CONFLICTING",
          "viewerLatestReview": null,
          "commits": { "nodes": [] },
          "timelineItems": { "nodes": [] }
        },
        {
          "id": "PR_A", "number": 101, "title": "Duplicate of PR_A",
          "url": "https://github.com/acme/web/pull/101", "isDraft": false,
          "additions": 120, "deletions": 4,
          "createdAt": "2026-08-01T09:00:00Z", "updatedAt": "2026-08-06T09:00:00Z",
          "author": { "login": "alice", "avatarUrl": "https://avatars.githubusercontent.com/u/1?s=64" },
          "repository": { "nameWithOwner": "acme/web", "isArchived": false },
          "reviewDecision": "REVIEW_REQUIRED", "mergeable": "MERGEABLE",
          "viewerLatestReview": null,
          "commits": { "nodes": [] },
          "timelineItems": { "nodes": [] }
        }
      ]
    },
    "mine": {
      "issueCount": 40,
      "nodes": [
        {
          "id": "PR_E", "number": 55, "title": "My approved change",
          "url": "https://github.com/acme/web/pull/55", "isDraft": false,
          "additions": 30, "deletions": 10,
          "createdAt": "2026-08-01T09:00:00Z", "updatedAt": "2026-08-07T09:00:00Z",
          "author": { "login": "me", "avatarUrl": "https://avatars.githubusercontent.com/u/9?s=64" },
          "repository": { "nameWithOwner": "acme/web", "isArchived": false },
          "reviewDecision": "APPROVED", "mergeable": "MERGEABLE",
          "viewerLatestReview": null,
          "commits": { "nodes": [{ "commit": { "committedDate": "2026-08-06T08:00:00Z", "statusCheckRollup": { "state": "ERROR" } } }] },
          "timelineItems": { "nodes": [] }
        },
        {
          "id": "PR_F", "number": 9, "title": "Old archived work",
          "url": "https://github.com/acme/legacy/pull/9", "isDraft": true,
          "additions": 0, "deletions": 0,
          "createdAt": "2026-07-01T09:00:00Z", "updatedAt": "2026-07-02T09:00:00Z",
          "author": { "login": "me", "avatarUrl": "https://avatars.githubusercontent.com/u/9?s=64" },
          "repository": { "nameWithOwner": "acme/legacy", "isArchived": true },
          "reviewDecision": "CHANGES_REQUESTED", "mergeable": "UNKNOWN",
          "viewerLatestReview": null,
          "commits": { "nodes": [{ "commit": { "committedDate": "2026-07-01T08:00:00Z", "statusCheckRollup": { "state": "EXPECTED" } } }] },
          "timelineItems": { "nodes": [] }
        }
      ]
    }
  }
}
```

`Tests/PrinboxCoreTests/Support/Fixture.swift`:
```swift
import Foundation

enum Fixture {
    /// Loads Tests/PrinboxCoreTests/Fixtures/<name>.json from the source tree (no SwiftPM resources).
    static func data(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name).json")
        return try Data(contentsOf: url)
    }
}
```

- [x] **Step 2: Write the failing tests**

`Tests/PrinboxCoreTests/GitHub/InboxQueryTests.swift`:
```swift
import Testing

@testable import PrinboxCore

@Suite struct InboxQueryTests {
    @Test func everySearchExcludesArchivedRepositories() {
        #expect(InboxQuery.text.components(separatedBy: "archived:false").count - 1 == 3)
    }

    @Test func asksForTheViewerLogin() {
        #expect(InboxQuery.text.contains("viewer { login }"))
    }
}
```

`Tests/PrinboxCoreTests/GitHub/PullRequestMapperTests.swift`:
```swift
import Foundation
import Testing

@testable import PrinboxCore

@Suite struct PullRequestMapperTests {
    let result: FetchResult

    init() throws {
        result = try PullRequestMapper.map(InboxResponse.decode(Fixture.data("review-mix")))
    }

    func pr(_ id: String) throws -> PullRequest {
        try #require(result.pullRequests.first { $0.id == id })
    }

    @Test func readsViewerAndCounts() {
        #expect(result.viewerLogin == "me")
        #expect(result.totals == [.review: 5, .mentions: 2, .mine: 40])
        #expect(result.fetched == [.review: 5, .mentions: 2, .mine: 2])
        #expect(result.warnings.isEmpty)
    }

    @Test func skipsNullAndNonPullRequestNodesAndDedupesById() {
        #expect(result.pullRequests.map(\.id) == ["PR_A", "PR_B", "PR_C", "PR_D", "PR_E", "PR_F"])
    }

    @Test func firstSearchWinsForDuplicates() throws {
        let first = try pr("PR_A")
        #expect(first.source == .review)
        #expect(first.title == "Direct review request")
    }

    @Test func directRequestWinsOverTeamAndIgnoresOtherUsers() throws {
        #expect(try pr("PR_A").reviewRequestedAt == date("2026-08-02T10:00:00Z"))
    }

    @Test func teamRequestIsTheFallback() throws {
        #expect(try pr("PR_B").reviewRequestedAt == date("2026-08-03T08:00:00Z"))
    }

    @Test func pendingViewerReviewCountsAsNoReview() throws {
        #expect(try pr("PR_B").viewerReview == nil)
    }

    @Test func readsReadyForReviewTime() throws {
        #expect(try pr("PR_B").readyForReviewAt == date("2026-08-03T07:00:00Z"))
        #expect(try pr("PR_A").readyForReviewAt == nil)
    }

    @Test func keepsSubmittedViewerReview() throws {
        #expect(try pr("PR_C").viewerReview == ViewerReview(state: "COMMENTED", submittedAt: date("2026-08-04T09:00:00Z")))
    }

    @Test func mapsCheckRollupStates() throws {
        #expect(try pr("PR_A").ci == .success)
        #expect(try pr("PR_B").ci == .pending)
        #expect(try pr("PR_C").ci == CIState.none)
        #expect(try pr("PR_D").ci == CIState.none)
        #expect(try pr("PR_E").ci == .failure)
        #expect(try pr("PR_F").ci == .pending)
    }

    @Test func mapsReviewDecisionAndMergeable() throws {
        #expect(try pr("PR_C").reviewDecision == .changesRequested)
        #expect(try pr("PR_D").reviewDecision == ReviewDecision.none)
        #expect(try pr("PR_E").reviewDecision == .approved)
        #expect(try pr("PR_D").mergeable == .conflicting)
        #expect(try pr("PR_F").mergeable == .unknown)
    }

    @Test func deletedAuthorBecomesGhost() throws {
        let ghost = try pr("PR_D")
        #expect(ghost.authorLogin == "ghost")
        #expect(ghost.avatarURL == nil)
    }

    @Test func keepsArchivedFlagForTheBuilder() throws {
        #expect(try pr("PR_F").isArchived)
        #expect(try pr("PR_F").isDraft)
    }

    @Test func responseWithoutDataIsBadResponse() throws {
        let response = try InboxResponse.decode(Data(#"{"message":"Not Found"}"#.utf8))
        #expect(throws: FetchError.badResponse) { try PullRequestMapper.map(response) }
    }
}
```

- [x] **Step 3: Run the tests and confirm they fail**

Run: `swift test`
Expected: the build fails with `cannot find 'InboxQuery' in scope` and `cannot find 'PullRequestMapper' in scope`.

- [x] **Step 4: Implement the query, DTOs, result types and mapper**

`Sources/PrinboxCore/GitHub/InboxQuery.swift`:
```swift
/// The single GraphQL request behind every refresh. Measured on a real account: cost 2 points, about 6 s.
/// The three searches are disjoint: mentions excludes your own PRs and PRs where you are a requested reviewer.
public enum InboxQuery {
    public static let text = """
        query Inbox {
          viewer { login }
          rateLimit { cost remaining resetAt }
          review: search(query: "is:pr is:open archived:false review-requested:@me sort:updated-desc", type: ISSUE, first: 30) { issueCount nodes { ...pr } }
          mentions: search(query: "is:pr is:open archived:false mentions:@me -author:@me -review-requested:@me sort:updated-desc", type: ISSUE, first: 30) { issueCount nodes { ...pr } }
          mine: search(query: "is:pr is:open archived:false author:@me sort:updated-desc", type: ISSUE, first: 30) { issueCount nodes { ...pr } }
        }
        fragment pr on PullRequest {
          id number title url isDraft additions deletions createdAt updatedAt
          author { login avatarUrl(size: 64) }
          repository { nameWithOwner isArchived }
          reviewDecision mergeable
          viewerLatestReview { state submittedAt }
          commits(last: 1) { nodes { commit { committedDate statusCheckRollup { state } } } }
          timelineItems(last: 20, itemTypes: [REVIEW_REQUESTED_EVENT, READY_FOR_REVIEW_EVENT]) {
            nodes {
              __typename
              ... on ReviewRequestedEvent { createdAt requestedReviewer { __typename ... on User { login } } }
              ... on ReadyForReviewEvent { createdAt }
            }
          }
        }
        """
}
```

`Sources/PrinboxCore/GitHub/FetchResult.swift`:
```swift
import Foundation

/// One successful refresh, before classification.
public struct FetchResult: Sendable, Equatable {
    public let viewerLogin: String
    /// Deduplicated by id; the first search in `SearchSource` order wins.
    public let pullRequests: [PullRequest]
    /// `issueCount` per search: everything GitHub has.
    public let totals: [SearchSource: Int]
    /// Nodes returned per search, including null entries.
    public let fetched: [SearchSource: Int]
    /// Partial-data warnings from GraphQL `errors` that came with usable `data`.
    public let warnings: [String]

    public init(
        viewerLogin: String, pullRequests: [PullRequest], totals: [SearchSource: Int],
        fetched: [SearchSource: Int], warnings: [String]
    ) {
        self.viewerLogin = viewerLogin
        self.pullRequests = pullRequests
        self.totals = totals
        self.fetched = fetched
        self.warnings = warnings
    }
}

/// Why a refresh failed. Partial data is not an error; it arrives as `FetchResult.warnings`.
public enum FetchError: Error, Sendable, Equatable {
    case ghNotFound
    case loggedOut
    case offline
    case timedOut
    case rateLimited(resetAt: Date?)
    case badResponse
    case other(String)
}
```

`Sources/PrinboxCore/GitHub/InboxResponse.swift`:
```swift
import Foundation

/// Raw shape of the `gh api graphql` response for `InboxQuery`. Only the mapper reads it.
struct InboxResponse: Decodable {
    let data: Payload?
    let errors: [GraphQLError]?

    static func decode(_ bytes: Data) throws -> InboxResponse {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(InboxResponse.self, from: bytes)
    }

    struct Payload: Decodable {
        let viewer: Viewer?
        let rateLimit: RateLimit?
        let review: Search?
        let mentions: Search?
        let mine: Search?

        func search(for source: SearchSource) -> Search? {
            switch source {
            case .review: review
            case .mentions: mentions
            case .mine: mine
            }
        }
    }

    struct Viewer: Decodable { let login: String }
    struct RateLimit: Decodable { let resetAt: Date? }

    struct Search: Decodable {
        let issueCount: Int
        let nodes: [SearchNode?]
    }

    /// A search hit. Hits that are not pull requests come back as `{}` and decode to `pullRequest == nil`.
    struct SearchNode: Decodable {
        let pullRequest: PRNode?

        init(from decoder: Decoder) throws {
            let keys = try decoder.container(keyedBy: AnyKey.self).allKeys
            pullRequest = keys.isEmpty ? nil : try PRNode(from: decoder)
        }
    }

    struct AnyKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    struct PRNode: Decodable {
        let id: String
        let number: Int
        let title: String
        let url: URL
        let isDraft: Bool
        let additions: Int
        let deletions: Int
        let createdAt: Date
        let updatedAt: Date
        let author: Author?
        let repository: Repository
        let reviewDecision: String?
        let mergeable: String?
        let viewerLatestReview: Review?
        let commits: Connection<CommitNode>?
        let timelineItems: Connection<TimelineNode>?
    }

    struct Author: Decodable {
        let login: String
        let avatarUrl: URL?
    }

    struct Repository: Decodable {
        let nameWithOwner: String
        let isArchived: Bool
    }

    struct Review: Decodable {
        let state: String
        let submittedAt: Date?
    }

    struct Connection<Node: Decodable>: Decodable {
        let nodes: [Node?]
    }

    struct CommitNode: Decodable { let commit: Commit }
    struct Commit: Decodable { let statusCheckRollup: Rollup? }
    struct Rollup: Decodable { let state: String }

    struct TimelineNode: Decodable {
        let typename: String
        let createdAt: Date?
        let requestedReviewer: Reviewer?

        enum CodingKeys: String, CodingKey {
            case typename = "__typename"
            case createdAt
            case requestedReviewer
        }
    }

    struct Reviewer: Decodable {
        let typename: String
        let login: String?

        enum CodingKeys: String, CodingKey {
            case typename = "__typename"
            case login
        }
    }
}

public struct GraphQLError: Decodable, Sendable, Equatable {
    public let type: String?
    public let message: String
}
```

`Sources/PrinboxCore/GitHub/PullRequestMapper.swift`:
```swift
// Ported from Pullover (https://github.com/omgovich/pullover), src/core/map-pr.ts.
// MIT License, Copyright (c) 2026 Vlad Shilov.
import Foundation

/// Turns a decoded `InboxResponse` into domain values.
enum PullRequestMapper {
    static func map(_ response: InboxResponse) throws -> FetchResult {
        guard let data = response.data, let viewer = data.viewer?.login else {
            throw FetchError.badResponse
        }
        let candidates = SearchSource.allCases.flatMap { source in
            (data.search(for: source)?.nodes ?? [])
                .compactMap { $0?.pullRequest }
                .map { makePullRequest($0, source: source, viewer: viewer) }
        }
        let unique = candidates.reduce(into: [PullRequest]()) { kept, pr in
            if !kept.contains(where: { $0.id == pr.id }) { kept.append(pr) }
        }
        return FetchResult(
            viewerLogin: viewer,
            pullRequests: unique,
            totals: perSearch(data) { $0.issueCount },
            fetched: perSearch(data) { $0.nodes.count },
            warnings: []
        )
    }

    private static func perSearch(
        _ data: InboxResponse.Payload, _ value: (InboxResponse.Search) -> Int
    ) -> [SearchSource: Int] {
        Dictionary(uniqueKeysWithValues: SearchSource.allCases.map { ($0, data.search(for: $0).map(value) ?? 0) })
    }

    static func makePullRequest(_ node: InboxResponse.PRNode, source: SearchSource, viewer: String) -> PullRequest {
        let events = (node.timelineItems?.nodes ?? []).compactMap { $0 }
        let rollup = node.commits?.nodes.compactMap { $0 }.last?.commit.statusCheckRollup?.state
        return PullRequest(
            id: node.id,
            number: node.number,
            title: node.title,
            url: node.url,
            repository: node.repository.nameWithOwner,
            isArchived: node.repository.isArchived,
            authorLogin: node.author?.login ?? "ghost",
            avatarURL: node.author?.avatarUrl,
            isDraft: node.isDraft,
            additions: node.additions,
            deletions: node.deletions,
            createdAt: node.createdAt,
            updatedAt: node.updatedAt,
            reviewDecision: reviewDecision(node.reviewDecision),
            mergeable: mergeable(node.mergeable),
            ci: ciState(rollup),
            viewerReview: viewerReview(node.viewerLatestReview),
            reviewRequestedAt: reviewRequestedAt(events, viewer: viewer),
            readyForReviewAt: events.filter { $0.typename == "ReadyForReviewEvent" }.compactMap(\.createdAt).max(),
            source: source
        )
    }

    /// The latest request naming the viewer; otherwise the latest request for a team (or an unknown
    /// reviewer), which is how team review requests reach the viewer.
    static func reviewRequestedAt(_ events: [InboxResponse.TimelineNode], viewer: String) -> Date? {
        let requests = events.filter { $0.typename == "ReviewRequestedEvent" }
        let direct = requests.filter {
            $0.requestedReviewer?.typename == "User"
                && $0.requestedReviewer?.login?.lowercased() == viewer.lowercased()
        }
        let indirect = requests.filter { $0.requestedReviewer?.typename != "User" }
        return direct.compactMap(\.createdAt).max() ?? indirect.compactMap(\.createdAt).max()
    }

    static func reviewDecision(_ raw: String?) -> ReviewDecision {
        switch raw {
        case "APPROVED": .approved
        case "CHANGES_REQUESTED": .changesRequested
        case "REVIEW_REQUIRED": .reviewRequired
        default: .none
        }
    }

    /// GitHub computes mergeability lazily; anything but MERGEABLE/CONFLICTING is unknown, never a conflict.
    static func mergeable(_ raw: String?) -> Mergeable {
        switch raw {
        case "MERGEABLE": .mergeable
        case "CONFLICTING": .conflicting
        default: .unknown
        }
    }

    static func ciState(_ raw: String?) -> CIState {
        switch raw {
        case "SUCCESS": .success
        case "FAILURE", "ERROR": .failure
        case "PENDING", "EXPECTED": .pending
        default: .none
        }
    }

    static func viewerReview(_ review: InboxResponse.Review?) -> ViewerReview? {
        guard let review, review.state != "PENDING" else { return nil }
        return ViewerReview(state: review.state, submittedAt: review.submittedAt)
    }
}
```

- [x] **Step 5: Run the tests and confirm they pass**

Run: `swift test`
Expected: all tests pass (2 query tests, 13 mapper tests, and the Task 1 tests).

- [x] **Step 6: Commit**

```bash
make format && make lint
git add Sources/PrinboxCore/GitHub Tests/PrinboxCoreTests
git commit -m "feat: decode the inbox GraphQL response into pull requests"
```

---

### Task 3: Error classification and partial GraphQL errors

**Files:**
- Create: `Sources/PrinboxCore/GitHub/GhErrorClassifier.swift`
- Create: `Sources/PrinboxCore/GitHub/GraphQLErrors.swift`
- Modify: `Sources/PrinboxCore/GitHub/PullRequestMapper.swift`, the `map(_:)` function only
- Test: `Tests/PrinboxCoreTests/GitHub/GhErrorClassifierTests.swift`, `Tests/PrinboxCoreTests/GitHub/GraphQLErrorsTests.swift`

**Interfaces:**
- Consumes: `FetchError`, `GraphQLError`, `InboxResponse` and `PullRequestMapper` from Task 2.
- Produces:
  - `enum GhErrorClassifier { static func classify(exitCode: Int32, stderr: String) -> FetchError }`
  - `enum GraphQLErrors { static func isRateLimited(_:) -> Bool; static func warnings(_:) -> [String] }`
  - `PullRequestMapper.map` now:
    - throws `.rateLimited(resetAt:)` on a `RATE_LIMITED` error
    - throws `.other(message)` when there are errors and no data
    - fills `warnings` when there are errors next to data

- [x] **Step 1: Write the failing tests**

The stderr strings are recorded from gh 2.97 on 2026-09-29.

`Tests/PrinboxCoreTests/GitHub/GhErrorClassifierTests.swift`:
```swift
import Testing

@testable import PrinboxCore

@Suite struct GhErrorClassifierTests {
    @Test func exitCodeFourIsLoggedOut() {
        let stderr = "To get started with GitHub CLI, please run:  gh auth login\nAlternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.\n"
        #expect(GhErrorClassifier.classify(exitCode: 4, stderr: stderr) == .loggedOut)
    }

    @Test func badCredentialsIsLoggedOut() {
        #expect(GhErrorClassifier.classify(exitCode: 1, stderr: "gh: Bad credentials (HTTP 401)\n") == .loggedOut)
    }

    @Test func connectionFailureIsOffline() {
        let stderr = #"Post "https://api.github.com/graphql": proxyconnect tcp: dial tcp 127.0.0.1:9: connect: connection refused"#
        #expect(GhErrorClassifier.classify(exitCode: 1, stderr: stderr) == .offline)
    }

    @Test func unknownHostIsOffline() {
        let stderr = #"Post "https://api.github.com/graphql": dial tcp: lookup api.github.com: no such host"#
        #expect(GhErrorClassifier.classify(exitCode: 1, stderr: stderr) == .offline)
    }

    @Test func rateLimitMessageIsRateLimited() {
        let stderr = "gh: API rate limit exceeded for user ID 1. (HTTP 403)\n"
        #expect(GhErrorClassifier.classify(exitCode: 1, stderr: stderr) == .rateLimited(resetAt: nil))
    }

    @Test func otherFailuresKeepTheFirstLineWithoutPrefix() {
        #expect(GhErrorClassifier.classify(exitCode: 1, stderr: "gh: Something odd\nmore detail\n") == .other("Something odd"))
    }

    @Test func emptyStderrNamesTheExitCode() {
        #expect(GhErrorClassifier.classify(exitCode: 2, stderr: "") == .other("gh exited with code 2"))
    }

    @Test func longMessagesAreCutTo120Characters() {
        let long = String(repeating: "x", count: 300)
        #expect(GhErrorClassifier.classify(exitCode: 1, stderr: long) == .other(String(repeating: "x", count: 120)))
    }
}
```

`Tests/PrinboxCoreTests/GitHub/GraphQLErrorsTests.swift`:
```swift
import Foundation
import Testing

@testable import PrinboxCore

@Suite struct GraphQLErrorsTests {
    func map(_ json: String) throws -> FetchResult {
        try PullRequestMapper.map(InboxResponse.decode(Data(json.utf8)))
    }

    let emptySearches = #""review":{"issueCount":0,"nodes":[]},"mentions":{"issueCount":0,"nodes":[]},"mine":{"issueCount":0,"nodes":[]}"#

    @Test func samlErrorNextToDataBecomesAWarning() throws {
        let json = #"{"data":{"viewer":{"login":"me"},"#
            + #""review":{"issueCount":1,"nodes":[null]},"mentions":{"issueCount":0,"nodes":[]},"mine":{"issueCount":0,"nodes":[]}},"#
            + #""errors":[{"type":"FORBIDDEN","message":"Resource protected by organization SAML enforcement. You must grant your OAuth token access to this organization."}]}"#
        let result = try map(json)
        #expect(result.pullRequests.isEmpty)
        #expect(result.warnings == ["An org requires SSO authorization for gh: results incomplete"])
    }

    @Test func oauthRestrictionNamesTheOrg() throws {
        let message = "Although you appear to have the correct authorization credentials, the `acme` organization has enabled OAuth App access restrictions, meaning that data access to third-parties is limited."
        let json = #"{"data":{"viewer":{"login":"me"},"# + emptySearches + #"},"errors":[{"type":"FORBIDDEN","message":""# + message + #""}]}"#
        #expect(try map(json).warnings == ["acme restricts gh (OAuth app access): results incomplete"])
    }

    @Test func otherErrorsAreQuotedAndDeduplicated() throws {
        let json = #"{"data":{"viewer":{"login":"me"},"# + emptySearches
            + #"},"errors":[{"message":"Something failed"},{"message":"Something failed"}]}"#
        #expect(try map(json).warnings == ["GitHub: Something failed"])
    }

    @Test func rateLimitedErrorThrowsWithResetTime() {
        let json = #"{"data":{"viewer":null,"rateLimit":{"resetAt":"2026-08-10T13:00:00Z"}},"#
            + #""errors":[{"type":"RATE_LIMITED","message":"API rate limit exceeded for user ID 1."}]}"#
        #expect(throws: FetchError.rateLimited(resetAt: date("2026-08-10T13:00:00Z"))) { try map(json) }
    }

    @Test func rateLimitedWithoutDataHasNoResetTime() {
        let json = #"{"errors":[{"type":"RATE_LIMITED","message":"API rate limit exceeded"}]}"#
        #expect(throws: FetchError.rateLimited(resetAt: nil)) { try map(json) }
    }

    @Test func errorsWithoutDataUseTheFirstMessage() {
        let json = #"{"errors":[{"message":"Field 'x' doesn't exist on type 'Query'"}]}"#
        #expect(throws: FetchError.other("Field 'x' doesn't exist on type 'Query'")) { try map(json) }
    }
}
```

- [x] **Step 2: Run the tests and confirm they fail**

Run: `swift test`
Expected:
- The build fails with `cannot find 'GhErrorClassifier' in scope`.
- After a stub, the GraphQL tests fail because `warnings` is always `[]`.

- [x] **Step 3: Implement the classifier and GraphQL error handling**

`Sources/PrinboxCore/GitHub/GhErrorClassifier.swift`:
```swift
import Foundation

/// Maps a failed `gh` run to a `FetchError`. gh exits 4 when not logged in and 1 for everything else,
/// so the rest is read from stderr.
enum GhErrorClassifier {
    static let networkMarkers = [
        "dial tcp", "no such host", "connection refused", "network is unreachable",
        "i/o timeout", "tls handshake timeout", "error connecting to",
    ]

    static func classify(exitCode: Int32, stderr: String) -> FetchError {
        let text = stderr.lowercased()
        if exitCode == 4 || text.contains("http 401") || text.contains("bad credentials") {
            return .loggedOut
        }
        if text.contains("rate limit") { return .rateLimited(resetAt: nil) }
        if networkMarkers.contains(where: text.contains) { return .offline }
        return .other(firstLine(stderr) ?? "gh exited with code \(exitCode)")
    }

    /// First non-empty line without gh's "gh: " prefix, cut to 120 characters.
    static func firstLine(_ text: String) -> String? {
        guard let line = text.split(whereSeparator: \.isNewline).first else { return nil }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let message = trimmed.hasPrefix("gh: ") ? String(trimmed.dropFirst(4)) : trimmed
        return message.isEmpty ? nil : String(message.prefix(120))
    }
}
```

`Sources/PrinboxCore/GitHub/GraphQLErrors.swift`:
```swift
import Foundation

/// Interprets GraphQL `errors` that came back next to (partial) `data`.
enum GraphQLErrors {
    static func isRateLimited(_ errors: [GraphQLError]) -> Bool {
        errors.contains { $0.type == "RATE_LIMITED" }
    }

    /// One readable warning per distinct error, in order.
    static func warnings(_ errors: [GraphQLError]) -> [String] {
        errors.map(warning(for:)).reduce(into: [String]()) { unique, line in
            if !unique.contains(line) { unique.append(line) }
        }
    }

    static func warning(for error: GraphQLError) -> String {
        if let org = restrictedOrg(error.message) {
            return "\(org) restricts gh (OAuth app access): results incomplete"
        }
        if error.message.contains("SAML") {
            return "An org requires SSO authorization for gh: results incomplete"
        }
        return "GitHub: " + String(error.message.prefix(120))
    }

    /// "the `acme` organization has enabled OAuth App access restrictions" -> "acme".
    static func restrictedOrg(_ message: String) -> String? {
        let pattern = /the `([^`]+)` organization has enabled OAuth App access restrictions/
        return message.firstMatch(of: pattern).map { String($0.1) }
    }
}
```

In `PullRequestMapper.swift`, replace the start of `map(_:)` and its `warnings: []` argument so that the function reads:
```swift
    static func map(_ response: InboxResponse) throws -> FetchResult {
        let errors = response.errors ?? []
        if GraphQLErrors.isRateLimited(errors) {
            throw FetchError.rateLimited(resetAt: response.data?.rateLimit?.resetAt)
        }
        guard let data = response.data, let viewer = data.viewer?.login else {
            throw errors.first.map { FetchError.other(String($0.message.prefix(120))) } ?? FetchError.badResponse
        }
        let candidates = SearchSource.allCases.flatMap { source in
            (data.search(for: source)?.nodes ?? [])
                .compactMap { $0?.pullRequest }
                .map { makePullRequest($0, source: source, viewer: viewer) }
        }
        let unique = candidates.reduce(into: [PullRequest]()) { kept, pr in
            if !kept.contains(where: { $0.id == pr.id }) { kept.append(pr) }
        }
        return FetchResult(
            viewerLogin: viewer,
            pullRequests: unique,
            totals: perSearch(data) { $0.issueCount },
            fetched: perSearch(data) { $0.nodes.count },
            warnings: GraphQLErrors.warnings(errors)
        )
    }
```

- [x] **Step 4: Run the tests and confirm they pass**

Run: `swift test`
Expected: every test passes, including the Task 2 mapper tests.

- [x] **Step 5: Commit**

```bash
make format && make lint
git add Sources/PrinboxCore/GitHub Tests/PrinboxCoreTests/GitHub
git commit -m "feat: classify gh failures and surface partial GraphQL errors as warnings"
```

---

### Task 4: Subprocess runner, gh locator and GhClient

**Files:**
- Create: `Sources/PrinboxCore/GitHub/CommandRunning.swift`
- Create: `Sources/PrinboxCore/GitHub/ProcessCommandRunner.swift`
- Create: `Sources/PrinboxCore/GitHub/GhLocator.swift`
- Create: `Sources/PrinboxCore/GitHub/GhClient.swift`
- Test: `Tests/PrinboxCoreTests/GitHub/ProcessCommandRunnerTests.swift`, `Tests/PrinboxCoreTests/GitHub/GhLocatorTests.swift`, `Tests/PrinboxCoreTests/GitHub/GhClientTests.swift`

**Interfaces:**
- Consumes:
  - `InboxQuery.text`, `InboxResponse.decode` and `PullRequestMapper.map` (Task 2)
  - `GhErrorClassifier.classify` (Task 3)
- Produces:
  - `public struct CommandOutput { exitCode: Int32; stdout: Data; stderr: String }`
  - `public enum CommandRunnerError: Error, Equatable { case launchFailed(String), timedOut }`
  - `public protocol CommandRunning: Sendable { func run(executable: URL, arguments: [String], environment: [String: String], timeout: Duration) async throws -> CommandOutput }`
  - `public struct ProcessCommandRunner: CommandRunning`
  - `public struct GhLocator` with `init(overridePath:environmentPath:isExecutable:)` and `func locate() -> URL?`
  - `public protocol InboxFetching: Sendable { func fetch() async throws -> FetchResult }`
  - `public struct GhClient: InboxFetching` with `init(locator:runner:timeout:)`, `func ghPath() -> String?` and `static func interpret(_ output: CommandOutput) throws -> FetchResult`

- [x] **Step 1: Write the failing tests**

`Tests/PrinboxCoreTests/GitHub/ProcessCommandRunnerTests.swift`:
```swift
import Foundation
import Testing

@testable import PrinboxCore

@Suite struct ProcessCommandRunnerTests {
    let runner = ProcessCommandRunner()
    let sh = URL(fileURLWithPath: "/bin/sh")
    let path = ["PATH": "/usr/bin:/bin"]

    @Test func capturesStdoutStderrAndExitCode() async throws {
        let output = try await runner.run(
            executable: sh, arguments: ["-c", "printf out; printf err >&2; exit 3"], environment: path,
            timeout: .seconds(5))
        #expect(output.exitCode == 3)
        #expect(String(decoding: output.stdout, as: UTF8.self) == "out")
        #expect(output.stderr == "err")
    }

    @Test func drainsLargeOutputWithoutDeadlock() async throws {
        let output = try await runner.run(
            executable: sh, arguments: ["-c", "head -c 300000 /dev/zero; head -c 100000 /dev/zero >&2"],
            environment: path, timeout: .seconds(10))
        #expect(output.stdout.count == 300_000)
        #expect(output.stderr.utf8.count == 100_000)
    }

    @Test func terminatesAfterTimeout() async {
        await #expect(throws: CommandRunnerError.timedOut) {
            try await runner.run(
                executable: sh, arguments: ["-c", "exec sleep 5"], environment: path, timeout: .milliseconds(200))
        }
    }

    @Test func reportsLaunchFailure() async {
        await #expect(throws: CommandRunnerError.self) {
            try await runner.run(
                executable: URL(fileURLWithPath: "/nonexistent/gh"), arguments: [], environment: path,
                timeout: .seconds(1))
        }
    }
}
```

`Tests/PrinboxCoreTests/GitHub/GhLocatorTests.swift`:
```swift
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
```

`Tests/PrinboxCoreTests/GitHub/GhClientTests.swift`:
```swift
import Foundation
import Testing

@testable import PrinboxCore

struct FakeRunner: CommandRunning {
    let handler: @Sendable (URL, [String], [String: String]) throws -> CommandOutput

    func run(executable: URL, arguments: [String], environment: [String: String], timeout: Duration)
        async throws -> CommandOutput
    {
        try handler(executable, arguments, environment)
    }
}

@Suite struct GhClientTests {
    let gh = GhLocator(overridePath: "/fake/gh", environmentPath: nil, isExecutable: { $0 == "/fake/gh" })

    func client(_ handler: @escaping @Sendable (URL, [String], [String: String]) throws -> CommandOutput) -> GhClient {
        GhClient(locator: gh, runner: FakeRunner(handler: handler))
    }

    @Test func runsGhApiGraphqlWithTheInboxQuery() async throws {
        let fixture = try Fixture.data("review-mix")
        let result = try await client { executable, arguments, environment in
            #expect(executable.path == "/fake/gh")
            #expect(arguments == ["api", "graphql", "-f", "query=\(InboxQuery.text)"])
            #expect(environment["GH_PROMPT_DISABLED"] == "1")
            return CommandOutput(exitCode: 0, stdout: fixture, stderr: "")
        }.fetch()
        #expect(result.pullRequests.count == 6)
    }

    @Test func partialErrorsWithExitOneStillReturnData() async throws {
        let body = #"{"data":{"viewer":{"login":"me"},"review":{"issueCount":0,"nodes":[]},"#
            + #""mentions":{"issueCount":0,"nodes":[]},"mine":{"issueCount":0,"nodes":[]}},"#
            + #""errors":[{"type":"FORBIDDEN","message":"Resource protected by organization SAML enforcement."}]}"#
        let result = try await client { _, _, _ in
            CommandOutput(exitCode: 1, stdout: Data(body.utf8), stderr: "gh: Resource protected by organization SAML enforcement.")
        }.fetch()
        #expect(result.warnings == ["An org requires SSO authorization for gh: results incomplete"])
    }

    @Test func loggedOutGhIsLoggedOut() async {
        await #expect(throws: FetchError.loggedOut) {
            try await client { _, _, _ in CommandOutput(exitCode: 4, stdout: Data(), stderr: "gh auth login") }.fetch()
        }
    }

    @Test func networkFailureIsOffline() async {
        await #expect(throws: FetchError.offline) {
            try await client { _, _, _ in
                CommandOutput(exitCode: 1, stdout: Data(), stderr: "dial tcp: lookup api.github.com: no such host")
            }.fetch()
        }
    }

    @Test func runnerTimeoutIsTimedOut() async {
        await #expect(throws: FetchError.timedOut) {
            try await client { _, _, _ in throw CommandRunnerError.timedOut }.fetch()
        }
    }

    @Test func launchFailureIsGhNotFound() async {
        await #expect(throws: FetchError.ghNotFound) {
            try await client { _, _, _ in throw CommandRunnerError.launchFailed("no such file") }.fetch()
        }
    }

    @Test func missingGhIsGhNotFound() async {
        let missing = GhLocator(overridePath: nil, environmentPath: nil, isExecutable: { _ in false })
        await #expect(throws: FetchError.ghNotFound) {
            try await GhClient(locator: missing, runner: FakeRunner { _, _, _ in CommandOutput(exitCode: 0, stdout: Data(), stderr: "") }).fetch()
        }
    }

    @Test func garbageOnSuccessIsBadResponse() {
        #expect(throws: FetchError.badResponse) {
            try GhClient.interpret(CommandOutput(exitCode: 0, stdout: Data("not json".utf8), stderr: ""))
        }
    }
}
```

- [x] **Step 2: Run the tests and confirm they fail**

Run: `swift test`
Expected: the build fails with `cannot find 'ProcessCommandRunner' in scope` and similar errors.

- [x] **Step 3: Implement**

`Sources/PrinboxCore/GitHub/CommandRunning.swift`:
```swift
import Foundation

public struct CommandOutput: Sendable, Equatable {
    public let exitCode: Int32
    public let stdout: Data
    public let stderr: String

    public init(exitCode: Int32, stdout: Data, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public enum CommandRunnerError: Error, Equatable {
    case launchFailed(String)
    case timedOut
}

/// Runs an external command. The real implementation is `ProcessCommandRunner`; tests replay recorded output.
public protocol CommandRunning: Sendable {
    func run(executable: URL, arguments: [String], environment: [String: String], timeout: Duration)
        async throws -> CommandOutput
}
```

`Sources/PrinboxCore/GitHub/ProcessCommandRunner.swift`:
```swift
import Foundation

/// Runs a subprocess on a background queue. It drains stdout and stderr concurrently, so large output
/// cannot fill a pipe and deadlock, and it terminates the process when `timeout` elapses.
public struct ProcessCommandRunner: CommandRunning {
    public init() {}

    public func run(executable: URL, arguments: [String], environment: [String: String], timeout: Duration)
        async throws -> CommandOutput
    {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(
                    with: Result { try Self.runBlocking(executable, arguments, environment, timeout) })
            }
        }
    }

    private static func runBlocking(
        _ executable: URL, _ arguments: [String], _ environment: [String: String], _ timeout: Duration
    ) throws -> CommandOutput {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw CommandRunnerError.launchFailed(error.localizedDescription)
        }
        let watchdog = Watchdog(process: process)
        watchdog.arm(after: timeout)
        let stderrBox = DataBox()
        let stderrHandle = UncheckedBox(stderrPipe.fileHandleForReading)
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            stderrBox.set(stderrHandle.value.readDataToEndOfFile())
            group.leave()
        }
        let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        watchdog.disarm()
        if watchdog.fired { throw CommandRunnerError.timedOut }
        return CommandOutput(
            exitCode: process.terminationStatus, stdout: stdout,
            stderr: String(decoding: stderrBox.value, as: UTF8.self))
    }
}

/// Carries a non-Sendable reference into a background closure that is its only other user.
private struct UncheckedBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = Data()

    func set(_ data: Data) {
        lock.lock()
        stored = data
        lock.unlock()
    }

    var value: Data {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}

/// Terminates the process if it is still running when the timeout fires.
private final class Watchdog: @unchecked Sendable {
    private let process: Process
    private let lock = NSLock()
    private var didFire = false
    private var isDisarmed = false

    init(process: Process) { self.process = process }

    func arm(after timeout: Duration) {
        let (seconds, attoseconds) = timeout.components
        let interval = Double(seconds) + Double(attoseconds) / 1e18
        DispatchQueue.global().asyncAfter(deadline: .now() + interval) { self.fire() }
    }

    func disarm() {
        lock.lock()
        isDisarmed = true
        lock.unlock()
    }

    var fired: Bool {
        lock.lock()
        defer { lock.unlock() }
        return didFire
    }

    private func fire() {
        lock.lock()
        let shouldKill = !isDisarmed
        if shouldKill { didFire = true }
        lock.unlock()
        if shouldKill && process.isRunning { process.terminate() }
    }
}
```

`Sources/PrinboxCore/GitHub/GhLocator.swift`:
```swift
import Foundation

/// Finds the gh binary. Apps launched from Finder or at login do not inherit the shell PATH, so the
/// Homebrew locations are checked explicitly before PATH.
public struct GhLocator: Sendable {
    public static let fixedCandidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]

    private let overridePath: String?
    private let environmentPath: String?
    private let isExecutable: @Sendable (String) -> Bool

    public init(
        overridePath: String? = UserDefaults.standard.string(forKey: "ghPath"),
        environmentPath: String? = ProcessInfo.processInfo.environment["PATH"],
        isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) {
        self.overridePath = overridePath
        self.environmentPath = environmentPath
        self.isExecutable = isExecutable
    }

    public func locate() -> URL? {
        let fromPath = (environmentPath ?? "").split(separator: ":").map { "\($0)/gh" }
        let candidates = [overridePath].compactMap { $0 } + Self.fixedCandidates + fromPath
        return candidates.first(where: isExecutable).map { URL(fileURLWithPath: $0) }
    }
}
```

`Sources/PrinboxCore/GitHub/GhClient.swift`:
```swift
import Foundation
import os

public protocol InboxFetching: Sendable {
    func fetch() async throws -> FetchResult
}

/// Fetches the inbox by running `gh api graphql`. gh owns authentication; prinbox never sees the token.
/// Failures log gh's stderr (truncated) to the unified log. stdout is never logged.
public struct GhClient: InboxFetching {
    public static let defaultTimeout: Duration = .seconds(30)
    private static let log = Logger(subsystem: "io.github.creeonix.prinbox", category: "gh")

    private let locator: GhLocator
    private let runner: CommandRunning
    private let timeout: Duration

    public init(
        locator: GhLocator = GhLocator(), runner: CommandRunning = ProcessCommandRunner(),
        timeout: Duration = GhClient.defaultTimeout
    ) {
        self.locator = locator
        self.runner = runner
        self.timeout = timeout
    }

    public func ghPath() -> String? { locator.locate()?.path }

    public func fetch() async throws -> FetchResult {
        guard let gh = locator.locate() else { throw FetchError.ghNotFound }
        let output: CommandOutput
        do {
            output = try await runner.run(
                executable: gh, arguments: ["api", "graphql", "-f", "query=\(InboxQuery.text)"],
                environment: Self.environment(), timeout: timeout)
        } catch CommandRunnerError.timedOut {
            Self.log.error("gh timed out")
            throw FetchError.timedOut
        } catch {
            Self.log.error("gh could not be launched: \(String(describing: error), privacy: .public)")
            throw FetchError.ghNotFound
        }
        if output.exitCode != 0 {
            Self.log.error("gh exited \(output.exitCode): \(String(output.stderr.prefix(500)), privacy: .public)")
        }
        return try Self.interpret(output)
    }

    /// gh prints the response body even when it exits 1 because of GraphQL errors, so a decodable body
    /// is used first and stderr only explains failures without one.
    static func interpret(_ output: CommandOutput) throws -> FetchResult {
        if let response = try? InboxResponse.decode(output.stdout), response.data != nil || response.errors != nil {
            return try PullRequestMapper.map(response)
        }
        guard output.exitCode == 0 else {
            throw GhErrorClassifier.classify(exitCode: output.exitCode, stderr: output.stderr)
        }
        throw FetchError.badResponse
    }

    static func environment(base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        base.merging(["GH_PROMPT_DISABLED": "1", "GH_NO_UPDATE_NOTIFIER": "1", "NO_COLOR": "1"]) { _, new in new }
    }
}
```

If Swift 6 rejects `Pipe` or `FileHandle` captures elsewhere, wrap them in `UncheckedBox` the same way. Do not weaken the language mode.

- [x] **Step 4: Run the tests and confirm they pass**

Run: `swift test`
Expected: every test passes. The timeout test finishes in about 0.2 s.

- [x] **Step 5: Commit**

```bash
make format && make lint
git add Sources/PrinboxCore/GitHub Tests/PrinboxCoreTests/GitHub
git commit -m "feat: fetch the inbox through gh api graphql with timeout and error mapping"
```

---

### Task 5: Sections, reasons and classification

**Files:**
- Create: `Sources/PrinboxCore/Inbox/SectionKind.swift`
- Create: `Sources/PrinboxCore/Inbox/WaitingSince.swift`
- Create: `Sources/PrinboxCore/Inbox/Classifier.swift`
- Test: `Tests/PrinboxCoreTests/Inbox/ClassifierTests.swift`, `Tests/PrinboxCoreTests/Inbox/WaitingSinceTests.swift`

**Interfaces:**
- Consumes: `PullRequest` (Task 1).
- Produces:
  - `public enum SectionKind: String, CaseIterable, Sendable, Codable`
    - cases in display order: `.needsReview`, `.takeAnotherLook`, `.mentions`, `.yourPRs`, `.waitingOnOthers`
    - properties: `title`, `countsTowardBadge`, `sortsByRecency`, `usesCompactRows`, `moreURL`
  - `public enum ReasonTone { attention, failure, success, neutral }`
  - `public enum Reason: String` with `tone`
  - `public struct Classification { section; reason; waitingSince: Date? }`
  - `public enum Classifier { static func classify(_:) -> Classification }`
  - `enum WaitingSince`

- [x] **Step 1: Write the failing tests**

`Tests/PrinboxCoreTests/Inbox/ClassifierTests.swift`:
```swift
// Ported from Pullover (https://github.com/omgovich/pullover), src/core/classify.test.ts.
// MIT License, Copyright (c) 2026 Vlad Shilov.
import Testing

@testable import PrinboxCore

@Suite struct ClassifierTests {
    func classify(_ pr: PullRequest) -> Classification { Classifier.classify(pr) }

    @Test func requestedWithoutViewerReviewNeedsReview() {
        let result = classify(makePR(source: .review))
        #expect(result.section == .needsReview)
        #expect(result.reason == .reviewRequested)
    }

    @Test func requestedAfterViewerReviewIsTakeAnotherLook() {
        let reviewed = ViewerReview(state: "COMMENTED", submittedAt: date("2026-08-02T10:00:00Z"))
        let result = classify(makePR(viewerReview: reviewed, source: .review))
        #expect(result.section == .takeAnotherLook)
        #expect(result.reason == .reReviewRequested)
    }

    @Test func mentionSearchIsMentions() {
        let result = classify(makePR(source: .mentions))
        #expect(result.section == .mentions)
        #expect(result.reason == .mentioned)
    }

    @Test func draftsInReviewSectionsAreNotHidden() {
        #expect(classify(makePR(isDraft: true, source: .review)).section == .needsReview)
    }

    @Test func ownChangesRequestedWinsOverEverything() {
        let pr = makePR(
            reviewDecision: .changesRequested, mergeable: .conflicting, ci: .failure, source: .mine)
        #expect(classify(pr).reason == .changesRequested)
        #expect(classify(pr).section == .yourPRs)
    }

    @Test func ownConflictWinsOverRedCI() {
        #expect(classify(makePR(mergeable: .conflicting, ci: .failure, source: .mine)).reason == .mergeConflicts)
    }

    @Test func ownRedCIWinsOverApproval() {
        #expect(classify(makePR(reviewDecision: .approved, ci: .failure, source: .mine)).reason == .ciRed)
    }

    @Test func ownApprovedIsReadyToMerge() {
        #expect(classify(makePR(reviewDecision: .approved, source: .mine)).reason == .readyToMerge)
    }

    @Test func ownApprovedDraftIsWaitingAsDraft() {
        let result = classify(makePR(isDraft: true, reviewDecision: .approved, source: .mine))
        #expect(result.section == .waitingOnOthers)
        #expect(result.reason == .draft)
    }

    @Test func ownDraftWithRedCIStillNeedsAction() {
        #expect(classify(makePR(isDraft: true, ci: .failure, source: .mine)).section == .yourPRs)
    }

    @Test func unknownMergeabilityIsNotAConflict() {
        let result = classify(makePR(mergeable: .unknown, source: .mine))
        #expect(result.section == .waitingOnOthers)
        #expect(result.reason == .waitingForReview)
    }

    @Test func ownSectionsHaveNoWaitingSince() {
        #expect(classify(makePR(reviewDecision: .approved, source: .mine)).waitingSince == nil)
        #expect(classify(makePR(source: .mine)).waitingSince == nil)
    }

    @Test func reasonTones() {
        #expect(Reason.reviewRequested.tone == .attention)
        #expect(Reason.ciRed.tone == .failure)
        #expect(Reason.readyToMerge.tone == .success)
        #expect(Reason.waitingForReview.tone == .neutral)
    }

    @Test func badgeSections() {
        #expect(SectionKind.allCases.filter(\.countsTowardBadge) == [.needsReview, .takeAnotherLook, .mentions])
    }
}
```

`Tests/PrinboxCoreTests/Inbox/WaitingSinceTests.swift`:
```swift
// Ported from Pullover (https://github.com/omgovich/pullover), src/core/classify.test.ts.
// MIT License, Copyright (c) 2026 Vlad Shilov.
import Foundation
import Testing

@testable import PrinboxCore

@Suite struct WaitingSinceTests {
    func since(_ pr: PullRequest) -> Date? { Classifier.classify(pr).waitingSince }

    @Test func needsReviewUsesTheRequestTime() {
        let pr = makePR(reviewRequestedAt: date("2026-08-03T10:00:00Z"), source: .review)
        #expect(since(pr) == date("2026-08-03T10:00:00Z"))
    }

    @Test func needsReviewFallsBackToCreation() {
        #expect(since(makePR(createdAt: date("2026-08-02T10:00:00Z"), source: .review)) == date("2026-08-02T10:00:00Z"))
    }

    @Test func draftFloorWinsOverAnEarlierRequest() {
        let pr = makePR(
            reviewRequestedAt: date("2026-08-02T10:00:00Z"), readyForReviewAt: date("2026-08-04T10:00:00Z"),
            source: .review)
        #expect(since(pr) == date("2026-08-04T10:00:00Z"))
    }

    @Test func reReviewUsesARequestAfterTheReview() {
        let pr = makePR(
            viewerReview: ViewerReview(state: "APPROVED", submittedAt: date("2026-08-02T10:00:00Z")),
            reviewRequestedAt: date("2026-08-03T10:00:00Z"), source: .review)
        #expect(since(pr) == date("2026-08-03T10:00:00Z"))
    }

    @Test func reReviewIgnoresARequestPredatingTheReview() {
        let pr = makePR(
            updatedAt: date("2026-08-05T10:00:00Z"),
            viewerReview: ViewerReview(state: "APPROVED", submittedAt: date("2026-08-03T10:00:00Z")),
            reviewRequestedAt: date("2026-08-02T10:00:00Z"), source: .review)
        #expect(since(pr) == date("2026-08-05T10:00:00Z"))
    }

    @Test func mentionsUseTheLastUpdate() {
        #expect(since(makePR(updatedAt: date("2026-08-06T10:00:00Z"), source: .mentions)) == date("2026-08-06T10:00:00Z"))
    }
}
```

- [x] **Step 2: Run the tests and confirm they fail**

Run: `swift test`
Expected: the build fails with `cannot find 'Classifier' in scope`.

- [x] **Step 3: Implement**

`Sources/PrinboxCore/Inbox/SectionKind.swift`:
```swift
import Foundation

/// Inbox sections, declared in display order.
public enum SectionKind: String, CaseIterable, Sendable, Codable {
    case needsReview
    case takeAnotherLook
    case mentions
    case yourPRs
    case waitingOnOthers

    public var title: String {
        switch self {
        case .needsReview: "Needs your review"
        case .takeAnotherLook: "Take another look"
        case .mentions: "Mentions"
        case .yourPRs: "Your PRs"
        case .waitingOnOthers: "Waiting on others"
        }
    }

    /// Non-draft PRs in these sections are what the menu-bar badge counts.
    public var countsTowardBadge: Bool { self == .needsReview || self == .takeAnotherLook || self == .mentions }

    /// Own-PR sections are sorted newest first and show "updated X ago" instead of "waiting X".
    public var sortsByRecency: Bool { self == .yourPRs || self == .waitingOnOthers }

    public var usesCompactRows: Bool { self == .waitingOnOthers }

    public var moreURL: URL {
        switch self {
        case .needsReview, .takeAnotherLook: URL(string: "https://github.com/pulls/review-requested")!
        case .mentions: URL(string: "https://github.com/pulls/mentioned")!
        case .yourPRs, .waitingOnOthers: URL(string: "https://github.com/pulls")!
        }
    }
}

public enum ReasonTone: Sendable, Equatable {
    case attention
    case failure
    case success
    case neutral
}

/// Why a PR is in its section. The raw value is the status text shown on the row.
public enum Reason: String, Sendable, Equatable {
    case reviewRequested = "Review requested"
    case reReviewRequested = "Re-review requested"
    case mentioned = "Mentioned"
    case changesRequested = "Changes requested"
    case mergeConflicts = "Merge conflicts"
    case ciRed = "CI is red"
    case readyToMerge = "Ready to merge"
    case draft = "Draft"
    case waitingForReview = "Waiting for review"

    public var tone: ReasonTone {
        switch self {
        case .reviewRequested, .reReviewRequested, .mentioned: .attention
        case .changesRequested, .mergeConflicts, .ciRed: .failure
        case .readyToMerge: .success
        case .draft, .waitingForReview: .neutral
        }
    }
}
```

`Sources/PrinboxCore/Inbox/WaitingSince.swift`:
```swift
// Ported from Pullover (https://github.com/omgovich/pullover), src/core/classify.ts.
// MIT License, Copyright (c) 2026 Vlad Shilov.
import Foundation

/// When the viewer started being waited on, per section.
enum WaitingSince {
    /// Nobody waits on a PR before it exists or while it is a draft.
    static func visibleSince(_ pr: PullRequest) -> Date {
        max(pr.createdAt, pr.readyForReviewAt ?? pr.createdAt)
    }

    static func reviewRequest(_ pr: PullRequest) -> Date {
        max(pr.reviewRequestedAt ?? pr.createdAt, visibleSince(pr))
    }

    /// A request counts only if it came after the viewer's review; otherwise fall back to the last update.
    static func reReview(_ pr: PullRequest) -> Date {
        let base: Date
        if let requested = pr.reviewRequestedAt, let reviewed = pr.viewerReview?.submittedAt, requested > reviewed {
            base = requested
        } else {
            base = pr.updatedAt
        }
        return max(base, visibleSince(pr))
    }
}
```

`Sources/PrinboxCore/Inbox/Classifier.swift`:
```swift
// Ported from Pullover (https://github.com/omgovich/pullover), src/core/classify.ts.
// MIT License, Copyright (c) 2026 Vlad Shilov.
import Foundation

public struct Classification: Sendable, Equatable {
    public let section: SectionKind
    public let reason: Reason
    /// When the viewer started being waited on; nil for sections sorted by recency.
    public let waitingSince: Date?
}

/// Assigns a PR to a section: the search it came from decides review vs mention vs own, and own PRs are
/// split by the first action reason that applies.
public enum Classifier {
    public static func classify(_ pr: PullRequest) -> Classification {
        switch pr.source {
        case .review:
            pr.viewerReview == nil
                ? Classification(
                    section: .needsReview, reason: .reviewRequested, waitingSince: WaitingSince.reviewRequest(pr))
                : Classification(
                    section: .takeAnotherLook, reason: .reReviewRequested, waitingSince: WaitingSince.reReview(pr))
        case .mentions:
            Classification(section: .mentions, reason: .mentioned, waitingSince: pr.updatedAt)
        case .mine:
            ownActionReason(pr).map { Classification(section: .yourPRs, reason: $0, waitingSince: nil) }
                ?? Classification(
                    section: .waitingOnOthers, reason: pr.isDraft ? .draft : .waitingForReview, waitingSince: nil)
        }
    }

    /// First match wins: changes requested, merge conflicts, red CI, approved (not draft).
    static func ownActionReason(_ pr: PullRequest) -> Reason? {
        if pr.reviewDecision == .changesRequested { return .changesRequested }
        if pr.mergeable == .conflicting { return .mergeConflicts }
        if pr.ci == .failure { return .ciRed }
        if pr.reviewDecision == .approved && !pr.isDraft { return .readyToMerge }
        return nil
    }
}
```

- [x] **Step 4: Run the tests and confirm they pass**

Run: `swift test`
Expected: every test passes.

- [x] **Step 5: Commit**

```bash
make format && make lint
git add Sources/PrinboxCore/Inbox Tests/PrinboxCoreTests/Inbox
git commit -m "feat: classify pull requests into inbox sections"
```

---

### Task 6: Inbox builder

**Files:**
- Create: `Sources/PrinboxCore/Inbox/Inbox.swift`
- Create: `Sources/PrinboxCore/Inbox/InboxBuilder.swift`
- Modify: `Tests/PrinboxCoreTests/Support/Factory.swift`, adding `makeResult`
- Test: `Tests/PrinboxCoreTests/Inbox/InboxBuilderTests.swift`

**Interfaces:**
- Consumes: `FetchResult` (Task 2), `Classifier`, `Classification` and `SectionKind` (Task 5).
- Produces:
  - `public struct InboxRow: Identifiable { pullRequest; classification; id: String }`
  - `public struct InboxSection: Identifiable { kind; rows (capped); count; moreCount; id: SectionKind }`
  - `public struct Inbox { sections; badgeCount; warnings; static let empty; isEmpty; func section(_:) -> InboxSection? }`
  - `public enum InboxBuilder { static let rowCap = 8; static func build(_ result: FetchResult, cap: Int = rowCap) -> Inbox }`
  - Test helper `makeResult(_ prs: [PullRequest], totals: [SearchSource: Int]? = nil, warnings: [String] = []) -> FetchResult`

- [x] **Step 1: Add the test helper and write the failing tests**

Append to `Tests/PrinboxCoreTests/Support/Factory.swift`:
```swift
func makeResult(_ prs: [PullRequest], totals: [SearchSource: Int]? = nil, warnings: [String] = []) -> FetchResult {
    let counts = Dictionary(grouping: prs, by: \.source).mapValues(\.count)
    let fetched = Dictionary(uniqueKeysWithValues: SearchSource.allCases.map { ($0, counts[$0] ?? 0) })
    return FetchResult(
        viewerLogin: testViewer, pullRequests: prs, totals: totals ?? fetched, fetched: fetched, warnings: warnings)
}
```

`Tests/PrinboxCoreTests/Inbox/InboxBuilderTests.swift`:
```swift
import Foundation
import Testing

@testable import PrinboxCore

@Suite struct InboxBuilderTests {
    let reviewed = ViewerReview(state: "COMMENTED", submittedAt: date("2026-08-01T11:00:00Z"))

    @Test func dropsArchivedRepositories() {
        let inbox = InboxBuilder.build(makeResult([makePR(id: "old", isArchived: true, source: .mine)]))
        #expect(inbox.sections.isEmpty)
    }

    @Test func emitsNonEmptySectionsInDisplayOrder() {
        let inbox = InboxBuilder.build(
            makeResult([
                makePR(id: "w", source: .mine),
                makePR(id: "m", source: .mentions),
                makePR(id: "r", source: .review),
            ]))
        #expect(inbox.sections.map(\.kind) == [.needsReview, .mentions, .waitingOnOthers])
    }

    @Test func reviewSectionsPutTheLongestWaitingFirst() {
        let inbox = InboxBuilder.build(
            makeResult([
                makePR(id: "new", number: 3, reviewRequestedAt: date("2026-08-05T10:00:00Z")),
                makePR(id: "old", number: 2, reviewRequestedAt: date("2026-08-02T10:00:00Z")),
                makePR(id: "tie", number: 1, reviewRequestedAt: date("2026-08-05T10:00:00Z")),
            ]))
        #expect(inbox.section(.needsReview)?.rows.map(\.id) == ["old", "tie", "new"])
    }

    @Test func ownSectionsPutTheNewestFirst() {
        let inbox = InboxBuilder.build(
            makeResult([
                makePR(id: "a", updatedAt: date("2026-08-02T10:00:00Z"), source: .mine),
                makePR(id: "b", updatedAt: date("2026-08-05T10:00:00Z"), source: .mine),
            ]))
        #expect(inbox.section(.waitingOnOthers)?.rows.map(\.id) == ["b", "a"])
    }

    @Test func badgeCountsReviewAndMentionSectionsWithoutDrafts() {
        let inbox = InboxBuilder.build(
            makeResult([
                makePR(id: "r1"), makePR(id: "r2"), makePR(id: "draft", isDraft: true),
                makePR(id: "again", viewerReview: reviewed),
                makePR(id: "m", source: .mentions),
                makePR(id: "mine", reviewDecision: .approved, source: .mine),
            ]))
        #expect(inbox.badgeCount == 4)
    }

    @Test func capsRowsAndCountsTheOverflow() {
        let prs = (1...10).map { makePR(id: "p\($0)", number: $0) }
        let section = InboxBuilder.build(makeResult(prs)).section(.needsReview)
        #expect(section?.rows.count == 8)
        #expect(section?.count == 10)
        #expect(section?.moreCount == 2)
    }

    @Test func unfetchedResultsGoToTheLastSectionOfTheirSearch() {
        let result = makeResult([makePR(id: "r")], totals: [.review: 12, .mentions: 0, .mine: 0])
        let inbox = InboxBuilder.build(result)
        #expect(inbox.section(.needsReview)?.moreCount == 0)
        #expect(inbox.section(.takeAnotherLook)?.rows.isEmpty == true)
        #expect(inbox.section(.takeAnotherLook)?.moreCount == 11)
    }

    @Test func passesWarningsThrough() {
        #expect(InboxBuilder.build(makeResult([], warnings: ["w"])).warnings == ["w"])
    }

    @Test func emptyResultIsAnEmptyInbox() {
        let inbox = InboxBuilder.build(makeResult([]))
        #expect(inbox.isEmpty)
        #expect(inbox.badgeCount == 0)
    }
}
```

- [x] **Step 2: Run the tests and confirm they fail**

Run: `swift test`
Expected: the build fails with `cannot find 'InboxBuilder' in scope`.

- [x] **Step 3: Implement**

`Sources/PrinboxCore/Inbox/Inbox.swift`:
```swift
import Foundation

public struct InboxRow: Sendable, Equatable, Identifiable {
    public let pullRequest: PullRequest
    public let classification: Classification
    public var id: String { pullRequest.id }
}

public struct InboxSection: Sendable, Equatable, Identifiable {
    public let kind: SectionKind
    /// Rows to display, sorted and capped.
    public let rows: [InboxRow]
    /// Everything GitHub has for this section: classified rows plus unfetched search results.
    public let count: Int
    /// Rows hidden by the cap plus unfetched results. Above zero, a "+N more on GitHub" row is shown.
    public let moreCount: Int
    public var id: SectionKind { kind }
}

public struct Inbox: Sendable, Equatable {
    public let sections: [InboxSection]
    public let badgeCount: Int
    public let warnings: [String]

    public static let empty = Inbox(sections: [], badgeCount: 0, warnings: [])

    public var isEmpty: Bool { sections.isEmpty }

    public func section(_ kind: SectionKind) -> InboxSection? { sections.first { $0.kind == kind } }
}
```

`Sources/PrinboxCore/Inbox/InboxBuilder.swift`:
```swift
import Foundation

/// Turns a fetch into the displayed inbox. The steps are:
/// 1. drop archived repositories
/// 2. classify
/// 3. sort each section
/// 4. cap each section
/// 5. count the badge
public enum InboxBuilder {
    public static let rowCap = 8

    /// The unfetched remainder of each search is attributed to the last section that search feeds.
    static let remainderSection: [SearchSource: SectionKind] = [
        .review: .takeAnotherLook, .mentions: .mentions, .mine: .waitingOnOthers,
    ]

    public static func build(_ result: FetchResult, cap: Int = rowCap) -> Inbox {
        let rows = result.pullRequests
            .filter { !$0.isArchived }
            .map { InboxRow(pullRequest: $0, classification: Classifier.classify($0)) }
        let remainders = unfetchedBySection(result)
        let sections = SectionKind.allCases.compactMap { kind -> InboxSection? in
            let members = sorted(rows.filter { $0.classification.section == kind }, kind: kind)
            let remainder = remainders[kind] ?? 0
            guard !members.isEmpty || remainder > 0 else { return nil }
            return InboxSection(
                kind: kind, rows: Array(members.prefix(cap)), count: members.count + remainder,
                moreCount: max(0, members.count - cap) + remainder)
        }
        let badge = rows.filter { $0.classification.section.countsTowardBadge && !$0.pullRequest.isDraft }.count
        return Inbox(sections: sections, badgeCount: badge, warnings: result.warnings)
    }

    static func unfetchedBySection(_ result: FetchResult) -> [SectionKind: Int] {
        Dictionary(
            uniqueKeysWithValues: remainderSection.map { source, kind in
                (kind, max(0, (result.totals[source] ?? 0) - (result.fetched[source] ?? 0)))
            })
    }

    /// Review sections: longest waiting first. Own sections: newest update first. Ties: lower number first.
    static func sorted(_ rows: [InboxRow], kind: SectionKind) -> [InboxRow] {
        rows.sorted { lhs, rhs in
            if kind.sortsByRecency, lhs.pullRequest.updatedAt != rhs.pullRequest.updatedAt {
                return lhs.pullRequest.updatedAt > rhs.pullRequest.updatedAt
            }
            if !kind.sortsByRecency {
                let left = lhs.classification.waitingSince ?? .distantFuture
                let right = rhs.classification.waitingSince ?? .distantFuture
                if left != right { return left < right }
            }
            return lhs.pullRequest.number < rhs.pullRequest.number
        }
    }
}
```

- [x] **Step 4: Run the tests and confirm they pass**

Run: `swift test`
Expected: every test passes.

- [x] **Step 5: Commit**

```bash
make format && make lint
git add Sources/PrinboxCore/Inbox Tests/PrinboxCoreTests
git commit -m "feat: build sorted, capped inbox sections and the badge count"
```

---

### Task 7: Formatting and the text printer

**Files:**
- Create: `Sources/PrinboxCore/Format/RelativeAge.swift`, `ClockText.swift`, `RowText.swift`, `FetchErrorText.swift`, `InboxPrinter.swift`
- Test: `Tests/PrinboxCoreTests/Format/RelativeAgeTests.swift`, `RowTextTests.swift`, `FetchErrorTextTests.swift`, `InboxPrinterTests.swift`

**Interfaces:**
- Consumes: `InboxRow`, `Inbox` and `InboxBuilder` (Task 6), `FetchError` (Task 2).
- Produces:
  - `RelativeAge.format(from:to:) -> String`
  - `ClockText.hhmm(_:timeZone:) -> String`
  - `RowText.title(_:)`, `.meta(_:now:)`, `.detail(_:now:)`, `.compact(_:)`, `.more(_:)`, `.initials(_:)`, `.header(badgeCount:lastSuccess:timeZone:)`
  - `FetchError.message(lastSuccess:timeZone:) -> String`
  - `InboxPrinter.render(_:now:) -> String`

- [x] **Step 1: Write the failing tests**

`Tests/PrinboxCoreTests/Format/RelativeAgeTests.swift`:
```swift
import Foundation
import Testing

@testable import PrinboxCore

@Suite struct RelativeAgeTests {
    let now = date("2026-08-10T12:00:00Z")

    func age(_ seconds: TimeInterval) -> String {
        RelativeAge.format(from: now.addingTimeInterval(-seconds), to: now)
    }

    @Test func boundaries() {
        #expect(age(0) == "<1m")
        #expect(age(59) == "<1m")
        #expect(age(60) == "1m")
        #expect(age(59 * 60) == "59m")
        #expect(age(60 * 60) == "1h")
        #expect(age(47 * 3600 + 59 * 60) == "47h")
        #expect(age(48 * 3600) == "2d")
    }

    @Test func futureTimestampsReadAsJustNow() {
        #expect(age(-300) == "<1m")
    }

    @Test func clockTextUsesTheGivenTimeZone() throws {
        let instant = date("2026-08-10T12:05:00Z")
        #expect(ClockText.hhmm(instant, timeZone: try #require(TimeZone(identifier: "UTC"))) == "12:05")
        #expect(ClockText.hhmm(instant, timeZone: try #require(TimeZone(identifier: "Europe/Warsaw"))) == "14:05")
    }
}
```

`Tests/PrinboxCoreTests/Format/RowTextTests.swift`:
```swift
import Foundation
import Testing

@testable import PrinboxCore

@Suite struct RowTextTests {
    let now = date("2026-08-10T12:00:00Z")
    let utc = TimeZone(identifier: "UTC")!

    func row(_ pr: PullRequest) -> InboxRow {
        InboxRow(pullRequest: pr, classification: Classifier.classify(pr))
    }

    @Test func titleShowsNumberAndTitle() {
        #expect(RowText.title(makePR(number: 12, title: "Fix it")) == "#12 Fix it")
    }

    @Test func titleCollapsesLineBreaksAndTabs() {
        #expect(RowText.title(makePR(number: 1, title: "Fix\nthe\t\tthing\r\nnow")) == "#1 Fix the thing now")
    }

    @Test func reviewRowsSayHowLongTheyWaited() {
        let pr = makePR(additions: 120, deletions: 4, reviewRequestedAt: date("2026-08-10T06:00:00Z"))
        #expect(RowText.meta(row(pr), now: now) == "web · waiting 6h · +120 −4")
        #expect(RowText.detail(row(pr), now: now) == "web · waiting 6h · +120 −4 · Review requested")
    }

    @Test func ownRowsSayWhenTheyWereUpdated() {
        let pr = makePR(additions: 1, deletions: 0, updatedAt: date("2026-08-10T09:00:00Z"), source: .mine)
        #expect(RowText.meta(row(pr), now: now) == "web · updated 3h ago · +1 −0")
    }

    @Test func compactRowIsOneLine() {
        #expect(RowText.compact(row(makePR(number: 9, title: "Mine", source: .mine))) == "#9 Mine · Waiting for review")
    }

    @Test func moreRow() {
        #expect(RowText.more(3) == "+3 more on GitHub")
    }

    @Test func initials() {
        #expect(RowText.initials("alice") == "AL")
        #expect(RowText.initials("x") == "X")
    }

    @Test func header() {
        #expect(RowText.header(badgeCount: 2, lastSuccess: nil, timeZone: utc) == "Loading…")
        #expect(
            RowText.header(badgeCount: 2, lastSuccess: date("2026-08-10T12:05:00Z"), timeZone: utc)
                == "2 waiting on you · updated 12:05")
    }
}
```

`Tests/PrinboxCoreTests/Format/FetchErrorTextTests.swift`:
```swift
import Foundation
import Testing

@testable import PrinboxCore

@Suite struct FetchErrorTextTests {
    let utc = TimeZone(identifier: "UTC")!
    let at = date("2026-08-10T14:05:00Z")

    func text(_ error: FetchError, lastSuccess: Date? = nil) -> String {
        error.message(lastSuccess: lastSuccess, timeZone: utc)
    }

    @Test func messages() {
        #expect(text(.ghNotFound) == "gh not found: brew install gh")
        #expect(text(.loggedOut) == "gh is not logged in: run gh auth login")
        #expect(text(.offline) == "Offline")
        #expect(text(.offline, lastSuccess: at) == "Offline, showing data from 14:05")
        #expect(text(.timedOut) == "GitHub did not answer in time")
        #expect(text(.rateLimited(resetAt: at)) == "Rate limited until 14:05")
        #expect(text(.rateLimited(resetAt: nil)) == "Rate limited by GitHub")
        #expect(text(.badResponse) == "Unexpected response from gh")
        #expect(text(.other("boom")) == "boom")
    }
}
```

`Tests/PrinboxCoreTests/Format/InboxPrinterTests.swift`:
```swift
import Foundation
import Testing

@testable import PrinboxCore

@Suite struct InboxPrinterTests {
    let now = date("2026-08-10T12:00:00Z")

    @Test func rendersSectionsRowsAndWarnings() {
        let inbox = InboxBuilder.build(
            makeResult(
                [
                    makePR(
                        id: "a", number: 101, title: "Review me", repository: "acme/web",
                        reviewRequestedAt: date("2026-08-10T06:00:00Z")),
                    makePR(id: "b", number: 9, title: "Mine", repository: "acme/api", source: .mine),
                ], warnings: ["w1"]))
        let expected = """
            waiting on you: 1

            Needs your review (1)
              #101 Review me  [acme/web]
                  web · waiting 6h · +10 −2 · Review requested

            Waiting on others (1)
              #9 Mine · Waiting for review  [acme/api]

            warning: w1
            """
        #expect(InboxPrinter.render(inbox, now: now) == expected)
    }

    @Test func rendersInboxZero() {
        #expect(InboxPrinter.render(.empty, now: now) == "waiting on you: 0\n\nInbox zero. Nothing waiting on you.")
    }
}
```

- [x] **Step 2: Run the tests and confirm they fail**

Run: `swift test`
Expected: the build fails with `cannot find 'RelativeAge' in scope`.

- [x] **Step 3: Implement**

`Sources/PrinboxCore/Format/RelativeAge.swift`:
```swift
import Foundation

public enum RelativeAge {
    /// Floored age, using the thresholds of the sketchybar prototype: <1m, Nm, Nh (under 48 h), Nd.
    /// Future timestamps (clock skew) read as "<1m".
    public static func format(from start: Date, to now: Date) -> String {
        let minutes = Int(max(0, now.timeIntervalSince(start)) / 60)
        if minutes < 1 { return "<1m" }
        if minutes < 60 { return "\(minutes)m" }
        if minutes < 48 * 60 { return "\(minutes / 60)h" }
        return "\(minutes / (24 * 60))d"
    }
}
```

`Sources/PrinboxCore/Format/ClockText.swift`:
```swift
import Foundation

public enum ClockText {
    /// 24-hour "HH:MM" in the given time zone.
    public static func hhmm(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}
```

`Sources/PrinboxCore/Format/RowText.swift`:
```swift
import Foundation

/// Every string shown for a row, a header or a placeholder, shared by the popover and `--print`.
public enum RowText {
    /// "#12 Title". Line breaks and tabs become single spaces so a row never wraps.
    public static func title(_ pr: PullRequest) -> String {
        let flat = pr.title.split(whereSeparator: { $0.isNewline || $0 == "\t" }).joined(separator: " ")
        return "#\(pr.number) \(flat)"
    }

    /// "web · waiting 6h · +120 −4" for review sections, "web · updated 3h ago · +1 −0" for own PRs.
    public static func meta(_ row: InboxRow, now: Date) -> String {
        let pr = row.pullRequest
        let age =
            row.classification.waitingSince.map { "waiting \(RelativeAge.format(from: $0, to: now))" }
            ?? "updated \(RelativeAge.format(from: pr.updatedAt, to: now)) ago"
        return [pr.repoShortName, age, "+\(pr.additions) −\(pr.deletions)"].joined(separator: " · ")
    }

    public static func detail(_ row: InboxRow, now: Date) -> String {
        "\(meta(row, now: now)) · \(row.classification.reason.rawValue)"
    }

    /// One-line row for Waiting on others: "#9 Title · Waiting for review".
    public static func compact(_ row: InboxRow) -> String {
        "\(title(row.pullRequest)) · \(row.classification.reason.rawValue)"
    }

    public static func more(_ count: Int) -> String { "+\(count) more on GitHub" }

    /// Up to two uppercase characters for the avatar placeholder.
    public static func initials(_ login: String) -> String { String(login.prefix(2)).uppercased() }

    /// "3 waiting on you · updated 14:05", or "Loading…" before the first successful refresh.
    public static func header(badgeCount: Int, lastSuccess: Date?, timeZone: TimeZone = .current) -> String {
        guard let lastSuccess else { return "Loading…" }
        return "\(badgeCount) waiting on you · updated \(ClockText.hhmm(lastSuccess, timeZone: timeZone))"
    }
}
```

`Sources/PrinboxCore/Format/FetchErrorText.swift`:
```swift
import Foundation

extension FetchError {
    /// One line for the popover warning line and the status item tooltip.
    public func message(lastSuccess: Date?, timeZone: TimeZone = .current) -> String {
        switch self {
        case .ghNotFound:
            "gh not found: brew install gh"
        case .loggedOut:
            "gh is not logged in: run gh auth login"
        case .offline:
            lastSuccess.map { "Offline, showing data from \(ClockText.hhmm($0, timeZone: timeZone))" } ?? "Offline"
        case .timedOut:
            "GitHub did not answer in time"
        case .rateLimited(let resetAt):
            resetAt.map { "Rate limited until \(ClockText.hhmm($0, timeZone: timeZone))" } ?? "Rate limited by GitHub"
        case .badResponse:
            "Unexpected response from gh"
        case .other(let message):
            message
        }
    }
}
```

`Sources/PrinboxCore/Format/InboxPrinter.swift`:
```swift
import Foundation

/// Plain-text rendering for `Prinbox --print`, the live end-to-end check. Full repository names are
/// printed so exclusions (archived repositories) can be verified.
public enum InboxPrinter {
    public static func render(_ inbox: Inbox, now: Date) -> String {
        let header = "waiting on you: \(inbox.badgeCount)"
        let body =
            inbox.isEmpty
            ? ["", "Inbox zero. Nothing waiting on you."]
            : inbox.sections.flatMap { section in
                ["", "\(section.kind.title) (\(section.count))"]
                    + section.rows.flatMap { lines(for: $0, compact: section.kind.usesCompactRows, now: now) }
                    + (section.moreCount > 0 ? ["  \(RowText.more(section.moreCount))"] : [])
            }
        let warnings = inbox.warnings.isEmpty ? [] : [""] + inbox.warnings.map { "warning: \($0)" }
        return ([header] + body + warnings).joined(separator: "\n")
    }

    static func lines(for row: InboxRow, compact: Bool, now: Date) -> [String] {
        let repo = "[\(row.pullRequest.repository)]"
        if compact { return ["  \(RowText.compact(row))  \(repo)"] }
        return ["  \(RowText.title(row.pullRequest))  \(repo)", "      \(RowText.detail(row, now: now))"]
    }
}
```

- [x] **Step 4: Run the tests and confirm they pass**

Run: `swift test`
Expected: every test passes.

- [x] **Step 5: Commit**

```bash
make format && make lint
git add Sources/PrinboxCore/Format Tests/PrinboxCoreTests/Format
git commit -m "feat: format ages, rows, errors and a plain-text inbox"
```

---

### Task 8: Inbox store and status badge

**Files:**
- Create: `Sources/PrinboxCore/State/StatusBadge.swift`
- Create: `Sources/PrinboxCore/State/InboxStore.swift`
- Create: `Tests/PrinboxCoreTests/Support/TestClock.swift`, `Tests/PrinboxCoreTests/Support/ScriptedFetcher.swift`
- Test: `Tests/PrinboxCoreTests/State/StatusBadgeTests.swift`, `Tests/PrinboxCoreTests/State/InboxStoreTests.swift`

**Interfaces:**
- Consumes: `InboxFetching` (Task 4), `InboxBuilder` and `Inbox` (Task 6), `FetchError.message` (Task 7).
- Produces:
  - `public enum StatusBadge { loading, count(Int), zero, error(String) }` with `static func derive(inbox:error:lastSuccess:timeZone:)`
  - `@MainActor @Observable public final class InboxStore` with:
    - `inbox`, `error`, `lastSuccess`, `isRefreshing`, `badge` and `warningLines`
    - `init(fetcher:clock:)`
    - `func refresh() async` and `func refreshIfStale() async`
  - Test helpers `TestClock` and `ScriptedFetcher`

- [x] **Step 1: Write the test helpers and the failing tests**

`Tests/PrinboxCoreTests/Support/TestClock.swift`:
```swift
import Foundation

/// A clock the tests move by hand. `now` is read from `@Sendable` closures, hence the lock.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date) { current = start }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(_ seconds: TimeInterval) {
        lock.lock()
        current += seconds
        lock.unlock()
    }
}
```

`Tests/PrinboxCoreTests/Support/ScriptedFetcher.swift`:
```swift
@testable import PrinboxCore

/// Fetcher whose answer depends on the call number (1-based).
actor ScriptedFetcher: InboxFetching {
    private(set) var calls = 0
    private let script: @Sendable (Int) async throws -> FetchResult

    init(_ script: @escaping @Sendable (Int) async throws -> FetchResult) { self.script = script }

    func fetch() async throws -> FetchResult {
        calls += 1
        return try await script(calls)
    }
}
```

`Tests/PrinboxCoreTests/State/StatusBadgeTests.swift`:
```swift
import Foundation
import Testing

@testable import PrinboxCore

@Suite struct StatusBadgeTests {
    let utc = TimeZone(identifier: "UTC")!

    @Test func loadingBeforeAnyData() {
        #expect(StatusBadge.derive(inbox: nil, error: nil, lastSuccess: nil, timeZone: utc) == .loading)
    }

    @Test func countWhenSomethingWaits() {
        let inbox = InboxBuilder.build(makeResult([makePR()]))
        #expect(StatusBadge.derive(inbox: inbox, error: nil, lastSuccess: nil, timeZone: utc) == .count(1))
    }

    @Test func zeroWhenNothingWaits() {
        #expect(StatusBadge.derive(inbox: .empty, error: nil, lastSuccess: nil, timeZone: utc) == .zero)
    }

    @Test func errorWinsOverData() {
        let badge = StatusBadge.derive(inbox: .empty, error: .loggedOut, lastSuccess: nil, timeZone: utc)
        #expect(badge == .error("gh is not logged in: run gh auth login"))
    }
}
```

`Tests/PrinboxCoreTests/State/InboxStoreTests.swift`:
```swift
import Foundation
import Testing

@testable import PrinboxCore

@MainActor
final class StoreHolder {
    var store: InboxStore?
}

@MainActor
@Suite struct InboxStoreTests {
    let start = date("2026-08-10T12:00:00Z")

    @Test func successfulRefreshBuildsTheInbox() async {
        let clock = TestClock(start)
        let store = InboxStore(fetcher: ScriptedFetcher { _ in makeResult([makePR()]) }, clock: { clock.now })
        await store.refresh()
        #expect(store.inbox?.badgeCount == 1)
        #expect(store.error == nil)
        #expect(store.lastSuccess == start)
        #expect(store.badge == .count(1))
        #expect(store.isRefreshing == false)
    }

    @Test func failedRefreshKeepsTheLastInbox() async {
        let fetcher = ScriptedFetcher { call in
            if call == 1 { return makeResult([makePR()]) }
            throw FetchError.offline
        }
        let store = InboxStore(fetcher: fetcher)
        await store.refresh()
        await store.refresh()
        #expect(store.inbox?.badgeCount == 1)
        #expect(store.error == .offline)
        #expect(store.badge == .error(FetchError.offline.message(lastSuccess: store.lastSuccess)))
    }

    @Test func successAfterFailureClearsTheError() async {
        let fetcher = ScriptedFetcher { call in
            if call == 1 { throw FetchError.loggedOut }
            return makeResult([])
        }
        let store = InboxStore(fetcher: fetcher)
        await store.refresh()
        #expect(store.error == .loggedOut)
        await store.refresh()
        #expect(store.error == nil)
        #expect(store.badge == .zero)
    }

    @Test func refreshRequestedDuringAFetchRunsExactlyOnceMore() async {
        let holder = StoreHolder()
        let fetcher = ScriptedFetcher { call in
            if call == 1, let store = await holder.store {
                await store.refresh()
                await store.refresh()
            }
            return makeResult([])
        }
        let store = InboxStore(fetcher: fetcher)
        holder.store = store
        await store.refresh()
        #expect(await fetcher.calls == 2)
        #expect(store.isRefreshing == false)
    }

    @Test func rateLimitPausesRefreshesUntilReset() async {
        let clock = TestClock(start)
        let reset = start.addingTimeInterval(600)
        let fetcher = ScriptedFetcher { call in
            if call == 1 { throw FetchError.rateLimited(resetAt: reset) }
            return makeResult([])
        }
        let store = InboxStore(fetcher: fetcher, clock: { clock.now })
        await store.refresh()
        clock.advance(300)
        await store.refresh()
        #expect(await fetcher.calls == 1)
        #expect(store.error == .rateLimited(resetAt: reset))
        clock.advance(301)
        await store.refresh()
        #expect(await fetcher.calls == 2)
        #expect(store.error == nil)
    }

    @Test func rateLimitWithoutResetPausesFifteenMinutes() async {
        let clock = TestClock(start)
        let fetcher = ScriptedFetcher { call in
            if call == 1 { throw FetchError.rateLimited(resetAt: nil) }
            return makeResult([])
        }
        let store = InboxStore(fetcher: fetcher, clock: { clock.now })
        await store.refresh()
        clock.advance(14 * 60)
        await store.refresh()
        #expect(await fetcher.calls == 1)
        clock.advance(61)
        await store.refresh()
        #expect(await fetcher.calls == 2)
    }

    @Test func refreshIfStaleOnlyFetchesOldData() async {
        let clock = TestClock(start)
        let fetcher = ScriptedFetcher { _ in makeResult([]) }
        let store = InboxStore(fetcher: fetcher, clock: { clock.now })
        await store.refreshIfStale()
        #expect(await fetcher.calls == 1)
        clock.advance(30)
        await store.refreshIfStale()
        #expect(await fetcher.calls == 1)
        clock.advance(31)
        await store.refreshIfStale()
        #expect(await fetcher.calls == 2)
    }

    @Test func unexpectedErrorsBecomeOther() async {
        let store = InboxStore(fetcher: ScriptedFetcher { _ in throw CancellationError() })
        await store.refresh()
        guard case .other = store.error else {
            Issue.record("expected .other, got \(String(describing: store.error))")
            return
        }
    }

    @Test func warningLinesPutTheErrorFirst() async {
        let fetcher = ScriptedFetcher { call in
            if call == 1 { return makeResult([], warnings: ["acme restricts gh (OAuth app access): results incomplete"]) }
            throw FetchError.offline
        }
        let store = InboxStore(fetcher: fetcher)
        await store.refresh()
        await store.refresh()
        #expect(
            store.warningLines == [
                FetchError.offline.message(lastSuccess: store.lastSuccess),
                "acme restricts gh (OAuth app access): results incomplete",
            ])
    }
}
```

- [x] **Step 2: Run the tests and confirm they fail**

Run: `swift test`
Expected: the build fails with `cannot find 'InboxStore' in scope`.

- [x] **Step 3: Implement**

`Sources/PrinboxCore/State/StatusBadge.swift`:
```swift
import Foundation

/// What the menu-bar item shows.
public enum StatusBadge: Equatable, Sendable {
    case loading
    case count(Int)
    case zero
    case error(String)

    public static func derive(
        inbox: Inbox?, error: FetchError?, lastSuccess: Date?, timeZone: TimeZone = .current
    ) -> StatusBadge {
        if let error { return .error(error.message(lastSuccess: lastSuccess, timeZone: timeZone)) }
        guard let inbox else { return .loading }
        return inbox.badgeCount > 0 ? .count(inbox.badgeCount) : .zero
    }
}
```

`Sources/PrinboxCore/State/InboxStore.swift`:
```swift
import Foundation
import Observation

/// Owns the inbox and serializes refreshes:
/// - One fetch runs at a time.
/// - A refresh requested meanwhile runs exactly once afterwards.
/// - Rate limiting pauses refreshes until GitHub's reset time.
/// - A failure keeps the last good inbox.
@MainActor
@Observable
public final class InboxStore {
    public static let staleAfter: TimeInterval = 60
    public static let rateLimitFallbackPause: TimeInterval = 15 * 60

    public private(set) var inbox: Inbox?
    public private(set) var error: FetchError?
    public private(set) var lastSuccess: Date?
    public private(set) var isRefreshing = false

    @ObservationIgnored private var followUpRequested = false
    @ObservationIgnored private var pausedUntil: Date?
    @ObservationIgnored private let fetcher: InboxFetching
    @ObservationIgnored private let clock: @Sendable () -> Date

    public init(fetcher: InboxFetching, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.fetcher = fetcher
        self.clock = clock
    }

    public var badge: StatusBadge {
        StatusBadge.derive(inbox: inbox, error: error, lastSuccess: lastSuccess)
    }

    /// The current error (if any) followed by partial-data warnings.
    public var warningLines: [String] {
        (error.map { [$0.message(lastSuccess: lastSuccess)] } ?? []) + (inbox?.warnings ?? [])
    }

    public func refresh() async {
        guard !isPaused else { return }
        guard !isRefreshing else {
            followUpRequested = true
            return
        }
        isRefreshing = true
        repeat {
            followUpRequested = false
            await fetchOnce()
        } while followUpRequested && !isPaused
        isRefreshing = false
    }

    /// Refreshes only when the last success is older than `staleAfter`. Used when the popover opens.
    public func refreshIfStale() async {
        if let lastSuccess, clock().timeIntervalSince(lastSuccess) < Self.staleAfter { return }
        await refresh()
    }

    private var isPaused: Bool {
        pausedUntil.map { clock() < $0 } ?? false
    }

    private func fetchOnce() async {
        do {
            let result = try await fetcher.fetch()
            inbox = InboxBuilder.build(result)
            error = nil
            lastSuccess = clock()
            pausedUntil = nil
        } catch let failure as FetchError {
            error = failure
            if case .rateLimited(let resetAt) = failure {
                pausedUntil = resetAt ?? clock().addingTimeInterval(Self.rateLimitFallbackPause)
            }
        } catch {
            self.error = .other(String(String(describing: error).prefix(120)))
        }
    }
}
```

- [x] **Step 4: Run the tests and confirm they pass**

Run: `swift test`
Expected: every test passes.

- [x] **Step 5: Commit**

```bash
make format && make lint
git add Sources/PrinboxCore/State Tests/PrinboxCoreTests
git commit -m "feat: add inbox store with coalesced refresh and rate-limit pause"
```

---

### Task 9: Global shortcut model

**Files:**
- Create: `Sources/PrinboxCore/State/KeyValueStoring.swift`
- Create: `Sources/PrinboxCore/State/HotKeySpec.swift`
- Create: `Sources/PrinboxCore/State/HotKeySettings.swift`
- Create: `Tests/PrinboxCoreTests/Support/MemoryDefaults.swift`
- Test: `Tests/PrinboxCoreTests/State/HotKeySpecTests.swift`, `Tests/PrinboxCoreTests/State/HotKeySettingsTests.swift`

**Interfaces:**
- Produces:
  - `public protocol KeyValueStoring: AnyObject { object(forKey:) -> Any?; set(_:forKey:) }`, which `UserDefaults` conforms to
  - `public struct HotKeyModifiers: OptionSet` with `.control`, `.option`, `.shift` and `.command`
  - `public struct HotKeySpec`:
    - properties `keyCode: UInt32` and `modifiers`
    - `.default`
    - `static func recorded(keyCode: UInt16, modifiers:) -> HotKeySpec?`
    - `displayString` and `carbonModifiers`
    - `storedValue: [Int]` and `init?(storedValue:)`
  - `@MainActor @Observable public final class HotKeySettings`:
    - `spec: HotKeySpec?`, where nil means no shortcut
    - `isUnavailable: Bool`
    - `update(_:)`
  - Test helper `MemoryDefaults`

- [x] **Step 1: Write the failing tests**

`Tests/PrinboxCoreTests/Support/MemoryDefaults.swift`:
```swift
@testable import PrinboxCore

final class MemoryDefaults: KeyValueStoring {
    private var storage: [String: Any] = [:]

    func object(forKey defaultName: String) -> Any? { storage[defaultName] }

    func set(_ value: Any?, forKey defaultName: String) { storage[defaultName] = value }
}
```

`Tests/PrinboxCoreTests/State/HotKeySpecTests.swift`:
```swift
import Testing

@testable import PrinboxCore

@Suite struct HotKeySpecTests {
    @Test func defaultIsControlOptionP() {
        #expect(HotKeySpec.default.displayString == "⌃⌥P")
        #expect(HotKeySpec.default.carbonModifiers == 4096 | 2048)
    }

    @Test func modifiersDisplayInMenuOrder() {
        let spec = HotKeySpec(keyCode: 0, modifiers: [.command, .shift, .option, .control])
        #expect(spec.displayString == "⌃⌥⇧⌘A")
        #expect(spec.carbonModifiers == 256 | 512 | 2048 | 4096)
    }

    @Test func unknownKeysGetANumberedName() {
        #expect(HotKeySpec(keyCode: 200, modifiers: [.command]).displayString == "⌘Key 200")
    }

    @Test func recordingRequiresControlOptionOrCommand() {
        #expect(HotKeySpec.recorded(keyCode: 35, modifiers: [.shift]) == nil)
        #expect(HotKeySpec.recorded(keyCode: 35, modifiers: []) == nil)
        #expect(HotKeySpec.recorded(keyCode: 35, modifiers: [.option]) == HotKeySpec(keyCode: 35, modifiers: [.option]))
    }

    @Test func storedValueRoundTrips() {
        let spec = HotKeySpec(keyCode: 15, modifiers: [.command, .shift])
        #expect(HotKeySpec(storedValue: spec.storedValue) == spec)
        #expect(HotKeySpec(storedValue: []) == nil)
        #expect(HotKeySpec(storedValue: [1]) == nil)
    }
}
```

`Tests/PrinboxCoreTests/State/HotKeySettingsTests.swift`:
```swift
import Testing

@testable import PrinboxCore

@MainActor
@Suite struct HotKeySettingsTests {
    @Test func firstRunUsesTheDefault() {
        #expect(HotKeySettings(defaults: MemoryDefaults()).spec == .default)
    }

    @Test func clearingPersistsAsNoShortcut() {
        let defaults = MemoryDefaults()
        HotKeySettings(defaults: defaults).update(nil)
        #expect(HotKeySettings(defaults: defaults).spec == nil)
    }

    @Test func updatePersists() {
        let defaults = MemoryDefaults()
        let spec = HotKeySpec(keyCode: 15, modifiers: [.command, .option])
        HotKeySettings(defaults: defaults).update(spec)
        #expect(HotKeySettings(defaults: defaults).spec == spec)
    }

    @Test func malformedStoredValueMeansNoShortcut() {
        let defaults = MemoryDefaults()
        defaults.set([7], forKey: HotKeySettings.key)
        #expect(HotKeySettings(defaults: defaults).spec == nil)
    }
}
```

- [x] **Step 2: Run the tests and confirm they fail**

Run: `swift test`
Expected: the build fails with `cannot find type 'KeyValueStoring' in scope`.

- [x] **Step 3: Implement**

`Sources/PrinboxCore/State/KeyValueStoring.swift`:
```swift
import Foundation

/// The part of `UserDefaults` prinbox uses. Tests substitute an in-memory store.
public protocol KeyValueStoring: AnyObject {
    func object(forKey defaultName: String) -> Any?
    func set(_ value: Any?, forKey defaultName: String)
}

extension UserDefaults: KeyValueStoring {}
```

`Sources/PrinboxCore/State/HotKeySpec.swift`:
```swift
import Foundation

public struct HotKeyModifiers: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let control = HotKeyModifiers(rawValue: 1 << 0)
    public static let option = HotKeyModifiers(rawValue: 1 << 1)
    public static let shift = HotKeyModifiers(rawValue: 1 << 2)
    public static let command = HotKeyModifiers(rawValue: 1 << 3)
}

/// A global shortcut: a virtual key code plus modifiers.
public struct HotKeySpec: Equatable, Sendable {
    public let keyCode: UInt32
    public let modifiers: HotKeyModifiers

    /// ⌃⌥P, the same default as Pullover.
    public static let `default` = HotKeySpec(keyCode: 35, modifiers: [.control, .option])

    public init(keyCode: UInt32, modifiers: HotKeyModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// A recorded shortcut must include ⌃, ⌥ or ⌘ so that ordinary typing can never trigger it.
    public static func recorded(keyCode: UInt16, modifiers: HotKeyModifiers) -> HotKeySpec? {
        guard !modifiers.isDisjoint(with: [.control, .option, .command]) else { return nil }
        return HotKeySpec(keyCode: UInt32(keyCode), modifiers: modifiers)
    }

    /// "⌃⌥P": modifiers in macOS menu order, then the key name.
    public var displayString: String {
        let symbols: [(HotKeyModifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return symbols.filter { modifiers.contains($0.0) }.map(\.1).joined() + KeyNames.name(for: keyCode)
    }

    /// Carbon mask for RegisterEventHotKey: cmdKey 1<<8, shiftKey 1<<9, optionKey 1<<11, controlKey 1<<12.
    public var carbonModifiers: UInt32 {
        let masks: [(HotKeyModifiers, UInt32)] = [
            (.command, 1 << 8), (.shift, 1 << 9), (.option, 1 << 11), (.control, 1 << 12),
        ]
        return masks.filter { modifiers.contains($0.0) }.reduce(0) { $0 | $1.1 }
    }

    /// The user-defaults form: `[keyCode, modifiers]`.
    public var storedValue: [Int] { [Int(keyCode), modifiers.rawValue] }

    public init?(storedValue: [Int]) {
        guard storedValue.count == 2, let code = UInt32(exactly: storedValue[0]) else { return nil }
        self.init(keyCode: code, modifiers: HotKeyModifiers(rawValue: storedValue[1]))
    }
}

/// Names for ANSI virtual key codes (Carbon kVK_*).
enum KeyNames {
    static func name(for keyCode: UInt32) -> String { names[keyCode] ?? "Key \(keyCode)" }

    static let names: [UInt32: String] = [
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J", 40: "K",
        37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U",
        9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
        49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 53: "⎋", 123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
        27: "-", 24: "=", 33: "[", 30: "]", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/", 42: "\\", 50: "`",
    ]
}
```

`Sources/PrinboxCore/State/HotKeySettings.swift`:
```swift
import Foundation
import Observation

/// The persisted global shortcut. `spec == nil` means the user removed it.
@MainActor
@Observable
public final class HotKeySettings {
    public static let key = "globalShortcut"

    public private(set) var spec: HotKeySpec?
    /// Set by the app when registration fails, typically because another app owns the shortcut.
    public var isUnavailable = false

    @ObservationIgnored private let defaults: KeyValueStoring

    public init(defaults: KeyValueStoring) {
        self.defaults = defaults
        if let stored = defaults.object(forKey: Self.key) as? [Int] {
            spec = HotKeySpec(storedValue: stored)
        } else {
            spec = .default
        }
    }

    public func update(_ spec: HotKeySpec?) {
        self.spec = spec
        defaults.set(spec?.storedValue ?? [], forKey: Self.key)
    }
}
```

- [x] **Step 4: Run the tests and confirm they pass**

Run: `swift test`
Expected: every test passes.

- [x] **Step 5: Commit**

```bash
make format && make lint
git add Sources/PrinboxCore/State Tests/PrinboxCoreTests
git commit -m "feat: model the global shortcut and persist it"
```

---

### Task 10: Popover navigation state

**Files:**
- Create: `Sources/PrinboxCore/State/InboxItemID.swift`
- Create: `Sources/PrinboxCore/State/Selection.swift`
- Create: `Sources/PrinboxCore/State/FoldStore.swift`
- Create: `Sources/PrinboxCore/State/KeyCommand.swift`
- Create: `Sources/PrinboxCore/State/PopoverState.swift`
- Test: `Tests/PrinboxCoreTests/State/SelectionTests.swift`, `InboxLayoutTests.swift`, `FoldStoreTests.swift`, `KeyCommandTests.swift`, `PopoverStateTests.swift`

**Interfaces:**
- Consumes:
  - `Inbox` and `SectionKind` (Tasks 5-6)
  - `InboxStore` (Task 8)
  - `KeyValueStoring` and `HotKeyModifiers` (Task 9)
  - Test helpers `ScriptedFetcher`, `makeResult` and `MemoryDefaults`
- Produces:
  - `public enum InboxItemID: Hashable { header(SectionKind), row(String), more(SectionKind) }`
  - `public enum InboxLayout { static func visibleItems(_:folded:) -> [InboxItemID] }`
  - `public struct Selection`:
    - `current`
    - `movingDown(in:)` and `movingUp(in:)`
    - `reconciled(previous:current:)`
  - `@MainActor @Observable public final class FoldStore`:
    - `key` and `defaultFolded`
    - `folded`, `isFolded(_:)` and `toggle(_:)`
  - `public enum KeyCommand { up, down, enter, refresh, escape }` with `init?(keyCode:characters:modifiers:)`
  - `public enum KeyAction: Equatable { handled, open(URL), refresh, close }`
  - `@MainActor @Observable public final class PopoverState`:
    - properties `store`, `folds`, `selection`, `showingSettings`, `isRecordingShortcut`, `contentHeight` and `items`
    - `isSelected(_:)`, `select(_:)` and `reconcileSelection()`
    - `toggleFold(_:)`, `activate(_:) -> KeyAction` and `handle(_:) -> KeyAction?`
    - `popoverWillShow()`, `refresh() async` and `refreshIfStale() async`

- [x] **Step 1: Write the failing tests**

`Tests/PrinboxCoreTests/State/SelectionTests.swift`:
```swift
import Testing

@testable import PrinboxCore

@Suite struct SelectionTests {
    let items: [InboxItemID] = [.header(.needsReview), .row("a"), .row("b"), .more(.needsReview)]

    @Test func downFromNothingSelectsTheFirstItem() {
        #expect(Selection().movingDown(in: items).current == .header(.needsReview))
    }

    @Test func upFromNothingSelectsTheLastItem() {
        #expect(Selection().movingUp(in: items).current == .more(.needsReview))
    }

    @Test func movementWrapsAtBothEnds() {
        #expect(Selection(current: .more(.needsReview)).movingDown(in: items).current == .header(.needsReview))
        #expect(Selection(current: .header(.needsReview)).movingUp(in: items).current == .more(.needsReview))
    }

    @Test func movingInAnEmptyListClearsTheSelection() {
        #expect(Selection(current: .row("a")).movingDown(in: []).current == nil)
    }

    @Test func reconcileKeepsASurvivingItem() {
        let after: [InboxItemID] = [.header(.needsReview), .row("b")]
        #expect(Selection(current: .row("b")).reconciled(previous: items, current: after).current == .row("b"))
    }

    @Test func foldingMovesTheSelectionToTheHeader() {
        let after: [InboxItemID] = [.header(.needsReview)]
        #expect(Selection(current: .row("b")).reconciled(previous: items, current: after).current == .header(.needsReview))
    }

    @Test func removedRowSelectsThePrecedingRow() {
        let after: [InboxItemID] = [.header(.needsReview), .row("a"), .more(.needsReview)]
        #expect(Selection(current: .row("b")).reconciled(previous: items, current: after).current == .row("a"))
    }

    @Test func reconcileWithEmptyInboxClearsSelection() {
        #expect(Selection(current: .row("a")).reconciled(previous: items, current: []).current == nil)
    }

    @Test func unknownItemFallsBackToTheFirst() {
        #expect(Selection(current: .row("zzz")).reconciled(previous: [], current: items).current == .header(.needsReview))
    }
}
```

`Tests/PrinboxCoreTests/State/InboxLayoutTests.swift`:
```swift
import Testing

@testable import PrinboxCore

@Suite struct InboxLayoutTests {
    let inbox = InboxBuilder.build(
        makeResult((1...9).map { makePR(id: "r\($0)", number: $0) } + [makePR(id: "w", source: .mine)]))

    @Test func expandedSectionsListRowsThenTheMoreRow() {
        let items = InboxLayout.visibleItems(inbox, folded: [])
        #expect(items.first == .header(.needsReview))
        #expect(items.contains(.row("r8")))
        #expect(!items.contains(.row("r9")))
        #expect(items.contains(.more(.needsReview)))
        #expect(items.suffix(2) == [.header(.waitingOnOthers), .row("w")])
    }

    @Test func foldedSectionsShowOnlyTheirHeader() {
        let items = InboxLayout.visibleItems(inbox, folded: [.needsReview, .waitingOnOthers])
        #expect(items == [.header(.needsReview), .header(.waitingOnOthers)])
    }
}
```

`Tests/PrinboxCoreTests/State/FoldStoreTests.swift`:
```swift
import Testing

@testable import PrinboxCore

@MainActor
@Suite struct FoldStoreTests {
    @Test func firstRunOpensOnlyNeedsYourReview() {
        let folds = FoldStore(defaults: MemoryDefaults())
        #expect(!folds.isFolded(.needsReview))
        #expect(folds.isFolded(.takeAnotherLook))
        #expect(folds.isFolded(.waitingOnOthers))
    }

    @Test func togglePersistsAcrossInstances() {
        let defaults = MemoryDefaults()
        FoldStore(defaults: defaults).toggle(.mentions)
        #expect(!FoldStore(defaults: defaults).isFolded(.mentions))
    }

    @Test func unknownStoredValuesAreIgnored() {
        let defaults = MemoryDefaults()
        defaults.set(["mentions", "bogus"], forKey: FoldStore.key)
        #expect(FoldStore(defaults: defaults).folded == [.mentions])
    }
}
```

`Tests/PrinboxCoreTests/State/KeyCommandTests.swift`:
```swift
import Testing

@testable import PrinboxCore

@Suite struct KeyCommandTests {
    func command(_ code: UInt16, _ chars: String? = nil, _ mods: HotKeyModifiers = []) -> KeyCommand? {
        KeyCommand(keyCode: code, characters: chars, modifiers: mods)
    }

    @Test func navigationKeys() {
        #expect(command(126) == .up)
        #expect(command(125) == .down)
        #expect(command(36) == .enter)
        #expect(command(76) == .enter)
        #expect(command(53) == .escape)
    }

    @Test func plainRRefreshes() {
        #expect(command(15, "r") == .refresh)
        #expect(command(15, "R", [.shift]) == .refresh)
    }

    @Test func modifiedROrOtherKeysAreIgnored() {
        #expect(command(15, "r", [.command]) == nil)
        #expect(command(0, "a") == nil)
    }
}
```

`Tests/PrinboxCoreTests/State/PopoverStateTests.swift`:
```swift
import Foundation
import Testing

@testable import PrinboxCore

@MainActor
@Suite struct PopoverStateTests {
    let a = makePR(id: "a", number: 1, reviewRequestedAt: date("2026-08-02T10:00:00Z"))
    let b = makePR(id: "b", number: 2, reviewRequestedAt: date("2026-08-03T10:00:00Z"))

    func makeState(
        folded: [SectionKind] = [], script: @escaping @Sendable (Int) async throws -> FetchResult
    ) async -> PopoverState {
        let defaults = MemoryDefaults()
        defaults.set(folded.map(\.rawValue), forKey: FoldStore.key)
        let state = PopoverState(
            store: InboxStore(fetcher: ScriptedFetcher(script)), folds: FoldStore(defaults: defaults))
        await state.refresh()
        return state
    }

    @Test func popoverOpensOnTheFirstRow() async {
        let prs = [a, b]
        let state = await makeState { _ in makeResult(prs) }
        state.showingSettings = true
        state.popoverWillShow()
        #expect(state.selection.current == .row("a"))
        #expect(state.showingSettings == false)
    }

    @Test func arrowsMoveAndEnterOpensThePullRequest() async {
        let prs = [a, b]
        let state = await makeState { _ in makeResult(prs) }
        state.popoverWillShow()
        #expect(state.handle(.down) == .handled)
        #expect(state.handle(.enter) == .open(b.url))
    }

    @Test func enterOnAHeaderTogglesTheFold() async {
        let prs = [a]
        let state = await makeState { _ in makeResult(prs) }
        state.select(.header(.needsReview))
        #expect(state.handle(.enter) == .handled)
        #expect(state.folds.isFolded(.needsReview))
        #expect(state.items == [.header(.needsReview)])
        #expect(state.selection.current == .header(.needsReview))
    }

    @Test func enterOnTheMoreRowOpensTheSearch() async {
        let prs = (1...9).map { makePR(id: "p\($0)", number: $0) }
        let state = await makeState { _ in makeResult(prs) }
        state.select(.more(.needsReview))
        #expect(state.handle(.enter) == .open(SectionKind.needsReview.moreURL))
    }

    @Test func foldingASectionMovesTheSelectionToItsHeader() async {
        let prs = [a, b]
        let state = await makeState { _ in makeResult(prs) }
        state.select(.row("b"))
        state.toggleFold(.needsReview)
        #expect(state.selection.current == .header(.needsReview))
    }

    @Test func refreshThatRemovesTheSelectedRowSelectsThePrecedingOne() async {
        let (first, second) = (a, b)
        let state = await makeState { call in makeResult(call == 1 ? [first, second] : [first]) }
        state.select(.row("b"))
        await state.refresh()
        #expect(state.selection.current == .row("a"))
    }

    @Test func refreshAndEscapeKeys() async {
        let state = await makeState { _ in makeResult([]) }
        #expect(state.handle(.refresh) == .refresh)
        #expect(state.handle(.escape) == .close)
    }

    @Test func escapeInSettingsReturnsToTheList() async {
        let state = await makeState { _ in makeResult([]) }
        state.showingSettings = true
        #expect(state.handle(.down) == nil)
        #expect(state.handle(.escape) == .handled)
        #expect(state.showingSettings == false)
    }
}
```

- [x] **Step 2: Run the tests and confirm they fail**

Run: `swift test`
Expected: the build fails with `cannot find 'Selection' in scope`.

- [x] **Step 3: Implement**

`Sources/PrinboxCore/State/InboxItemID.swift`:
```swift
import Foundation

/// Everything the keyboard can select in the popover.
public enum InboxItemID: Hashable, Sendable {
    case header(SectionKind)
    case row(String)
    case more(SectionKind)
}

public enum InboxLayout {
    /// Focusable items in display order. Rows and "more" rows of folded sections are skipped.
    public static func visibleItems(_ inbox: Inbox, folded: Set<SectionKind>) -> [InboxItemID] {
        inbox.sections.flatMap { section -> [InboxItemID] in
            let header = InboxItemID.header(section.kind)
            guard !folded.contains(section.kind) else { return [header] }
            let more: [InboxItemID] = section.moreCount > 0 ? [.more(section.kind)] : []
            return [header] + section.rows.map { .row($0.id) } + more
        }
    }
}
```

`Sources/PrinboxCore/State/Selection.swift`:
```swift
import Foundation

/// Keyboard and hover selection over the visible items. Movement wraps at both ends.
public struct Selection: Equatable, Sendable {
    public let current: InboxItemID?

    public init(current: InboxItemID? = nil) { self.current = current }

    public func movingDown(in items: [InboxItemID]) -> Selection { step(in: items, by: 1) }

    public func movingUp(in items: [InboxItemID]) -> Selection { step(in: items, by: -1) }

    /// Keeps the selection if its item survives. Otherwise selects the nearest preceding item that still
    /// exists (so folding lands on the section header), else the first item.
    public func reconciled(previous: [InboxItemID], current items: [InboxItemID]) -> Selection {
        guard let current else { return self }
        if items.contains(current) { return self }
        let index = previous.firstIndex(of: current) ?? 0
        let survivor = previous[..<index].reversed().first(where: items.contains)
        return Selection(current: survivor ?? items.first)
    }

    private func step(in items: [InboxItemID], by delta: Int) -> Selection {
        guard !items.isEmpty else { return Selection() }
        guard let current, let index = items.firstIndex(of: current) else {
            return Selection(current: delta > 0 ? items.first : items.last)
        }
        return Selection(current: items[(index + delta + items.count) % items.count])
    }
}
```

`Sources/PrinboxCore/State/FoldStore.swift`:
```swift
import Foundation
import Observation

/// Which sections are folded, persisted in user defaults.
@MainActor
@Observable
public final class FoldStore {
    public static let key = "foldedSections"
    /// First run: only "Needs your review" is open, as in the sketchybar prototype.
    public static let defaultFolded: Set<SectionKind> = [.takeAnotherLook, .mentions, .yourPRs, .waitingOnOthers]

    public private(set) var folded: Set<SectionKind>
    @ObservationIgnored private let defaults: KeyValueStoring

    public init(defaults: KeyValueStoring) {
        self.defaults = defaults
        let stored = defaults.object(forKey: Self.key) as? [String]
        folded = stored.map { Set($0.compactMap(SectionKind.init(rawValue:))) } ?? Self.defaultFolded
    }

    public func isFolded(_ kind: SectionKind) -> Bool { folded.contains(kind) }

    public func toggle(_ kind: SectionKind) {
        folded = folded.symmetricDifference([kind])
        defaults.set(folded.map(\.rawValue).sorted(), forKey: Self.key)
    }
}
```

`Sources/PrinboxCore/State/KeyCommand.swift`:
```swift
import Foundation

/// Keys the popover understands.
public enum KeyCommand: Equatable, Sendable {
    case up
    case down
    case enter
    case refresh
    case escape

    /// Returns nil for keys the popover leaves alone. R counts only without ⌘, ⌃ or ⌥.
    public init?(keyCode: UInt16, characters: String?, modifiers: HotKeyModifiers) {
        switch keyCode {
        case 126: self = .up
        case 125: self = .down
        case 36, 76: self = .enter
        case 53: self = .escape
        default:
            guard modifiers.isDisjoint(with: [.command, .control, .option]), characters?.lowercased() == "r" else {
                return nil
            }
            self = .refresh
        }
    }
}

/// What the app should do after the popover handled a key or an activation.
public enum KeyAction: Equatable, Sendable {
    case handled
    case open(URL)
    case refresh
    case close
}
```

`Sources/PrinboxCore/State/PopoverState.swift`:
```swift
import Foundation
import Observation

/// View model of the popover: selection, folding, settings mode and key handling. The SwiftUI views
/// read it directly; it contains no AppKit.
@MainActor
@Observable
public final class PopoverState {
    public let store: InboxStore
    public let folds: FoldStore
    public private(set) var selection = Selection()
    public var showingSettings = false
    public var isRecordingShortcut = false
    /// Measured height of the list content, used to size the popover.
    public var contentHeight: CGFloat = 0

    @ObservationIgnored private var lastItems: [InboxItemID] = []

    public init(store: InboxStore, folds: FoldStore) {
        self.store = store
        self.folds = folds
        lastItems = items
    }

    public var items: [InboxItemID] {
        InboxLayout.visibleItems(store.inbox ?? .empty, folded: folds.folded)
    }

    public func isSelected(_ id: InboxItemID) -> Bool { selection.current == id }

    public func select(_ id: InboxItemID) { selection = Selection(current: id) }

    /// Follows the selected item through a change of the visible items.
    public func reconcileSelection() {
        let current = items
        selection = selection.reconciled(previous: lastItems, current: current)
        lastItems = current
    }

    public func toggleFold(_ kind: SectionKind) {
        folds.toggle(kind)
        reconcileSelection()
    }

    public func refresh() async {
        await store.refresh()
        reconcileSelection()
    }

    public func refreshIfStale() async {
        await store.refreshIfStale()
        reconcileSelection()
    }

    /// Resets transient state each time the popover opens and selects the first PR row.
    public func popoverWillShow() {
        showingSettings = false
        isRecordingShortcut = false
        reconcileSelection()
        if selection.current == nil { selection = Selection(current: firstRow ?? items.first) }
    }

    /// Activating a header folds it; a row or "more" row opens its URL.
    public func activate(_ id: InboxItemID) -> KeyAction {
        switch id {
        case .header(let kind):
            toggleFold(kind)
            return .handled
        case .row(let prID):
            return url(forRow: prID).map(KeyAction.open) ?? .handled
        case .more(let kind):
            return .open(kind.moreURL)
        }
    }

    /// Returns nil when the key is not for the popover, so the event continues to the view.
    public func handle(_ command: KeyCommand) -> KeyAction? {
        if showingSettings {
            guard command == .escape else { return nil }
            showingSettings = false
            return .handled
        }
        switch command {
        case .up:
            selection = selection.movingUp(in: items)
            return .handled
        case .down:
            selection = selection.movingDown(in: items)
            return .handled
        case .enter:
            return selection.current.map(activate) ?? .handled
        case .refresh:
            return .refresh
        case .escape:
            return .close
        }
    }

    private var firstRow: InboxItemID? {
        items.first { item in
            if case .row = item { return true }
            return false
        }
    }

    private func url(forRow id: String) -> URL? {
        store.inbox?.sections.lazy.flatMap(\.rows).first { $0.id == id }?.pullRequest.url
    }
}
```

- [x] **Step 4: Run the tests and confirm they pass**

Run: `swift test`
Expected: every test passes.

- [x] **Step 5: Commit**

```bash
make format && make lint
git add Sources/PrinboxCore/State Tests/PrinboxCoreTests/State
git commit -m "feat: add popover navigation, folding and key handling state"
```

---

### Task 11: Avatar cache

**Files:**
- Create: `Sources/PrinboxCore/State/DataLoading.swift`
- Create: `Sources/PrinboxCore/State/AvatarCache.swift`
- Test: `Tests/PrinboxCoreTests/State/AvatarCacheTests.swift`

**Interfaces:**
- Consumes: `TestClock` (Task 8, tests only).
- Produces:
  - `public protocol DataLoading: Sendable { func load(_ url: URL) async throws -> Data }`
  - `public struct URLSessionDataLoader: DataLoading`
  - `public actor AvatarCache`:
    - `init(directory:loader:maxAge:clock:)`
    - `static func defaultDirectory(bundleID:) -> URL`
    - `func data(login:url:) async -> Data?`
    - `static func fileName(for:) -> String`

- [x] **Step 1: Write the failing tests**

`Tests/PrinboxCoreTests/State/AvatarCacheTests.swift`:
```swift
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
        let cache = AvatarCache(directory: directory, loader: CountingLoader(.failure(URLError(.notConnectedToInternet))), clock: { clock.now })
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
```

- [x] **Step 2: Run the tests and confirm they fail**

Run: `swift test`
Expected: the build fails with `cannot find 'AvatarCache' in scope`.

- [x] **Step 3: Implement**

`Sources/PrinboxCore/State/DataLoading.swift`:
```swift
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
```

`Sources/PrinboxCore/State/AvatarCache.swift`:
```swift
import Foundation

/// Disk cache for author avatars, one file per login, refreshed after `maxAge`.
/// - The cache is best-effort. A failed download or write falls back to the stale copy, or to nil, and
///   the view shows initials.
/// - Concurrent requests for the same login share one download.
public actor AvatarCache {
    public static let defaultMaxAge: TimeInterval = 7 * 24 * 3600

    private let directory: URL
    private let loader: DataLoading
    private let maxAge: TimeInterval
    private let clock: @Sendable () -> Date
    private var downloads: [String: Task<Data?, Never>] = [:]

    public init(
        directory: URL, loader: DataLoading = URLSessionDataLoader(),
        maxAge: TimeInterval = AvatarCache.defaultMaxAge, clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.directory = directory
        self.loader = loader
        self.maxAge = maxAge
        self.clock = clock
    }

    /// ~/Library/Caches/<bundleID>/avatars
    public static func defaultDirectory(bundleID: String) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID)
            .appendingPathComponent("avatars")
    }

    public func data(login: String, url: URL?) async -> Data? {
        let file = directory.appendingPathComponent(Self.fileName(for: login))
        let cached = try? Data(contentsOf: file)
        if let cached, isFresh(file) { return cached }
        guard let url else { return cached }
        if let running = downloads[login] { return await running.value ?? cached }
        let loader = self.loader
        let task = Task { try? await loader.load(url) }
        downloads[login] = task
        let downloaded = await task.value
        downloads[login] = nil
        guard let downloaded else { return cached }
        write(downloaded, to: file)
        return downloaded
    }

    /// Anything outside [A-Za-z0-9_-] becomes "_", so a login can never name a path outside the directory.
    static func fileName(for login: String) -> String {
        let safe = login.map { char -> Character in
            char.isASCII && (char.isLetter || char.isNumber || char == "-" || char == "_") ? char : "_"
        }
        return String(safe) + ".png"
    }

    private func isFresh(_ file: URL) -> Bool {
        let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
        let modified = attributes?[.modificationDate] as? Date
        return modified.map { clock().timeIntervalSince($0) < maxAge } ?? false
    }

    private func write(_ data: Data, to file: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
```

- [x] **Step 4: Run the tests and confirm they pass**

Run: `swift test`
Expected: every test passes.

- [x] **Step 5: Commit**

```bash
make format && make lint
git add Sources/PrinboxCore/State Tests/PrinboxCoreTests/State
git commit -m "feat: cache author avatars on disk"
```

---

### Task 12: Executable target, `--print`, and the recorded live fixture

**Files:**
- Modify: `Package.swift`, adding the executable target
- Create: `Sources/Prinbox/App/main.swift`, `Sources/Prinbox/App/CommandLineMode.swift`
- Create: `scripts/anonymize.jq`, `scripts/record-fixture.sh`
- Create: `Tests/PrinboxCoreTests/Fixtures/live-2026-09-29.json`, generated in Step 4
- Test: `Tests/PrinboxCoreTests/GitHub/RecordedFixtureTests.swift`

**Interfaces:**
- Consumes: `GhClient` (Task 4), `InboxBuilder` (Task 6), `InboxPrinter` and `FetchError.message` (Task 7), `InboxQuery.text` (Task 2).
- Produces: `Prinbox --print` and `Prinbox --print-query`, plus the `CommandLineMode` enum that Task 15 extends.

- [x] **Step 1: Add the executable target and CLI mode**

`Package.swift`:
```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Prinbox",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Prinbox", targets: ["Prinbox"])
    ],
    targets: [
        .target(name: "PrinboxCore"),
        .executableTarget(name: "Prinbox", dependencies: ["PrinboxCore"]),
        .testTarget(name: "PrinboxCoreTests", dependencies: ["PrinboxCore"]),
    ]
)
```

`Sources/Prinbox/App/CommandLineMode.swift`:
```swift
import Foundation
import PrinboxCore

/// Entry points that run without UI.
/// - `--print` is the live end-to-end check.
/// - `--print-query` is used by scripts/record-fixture.sh.
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
```

`Sources/Prinbox/App/main.swift` (Task 13 adds the UI launch after the `if`):
```swift
import AppKit

if let mode = CommandLineMode(arguments: CommandLine.arguments) {
    Task { exit(await mode.run()) }
    dispatchMain()
}
```

Run: `swift build`
Expected: `Build complete!`

- [x] **Step 2: Run the live end-to-end check**

Run: `swift run -q Prinbox --print`
Expected, as of 2026-09-29:
- `waiting on you: 0`
- a `Your PRs` and/or `Waiting on others` section listing 7 of your PRs, all in `[example-org/...]`
- no line containing `example-org/archived-repo`

Check the exclusion explicitly:

Run: `swift run -q Prinbox --print | grep -c archived-repo`
Expected: `0`.

- [x] **Step 3: Write the anonymizer and the recording script**

`scripts/anonymize.jq`:
```jq
# Replaces everything private in a recorded inbox response with deterministic placeholders:
# repositories -> acme/repo-N, logins -> user-N (the viewer -> me), titles -> "PR title N",
# ids -> PR_N, urls and avatar urls rebuilt from those, error messages redacted.
.data.viewer.login as $viewer
| [.data | (.review, .mentions, .mine) | .nodes[]? | select(. != null and .id != null)] as $prs
| ([$prs[].repository.nameWithOwner] | unique) as $repos
| ([$prs[].id] | unique) as $ids
| ([$prs[] | .author.login?, (.timelineItems.nodes[]?.requestedReviewer.login?)]
   | map(select(. != null and . != $viewer)) | unique) as $logins
| def login($l):
    if $l == null then null elif $l == $viewer then "me" else "user-\(($logins | index($l)) + 1)" end;
  def repo($r): "acme/repo-\(($repos | index($r)) + 1)";
  def anon:
    if . == null or .id == null then . else
      (($ids | index(.id)) + 1) as $n
      | repo(.repository.nameWithOwner) as $repo
      | .id = "PR_\($n)"
      | .title = "PR title \($n)"
      | .url = "https://github.com/\($repo)/pull/\(.number)"
      | .repository.nameWithOwner = $repo
      | .author |= (if . == null then null
          else {login: login(.login), avatarUrl: "https://avatars.githubusercontent.com/u/\($n)?v=4"} end)
      | .timelineItems.nodes |= ((. // []) | map(
          if .requestedReviewer.login? then .requestedReviewer.login |= login(.) else . end))
    end;
  .data.viewer.login = "me"
  | .data.review.nodes |= map(anon)
  | .data.mentions.nodes |= map(anon)
  | .data.mine.nodes |= map(anon)
  | if .errors then .errors |= map({type, message: "redacted"}) else . end
```

`scripts/record-fixture.sh`:
```bash
#!/usr/bin/env bash
# Records the live inbox query as an anonymized test fixture.
# Usage: scripts/record-fixture.sh <name>
# Writes Tests/PrinboxCoreTests/Fixtures/<name>.json. scripts/anonymize.jq replaces repositories,
# logins, titles, urls and ids, so no private org data is committed.
set -euo pipefail

name=${1:?usage: scripts/record-fixture.sh <name>}
root=$(cd "$(dirname "$0")/.." && pwd)
out="$root/Tests/PrinboxCoreTests/Fixtures/$name.json"

query=$(swift run --package-path "$root" -q Prinbox --print-query)
# gh exits 1 when the response carries GraphQL errors but still prints the body, so keep it.
raw=$(gh api graphql -f query="$query") || true
if [ -z "$raw" ]; then
    echo "gh returned nothing" >&2
    exit 1
fi
jq -f "$root/scripts/anonymize.jq" <<<"$raw" > "$out"
echo "wrote $out"
```

Run: `chmod +x scripts/record-fixture.sh`

- [x] **Step 4: Record the fixture and check that no private data leaked**

Run: `scripts/record-fixture.sh live-2026-09-29`
Expected: `wrote .../Fixtures/live-2026-09-29.json`

Run: `grep -ciE 'example-org|creeonix|archived-repo|api|web-app' Tests/PrinboxCoreTests/Fixtures/live-2026-09-29.json`
Expected: `0`. If it isn't 0, fix `anonymize.jq` before continuing. Never commit a fixture that fails this check.

- [x] **Step 5: Write the fixture tests and run them**

`Tests/PrinboxCoreTests/GitHub/RecordedFixtureTests.swift`:
```swift
import Testing

@testable import PrinboxCore

/// Invariants of a response recorded from a real account (anonymized by scripts/anonymize.jq).
@Suite struct RecordedFixtureTests {
    let result: FetchResult

    init() throws {
        result = try PullRequestMapper.map(InboxResponse.decode(Fixture.data("live-2026-09-29")))
    }

    @Test func containsOnlyAnonymizedValues() {
        #expect(result.viewerLogin == "me")
        #expect(!result.pullRequests.isEmpty)
        for pr in result.pullRequests {
            #expect(pr.repository.hasPrefix("acme/repo-"))
            #expect(pr.title.hasPrefix("PR title "))
            #expect(pr.url.absoluteString.hasPrefix("https://github.com/acme/repo-"))
        }
    }

    @Test func ownPullRequestsLandInOwnSections() {
        let own: Set<SectionKind> = [.yourPRs, .waitingOnOthers]
        let rows = InboxBuilder.build(result).sections.flatMap(\.rows)
        for row in rows where row.pullRequest.source == .mine {
            #expect(own.contains(row.classification.section))
        }
    }

    @Test func archivedRepositoriesAreExcludedByTheQuery() {
        #expect(result.pullRequests.allSatisfy { !$0.isArchived })
    }
}
```

Run: `swift test`
Expected: every test passes.

- [x] **Step 6: Commit**

```bash
make format && make lint
git add Package.swift Sources/Prinbox scripts Tests/PrinboxCoreTests
git commit -m "feat: add --print live check and record an anonymized live fixture"
```

---

> **Checkpoint:** Core is complete. Before starting UI work, dispatch the **code-reviewer** agent on `Sources/PrinboxCore` and `Tests`. Fix CRITICAL and HIGH findings, then run `make coverage` once Task 16 adds the script. Until then, run `swift test --enable-code-coverage`.

---

### Task 13: Status item and refresh loop

**Files:**
- Modify: `Sources/Prinbox/App/main.swift`
- Create: `Sources/Prinbox/App/AppDelegate.swift`, `Sources/Prinbox/App/AppCoordinator.swift`, `Sources/Prinbox/App/RefreshTriggers.swift`
- Create: `Sources/Prinbox/StatusItem/StatusItemController.swift`

**Interfaces:**
- Consumes: `GhClient`, `InboxStore` and `StatusBadge`.
- Produces:
  - `StatusItemController(onLeftClick:onRefresh:)` with `anchor: NSView?` and `render(_ badge: StatusBadge)`
  - `RefreshTriggers.start(_ refresh:)`
  - `AppCoordinator.start()`

In this task a left click refreshes. Task 14 replaces that with the popover.

- [x] **Step 1: Implement the status item**

`Sources/Prinbox/StatusItem/StatusItemController.swift`:
```swift
import AppKit
import PrinboxCore

/// The menu-bar item: pull-request symbol plus count, dimmed at zero, red with "!" on error.
/// Left click runs `onLeftClick`; right click shows a small fallback menu.
@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let onLeftClick: @MainActor () -> Void
    private let onRefresh: @MainActor () -> Void

    init(onLeftClick: @escaping @MainActor () -> Void, onRefresh: @escaping @MainActor () -> Void) {
        self.onLeftClick = onLeftClick
        self.onRefresh = onRefresh
        super.init()
        guard let button = item.button else { return }
        button.imagePosition = .imageLeading
        button.target = self
        button.action = #selector(clicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        render(.loading)
    }

    var anchor: NSView? { item.button }

    func render(_ badge: StatusBadge) {
        guard let button = item.button else { return }
        switch badge {
        case .loading:
            show(button, title: "…", tint: nil, dimmed: true, tooltip: "prinbox: loading")
        case .count(let count):
            show(button, title: "\(count)", tint: nil, dimmed: false, tooltip: "prinbox: \(count) waiting on you")
        case .zero:
            show(button, title: "", tint: nil, dimmed: true, tooltip: "prinbox: nothing waiting on you")
        case .error(let message):
            show(button, title: "!", tint: .systemRed, dimmed: false, tooltip: "prinbox: \(message)")
        }
    }

    private func show(_ button: NSStatusBarButton, title: String, tint: NSColor?, dimmed: Bool, tooltip: String) {
        button.image = Self.symbol(tint: tint)
        var attributes: [NSAttributedString.Key: Any] = [.font: NSFont.menuBarFont(ofSize: 0)]
        if let tint { attributes[.foregroundColor] = tint }
        button.attributedTitle = NSAttributedString(string: title.isEmpty ? "" : " \(title)", attributes: attributes)
        button.appearsDisabled = dimmed
        button.toolTip = tooltip
    }

    private static func symbol(tint: NSColor?) -> NSImage? {
        let base = NSImage(systemSymbolName: "arrow.triangle.pull", accessibilityDescription: "prinbox")
        guard let tint else {
            base?.isTemplate = true
            return base
        }
        let tinted = base?.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [tint]))
        tinted?.isTemplate = false
        return tinted
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            onLeftClick()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        let refresh = menu.addItem(withTitle: "Refresh now", action: #selector(refreshChosen), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit prinbox", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func refreshChosen() { onRefresh() }
}
```

`Sources/Prinbox/App/RefreshTriggers.swift`:
```swift
import AppKit

/// Refreshes every five minutes and after the Mac wakes. Popover-open and manual refreshes live in
/// the coordinator.
@MainActor
final class RefreshTriggers {
    static let interval: Duration = .seconds(300)

    private var timer: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?

    func start(_ refresh: @escaping @MainActor @Sendable () async -> Void) {
        timer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.interval)
                guard !Task.isCancelled else { return }
                await refresh()
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in await refresh() }
        }
    }
}
```

`Sources/Prinbox/App/AppCoordinator.swift` (Task 13 version):
```swift
import AppKit
import Observation
import PrinboxCore

/// Wires Core models to AppKit and owns every long-lived object of the running app.
@MainActor
final class AppCoordinator {
    private let store: InboxStore
    private let triggers = RefreshTriggers()
    private var statusItem: StatusItemController?

    init() {
        store = InboxStore(fetcher: GhClient())
    }

    func start() {
        statusItem = StatusItemController(
            onLeftClick: { [weak self] in self?.refreshNow() },
            onRefresh: { [weak self] in self?.refreshNow() })
        observeBadge()
        triggers.start { [weak self] in await self?.store.refresh() }
        refreshNow()
    }

    private func refreshNow() {
        Task { await store.refresh() }
    }

    /// Re-renders the status item whenever anything the badge depends on changes.
    private func observeBadge() {
        withObservationTracking {
            statusItem?.render(store.badge)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeBadge() }
        }
    }
}
```

`Sources/Prinbox/App/AppDelegate.swift`:
```swift
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let coordinator = AppCoordinator()
        coordinator.start()
        self.coordinator = coordinator
    }
}
```

`Sources/Prinbox/App/main.swift`:
```swift
import AppKit

if let mode = CommandLineMode(arguments: CommandLine.arguments) {
    Task { exit(await mode.run()) }
    dispatchMain()
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

- [x] **Step 2: Build**

Run: `swift build`
Expected: `Build complete!` with no concurrency errors.

- [x] **Step 3: Verify manually**

Run: `swift run Prinbox`. Leave it running and check the menu bar:
1. A pull-request symbol appears. With 0 review requests today it is dimmed with no number, and the tooltip reads "nothing waiting on you".
2. Right-click shows "Refresh now" and "Quit prinbox". Quit works.

Run: `GH_CONFIG_DIR=$(mktemp -d) swift run Prinbox`
Expected: a red symbol with "!", and the tooltip "prinbox: gh is not logged in: run gh auth login". Quit it.

Run: `HTTPS_PROXY=http://127.0.0.1:9 swift run Prinbox`
Expected: a red "!", and the tooltip starts with "prinbox: Offline". Quit it.

- [x] **Step 4: Commit**

```bash
make format && make lint
git add Sources/Prinbox
git commit -m "feat: show the inbox count in the menu bar with periodic refresh"
```

---

### Task 14: Popover, inbox views, keyboard and avatars

**Files:**
- Create: `Sources/Prinbox/Popover/PopoverController.swift`, `Sources/Prinbox/Popover/KeyMonitor.swift`
- Create: `Sources/Prinbox/System/AvatarImages.swift`
- Create: `Sources/Prinbox/Views/PopoverActions.swift`, `InboxView.swift`, `HeaderView.swift`, `InboxListView.swift`, `SectionView.swift`, `RowViews.swift`, `AvatarView.swift`, `Theme.swift`
- Modify: `Sources/Prinbox/App/AppCoordinator.swift`, replacing the whole file

**Interfaces:**
- Consumes:
  - `PopoverState`, `FoldStore`, `KeyCommand` and `KeyAction` (Task 10)
  - `AvatarCache` (Task 11)
  - `RowText` (Task 7)
  - `StatusItemController` and `RefreshTriggers` (Task 13)
- Produces:
  - `PopoverController(rootView:keyHandler:onShow:onClose:)` with `toggle(relativeTo:)` and `close()`
  - `PopoverActions`, which Task 15 extends
  - `InboxView(state:avatars:actions:)`, which Task 15 extends
  - `HotKeyModifiers.init(_ flags: NSEvent.ModifierFlags)`

- [x] **Step 1: Implement the popover plumbing**

`Sources/Prinbox/Popover/KeyMonitor.swift`:
```swift
import AppKit
import PrinboxCore

/// A local keyDown monitor that exists only while the popover is open. The handler returns true to
/// consume the event.
@MainActor
final class KeyMonitor {
    private let handler: @MainActor (NSEvent) -> Bool
    private var token: Any?

    init(handler: @escaping @MainActor (NSEvent) -> Bool) { self.handler = handler }

    func install() {
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let consumed = MainActor.assumeIsolated { self.handler(event) }
            return consumed ? nil : event
        }
    }

    func remove() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }
}

extension HotKeyModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        let pairs: [(NSEvent.ModifierFlags, HotKeyModifiers)] = [
            (.control, .control), (.option, .option), (.shift, .shift), (.command, .command),
        ]
        self = pairs.filter { flags.contains($0.0) }.reduce(HotKeyModifiers()) { $0.union($1.1) }
    }
}
```

`Sources/Prinbox/Popover/PopoverController.swift`:
```swift
import AppKit
import SwiftUI

/// Hosts the SwiftUI inbox in a transient NSPopover under the status item. Popovers have the
/// AXPopover role, so tiling window managers (OmniWM, AeroSpace, yabai) never manage them.
@MainActor
final class PopoverController: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let keyMonitor: KeyMonitor
    private let onShow: @MainActor () -> Void
    private let onClose: @MainActor () -> Void

    init<Content: View>(
        rootView: Content, keyHandler: @escaping @MainActor (NSEvent) -> Bool,
        onShow: @escaping @MainActor () -> Void, onClose: @escaping @MainActor () -> Void
    ) {
        keyMonitor = KeyMonitor(handler: keyHandler)
        self.onShow = onShow
        self.onClose = onClose
        super.init()
        let host = NSHostingController(rootView: rootView)
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
    }

    var isShown: Bool { popover.isShown }

    func toggle(relativeTo anchor: NSView) {
        if popover.isShown { close() } else { show(relativeTo: anchor) }
    }

    /// A dock-less app gets keystrokes only once it is active and the popover window is key.
    func show(relativeTo anchor: NSView) {
        onShow()
        NSApp.activate()
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        keyMonitor.install()
    }

    func close() { popover.performClose(nil) }

    func popoverDidClose(_ notification: Notification) {
        keyMonitor.remove()
        onClose()
    }
}
```

`Sources/Prinbox/System/AvatarImages.swift`:
```swift
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
```

- [x] **Step 2: Implement the views**

`Sources/Prinbox/Views/PopoverActions.swift` (Task 14 version):
```swift
import Foundation

/// Side effects the views can trigger. AppCoordinator implements them.
struct PopoverActions {
    let open: @MainActor (URL) -> Void
    let refresh: @MainActor () -> Void
    let quit: @MainActor () -> Void
}
```

`Sources/Prinbox/Views/Theme.swift`:
```swift
import PrinboxCore
import SwiftUI

enum Theme {
    static func color(for tone: ReasonTone) -> Color {
        switch tone {
        case .attention: .accentColor
        case .failure: .red
        case .success: .green
        case .neutral: .secondary
        }
    }
}

/// Shared highlight for hover and keyboard selection.
struct RowHighlight: View {
    let isSelected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            .padding(.horizontal, 4)
    }
}
```

`Sources/Prinbox/Views/InboxView.swift` (Task 14 version):
```swift
import PrinboxCore
import SwiftUI

/// Root of the popover. All state lives in `PopoverState`; there is no @State, because its macro
/// plugin ships only with Xcode.
struct InboxView: View {
    static let width: CGFloat = 420
    static let maxHeight: CGFloat = 600

    let state: PopoverState
    let avatars: AvatarImages
    let actions: PopoverActions

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(state: state, actions: actions)
            WarningLinesView(lines: state.store.warningLines)
            Divider()
            content
        }
        .frame(width: Self.width)
    }

    @ViewBuilder private var content: some View {
        if let inbox = state.store.inbox, !inbox.isEmpty {
            InboxListView(state: state, inbox: inbox, avatars: avatars, actions: actions)
        } else if state.store.inbox != nil {
            EmptyStateView()
        } else {
            ProgressView().padding(24)
        }
    }
}

struct WarningLinesView: View {
    let lines: [String]

    var body: some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(lines, id: \.self) { line in
                    Label(line, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .help(line)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle").font(.system(size: 24)).foregroundStyle(.secondary)
            Text("Inbox zero").font(.headline)
            Text("Nothing waiting on you.").font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
    }
}
```

`Sources/Prinbox/Views/HeaderView.swift` (Task 14 version):
```swift
import PrinboxCore
import SwiftUI

struct HeaderView: View {
    let state: PopoverState
    let actions: PopoverActions

    var body: some View {
        HStack(spacing: 8) {
            Text(RowText.header(badgeCount: state.store.inbox?.badgeCount ?? 0, lastSuccess: state.store.lastSuccess))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if state.store.isRefreshing {
                ProgressView().controlSize(.small)
            } else {
                IconButton(symbol: "arrow.clockwise", help: "Refresh (R)", action: actions.refresh)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(.borderless)
            .help(help)
    }
}
```

`Sources/Prinbox/Views/InboxListView.swift`:
```swift
import PrinboxCore
import SwiftUI

/// Scrolling list of sections. It measures its content so the popover is only as tall as needed (up to
/// `InboxView.maxHeight`), and scrolls to follow the keyboard selection.
struct InboxListView: View {
    let state: PopoverState
    let inbox: Inbox
    let avatars: AvatarImages
    let actions: PopoverActions

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(inbox.sections) { section in
                        SectionView(section: section, state: state, avatars: avatars, actions: actions)
                    }
                }
                .padding(.vertical, 6)
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(key: ContentHeightKey.self, value: geometry.size.height)
                    })
            }
            .onPreferenceChange(ContentHeightKey.self) { height in
                MainActor.assumeIsolated { state.contentHeight = height }
            }
            .onChange(of: state.selection.current) { _, id in
                if let id { proxy.scrollTo(id) }
            }
            .frame(height: min(max(state.contentHeight, 1), InboxView.maxHeight))
        }
    }
}

struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
```

`Sources/Prinbox/Views/SectionView.swift`:
```swift
import PrinboxCore
import SwiftUI

struct SectionView: View {
    let section: InboxSection
    let state: PopoverState
    let avatars: AvatarImages
    let actions: PopoverActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeaderView(
                section: section, isFolded: state.folds.isFolded(section.kind),
                isSelected: state.isSelected(.header(section.kind))
            ) {
                state.toggleFold(section.kind)
            }
            .id(InboxItemID.header(section.kind))
            .onHover { inside in if inside { state.select(.header(section.kind)) } }
            if !state.folds.isFolded(section.kind) {
                ForEach(section.rows) { row in
                    rowView(row)
                        .id(InboxItemID.row(row.id))
                        .onHover { inside in if inside { state.select(.row(row.id)) } }
                }
                if section.moreCount > 0 {
                    MoreRowView(count: section.moreCount, isSelected: state.isSelected(.more(section.kind))) {
                        actions.open(section.kind.moreURL)
                    }
                    .id(InboxItemID.more(section.kind))
                    .onHover { inside in if inside { state.select(.more(section.kind)) } }
                }
            }
        }
    }

    @ViewBuilder private func rowView(_ row: InboxRow) -> some View {
        let selected = state.isSelected(.row(row.id))
        if section.kind.usesCompactRows {
            CompactRowView(row: row, isSelected: selected) { actions.open(row.pullRequest.url) }
        } else {
            PullRequestRowView(row: row, avatars: avatars, isSelected: selected) { actions.open(row.pullRequest.url) }
        }
    }
}

struct SectionHeaderView: View {
    let section: InboxSection
    let isFolded: Bool
    let isSelected: Bool
    let onToggle: @MainActor () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Image(systemName: isFolded ? "chevron.right" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 12)
                Text(section.kind.title).font(.system(size: 12, weight: .semibold))
                Text("\(section.count)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.secondary.opacity(0.18)))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(RowHighlight(isSelected: isSelected))
        }
        .buttonStyle(.plain)
    }
}
```

`Sources/Prinbox/Views/RowViews.swift`:
```swift
import PrinboxCore
import SwiftUI

struct PullRequestRowView: View {
    let row: InboxRow
    let avatars: AvatarImages
    let isSelected: Bool
    let onOpen: @MainActor () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 10) {
                AvatarView(login: row.pullRequest.authorLogin, url: row.pullRequest.avatarURL, avatars: avatars)
                VStack(alignment: .leading, spacing: 2) {
                    Text(RowText.title(row.pullRequest))
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    TimelineView(.everyMinute) { context in
                        HStack(spacing: 0) {
                            Text(RowText.meta(row, now: context.date) + " · ").foregroundStyle(.secondary)
                            Text(row.classification.reason.rawValue)
                                .foregroundStyle(Theme.color(for: row.classification.reason.tone))
                        }
                        .font(.system(size: 11))
                        .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(RowHighlight(isSelected: isSelected))
            .opacity(row.pullRequest.isDraft ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .help(row.pullRequest.repository)
    }
}

struct CompactRowView: View {
    let row: InboxRow
    let isSelected: Bool
    let onOpen: @MainActor () -> Void

    var body: some View {
        Button(action: onOpen) {
            Text(RowText.compact(row))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 30)
                .padding(.trailing, 12)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .background(RowHighlight(isSelected: isSelected))
                .opacity(row.pullRequest.isDraft ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .help(row.pullRequest.repository)
    }
}

struct MoreRowView: View {
    let count: Int
    let isSelected: Bool
    let onOpen: @MainActor () -> Void

    var body: some View {
        Button(action: onOpen) {
            Text(RowText.more(count))
                .font(.system(size: 12))
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 50)
                .padding(.trailing, 12)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .background(RowHighlight(isSelected: isSelected))
        }
        .buttonStyle(.plain)
    }
}
```

`Sources/Prinbox/Views/AvatarView.swift`:
```swift
import PrinboxCore
import SwiftUI

/// Round 28 pt avatar with an initials placeholder until the image loads.
struct AvatarView: View {
    static let size: CGFloat = 28

    let login: String
    let url: URL?
    let avatars: AvatarImages

    var body: some View {
        Group {
            if let image = avatars.image(for: login) {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                ZStack {
                    Circle().fill(Color.secondary.opacity(0.2))
                    Text(RowText.initials(login))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: Self.size, height: Self.size)
        .clipShape(Circle())
        .task(id: login) { await avatars.load(login: login, url: url) }
    }
}
```

- [x] **Step 3: Wire the popover into the coordinator**

`Sources/Prinbox/App/AppCoordinator.swift` (Task 14 version, replacing the whole file):
```swift
import AppKit
import Observation
import PrinboxCore

/// Wires Core models to AppKit and owns every long-lived object of the running app.
@MainActor
final class AppCoordinator {
    static let bundleID = Bundle.main.bundleIdentifier ?? "io.github.creeonix.prinbox"

    private let store: InboxStore
    private let state: PopoverState
    private let avatars: AvatarImages
    private let triggers = RefreshTriggers()
    private var statusItem: StatusItemController?
    private var popover: PopoverController?

    init() {
        let store = InboxStore(fetcher: GhClient())
        self.store = store
        state = PopoverState(store: store, folds: FoldStore(defaults: UserDefaults.standard))
        avatars = AvatarImages(cache: AvatarCache(directory: AvatarCache.defaultDirectory(bundleID: Self.bundleID)))
    }

    func start() {
        statusItem = StatusItemController(
            onLeftClick: { [weak self] in self?.togglePopover() },
            onRefresh: { [weak self] in self?.refreshNow() })
        popover = PopoverController(
            rootView: InboxView(state: state, avatars: avatars, actions: makeActions()),
            keyHandler: { [weak self] event in self?.handleKey(event) ?? false },
            onShow: { [weak self] in self?.popoverWillShow() },
            onClose: {})
        observeBadge()
        triggers.start { [weak self] in await self?.state.refresh() }
        refreshNow()
    }

    private func makeActions() -> PopoverActions {
        PopoverActions(
            open: { [weak self] url in self?.open(url) },
            refresh: { [weak self] in self?.refreshNow() },
            quit: { NSApp.terminate(nil) })
    }

    private func togglePopover() {
        guard let anchor = statusItem?.anchor else { return }
        popover?.toggle(relativeTo: anchor)
    }

    private func popoverWillShow() {
        state.popoverWillShow()
        Task { await state.refreshIfStale() }
    }

    private func refreshNow() {
        Task { await state.refresh() }
    }

    private func open(_ url: URL) {
        NSWorkspace.shared.open(url)
        popover?.close()
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let modifiers = HotKeyModifiers(event.modifierFlags)
        guard
            let command = KeyCommand(
                keyCode: event.keyCode, characters: event.charactersIgnoringModifiers, modifiers: modifiers),
            let action = state.handle(command)
        else { return false }
        perform(action)
        return true
    }

    private func perform(_ action: KeyAction) {
        switch action {
        case .handled: break
        case .open(let url): open(url)
        case .refresh: refreshNow()
        case .close: popover?.close()
        }
    }

    /// Re-renders the status item whenever anything the badge depends on changes.
    private func observeBadge() {
        withObservationTracking {
            statusItem?.render(store.badge)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeBadge() }
        }
    }
}
```

- [x] **Step 4: Build and lint**

Run: `swift build && make lint`
Expected: `Build complete!` and no lint errors. `make lint` also proves no `@State` slipped in.

- [x] **Step 5: Verify manually under OmniWM**

Run: `swift run Prinbox`
1. Click the icon. The popover opens anchored under it, and OmniWM does not tile or move it.
2. The header reads "0 waiting on you · updated HH:MM". "Your PRs" and "Waiting on others" appear folded, per the first-run defaults.
3. Press ↓ until a section header is selected, then Enter. It unfolds, and the rows show avatars (initials first, then the image).
4. ↑ and ↓ move the highlight and wrap. Hovering moves it too.
5. Enter on a row opens the PR in the default browser and closes the popover.
6. R shows a spinner, and the header time updates.
7. Esc closes. Clicking outside also closes.
8. Relaunch. The fold state from step 3 is remembered.

Run: `ls ~/Library/Caches/io.github.creeonix.prinbox/avatars`
Expected: `.png` files named by login. Unbundled `swift run` has no bundle id, so `AppCoordinator.bundleID` falls back to this path.

- [x] **Step 6: Commit**

```bash
make format && make lint
git add Sources/Prinbox
git commit -m "feat: add the inbox popover with keyboard navigation and avatars"
```

---

### Task 15: Settings, global shortcut and launch at login

**Files:**
- Create: `Sources/Prinbox/System/HotKeyCenter.swift`, `Sources/Prinbox/System/LoginItem.swift`, `Sources/Prinbox/App/AppInfo.swift`
- Create: `Sources/Prinbox/Views/SettingsView.swift`, `Sources/Prinbox/Views/ShortcutRecorderView.swift`
- Modify, replacing each whole file: `Sources/Prinbox/Views/PopoverActions.swift`, `Sources/Prinbox/Views/InboxView.swift` (the `InboxView` struct only), `Sources/Prinbox/Views/HeaderView.swift` (the `HeaderView` struct only), `Sources/Prinbox/App/AppCoordinator.swift`
- Modify: `Sources/Prinbox/App/CommandLineMode.swift`, adding the `unregisterLoginItem` case

**Interfaces:**
- Consumes:
  - `HotKeySettings`, `HotKeySpec` and `HotKeyModifiers` (Task 9)
  - `PopoverState.isRecordingShortcut` and `showingSettings` (Task 10)
- Produces:
  - `HotKeyCenter(onPress:)` with `register(_ spec: HotKeySpec?) -> Bool` and `unregister()`
  - `LoginItem` with `isEnabled`, `note` and `setEnabled(_:)`
  - `AppInfo`
  - `Prinbox --unregister-login-item`

- [x] **Step 1: Implement the system integrations**

`Sources/Prinbox/System/HotKeyCenter.swift`:
```swift
import Carbon.HIToolbox
import PrinboxCore

/// A global shortcut via Carbon RegisterEventHotKey. It needs no Accessibility permission.
/// Registration fails when another app already owns the same shortcut.
@MainActor
final class HotKeyCenter {
    private static let signature: OSType = 0x5052_4E42  // "PRNB"

    private let onPress: @MainActor () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init(onPress: @escaping @MainActor () -> Void) {
        self.onPress = onPress
        installHandler()
    }

    /// Replaces the current shortcut. nil removes it. Returns false when the shortcut is unavailable.
    func register(_ spec: HotKeySpec?) -> Bool {
        unregister()
        guard let spec else { return true }
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(
            spec.keyCode, spec.carbonModifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        return status == noErr
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    private func installHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, context in
                guard let context else { return OSStatus(eventNotHandledErr) }
                let center = Unmanaged<HotKeyCenter>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated { center.onPress() }
                return noErr
            }, 1, &eventType, context, &handlerRef)
    }
}
```

`Sources/Prinbox/System/LoginItem.swift`:
```swift
import Foundation
import Observation
import ServiceManagement

/// Launch at login via SMAppService.mainApp. The registration belongs to the app copy that made it, so
/// it is only offered from /Applications.
@MainActor
@Observable
final class LoginItem {
    private(set) var status: SMAppService.Status = SMAppService.mainApp.status
    private(set) var lastError: String?

    var isEnabled: Bool { status == .enabled || status == .requiresApproval }

    var isInstalled: Bool { Bundle.main.bundleURL.path.hasPrefix("/Applications/") }

    /// A hint under the toggle, or nil when everything is fine.
    var note: String? {
        if let lastError { return lastError }
        if !isInstalled { return "Install to /Applications (make install) to use this." }
        if status == .requiresApproval { return "Approve prinbox in System Settings > General > Login Items." }
        return nil
    }

    func setEnabled(_ enabled: Bool) {
        guard isInstalled else {
            lastError = "Install to /Applications (make install) first."
            return
        }
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            lastError = nil
        } catch {
            lastError = "Could not update the login item: \(error.localizedDescription)"
        }
        status = SMAppService.mainApp.status
    }
}
```

`Sources/Prinbox/App/AppInfo.swift`:
```swift
import Foundation
import PrinboxCore

struct AppInfo {
    let ghPath: String?
    let version: String

    static func current(client: GhClient) -> AppInfo {
        AppInfo(
            ghPath: client.ghPath(),
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")
    }
}
```

In `CommandLineMode.swift`:
- Add `import ServiceManagement`.
- Add the case `unregisterLoginItem`.
- In `init?`, add `else if arguments.contains("--unregister-login-item") { self = .unregisterLoginItem }` before the final `else`.
- Add this branch to `run()`:
```swift
        case .unregisterLoginItem:
            do {
                try SMAppService.mainApp.unregister()
                return 0
            } catch {
                FileHandle.standardError.write(Data("login item: \(error.localizedDescription)\n".utf8))
                return 1
            }
```

- [x] **Step 2: Implement the settings views**

`Sources/Prinbox/Views/PopoverActions.swift` (final):
```swift
import Foundation
import PrinboxCore

/// Side effects the views can trigger. AppCoordinator implements them.
struct PopoverActions {
    let open: @MainActor (URL) -> Void
    let refresh: @MainActor () -> Void
    let quit: @MainActor () -> Void
    let toggleShortcutRecording: @MainActor () -> Void
    let setShortcut: @MainActor (HotKeySpec?) -> Void
    let setLaunchAtLogin: @MainActor (Bool) -> Void
}
```

`Sources/Prinbox/Views/ShortcutRecorderView.swift`:
```swift
import PrinboxCore
import SwiftUI

/// Shows the shortcut. Click it, then press a new one. Esc cancels. The popover's key monitor does the
/// capturing (see AppCoordinator.recordShortcut).
struct ShortcutRecorderView: View {
    let state: PopoverState
    let hotKeys: HotKeySettings
    let actions: PopoverActions

    var body: some View {
        HStack(spacing: 6) {
            Button(action: actions.toggleShortcutRecording) {
                Text(label)
                    .font(.system(size: 12, weight: .medium).monospaced())
                    .frame(minWidth: 110)
            }
            .help("Click, then press the new shortcut. Esc cancels.")
            if hotKeys.spec != nil && !state.isRecordingShortcut {
                Button(action: { actions.setShortcut(nil) }) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .help("Remove shortcut")
            }
        }
    }

    private var label: String {
        if state.isRecordingShortcut { return "Press shortcut…" }
        return hotKeys.spec?.displayString ?? "None"
    }
}
```

`Sources/Prinbox/Views/SettingsView.swift`:
```swift
import PrinboxCore
import SwiftUI

/// Settings live inside the popover. A separate window would be managed by the tiling window manager.
struct SettingsView: View {
    let state: PopoverState
    let hotKeys: HotKeySettings
    let loginItem: LoginItem
    let info: AppInfo
    let actions: PopoverActions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: { state.showingSettings = false }) { Label("Inbox", systemImage: "chevron.left") }
                .buttonStyle(.borderless)
            SettingRow(title: "Global shortcut") {
                ShortcutRecorderView(state: state, hotKeys: hotKeys, actions: actions)
            }
            if hotKeys.isUnavailable {
                Text("Shortcut unavailable (in use by another app)").font(.caption).foregroundStyle(.orange)
            }
            SettingRow(title: "Launch at login") {
                Toggle("", isOn: Binding(get: { loginItem.isEnabled }, set: { actions.setLaunchAtLogin($0) }))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            if let note = loginItem.note {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            InfoLine(label: "gh", value: info.ghPath ?? "not found")
            InfoLine(label: "Version", value: info.version)
            HStack {
                Spacer()
                Button("Quit prinbox", action: actions.quit)
            }
        }
        .padding(14)
    }
}

struct SettingRow<Control: View>: View {
    let title: String
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack {
            Text(title).font(.system(size: 12))
            Spacer()
            control()
        }
    }
}

struct InfoLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
        }
        .font(.system(size: 11))
    }
}
```

In `InboxView.swift`, replace the `InboxView` struct with:
```swift
struct InboxView: View {
    static let width: CGFloat = 420
    static let maxHeight: CGFloat = 600

    let state: PopoverState
    let avatars: AvatarImages
    let hotKeys: HotKeySettings
    let loginItem: LoginItem
    let info: AppInfo
    let actions: PopoverActions

    var body: some View {
        VStack(spacing: 0) {
            if state.showingSettings {
                SettingsView(state: state, hotKeys: hotKeys, loginItem: loginItem, info: info, actions: actions)
            } else {
                HeaderView(state: state, actions: actions)
                WarningLinesView(lines: state.store.warningLines)
                Divider()
                content
            }
        }
        .frame(width: Self.width)
    }

    @ViewBuilder private var content: some View {
        if let inbox = state.store.inbox, !inbox.isEmpty {
            InboxListView(state: state, inbox: inbox, avatars: avatars, actions: actions)
        } else if state.store.inbox != nil {
            EmptyStateView()
        } else {
            ProgressView().padding(24)
        }
    }
}
```

In `HeaderView.swift`, replace the `HeaderView` struct with this version, which adds the gear:
```swift
struct HeaderView: View {
    let state: PopoverState
    let actions: PopoverActions

    var body: some View {
        HStack(spacing: 8) {
            Text(RowText.header(badgeCount: state.store.inbox?.badgeCount ?? 0, lastSuccess: state.store.lastSuccess))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if state.store.isRefreshing {
                ProgressView().controlSize(.small)
            } else {
                IconButton(symbol: "arrow.clockwise", help: "Refresh (R)", action: actions.refresh)
            }
            IconButton(symbol: "gearshape", help: "Settings") { state.showingSettings = true }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
```

- [x] **Step 3: Replace the coordinator with the final version**

`Sources/Prinbox/App/AppCoordinator.swift`:
```swift
import AppKit
import Observation
import PrinboxCore

/// Wires Core models to AppKit and owns every long-lived object of the running app.
@MainActor
final class AppCoordinator {
    static let bundleID = Bundle.main.bundleIdentifier ?? "io.github.creeonix.prinbox"

    private let client: GhClient
    private let store: InboxStore
    private let state: PopoverState
    private let hotKeys: HotKeySettings
    private let loginItem = LoginItem()
    private let avatars: AvatarImages
    private let triggers = RefreshTriggers()
    private var statusItem: StatusItemController?
    private var popover: PopoverController?
    private var hotKeyCenter: HotKeyCenter?

    init() {
        let defaults = UserDefaults.standard
        let client = GhClient()
        let store = InboxStore(fetcher: client)
        self.client = client
        self.store = store
        state = PopoverState(store: store, folds: FoldStore(defaults: defaults))
        hotKeys = HotKeySettings(defaults: defaults)
        avatars = AvatarImages(cache: AvatarCache(directory: AvatarCache.defaultDirectory(bundleID: Self.bundleID)))
    }

    func start() {
        statusItem = StatusItemController(
            onLeftClick: { [weak self] in self?.togglePopover() },
            onRefresh: { [weak self] in self?.refreshNow() })
        let root = InboxView(
            state: state, avatars: avatars, hotKeys: hotKeys, loginItem: loginItem,
            info: AppInfo.current(client: client), actions: makeActions())
        popover = PopoverController(
            rootView: root,
            keyHandler: { [weak self] event in self?.handleKey(event) ?? false },
            onShow: { [weak self] in self?.popoverWillShow() },
            onClose: { [weak self] in self?.popoverDidClose() })
        hotKeyCenter = HotKeyCenter { [weak self] in self?.togglePopover() }
        applyHotKey()
        observeBadge()
        triggers.start { [weak self] in await self?.state.refresh() }
        refreshNow()
    }

    private func makeActions() -> PopoverActions {
        PopoverActions(
            open: { [weak self] url in self?.open(url) },
            refresh: { [weak self] in self?.refreshNow() },
            quit: { NSApp.terminate(nil) },
            toggleShortcutRecording: { [weak self] in self?.toggleShortcutRecording() },
            setShortcut: { [weak self] spec in self?.setShortcut(spec) },
            setLaunchAtLogin: { [weak self] enabled in self?.loginItem.setEnabled(enabled) })
    }

    private func togglePopover() {
        guard let anchor = statusItem?.anchor else { return }
        popover?.toggle(relativeTo: anchor)
    }

    private func popoverWillShow() {
        state.popoverWillShow()
        Task { await state.refreshIfStale() }
    }

    /// Closing mid-recording cancels it, which re-registers the shortcut that recording suspended.
    private func popoverDidClose() {
        if state.isRecordingShortcut { toggleShortcutRecording() }
    }

    private func refreshNow() {
        Task { await state.refresh() }
    }

    private func open(_ url: URL) {
        NSWorkspace.shared.open(url)
        popover?.close()
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let modifiers = HotKeyModifiers(event.modifierFlags)
        if state.isRecordingShortcut { return recordShortcut(keyCode: event.keyCode, modifiers: modifiers) }
        guard
            let command = KeyCommand(
                keyCode: event.keyCode, characters: event.charactersIgnoringModifiers, modifiers: modifiers),
            let action = state.handle(command)
        else { return false }
        perform(action)
        return true
    }

    private func perform(_ action: KeyAction) {
        switch action {
        case .handled: break
        case .open(let url): open(url)
        case .refresh: refreshNow()
        case .close: popover?.close()
        }
    }

    // MARK: Global shortcut

    /// While recording, the current shortcut is unregistered; otherwise Carbon would swallow it and it
    /// could never be re-recorded.
    private func toggleShortcutRecording() {
        if state.isRecordingShortcut {
            state.isRecordingShortcut = false
            applyHotKey()
        } else {
            hotKeyCenter?.unregister()
            state.isRecordingShortcut = true
        }
    }

    /// Esc cancels. Keys without ⌃, ⌥ or ⌘ are swallowed and recording continues.
    private func recordShortcut(keyCode: UInt16, modifiers: HotKeyModifiers) -> Bool {
        if keyCode == 53 {
            toggleShortcutRecording()
            return true
        }
        guard let spec = HotKeySpec.recorded(keyCode: keyCode, modifiers: modifiers) else { return true }
        state.isRecordingShortcut = false
        setShortcut(spec)
        return true
    }

    private func setShortcut(_ spec: HotKeySpec?) {
        hotKeys.update(spec)
        applyHotKey()
    }

    private func applyHotKey() {
        hotKeys.isUnavailable = !(hotKeyCenter?.register(hotKeys.spec) ?? false)
    }

    /// Re-renders the status item whenever anything the badge depends on changes.
    private func observeBadge() {
        withObservationTracking {
            statusItem?.render(store.badge)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeBadge() }
        }
    }
}
```

- [x] **Step 4: Build, lint and verify manually**

Run: `swift build && make lint`
Expected: `Build complete!` and a clean lint.

Quit Pullover first, since it also defaults to ⌃⌥P. Then run `swift run Prinbox` and check:
1. ⌃⌥P opens the popover from any app. Pressing it again closes it.
2. The gear opens Settings inside the popover. Esc or the "Inbox" button returns to the list.
3. Click the shortcut field. It shows "Press shortcut…".
   - Press P alone: nothing changes.
   - Press ⌃⌥⌘I: the field shows "⌃⌥⌘I", and that shortcut now opens the popover while ⌃⌥P does nothing.
4. Record ⌃⌥P again. Remove it with the x button. The field shows "None" and no shortcut opens the popover. Record ⌃⌥P back.
5. Start Pullover, then relaunch prinbox. Settings shows "Shortcut unavailable (in use by another app)". Quit Pullover.
6. The launch-at-login toggle shows the note "Install to /Applications (make install) to use this." This task runs unbundled; it is checked for real in Task 16.

- [x] **Step 5: Commit**

```bash
make format && make lint
git add Sources/Prinbox
git commit -m "feat: add in-popover settings with global shortcut and launch at login"
```

---

### Task 16: Packaging, coverage and README

**Files:**
- Create: `Resources/Info.plist`, `scripts/coverage.sh`, `README.md`
- Modify: `Makefile`, replacing the whole file

**Interfaces:**
- Consumes: everything from earlier tasks.
- Produces: the `make` targets `test`, `lint`, `format`, `coverage`, `build`, `app`, `install`, `uninstall`, `run` and `clean`.

- [x] **Step 1: Write the bundle plist, coverage script and Makefile**

`Resources/Info.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleDisplayName</key><string>prinbox</string>
    <key>CFBundleExecutable</key><string>Prinbox</string>
    <key>CFBundleIdentifier</key><string>io.github.creeonix.prinbox</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>Prinbox</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>__VERSION__</string>
    <key>CFBundleVersion</key><string>__VERSION__</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>Copyright (c) 2026 creeonix. MIT License.</string>
</dict>
</plist>
```

`scripts/coverage.sh`:
```bash
#!/usr/bin/env bash
# Runs the tests with coverage and fails when PrinboxCore line coverage is below the threshold.
# Usage: scripts/coverage.sh [threshold-percent]
set -euo pipefail

threshold=${1:-80}
swift test --enable-code-coverage
report=$(swift test --show-codecov-path)
jq -r --argjson threshold "$threshold" '
  [.data[0].files[] | select(.filename | contains("/Sources/PrinboxCore/"))] as $files
  | ($files | map(.summary.lines.covered) | add) as $covered
  | ($files | map(.summary.lines.count) | add) as $total
  | ($covered * 100 / $total) as $pct
  | "PrinboxCore line coverage: \((($pct * 10) | floor) / 10)% (\($covered)/\($total) lines)",
    (if $pct < $threshold then "error: below \($threshold)%\n" | halt_error(1) else empty end)
' "$report"
```

Run: `chmod +x scripts/coverage.sh`

`Makefile` (recipes indented with tabs):
```make
APP_NAME  := Prinbox
BUNDLE_ID := io.github.creeonix.prinbox
VERSION   := 0.1.0
BUILD_DIR := build
APP       := $(BUILD_DIR)/$(APP_NAME).app
INSTALLED := /Applications/$(APP_NAME).app

.PHONY: test lint format coverage build app install uninstall run clean

test:
	swift test

lint:
	swift format lint --recursive Sources Tests Package.swift
	@if grep -rnE '@State( |$$)|#Preview' Sources; then \
		echo "error: @State and #Preview need Xcode's SwiftUI macro plugin; keep view state in @Observable models"; \
		exit 1; \
	fi

format:
	swift format --in-place --recursive Sources Tests Package.swift

coverage:
	scripts/coverage.sh 80

build:
	swift build -c release --product $(APP_NAME)

app: build
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS"
	cp "$$(swift build -c release --show-bin-path)/$(APP_NAME)" "$(APP)/Contents/MacOS/$(APP_NAME)"
	sed 's/__VERSION__/$(VERSION)/g' Resources/Info.plist > "$(APP)/Contents/Info.plist"
	codesign --force --sign - --identifier $(BUNDLE_ID) "$(APP)"
	codesign --verify --strict "$(APP)"

install: app
	-pkill -x $(APP_NAME)
	rm -rf "$(INSTALLED)"
	cp -R "$(APP)" /Applications/
	open "$(INSTALLED)"

uninstall:
	-"$(INSTALLED)/Contents/MacOS/$(APP_NAME)" --unregister-login-item
	-pkill -x $(APP_NAME)
	rm -rf "$(INSTALLED)" "$(HOME)/Library/Caches/$(BUNDLE_ID)"
	-defaults delete $(BUNDLE_ID)

run:
	swift run $(APP_NAME)

clean:
	rm -rf .build $(BUILD_DIR)
```

- [x] **Step 2: Check coverage**

Run: `make coverage`
Expected: `PrinboxCore line coverage: NN.N% (...)` with NN.N ≥ 80, and exit status 0.

If coverage is below 80%, add tests for the uncovered Core lines. `xcrun llvm-cov report` on the profdata next to the JSON lists per-file coverage. Do not lower the threshold.

- [x] **Step 3: Build, install and verify the bundle**

Run: `make install`
Expected:
- `codesign --verify` prints nothing and succeeds.
- `/Applications/Prinbox.app` launches, and the icon appears with no Dock icon.

Run: `/Applications/Prinbox.app/Contents/MacOS/Prinbox --print | grep -c archived-repo`
Expected: `0`

Launch at login:
1. In Settings, turn on "Launch at login". The toggle stays on, and any approval hint points to System Settings.
2. Run `sfltool dumpbtm | grep -i prinbox`. It lists `io.github.creeonix.prinbox`.
3. Log out and back in. prinbox starts.

- [x] **Step 4: Write the README**

`README.md` must include:
- **Title and summary:** "prinbox: a macOS menu-bar code-review inbox that signs in through the GitHub CLI", one paragraph on why (orgs that restrict third-party OAuth apps still allow gh), and a credit to Pullover.
- **Requirements:** macOS 14+, Command Line Tools (`xcode-select --install`), `gh` logged in (`gh auth login`), and jq for recording fixtures.
- **Install:** `git clone …`, `make install`, `make uninstall`.
- **Usage:**
  - the badge states
  - the sections and what goes in each, with the rules table from spec section 5
  - the keys ↑/↓, Enter, R and Esc
  - the global shortcut ⌃⌥P and how to change it
  - launch at login
  - `Prinbox --print`
- **Development:**
  - `make test`, `make lint`, `make coverage` and `make run`
  - `scripts/record-fixture.sh <name>`, and the anonymization guarantee
  - the Xcode-free constraints: no `@State` or `#Preview`, Swift Testing only
- **Manual checklist:** the items from spec section 8, as a checkbox list.
- **License:** MIT, pointing to `THIRD_PARTY_NOTICES.md`.

- [x] **Step 5: Commit**

```bash
make format && make lint
git add Makefile Resources scripts README.md
git commit -m "build: package an ad-hoc signed app with make install and coverage gate"
```

---

### Task 17: Acceptance, review and wrap-up

**Files:**
- Modify: `tasks/todo.md`, ticking the boxes and adding a Review section
- Create, only if the user corrected something: `tasks/lessons.md`

- [x] **Step 1: Run the full verification**

```bash
make lint && make test && make coverage && make install
/Applications/Prinbox.app/Contents/MacOS/Prinbox --print
GH_CONFIG_DIR=$(mktemp -d) /Applications/Prinbox.app/Contents/MacOS/Prinbox --print; echo "exit=$?"
HTTPS_PROXY=http://127.0.0.1:9 /Applications/Prinbox.app/Contents/MacOS/Prinbox --print; echo "exit=$?"
```
Expected:
- Lint is clean, all tests pass, and coverage is at least 80%.
- The first `--print` lists your open PRs, with no archived-repo.
- The logged-out run prints "gh is not logged in: run gh auth login" and `exit=1`.
- The proxied run prints "Offline" and `exit=1`.

- [ ] **Step 2: Walk the manual checklist with the user**

Some items need the user's eyes: OmniWM behaviour, the look next to Pullover, and approving the login item. Walk the README checklist with the user and record each result.

- [x] **Step 3: Code review**

Dispatch the **code-reviewer** agent on the whole branch (`git diff d89f348..HEAD`), and the **security-reviewer** agent on these areas:
- the gh subprocess and its environment
- avatar file names
- the fixture anonymizer

Fix CRITICAL and HIGH findings with tests, and commit each fix separately (`fix: ...`).

- [x] **Step 4: Record the outcome**

Append a `## Review` section to this file covering:
- what shipped
- the verification output: coverage %, the live `--print` summary, and checklist results
- deviations from the spec, with the reason for each
- follow-ups for v2

If the user corrected anything during the work, add each pattern to `tasks/lessons.md`.

```bash
git add tasks
git commit -m "docs: record v1 review results"
```

---

## Review

Recorded 2026-09-29 on branch `feat/v1`.

### What shipped

prinbox v1 covers every item in the spec's v1 list:
- the menu-bar count, with dimmed and red states
- an NSPopover with five collapsible sections that remember their fold state
- rows with cached avatars, sorting and caps
- refresh every 5 minutes, on wake, on open and on R
- keyboard control and a configurable global shortcut
- launch at login
- `make install` and `make uninstall`
- a `--print` live check and anonymized recorded fixtures

### Verification

- **Tests:** `make test` passes 153/153. `make coverage` reports 95.6% line coverage for PrinboxCore (916/958 lines).
- **Live account, from `/Applications/Prinbox.app`:** `--print` lists your 7 open PRs and nothing from archived-repo. The status item read "1 waiting on you" while one review was pending and "nothing waiting on you" after you reviewed it.
- **Error modes:** logged out prints "gh is not logged in: run gh auth login" and exits 1. Offline prints "Offline" and exits 1.
- **Screenshots:** the popover was confirmed visually, including above OmniWM's workspace bar after the window-level ruling.
- **Reviews:** a PrinboxCore checkpoint review, a final whole-branch review and a security review. Every Critical and Important finding is fixed, or ruled on in the ledger.

### Deviations from the plan

These are all recorded as rulings in the ledger:
- **`make test` workaround:** it passes the swift-testing plugin path, because Command Line Tools intermittently fail to load TestingMacros.
- **Package:** the test target excludes `Fixtures`.
- **Anonymizer:** `anonymize.jq` fixes a jq argument-scoping bug and now rebuilds fixtures from an allowlist of fields.
- **Popover level:** the window is raised one level above popup menus, so OmniWM's workspace bar can't cover it.
- **Shortcut:** it is registered exclusively. Shared registrations, such as Pullover's, can't be detected, and the docs now say so.
- **Focus after closing:** it returns to the previous app, except when a PR was just opened.
- **Wake:** the wake refresh is delayed 15 s, and the timer runs on the suspending clock.
- **`make install`:** it waits for the old instance to exit before launching the new one.
- **Manual checks:** keyboard, shortcut and login-item checks moved to the user checklist. Synthetic input can't safely drive an accessory app while you are using the Mac.

### Follow-ups

- **Manual checklist (README):** still to be walked with you. It covers focus, the shortcut, launch at login, wake and click-outside.
- **Deferred minors:** listed in the ledger and in the final message.
- **Before publishing:** done 2026-09-29. Private org and repository names were replaced with
  placeholders in the docs and throughout git history, via `git filter-branch` over all commits.
- **v2:**
  - Pullover's two-phase fetch
  - snooze
  - Replies to you
  - stacks
  - compact layout
  - the MCP server
  - treating DISMISSED reviews as "not reviewed"

### Manual checklist results (user, 2026-09-29)

- **Passed:**
  - popover under the icon, left alone by OmniWM
  - keyboard: ↑/↓, Enter, R, Esc
  - folding and fold persistence
  - global shortcut and recording
  - click outside closes
  - offline and signed-out states
  - gh missing and gh signed out: setup panel, Copy, recovery after fixing gh
- **Seen but not yet exercised:** the login item appears in Login Items and points at
  /Applications/PRInbox.app; starting at the next login is still to be confirmed.
- **Pending:** sleep/wake keeps the icon normal.
