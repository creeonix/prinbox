import Foundation
import Testing

@testable import PrinboxCore

@Suite struct RowTextTests {
    let now = date("2026-08-10T12:00:00Z")
    let utc = TimeZone(identifier: "UTC")!

    func row(_ pr: PullRequest) -> InboxRow {
        InboxRow(pullRequest: pr, classification: Classifier.classify(pr))
    }

    @Test func metaShowsTheOwnerOnlyWhenAsked() {
        let pr = makePR(
            repository: "globex/billing", additions: 1, deletions: 0,
            reviewRequestedAt: date("2026-08-10T06:00:00Z"))
        #expect(RowText.meta(row(pr), now: now) == "billing · waiting 6h · +1 −0")
        #expect(RowText.meta(row(pr), now: now, showOrg: true) == "globex/billing · waiting 6h · +1 −0")
        #expect(RowText.detail(row(pr), now: now) == "billing · waiting 6h · +1 −0 · Review requested")
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
        let row = InboxRow(pullRequest: pr, classification: Classifier.classify(pr, snoozed: true))
        #expect(RowText.compactTrailer(row, showOrg: true) == "· globex/billing · Snoozed")
        #expect(RowText.compact(row) == "#1 Add feature · Snoozed")
    }
}
