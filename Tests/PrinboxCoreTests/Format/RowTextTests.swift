import Foundation
import Testing

@testable import PrinboxCore

@Suite struct RowTextTests {
    let now = date("2026-08-10T12:00:00Z")
    let utc = TimeZone(identifier: "UTC")!

    func row(_ pr: PullRequest) -> InboxRow {
        InboxRow(pullRequest: pr, classification: Classifier.classify(pr, viewer: testViewer)!)
    }

    @Test func metaShowsTheOwnerOnlyWhenAsked() {
        let pr = makePR(
            repository: "globex/billing", additions: 1, deletions: 0,
            reviewRequestedAt: date("2026-08-10T06:00:00Z"))
        #expect(RowText.meta(row(pr), now: now) == "billing · waiting 6h · +1 −0")
        #expect(RowText.meta(row(pr), now: now, showOrg: true) == "globex/billing · waiting 6h · +1 −0")
        #expect(RowText.detail(row(pr), now: now) == "billing · waiting 6h · +1 −0 · Review requested")
    }

    @Test func compactRowCarriesItsStackPosition() throws {
        let base = makePR(id: "base", number: 1, source: .mine, headRef: "f1", baseRef: "main")
        let top = makePR(id: "top", number: 2, source: .mine, headRef: "f2", baseRef: "f1")
        let lone = makePR(id: "lone", number: 3, source: .mine)
        let stacked = InboxBuilder.build(makeResult([base, top]))
        let rows = try #require(stacked.section(.waitingOnOthers)).rows
        let baseRow = try #require(rows.first { $0.pullRequest.id == "base" })
        let topRow = try #require(rows.first { $0.pullRequest.id == "top" })
        #expect(RowText.compact(baseRow).hasSuffix(" · stack 1/2"))
        #expect(RowText.compact(topRow).hasSuffix(" · stack 2/2"))
        #expect(RowText.compact(row(lone)) == "#3 Add feature · Waiting for review")
    }

    @Test func compactTrailerNamesTheRepositoryAndDraft() {
        let pr = makePR(repository: "globex/billing", source: .mine)
        #expect(RowText.compactTrailer(row(pr)) == "· billing")
        #expect(RowText.compactTrailer(row(pr), showOrg: true) == "· globex/billing")
        let draft = makePR(repository: "globex/billing", isDraft: true, source: .mine)
        #expect(RowText.compactTrailer(row(draft), showOrg: true) == "· globex/billing · Draft")
    }

    @Test func titleShowsNumberAndTitle() {
        #expect(RowText.title(makePR(number: 12, title: "Fix it")) == "#12 Fix it")
    }

    @Test func titleCollapsesLineBreaksAndTabs() {
        #expect(RowText.title(makePR(number: 1, title: "Fix\nthe\t\tthing\r\nnow")) == "#1 Fix the thing now")
    }

    @Test func titleNeutralizesControlAndBidiCharacters() {
        #expect(RowText.title(makePR(number: 1, title: "a\u{1B}[31mb\u{202E}c\u{2066}d")) == "#1 a [31mb c d")
    }

    @Test func titleKeepsEmojiSequences() {
        #expect(
            RowText.title(makePR(number: 1, title: "ship \u{1F468}\u{200D}\u{1F4BB}"))
                == "#1 ship \u{1F468}\u{200D}\u{1F4BB}")
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
        #expect(RowText.header(badgeCount: 0, lastSuccess: nil, needsSetup: true, timeZone: utc) == "Setup needed")
        #expect(
            RowText.header(badgeCount: 2, lastSuccess: date("2026-08-10T12:05:00Z"), timeZone: utc)
                == "2 waiting on you · updated 12:05")
    }

    @Test func compactTrailerSaysSnoozedEvenForDrafts() {
        let pr = makePR(repository: "globex/billing", isDraft: true)
        let row = InboxRow(pullRequest: pr, classification: Classifier.classify(pr, viewer: testViewer, snoozed: true)!)
        #expect(RowText.compactTrailer(row, showOrg: true) == "· globex/billing · Snoozed")
        #expect(RowText.compact(row) == "#1 Add feature · Snoozed")
    }

    @Test func headerCountsNewRows() {
        let at = date("2026-08-10T12:05:00Z")
        #expect(
            RowText.header(badgeCount: 5, lastSuccess: at, newCount: 3, timeZone: utc)
                == "5 waiting on you · updated 12:05 · 3 new")
        #expect(
            RowText.header(badgeCount: 5, lastSuccess: at, newCount: 0, timeZone: utc)
                == "5 waiting on you · updated 12:05")
        #expect(RowText.header(badgeCount: 0, lastSuccess: nil, newCount: 3, timeZone: utc) == "Loading…")
    }

    @Test func compactAgeIsTheWaitingAgeOrTheUpdateAge() {
        let waiting = row(makePR(reviewRequestedAt: date("2026-08-10T04:00:00Z")))
        #expect(RowText.compactAge(waiting, now: now) == "8h")
        let own = row(makePR(updatedAt: date("2026-08-10T11:00:00Z"), source: .mine))
        #expect(RowText.compactAge(own, now: now) == "1h ago")
    }

    @Test func compactTrailerAppendsTheAgeAfterDraftOrSnoozed() {
        let draft = row(makePR(repository: "globex/billing", isDraft: true))
        #expect(RowText.compactTrailer(draft, showOrg: true, age: "2h") == "· globex/billing · Draft · 2h")
        #expect(RowText.compactTrailer(draft, age: nil) == "· billing · Draft")
        let pr = makePR(repository: "globex/billing")
        let snoozed = InboxRow(
            pullRequest: pr, classification: Classifier.classify(pr, viewer: testViewer, snoozed: true)!)
        #expect(RowText.compactTrailer(snoozed, age: "2h") == "· billing · Snoozed · 2h")
    }

    @Test func metaAndTrailerCarryTheStack() throws {
        let base = makePR(
            id: "base", number: 1, repository: "globex/billing", reviewRequestedAt: date("2026-08-10T06:00:00Z"),
            headRef: "f1", baseRef: "main")
        let top = makePR(
            id: "top", number: 2, repository: "globex/billing", isDraft: true, additions: 1, deletions: 0,
            source: .mine, headRef: "f2", baseRef: "f1")
        let inbox = InboxBuilder.build(makeResult([base, top]))
        let baseRow = try #require(inbox.section(.needsReview)?.rows.first)
        let topRow = try #require(inbox.section(.waitingOnOthers)?.rows.first)
        #expect(RowText.meta(baseRow, now: now).hasSuffix(" · stack 1/2"))
        #expect(RowText.detail(baseRow, now: now).hasSuffix(" · stack 1/2 · Review requested"))
        #expect(RowText.compactTrailer(topRow, showOrg: true) == "· globex/billing · stack 2/2 · Draft")
        #expect(RowText.help(topRow) == "globex/billing · stacked on #1")
        #expect(RowText.help(baseRow) == "globex/billing")
    }

    @Test func emptyStateNamesTheDefaultRepositories() {
        #expect(RowText.emptyState(repositories: []) == "Nothing waiting on you.")
        #expect(
            RowText.emptyState(repositories: ["acme/*", "globex/billing"])
                == "Nothing waiting on you in acme/*, globex/billing.")
    }
}
