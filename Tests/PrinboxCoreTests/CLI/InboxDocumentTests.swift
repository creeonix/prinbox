import Foundation
import Testing

@testable import PrinboxCore

@Suite struct InboxDocumentTests {
    let now = date("2026-08-10T12:00:00Z")
    let meta = DocumentMeta(
        prinbox: "0.5.0-test", source: "fetch", fetchedAt: date("2026-08-10T11:58:00Z"),
        checkedAt: date("2026-08-10T12:00:00Z"), viewer: "me", error: nil)

    @Test func everySectionAppearsInOrderEvenWhenEmpty() {
        let document = InboxDocument.make(
            InboxBuilder.build(makeResult([makePR()])), meta: meta, isNew: { _ in false }, now: now)
        #expect(document.sections.map(\.kind) == SectionKind.allCases.map(\.rawValue))
        #expect(document.sections.map(\.title) == SectionKind.allCases.map(\.title))
        #expect(document.sections.map { $0.rows.count } == [1, 0, 0, 0, 0, 0, 0])
        #expect(document.sections[0].moreUrl == SectionKind.needsReview.moreURL)
        #expect(document.version == 1)
        #expect(document.prinbox == "0.5.0-test")
        #expect(document.badge == 1)
    }

    @Test func aRowCarriesCodesTextMarksAndTheStack() throws {
        let base = makePR(
            id: "base", number: 1, repository: "acme/web", authorLogin: "bob", additions: 5, deletions: 2,
            reviewDecision: .changesRequested, ci: .failure, reviewRequestedAt: date("2026-08-10T08:00:00Z"),
            commentCount: 4, headRef: "f1", baseRef: "main")
        let top = makePR(
            id: "top", number: 2, repository: "acme/web", ci: .pending, source: .mine, headRef: "f2", baseRef: "f1")
        let document = InboxDocument.make(
            InboxBuilder.build(makeResult([base, top])), meta: meta, isNew: { $0.id == "top" }, now: now)
        let row = try #require(document.sections[0].rows.first)
        #expect(row.id == "base")
        #expect(row.number == 1)
        #expect(row.repository == "acme/web")
        #expect(row.author == "bob")
        #expect(row.reason == "reviewRequested")
        #expect(row.reasonText == "Review requested")
        #expect(row.age == "4h")
        #expect(row.waitingSince == date("2026-08-10T08:00:00Z"))
        #expect(row.marks.comments == 4)
        #expect(row.marks.ci == "failure")
        #expect(row.marks.review == "changesRequested")
        #expect(row.stack == InboxDocument.Stack(position: 1, size: 2, parentId: nil))
        #expect(row.isNew == false)
        #expect(row.snoozed == false)
        let own = try #require(document.sections[5].rows.first)
        #expect(own.reason == "waitingForReview")
        #expect(own.waitingSince == nil)
        #expect(own.age == "9d")
        #expect(own.stack == InboxDocument.Stack(position: 2, size: 2, parentId: "base"))
        #expect(own.isNew == true)
        #expect(document.newCount == 1)
    }

    @Test func aSnoozedRowSaysSo() throws {
        let pr = makePR(id: "p")
        let document = InboxDocument.make(
            InboxBuilder.build(makeResult([pr]), snoozed: ["p"]), meta: meta, isNew: { _ in false }, now: now)
        let row = try #require(document.sections[5].rows.first)
        #expect(row.snoozed)
        #expect(row.reason == "snoozed")
        #expect(document.badge == 0)
    }

    @Test func noInboxGivesSevenEmptySectionsAndTheError() {
        let error = InboxDocument.ErrorInfo(code: "offline", message: "Offline", help: nil)
        let empty = DocumentMeta(prinbox: "x", source: nil, fetchedAt: nil, checkedAt: nil, viewer: nil, error: error)
        let document = InboxDocument.make(nil, meta: empty, isNew: { _ in false }, now: now)
        #expect(document.sections.count == 7)
        #expect(document.sections.allSatisfy { $0.rows.isEmpty })
        #expect(document.error == error)
        #expect(document.source == nil)
        #expect(document.badge == 0)
    }

    @Test func reasonCodesAreStable() {
        let codes = [
            Reason.reviewRequested, .reReviewRequested, .mentioned, .awaitingReply, .openThreads, .changesRequested,
            .mergeConflicts, .ciRed, .readyToMerge, .draft, .waitingForReview, .snoozed,
        ].map(\.code)
        #expect(
            codes == [
                "reviewRequested", "reReviewRequested", "mentioned", "awaitingReply", "openThreads", "changesRequested",
                "mergeConflicts", "ciRed", "readyToMerge", "draft", "waitingForReview", "snoozed",
            ])
    }

    @Test func moreUrlFollowsTheInboxScope() {
        let scope = SearchScope(hideDrafts: true)
        let inbox = InboxBuilder.build(makeResult([makePR()]), scope: scope)
        let document = InboxDocument.make(inbox, meta: meta, isNew: { _ in false }, now: now)
        #expect(document.sections[0].moreUrl == SectionKind.needsReview.moreURL(scope: scope))
        #expect(document.sections[5].moreUrl == SectionKind.waitingOnOthers.moreURL(scope: scope))
        let empty = InboxDocument.make(nil, meta: meta, isNew: { _ in false }, now: now)
        #expect(empty.sections[0].moreUrl == SectionKind.needsReview.moreURL)
    }

    @Test func theDocumentNamesTheDefaultRepositoriesFromTheMeta() throws {
        let filtered = DocumentMeta(
            prinbox: "0.5.0-test", source: "fetch", fetchedAt: now, checkedAt: now, viewer: "me", error: nil,
            defaultRepositories: ["acme/*", "globex/billing"])
        let document = InboxDocument.make(
            InboxBuilder.build(makeResult([makePR()])), meta: filtered, isNew: { _ in false }, now: now)
        #expect(document.defaultRepositories == ["acme/*", "globex/billing"])
        let text = InboxJSON.render(document)
        #expect(text.contains("\"defaultRepositories\" : [\n    \"acme/*\",\n    \"globex/billing\"\n  ]"))
        let plain = InboxDocument.make(nil, meta: meta, isNew: { _ in false }, now: now)
        #expect(plain.defaultRepositories == [])
        #expect(InboxJSON.render(plain).contains("\"defaultRepositories\" : [\n\n  ]"))
        let decoded = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
        #expect(decoded["defaultRepositories"] == ["acme/*", "globex/billing"])
    }
}
