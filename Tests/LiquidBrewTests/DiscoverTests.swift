import XCTest
@testable import LiquidBrew

final class DiscoverTests: XCTestCase {
    func testSearchOutputSkipsHeadersAndPreservesPackageKinds() throws {
        let output = BrewCommandResult(stdout: "==> Formulae\nwget ✔\nwget2\nowner/tools/wget\nwget\n==> Casks\nfirefox\n", stderr: "", exitCode: 0)
        XCTAssertEqual(try BrewSearchOutput.names(from: output), ["wget", "wget2", "owner/tools/wget", "firefox"])
        XCTAssertTrue(try BrewSearchOutput.names(from: .init(stdout: "", stderr: "Error: No formulae or casks found for x.", exitCode: 1)).isEmpty)
        XCTAssertThrowsError(try BrewSearchOutput.names(from: .init(stdout: "", stderr: "Error: Network unavailable", exitCode: 1)))
        XCTAssertFalse(BrewSearchOutput.isPackageToken("--help"))
    }

    func testTrendingComparesNonOverlappingDailyRatesAndExcludesNoise() {
        let names = ["rising", "steady", "falling", "small", "new", "invalid"]
        let packages = Dictionary(uniqueKeysWithValues: names.map { ($0, BrewPackage(name: $0, version: "1")) })
        let recent = ["rising": 600, "steady": 600, "falling": 600, "small": 100, "new": 600, "invalid": 600]
        let old = ["rising": 1200, "steady": 1800, "falling": 3600, "small": 200, "new": 600, "invalid": 500]
        let trending = DiscoverRankings.trending(recent: recent, total90: old, packages: packages)
        XCTAssertEqual(trending.map(\.package.name), ["rising"])
        XCTAssertEqual(trending.first?.growth, 1)
    }

    func testTopChartSortsCountsAndOmitsMissingPackages() {
        let packages = Dictionary(uniqueKeysWithValues: ["alpha", "beta", "gamma"].map { ($0, BrewPackage(name: $0, version: "1")) })
        let top = DiscoverRankings.top(counts: ["alpha": 10, "beta": 30, "gamma": 10, "removed": 1000], packages: packages)
        XCTAssertEqual(top.map(\.package.name), ["beta", "alpha", "gamma"])
    }

    func testAnalyticsAggregatesOptionsAndExcludesThirdPartyTaps() throws {
        let report = try JSONDecoder().decode(BrewAnalyticsReport.self, from: Data(#"{"start_date":"2026-10-14","end_date":"2026-11-13","items":[{"formula":"wget","count":"1,200"},{"formula":"wget --HEAD","count":"50"},{"formula":"homebrew/core/curl","count":"10"},{"formula":"someone/tools/wget","count":"500"}]}"#.utf8))
        XCTAssertEqual(report.counts(catalog: .formulae), ["wget": 1250, "curl": 10])
    }

    @MainActor func testSearchErrorsAreVisibleAndClearable() async {
        let store = BrewStore(packageSearch: { _, _ in throw BrewCLIError.executionFailed("Connection failed") })
        store.discoverSearchText = "wget"
        await store.searchRemotePackages(query: "wget")
        XCTAssertEqual(store.discoverSearchError, "Connection failed")
        XCTAssertTrue(store.hasSearchedDiscover)
        XCTAssertFalse(store.isSearchingDiscover)
        store.resetDiscoverSearch()
        XCTAssertNil(store.discoverSearchError)
        XCTAssertFalse(store.hasSearchedDiscover)
    }

    @MainActor func testOlderSearchCannotOverwriteNewerResultsOrStopSpinner() async {
        let controller = SearchController()
        let store = BrewStore(packageSearch: { query, _ in try await controller.search(query) })
        store.discoverSearchText = "older"
        let first = Task { await store.searchRemotePackages(query: "older") }
        for _ in 0..<1000 where controller.pending["older"] == nil { await Task.yield() }
        XCTAssertNotNil(controller.pending["older"])
        store.discoverSearchText = "newer"
        let second = Task { await store.searchRemotePackages(query: "newer") }
        for _ in 0..<1000 where controller.pending["newer"] == nil { await Task.yield() }
        XCTAssertNotNil(controller.pending["newer"])
        controller.finish("older")
        await first.value
        XCTAssertTrue(store.isSearchingDiscover)
        XCTAssertTrue(store.discoverResults.isEmpty)
        controller.finish("newer")
        await second.value
        XCTAssertEqual(store.discoverResults.map(\.name), ["newer"])
        XCTAssertFalse(store.isSearchingDiscover)
    }

    func testLiveChartsAndSearch() async throws {
        guard ProcessInfo.processInfo.environment["LIQUIDBREW_DISCOVER_LIVE_TESTS"] == "1" else {
            throw XCTSkip("Set LIQUIDBREW_DISCOVER_LIVE_TESTS=1 for network and Homebrew checks")
        }
        let service = DiscoverChartsService()
        for catalog in DiscoverCatalog.allCases {
            let snapshot = try await service.load(catalog)
            XCTAssertFalse(snapshot.top.isEmpty, catalog.rawValue)
            XCTAssertFalse(snapshot.trending.isEmpty, catalog.rawValue)
            XCTAssertEqual(snapshot.usesDownloads, !catalog.isCask)
            XCTAssertTrue(snapshot.top.allSatisfy { $0.package.isCask == catalog.isCask })
            XCTAssertNil(snapshot.warning)
        }
        let results = try await BrewCLIService().searchPackages(query: "docker")
        XCTAssertTrue(results.contains { $0.isCask })
        XCTAssertTrue(results.contains { !$0.isCask })
        XCTAssertTrue(results.allSatisfy { BrewSearchOutput.isPackageToken($0.name) })
    }
}

@MainActor private final class SearchController {
    var pending: [String: CheckedContinuation<[BrewPackage], Error>] = [:]
    func search(_ query: String) async throws -> [BrewPackage] {
        try await withCheckedThrowingContinuation { pending[query] = $0 }
    }
    func finish(_ query: String) {
        pending.removeValue(forKey: query)?.resume(returning: [BrewPackage(name: query, version: "1")])
    }
}
