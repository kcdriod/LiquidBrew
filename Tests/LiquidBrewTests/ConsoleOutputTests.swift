import XCTest
@testable import LiquidBrew

final class ConsoleOutputTests: XCTestCase {
    func testStderrProgressIsNotAnError() {
        XCTAssertEqual(CommandLogEntry(text: "==> Downloading curl", isError: true).kind, .progress)
        XCTAssertEqual(CommandLogEntry(text: "Downloading https://example.org/archive", isError: true).kind, .progress)
        XCTAssertEqual(CommandLogEntry(text: "Additional diagnostic detail", isError: true).kind, .diagnostic)
        XCTAssertFalse(CommandLogEntry(text: "Downloading archive", isError: true).kind.isIssue)
    }

    func testFailuresWarningsAndSuccessAreDistinct() {
        XCTAssertEqual(CommandLogEntry(text: "Error: Permission denied").kind, .error)
        XCTAssertEqual(CommandLogEntry(text: "Failed to load packages", isError: true).kind, .error)
        XCTAssertEqual(CommandLogEntry(text: "✗ Exited with code 1 after 2.0s").kind, .error)
        XCTAssertEqual(CommandLogEntry(text: "Warning: package is deprecated", isError: true).kind, .warning)
        XCTAssertEqual(CommandLogEntry(text: "✓ Completed (install) in 1.0s").kind, .success)
        XCTAssertEqual(CommandLogEntry(text: "$ brew install warning", isCommandHeader: true).kind, .command)
        XCTAssertEqual(CommandLogEntry(text: "Ordinary output").kind, .output)
    }

    func testTerminalFormattingIsRemovedFromDisplayAndTranscript() {
        let colored = "\u{001B}[31mError: failure\u{001B}[0m"
        XCTAssertEqual(ConsoleOutput.clean(colored), "Error: failure")
        let link = "\u{001B}]8;;https://example.org\u{0007}Source\u{001B}]8;;\u{0007}"
        XCTAssertEqual(ConsoleOutput.clean(link), "Source")
        let stLink = "\u{001B}]8;;https://example.org\u{001B}\\Source\u{001B}]8;;\u{001B}\\"
        XCTAssertEqual(ConsoleOutput.clean(stLink), "Source")
        XCTAssertEqual(ConsoleOutput.transcript([CommandLogEntry(text: colored), CommandLogEntry(text: "Done")]), "Error: failure\nDone")
    }
}
