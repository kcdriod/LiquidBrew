import SwiftUI
import AppKit

// MARK: - Packages Workspace View

public struct PackagesWorkspaceView: View {
    @ObservedObject public var store: BrewStore
    @FocusState private var isSearchFocused: Bool
    @State private var showUninstallConfirm: Bool = false
    @State private var packagePendingUninstall: BrewPackage?

    public init(store: BrewStore) {
        self.store = store
    }

    private var activePackage: BrewPackage? {
        if let selected = store.selectedPackage {
            // Keep synced with latest version in installedPackages if available
            return store.installedPackages.first(where: { $0.id == selected.id }) ?? selected
        }
        return store.filteredPackages.first ?? store.installedPackages.first
    }

    public var body: some View {
        HStack(spacing: 16) {
            // Left / Center Pane: Search, Filters & Package Cards
            VStack(spacing: 12) {
                searchAndFilterHeader

                if store.isLoading && store.installedPackages.isEmpty {
                    loadingPlaceholder
                } else if store.filteredPackages.isEmpty {
                    emptyPackagesState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(store.filteredPackages) { pkg in
                                PackageListRowCard(
                                    package: pkg,
                                    isSelected: activePackage?.id == pkg.id,
                                    isRunningCommand: store.isRunningCommand,
                                    onSelect: {
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                                            store.selectedPackage = pkg
                                        }
                                    },
                                    onUpgrade: {
                                        Task { await store.upgradePackage(name: pkg.name, isCask: pkg.isCask) }
                                    },
                                    onTogglePin: {
                                        Task { await store.togglePin(pkg) }
                                    },
                                    onInspect: {
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                                            store.selectedPackage = pkg
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 2)
                        .padding(.bottom, 16)
                    }
                }
            }
            .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)

            // Right Inspector Pane: Detailed Package Inspector
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
            .frame(width: 390)
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 16)
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
                    Text("Warning: \(dependents.map(\.name).joined(separator: ", ")) depend on \(pkg.name). Uninstalling it may break those packages.")
                }
            }
        }
    }

    // MARK: - Search & Filter Header

    private var searchAndFilterHeader: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSearchFocused ? Color.cyan : Color.secondary)

                TextField("Search installed formulae, casks, or descriptions...", text: $store.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5, weight: .medium, design: .rounded))
                    .focused($isSearchFocused)

                if !store.searchText.isEmpty {
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            store.searchText = ""
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                }

                Divider()
                    .frame(height: 16)
                    .overlay(Color.white.opacity(0.12))

                Text("\(store.filteredPackages.count) shown")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .liquidGlassCard(cornerRadius: 14, tint: isSearchFocused ? .cyan : nil)

            // Filter Pills Bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PackageFilter.allCases) { filter in
                        FilterPillItem(
                            filter: filter,
                            count: count(for: filter),
                            isSelected: store.packageFilter == filter
                        ) {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                store.packageFilter = filter
                            }
                        }
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
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
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(.cyan)
            Text("Scanning Homebrew Cellar & Caskroom...")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Text("Inspecting installed formulae, casks, leaves, and dependency trees.")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(Color.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .liquidGlassCard(cornerRadius: 18, tint: .cyan)
    }

    private var emptyPackagesState: some View {
        VStack(spacing: 14) {
            Image(systemName: store.installedPackages.isEmpty ? "shippingbox" : "magnifyingglass")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(Color.cyan.opacity(0.8))

            Text(store.installedPackages.isEmpty ? "No Installed Packages Found" : "No Matching Packages")
                .font(.system(size: 16, weight: .bold, design: .rounded))

            Text(
                store.installedPackages.isEmpty
                    ? "Explore the Discover tab to install popular developer tools and casks."
                    : "Try clearing your search query or switching the active filter pill."
            )
            .font(.system(size: 12.5, design: .rounded))
            .foregroundStyle(Color.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 320)

            HStack(spacing: 10) {
                if !store.searchText.isEmpty || store.packageFilter != .all {
                    GlassPillButton("Reset Filters", icon: "arrow.counterclockwise", tint: .cyan) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            store.searchText = ""
                            store.packageFilter = .all
                        }
                    }
                }
                GlassPillButton("Explore Discover", icon: "sparkles", tint: .purple, isProminent: true) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        store.selectedTab = .discover
                    }
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .liquidGlassCard(cornerRadius: 18)
    }

    private var emptyInspectorState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color.secondary)
            Text("Select a Package")
                .font(.system(size: 15, weight: .bold, design: .rounded))
            Text("Click any formula or cask on the left to inspect its metadata, caveats, and dependency tree.")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .liquidGlassCard(cornerRadius: 18)
    }
}

// MARK: - Filter Pill Component

private struct FilterPillItem: View {
    let filter: PackageFilter
    let count: Int
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    private var filterIcon: String {
        switch filter {
        case .all: return "square.grid.2x2.fill"
        case .formulae: return "terminal.fill"
        case .casks: return "macwindow"
        case .leaves: return "leaf.fill"
        case .pinned: return "pin.fill"
        case .outdated: return "arrow.up.circle.fill"
        }
    }

    private var accentColor: Color {
        switch filter {
        case .all: return .cyan
        case .formulae: return .cyan
        case .casks: return .purple
        case .leaves: return .mint
        case .pinned: return .yellow
        case .outdated: return .orange
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: filterIcon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : accentColor)

                Text(filter.rawValue)
                    .font(.system(size: 12, weight: isSelected ? .bold : .medium, design: .rounded))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)

                Text("\(count)")
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .foregroundStyle(isSelected ? Color.white : accentColor)
                    .background(
                        Capsule(style: .continuous)
                            .fill(isSelected ? Color.white.opacity(0.22) : accentColor.opacity(0.15))
                    )
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6.5)
            .background {
                ZStack {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)

                    Capsule(style: .continuous)
                        .fill(
                            isSelected
                                ? LinearGradient(
                                    colors: [accentColor.opacity(0.85), accentColor.opacity(0.55)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                : LinearGradient(
                                    colors: [
                                        accentColor.opacity(isHovered ? 0.18 : 0.08),
                                        Color.clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                        )

                    Capsule(style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.white.opacity(0.55) : accentColor.opacity(isHovered ? 0.45 : 0.22),
                            lineWidth: 1
                        )
                }
            }
            .shadow(color: isSelected ? accentColor.opacity(0.28) : Color.clear, radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Package List Row Card

private struct PackageListRowCard: View {
    let package: BrewPackage
    let isSelected: Bool
    let isRunningCommand: Bool
    let onSelect: () -> Void
    let onUpgrade: () -> Void
    let onTogglePin: () -> Void
    let onInspect: () -> Void

    @State private var isHovered: Bool = false

    private var cardAccent: Color {
        if package.isOutdated { return .orange }
        return package.isCask ? .purple : .cyan
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 13) {
                // Formula / Cask Icon Badge
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    cardAccent.opacity(isSelected ? 0.85 : 0.24),
                                    cardAccent.opacity(isSelected ? 0.55 : 0.10)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 42, height: 42)
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(cardAccent.opacity(isSelected ? 0.8 : 0.35), lineWidth: 1)
                        )

                    Image(systemName: package.isCask ? "macwindow" : "terminal.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white : cardAccent)
                }

                // Package Name, Badges & Description
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text(package.name)
                            .font(.system(size: 14.5, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)

                        // Version Pill
                        Text("v\(package.version)")
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .foregroundStyle(package.isCask ? Color.purple : Color.cyan)
                            .background(
                                Capsule(style: .continuous)
                                    .fill((package.isCask ? Color.purple : Color.cyan).opacity(0.14))
                            )

                        if package.isOutdated {
                            GlassBadge(
                                package.outdatedVersion.map { "→ \($0)" } ?? "Update",
                                icon: "arrow.up.circle.fill",
                                color: .orange
                            )
                        }

                        if package.isPinned {
                            GlassBadge("Pinned", icon: "lock.fill", color: .yellow)
                        }

                        if package.isLeaf {
                            GlassBadge("Leaf", icon: "leaf.fill", color: .mint)
                        }
                    }

                    Text(package.desc ?? (package.isCask ? "macOS GUI Application Cask" : "Homebrew Formula Package"))
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                // Quick Hover Action Buttons
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
                            GlassPillButton(
                                "",
                                icon: package.isPinned ? "pin.slash.fill" : "pin.fill",
                                tint: package.isPinned ? .yellow : .secondary,
                                isDisabled: isRunningCommand,
                                action: onTogglePin
                            )
                            .help(package.isPinned ? "Unpin Formula" : "Pin Formula Version")
                        }

                        GlassPillButton(
                            "",
                            icon: "info.circle.fill",
                            tint: cardAccent,
                            action: onInspect
                        )
                        .help("Inspect Package Details")
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else {
                    GlassBadge(
                        package.isCask ? "Cask" : "Formula",
                        color: package.isCask ? .purple : .cyan
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .liquidGlassCard(
                cornerRadius: 14,
                tint: isSelected ? cardAccent : (package.isOutdated ? .orange : nil),
                isInteractive: true
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isSelected ? cardAccent.opacity(0.75) : Color.clear,
                        lineWidth: 1.6
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Right Inspector Pane: Package Detail Inspector

private struct PackageDetailInspectorView: View {
    let package: BrewPackage
    @ObservedObject var store: BrewStore
    let onRequestUninstall: (BrewPackage) -> Void

    private var accentColor: Color {
        package.isCask ? .purple : .cyan
    }

    private var reverseDeps: [BrewPackage] {
        store.reverseDependencies(for: package.name)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                inspectorHeaderCard
                actionControlsBar

                // Description Section
                inspectorSection(title: "Description", icon: "doc.text.fill", tint: accentColor) {
                    Text(package.desc ?? "No description provided by this tap.")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.primary.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Caveats Highlighted in Amber Glass Card
                if let caveats = package.caveats, !caveats.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.orange)
                            Text("Caveats & Post-Install Notes")
                                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.orange)
                        }

                        Text(caveats.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.primary.opacity(0.9))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .liquidGlassCard(cornerRadius: 14, tint: .orange)
                }

                // Dependencies Section (Runtime & Build)
                dependenciesSection

                // Required By (Reverse Dependencies)
                requiredBySection
            }
            .padding(16)
        }
        .liquidGlassCard(cornerRadius: 18)
    }

    // MARK: - Inspector Header

    private var inspectorHeaderCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                // Large Glowing Icon
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.28))
                        .frame(width: 62, height: 62)
                        .blur(radius: 12)

                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [accentColor.opacity(0.85), accentColor.opacity(0.45)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 54, height: 54)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.55), lineWidth: 1.2)
                        )
                        .shadow(color: accentColor.opacity(0.45), radius: 12, x: 0, y: 5)

                    Image(systemName: package.isCask ? "macwindow.badge.plus" : "shippingbox.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(package.name)
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.primary)

                        if package.isPinned {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.yellow)
                                .help("Pinned version")
                        }
                    }

                    Text(package.fullName)
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.secondary)

                    HStack(spacing: 6) {
                        GlassBadge(
                            package.isCask ? "Cask" : "Formula",
                            icon: package.isCask ? "macwindow" : "terminal.fill",
                            color: accentColor
                        )
                        if let tap = package.tap, !tap.isEmpty {
                            GlassBadge(tap, icon: "spigot.fill", color: .indigo)
                        }
                        if let license = package.license, !license.isEmpty {
                            GlassBadge(license, icon: "checkmark.seal.fill", color: .mint)
                        }
                    }
                    .padding(.top, 2)
                }

                Spacer(minLength: 0)
            }

            Divider()
                .overlay(Color.white.opacity(0.1))

            // Version & Installation Metadata Grid
            HStack(spacing: 12) {
                metadataMiniTile(
                    label: "Installed Version",
                    value: package.version,
                    icon: "tag.fill",
                    color: accentColor
                )

                if package.isOutdated, let latest = package.outdatedVersion {
                    metadataMiniTile(
                        label: "Available Update",
                        value: latest,
                        icon: "arrow.up.forward.circle.fill",
                        color: .orange
                    )
                } else {
                    metadataMiniTile(
                        label: "Installed On",
                        value: formattedInstallDate(package.installedTime),
                        icon: "calendar",
                        color: .secondary
                    )
                }
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: 15, tint: accentColor)
    }

    private func metadataMiniTile(label: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.secondary)
                Text(value)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private func formattedInstallDate(_ date: Date?) -> String {
        guard let date else { return "Managed by Brew" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    // MARK: - Action Controls Bar

    private var actionControlsBar: some View {
        VStack(spacing: 8) {
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
                        icon: package.isPinned ? "pin.slash.fill" : "pin.fill",
                        tint: .yellow,
                        isDisabled: store.isRunningCommand
                    ) {
                        Task { await store.togglePin(package) }
                    }
                }

                if let homepage = package.homepage, let url = URL(string: homepage) {
                    GlassPillButton("Homepage", icon: "safari.fill", tint: .cyan) {
                        NSWorkspace.shared.open(url)
                    }
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                GlassPillButton("Dependency Graph", icon: "point.3.connected.trianglepath.dotted", tint: .indigo) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        store.selectedPackage = package
                        store.selectedTab = .graph
                    }
                }

                Spacer(minLength: 0)

                GlassPillButton(
                    "Uninstall",
                    icon: "trash.fill",
                    tint: .red,
                    isDisabled: store.isRunningCommand
                ) {
                    onRequestUninstall(package)
                }
            }
        }
    }

    // MARK: - Dependencies Section

    private var dependenciesSection: some View {
        let runtimeDeps = !package.runtimeDependencies.isEmpty ? package.runtimeDependencies : package.dependencies
        let buildDeps = package.buildDependencies

        return inspectorSection(
            title: "Dependencies (\(runtimeDeps.count + buildDeps.count))",
            icon: "link.circle.fill",
            tint: .cyan
        ) {
            if runtimeDeps.isEmpty && buildDeps.isEmpty {
                Text("Standalone package — no formula dependencies required.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Color.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    if !runtimeDeps.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Runtime Dependencies")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.secondary)

                            FlowLayoutChips(items: runtimeDeps) { depName in
                                dependencyChip(name: depName, isBuild: false)
                            }
                        }
                    }

                    if !buildDeps.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Build Dependencies")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.secondary)

                            FlowLayoutChips(items: buildDeps) { depName in
                                dependencyChip(name: depName, isBuild: true)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Required By Section

    private var requiredBySection: some View {
        inspectorSection(
            title: "Required By (\(reverseDeps.count))",
            icon: "arrow.turn.down.right",
            tint: .mint
        ) {
            if reverseDeps.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.mint)
                    Text("Top-level leaf package — no installed packages depend on \(package.name).")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Color.secondary)
                }
            } else {
                FlowLayoutChips(items: reverseDeps.map(\.name)) { parentName in
                    dependencyChip(name: parentName, isBuild: false)
                }
            }
        }
    }

    private func dependencyChip(name: String, isBuild: Bool) -> some View {
        let installedMatch = store.installedPackages.first { $0.name == name || $0.fullName == name }
        let chipColor: Color = installedMatch != nil ? (isBuild ? .indigo : .cyan) : .secondary

        return Button {
            if let match = installedMatch {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    store.selectedPackage = match
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: installedMatch != nil ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.system(size: 10, weight: .semibold))
                Text(name)
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                if isBuild {
                    Text("build")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.indigo.opacity(0.25)))
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4.5)
            .foregroundStyle(chipColor)
            .background(
                Capsule(style: .continuous)
                    .fill(chipColor.opacity(0.14))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(chipColor.opacity(0.35), lineWidth: 0.8)
                    )
            )
        }
        .buttonStyle(.plain)
        .help(installedMatch != nil ? "Click to inspect \(name)" : "\(name) (not currently installed)")
    }

    private func inspectorSection<Content: View>(
        title: String,
        icon: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.primary)
            }
            content()
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: 14)
    }
}

// MARK: - Wrapping Chip Layout Helper

private struct FlowLayoutChips<ItemView: View>: View {
    let items: [String]
    let content: (String) -> ItemView

    var body: some View {
        // Adaptive grid that wraps nicely inside the 390pt inspector
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 105, maximum: 180), spacing: 6)],
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
    @FocusState private var isHeroSearchFocused: Bool
    @State private var resultFilter: DiscoverResultFilter = .all
    @State private var selectedCategory: String = "All Curated"

    public init(store: BrewStore) {
        self.store = store
    }

    private enum DiscoverResultFilter: String, CaseIterable, Identifiable {
        case all = "All Results"
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

    private let curatedCategories = [
        "All Curated",
        "Modern CLI",
        "Git & DevOps",
        "macOS Apps"
    ]

    private let curatedTools: [CuratedTool] = [
        CuratedTool(name: "ripgrep", category: "Modern CLI", isCask: false, tagline: "Ultra-fast recursive regex search tool (`rg`)", icon: "magnifyingglass.circle.fill"),
        CuratedTool(name: "fd", category: "Modern CLI", isCask: false, tagline: "Simple, fast and user-friendly alternative to `find`", icon: "folder.fill.badge.gearshape"),
        CuratedTool(name: "bat", category: "Modern CLI", isCask: false, tagline: "Clone of `cat` with syntax highlighting and Git integration", icon: "doc.richtext.fill"),
        CuratedTool(name: "jq", category: "Modern CLI", isCask: false, tagline: "Lightweight and flexible command-line JSON processor", icon: "curlybraces.square.fill"),
        CuratedTool(name: "fzf", category: "Modern CLI", isCask: false, tagline: "Command-line fuzzy finder written in Go", icon: "sparkle.magnifyingglass"),
        CuratedTool(name: "htop", category: "Modern CLI", isCask: false, tagline: "Interactive process viewer and system monitor", icon: "waveform.path.ecg"),
        CuratedTool(name: "neovim", category: "Git & DevOps", isCask: false, tagline: "Ambitious Vim-fork focused on extensibility and usability", icon: "chevron.left.forwardslash.chevron.right"),
        CuratedTool(name: "gh", category: "Git & DevOps", isCask: false, tagline: "GitHub’s official command-line tool for PRs & issues", icon: "point.topleft.down.curvedto.point.bottomright.up"),
        CuratedTool(name: "lazygit", category: "Git & DevOps", isCask: false, tagline: "Simple terminal UI for git commands", icon: "arrow.triangle.branch"),
        CuratedTool(name: "tmux", category: "Git & DevOps", isCask: false, tagline: "Terminal multiplexer for persistent split-pane sessions", icon: "rectangle.split.3x1.fill"),
        CuratedTool(name: "ghostty", category: "macOS Apps", isCask: true, tagline: "Fast, feature-rich, native GPU-accelerated terminal emulator", icon: "terminal.fill"),
        CuratedTool(name: "orbstack", category: "macOS Apps", isCask: true, tagline: "Fast, light, easy way to run Docker containers & Linux", icon: "cube.transparent.fill"),
        CuratedTool(name: "raycast", category: "macOS Apps", isCask: true, tagline: "Blazingly fast, extendable launcher for macOS", icon: "command.square.fill"),
        CuratedTool(name: "warp", category: "macOS Apps", isCask: true, tagline: "Rust-based modern terminal with AI and block workflows", icon: "bolt.horizontal.circle.fill"),
        CuratedTool(name: "visual-studio-code", category: "macOS Apps", isCask: true, tagline: "Open-source code editor by Microsoft", icon: "macwindow.badge.plus")
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
        if selectedCategory == "All Curated" {
            return curatedTools
        }
        return curatedTools.filter { $0.category == selectedCategory }
    }

    public var body: some View {
        VStack(spacing: 16) {
            heroSearchBar

            if store.isSearchingDiscover {
                discoverLoadingView
            } else if !store.discoverSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !store.discoverResults.isEmpty {
                searchResultsSection
            } else {
                curatedShowcaseSection
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 16)
    }

    // MARK: - Hero Search Bar

    private var heroSearchBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.cyan.opacity(0.2))
                        .frame(width: 36, height: 36)
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.cyan)
                }

                TextField("Search 14,000+ Homebrew formulae and macOS casks (press Return)...", text: $store.discoverSearchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .focused($isHeroSearchFocused)
                    .onSubmit {
                        triggerRemoteSearch()
                    }

                if !store.discoverSearchText.isEmpty {
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            store.discoverSearchText = ""
                            store.discoverResults = []
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                }

                GlassPillButton(
                    "Search Brew",
                    icon: "magnifyingglass",
                    tint: .cyan,
                    isProminent: true,
                    isDisabled: store.discoverSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isSearchingDiscover
                ) {
                    triggerRemoteSearch()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .liquidGlassCard(cornerRadius: 18, tint: isHeroSearchFocused ? .cyan : .indigo)
        }
    }

    private func triggerRemoteSearch() {
        let query = store.discoverSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        Task {
            await store.searchRemotePackages(query: query)
        }
    }

    // MARK: - Curated Developer Showcase

    private var curatedShowcaseSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Category Chips Header
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Essential Developer Toolkit")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Text("Hand-picked CLI formulae and native macOS casks ready for one-click installation.")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(Color.secondary)
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        ForEach(curatedCategories, id: \.self) { category in
                            let isSelected = selectedCategory == category
                            GlassPillButton(
                                category,
                                icon: categoryIcon(for: category),
                                tint: isSelected ? .cyan : .secondary,
                                isProminent: isSelected
                            ) {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    selectedCategory = category
                                }
                            }
                        }
                    }
                }

                // Grid of Curated Tools
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 290, maximum: 420), spacing: 14)],
                    spacing: 14
                ) {
                    ForEach(filteredCuratedTools) { tool in
                        let isInstalled = store.installedPackages.contains { $0.name == tool.name }
                        CuratedToolGlassCard(
                            name: tool.name,
                            category: tool.category,
                            tagline: tool.tagline,
                            icon: tool.icon,
                            isCask: tool.isCask,
                            isInstalled: isInstalled,
                            isRunningCommand: store.isRunningCommand
                        ) {
                            Task {
                                await store.installPackage(name: tool.name, isCask: tool.isCask)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 18)
        }
    }

    private func categoryIcon(for category: String) -> String {
        switch category {
        case "Modern CLI": return "terminal.fill"
        case "Git & DevOps": return "arrow.triangle.branch"
        case "macOS Apps": return "macwindow"
        default: return "sparkles"
        }
    }

    // MARK: - Remote Search Results Section

    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("Search Results (\(filteredDiscoverResults.count))")
                    .font(.system(size: 15, weight: .bold, design: .rounded))

                Spacer()

                ForEach(DiscoverResultFilter.allCases) { filter in
                    let count = countForDiscoverFilter(filter)
                    GlassPillButton(
                        "\(filter.rawValue) (\(count))",
                        icon: filter == .casks ? "macwindow" : (filter == .formulae ? "terminal.fill" : "square.grid.2x2.fill"),
                        tint: filter == .casks ? .purple : .cyan,
                        isProminent: resultFilter == filter
                    ) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            resultFilter = filter
                        }
                    }
                }
            }

            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 300, maximum: 460), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(filteredDiscoverResults) { result in
                        let isInstalled = store.installedPackages.contains { $0.name == result.name && $0.isCask == result.isCask }
                        DiscoverSearchResultCard(
                            package: result,
                            isInstalled: isInstalled,
                            isRunningCommand: store.isRunningCommand
                        ) {
                            Task {
                                await store.installPackage(name: result.name, isCask: result.isCask)
                            }
                        }
                    }
                }
                .padding(.bottom, 16)
            }
        }
    }

    private func countForDiscoverFilter(_ filter: DiscoverResultFilter) -> Int {
        switch filter {
        case .all: return store.discoverResults.count
        case .formulae: return store.discoverResults.filter { !$0.isCask }.count
        case .casks: return store.discoverResults.filter { $0.isCask }.count
        }
    }

    private var discoverLoadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(.cyan)
            Text("Searching Homebrew Formulae & Casks...")
                .font(.system(size: 15, weight: .bold, design: .rounded))
            Text("Querying `brew search \(store.discoverSearchText)`")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .liquidGlassCard(cornerRadius: 18, tint: .cyan)
    }
}

// MARK: - Curated Tool Card

private struct CuratedToolGlassCard: View {
    let name: String
    let category: String
    let tagline: String
    let icon: String
    let isCask: Bool
    let isInstalled: Bool
    let isRunningCommand: Bool
    let onInstall: () -> Void

    private var accentColor: Color {
        isCask ? .purple : .cyan
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accentColor.opacity(0.2))
                        .frame(width: 42, height: 42)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(accentColor.opacity(0.45), lineWidth: 1)
                        )
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(accentColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(name)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.primary)

                        GlassBadge(isCask ? "Cask" : "Formula", color: accentColor)
                    }

                    Text(category)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.secondary)
                }

                Spacer()

                if isInstalled {
                    GlassBadge("Installed", icon: "checkmark.circle.fill", color: .mint)
                } else {
                    GlassPillButton(
                        "Install",
                        icon: "arrow.down.circle.fill",
                        tint: accentColor,
                        isProminent: true,
                        isDisabled: isRunningCommand,
                        action: onInstall
                    )
                }
            }

            Text(tagline)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(Color.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: 16, tint: isInstalled ? .mint : accentColor, isInteractive: true)
    }
}

// MARK: - Remote Search Result Card

private struct DiscoverSearchResultCard: View {
    let package: BrewPackage
    let isInstalled: Bool
    let isRunningCommand: Bool
    let onInstall: () -> Void

    private var accentColor: Color {
        package.isCask ? .purple : .cyan
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accentColor.opacity(0.18))
                    .frame(width: 38, height: 38)
                Image(systemName: package.isCask ? "macwindow" : "terminal.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accentColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(package.name)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)

                    GlassBadge(package.isCask ? "Cask" : "Formula", color: accentColor)
                }

                Text(package.desc ?? "Available via Homebrew \(package.isCask ? "Caskroom" : "Core")")
                    .font(.system(size: 11.5, design: .rounded))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isInstalled {
                GlassBadge("Installed", icon: "checkmark.circle.fill", color: .mint)
            } else {
                GlassPillButton(
                    "Install",
                    icon: "arrow.down.circle.fill",
                    tint: accentColor,
                    isProminent: true,
                    isDisabled: isRunningCommand,
                    action: onInstall
                )
            }
        }
        .padding(13)
        .liquidGlassCard(cornerRadius: 14, tint: isInstalled ? .mint : accentColor, isInteractive: true)
    }
}
