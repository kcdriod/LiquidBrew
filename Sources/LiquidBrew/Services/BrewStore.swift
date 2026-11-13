import Foundation
import SwiftUI
import UserNotifications

@MainActor
public final class BrewStore: ObservableObject {
    @Published public var selectedTab: NavigationTab = .packages
    @Published public var packageFilter: PackageFilter = .all
    @Published public var searchText: String = ""
    @Published public var discoverSearchText: String = ""

    @Published public var installedPackages: [BrewPackage] = []
    @Published public var discoverResults: [BrewPackage] = []
    @Published var hasSearchedDiscover = false
    @Published var discoverSearchError: String?
    private var discoverSearchID = UUID()
    @Published var discoverCharts: [DiscoverCatalog: DiscoverChartSnapshot] = [:]
    @Published var loadingDiscoverCharts: Set<DiscoverCatalog> = []
    @Published var discoverChartErrors: [DiscoverCatalog: String] = [:]
    private let chartsService = DiscoverChartsService()
    private var activeDiscoverQuery: String?
    private let packageSearch: (String, Set<String>) async throws -> [BrewPackage]
    @Published public var outdatedPackages: [OutdatedPackage] = []
    @Published public var services: [BrewServiceItem] = []
    @Published public var taps: [BrewTap] = []
    @Published public var healthReport: BrewHealthReport = BrewHealthReport()

    @Published public var selectedPackage: BrewPackage?
    @Published public var isLoading: Bool = false
    @Published public var isSearchingDiscover: Bool = false
    @Published public var isRunningCommand: Bool = false
    @Published public var currentCommandTitle: String = ""
    @Published public private(set) var commandStartedAt: Date?
    @Published public var showTerminalDrawer: Bool = false
    @Published public var terminalLogs: [CommandLogEntry] = []
    @Published public var brewfilePreview: String = ""
    @Published public var statusBannerMessage: String?

    @Published var securityFindings: [SecurityFinding] = []
    @Published var securitySources: [SecuritySourceStatus] = []
    @Published var isCheckingSecurity = false
    @Published var securityNotificationsEnabled = UserDefaults.standard.bool(forKey: "securityNotificationsEnabled")
    @Published var notificationMessage: String?
    private let securityService = PackageSecurityService()
    private var packageInventoryLoaded = false

    var installedSecurityFindings: [SecurityFinding] {
        let ids = Set(installedPackages.map(\.id))
        return securityFindings.filter { ids.contains($0.packageID) }
            .sorted { $0.isMalwareWarning && !$1.isMalwareWarning }
    }

    func refreshSecurity() async {
        guard packageInventoryLoaded, !isCheckingSecurity else { return }
        isCheckingSecurity = true
        defer { isCheckingSecurity = false }
        let inventory = installedPackages
        let results = await securityService.scan(packages: inventory)
        if inventory != installedPackages {
            isCheckingSecurity = false
            await refreshSecurity()
            return
        }
        for result in results {
            if result.status.error == nil {
                securityFindings.removeAll { $0.sourceID == result.status.id }
                securityFindings.append(contentsOf: result.findings)
            }
            let previous = securitySources.first { $0.id == result.status.id }
            var status = result.status
            if status.error != nil { status.checkedAt = previous?.checkedAt }
            securitySources.removeAll { $0.id == status.id }
            securitySources.append(status)
        }
        // Keep cached warnings if a source fails, but never for an uninstalled package.
        let installedIDs = Set(installedPackages.map(\.id))
        securityFindings.removeAll { !installedIDs.contains($0.packageID) }
        let defaults = UserDefaults.standard
        defaults.set(try? JSONEncoder().encode(securityFindings), forKey: "securityFindings")
        defaults.set(try? JSONEncoder().encode(securitySources), forKey: "securitySources")
        await notifyNewSecurityFindings()
    }

    func setSecurityNotifications(_ enabled: Bool) async {
        if enabled {
            do {
                guard try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) else {
                    notificationMessage = "Notifications are disabled. Allow LiquidBrew in System Settings → Notifications."
                    return
                }
            } catch {
                notificationMessage = "Could not enable notifications: \(error.localizedDescription)"
                return
            }
        }
        securityNotificationsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "securityNotificationsEnabled")
        notificationMessage = nil
        if enabled { await notifyNewSecurityFindings() }
    }

    private func notifyNewSecurityFindings() async {
        guard securityNotificationsEnabled else { return }
        let defaults = UserDefaults.standard
        var delivered = Set(defaults.stringArray(forKey: "securityDeliveredFindings") ?? [])
        let newFindings = installedSecurityFindings.filter { !delivered.contains($0.id) }
        guard !newFindings.isEmpty else { return }
        let content = UNMutableNotificationContent()
        content.title = "Package security reports to review"
        content.body = "\(Set(newFindings.map(\.packageID)).count) installed package(s) matched reports. Open LiquidBrew’s Security tab to review sources and removal options."
        content.sound = .default
        do {
            try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "liquidbrew-security", content: content, trigger: nil))
            delivered.formUnion(newFindings.map(\.id))
            defaults.set(Array(delivered).sorted(), forKey: "securityDeliveredFindings")
        } catch {
            notificationMessage = "Could not deliver security notification: \(error.localizedDescription)"
        }
    }

    private let cli: BrewCLIService

    public init(cli: BrewCLIService = .shared, packageSearch: ((String, Set<String>) async throws -> [BrewPackage])? = nil) {
        self.cli = cli
        self.packageSearch = packageSearch ?? { query, names in
            try await cli.searchPackages(query: query, installedNames: names)
        }
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "discoverCharts"), let cached = try? JSONDecoder().decode([DiscoverCatalog: DiscoverChartSnapshot].self, from: data) { discoverCharts = cached }
        if let data = defaults.data(forKey: "securityFindings"), let cached = try? JSONDecoder().decode([SecurityFinding].self, from: data) { securityFindings = cached }
        if let data = defaults.data(forKey: "securitySources"), let cached = try? JSONDecoder().decode([SecuritySourceStatus].self, from: data) { securitySources = cached }
    }

    public var filteredPackages: [BrewPackage] {
        installedPackages.filter { pkg in
            let matchesFilter: Bool
            switch packageFilter {
            case .all: matchesFilter = true
            case .formulae: matchesFilter = !pkg.isCask
            case .casks: matchesFilter = pkg.isCask
            case .leaves: matchesFilter = pkg.isLeaf && !pkg.isCask
            case .pinned: matchesFilter = pkg.isPinned
            case .outdated: matchesFilter = pkg.isOutdated
            }
            guard matchesFilter else { return false }
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return true
            }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return pkg.name.lowercased().contains(query) ||
                pkg.fullName.lowercased().contains(query) ||
                (pkg.desc?.lowercased().contains(query) ?? false)
        }
    }

    // MARK: - Data Refresh Methods

    public func refreshAll() async {
        isLoading = true
        appendLog("$ brew info --json=v2 --installed && brew outdated && brew services list && brew tap-info", isHeader: true)

        async let pkgsTask: Void = refreshPackages()
        async let outdatedTask: Void = refreshOutdated()
        async let servicesTask: Void = refreshServices()
        async let tapsTask: Void = refreshTaps()

        _ = await (pkgsTask, outdatedTask, servicesTask, tapsTask)
        isLoading = false

        // Load health & Brewfile preview in background so startup feels instant
        Task {
            await generateBrewfilePreview()
            await refreshHealth()
        }
    }

    public func refreshPackages() async {
        do {
            let pkgs = try await cli.fetchInstalledPackages()
            self.installedPackages = pkgs
            packageInventoryLoaded = true
            securityFindings.removeAll { finding in !pkgs.contains { $0.id == finding.packageID } }
            Task { await refreshSecurity() }
            if let currentSelected = selectedPackage {
                self.selectedPackage = pkgs.first(where: { $0.id == currentSelected.id }) ?? pkgs.first
            } else if selectedPackage == nil {
                self.selectedPackage = pkgs.first
            }
        } catch {
            appendLog("Failed to load installed packages: \(error.localizedDescription)", isError: true)
        }
    }

    public func refreshOutdated() async {
        do {
            let outdated = try await cli.fetchOutdatedPackages()
            self.outdatedPackages = outdated
        } catch {
            appendLog("Failed to load outdated packages: \(error.localizedDescription)", isError: true)
        }
    }

    public func refreshServices() async {
        do {
            let items = try await cli.fetchServices()
            self.services = items
        } catch {
            appendLog("Failed to load services: \(error.localizedDescription)", isError: true)
        }
    }

    public func refreshTaps() async {
        do {
            let fetchedTaps = try await cli.fetchTaps()
            self.taps = fetchedTaps
        } catch {
            appendLog("Failed to load taps: \(error.localizedDescription)", isError: true)
        }
    }

    public func refreshHealth() async {
        let report = await cli.fetchHealthReport()
        self.healthReport = report
    }

    func loadDiscoverCharts(_ catalog: DiscoverCatalog, force: Bool = false) async {
        guard !loadingDiscoverCharts.contains(catalog) else { return }
        loadingDiscoverCharts.insert(catalog)
        defer { loadingDiscoverCharts.remove(catalog) }
        discoverChartErrors[catalog] = nil
        do {
            discoverCharts[catalog] = try await chartsService.load(catalog, force: force)
            if let data = try? JSONEncoder().encode(discoverCharts) {
                UserDefaults.standard.set(data, forKey: "discoverCharts")
            }
        } catch {
            discoverChartErrors[catalog] = error.localizedDescription
        }
    }

    func resetDiscoverSearch() {
        discoverSearchID = UUID()
        activeDiscoverQuery = nil
        isSearchingDiscover = false
        discoverResults = []
        discoverSearchError = nil
        hasSearchedDiscover = false
    }

    public func searchRemotePackages(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { resetDiscoverSearch(); return }
        guard !(isSearchingDiscover && activeDiscoverQuery == trimmed) else { return }
        let requestID = UUID()
        discoverSearchID = requestID
        activeDiscoverQuery = trimmed
        isSearchingDiscover = true
        hasSearchedDiscover = true
        discoverSearchError = nil
        discoverResults = []
        defer {
            if discoverSearchID == requestID {
                isSearchingDiscover = false
                activeDiscoverQuery = nil
            }
        }
        do {
            let results = try await packageSearch(trimmed, Set(installedPackages.map(\.name)))
            guard discoverSearchID == requestID, !Task.isCancelled,
                  trimmed == discoverSearchText.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            discoverResults = results
        } catch {
            guard discoverSearchID == requestID, !Task.isCancelled,
                  trimmed == discoverSearchText.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            discoverSearchError = error.localizedDescription
            appendLog("Search failed for '\(trimmed)': \(error.localizedDescription)", isError: true)
        }
    }

    // MARK: - Package Actions

    public func installPackage(name: String, isCask: Bool) async {
        let args = isCask ? ["install", "--cask", name] : ["install", name]
        let code = await executeStreamingCommand(
            title: "Installing \(name)...",
            arguments: args,
            openDrawer: true
        )
        if code == 0 {
            showBanner("Installed \(name) successfully")
        } else {
            showBanner("Failed to install \(name) (exit \(code))")
        }
        await refreshPackages()
        await refreshOutdated()
    }

    public func uninstallPackage(_ package: BrewPackage) async {
        guard !isRunningCommand, installedPackages.contains(where: { $0.id == package.id }) else { return }
        let caskToken = package.tap.map { "\($0)/\(package.name)" } ?? package.name
        let args = package.isCask
            ? ["uninstall", "--cask", caskToken]
            : ["uninstall", "--formula", package.fullName]
        let code = await executeStreamingCommand(
            title: "Uninstalling \(package.name)...",
            arguments: args,
            openDrawer: true
        )
        if code == 0 {
            if selectedPackage?.id == package.id {
                selectedPackage = nil
            }
            showBanner("Uninstalled \(package.name)")
        } else {
            showBanner("Could not uninstall \(package.name) (exit \(code))")
        }
        await refreshPackages()
        await refreshOutdated()
    }

    public func upgradePackage(name: String, isCask: Bool) async {
        let args = isCask ? ["upgrade", "--cask", name] : ["upgrade", name]
        let code = await executeStreamingCommand(
            title: "Upgrading \(name)...",
            arguments: args,
            openDrawer: true
        )
        if code == 0 {
            showBanner("Upgraded \(name) to latest version")
        } else {
            showBanner("Upgrade of \(name) finished with exit code \(code)")
        }
        await refreshPackages()
        await refreshOutdated()
    }

    public func upgradeAll() async {
        let code = await executeStreamingCommand(
            title: "Upgrading all outdated packages...",
            arguments: ["upgrade"],
            openDrawer: true
        )
        if code == 0 {
            showBanner("All packages upgraded")
        } else {
            showBanner("Upgrade all finished with exit code \(code)")
        }
        await refreshPackages()
        await refreshOutdated()
    }

    public func togglePin(_ package: BrewPackage) async {
        guard !package.isCask else { return }
        let action = package.isPinned ? "unpin" : "pin"
        let title = package.isPinned ? "Unpinning \(package.name)..." : "Pinning \(package.name)..."
        let code = await executeStreamingCommand(
            title: title,
            arguments: [action, package.name],
            openDrawer: false
        )
        if code == 0 {
            showBanner(package.isPinned ? "Unpinned \(package.name)" : "Pinned \(package.name)")
        }
        await refreshPackages()
        await refreshOutdated()
    }

    public func updateHomebrew() async {
        let code = await executeStreamingCommand(
            title: "Updating Homebrew & Taps...",
            arguments: ["update"],
            openDrawer: true
        )
        if code == 0 {
            showBanner("Homebrew updated")
        }
        await refreshAll()
    }

    // MARK: - Services, Taps & Brewfile Actions

    public func controlService(_ service: BrewServiceItem, action: String) async {
        let validAction = action.lowercased()
        let code = await executeStreamingCommand(
            title: "\(validAction.capitalized) service \(service.name)...",
            arguments: ["services", validAction, service.name],
            openDrawer: true
        )
        if code == 0 {
            showBanner("Service \(service.name): \(validAction)")
        } else {
            showBanner("Service \(service.name) \(validAction) exited with code \(code)")
        }
        await refreshServices()
    }

    public func addTap(name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let code = await executeStreamingCommand(
            title: "Adding tap \(trimmed)...",
            arguments: ["tap", trimmed],
            openDrawer: true
        )
        if code == 0 {
            showBanner("Tapped \(trimmed)")
        } else {
            showBanner("Failed to tap \(trimmed)")
        }
        await refreshTaps()
    }

    public func removeTap(name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let code = await executeStreamingCommand(
            title: "Removing tap \(trimmed)...",
            arguments: ["untap", trimmed],
            openDrawer: true
        )
        if code == 0 {
            showBanner("Untapped \(trimmed)")
        } else {
            showBanner("Failed to untap \(trimmed)")
        }
        await refreshTaps()
    }

    public func generateBrewfilePreview() async {
        do {
            let content = try await cli.generateBrewfileContent()
            self.brewfilePreview = content
        } catch {
            appendLog("Failed to generate Brewfile preview: \(error.localizedDescription)", isError: true)
        }
    }

    public func exportBrewfile(to url: URL) async {
        let path = url.path
        let code = await executeStreamingCommand(
            title: "Exporting Brewfile to \(url.lastPathComponent)...",
            arguments: ["bundle", "dump", "--force", "--describe", "--file=\(path)"],
            openDrawer: true
        )
        if code == 0 {
            showBanner("Exported Brewfile to \(url.lastPathComponent)")
            if let saved = try? String(contentsOf: url, encoding: .utf8) {
                self.brewfilePreview = saved
            }
        } else {
            showBanner("Failed to export Brewfile")
        }
    }

    public func importBrewfile(from url: URL) async {
        let path = url.path
        let code = await executeStreamingCommand(
            title: "Installing bundle from \(url.lastPathComponent)...",
            arguments: ["bundle", "install", "--file=\(path)"],
            openDrawer: true
        )
        if code == 0 {
            showBanner("Imported Brewfile \(url.lastPathComponent)")
        } else {
            showBanner("Brewfile import finished with code \(code)")
        }
        await refreshPackages()
        await refreshTaps()
    }

    // MARK: - Maintenance & Diagnostics

    public func runDoctor() async {
        let code = await executeStreamingCommand(
            title: "Running brew doctor...",
            arguments: ["doctor"],
            openDrawer: true
        )
        if code == 0 {
            showBanner("Your system is ready to brew")
        } else {
            showBanner("Doctor reported warnings")
        }
        await refreshHealth()
    }

    public func runCleanup(dryRun: Bool) async {
        let args = dryRun ? ["cleanup", "-n"] : ["cleanup", "--prune=all"]
        let title = dryRun ? "Simulating cache cleanup..." : "Cleaning up old versions & cache..."
        let code = await executeStreamingCommand(
            title: title,
            arguments: args,
            openDrawer: true
        )
        if code == 0 {
            showBanner(dryRun ? "Cleanup dry-run complete" : "Cache & old formula versions cleaned")
        }
        await refreshHealth()
    }

    public func runAutoremove() async {
        let code = await executeStreamingCommand(
            title: "Removing unused dependencies...",
            arguments: ["autoremove"],
            openDrawer: true
        )
        if code == 0 {
            showBanner("Unused dependencies removed")
        }
        await refreshPackages()
        await refreshHealth()
    }

    public func clearTerminalLogs() {
        terminalLogs.removeAll()
    }

    public func reverseDependencies(for packageName: String) -> [BrewPackage] {
        installedPackages.filter {
            $0.dependencies.contains(packageName) || $0.runtimeDependencies.contains(packageName)
        }
    }

    // MARK: - Streaming Execution Helper

    @discardableResult
    private func executeStreamingCommand(
        title: String,
        arguments: [String],
        openDrawer: Bool
    ) async -> Int32 {
        guard !isRunningCommand else { return -1 }
        isRunningCommand = true
        commandStartedAt = Date()
        currentCommandTitle = title
        if openDrawer {
            showTerminalDrawer = true
        }

        let cmdDisplay = "$ brew " + arguments.joined(separator: " ")
        appendLog(cmdDisplay, isHeader: true)

        let (output, continuation) = AsyncStream<(String, Bool)>.makeStream()
        let outputTask = Task { @MainActor [weak self] in
            for await (line, isError) in output {
                self?.appendLog(line, isError: isError)
            }
        }
        do {
            let exitCode = try await cli.streamCommand(arguments) { line, isError in
                continuation.yield((line, isError))
            }
            continuation.finish()
            await outputTask.value
            let elapsed = Date().timeIntervalSince(commandStartedAt ?? Date())
            let duration = String(format: "%.1fs", elapsed)
            let statusLine = exitCode == 0
                ? "✓ Completed (\(arguments.first ?? "brew")) in \(duration)"
                : "✗ Exited with code \(exitCode) after \(duration)"
            appendLog(statusLine, isError: exitCode != 0)
            isRunningCommand = false
            currentCommandTitle = ""
            return exitCode
        } catch {
            continuation.finish()
            await outputTask.value
            appendLog("Error: \(error.localizedDescription)", isError: true)
            isRunningCommand = false
            currentCommandTitle = ""
            return -1
        }
    }

    private func appendLog(_ text: String, isError: Bool = false, isHeader: Bool = false) {
        let entry = CommandLogEntry(
            timestamp: Date(),
            text: text,
            isError: isError,
            isCommandHeader: isHeader
        )
        terminalLogs.append(entry)
        if terminalLogs.count > 1000 {
            terminalLogs.removeFirst(terminalLogs.count - 1000)
        }
    }

    private func showBanner(_ message: String) {
        statusBannerMessage = message
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if self?.statusBannerMessage == message {
                self?.statusBannerMessage = nil
            }
        }
    }
}
