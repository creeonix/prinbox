import Foundation
import Testing

@testable import PrinboxCore

@Suite struct GraphQLErrorsTests {
    func map(_ json: String) throws -> FetchResult {
        try PullRequestMapper.map(InboxResponse.decode(Data(json.utf8)))
    }

    let emptySearches =
        #""review":{"issueCount":0,"nodes":[]},"mentions":{"issueCount":0,"nodes":[]},"mine":{"issueCount":0,"nodes":[]}"#

    @Test func samlErrorNextToDataBecomesAWarning() throws {
        let json =
            #"{"data":{"viewer":{"login":"me"},"#
            + #""review":{"issueCount":1,"nodes":[null]},"mentions":{"issueCount":0,"nodes":[]},"mine":{"issueCount":0,"nodes":[]}},"#
            + #""errors":[{"type":"FORBIDDEN","message":"Resource protected by organization SAML enforcement. You must grant your OAuth token access to this organization."}]}"#
        let result = try map(json)
        #expect(result.pullRequests.isEmpty)
        #expect(result.warnings == ["An org requires SSO authorization for gh: results incomplete"])
    }

    @Test func oauthRestrictionNamesTheOrg() throws {
        let message =
            "Although you appear to have the correct authorization credentials, the `acme` organization has enabled OAuth App access restrictions, meaning that data access to third-parties is limited."
        let json =
            #"{"data":{"viewer":{"login":"me"},"# + emptySearches + #"},"errors":[{"type":"FORBIDDEN","message":""#
            + message + #""}]}"#
        #expect(try map(json).warnings == ["acme restricts gh (OAuth app access): results incomplete"])
    }

    @Test func otherErrorsAreQuotedAndDeduplicated() throws {
        let json =
            #"{"data":{"viewer":{"login":"me"},"# + emptySearches
            + #"},"errors":[{"message":"Something failed"},{"message":"Something failed"}]}"#
        #expect(try map(json).warnings == ["GitHub: Something failed"])
    }

    @Test func rateLimitedErrorThrowsWithResetTime() {
        let json =
            #"{"data":{"viewer":null,"rateLimit":{"resetAt":"2026-08-10T13:00:00Z"}},"#
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
