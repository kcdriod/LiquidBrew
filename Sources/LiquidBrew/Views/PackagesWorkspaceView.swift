import SwiftUI
import AppKit

// MARK: - Packages Workspace View (Clean macOS 26 Liquid Glass Split Layout)

public struct PackagesWorkspaceView: View {
    @ObservedObject public var store: BrewStore
    @State private var showUninstallConfirm: Bool = false
    @State private var packagePendingUninstall: BrewPackage?

    public init(store: BrewStore) {
        self.store = store
    }

    private var activePackage: BrewPackage? {
        if let selected = store.selectedPackage {
            return store.installedPackages.first(where: { $0.id == selected.id }) ?? selected
        }
        return store.filteredPackages.first ?? store.installedPackages.first
    }

    public var body: some View {
        HSplitView {
            // Left Pane: Clean Package List + Native Filter Bar
            VStack(spacing: 0) {
                filterBarHeader
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                Divider()
                    .opacity(0.4)

                if store.isLoading && store.installedPackages.isEmpty {
                    loadingPlaceholder
                } else if store.filteredPackages.isEmpty {
                    emptyPackagesState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(store.filteredPackages) { pkg in
                                PackageListRowCard(
                                    package: pkg,
                                    isSelected: activePackage?.id == pkg.id,
                                    isRunningCommand: store.isRunningCommand,
                                    onSelect: {
                                        withAnimation(.snappy(duration: 0.2)) {
                                            store.selectedPackage = pkg
                                        }
                                    },
                                    onUpgrade: {
                                        Task { await store.upgradePackage(name: pkg.name, isCask: pkg.isCask) }
                                    },
                                    onTogglePin: {
                                        Task { await store.togglePin(pkg) }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                }
            }
            .frame(minWidth: 420, idealWidth: 520, maxWidth: .infinity, maxHeight: .infinity)

            // Right Inspector Pane: Clean Glass Detail Sheet
            Group {
                if let pkg = activePackage {
                    PackageDetailInspectorView(
                        package: pkg,
                        store: store,
                        onRequestUninstall: { target in
                            packagePendingUninstall = target
                            showUninstallConfirm = true
                        }
                    )
                } else {
                    emptyInspectorState
                }
            }
            .frame(minWidth: 340, idealWidth: 390, maxWidth: 450, maxHeight: .infinity)
        }
        .searchable(text: $store.searchText, placement: .toolbar, prompt: "Filter installed packages…")
        .confirmationDialog(
            "Uninstall \(packagePendingUninstall?.name ?? "Package")?",
            isPresented: $showUninstallConfirm,
            titleVisibility: .visible
        ) {
            if let pkg = packagePendingUninstall {
                Button("Uninstall \(pkg.name)", role: .destructive) {
                    Task {
                        await store.uninstallPackage(pkg)
                        if store.selectedPackage?.id == pkg.id {
                            store.selectedPackage = nil
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                packagePendingUninstall = nil
            }
        } message: {
            if let pkg = packagePendingUninstall {
                let dependents = store.reverseDependencies(for: pkg.name)
                if dependents.isEmpty {
                    Text("This will run `brew uninstall \(pkg.isCask ? "--cask " : "")\(pkg.name)` and remove its files from your Mac.")
                } else {
                    Text("Warning: \(dependents.map(\.name).joined(separator: ", ")) depend on \(pkg.name). Uninstalling it may affect those packages.")
                }
            }
        }
    }

    // MARK: - Filter Header

    private var filterBarHeader: some View {
        HStack(spacing: 10) {
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(PackageFilter.allCases) { filter in
                        FilterPillItem(
                            filter: filter,
                            count: count(for: filter),
                            isSelected: store.packageFilter == filter
                        ) {
                            withAnimation(.snappy(duration: 0.2)) {
                                store.packageFilter = filter
                            }
                        }
                    }
                }
            }

            Spacer()

            Text("\(store.filteredPackages.count) packages")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.secondary)
        }
    }

    private func count(for filter: PackageFilter) -> Int {
        switch filter {
        case .all:
            return store.installedPackages.count
        case .formulae:
            return store.installedPackages.filter { !$0.isCask }.count
        case .casks:
            return store.installedPackages.filter { $0.isCask }.count
        case .leaves:
            return store.installedPackages.filter { $0.isLeaf }.count
        case .pinned:
            return store.installedPackages.filter { $0.isPinned }.count
        case .outdated:
            return store.installedPackages.filter { $0.isOutdated }.count
        }
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Loading Homebrew Packages…")
                .font(.system(size: 14, weight: .semibold))
            Text("Inspecting installed formulae, casks, and dependency metadata.")
                .font(.system(size: 12))
                .foregroundStyle(Color.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyPackagesState: some View {
        VStack(spacing: 12) {
            Image(systemName: store.installedPackages.isEmpty ? "shippingbox" : "magnifyingglass")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color.secondary)

            Text(store.installedPackages.isEmpty ? "No Installed Packages" : "No Matching Packages")
                .font(.system(size: 15, weight: .semibold))

            Text(
                store.installedPackages.isEmpty
                    ? "Open Discover to browse and install Homebrew formulae and macOS casks."
                    : "Try clearing your search or selecting a different filter."
            )
            .font(.system(size: 12.5))
            .foregroundStyle(Color.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 300)

            HStack(spacing: 8) {
                if !store.searchText.isEmpty || store.packageFilter != .all {
                    GlassPillButton("Reset Filter", icon: "arrow.counterclockwise") {
                        store.searchText = ""
                        store.packageFilter = .all
                    }
                }
                GlassPillButton("Open Discover", icon: "sparkles", isProminent: true) {
                    store.selectedTab = .discover
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyInspectorState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color.secondary)
            Text("No Package Selected")
                .font(.system(size: 14, weight: .semibold))
            Text("Select a formula or cask from the list to inspect its details and dependencies.")
                .font(.system(size: 12))
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Native Liquid Glass Filter Pill

private struct FilterPillItem: View {
    let filter: PackageFilter
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    private var shortTitle: String {
        switch filter {
        case .leaves: return "Leaves"
        default: return filter.rawValue
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(shortTitle)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                Text("\(count)")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule()
                            .fill(Color.primary.opacity(isSelected ? 0.14 : 0.06))
                    )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassEffect(
                isSelected ? .regular.tint(Color.accentColor.opacity(0.32)).interactive() : .regular.interactive(),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Clean Package Row Card

private struct PackageListRowCard: View {
    let package: BrewPackage
    let isSelected: Bool
    let isRunningCommand: Bool
    let onSelect: () -> Void
    let onUpgrade: () -> Void
    let onTogglePin: () -> Void

    @State private var isHovered: Bool = false

    private var symbolTint: Color {
        if package.isOutdated { return .orange }
        return package.isCask ? .indigo : .cyan
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Clean Icon Container
                Image(systemName: package.isCask ? "macwindow" : "terminal")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(symbolTint)
                    .frame(width: 34, height: 34)
                    .glassEffect(.regular.tint(symbolTint.opacity(0.18)), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                // Title & Subtitle
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(package.name)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)

                        Text(package.version)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color.secondary)

                        if package.isOutdated {
                            GlassBadge(
                                package.outdatedVersion.map { "→ \($0)" } ?? "Update",
                                icon: "arrow.up.circle.fill",
                                color: .orange
                            )
                        }

                        if package.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.orange)
                                .help("Pinned")
                        }

                        if package.isLeaf && !package.isCask {
                            Text("Leaf")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.primary.opacity(0.06)))
                        }
                    }

                    Text(package.desc ?? (package.isCask ? "macOS Application Cask" : "Homebrew Formula"))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                // Right-side status or quick actions on hover
                if isHovered || isSelected {
                    HStack(spacing: 6) {
                        if package.isOutdated {
                            GlassPillButton(
                                "Upgrade",
                                icon: "arrow.up.circle.fill",
                                tint: .orange,
                                isProminent: true,
                                isDisabled: isRunningCommand,
                                action: onUpgrade
                            )
                        }

                        if !package.isCask {
                            Button(action: onTogglePin) {
                                Image(systemName: package.isPinned ? "pin.slash" : "pin")
                                    .font(.system(size: 11.5))
                            }
                            .buttonStyle(.glass)
                            .disabled(isRunningCommand)
                            .help(package.isPinned ? "Unpin Formula" : "Pin Formula")
                        }
                    }
                } else {
                    Text(package.isCask ? "Cask" : "Formula")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .glassEffect(
                isSelected
                    ? .regular.tint(Color.accentColor.opacity(0.26)).interactive()
                    : (isHovered ? .regular.interactive() : .identity),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .background {
                if !isSelected && !isHovered {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.03))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Right Inspector Pane

private struct PackageDetailInspectorView: View {
    let package: BrewPackage
    @ObservedObject var store: BrewStore
    let onRequestUninstall: (BrewPackage) -> Void

    private var accentColor: Color {
        package.isCask ? .indigo : .cyan
    }

    private var reverseDeps: [BrewPackage] {
        store.reverseDependencies(for: package.name)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Header Section
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: package.isCask ? "macwindow" : "shippingbox.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(accentColor)
                            .frame(width: 52, height: 52)
                            .glassEffect(.regular.tint(accentColor.opacity(0.22)), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(package.name)
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(Color.primary)

                                if package.isPinned {
                                    GlassBadge("Pinned", icon: "pin.fill", color: .orange)
                                }
                            }

                            Text(package.fullName)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Color.secondary)

                            HStack(spacing: 6) {
                                GlassBadge(package.isCask ? "Cask" : "Formula", color: accentColor)
                                if let tap = package.tap, !tap.isEmpty {
                                    GlassBadge(tap, color: .secondary)
                                }
                                if let license = package.license, !license.isEmpty {
                                    GlassBadge(license, color: .secondary)
                                }
                            }
                            .padding(.top, 2)
                        }
                        Spacer(minLength: 0)
                    }

                    if let desc = package.desc, !desc.isEmpty {
                        Text(desc)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.primary.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Primary Actions Row
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            if package.isOutdated {
                                GlassPillButton(
                                    "Upgrade",
                                    icon: "arrow.up.circle.fill",
                                    tint: .orange,
                                    isProminent: true,
                                    isDisabled: store.isRunningCommand
                                ) {
                                    Task { await store.upgradePackage(name: package.name, isCask: package.isCask) }
                                }
                            }

                            if !package.isCask {
                                GlassPillButton(
                                    package.isPinned ? "Unpin" : "Pin",
                                    icon: package.isPinned ? "pin.slash" : "pin",
                                    tint: .secondary,
                                    isDisabled: store.isRunningCommand
                                ) {
                                    Task { await store.togglePin(package) }
                                }

                                GlassPillButton("Graph", icon: "point.3.connected.trianglepath.dotted", tint: .secondary) {
                                    store.selectedPackage = package
                                    store.selectedTab = .graph
                                }
                            }

                            if let homepage = package.homepage, let url = URL(string: homepage) {
                                GlassPillButton("Website", icon: "safari", tint: .secondary) {
                                    NSWorkspace.shared.open(url)
                                }
                            }

                            Spacer(minLength: 0)

                            GlassPillButton(
                                "Uninstall",
                                icon: "trash",
                                tint: .red,
                                isDisabled: store.isRunningCommand
                            ) {
                                onRequestUninstall(package)
                            }
                        }
                    }
                }
                .padding(16)
                .liquidGlassCard(cornerRadius: 16)

                // Key Metadata Grid
                HStack(spacing: 10) {
                    inspectorMetricBox(title: "Installed", value: package.version)
                    if package.isOutdated, let latest = package.outdatedVersion {
                        inspectorMetricBox(title: "Latest", value: latest, valueColor: .orange)
                    } else {
                        inspectorMetricBox(title: "Installed Date", value: formattedInstallDate(package.installedTime))
                    }
                }

                // Caveats Section
                if let caveats = package.caveats, !caveats.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Caveats", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Color.orange)

                        Text(caveats.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(Color.primary.opacity(0.9))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .liquidGlassCard(cornerRadius: 14, tint: .orange)
                }

                // Dependencies
                dependenciesSection

                // Required By
                requiredBySection
            }
            .padding(16)
        }
    }

    private func inspectorMetricBox(title: String, value: String, valueColor: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(valueColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .liquidGlassCard(cornerRadius: 12)
    }

    private func formattedInstallDate(_ date: Date?) -> String {
        guard let date else { return "Homebrew" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private var dependenciesSection: some View {
        let runtimeDeps = !package.runtimeDependencies.isEmpty ? package.runtimeDependencies : package.dependencies
        let buildDeps = package.buildDependencies

        return VStack(alignment: .leading, spacing: 10) {
            Text("Dependencies (\(runtimeDeps.count + buildDeps.count))")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color.secondary)

            if runtimeDeps.isEmpty && buildDeps.isEmpty {
                Text("No formula dependencies required.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    if !runtimeDeps.isEmpty {
                        FlowLayoutChips(items: runtimeDeps) { depName in
                            dependencyChip(name: depName, isBuild: false)
                        }
                    }
                    if !buildDeps.isEmpty {
                        Text("Build Only")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.secondary)
                        FlowLayoutChips(items: buildDeps) { depName in
                            dependencyChip(name: depName, isBuild: true)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: 14)
    }

    private var requiredBySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Required By (\(reverseDeps.count))")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color.secondary)

            if reverseDeps.isEmpty {
                Text("Top-level leaf package — nothing depends on \(package.name).")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondary)
            } else {
                FlowLayoutChips(items: reverseDeps.map(\.name)) { parentName in
                    dependencyChip(name: parentName, isBuild: false)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: 14)
    }

    private func dependencyChip(name: String, isBuild: Bool) -> some View {
        let installedMatch = store.installedPackages.first { $0.name == name || $0.fullName == name }

        return Button {
            if let match = installedMatch {
                store.selectedPackage = match
            }
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(installedMatch != nil ? Color.green : Color.secondary)
                    .frame(width: 6, height: 6)
                Text(name)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .glassEffect(.regular.interactive(), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct FlowLayoutChips<ItemView: View>: View {
    let items: [String]
    let content: (String) -> ItemView

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 100, maximum: 170), spacing: 6)],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(items, id: \.self) { item in
                content(item)
            }
        }
    }
}

// MARK: - Discover Workspace View

public struct DiscoverWorkspaceView: View {
    @ObservedObject public var store: BrewStore
    @State private var resultFilter: DiscoverResultFilter = .all
    @State private var selectedCategory: String = "All"

    public init(store: BrewStore) {
        self.store = store
    }

    private enum DiscoverResultFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case formulae = "Formulae"
        case casks = "Casks"
        var id: String { rawValue }
    }

    private struct CuratedTool: Identifiable {
        var id: String { name }
        let name: String
        let category: String
        let isCask: Bool
        let tagline: String
        let icon: String
    }

    private let curatedCategories = ["All", "CLI Utilities", "Git & DevOps", "macOS Apps"]

    private let curatedTools: [CuratedTool] = [
        CuratedTool(name: "ripgrep", category: "CLI Utilities", isCask: false, tagline: "Fast recursive regex search (`rg`)", icon: "magnifyingglass"),
        CuratedTool(name: "fd", category: "CLI Utilities", isCask: false, tagline: "Fast and user-friendly alternative to `find`", icon: "folder"),
        CuratedTool(name: "bat", category: "CLI Utilities", isCask: false, tagline: "Clone of `cat` with syntax highlighting", icon: "doc.text"),
        CuratedTool(name: "jq", category: "CLI Utilities", isCask: false, tagline: "Command-line JSON processor", icon: "curlybraces"),
        CuratedTool(name: "fzf", category: "CLI Utilities", isCask: false, tagline: "Command-line fuzzy finder", icon: "text.magnifyingglass"),
        CuratedTool(name: "htop", category: "CLI Utilities", isCask: false, tagline: "Interactive process viewer", icon: "waveform.path.ecg"),
        CuratedTool(name: "neovim", category: "Git & DevOps", isCask: false, tagline: "Extensible Vim-based text editor", icon: "chevron.left.forwardslash.chevron.right"),
        CuratedTool(name: "gh", category: "Git & DevOps", isCask: false, tagline: "GitHub official command-line tool", icon: "terminal"),
        CuratedTool(name: "lazygit", category: "Git & DevOps", isCask: false, tagline: "Terminal UI for git commands", icon: "arrow.triangle.branch"),
        CuratedTool(name: "tmux", category: "Git & DevOps", isCask: false, tagline: "Terminal multiplexer", icon: "rectangle.split.3x1"),
        CuratedTool(name: "ghostty", category: "macOS Apps", isCask: true, tagline: "Fast native GPU-accelerated terminal", icon: "terminal.fill"),
        CuratedTool(name: "orbstack", category: "macOS Apps", isCask: true, tagline: "Fast, light Docker containers & Linux VM", icon: "cube.transparent"),
        CuratedTool(name: "raycast", category: "macOS Apps", isCask: true, tagline: "Extendable launcher for macOS", icon: "command"),
        CuratedTool(name: "warp", category: "macOS Apps", isCask: true, tagline: "Modern Rust-based terminal", icon: "bolt.horizontal"),
        CuratedTool(name: "visual-studio-code", category: "macOS Apps", isCask: true, tagline: "Code editor by Microsoft", icon: "macwindow")
    ]

    private var filteredDiscoverResults: [BrewPackage] {
        store.discoverResults.filter { pkg in
            switch resultFilter {
            case .all: return true
            case .formulae: return !pkg.isCask
            case .casks: return pkg.isCask
            }
        }
    }

    private var filteredCuratedTools: [CuratedTool] {
        if selectedCategory == "All" { return curatedTools }
        return curatedTools.filter { $0.category == selectedCategory }
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Search Bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.secondary)

                TextField("Search Homebrew formulae and casks (press Return)…", text: $store.discoverSearchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .onSubmit {
                        triggerRemoteSearch()
                    }

                if !store.discoverSearchText.isEmpty {
                    Button {
                        store.discoverSearchText = ""
                        store.discoverResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                }

                GlassPillButton(
                    "Search",
                    icon: "arrow.right.circle.fill",
                    isProminent: true,
                    isDisabled: store.discoverSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isSearchingDiscover
                ) {
                    triggerRemoteSearch()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .liquidGlassCard(cornerRadius: 14)
            .padding(.horizontal, 20)
            .padding(.top, 12)

            if store.isSearchingDiscover {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Searching Homebrew…")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !store.discoverSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !store.discoverResults.isEmpty {
                searchResultsSection
            } else {
                curatedShowcaseSection
            }
        }
    }

    private func triggerRemoteSearch() {
        let query = store.discoverSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        Task { await store.searchRemotePackages(query: query) }
    }

    private var curatedShowcaseSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Popular Developer Tools")
                        .font(.system(size: 15, weight: .semibold))

                    Spacer()

                    Picker("Category", selection: $selectedCategory) {
                        ForEach(curatedCategories, id: \.self) { category in
                            Text(category).tag(category)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 360)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 270, maximum: 380), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(filteredCuratedTools) { tool in
                        let isInstalled = store.installedPackages.contains { $0.name == tool.name }
                        HStack(spacing: 12) {
                            Image(systemName: tool.icon)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(tool.isCask ? Color.indigo : Color.cyan)
                                .frame(width: 36, height: 36)
                                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(tool.name)
                                        .font(.system(size: 13.5, weight: .semibold))
                                    Text(tool.isCask ? "Cask" : "Formula")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(Color.secondary)
                                }
                                Text(tool.tagline)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Color.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            if isInstalled {
                                GlassBadge("Installed", icon: "checkmark", color: .green)
                            } else {
                                GlassPillButton("Install", isProminent: true, isDisabled: store.isRunningCommand) {
                                    Task { await store.installPackage(name: tool.name, isCask: tool.isCask) }
                                }
                            }
                        }
                        .padding(12)
                        .liquidGlassCard(cornerRadius: 12, isInteractive: true)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(filteredDiscoverResults.count) Results")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Picker("Filter", selection: $resultFilter) {
                    ForEach(DiscoverResultFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
            }
            .padding(.horizontal, 20)

            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 280, maximum: 420), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(filteredDiscoverResults) { result in
                        let isInstalled = store.installedPackages.contains { $0.name == result.name && $0.isCask == result.isCask }
                        HStack(spacing: 12) {
                            Image(systemName: result.isCask ? "macwindow" : "terminal")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(result.isCask ? Color.indigo : Color.cyan)
                                .frame(width: 34, height: 34)
                                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(result.name)
                                        .font(.system(size: 13.5, weight: .semibold))
                                        .lineLimit(1)
                                    Text(result.isCask ? "Cask" : "Formula")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color.secondary)
                                }
                                Text(result.desc ?? "Homebrew package")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Color.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            if isInstalled {
                                GlassBadge("Installed", icon: "checkmark", color: .green)
                            } else {
                                GlassPillButton("Install", isProminent: true, isDisabled: store.isRunningCommand) {
                                    Task { await store.installPackage(name: result.name, isCask: result.isCask) }
                                }
                            }
                        }
                        .padding(12)
                        .liquidGlassCard(cornerRadius: 12, isInteractive: true)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
    }
}
