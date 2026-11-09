import SwiftUI
import AppKit

// MARK: - Outdated & Upgrades Center

public struct UpdatesCenterView: View {
    @ObservedObject public var store: BrewStore

    @State private var searchQuery: String = ""
    @State private var selectedScope: OutdatedScope = .all
    @State private var lastCheckedAt: Date = Date()

    public enum OutdatedScope: String, CaseIterable, Identifiable {
        case all = "All Outdated"
        case formulae = "Formulae"
        case casks = "Casks"
        case pinned = "Pinned"

        public var id: String { rawValue }
    }

    public init(store: BrewStore) {
        self.store = store
    }

    private var filteredOutdatedPackages: [OutdatedPackage] {
        store.outdatedPackages.filter { pkg in
            let matchesScope: Bool
            switch selectedScope {
            case .all:
                matchesScope = true
            case .formulae:
                matchesScope = !pkg.isCask
            case .casks:
                matchesScope = pkg.isCask
            case .pinned:
                matchesScope = pkg.isPinned
            }
            guard matchesScope else { return false }

            let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !trimmed.isEmpty else { return true }
            return pkg.name.lowercased().contains(trimmed) ||
                pkg.currentVersion.lowercased().contains(trimmed) ||
                pkg.installedVersions.joined(separator: " ").lowercased().contains(trimmed)
        }
    }

    private var unpinnedOutdatedCount: Int {
        store.outdatedPackages.filter { !$0.isPinned }.count
    }

    private var formulaOutdatedCount: Int {
        store.outdatedPackages.filter { !$0.isCask }.count
    }

    private var caskOutdatedCount: Int {
        store.outdatedPackages.filter { $0.isCask }.count
    }

    public var body: some View {
        VStack(spacing: 16) {
            updatesHeroBanner
                .padding(.horizontal, 20)

            if !store.outdatedPackages.isEmpty {
                updatesFilterBar
                    .padding(.horizontal, 20)
            }

            if store.outdatedPackages.isEmpty {
                celebratoryUpToDateState
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            } else if filteredOutdatedPackages.isEmpty {
                emptyFilteredOutdatedState
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredOutdatedPackages) { pkg in
                            OutdatedPackageCard(
                                package: pkg,
                                isBusy: store.isRunningCommand
                            ) {
                                Task {
                                    store.showTerminalDrawer = true
                                    await store.upgradePackage(name: pkg.name, isCask: pkg.isCask)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
                }
            }
        }
        .padding(.top, 6)
    }

    private var updatesHeroBanner: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: store.outdatedPackages.isEmpty
                                ? [Color.mint.opacity(0.45), Color.green.opacity(0.10)]
                                : [Color.cyan.opacity(0.45), Color.orange.opacity(0.15)],
                            center: .center,
                            startRadius: 4,
                            endRadius: 34
                        )
                    )
                    .frame(width: 60, height: 60)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                store.outdatedPackages.isEmpty ? Color.mint.opacity(0.5) : Color.cyan.opacity(0.5),
                                lineWidth: 1.2
                            )
                    )
                    .shadow(
                        color: (store.outdatedPackages.isEmpty ? Color.mint : Color.cyan).opacity(0.3),
                        radius: 12,
                        x: 0,
                        y: 4
                    )

                Image(systemName: store.outdatedPackages.isEmpty ? "checkmark.seal.fill" : "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(store.outdatedPackages.isEmpty ? Color.mint : Color.cyan)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 10) {
                    Text(
                        store.outdatedPackages.isEmpty
                            ? "All Packages Are Up to Date"
                            : "\(store.outdatedPackages.count) Outdated \(store.outdatedPackages.count == 1 ? "Package" : "Packages") Available"
                    )
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.primary)

                    if !store.outdatedPackages.isEmpty {
                        GlassBadge("\(formulaOutdatedCount) Formulae", icon: "terminal.fill", color: .cyan)
                        GlassBadge("\(caskOutdatedCount) Casks", icon: "macwindow", color: .purple)
                    }
                }

                Text(
                    store.outdatedPackages.isEmpty
                        ? "Your Homebrew formulae and casks are running the latest upstream releases."
                        : "Review version diffs below or upgrade all \(unpinnedOutdatedCount) unpinned packages in a single batch."
                )
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundStyle(Color.secondary)
            }

            Spacer()

            HStack(spacing: 10) {
                GlassPillButton(
                    "Check for Updates",
                    icon: "arrow.triangle.2.circlepath",
                    tint: .cyan,
                    isDisabled: store.isRunningCommand
                ) {
                    Task {
                        await store.updateHomebrew()
                        await store.refreshOutdated()
                        lastCheckedAt = Date()
                    }
                }

                GlassPillButton(
                    "Upgrade All (\(store.outdatedPackages.count))",
                    icon: "arrow.up.circle.fill",
                    tint: .mint,
                    isProminent: !store.outdatedPackages.isEmpty,
                    isDisabled: store.outdatedPackages.isEmpty || store.isRunningCommand
                ) {
                    Task {
                        store.showTerminalDrawer = true
                        await store.upgradeAll()
                        lastCheckedAt = Date()
                    }
                }
            }
        }
        .padding(18)
        .liquidGlassCard(
            cornerRadius: 20,
            tint: store.outdatedPackages.isEmpty ? .mint : .cyan
        )
    }

    private var updatesFilterBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(OutdatedScope.allCases) { scope in
                    let isSelected = selectedScope == scope
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            selectedScope = scope
                        }
                    } label: {
                        Text(scope.rawValue)
                            .font(.system(size: 12, weight: isSelected ? .bold : .medium, design: .rounded))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .foregroundStyle(isSelected ? Color.white : Color.secondary)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(isSelected ? Color.cyan.opacity(0.55) : Color.white.opacity(0.05))
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .strokeBorder(
                                                isSelected ? Color.white.opacity(0.45) : Color.white.opacity(0.12),
                                                lineWidth: 0.9
                                            )
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.secondary)

                TextField("Filter outdated packages...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .frame(width: 210)

                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .liquidGlassCard(cornerRadius: 12)
        }
    }

    private var celebratoryUpToDateState: some View {
        VStack(spacing: 18) {
            Spacer()

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.mint.opacity(0.32), Color.cyan.opacity(0.12), Color.clear],
                            center: .center,
                            startRadius: 8,
                            endRadius: 80
                        )
                    )
                    .frame(width: 150, height: 150)

                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.mint.opacity(0.75), Color.cyan.opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                    .frame(width: 92, height: 92)
                    .shadow(color: Color.mint.opacity(0.35), radius: 16, x: 0, y: 6)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.mint, Color.cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 6) {
                Text("All Packages Up to Date")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.primary)

                Text("Every installed formula and cask is on its latest available version.")
                    .font(.system(size: 13.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.secondary)
            }

            HStack(spacing: 12) {
                GlassBadge(
                    "Last Checked \(lastCheckedAt.formatted(date: .omitted, time: .shortened))",
                    icon: "clock.badge.checkmark.fill",
                    color: .mint
                )
                GlassBadge(
                    "\(store.installedPackages.count) Installed Verified",
                    icon: "checkmark.shield.fill",
                    color: .cyan
                )
            }

            GlassPillButton(
                "Sync Homebrew Index Now",
                icon: "arrow.triangle.2.circlepath",
                tint: .cyan,
                isProminent: true,
                isDisabled: store.isRunningCommand
            ) {
                Task {
                    await store.updateHomebrew()
                    await store.refreshOutdated()
                    lastCheckedAt = Date()
                }
            }
            .padding(.top, 4)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .liquidGlassCard(cornerRadius: 24, tint: .mint)
    }

    private var emptyFilteredOutdatedState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Color.cyan)
            Text("No Matching Outdated Packages")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Color.primary)
            Text("Try clearing your search query or switching the filter scope.")
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundStyle(Color.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .liquidGlassCard(cornerRadius: 20)
    }
}

private struct OutdatedPackageCard: View {
    let package: OutdatedPackage
    let isBusy: Bool
    let onUpgrade: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Left icon badge
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: package.isCask
                                ? [Color.purple.opacity(0.38), Color.indigo.opacity(0.22)]
                                : [Color.cyan.opacity(0.38), Color.blue.opacity(0.22)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                (package.isCask ? Color.purple : Color.cyan).opacity(0.45),
                                lineWidth: 1
                            )
                    )

                Image(systemName: package.isCask ? "macwindow.badge.plus" : "shippingbox.and.arrow.backward.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(package.isCask ? Color.purple : Color.cyan)
            }

            // Package details & badges
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(package.name)
                        .font(.system(size: 15.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.primary)

                    GlassBadge(
                        package.isCask ? "Cask" : "Formula",
                        icon: package.isCask ? "macwindow" : "terminal.fill",
                        color: package.isCask ? .purple : .cyan
                    )

                    if package.isPinned {
                        GlassBadge(
                            package.pinnedVersion.map { "Pinned (\($0))" } ?? "Pinned",
                            icon: "pin.fill",
                            color: .yellow
                        )
                    }
                }

                // Version transition pill
                HStack(spacing: 8) {
                    Text(package.installedVersions.joined(separator: ", "))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.orange.opacity(0.14))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(Color.orange.opacity(0.35), lineWidth: 0.8)
                                )
                        )

                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.secondary)

                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .bold))
                        Text(package.currentVersion)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(Color.mint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.mint.opacity(0.16))
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(Color.cyan.opacity(0.45), lineWidth: 0.9)
                            )
                    )
                    .shadow(color: Color.mint.opacity(0.25), radius: 6, x: 0, y: 2)
                }
            }

            Spacer()

            // Individual Upgrade Action
            GlassPillButton(
                package.isPinned ? "Pinned" : "Upgrade",
                icon: package.isPinned ? "lock.fill" : "arrow.up.circle.fill",
                tint: package.isPinned ? .orange : .mint,
                isProminent: !package.isPinned,
                isDisabled: isBusy || package.isPinned,
                action: onUpgrade
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .liquidGlassCard(
            cornerRadius: 16,
            tint: package.isPinned ? .orange : .cyan,
            isInteractive: true
        )
    }
}

// MARK: - Brew Services Dashboard

public struct ServicesDashboardView: View {
    @ObservedObject public var store: BrewStore

    @State private var selectedFilter: ServiceFilterOption = .all
    @State private var searchQuery: String = ""

    public enum ServiceFilterOption: String, CaseIterable, Identifiable {
        case all = "All"
        case running = "Running"
        case stopped = "Stopped"
        case error = "Error"

        public var id: String { rawValue }
    }

    public init(store: BrewStore) {
        self.store = store
    }

    private var runningCount: Int {
        store.services.filter { $0.status == .started }.count
    }

    private var stoppedCount: Int {
        store.services.filter { $0.status == .stopped || $0.status == .none }.count
    }

    private var errorCount: Int {
        store.services.filter { $0.status == .error || $0.status == .unknown }.count
    }

    private var filteredServices: [BrewServiceItem] {
        store.services.filter { service in
            let matchesFilter: Bool
            switch selectedFilter {
            case .all:
                matchesFilter = true
            case .running:
                matchesFilter = service.status == .started
            case .stopped:
                matchesFilter = service.status == .stopped || service.status == .none
            case .error:
                matchesFilter = service.status == .error || service.status == .unknown
            }
            guard matchesFilter else { return false }

            let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !query.isEmpty else { return true }
            return service.name.lowercased().contains(query) ||
                (service.user?.lowercased().contains(query) ?? false) ||
                (service.file?.lowercased().contains(query) ?? false)
        }
    }

    public var body: some View {
        VStack(spacing: 16) {
            servicesSummaryHeader
                .padding(.horizontal, 20)

            servicesFilterBar
                .padding(.horizontal, 20)

            if store.services.isEmpty {
                emptyServicesState
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            } else if filteredServices.isEmpty {
                noMatchingServicesState
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [
                            GridItem(.adaptive(minimum: 340, maximum: 560), spacing: 14)
                        ],
                        spacing: 14
                    ) {
                        ForEach(filteredServices) { service in
                            BrewServiceCardView(
                                service: service,
                                isBusy: store.isRunningCommand,
                                onToggleStartStop: {
                                    Task {
                                        let action = service.status == .started ? "stop" : "start"
                                        await store.controlService(service, action: action)
                                    }
                                },
                                onRestart: {
                                    Task {
                                        await store.controlService(service, action: "restart")
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
                }
            }
        }
        .padding(.top, 6)
    }

    private var servicesSummaryHeader: some View {
        HStack(spacing: 14) {
            ServiceCounterCard(
                title: "Running",
                count: runningCount,
                icon: "bolt.horizontal.circle.fill",
                color: .green
            )

            ServiceCounterCard(
                title: "Stopped",
                count: stoppedCount,
                icon: "pause.circle.fill",
                color: .secondary
            )

            ServiceCounterCard(
                title: "Error",
                count: errorCount,
                icon: "exclamationmark.triangle.fill",
                color: errorCount > 0 ? .red : .mint
            )

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                GlassPillButton(
                    "Refresh Services",
                    icon: "arrow.clockwise",
                    tint: .cyan,
                    isProminent: true,
                    isDisabled: store.isLoading || store.isRunningCommand
                ) {
                    Task {
                        await store.refreshServices()
                    }
                }

                Text("\(store.services.count) registered launchctl daemons")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.secondary)
            }
        }
        .padding(16)
        .liquidGlassCard(cornerRadius: 20, tint: .cyan)
    }

    private var servicesFilterBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(ServiceFilterOption.allCases) { option in
                    let isSelected = selectedFilter == option
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            selectedFilter = option
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(filterDotColor(for: option))
                                .frame(width: 7, height: 7)
                            Text(option.rawValue)
                                .font(.system(size: 12, weight: isSelected ? .bold : .medium, design: .rounded))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .foregroundStyle(isSelected ? Color.white : Color.secondary)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isSelected ? Color.cyan.opacity(0.55) : Color.white.opacity(0.05))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(
                                            isSelected ? Color.white.opacity(0.45) : Color.white.opacity(0.12),
                                            lineWidth: 0.9
                                        )
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.secondary)

                TextField("Search services, user, or plist...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .frame(width: 230)

                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .liquidGlassCard(cornerRadius: 12)
        }
    }

    private func filterDotColor(for option: ServiceFilterOption) -> Color {
        switch option {
        case .all: return .cyan
        case .running: return .green
        case .stopped: return .secondary
        case .error: return .red
        }
    }

    private var emptyServicesState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "gearshape.2.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(Color.cyan)
            Text("No Homebrew Services Found")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color.primary)
            Text("Install formulae that include background launchd plists (such as postgresql, redis, nginx, or dnsmasq) to manage them here.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)

            GlassPillButton("Refresh Services", icon: "arrow.clockwise", tint: .cyan, isProminent: true) {
                Task { await store.refreshServices() }
            }
            .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .liquidGlassCard(cornerRadius: 22)
    }

    private var noMatchingServicesState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Color.cyan)
            Text("No Services Match Filter")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Color.primary)
            Text("Try switching the status filter or clearing the search bar.")
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundStyle(Color.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .liquidGlassCard(cornerRadius: 20)
    }
}

private struct ServiceCounterCard: View {
    let title: String
    let count: Int
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.18))
                    .frame(width: 38, height: 38)
                    .overlay(
                        Circle()
                            .strokeBorder(color.opacity(0.45), lineWidth: 1)
                    )
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("\(count)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.primary)
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .liquidGlassCard(cornerRadius: 14, tint: color)
    }
}

private struct BrewServiceCardView: View {
    let service: BrewServiceItem
    let isBusy: Bool
    let onToggleStartStop: () -> Void
    let onRestart: () -> Void

    private var isRunning: Bool {
        service.status == .started
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Top row: Glowing status orb, service name, status badge
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(service.status.color.opacity(0.26))
                        .frame(width: 28, height: 28)
                    Circle()
                        .fill(service.status.color)
                        .frame(width: 11, height: 11)
                        .shadow(color: service.status.color.opacity(0.85), radius: isRunning ? 8 : 3, x: 0, y: 0)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(service.name)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.primary)
                    Text(service.status.displayTitle)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(service.status.color)
                }

                Spacer()

                // Metadata badges
                HStack(spacing: 6) {
                    if let pid = service.pid, isRunning {
                        GlassBadge("PID \(pid)", icon: "waveform.path.ecg", color: .green)
                    }

                    if let user = service.user, !user.isEmpty {
                        GlassBadge(user, icon: "person.fill", color: .cyan)
                    }

                    if let exitCode = service.exitCode, exitCode != 0 {
                        GlassBadge("Exit \(exitCode)", icon: "exclamationmark.octagon.fill", color: .red)
                    }
                }
            }

            Divider()
                .overlay(Color.white.opacity(0.08))

            // Plist path & Reveal in Finder button
            HStack(spacing: 8) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)

                if let file = service.file, !file.isEmpty {
                    Text(file)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Button {
                        let expandedPath = (file as NSString).expandingTildeInPath
                        let fileURL = URL(fileURLWithPath: expandedPath)
                        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 10.5, weight: .semibold))
                            Text("Reveal")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(Color.cyan)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.cyan.opacity(0.12))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(Color.cyan.opacity(0.32), lineWidth: 0.8)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Reveal launchd plist in Finder")
                } else {
                    Text("No active launchd plist file generated")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.secondary)
                    Spacer()
                }
            }

            // Action Buttons
            HStack(spacing: 10) {
                GlassPillButton(
                    isRunning ? "Stop" : "Start",
                    icon: isRunning ? "stop.fill" : "play.fill",
                    tint: isRunning ? .orange : .green,
                    isProminent: !isRunning,
                    isDisabled: isBusy,
                    action: onToggleStartStop
                )

                GlassPillButton(
                    "Restart",
                    icon: "arrow.clockwise",
                    tint: .cyan,
                    isDisabled: isBusy,
                    action: onRestart
                )

                Spacer()
            }
        }
        .padding(16)
        .liquidGlassCard(
            cornerRadius: 18,
            tint: isRunning ? .green : (service.status == .error ? .red : nil),
            isInteractive: true
        )
    }
}

// MARK: - Live Terminal Console Drawer

public struct LiveTerminalDrawerView: View {
    @ObservedObject public var store: BrewStore

    @State private var drawerHeight: CGFloat = 250
    @State private var isCollapsed: Bool = false
    @State private var didCopyFlash: Bool = false

    private let minDrawerHeight: CGFloat = 150
    private let maxDrawerHeight: CGFloat = 520

    public init(store: BrewStore) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Drag resize handle bar
            resizeHandleBar

            // Console Header Bar
            consoleHeaderBar

            if !isCollapsed {
                Divider()
                    .overlay(Color.white.opacity(0.1))

                // Streaming Monospaced Log Output
                consoleTranscriptArea
                    .frame(height: drawerHeight)
            }
        }
        .liquidGlassCard(cornerRadius: 20, tint: .cyan)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .shadow(color: Color.black.opacity(0.45), radius: 22, x: 0, y: -4)
    }

    private var resizeHandleBar: some View {
        HStack {
            Spacer()
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.28))
                .frame(width: 42, height: 4)
                .padding(.top, 7)
                .padding(.bottom, 3)
            Spacer()
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { value in
                    if isCollapsed {
                        isCollapsed = false
                    }
                    let proposed = drawerHeight - value.translation.height
                    drawerHeight = min(max(proposed, minDrawerHeight), maxDrawerHeight)
                }
        )
    }

    private var consoleHeaderBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                if store.isRunningCommand {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.cyan)
                } else {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.cyan)
                }

                Text(
                    store.isRunningCommand
                        ? (store.currentCommandTitle.isEmpty ? "Executing Brew Command..." : store.currentCommandTitle)
                        : (store.currentCommandTitle.isEmpty ? "Live Brew Console" : store.currentCommandTitle)
                )
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color.primary)
                .lineLimit(1)

                GlassBadge(
                    "\(store.terminalLogs.count) \(store.terminalLogs.count == 1 ? "line" : "lines")",
                    icon: "text.alignleft",
                    color: .cyan
                )
            }

            Spacer()

            HStack(spacing: 8) {
                GlassPillButton(
                    isCollapsed ? "Expand" : "Minimize",
                    icon: isCollapsed ? "chevron.up" : "chevron.down",
                    tint: .cyan
                ) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                        isCollapsed.toggle()
                    }
                }

                GlassPillButton(
                    didCopyFlash ? "Copied!" : "Copy Logs",
                    icon: didCopyFlash ? "checkmark" : "doc.on.doc",
                    tint: didCopyFlash ? .mint : .cyan,
                    isDisabled: store.terminalLogs.isEmpty
                ) {
                    copyLogsToPasteboard()
                }

                GlassPillButton(
                    "Clear",
                    icon: "trash",
                    tint: .orange,
                    isDisabled: store.terminalLogs.isEmpty
                ) {
                    store.clearTerminalLogs()
                }

                GlassPillButton(
                    "Close",
                    icon: "xmark",
                    tint: .secondary
                ) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        store.showTerminalDrawer = false
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var consoleTranscriptArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if store.terminalLogs.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "sparkles.rectangle.stack")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(Color.secondary)
                        Text("Ready for Homebrew commands. Real-time stdout and stderr lines stream here.")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: drawerHeight - 24)
                    .padding()
                } else {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(store.terminalLogs) { entry in
                            ConsoleLogLineView(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(Color.black.opacity(0.32))
            .onChange(of: store.terminalLogs.count) { _, _ in
                if let lastID = store.terminalLogs.last?.id {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func copyLogsToPasteboard() {
        let joined = store.terminalLogs.map { entry in
            let timeStr = entry.timestamp.formatted(date: .omitted, time: .standard)
            return "[\(timeStr)] \(entry.text)"
        }.joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(joined, forType: .string)

        withAnimation {
            didCopyFlash = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                didCopyFlash = false
            }
        }
    }
}

private struct ConsoleLogLineView: View {
    let entry: CommandLogEntry

    private var lineColor: Color {
        if entry.isCommandHeader {
            return Color.cyan
        } else if entry.isError {
            return Color.orange
        } else {
            return Color.mint.opacity(0.95)
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.secondary.opacity(0.75))

            if entry.isCommandHeader {
                Image(systemName: "chevron.right.square.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.cyan)
            } else if entry.isError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.orange)
            }

            Text(entry.text)
                .font(
                    .system(
                        size: 12,
                        weight: entry.isCommandHeader ? .bold : .regular,
                        design: .monospaced
                    )
                )
                .foregroundStyle(lineColor)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, entry.isCommandHeader ? 3 : 0.5)
    }
}
