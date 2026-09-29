# prinbox v1 design

Status: approved in conversation 2026-09-29, pending written-spec review.

prinbox is a native macOS menu-bar code-review inbox, an open-source analogue
of [Pullover](https://github.com/omgovich/pullover). It authenticates only
through the GitHub CLI (`gh`), so it sees every org that `gh` is approved for,
including orgs that restrict third-party OAuth apps.

## 1. Goals and constraints

- Show the pull requests waiting on the user, grouped and ranked, in a
  menu-bar popover.
- Auth: `gh api graphql` only. prinbox never reads, stores or passes a token,
  and has no OAuth app.
- The popup is a real `NSPopover` anchored to an `NSStatusItem`, never a
  normal window, so AX-based tilers (OmniWM, AeroSpace, yabai) ignore it.
- Build with Command Line Tools only (no Xcode): SwiftPM + Makefile.
- Personal use first: ad-hoc signed, installed with `make install`.

Non-goals for v1: snooze, "Replies to you", stacked PRs, compact layout, MCP
server (designed for in section 9, not built), GitHub Enterprise hosts,
notifications, multiple accounts.

## 2. Decisions

| Decision | Choice | Why |
|---|---|---|
| Stack | Swift 6.4, AppKit `NSStatusItem` + `NSPopover`, SwiftUI content in `NSHostingController` | Real popover (AXPopover role, tiler-safe), first-party APIs for every requirement, smallest code. Rust options evaluated: Tauri emulates the popover with a webview panel (open macOS 27 activation bug), objc2 needs ~3-4k LOC of unsafe glue, egui/iced are not popovers. |
| View state | `@Observable` models only; no `@State`, no `#Preview` | On the macOS 27 SDK these are macros whose plugin ships only with Xcode; verified they fail under Command Line Tools. |
| Tests | Swift Testing (`import Testing`) | XCTest is not available without Xcode; Swift Testing verified to run. |
| Global hotkey | Carbon `RegisterEventHotKey`, own recorder view | No Accessibility permission. sindresorhus/KeyboardShortcuts does not build without Xcode. |
| Launch at login | `SMAppService.mainApp` | Works for ad-hoc signed apps in `/Applications`. |
| Location | `~/code/fun/prinbox` | Where the project was started; `~/Projects` does not exist. |
| Bundle id | `io.github.creeonix.prinbox`, app `Prinbox.app` | |
| Minimum OS | macOS 14 | `@Observable`, `onKeyPress`, `SMAppService`. |

## 3. Architecture

```
Package.swift
Sources/PrinboxCore/        Foundation + Observation only, no AppKit. All logic.
  GitHub/                   query text, DTOs, mapper, gh runner, error classifier
  Model/                    PullRequest and value enums
  Inbox/                    classifier, waiting-since, builder, sections, badge
  Format/                   relative age, row text
  State/                    InboxStore, refresh scheduler, selection, folds,
                            hotkey spec, avatar cache
Sources/Prinbox/            thin AppKit + SwiftUI shell
  App/                      entry point, AppDelegate, --print mode
  StatusItem/               NSStatusItem controller, right-click menu
  Popover/                  NSPopover controller, local key monitor
  Views/                    SwiftUI views
  System/                   Carbon hotkey, SMAppService, NSImage avatar loader
Tests/PrinboxCoreTests/     Swift Testing + Fixtures/*.json
scripts/                    record-fixture.sh, anonymize.jq
Resources/Info.plist
Makefile, README.md, LICENSE, THIRD_PARTY_NOTICES.md
```

Rules for the split:
- Anything with a branch worth testing lives in `PrinboxCore`.
- `Prinbox` only wires Core models to AppKit and SwiftUI.
- Core must not import AppKit, so a future `prinbox-mcp` CLI can link it.

### Data flow

```
trigger -> InboxStore.refresh() -> GhClient.fetch() -> decode -> [PullRequest]
        -> InboxBuilder.build(prs, viewer, now) -> Inbox -> status item + popover
```

Triggers:
- a 5-minute timer
- R key or the refresh button
- opening the popover when the last success is older than 60 s
- `NSWorkspace.didWakeNotification`

`RefreshScheduler` allows one fetch in flight. A trigger that arrives during a
fetch queues exactly one follow-up. While rate limited, triggers are ignored
until `resetAt`.

## 4. GitHub access

### gh invocation

`GhClient` implements `InboxFetching`:

```swift
protocol InboxFetching { func fetch() async throws -> FetchResult }
```

It runs:

```
<gh> api graphql -f query=<INBOX_QUERY>
```

- It uses a `CommandRunning` protocol, whose real implementation is
  `Process`, so tests can replay recorded stdout, stderr and exit codes.
- The subprocess runs off the main actor with a 30 s timeout. On timeout the
  process is terminated.

`GhLocator` finds `gh` by checking, in order:
1. the `ghPath` user default, if set
2. `/opt/homebrew/bin/gh`
3. `/usr/local/bin/gh`
4. each entry of `PATH`

A GUI launch does not inherit the shell `PATH`, hence the fixed paths.

### Query

```graphql
query Inbox {
  viewer { login }
  rateLimit { cost remaining resetAt }
  review:   search(query: "is:pr is:open archived:false review-requested:@me sort:updated-desc", type: ISSUE, first: 30) { issueCount nodes { ...pr } }
  mentions: search(query: "is:pr is:open archived:false mentions:@me -author:@me -review-requested:@me sort:updated-desc", type: ISSUE, first: 30) { issueCount nodes { ...pr } }
  mine:     search(query: "is:pr is:open archived:false author:@me sort:updated-desc", type: ISSUE, first: 30) { issueCount nodes { ...pr } }
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
```

Measured on the live account: cost 2 points, about 6 s.

The three searches are disjoint by construction:
- `mentions` excludes `author:@me` and `review-requested:@me`.
- A user cannot be requested on their own PR.

The mapper still deduplicates by `id`, and the first search wins. Search
nodes that are not pull requests (empty objects) are skipped.

### Domain model (`PullRequest`)

`id, number, title, url, repository (nameWithOwner), isArchived, author
(login, "ghost" if null), avatarURL, isDraft, additions, deletions, createdAt,
updatedAt, reviewDecision (approved | changesRequested | reviewRequired |
none), mergeable (mergeable | conflicting | unknown), ci (success | failure |
pending | none), viewerReview (state, submittedAt)?, reviewRequestedAt?,
readyForReviewAt?, source (review | mentions | mine)`.

Field derivations:

| Field | Derived from |
|---|---|
| `ci` | `statusCheckRollup.state`: SUCCESS maps to success; FAILURE or ERROR to failure; PENDING or EXPECTED to pending; null or anything else to none. |
| `viewerReview` | Treated as absent when its state is `PENDING`. |
| `reviewRequestedAt` | The latest `ReviewRequestedEvent` whose `requestedReviewer` is a User with the viewer's login. Otherwise the latest event whose reviewer is not a User (Team, Bot or null), which covers team requests. Otherwise nil. Ported from Pullover `map-pr.ts`. |
| `readyForReviewAt` | The latest `ReadyForReviewEvent`. |

## 5. Classification

Classification is ported from Pullover `src/core/classify.ts` (MIT, Vlad
Shilov) and narrowed to the v1 data. Attribution goes in file headers and in
`THIRD_PARTY_NOTICES.md`.

### Sections, in display order

| Section | Title | Membership | Reason text |
|---|---|---|---|
| `needsReview` | Needs your review | `source == review` and `viewerReview == nil` | Review requested |
| `takeAnotherLook` | Take another look | `source == review` and `viewerReview != nil` | Re-review requested |
| `mentions` | Mentions | `source == mentions` | Mentioned |
| `yourPRs` | Your PRs | `source == mine` and an action reason applies | see below |
| `waitingOnOthers` | Waiting on others | `source == mine` and no action reason | Draft, or Waiting for review |

Action reasons for own PRs. The first match wins (Pullover order):
1. `reviewDecision == changesRequested`: Changes requested
2. `mergeable == conflicting`: Merge conflicts (`unknown` is never a conflict)
3. `ci == failure`: CI is red
4. `reviewDecision == approved` and not draft: Ready to merge

Archived repositories are dropped by the builder even though the query already
excludes them.

Drafts are never hidden. They are shown dimmed in every section.

### Waiting since and sort

`visibleSince = max(createdAt, readyForReviewAt ?? createdAt)`.

| Section | waitingSince | Sort |
|---|---|---|
| Needs your review | `max(reviewRequestedAt ?? createdAt, visibleSince)` | waitingSince ascending (longest waiting first) |
| Take another look | `reviewRequestedAt` if it is after `viewerReview.submittedAt`, else `updatedAt`; floored at `visibleSince` | waitingSince ascending |
| Mentions | `updatedAt` | waitingSince ascending |
| Your PRs | none; row shows "updated X ago" | `updatedAt` descending |
| Waiting on others | none | `updatedAt` descending |

Ties are broken by `number` ascending so ordering is deterministic.

### Badge

The badge count is the number of non-draft PRs in Needs your review, Take
another look and Mentions.

### Caps

Each section shows at most 8 PR rows. Hidden overflow becomes one row,
"+N more on GitHub".

If a search returned fewer nodes than its `issueCount`, the unfetched
remainder is added to N of the last section fed by that search:
- `review` feeds Take another look
- `mentions` feeds Mentions
- `mine` feeds Waiting on others

In that case the row appears even when the section is under the cap.

The "more" rows link to:
- review sections: `https://github.com/pulls/review-requested`
- Mentions: `https://github.com/pulls/mentioned`
- own sections: `https://github.com/pulls`

## 6. Errors

A failed refresh keeps the last good `Inbox` and records a `FetchError`.

| FetchError | Detection | Status item | Popover warning line |
|---|---|---|---|
| `ghNotFound` | locator finds nothing | red "!" | gh not found: `brew install gh` |
| `loggedOut` | exit 4, or stderr contains `HTTP 401` or `Bad credentials` | red "!" | gh is not logged in: run `gh auth login` |
| `offline` | exit 1 and stderr matches a network error (`dial tcp`, `no such host`, `connection refused`, `network is unreachable`, `i/o timeout`, `TLS handshake timeout`, `error connecting to`) | red "!" | Offline, showing data from HH:MM |
| `timedOut` | 30 s timeout fired | red "!" | GitHub did not answer in time |
| `rateLimited(resetAt)` | stderr contains `rate limit`, or a GraphQL error of type `RATE_LIMITED` | red "!" | Rate limited until HH:MM |
| `badResponse` | JSON failed to decode | red "!" | Unexpected response from gh |
| `other(message)` | any other non-zero exit | red "!" | first stderr line, cut to 120 chars |

Partial success is not an error. When `errors` and `data` are both present,
the builder uses `data`, drops null nodes, and emits one warning per error.
The warning names the org when the message or path allows it, for example
"example-org requires SSO re-authorization: results incomplete". The status item
stays normal (not red) in this case.

Logging:
- stderr, truncated, goes to the unified log (`os.Logger`, subsystem = bundle
  id).
- stdout is never logged.

## 7. UI

### Status item

| State | Rendering |
|---|---|
| loading (no data yet) | `arrow.triangle.pull` template symbol, dimmed, title "…" |
| count > 0 | symbol plus the count |
| zero | symbol only, `appearsDisabled` (dimmed) |
| error | symbol tinted `systemRed`, title "!", tooltip with the error text |

- Left click toggles the popover.
- Right click opens a menu: Refresh now, Quit prinbox.

### Popover mechanics

- It is an `NSPopover` with behavior `.transient` and width 420. Height fits
  the content up to 600, then scrolls.
- On show:
  1. `NSApp.activate()`
  2. make the popover window key
  3. install a local `keyDown` monitor
- The monitor is removed when the popover closes.
- Keys: ↑ and ↓ move the selection (wrapping). Enter activates. R refreshes.
  Esc closes.
- Opening a URL calls `NSWorkspace.shared.open(url)` and then
  `popover.performClose`.

### Layout

- **Header.** "N waiting on you · updated HH:MM" (24 h, local time), a
  refresh button that shows a spinner while fetching, and a gear.
- **Warning line.** Shown under the header while there is an error or any
  partial-data warnings.
- **Section header.** A chevron, the title and a count chip. Clicking it, or
  Enter while it is selected, toggles the fold.
  - Fold state is persisted in UserDefaults under `foldedSections`.
  - First-run default: every section is folded except Needs your review.
  - Empty sections are hidden.
- **PR row.**
  - A 28 pt round avatar, with an initials placeholder until the image loads.
  - Line 1: `#123 Title`, one line, truncated.
  - Line 2:
    - review sections and Mentions: `repo · waiting 6h · +120 −4 · status`
    - own PRs: `repo · updated 3h ago · +120 −4 · status`
  - `repo` is the short name. A tooltip shows the full `owner/name`.
  - Status colors: red for CI is red, Merge conflicts and Changes requested;
    green for Ready to merge; accent for the review and mention reasons;
    secondary for everything else.
  - Drafts are drawn at 50% opacity.
- **Waiting on others row.** One dim line: `#123 Title · Waiting for review`.
- **More row.** "+N more on GitHub" in the accent color.
- **Empty state.** When no section has rows: "Inbox zero. Nothing waiting on
  you."
- **Selection.** Hover and keyboard selection share one highlight. The
  selection model is a flat list of section headers, visible rows and more
  rows; rows inside folded sections are skipped. After a refresh or a fold,
  the selection stays on the same item id. If that item is gone, it moves to
  the nearest preceding item that still exists, so folding lands on the
  section header.

Age format, from the prototype: under 1 min is `<1m`, under 60 min is `Nm`,
under 48 h is `Nh`, otherwise `Nd`, always floored.

### Settings

Settings are a view inside the popover, reached from the gear. There is no
separate window.

- **Global shortcut.** A recorder field (default ⌃⌥P) with a clear button.
  - The shortcut is stored as key code plus Carbon modifiers.
  - Registration is exclusive. If it fails, show "Shortcut unavailable (in
    use by another app)". macOS lets apps that register non-exclusively
    (such as Pullover, which also defaults to ⌃⌥P) share a shortcut without
    any way to detect it; both then respond.
- **Launch at login.** A toggle using `SMAppService.mainApp`.
  - The toggle shows its status, including `requiresApproval`, which points
    to System Settings › Login Items.
  - Warn when running from outside `/Applications`.
- **Info.** The detected `gh` path, the app version, and a Quit button.

### Avatars

- Core's `AvatarCache` fetches `avatarUrl` (size 64) through an injected
  loader.
- It stores bytes at `~/Library/Caches/io.github.creeonix.prinbox/avatars/<login>.png`
  with a 7-day TTL.
- The app keeps decoded `NSImage`s in memory for the session.
- Failures fall back to initials.

### Setup panel (gh missing or signed out)

Added 2026-09-29 after v1 review:
- When the error is `ghNotFound` or `loggedOut`, the popover replaces the list with a setup panel from
  `SetupGuide`: a title, a one-line summary and numbered steps whose commands have Copy buttons. The
  header reads "Setup needed", and the warning line leaves that error out.
  - `ghNotFound` without an override: `brew install gh`, then `gh auth login`, plus a link to
    cli.github.com and the `ghPath` override hint.
  - `ghNotFound` with an override: names the path, and offers
    `defaults delete io.github.creeonix.prinbox ghPath` or `brew install gh`.
  - `loggedOut`: `gh auth login` (GitHub.com, then "Login with a web browser"), with an SSO note.
- While setup is needed, the app retries every 10 s (`InboxStore.setupRetryInterval`). A missing or
  signed-out gh fails locally, so the retry costs no API requests.
- The status-item tooltip says "gh not installed, click for setup" or "gh not signed in, click for setup".
- `--print` prints the same steps as plain text and exits 1.
- The `ghPath` override is exclusive: when set, only that path is tried.
- When the first load fails for any other reason, the popover shows "Couldn't load your inbox" instead of
  a spinner.
- The user-facing name is PRInbox (bundle display name, menus, tooltips, texts); the app installs as
  `/Applications/PRInbox.app`. The executable, targets and repository keep the name prinbox.

### --print mode

`Prinbox --print` runs one fetch and prints the classified inbox as text to
stdout, then exits: badge count, then sections and rows, then warnings. It
starts no UI. It is the live end-to-end check.

## 8. Testing

- **Framework.** Swift Testing via `swift test`. `make coverage` reports line
  coverage for `PrinboxCore`; the target is at least 80%.
- **Recorded fixtures.**
  - `scripts/record-fixture.sh <name>` runs `INBOX_QUERY` through `gh` and
    pipes the result through `scripts/anonymize.jq` into
    `Tests/PrinboxCoreTests/Fixtures/<name>.json`.
  - The anonymizer is deterministic: repositories become `acme/repo-N`,
    logins become `user-N` (the viewer becomes `me`), titles become
    `PR title N`, and URLs and ids are rebuilt from those values.
  - No private org data is committed.
- **Hand-built fixtures.** Built from the same shape, for cases not present
  on the live account today:
  - review requested, direct and via a team
  - re-requested after a review
  - a pending viewer review
  - a mention
  - an archived repo leaking through
  - a draft
  - each own-PR reason and their precedence
  - mergeable `UNKNOWN`
  - partial `errors` with SAML
  - empty inbox
  - over-cap sections and truncated searches
- **Error fixtures.** Exit code plus stderr pairs for logged out (exit 4), bad
  credentials (exit 1, HTTP 401), offline (exit 1, `dial tcp`), rate limit,
  and gh missing.
- **Ported tests.** Pullover's classify precedence, `UNKNOWN` not being a
  conflict, waiting-since with the team fallback and the draft floor, and
  ordering. These files carry an attribution header.
- **UI-logic tests:**
  - `SelectionModel`: wrapping, skipping folded sections, keeping the
    selection across a refresh
  - `FoldStore`: defaults and persistence, with an injected key-value store
  - `RefreshScheduler`: coalescing and the rate-limit pause
  - status item state derivation
  - age and row text formatting
  - `HotKeySpec` display strings
  - `AvatarCache` TTL
- **Build guard.** `make lint` runs `swift format lint` and fails on `@State`
  or `#Preview` in `Sources/`.
- **Live check.** `Prinbox --print` against the real account. Today it must
  show 7 own PRs and no `example-org/archived-repo`.
- **Manual checklist** (in the README):
  - the popover opens under the icon
  - OmniWM leaves it alone
  - click outside closes it
  - ↑/↓/Enter/R/Esc work
  - clicking a row opens the browser and closes the popover
  - the global shortcut works, and recording a new one works
  - the launch-at-login toggle works
  - pulling the network gives a red state with stale data kept

## 9. v2 design hooks (not built in v1)

- **Richer fetch.** `InboxFetching` gets a second implementation: Pullover's
  two-phase fetch.
  1. Search for ids with the same qualifiers plus `involves:@me`.
  2. `nodes(ids:)` in batches of 10, with `reviews`, `reviewThreads`,
     `comments`, `headRefName` and `baseRefName`.

  `PullRequest` gains optional `threads`, `comments`, `headRef` and `baseRef`.
  New rules slot into the first-match order:
  - "Replies to you" after Needs your review
  - "New commits" re-review
  - mentions newer than the viewer's last activity
- **Snooze until new activity.** A `SnoozeStore` persisted as JSON at
  `~/Library/Application Support/prinbox/state.json`, keyed by PR node id,
  holding `snoozedAt`.
  - It wakes on a reply from someone else in an unresolved thread the viewer
    commented in, or on a commit newer than `snoozedAt` (Pullover
    `snooze.ts`).
  - The S key toggles it.
  - Snoozed PRs move to Waiting on others with the reason "Snoozed".
- **Replies to you.** A section after Needs your review, built from
  `reviewThreads`. Its waitingSince is the oldest pending reply.
- **Stacked PRs.** A PR's parent is the PR in the same repo whose `headRefName`
  equals its `baseRefName`.
  - Only simple chains count.
  - The builder keeps a chain contiguous.
  - Rows get an `i/n` badge.
- **Compact layout.** The row style used by Waiting on others becomes a
  setting that applies to every section.
- **MCP server.** A separate `prinbox-mcp` stdio executable that links
  `PrinboxCore`.
  - Tools: `get_inbox`, `snooze_pull_request`, `unsnooze_pull_request`.
  - It shares `state.json` with the app, which watches the file.
  - Unlike Pullover's localhost HTTP server, stdio opens no network port.

## 10. Packaging

Makefile targets:
- `test`
- `lint`
- `coverage`
- `build` (release)
- `app`: assembles `build/Prinbox.app` from the release binary and
  `Resources/Info.plist`, which sets `LSUIElement`, the bundle id, the version
  and `LSMinimumSystemVersion` 14.0, then signs it with
  `codesign --force --sign - --identifier io.github.creeonix.prinbox`
- `install`: quits the running app, then copies it to `/Applications`
- `uninstall`: unregisters the login item and removes the app, its caches and
  its defaults
- `run`: debug build

SwiftPM resources are not used, because `Bundle.module` breaks codesign on a
hand-assembled bundle. Icons are SF Symbols.

Repository files:
- `LICENSE`: MIT, copyright 2026 creeonix
- `THIRD_PARTY_NOTICES.md`: Pullover (MIT, Vlad Shilov) and omarchy-pullover
  (MIT, Igor Alexandrov)
- `README.md`: requirements (macOS 14+, Command Line Tools, `gh` logged in),
  install, usage, the manual checklist, and the Xcode-free constraints

## 11. Acceptance criteria (v1)

1. `make test` passes and `make coverage` reports at least 80% line coverage
   for `PrinboxCore`.
2. `make install` produces a working, ad-hoc signed `/Applications/Prinbox.app`
   with no Dock icon.
3. `Prinbox --print` on the live account shows the 7 open PRs in example-org
   repos, and nothing from `example-org/archived-repo`. Review sections
   appear whenever review requests exist.
4. Status item states: count, dimmed at zero, red with a reason when gh is
   logged out (`GH_CONFIG_DIR` pointed at an empty dir) or offline.
5. Every item on the section 8 manual checklist passes under OmniWM.
