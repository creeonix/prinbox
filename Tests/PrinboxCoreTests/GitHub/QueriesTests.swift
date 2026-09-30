import Testing

@testable import PrinboxCore

@Suite struct QueriesTests {
    @Test func searchAsksForIdsOnlyAndExcludesArchivedRepositories() {
        let text = SearchQuery.text(includeInvolved: true)
        #expect(text.hasPrefix("query InboxIDs {"))
        #expect(text.contains("viewer { login }"))
        #expect(text.contains("rateLimit { cost remaining resetAt }"))
        #expect(text.components(separatedBy: "archived:false").count - 1 == 4)
        #expect(text.components(separatedBy: "nodes { ... on PullRequest { id updatedAt } }").count - 1 == 4)
        #expect(text.contains("first: 30"))
        #expect(!text.contains("title"))
    }

    @Test func involvedSearchExcludesTheOtherThreeQualifiersAndIsOptional() {
        let on = SearchQuery.text(includeInvolved: true)
        #expect(
            on.contains(
                "involved: search(query: \"is:pr is:open archived:false involves:@me -author:@me -review-requested:@me -mentions:@me sort:updated-desc\""
            ))
        let off = SearchQuery.text(includeInvolved: false)
        #expect(!off.contains("involved"))
        #expect(off.components(separatedBy: "search(").count - 1 == 3)
    }

    @Test func detailsTemplateCarriesTheRowFieldsAndThePlaceholder() {
        let text = DetailsQuery.template(includeConversation: true)
        #expect(text.contains("nodes(ids: [__IDS__])"))
        for field in [
            "totalCommentsCount", "headRefName baseRefName", "owner { __typename login avatarUrl(size: 64) }",
            "latestOpinionatedReviews(first: 10) { nodes { state } }", "committedDate statusCheckRollup { state }",
            "timelineItems(last: 20, itemTypes: [REVIEW_REQUESTED_EVENT, READY_FOR_REVIEW_EVENT])",
            "reviewThreads(last: 30) { totalCount nodes { isResolved comments(last: 20) { totalCount nodes { author { login } createdAt } } } }",
            "reviews(last: 50) { totalCount nodes { author { login } state submittedAt } }",
        ] {
            #expect(text.contains(field), "\(field)")
        }
        #expect(!text.contains("bodyText"))
        let rows = DetailsQuery.template(includeConversation: false)
        #expect(!rows.contains("reviewThreads"))
        #expect(!rows.contains("reviews("))
        #expect(rows.contains("headRefName"))
    }

    @Test func detailsTextInlinesQuotedIDs() {
        let text = DetailsQuery.text(ids: ["PR_kwDOA1", "PR_kwDOA2"], includeConversation: true)
        #expect(text.contains("nodes(ids: [\"PR_kwDOA1\", \"PR_kwDOA2\"])"))
        #expect(!text.contains(DetailsQuery.placeholder))
    }

    @Test func invalidIDsAreNeverInlined() {
        let text = DetailsQuery.text(
            ids: ["PR_1", "bad\"id", "new\nline", "", "with space", "PR_2=="], includeConversation: false)
        #expect(text.contains("nodes(ids: [\"PR_1\", \"PR_2==\"])"))
        #expect(!text.contains("bad"))
        #expect(DetailsQuery.text(ids: ["PR_9", "x y"], includeConversation: true).contains("nodes(ids: [\"PR_9\"])"))
        #expect(!DetailsQuery.isValidID("é"))
        #expect(DetailsQuery.isValidID("PR_kwDOABCD-5M6xyz="))
    }
}
