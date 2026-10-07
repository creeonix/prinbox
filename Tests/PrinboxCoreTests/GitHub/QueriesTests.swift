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
        #expect(text.contains("isCrossRepository"))
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

    @Test func validIDsFiltersWhatTextWouldDrop() {
        #expect(DetailsQuery.validIDs(["PR_1", "", "bad id", "PR_2=="]) == ["PR_1", "PR_2=="])
    }

    @Test func scopeChangesTheQualifiersOfEverySearch() {
        let scope = SearchScope(
            directReviewRequestsOnly: true, repositories: ["acme", "globex/billing"], hideDrafts: true)
        #expect(
            SearchQuery.qualifier(.review, scope: scope)
                == "user-review-requested:@me -is:draft user:acme repo:globex/billing")
        #expect(
            SearchQuery.qualifier(.mentions, scope: scope)
                == "mentions:@me -author:@me -user-review-requested:@me -is:draft user:acme repo:globex/billing")
        #expect(SearchQuery.qualifier(.mine, scope: scope) == "author:@me user:acme repo:globex/billing")
        #expect(
            SearchQuery.qualifier(.involved, scope: scope)
                == "involves:@me -author:@me -user-review-requested:@me -mentions:@me -is:draft user:acme repo:globex/billing"
        )
        #expect(
            SearchQuery.qualifier(.review, scope: SearchScope(hideDrafts: true)) == "review-requested:@me -is:draft")
        #expect(SearchQuery.qualifier(.mine, scope: SearchScope(hideDrafts: true)) == "author:@me")
        #expect(
            SearchQuery.qualifier(.mentions, scope: SearchScope(directReviewRequestsOnly: true))
                == "mentions:@me -author:@me -user-review-requested:@me")
        #expect(
            SearchQuery.qualifier(.mine, scope: SearchScope(repositories: ["acme/web"])) == "author:@me repo:acme/web")
        let text = SearchQuery.text(includeInvolved: true, scope: scope)
        #expect(text.components(separatedBy: "user:acme repo:globex/billing").count - 1 == 4)
        #expect(text.components(separatedBy: " -is:draft").count - 1 == 3)
        #expect(!text.contains(" review-requested:@me"))
        #expect(SearchQuery.text(includeInvolved: true) == SearchQuery.text(includeInvolved: true, scope: .none))
    }

    @Test func theQueryStringIsTheOneGitHubSees() {
        #expect(SearchQuery.query(.review) == "is:pr is:open archived:false review-requested:@me sort:updated-desc")
        let longest = SearchScope(directReviewRequestsOnly: true, hideDrafts: true)
        #expect(
            SearchQuery.query(.involved, scope: longest)
                == "is:pr is:open archived:false involves:@me -author:@me -user-review-requested:@me -mentions:@me -is:draft sort:updated-desc"
        )
        #expect(SearchQuery.query(.involved, scope: longest).count == 122)
        #expect(SearchQuery.query(.mentions, scope: longest).count == 108)
    }

    @Test func overflowCountsCharactersPastTheLimit() {
        // The longest base is `involved` with direct-only and drafts hidden: 122 characters (29 for
        // "is:pr is:open archived:false ", 65 for the qualifier, 10 for " -is:draft", 18 for " sort:updated-desc").
        // One owner entry adds " user:" (6) plus its length: 128 letters land exactly on 256, 129 go one over.
        let fits = SearchScope(
            directReviewRequestsOnly: true, repositories: [String(repeating: "a", count: 128)], hideDrafts: true)
        #expect(SearchQuery.query(.involved, scope: fits).count == 256)
        #expect(SearchQuery.overflow(includeInvolved: true, scope: fits) == 0)
        let over = SearchScope(
            directReviewRequestsOnly: true, repositories: [String(repeating: "a", count: 129)], hideDrafts: true)
        #expect(SearchQuery.overflow(includeInvolved: true, scope: over) == 1)
        // Without the involved search the longest is `mentions`, 108 base: 142 letters fit, 143 is one over.
        #expect(SearchQuery.overflow(includeInvolved: false, scope: over) == 0)
        let mentionsOver = SearchScope(
            directReviewRequestsOnly: true, repositories: [String(repeating: "a", count: 143)], hideDrafts: true)
        #expect(SearchQuery.overflow(includeInvolved: false, scope: mentionsOver) == 1)
        #expect(SearchQuery.overflow(includeInvolved: true, scope: .none) == 0)
        #expect(SearchQuery.queryLimit == 256)
    }
}
