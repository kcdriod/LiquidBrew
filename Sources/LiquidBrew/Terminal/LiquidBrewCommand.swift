import Foundation
import Darwin

@main
enum LiquidBrewCommand {
    @MainActor static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent
        guard executable == "liquidbrew" || arguments.first == "--tui" else {
            LiquidBrewApp.main()
            return
        }
        do {
            setlocale(LC_CTYPE, "")
            let options = try TerminalOptions(arguments: arguments)
            if options.help {
                print(TerminalOptions.helpText)
                return
            }
            if let command = options.brewArguments {
                // Replace this process so Homebrew retains stdin, signals, and its exit code.
                let values = ["env", "brew"] + command
                let pointers = values.map { strdup($0) } + [nil]
                defer { pointers.forEach { free($0) } }
                execv("/usr/bin/env", pointers)
                throw BrewCLIError.executionFailed("Could not start Homebrew: \(String(cString: strerror(errno)))")
            }
            let renderer = try TerminalAnimation(mode: options.renderer)
            if options.gpuInfo {
                print(renderer.description)
                _ = try renderer.colors(width: 32, height: 8, time: 0)
                print("Animation frame verified. Glyph rendering is provided by your terminal.")
                return
            }
            let app = TerminalApp(options: options, animation: renderer)
            if options.snapshot {
                app.loadDemo()
                print(app.screen(width: 110, height: 34, time: 1).plainText)
                return
            }
            try await app.run()
        } catch {
            FileHandle.standardError.write(Data("liquidbrew: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}

struct TerminalOptions {
    var demo = false
    var snapshot = false
    var help = false
    var gpuInfo = false
    var animated = true
    var fps = 24
    var renderer = "auto"
    var brewArguments: [String]?

    init(arguments: [String]) throws {
        let verbs: Set<String> = ["list", "info", "search", "install", "uninstall", "upgrade", "update", "outdated", "services", "tap", "untap", "pin", "unpin", "cleanup", "autoremove", "bundle", "doctor", "deps"]
        if let first = arguments.first, verbs.contains(first) {
            brewArguments = arguments
            return
        }
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--tui": break
            case "--help", "-h": help = true
            case "--demo": demo = true
            case "--snapshot": snapshot = true
            case "--gpu-info": gpuInfo = true
            case "--no-animation": animated = false
            case "--renderer", "--fps":
                let flag = arguments[index]
                index += 1
                guard index < arguments.count else { throw Self.invalid("Missing value for \(flag)") }
                if flag == "--renderer" {
                    guard ["auto", "gpu", "cpu"].contains(arguments[index]) else { throw Self.invalid("Renderer must be auto, gpu, or cpu") }
                    renderer = arguments[index]
                } else {
                    guard let value = Int(arguments[index]), (1...60).contains(value) else { throw Self.invalid("FPS must be between 1 and 60") }
                    fps = value
                }
            default: throw Self.invalid("Unknown option '\(arguments[index])'. Use liquidbrew --help")
            }
            index += 1
        }
        if snapshot { demo = true }
    }

    static func invalid(_ message: String) -> Error { BrewCLIError.executionFailed(message) }

    static let helpText = """
    LiquidBrew — animated Homebrew terminal workspace

      liquidbrew                         Open the live terminal app
      liquidbrew --demo                   Explore sample data without running Homebrew
      liquidbrew --renderer gpu           Require Metal animation rendering
      liquidbrew --renderer cpu           Use CPU animation rendering
      liquidbrew --fps 30                 Animation rate (1–60, default 24)
      liquidbrew --no-animation           Start with motion paused
      liquidbrew --gpu-info               Verify and identify the animation renderer
      liquidbrew --snapshot               Print a sample screen without terminal controls
      liquidbrew <brew command> [args]    Run Homebrew directly, preserving its exit code

    Commands: list, info, search, install, uninstall, upgrade, update, outdated,
              services, tap, untap, pin, unpin, cleanup, autoremove, bundle, doctor, deps

    Keys: 1–8 screens · arrows/j/k move · / search · Enter details/search · Esc back
          r refresh · l console · A ASCII art · Space pause motion · ? help · q quit
    Package and maintenance actions show an explicit confirmation before running.
    Graph: t radial/tree · n network · +/- zoom · arrows pan · 0 reset
           [ / ] or Tab select nodes · i inspector · Enter focus · e Packages
    Metal computes the animated color field. Your terminal renders the text.
    Ghostty uses Metal for terminal rendering on macOS. Minimum size 80 × 24.
    """
}
