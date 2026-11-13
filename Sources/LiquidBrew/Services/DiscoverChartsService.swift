import Foundation

enum DiscoverCatalog: String, CaseIterable, Identifiable, Codable, Sendable {
    case formulae = "Formulae"
    case casks = "Apps (Casks)"
    var id: String { rawValue }
    var isCask: Bool { self == .casks }
    var analyticsCategory: String { isCask ? "cask-install" : "install-on-request" }
}

enum DiscoverChartMode: String, CaseIterable, Identifiable {
    case top = "Top Charts"
    case trending = "Trending"
    var id: String { rawValue }
}

struct DiscoverChartEntry: Identifiable, Codable, Sendable {
    var id: String { package.id }
    let package: BrewPackage
    let count: Int
    let growth: Double?
}

struct DiscoverChartSnapshot: Codable, Sendable {
    let top: [DiscoverChartEntry]
    let trending: [DiscoverChartEntry]
    let usesDownloads: Bool
    let downloadCoverage: Int?
    let topPeriod: String
    let trendPeriod: String
    let fetchedAt: Date
    let warning: String?
}

struct BrewAnalyticsReport: Decodable {
    struct Item: Decodable {
        let formula: String?
        let cask: String?
        let count: String
    }
    let start_date: String
    let end_date: String
    let items: [Item]

    func counts(catalog: DiscoverCatalog) -> [String: Int] {
        var counts: [String: Int] = [:]
        let officialPrefix = catalog.isCask ? "homebrew/cask/" : "homebrew/core/"
        for item in items {
            guard let raw = catalog.isCask ? item.cask : item.formula,
                  var token = raw.split(separator: " ").first.map(String.init),
                  let count = Int(item.count.replacingOccurrences(of: ",", with: "")), count >= 0 else { continue }
            if token.hasPrefix(officialPrefix) { token = String(token.dropFirst(officialPrefix.count)) }
            guard !token.contains("/"), BrewSearchOutput.isPackageToken(token) else { continue }
            counts[token, default: 0] += count
        }
        return counts
    }
}

struct BrewDownloadReport: Decodable {
    struct Item: Decodable {
        let last_30_days: Int?
        let start_date: String?
        let end_date: String?
    }
    let selected_formulae: Int
    let formulae: [String: Item]
}

enum DiscoverRankings {
    static func top(counts: [String: Int], packages: [String: BrewPackage]) -> [DiscoverChartEntry] {
        counts.compactMap { name, count in
            packages[name].map { DiscoverChartEntry(package: $0, count: count, growth: nil) }
        }.sorted { $0.count == $1.count ? $0.package.name < $1.package.name : $0.count > $1.count }
    }

    // The 90-day window includes the recent 30 days. Subtract it to compare
    // two non-overlapping daily rates, rather than comparing overlapping totals.
    static func trending(recent: [String: Int], total90: [String: Int], packages: [String: BrewPackage]) -> [DiscoverChartEntry] {
        recent.compactMap { name, count in
            guard count >= 500, let total = total90[name], let package = packages[name] else { return nil }
            let previous60 = total - count
            guard previous60 >= 100 else { return nil }
            let growth = (Double(count) / 30) / (Double(previous60) / 60) - 1
            guard growth >= 0.1 else { return nil }
            return DiscoverChartEntry(package: package, count: count, growth: growth)
        }.sorted {
            if $0.growth == $1.growth { return $0.count == $1.count ? $0.package.name < $1.package.name : $0.count > $1.count }
            return ($0.growth ?? 0) > ($1.growth ?? 0)
        }
    }
}

private struct DiscoverCatalogRecord: Decodable {
    let package: BrewPackage
    let disabled: Bool
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: Keys.self)
        let token = try values.decodeIfPresent(String.self, forKey: .token)
        let isCask = token != nil
        let name = try token ?? values.decode(String.self, forKey: .name)
        let versions = try values.decodeIfPresent(Versions.self, forKey: .versions)
        let version = try values.decodeIfPresent(String.self, forKey: .version) ?? versions?.stable
        package = BrewPackage(name: name, desc: try values.decodeIfPresent(String.self, forKey: .desc),
            homepage: try values.decodeIfPresent(String.self, forKey: .homepage), version: version ?? "latest", isCask: isCask,
            tap: isCask ? "homebrew/cask" : "homebrew/core")
        disabled = try values.decodeIfPresent(Bool.self, forKey: .disabled) ?? false
    }
    private struct Versions: Decodable { let stable: String? }
    private enum Keys: String, CodingKey { case token, name, desc, homepage, version, versions, disabled }
}

actor DiscoverChartsService {
    private var cache: [DiscoverCatalog: DiscoverChartSnapshot] = [:]

    func load(_ catalog: DiscoverCatalog, force: Bool = false) async throws -> DiscoverChartSnapshot {
        if !force, let cached = cache[catalog], Date().timeIntervalSince(cached.fetchedAt) < 3600 { return cached }
        let category = catalog.analyticsCategory
        async let recentData = fetch("analytics/\(category)/30d.json")
        async let olderData = fetch("analytics/\(category)/90d.json")
        async let metadata = fetch(catalog.isCask ? "cask.json" : "formula.json")
        async let downloadsData: Data? = catalog.isCask ? nil : try? fetch("analytics/github-packages/30d.json")
        let decoder = JSONDecoder()
        let recent = try decoder.decode(BrewAnalyticsReport.self, from: await recentData)
        let older = try decoder.decode(BrewAnalyticsReport.self, from: await olderData)
        let records = try decoder.decode([DiscoverCatalogRecord].self, from: await metadata)
        let packages = Dictionary(records.filter { !$0.disabled }.map { ($0.package.name, $0.package) }, uniquingKeysWith: { first, _ in first })
        let recentCounts = recent.counts(catalog: catalog)
        var counts = recentCounts
        var usesDownloads = false
        var coverage: Int?
        var period = "\(recent.start_date) – \(recent.end_date)"
        var warnings: [String] = []
        if !catalog.isCask {
            if let data = await downloadsData, let downloads = try? decoder.decode(BrewDownloadReport.self, from: data) {
                let available = downloads.formulae.compactMapValues { $0.last_30_days }
                if !available.isEmpty {
                    usesDownloads = true
                    counts = available
                    coverage = downloads.selected_formulae
                    if let dates = downloads.formulae.values.first(where: { $0.last_30_days != nil }), let start = dates.start_date, let end = dates.end_date { period = "\(start) – \(end)" }
                }
            }
            if !usesDownloads { warnings.append("Download counts are unavailable. Top Charts is showing reported installs instead.") }
        }
        let aligned = recent.end_date == older.end_date
        if !aligned { warnings.append("Trending is unavailable because the source reporting windows do not align.") }
        let snapshot = DiscoverChartSnapshot(
            top: Array(DiscoverRankings.top(counts: counts, packages: packages).prefix(50)),
            trending: aligned ? Array(DiscoverRankings.trending(recent: recentCounts, total90: older.counts(catalog: catalog), packages: packages).prefix(50)) : [],
            usesDownloads: usesDownloads, downloadCoverage: coverage, topPeriod: period,
            trendPeriod: "\(recent.start_date) – \(recent.end_date)", fetchedAt: Date(),
            warning: warnings.isEmpty ? nil : warnings.joined(separator: " ")
        )
        cache[catalog] = snapshot
        return snapshot
    }

    private func fetch(_ path: String) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://formulae.brew.sh/api/\(path)")!)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }
}
