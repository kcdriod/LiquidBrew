import Foundation

// stderr also carries Homebrew download/progress messages, so classify the text first.
enum ConsoleLineKind {
    case command, output, progress, success, warning, error, diagnostic

    var isIssue: Bool { self == .warning || self == .error }
}

extension CommandLogEntry {
    var cleanText: String { ConsoleOutput.clean(text) }

    var kind: ConsoleLineKind {
        if isCommandHeader { return .command }
        let text = cleanText.trimmingCharacters(in: .whitespaces)
        if text.range(of: #"^(error:|fatal:|✗|failed\b)|\b(failed to|could not|couldn't|failure:|exited with code [1-9])"#, options: [.regularExpression, .caseInsensitive]) != nil { return .error }
        if text.range(of: #"^(warning:|warn:)|\bdeprecated\b"#, options: [.regularExpression, .caseInsensitive]) != nil { return .warning }
        if text.hasPrefix("✓") || text.hasPrefix("🍺") || text.hasPrefix("Your system is ready to brew") { return .success }
        if text.range(of: #"^(==>|Downloading|Fetching|Pouring|Installing|Upgrading|Already downloaded:|\s*#+.*%)"#, options: [.regularExpression, .caseInsensitive]) != nil { return .progress }
        return isError ? .diagnostic : .output
    }
}

enum ConsoleOutput {
    static func clean(_ text: String) -> String {
        // Strip OSC hyperlinks and CSI color/cursor codes, retaining their readable contents.
        let withoutOSC = text.replacingOccurrences(of: "\u{001B}\\][^\u{0007}\u{001B}]*(?:\u{0007}|\u{001B}\\\\)", with: "", options: .regularExpression)
        let withoutCSI = withoutOSC.replacingOccurrences(of: "\u{001B}\\[[0-?]*[ -/]*[@-~]", with: "", options: .regularExpression)
        return String(String.UnicodeScalarView(withoutCSI.unicodeScalars.filter { $0.value >= 32 || $0 == "\t" || $0 == "\n" }))
    }

    static func transcript(_ entries: [CommandLogEntry], timestamps: Bool = false) -> String {
        entries.map { entry in
            let prefix = timestamps ? "[\(entry.timestamp.formatted(date: .omitted, time: .standard))] " : ""
            return prefix + entry.cleanText
        }.joined(separator: "\n")
    }
}
