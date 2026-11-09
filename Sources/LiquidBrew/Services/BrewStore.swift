import SwiftUI

/// Fallback starter stub for BrewStore so each git worktree compiles independently while agents build their modules.
@MainActor
public final class BrewStore: ObservableObject {
    @Published public var selectedTab: NavigationTab = .packages
    @Published public var packageFilter: PackageFilter = .all
    @Published public var searchText: String = ""
    @Published public var discoverSearchText: String = ""

    @Published public var installedPackages: [BrewPackage] = []
    @Published public var discoverResults: [BrewPackage] = []
    @Published public var outdatedPackages: [OutdatedPackage] = []
    @Published public var services: [BrewServiceItem] = []
    @Published public var taps: [BrewTap] = []
    @Published public var healthReport: BrewHealthReport = BrewHealthReport()

    @Published public var selectedPackage: BrewPackage?
    @Published public var isLoading: Bool = false
    @Published public var isSearchingDiscover: Bool = false
    @Published public var isRunningCommand: Bool = false
    @Published public var currentCommandTitle: String = ""
    @Published public var showTerminalDrawer: Bool = false
    @Published public var terminalLogs: [CommandLogEntry] = []
    @Published public var brewfilePreview: String = ""
    @Published public var statusBannerMessage: String?

    public init() {}

    public var filteredPackages: [BrewPackage] {
        installedPackages.filter { pkg in
            let matchesFilter: Bool
            switch packageFilter {
            case .all: matchesFilter = true
            case .formulae: matchesFilter = !pkg.isCask
            case .casks: matchesFilter = pkg.isCask
            case .leaves: matchesFilter = pkg.isLeaf
            case .pinned: matchesFilter = pkg.isPinned
            case .outdated: matchesFilter = pkg.isOutdated
            }
            guard matchesFilter else { return false }
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return true
            }
            let query = searchText.lowercased()
            return pkg.name.lowercased().contains(query) ||
                (pkg.desc?.lowercased().contains(query) ?? false)
        }
    }

    public func refreshAll() async {}
    public func refreshPackages() async {}
    public func refreshOutdated() async {}
    public func refreshServices() async {}
    public func refreshTaps() async {}
    public func refreshHealth() async {}
    public func searchRemotePackages(query: String) async {}

    public func installPackage(name: String, isCask: Bool) async {}
    public func uninstallPackage(_ package: BrewPackage) async {}
    public func upgradePackage(name: String, isCask: Bool) async {}
    public func upgradeAll() async {}
    public func togglePin(_ package: BrewPackage) async {}
    public func updateHomebrew() async {}

    public func controlService(_ service: BrewServiceItem, action: String) async {}
    public func addTap(name: String) async {}
    public func removeTap(name: String) async {}
    public func generateBrewfilePreview() async {}
    public func exportBrewfile(to url: URL) async {}
    public func importBrewfile(from url: URL) async {}

    public func runDoctor() async {}
    public func runCleanup(dryRun: Bool) async {}
    public func runAutoremove() async {}
    public func clearTerminalLogs() {
        terminalLogs.removeAll()
    }
    public func reverseDependencies(for packageName: String) -> [BrewPackage] {
        installedPackages.filter { $0.dependencies.contains(packageName) || $0.runtimeDependencies.contains(packageName) }
    }
}
