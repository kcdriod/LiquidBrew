import Foundation

struct SecurityFinding: Codable, Identifiable, Hashable {
    var id: String { "\(sourceID)|\(packageID)|\(url.absoluteString)" }
    let sourceID: String
    let packageID: String
    let title: String
    let detail: String
    let url: URL
    let reportedAt: Date?
    let isMalwareWarning: Bool
}

struct SecuritySourceStatus: Codable, Identifiable {
    let id: String
    let name: String
    var checkedAt: Date?
    var error: String?
}

struct SecurityScanResult {
    let status: SecuritySourceStatus
    let findings: [SecurityFinding]
}

struct SecurityArticle {
    let title: String
    let url: URL
    let date: Date?
}

// Headlines are leads for human review, never evidence that an installed version is affected.
enum SecurityMatcher {
    static func matches(_ package: BrewPackage, headline: String) -> Bool {
        let name = package.name.components(separatedBy: "@")[0].lowercased()
        // Short/common package names generate too many unrelated news matches.
        let ambiguous: Set<String> = ["go", "ruby", "swift", "screen", "watch", "tree", "file", "find", "time", "expect", "help", "coreutils"]
        guard name.count >= 4, !ambiguous.contains(name) else { return false }
        let escaped = NSRegularExpression.escapedPattern(for: name)
        return headline.range(of: "(?<![a-z0-9_-])\(escaped)(?![a-z0-9_-])", options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func isSecurityHeadline(_ title: String) -> Bool {
        title.range(of: "malware|malicious|backdoor|compromis|supply.chain|trojan|hijack|security|vulnerab|CVE-[0-9]", options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func newsFindings(packages: [BrewPackage], articles: [SecurityArticle], sourceID: String, now: Date = Date()) -> [SecurityFinding] {
        articles.filter {
            guard let date = $0.date else { return false }
            return date <= now.addingTimeInterval(86400) && date >= now.addingTimeInterval(-90 * 86400) && isSecurityHeadline($0.title)
        }.flatMap { article in
            packages.filter { matches($0, headline: article.title) }.map {
                SecurityFinding(sourceID: sourceID, packageID: $0.id, title: article.title,
                    detail: "Package name mentioned in a recent security headline. Verify the product, ecosystem and affected versions in the report before removing anything.",
                    url: article.url, reportedAt: article.date, isMalwareWarning: false)
            }
        }
    }
}

struct HomebrewSecurityMetadata: Decodable {
    let name: String?
    let token: String?
    let disabled: Bool?
    let disable_reason: String?
    let deprecated: Bool?
    let deprecation_reason: String?

    private enum CodingKeys: String, CodingKey {
        case name, token, disabled, disable_reason, deprecated, deprecation_reason
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        token = try values.decodeIfPresent(String.self, forKey: .token)
        // A formula has a string name; a cask has a token and an array of display names.
        name = token == nil ? try values.decodeIfPresent(String.self, forKey: .name) : nil
        disabled = try values.decodeIfPresent(Bool.self, forKey: .disabled)
        disable_reason = try values.decodeIfPresent(String.self, forKey: .disable_reason)
        deprecated = try values.decodeIfPresent(Bool.self, forKey: .deprecated)
        deprecation_reason = try values.decodeIfPresent(String.self, forKey: .deprecation_reason)
    }

    func finding(for package: BrewPackage, sourceID: String) -> SecurityFinding? {
        guard (package.isCask ? token : name) == package.name,
              package.tap == (package.isCask ? "homebrew/cask" : "homebrew/core") else { return nil }
        let reason = disabled == true ? disable_reason : (deprecated == true ? deprecation_reason : nil)
        guard let reason, reason.range(of: "malware|malicious|backdoor|compromis|security|vulnerab", options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
        let malware = reason.range(of: "malware|malicious|backdoor", options: [.regularExpression, .caseInsensitive]) != nil
        return SecurityFinding(sourceID: sourceID, packageID: package.id,
            title: "Homebrew \(disabled == true ? "disabled" : "deprecated") \(package.name)", detail: reason,
            url: URL(string: "https://formulae.brew.sh/\(package.isCask ? "cask" : "formula")/\(package.name)")!,
            reportedAt: nil, isMalwareWarning: malware)
    }
}

actor PackageSecurityService {
    static let sources: [(id: String, name: String, url: String, metadata: Bool)] = [
        ("formula", "Homebrew formula warnings", "https://formulae.brew.sh/api/formula.json", true),
        ("cask", "Homebrew cask warnings", "https://formulae.brew.sh/api/cask.json", true),
        ("brew-news", "Homebrew news", "https://brew.sh/atom.xml", false),
        ("hacker-news", "The Hacker News", "https://feeds.feedburner.com/TheHackersNews", false)
    ]

    func scan(packages: [BrewPackage]) async -> [SecurityScanResult] {
        await withTaskGroup(of: SecurityScanResult.self) { group in
            for source in Self.sources {
                group.addTask {
                    do {
                        var request = URLRequest(url: URL(string: source.url)!)
                        request.timeoutInterval = 30
                        let (data, response) = try await URLSession.shared.data(for: request)
                        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                            throw URLError(.badServerResponse)
                        }
                        let findings: [SecurityFinding]
                        if source.metadata {
                            let records = try JSONDecoder().decode([HomebrewSecurityMetadata].self, from: data)
                            let index = Dictionary(records.map { (($0.token ?? $0.name ?? ""), $0) }, uniquingKeysWith: { first, _ in first })
                            findings = packages.filter { $0.isCask == (source.id == "cask") }.compactMap { index[$0.name]?.finding(for: $0, sourceID: source.id) }
                        } else {
                            let articles = try SecurityFeedParser.parse(data)
                            findings = SecurityMatcher.newsFindings(packages: packages, articles: articles, sourceID: source.id)
                        }
                        return SecurityScanResult(status: .init(id: source.id, name: source.name, checkedAt: Date()), findings: Array(Dictionary(findings.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values))
                    } catch {
                        return SecurityScanResult(status: .init(id: source.id, name: source.name, error: error.localizedDescription), findings: [])
                    }
                }
            }
            var results: [SecurityScanResult] = []
            for await result in group { results.append(result) }
            return results
        }
    }
}

// Handles RSS and Atom; external entities are never resolved.
final class SecurityFeedParser: NSObject, XMLParserDelegate {
    private var articles: [SecurityArticle] = []
    private var fields: [String: String] = [:]
    private var field = ""
    private var inEntry = false
    private var recognizedFeed = false

    static func parse(_ data: Data) throws -> [SecurityArticle] {
        let delegate = SecurityFeedParser()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), delegate.recognizedFeed else { throw URLError(.cannotParseResponse) }
        return delegate.articles
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if name == "rss" || name == "feed" { recognizedFeed = true }
        if name == "item" || name == "entry" { inEntry = true; fields = [:] }
        guard inEntry else { return }
        field = name
        if name == "link", let href = attributes["href"], attributes["rel"] == nil || attributes["rel"] == "alternate" { fields["link"] = href }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inEntry { fields[field, default: ""] += string }
    }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let text = String(data: CDATABlock, encoding: .utf8) { self.parser(parser, foundCharacters: text) }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard name == "item" || name == "entry" else { return }
        defer { inEntry = false }
        let title = (fields["title"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let url = URL(string: (fields["link"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme == "https", url.host != nil else { return }
        let raw = (fields["pubDate"] ?? fields["published"] ?? fields["updated"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        let iso = ISO8601DateFormatter()
        let date = formatter.date(from: raw) ?? iso.date(from: raw)
        articles.append(.init(title: title, url: url, date: date))
    }
}
