import XCTest
import Darwin
@testable import LiquidBrew

final class TerminalTests: XCTestCase {
    func testOptionsValidateRendererAndFrameRate() throws {
        let options = try TerminalOptions(arguments: ["--demo", "--renderer", "cpu", "--fps", "30", "--no-animation"])
        XCTAssertTrue(options.demo)
        XCTAssertEqual(options.fps, 30)
        XCTAssertEqual(options.renderer, "cpu")
        XCTAssertFalse(options.animated)
        XCTAssertThrowsError(try TerminalOptions(arguments: ["--fps", "0"]))
        XCTAssertThrowsError(try TerminalOptions(arguments: ["--fps", "61"]))
        XCTAssertThrowsError(try TerminalOptions(arguments: ["--renderer", "unknown"]))
        XCTAssertThrowsError(try TerminalOptions(arguments: ["--renderer"]))
        XCTAssertTrue(try TerminalOptions(arguments: ["--snapshot"]).demo)
    }

    func testDirectCommandsPreserveArgumentBoundaries() throws {
        let args = ["install", "--cask", "a name;$(no-execution)"]
        XCTAssertEqual(try TerminalOptions(arguments: args).brewArguments, args)
        XCTAssertThrowsError(try TerminalOptions(arguments: ["unknown-command"]))
    }

    func testFragmentedEscapeAndUnicodeInput() {
        var input = TerminalInput()
        XCTAssertEqual(input.decode([27, 91]), [])
        XCTAssertEqual(input.decode([65]), [.up])
        let unicode = Array("界".utf8)
        XCTAssertEqual(input.decode(Array(unicode.prefix(1))), [])
        XCTAssertEqual(input.decode(Array(unicode.dropFirst())), [.text("界")])
        let now = Date()
        XCTAssertEqual(input.decode([27], now: now), [])
        XCTAssertEqual(input.decode([], now: now.addingTimeInterval(0.1)), [.escape])
    }

    func testPasteNeverBecomesCommandKeys() {
        var input = TerminalInput()
        XCTAssertEqual(input.decode(Array("\u{1b}[200~qxy\n".utf8)), [])
        XCTAssertEqual(input.decode(Array("\u{1b}[201".utf8)), [])
        XCTAssertEqual(input.decode(Array("~".utf8)), [.paste("qxy")])
    }

    func testUntrustedOutputCannotInjectTerminalControls() {
        let text = "\u{1b}]52;c;secret\u{7}\u{1b}[31mhello\u{1b}[0m\r\u{202E}"
        XCTAssertEqual(TerminalText.clean(text), "hello")
        XCTAssertFalse(TerminalText.clean("\u{9b}31m").contains("\u{9b}"))
    }

    func testWideTextFitsCellBoundaries() {
        setlocale(LC_CTYPE, "en_US.UTF-8")
        XCTAssertEqual(TerminalText.width("界"), 2)
        XCTAssertEqual(TerminalText.width("👩‍💻"), 2)
        XCTAssertEqual(TerminalText.clipped("a界b", to: 3), "a界")
        XCTAssertEqual(TerminalText.wrapped("a界b", width: 3), ["a界", "b"])
        var frame = TerminalFrame(width: 4, height: 1)
        frame.text("a界b", x: 0, y: 0)
        XCTAssertTrue(frame.cells[2].continuation)
        XCTAssertEqual(frame.plainText, "a界b")
    }

    @MainActor func testEveryDemoScreenFitsSmallAndLargeTerminals() throws {
        let options = try TerminalOptions(arguments: ["--demo", "--renderer", "cpu"])
        let app = TerminalApp(options: options, animation: try TerminalAnimation(mode: "cpu"))
        app.loadDemo()
        for tab in NavigationTab.allCases {
            app.tab = tab
            for width in [40, 80, 104, 160] {
                for height in [12, 24, 40] {
                    for console in [false, true] {
                        app.showConsole = console
                        let frame = app.screen(width: width, height: height, time: 1)
                        XCTAssertEqual(frame.cells.count, width * height)
                        XCTAssertFalse(frame.plainText.contains("\u{1b}"))
                    }
                }
            }
        }
    }

    @MainActor func testDemoCannotConfirmMutationOrRunPastedKeys() throws {
        let app = TerminalApp(options: try TerminalOptions(arguments: ["--demo"]), animation: try TerminalAnimation(mode: "cpu"))
        app.loadDemo()
        var ran = false
        app.confirm("Remove package") { ran = true }
        XCTAssertNil(app.confirmation)
        XCTAssertFalse(ran)
        app.handle(.paste("qxy"))
        XCTAssertFalse(app.quitting)
        app.busy = "Installing"
        app.handle(.text("q"))
        XCTAssertFalse(app.quitting)
    }

    @MainActor func testConfirmationNeedsExplicitYesAndCanBeCancelled() throws {
        let app = TerminalApp(options: try TerminalOptions(arguments: []), animation: try TerminalAnimation(mode: "cpu"))
        app.confirm("Remove sample") {}
        XCTAssertNotNil(app.confirmation)
        app.handle(.enter)
        XCTAssertNotNil(app.confirmation)
        app.handle(.text("n"))
        XCTAssertNil(app.confirmation)
        XCTAssertNil(app.busy)
    }

    @MainActor func testSecurityRowUsesMatchingPackage() throws {
        let app = TerminalApp(options: try TerminalOptions(arguments: ["--demo"]), animation: try TerminalAnimation(mode: "cpu"))
        app.loadDemo()
        app.tab = .security
        app.store.securityFindings = [SecurityFinding(sourceID: "test", packageID: "formula:git", title: "Review", detail: "Review source", url: URL(string: "https://example.com")!, reportedAt: nil, isMalwareWarning: false)]
        XCTAssertEqual(app.current?.package?.name, "git")
    }

    func testCpuAnimationChangesOverTime() throws {
        let renderer = try TerminalAnimation(mode: "cpu")
        let first = try renderer.colors(width: 20, height: 6, time: 0)
        let second = try renderer.colors(width: 20, height: 6, time: 1)
        XCTAssertEqual(first.count, 120)
        XCTAssertNotEqual(first, second)
    }

    @MainActor func testAsciiArtAnimatesAndReturnsToWorkspace() throws {
        XCTAssertNotEqual(TerminalArt.mug(time: 0), TerminalArt.mug(time: 1))
        XCTAssertTrue(TerminalArt.splash(time: 0).joined().unicodeScalars.allSatisfy { $0.isASCII })
        let app = TerminalApp(options: try TerminalOptions(arguments: ["--demo"]), animation: try TerminalAnimation(mode: "cpu"))
        app.loadDemo()
        app.handle(.text("A"))
        XCTAssertTrue(app.showArt)
        let screen = app.screen(width: 80, height: 24, time: 0)
        XCTAssertTrue(screen.plainText.contains("~ BREW ~"))
        app.handle(.text(" "))
        XCTAssertFalse(app.animated)
        XCTAssertTrue(app.showArt)
        app.handle(.text("A"))
        XCTAssertFalse(app.showArt)
    }

    func testFillsOutsideTerminalAreClipped() {
        var frame = TerminalFrame(width: 4, height: 2)
        frame.fill(x: 9, y: 7, width: 5, height: 5, background: .cyan)
        XCTAssertTrue(frame.cells.allSatisfy { $0.background == .background })
        frame.fill(x: -3, y: -3, width: 4, height: 4, background: .cyan)
        XCTAssertEqual(frame.cells.filter { $0.background == .cyan }.count, 1)
    }

    @MainActor func testCompactConsoleUsesWorkspaceWithoutOverlappingList() throws {
        let app = TerminalApp(options: try TerminalOptions(arguments: ["--demo"]), animation: try TerminalAnimation(mode: "cpu"))
        app.loadDemo()
        app.showConsole = true
        let frame = app.screen(width: 80, height: 24, time: 0)
        XCTAssertTrue(frame.plainText.contains("Console"))
        XCTAssertFalse(frame.plainText.contains("ffmpeg"))
    }
}
