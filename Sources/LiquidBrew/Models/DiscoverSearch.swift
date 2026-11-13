import Foundation

enum BrewSearchOutput {
    static func names(from result: BrewCommandResult) throws -> [String] {
        if result.exitCode != 0 {
            if result.combinedOutput.contains("No formulae or casks found for") { return [] }
            throw BrewCLIError.executionFailed(result.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        var seen = Set<String>()
        return result.stdout.components(separatedBy: .newlines).filter {
            let line = $0.trimmingCharacters(in: .whitespaces)
            return !line.hasPrefix("==>") && !line.hasPrefix("Warning:") && !line.hasPrefix("Error:")
        }.flatMap { $0.split(whereSeparator: \.isWhitespace).map(String.init) }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "✔✓")) }
            .filter { isPackageToken($0) && seen.insert($0).inserted }
    }

    static func isPackageToken(_ token: String) -> Bool {
        token.range(of: #"^(?:[a-zA-Z0-9_.+-]+/)*[a-zA-Z0-9_+.-][a-zA-Z0-9_+.@-]*$"#, options: .regularExpression) != nil && !token.hasPrefix("-")
    }
}
