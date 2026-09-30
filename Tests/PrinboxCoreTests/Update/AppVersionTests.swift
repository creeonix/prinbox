import Testing

@testable import PrinboxCore

@Suite struct AppVersionTests {
    @Test func parsesTagsAndPlainVersions() {
        #expect(AppVersion("v0.3.0")?.components == [0, 3, 0])
        #expect(AppVersion("0.3.0") == AppVersion("v0.3.0"))
        #expect(AppVersion("0.3.0")?.description == "0.3.0")
    }

    @Test func devBuildsAndSuffixesDoNotParse() {
        #expect(AppVersion("dev") == nil)
        #expect(AppVersion("v0.3.0-beta") == nil)
        #expect(AppVersion("") == nil)
        #expect(AppVersion("1..2") == nil)
    }

    @Test func comparesNumericallyWithMissingComponentsAsZero() throws {
        let older = try #require(AppVersion("0.9.1"))
        let tenth = try #require(AppVersion("0.10.0"))
        let oneOh = try #require(AppVersion("1.0"))
        let oneOhOh = try #require(AppVersion("1.0.0"))
        #expect(older < tenth)
        #expect(oneOh == oneOhOh)
        #expect(!(oneOh < oneOhOh) && !(oneOhOh < oneOh))
        #expect(tenth < oneOh)
    }

    @Test func signedAndNonDigitComponentsDoNotParse() {
        #expect(AppVersion("1.-2") == nil)
        #expect(AppVersion("+1.0") == nil)
        #expect(AppVersion("1. 2") == nil)
        #expect(AppVersion("v1.٢") == nil)
        #expect(AppVersion("007.1")?.components == [7, 1])
    }
}
