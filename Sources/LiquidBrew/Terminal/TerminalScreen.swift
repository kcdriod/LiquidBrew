import Foundation

extension TerminalApp {
    func screen(width: Int, height: Int, time: Float) -> TerminalFrame {
        var frame = TerminalFrame(width: width, height: height)
        guard width >= 80, height >= 24 else {
            frame.text("LiquidBrew needs at least 80 columns × 24 rows.", x: 0, y: 0)
            frame.text("Resize the window · q to quit", x: 0, y: 2, color: .cyan)
            return frame
        }
        let fieldHeight = 6
        let colors = fieldColors(width: width, height: fieldHeight, time: time)
        for y in 0..<fieldHeight {
            for x in 0..<width {
                frame.cells[y * width + x].background = colors[y * width + x]
            }
        }
        let pulse = ["◐", "◓", "◑", "◒"][Int(time * 6) % 4]
        for (row, line) in TerminalArt.mug(time: time).enumerated() {
            frame.text(line, x: 3, y: row, color: .cyan)
        }
        frame.text("\(pulse) LIQUIDBREW", x: 14, y: 1, color: .cyan, bold: true)
        frame.text(options.demo ? "TERMINAL / DEMO" : "TERMINAL / LIVE", x: 14, y: 2, color: .muted)
        let rendererX = max(width / 2 + 3, width - 49)
        frame.text(animation.description, x: rendererX, y: 1, limit: width - rendererX - 2, color: .cyan)
        frame.text(animated ? "\(options.fps) FPS · Space pauses · A art" : "Motion paused · Space resumes", x: rendererX, y: 2, limit: width - rendererX - 2, color: .muted)
        frame.text("\(store.installedPackages.count) INSTALLED     \(store.outdatedPackages.count) UPDATES     \(store.services.filter { $0.status == .started }.count) RUNNING SERVICES", x: 14, y: 4, limit: width - 16, bold: true)
        drawTabs(&frame)
        let filter = tab == .discover ? "\(catalog.rawValue) · \(store.hasSearchedDiscover ? "Search" : chartMode.rawValue)" : store.packageFilter.rawValue
        let query = store.searchText.isEmpty ? "" : " · /\(store.searchText)"
        frame.text("\(tab.rawValue.uppercased())  /  \(filter)\(query)", x: 2, y: 9, limit: width - 18, color: .muted)
        frame.text("\(rows.count) ITEMS", x: width - 15, y: 9, limit: 13, color: .cyan)

        let bodyY = 11
        let consoleOnly = showConsole && height < 30
        let consoleHeight = consoleOnly ? height - bodyY - 4 : (showConsole ? min(10, max(6, height / 4)) : 0)
        let bodyHeight = height - bodyY - 4 - consoleHeight
        let split = width >= 104 && !detailExpanded
        let listWidth = split ? min(43, width / 3) : width - 4
        if !consoleOnly {
            if tab == .graph {
                let sidebarWidth = width >= 120 && !graph.expanded ? min(32, width / 4) : 0
                if sidebarWidth > 0 { drawRows(&frame, x: 2, y: bodyY, width: sidebarWidth, height: bodyHeight) }
                let graphX = sidebarWidth > 0 ? sidebarWidth + 4 : 2
                drawDependencyGraph(&frame, x: graphX, y: bodyY, width: width - graphX - 2, height: bodyHeight, time: time)
            } else if detailExpanded {
                drawDetails(&frame, x: 2, y: bodyY, width: width - 4, height: bodyHeight, time: time)
            } else {
                drawRows(&frame, x: 2, y: bodyY, width: listWidth, height: bodyHeight)
                if split {
                    drawDetails(&frame, x: listWidth + 4, y: bodyY, width: width - listWidth - 6, height: bodyHeight, time: time)
                }
            }
        }
        if showConsole { drawConsole(&frame, y: bodyY + bodyHeight, height: consoleHeight) }
        let status = busy ?? store.statusBannerMessage ?? message
        frame.text("\(isBusy ? pulse : "•") \(status)", x: 2, y: height - 3, limit: width - 4, color: isBusy ? .warning : .cyan)
        frame.text(keyHints, x: 2, y: height - 2, limit: width - 4, color: .muted)
        if showHelp { drawHelp(&frame) }
        if showArt { drawArt(&frame, time: time) }
        if let prompt { drawPrompt(&frame, title: prompt.title, text: prompt.value, confirmation: false) }
        if let confirmation { drawPrompt(&frame, title: "Confirm operation", text: confirmation.title, confirmation: true) }
        return frame
    }

    private func drawTabs(_ frame: inout TerminalFrame) {
        let compact = frame.width < 110
        let names = compact ? ["Pkgs", "Find", "Updates", "Svcs", "Graph", "Taps", "Health", "Security"] : ["Packages", "Discover", "Updates", "Services", "Graph", "Taps", "Health", "Security"]
        var x = 2
        for (index, item) in NavigationTab.allCases.enumerated() {
            let label = " \(index + 1) \(names[index]) "
            let length = label.count
            frame.fill(x: x, y: 7, width: length, height: 1, background: item == tab ? TerminalRGB(r: 34, g: 70, b: 83) : .background)
            frame.text(label, x: x, y: 7, color: item == tab ? .cyan : .muted, bold: item == tab)
            x += length + (compact ? 0 : 1)
        }
    }

    private func drawRows(_ frame: inout TerminalFrame, x: Int, y: Int, width: Int, height: Int) {
        frame.box(x: x, y: y, width: width, height: height, title: tab.rawValue)
        let items = rows
        let visible = max(1, (height - 3) / 3)
        let start = min(max(0, selected - visible + 1), max(0, items.count - visible))
        for (position, row) in items.dropFirst(start).prefix(visible).enumerated() {
            let rowY = y + 2 + position * 3
            let index = start + position
            let chosen = selected == index
            if chosen { frame.fill(x: x + 1, y: rowY - 1, width: width - 2, height: 3, background: TerminalRGB(r: 26, g: 50, b: 65)) }
            frame.text(chosen ? "›" : " ", x: x + 1, y: rowY, color: .cyan)
            frame.text(row.title, x: x + 3, y: rowY, limit: width - 5, color: chosen ? .cyan : .text, bold: chosen)
            frame.text(row.subtitle, x: x + 3, y: rowY + 1, limit: width - 5, color: .muted)
        }
        if items.isEmpty {
            let text: String
            switch tab {
            case .discover: text = store.discoverSearchError ?? store.discoverChartErrors[catalog] ?? "Press / to search · c for charts"
            case .security: text = store.isCheckingSecurity ? "Checking report sources…" : "No matching reports · r refreshes"
            case .updates: text = store.searchText.isEmpty ? "No outdated packages loaded" : "No matching updates"
            default: text = isBusy ? "Reading Homebrew…" : "No matches · Esc clears the filter"
            }
            let lines = TerminalText.wrapped(text, width: width - 6)
            for (offset, line) in lines.prefix(max(0, height - 4)).enumerated() { frame.text(line, x: x + 3, y: y + 2 + offset, color: .muted) }
        }
        if items.count > visible {
            frame.text(" \(start + 1)–\(min(items.count, start + visible)) / \(items.count) ", x: x + 2, y: y + height - 1, limit: width - 4, color: .muted)
        }
    }

    private func drawDetails(_ frame: inout TerminalFrame, x: Int, y: Int, width: Int, height: Int, time: Float) {
        frame.box(x: x, y: y, width: width, height: height, title: detailExpanded ? "Details · Esc returns" : "Details · Enter expands")
        let content = detailLines.flatMap { TerminalText.wrapped($0, width: width - 6) }
        let visible = max(1, height - 4)
        detailOffset = min(detailOffset, max(0, content.count - visible))
        for (offset, line) in content.dropFirst(detailOffset).prefix(visible).enumerated() {
            frame.text(line, x: x + 3, y: y + 2 + offset, limit: width - 6, color: offset == 0 && detailOffset == 0 ? .cyan : .text, bold: offset == 0 && detailOffset == 0)
        }
        if content.count > visible {
            frame.text(" PgUp/PgDn scroll · \(detailOffset + 1)/\(content.count) ", x: x + 2, y: y + height - 1, limit: width - 4, color: .muted)
        }
    }

    var detailLines: [String] {
        switch tab {
        case .health:
            let report = store.healthReport
            switch selected {
            case 1: return ["CACHE & OLD VERSIONS", "", report.formattedCacheSize, report.cachePath, "", "c  Preview cleanup", "C  Confirm cleanup", ""] + report.cleanupDryRunItems
            case 2: return ["UNUSED DEPENDENCIES", "", "a  Confirm autoremove", ""] + report.autoremoveCandidates
            default: return [report.brewVersion, report.homebrewPrefix, "Checked \(report.checkedAt.formatted())", "", "d  Run diagnostics", "", report.rawOutput]
            }
        case .taps:
            if showBrewfile { return ["BREWFILE", "", store.brewfilePreview.isEmpty ? "r refreshes the preview" : store.brewfilePreview] }
            let taps = store.taps.filter { matches($0.name) }
            guard taps.indices.contains(selected) else { return ["TAPS & BREWFILE", "a adds a repository", "b opens the Brewfile"] }
            let tap = taps[selected]
            return [tap.name, "", "\(tap.formulaCount) formulae · \(tap.caskCount) casks", tap.official ? "Official repository" : "Third party repository", tap.remote ?? "No remote URL", tap.path ?? "", "", "a  Add tap", "x  Confirm removal", "b  View Brewfile", "e  Export Brewfile", "m  Import Brewfile"]
        case .services:
            let services = store.services.filter { matches($0.name) }
            guard services.indices.contains(selected) else { return ["No services loaded"] }
            let service = services[selected]
            return [service.name, "", "Status  \(service.status.displayTitle)", "User    \(service.user ?? "—")", "PID     \(service.pid.map(String.init) ?? "—")", service.file ?? "", "", "s  Start service", "t  Stop service", "R  Restart service"]
        case .security:
            let findings = store.installedSecurityFindings.filter { matches($0.title + " " + $0.packageID) }
            var lines = ["SECURITY REPORTS", "Package matches require review.", ""]
            if findings.indices.contains(selected) {
                let finding = findings[selected]
                lines += [finding.packageID, finding.title, "", finding.detail, "", finding.url.absoluteString, ""]
            }
            lines += store.securitySources.map { "\($0.name) · \($0.error ?? ($0.checkedAt?.formatted() ?? "Not checked"))" }
            return lines
        default:
            guard let item = current else { return ["LIQUIDBREW", "", "Select an item to inspect it.", "Use / to search and ? for all keys."] }
            guard let package = item.package else { return [item.title, item.subtitle, item.badge] }
            var lines = [package.name, package.desc ?? "", "", "Kind     \(package.isCask ? "Cask" : "Formula")", "Version  \(package.version)", "Tap      \(package.tap ?? "—")", "License  \(package.license ?? "—")", "Status   \(item.badge)", package.homepage ?? ""]
            if tab == .discover, !store.hasSearchedDiscover, let chart = store.discoverCharts[catalog] {
                lines += ["", chartMode == .top ? chart.topPeriod : chart.trendPeriod, chart.warning ?? "", "Fetched \(chart.fetchedAt.formatted())"]
                if let entry = (chartMode == .top ? chart.top : chart.trending).first(where: { $0.package.id == package.id }) {
                    lines += ["Reported events  \(entry.count)"]
                    if let growth = entry.growth { lines += ["Growth  \(Int(growth * 100))%"] }
                }
            }
            if let latest = package.outdatedVersion { lines += ["Latest   \(latest)"] }
            if let caveats = package.caveats, !caveats.isEmpty { lines += ["", "CAVEATS", caveats] }
            let deps = Array(Set(package.dependencies + package.runtimeDependencies)).sorted()
            lines += ["", "DEPENDENCIES (\(deps.count))"] + deps
            let reverse = store.reverseDependencies(for: package.name).map(\.name)
            lines += ["", "REQUIRED BY (\(reverse.count))"] + reverse
            return lines
        }
    }

    private func drawConsole(_ frame: inout TerminalFrame, y: Int, height: Int) {
        frame.box(x: 2, y: y, width: frame.width - 4, height: height, title: "Console · l hides · PgUp/PgDn · w saves")
        let lines = store.terminalLogs.flatMap { entry in TerminalText.wrapped(entry.text, width: frame.width - 10).map { ($0, entry.isError, entry.isCommandHeader) } }
        let count = max(1, height - 2)
        let end = max(0, lines.count - logOffset)
        let start = max(0, end - count)
        for (offset, line) in lines[start..<end].enumerated() {
            frame.text(line.0, x: 5, y: y + 1 + offset, limit: frame.width - 10, color: line.1 ? .warning : (line.2 ? .cyan : .text))
        }
    }

    private var keyHints: String {
        let common = "1–8 tabs · ↑↓ move · / search · Enter details · ? help · q quit"
        switch tab {
        case .packages: return "u/x/p actions · f filter · g graph · l console · " + common
        case .graph: return "t layout · n network · +/- zoom · arrows pan · [ ] nodes · i inspect · ? keys"
        case .discover: return "i install · f formula/apps · c charts · t trending · " + common
        case .updates: return "u upgrade · a upgrade all · U update index · " + common
        case .services: return "s start · t stop · R restart · r refresh · " + common
        case .taps: return "a add · x remove · b Brewfile · e export · m import · " + common
        case .health: return "d doctor · c preview · C cleanup · a autoremove · " + common
        case .security: return "r refresh reports · PgUp/PgDn details · " + common
        }
    }

    private func drawPrompt(_ frame: inout TerminalFrame, title: String, text: String, confirmation: Bool) {
        let width = min(82, frame.width - 8)
        let lines = TerminalText.wrapped(text, width: width - 6)
        let height = min(frame.height - 6, max(7, lines.count + 5))
        let x = (frame.width - width) / 2
        let y = (frame.height - height) / 2
        frame.box(x: x, y: y, width: width, height: height, title: title)
        let visible = confirmation ? Array(lines.prefix(height - 5)) : Array(lines.suffix(height - 5))
        for (offset, line) in visible.enumerated() { frame.text(line, x: x + 3, y: y + 2 + offset, limit: width - 6, color: confirmation ? .warning : .text) }
        if !confirmation && text.isEmpty { frame.text("▏", x: x + 3, y: y + 2, color: .cyan) }
        frame.text(confirmation ? "y confirms · n / Esc cancels" : "Enter submits · Esc cancels", x: x + 3, y: y + height - 2, color: .cyan)
    }

    private func drawHelp(_ frame: inout TerminalFrame) {
        let width = min(92, frame.width - 6)
        let height = min(28, frame.height - 2)
        let x = (frame.width - width) / 2
        let y = (frame.height - height) / 2
        frame.box(x: x, y: y, width: width, height: height, title: "LiquidBrew · keyboard guide")
        let lines = [
            "1 Packages  2 Discover  3 Updates  4 Services", "5 Graph     6 Taps      7 Health   8 Security", "",
            "↑/k ↓/j navigate   ←/→/Tab switch screens   Enter expand details", "/ search/filter   Esc clear/back   PgUp/PgDn scroll details or logs", "r refresh   l console   w save logs   Space pause   A ASCII art   q quit", "",
            "PACKAGES   u upgrade   x remove   p pin/unpin   f filter   g graph", "DISCOVER   / search   i install   f formula/apps   c charts   t trending",
            "UPDATES    u upgrade selected   a upgrade all   U update index", "SERVICES   s start   t stop   R restart",
            "GRAPH      t radial/tree · n focused/network · f top-level filter",
            "           +/- zoom · arrows pan · 0 reset · v expand · j/k formulae",
            "           [ / ] or Tab selects nodes · i inspector · Enter focus · e Packages",
            "TAPS       a add   x remove   b Brewfile   e export   m import", "HEALTH     d diagnostics   c cleanup preview   C cleanup   a autoremove", "",
            "Package changes require y to confirm. Homebrew dependency checks apply.", "Demo mode runs no Homebrew commands. Search and charts use public sources.", "",
            animation.description, "Metal computes animated colors; your terminal draws the glyphs.", "Use Ghostty for Metal terminal rendering on macOS.", "", "Press any key to return."
        ]
        for (index, line) in lines.prefix(height - 3).enumerated() { frame.text(line, x: x + 3, y: y + 2 + index, limit: width - 6, color: index < 2 ? .cyan : .text) }
    }

    private func drawArt(_ frame: inout TerminalFrame, time: Float) {
        let width = min(72, frame.width - 6)
        let height = min(22, frame.height - 2)
        let x = (frame.width - width) / 2
        let y = (frame.height - height) / 2
        frame.box(x: x, y: y, width: width, height: height, title: "ASCII lounge · A returns")
        for (index, line) in TerminalArt.splash(time: time).prefix(height - 3).enumerated() {
            frame.text(line, x: x + 7, y: y + 2 + index, limit: width - 10, color: index < 12 ? .cyan : .text, bold: index == 0)
        }
    }
}
