import Foundation
import Darwin

struct TerminalRow {
    let title: String
    var subtitle = ""
    var badge = ""
    var package: BrewPackage?
}

struct TerminalPrompt {
    enum Purpose { case search, tap, export, importBundle, logs }
    let purpose: Purpose
    let title: String
    var value = ""
}

struct TerminalConfirmation {
    let title: String
    let operation: @MainActor () async -> Void
}

@MainActor
final class TerminalApp {
    let options: TerminalOptions
    let animation: TerminalAnimation
    let store = BrewStore(notificationsAvailable: false)
    var tab = NavigationTab.packages
    var selected = 0
    var detailOffset = 0
    var detailExpanded = false
    var showConsole = false
    var showHelp = false
    var showArt = false
    var graph = TerminalGraphState()
    var showBrewfile = false
    var logOffset = 0
    var prompt: TerminalPrompt?
    var confirmation: TerminalConfirmation?
    var message = "Ready · / to search · ? for keys"
    var busy: String?
    var animated: Bool
    var catalog = DiscoverCatalog.formulae
    var chartMode = DiscoverChartMode.top
    var quitting = false
    private var quitWhenIdle = false
    var signalSources: [DispatchSourceSignal] = []
    private var animationColors: [TerminalRGB] = []
    private var animationSize = (0, 0)
    private var lastAnimationTime: Float = -1

    init(options: TerminalOptions, animation: TerminalAnimation) {
        self.options = options
        self.animation = animation
        animated = options.animated
    }

    var rows: [TerminalRow] {
        switch tab {
        case .packages:
            return store.filteredPackages.map {
                TerminalRow(title: $0.name, subtitle: $0.version, badge: $0.isPinned ? "PIN" : ($0.isOutdated ? "UPDATE" : ($0.isCask ? "APP" : "BREW")), package: $0)
            }
        case .graph:
            return store.installedPackages.filter {
                !$0.isCask && (!graph.leavesOnly || $0.isLeaf) && matches($0.name + " " + ($0.desc ?? ""))
            }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }.map {
                TerminalRow(title: $0.name, subtitle: "\(Set($0.dependencies + $0.runtimeDependencies).count) dependencies", badge: $0.isLeaf ? "LEAF" : "BREW", package: $0)
            }
        case .discover:
            return discoverPackages.map { package in
                let installed = store.installedPackages.contains { $0.id == package.id }
                return TerminalRow(title: package.name, subtitle: package.desc ?? package.version, badge: installed ? "INSTALLED" : (package.isCask ? "APP" : "BREW"), package: package)
            }
        case .updates:
            return store.outdatedPackages.filter { matches($0.name) }.map { item in
                TerminalRow(title: item.name, subtitle: "\(item.installedVersions.joined(separator: ", ")) → \(item.currentVersion)", badge: item.isPinned ? "PIN" : "UPDATE", package: store.installedPackages.first { $0.name == item.name && $0.isCask == item.isCask })
            }
        case .services:
            return store.services.filter { matches($0.name) }.map { TerminalRow(title: $0.name, subtitle: $0.user ?? "No service user", badge: $0.status.displayTitle.uppercased()) }
        case .taps:
            return store.taps.filter { matches($0.name) }.map { TerminalRow(title: $0.name, subtitle: "\($0.formulaCount) formulae · \($0.caskCount) casks", badge: $0.official ? "OFFICIAL" : "TAP") }
        case .health:
            let report = store.healthReport
            return [TerminalRow(title: "Diagnostics", subtitle: report.isHealthy ? "No warnings in last report" : "\(report.warnings.count) warnings", badge: report.isHealthy ? "OK" : "REVIEW"),
                    TerminalRow(title: "Cache & old versions", subtitle: report.formattedCacheSize, badge: "DISK"),
                    TerminalRow(title: "Unused dependencies", subtitle: "\(report.autoremoveCandidates.count) candidates", badge: "CLEAN")]
        case .security:
            return store.installedSecurityFindings.filter { matches($0.title + " " + $0.packageID) }.map { finding in
                TerminalRow(title: finding.packageID, subtitle: finding.title, badge: "REVIEW", package: store.installedPackages.first { $0.id == finding.packageID })
            }
        }
    }

    var discoverPackages: [BrewPackage] {
        if store.hasSearchedDiscover { return store.discoverResults.filter { $0.isCask == catalog.isCask } }
        guard let charts = store.discoverCharts[catalog] else { return [] }
        return (chartMode == .top ? charts.top : charts.trending).map(\.package)
    }

    var current: TerminalRow? {
        let items = rows
        return items.indices.contains(selected) ? items[selected] : nil
    }

    var isBusy: Bool { busy != nil || store.isRunningCommand || store.isLoading || store.isSearchingDiscover }

    func matches(_ value: String) -> Bool {
        store.searchText.isEmpty || value.localizedCaseInsensitiveContains(store.searchText)
    }

    func run() async throws {
        setlocale(LC_CTYPE, "")
        let terminal = try TerminalSession()
        defer {
            signalSources.forEach { $0.cancel() }
            terminal.restore()
        }
        for number in [SIGTERM, SIGHUP, SIGINT] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { [weak self] in
                self?.handle(.interrupt)
            }
            source.resume()
            signalSources.append(source)
        }
        if options.demo { loadDemo() }
        else { perform("Reading Homebrew inventory") { await self.store.refreshAll() } }
        var frozenTime: Float = 0
        var lastTick = Date()
        while !quitting {
            let frameStart = Date()
            for key in terminal.keys() { handle(key) }
            if quitWhenIdle && !isBusy { quitting = true }
            if quitting { break }
            let size = terminal.size
            let delta = Float(Date().timeIntervalSince(lastTick))
            lastTick = Date()
            if animated { frozenTime += min(delta, 0.25) }
            terminal.draw(screen(width: size.width, height: size.height, time: frozenTime))
            let target = animated ? options.fps : 10
            let budget = max(0.002, 1 / Double(target) - Date().timeIntervalSince(frameStart))
            try await Task.sleep(for: .seconds(budget))
        }
    }

    func perform(_ title: String, operation: @escaping @MainActor () async -> Void) {
        guard !isBusy else { message = "Wait for the current operation to finish"; return }
        busy = title
        message = title
        Task {
            await operation()
            busy = nil
            selected = min(selected, max(0, rows.count - 1))
            message = store.statusBannerMessage ?? "Finished · \(title)"
        }
    }

    func confirm(_ title: String, operation: @escaping @MainActor () async -> Void) {
        guard !isBusy else { message = "Wait for the current operation to finish"; return }
        guard !options.demo else { message = "Demo mode · commands are disabled"; return }
        confirmation = TerminalConfirmation(title: title, operation: operation)
    }

    func handle(_ key: TerminalKey) {
        if key == .interrupt {
            requestQuit()
            return
        }
        if confirmation != nil {
            if key == .escape || key == .text("n") { confirmation = nil }
            if key == .text("y"), let action = confirmation {
                confirmation = nil
                perform(action.title, operation: action.operation)
                showConsole = true
            }
            return
        }
        if prompt != nil { handlePrompt(key); return }
        if showHelp { showHelp = false; return }
        if showArt {
            if key == .text(" ") { animated.toggle() }
            else { showArt = false }
            return
        }
        if tab == .graph, handleGraph(key) { return }
        switch key {
        case .escape:
            detailExpanded = false
            store.searchText = ""
            detailOffset = 0
        case .up, .text("k"): move(-1)
        case .down, .text("j"): move(1)
        case .pageUp: scroll(-10)
        case .pageDown: scroll(10)
        case .left: switchTab(-1)
        case .right, .tab: switchTab(1)
        case .enter: detailExpanded.toggle(); detailOffset = 0
        case .text(let text): handleCharacter(text)
        default: break
        }
    }

    private func requestQuit() {
        if isBusy {
            quitWhenIdle = true
            message = "Will exit after the current command finishes"
        }
        else { quitting = true }
    }

    private func move(_ amount: Int) {
        selected = max(0, min(max(0, rows.count - 1), selected + amount))
        detailOffset = 0
        if tab == .graph, let package = current?.package { graph.focus(package.name) }
    }

    private func scroll(_ amount: Int) {
        if showConsole { logOffset = max(0, min(max(0, store.terminalLogs.count - 1), logOffset - amount)) }
        else { detailOffset = max(0, detailOffset + amount) }
    }

    private func switchTab(_ amount: Int) {
        let tabs = NavigationTab.allCases
        let index = tabs.firstIndex(of: tab) ?? 0
        selectTab(tabs[(index + amount + tabs.count) % tabs.count])
    }

    private func selectTab(_ tab: NavigationTab) {
        self.tab = tab
        selected = 0; detailOffset = 0; detailExpanded = false
        store.searchText = ""
        if tab == .graph {
            if graph.focusedName.isEmpty, let package = store.selectedPackage, !package.isCask { graph.focus(package.name) }
            selected = rows.firstIndex(where: { $0.package?.name == graph.focusedName }) ?? 0
        }
    }

    private func handleCharacter(_ key: String) {
        if let number = Int(key), (1...8).contains(number) { selectTab(NavigationTab.allCases[number - 1]); return }
        switch key {
        case "q": requestQuit()
        case "?": showHelp = true
        case "A": showArt = true
        case " ": animated.toggle(); message = animated ? "Motion resumed" : "Motion paused"
        case "l": showConsole.toggle(); logOffset = 0
        case "/": prompt = TerminalPrompt(purpose: .search, title: tab == .discover ? "Search Homebrew" : "Filter \(tab.rawValue)")
        case "r": refresh()
        case "f":
            if tab == .discover {
                catalog = catalog == .formulae ? .casks : .formulae
                selected = 0
            } else {
                let values = PackageFilter.allCases
                store.packageFilter = values[((values.firstIndex(of: store.packageFilter) ?? 0) + 1) % values.count]
                selected = 0
            }
        case "c" where tab == .discover:
            store.resetDiscoverSearch(); selected = 0
            loadCharts()
        case "t" where tab == .discover:
            chartMode = chartMode == .top ? .trending : .top
            store.resetDiscoverSearch(); selected = 0
            loadCharts()
        case "b" where tab == .taps: showBrewfile.toggle(); detailOffset = 0
        case "e" where tab == .taps: prompt = TerminalPrompt(purpose: .export, title: "Export Brewfile to path")
        case "m" where tab == .taps: prompt = TerminalPrompt(purpose: .importBundle, title: "Import Brewfile from path")
        case "w": prompt = TerminalPrompt(purpose: .logs, title: "Save command log to path")
        case "a" where tab == .taps: prompt = TerminalPrompt(purpose: .tap, title: "Add tap · owner/repository")
        case "d" where tab == .health:
            if !options.demo { perform("Homebrew diagnostics") { await self.store.runDoctor() }; showConsole = true }
        case "c" where tab == .health:
            if !options.demo { perform("Preview cleanup") { await self.store.runCleanup(dryRun: true) }; showConsole = true }
        case "C" where tab == .health: confirm("brew cleanup --prune=all") { await self.store.runCleanup(dryRun: false) }
        case "a" where tab == .health: confirm("brew autoremove") { await self.store.runAutoremove() }
        case "a" where tab == .updates: confirm("brew upgrade · all outdated packages") { await self.store.upgradeAll() }
        case "U" where tab == .updates: confirm("brew update · update Homebrew index") { await self.store.updateHomebrew() }
        default: itemAction(key)
        }
    }

    private func itemAction(_ key: String) {
        guard tab != .graph else { return }
        if tab == .services {
            let services = store.services.filter { matches($0.name) }
            guard services.indices.contains(selected), let action = ["s": "start", "t": "stop", "R": "restart"][key] else { return }
            let service = services[selected]
            confirm("brew services \(action) \(service.name)") { await self.store.controlService(service, action: action) }
        } else if tab == .taps, key == "x", let current {
            confirm("brew untap \(current.title)") { await self.store.removeTap(name: current.title) }
        } else if let package = current?.package {
            switch key {
            case "i" where tab == .discover:
                guard !store.installedPackages.contains(where: { $0.id == package.id }) else { message = "Already installed"; return }
                confirm("brew install \(package.isCask ? "--cask" : "--formula") \(package.name)") { await self.store.installPackage(name: package.name, isCask: package.isCask) }
            case "u" where tab != .discover:
                confirm("brew upgrade \(package.name)") { await self.store.upgradePackage(name: package.name, isCask: package.isCask) }
            case "x" where tab != .discover:
                confirm("brew uninstall \(package.name) · remove this package") { await self.store.uninstallPackage(package) }
            case "p" where !package.isCask && tab != .discover:
                confirm("brew \(package.isPinned ? "unpin" : "pin") \(package.name)") { await self.store.togglePin(package) }
            case "g" where !package.isCask:
                selectTab(.graph)
                graph.focus(package.name)
                selected = rows.firstIndex(where: { $0.package?.id == package.id }) ?? 0
            default: break
            }
        }
    }

    private func refresh() {
        guard !options.demo else { message = "Demo mode · showing sample inventory"; return }
        switch tab {
        case .health: perform("Reading Homebrew health") { await self.store.refreshHealth() }
        case .security: perform("Checking security reports") { await self.store.refreshSecurity() }
        case .discover:
            if store.hasSearchedDiscover {
                perform("Searching Homebrew") { await self.store.searchRemotePackages(query: self.store.discoverSearchText) }
            } else { loadCharts(force: true) }
        default: perform("Refreshing Homebrew") { await self.store.refreshAll() }
        }
    }

    private func loadCharts(force: Bool = false) {
        guard !options.demo else { return }
        perform("Loading \(catalog.rawValue) charts") { await self.store.loadDiscoverCharts(self.catalog, force: force) }
    }

    private func handlePrompt(_ key: TerminalKey) {
        guard var value = prompt else { return }
        switch key {
        case .escape: prompt = nil; return
        case .backspace: if !value.value.isEmpty { value.value.removeLast() }
        case .text(let text), .paste(let text): value.value += TerminalText.clean(text)
        case .enter:
            prompt = nil
            submit(value)
            return
        default: break
        }
        value.value = String(value.value.prefix(2048))
        prompt = value
    }

    private func submit(_ prompt: TerminalPrompt) {
        let value = prompt.value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch prompt.purpose {
        case .search:
            selected = 0; detailOffset = 0
            if tab == .discover {
                guard !options.demo else { store.hasSearchedDiscover = true; store.discoverResults = store.installedPackages.filter { $0.name.contains(value) }; return }
                store.discoverSearchText = value
                perform("Searching for \(value)") { await self.store.searchRemotePackages(query: value) }
            } else { store.searchText = value }
        case .tap:
            guard value.split(separator: "/").count == 2, BrewSearchOutput.isPackageToken(value) else { message = "Use an owner/repository tap name"; return }
            confirm("brew tap \(value)") { await self.store.addTap(name: value) }
        case .importBundle:
            let url = URL(fileURLWithPath: (value as NSString).expandingTildeInPath)
            guard FileManager.default.isReadableFile(atPath: url.path) else { message = "Brewfile is not readable"; return }
            confirm("brew bundle install --file=\(url.path)") { await self.store.importBrewfile(from: url) }
        case .export, .logs:
            guard !value.isEmpty else { message = "Enter a file path"; return }
            let url = URL(fileURLWithPath: (value as NSString).expandingTildeInPath)
            guard !FileManager.default.fileExists(atPath: url.path) else { message = "File exists · choose another path"; return }
            if prompt.purpose == .export {
                confirm("Export Brewfile to \(url.path)") {
                    do {
                        let result = try await BrewCLIService.shared.runCommand(["bundle", "dump", "--file=-"])
                        guard result.exitCode == 0 else { throw TerminalOptions.invalid(result.combinedOutput) }
                        try Data(result.stdout.utf8).write(to: url, options: .withoutOverwriting)
                        self.store.statusBannerMessage = "Saved \(url.lastPathComponent)"
                    } catch { self.store.statusBannerMessage = error.localizedDescription }
                }
            } else {
                do {
                    let text = store.terminalLogs.map(\.text).joined(separator: "\n")
                    try Data(text.utf8).write(to: url, options: .withoutOverwriting)
                    message = "Saved log to \(url.path)"
                } catch { message = error.localizedDescription }
            }
        }
    }

    func fieldColors(width: Int, height: Int, time: Float) -> [TerminalRGB] {
        guard animationSize != (width, height) || (animated && time != lastAnimationTime) else { return animationColors }
        do {
            animationColors = try animation.colors(width: width, height: height, time: time)
            animationSize = (width, height)
            lastAnimationTime = time
        } catch {
            animated = false
            message = "Animation stopped · \(error.localizedDescription)"
            animationColors = Array(repeating: .panel, count: width * height)
            animationSize = (width, height)
        }
        return animationColors
    }

    func loadDemo() {
        store.installedPackages = [
            BrewPackage(name: "ffmpeg", desc: "Record, convert and stream audio and video", version: "8.0", outdatedVersion: "8.0.1", isOutdated: true, tap: "homebrew/core", dependencies: ["libvpx", "x264", "openssl@3", "opus"]),
            BrewPackage(name: "git", desc: "Distributed version control", version: "2.51.0", tap: "homebrew/core", dependencies: ["openssl@3", "pcre2"]),
            BrewPackage(name: "ghostty", desc: "Fast, native, GPU accelerated terminal", version: "1.2.0", isCask: true, tap: "homebrew/cask"),
            BrewPackage(name: "node", desc: "JavaScript runtime", version: "24.0.0", isPinned: true, tap: "homebrew/core", dependencies: ["openssl@3", "icu4c@77"]),
            BrewPackage(name: "ripgrep", desc: "Recursively search directories with regular expressions", version: "14.1.1", tap: "homebrew/core", dependencies: ["pcre2"])
        ]
        store.discoverResults = store.installedPackages
        store.hasSearchedDiscover = true
        store.outdatedPackages = [OutdatedPackage(name: "ffmpeg", installedVersions: ["8.0"], currentVersion: "8.0.1")]
        store.services = [BrewServiceItem(name: "postgresql@17", status: .started, user: "local"), BrewServiceItem(name: "redis", status: .stopped)]
        store.taps = [BrewTap(name: "homebrew/core", remote: "https://github.com/Homebrew/homebrew-core", formulaCount: 8000), BrewTap(name: "homebrew/cask", caskCount: 7000)]
        store.brewfilePreview = "tap \"homebrew/core\"\nbrew \"ffmpeg\"\nbrew \"git\"\nbrew \"ripgrep\"\ncask \"ghostty\""
        store.healthReport = BrewHealthReport(rawOutput: "Your system is ready to brew.", cacheSizeBytes: 512_000_000, brewVersion: "Homebrew · sample data")
        store.securityFindings = []
        store.discoverCharts = [:]
        store.terminalLogs = [CommandLogEntry(text: "Demo inventory loaded · no Homebrew commands will run", isCommandHeader: true)]
        message = "DEMO · sample data · commands disabled"
    }
}
