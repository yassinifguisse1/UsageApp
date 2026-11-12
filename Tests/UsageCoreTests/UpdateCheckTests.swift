import Foundation
import Testing
import UsageCore

private func release(_ tag: String, url: String = "https://github.com/yassinifguisse1/UsageApp/releases/tag/v1.2.0", draft: Bool = false, prerelease: Bool = false) -> Data {
    Data(#"{"tag_name":"\#(tag)","html_url":"\#(url)","draft":\#(draft),"prerelease":\#(prerelease)}"#.utf8)
}

@Test func releaseVersionsParseAndCompareNumerically() throws {
    #expect(ReleaseVersion("v1.10.0")! > ReleaseVersion("1.9.9")!)
    #expect(ReleaseVersion("1.2.3")?.description == "1.2.3")
    for invalid in ["1.2", "v1.2.3-beta", "1.2.3.4", "one.2.3", "", "1..3"] {
        #expect(ReleaseVersion(invalid) == nil)
    }
}

@Test func onlyANewerPublishedReleaseOfThisProjectIsOffered() throws {
    let offered = try #require(UpdateCheck.newerRelease(in: release("v1.2.0"), than: "1.1.0"))
    #expect(offered.version.description == "1.2.0")
    #expect(offered.url.absoluteString.hasSuffix("/releases/tag/v1.2.0"))

    #expect(UpdateCheck.newerRelease(in: release("v1.1.0"), than: "1.1.0") == nil)
    #expect(UpdateCheck.newerRelease(in: release("v1.0.9"), than: "1.1.0") == nil)
    #expect(UpdateCheck.newerRelease(in: release("v1.2.0", draft: true), than: "1.1.0") == nil)
    #expect(UpdateCheck.newerRelease(in: release("v1.2.0", prerelease: true), than: "1.1.0") == nil)
    #expect(UpdateCheck.newerRelease(in: release("v1.2.0", url: "https://example.com/releases/x"), than: "1.1.0") == nil)
    #expect(UpdateCheck.newerRelease(in: release("v1.2.0", url: "https://github.com/someone/else/releases/x"), than: "1.1.0") == nil)
    #expect(UpdateCheck.newerRelease(in: Data("{".utf8), than: "1.1.0") == nil)
}
