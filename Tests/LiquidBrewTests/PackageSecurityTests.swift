import XCTest
@testable import LiquidBrew

final class PackageSecurityTests: XCTestCase {
    func testLiveSources() async throws {
        guard ProcessInfo.processInfo.environment["LIQUIDBREW_SECURITY_LIVE_TESTS"] == "1" else {
            throw XCTSkip("Set LIQUIDBREW_SECURITY_LIVE_TESTS=1 to verify public sources")
        }
        let results = await PackageSecurityService().scan(packages: [BrewPackage(name: "curl", version: "1")])
        XCTAssertEqual(results.count, 4)
        for result in results {
            XCTAssertNil(result.status.error, "\(result.status.name): \(result.status.error ?? "")")
            XCTAssertNotNil(result.status.checkedAt)
        }
        for source in PackageSecurityService.sources where !source.metadata {
            let (data, _) = try await URLSession.shared.data(from: URL(string: source.url)!)
            let articles = try SecurityFeedParser.parse(data)
            XCTAssertFalse(articles.isEmpty, source.name)
            XCTAssertTrue(articles.contains { $0.date != nil }, source.name)
        }
    }

    func testHeadlineMatchingRequiresPackageBoundary() {
        let package = BrewPackage(name: "curl", version: "1")
        XCTAssertTrue(SecurityMatcher.matches(package, headline: "Malicious curl update discovered"))
        XCTAssertFalse(SecurityMatcher.matches(package, headline: "Malicious curly package"))
        XCTAssertFalse(SecurityMatcher.matches(package, headline: "Malicious libcurl package"))
        XCTAssertFalse(SecurityMatcher.matches(package, headline: "Malicious curl-helper package"))
        XCTAssertFalse(SecurityMatcher.matches(BrewPackage(name: "go", version: "1"), headline: "Go malware"))
        XCTAssertTrue(SecurityMatcher.matches(BrewPackage(name: "openssl@3", version: "3"), headline: "OpenSSL vulnerability"))
    }

    func testNewsRequiresRecentDatedSecurityHeadline() {
        let now = Date()
        let package = BrewPackage(name: "wget", version: "1")
        let url = URL(string: "https://example.org/report")!
        let articles = [
            SecurityArticle(title: "Wget malware discovered", url: url, date: now),
            SecurityArticle(title: "Wget new release", url: url, date: now),
            SecurityArticle(title: "Wget security issue", url: url, date: now.addingTimeInterval(-100 * 86400)),
            SecurityArticle(title: "Wget security issue", url: url, date: nil)
        ]
        let findings = SecurityMatcher.newsFindings(packages: [package], articles: articles, sourceID: "test", now: now)
        XCTAssertEqual(findings.count, 1)
        XCTAssertFalse(findings[0].isMalwareWarning)
    }

    func testMetadataDoesNotFlagOrdinaryDeprecationsOrOtherTaps() throws {
        let data = Data(#"{"name":"wget","disabled":true,"disable_reason":"malware"}"#.utf8)
        let record = try JSONDecoder().decode(HomebrewSecurityMetadata.self, from: data)
        XCTAssertTrue(try XCTUnwrap(record.finding(for: BrewPackage(name: "wget", version: "1"), sourceID: "formula")).isMalwareWarning)
        XCTAssertNil(record.finding(for: BrewPackage(name: "wget", version: "1", tap: "someone/tools"), sourceID: "formula"))
        let ordinary = try JSONDecoder().decode(HomebrewSecurityMetadata.self, from: Data(#"{"name":"wget","disabled":true,"disable_reason":"unmaintained"}"#.utf8))
        XCTAssertNil(ordinary.finding(for: BrewPackage(name: "wget", version: "1"), sourceID: "formula"))
        let cask = try JSONDecoder().decode(HomebrewSecurityMetadata.self, from: Data(#"{"token":"wget","name":["Wget App"],"disabled":true,"disable_reason":"malware"}"#.utf8))
        XCTAssertNil(cask.finding(for: BrewPackage(name: "wget", version: "1"), sourceID: "cask"))
    }

    func testRSSAndAtomParsingAndUnsafeLinks() throws {
        let rss = Data("""
        <rss><channel><item><title><![CDATA[Wget malware & attack]]></title><link>https://example.org/report</link><pubDate>Thu, 12 Nov 2026 10:00:00 +0000</pubDate></item><item><title>Unsafe</title><link>file:///tmp/test</link></item></channel></rss>
        """.utf8)
        let articles = try SecurityFeedParser.parse(rss)
        XCTAssertEqual(articles.count, 1)
        XCTAssertEqual(articles.first?.title, "Wget malware & attack")
        XCTAssertNotNil(articles.first?.date)
        let atom = Data("""
        <feed xmlns="http://www.w3.org/2005/Atom"><entry><title>Security report</title><link rel="alternate" href="https://brew.sh/report"/><updated>2026-11-12T10:00:00Z</updated></entry></feed>
        """.utf8)
        let atomArticles = try SecurityFeedParser.parse(atom)
        XCTAssertEqual(atomArticles.first?.url.absoluteString, "https://brew.sh/report")
        XCTAssertNotNil(atomArticles.first?.date)
        XCTAssertThrowsError(try SecurityFeedParser.parse(Data("<html/>".utf8)))
        XCTAssertThrowsError(try SecurityFeedParser.parse(Data("<rss><broken>".utf8)))
    }
}
