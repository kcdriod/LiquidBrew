import SwiftUI
import AppKit

@main
struct LiquidBrewApp: App {
    @StateObject private var store = BrewStore()

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup("LiquidBrew") {
            MainContentView(store: store)
                .frame(minWidth: 1080, minHeight: 720)
                .background(LiquidMeshBackground())
                .task {
                    await store.refreshAll()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Brew") {
                Button("Refresh All Status") {
                    Task { await store.refreshAll() }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Update Homebrew Index") {
                    Task { await store.updateHomebrew() }
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])

                Divider()

                Button("Upgrade All Outdated") {
                    Task { await store.upgradeAll() }
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])

                Divider()

                Button("Toggle Live Terminal Drawer") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        store.showTerminalDrawer.toggle()
                    }
                }
                .keyboardShortcut("t", modifiers: [.command, .option])
            }
        }
    }
}

public struct MainContentView: View {
    @ObservedObject public var store: BrewStore

    public init(store: BrewStore) {
        self.store = store
    }

    public var body: some View {
        NavigationSplitView {
            LiquidSidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 235, ideal: 255, max: 290)
        } detail: {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    TopGlassHeaderBar(store: store)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                    Group {
                        switch store.selectedTab {
                        case .packages:
                            PackagesWorkspaceView(store: store)
                        case .discover:
                            DiscoverWorkspaceView(store: store)
                        case .updates:
                            UpdatesCenterView(store: store)
                        case .services:
                            ServicesDashboardView(store: store)
                        case .graph:
                            DependencyGraphView(store: store)
                        case .taps:
                            TapsBrewfileView(store: store)
                        case .health:
                            HealthCleanupView(store: store)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if store.showTerminalDrawer {
                    LiveTerminalDrawerView(store: store)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(20)
                }
            }
        }
    }
}

struct LiquidSidebarView: View {
    @ObservedObject var store: BrewStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // App Brand Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.cyan.opacity(0.85), .blue.opacity(0.65), .indigo.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 38, height: 38)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(.white.opacity(0.45), lineWidth: 1)
                        )
                        .shadow(color: .cyan.opacity(0.35), radius: 8, x: 0, y: 4)

                    Image(systemName: "mug.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("LiquidBrew")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text(store.healthReport.brewVersion)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 18)

            // Stats summary pill
            HStack(spacing: 8) {
                SidebarStatPill(
                    label: "Formulae",
                    value: "\(store.installedPackages.filter { !$0.isCask }.count)",
                    color: .cyan
                )
                SidebarStatPill(
                    label: "Casks",
                    value: "\(store.installedPackages.filter { $0.isCask }.count)",
                    color: .purple
                )
                SidebarStatPill(
                    label: "Outdated",
                    value: "\(store.outdatedPackages.count)",
                    color: store.outdatedPackages.isEmpty ? .green : .orange
                )
            }
            .padding(.horizontal, 12)

            Divider()
                .overlay(Color.white.opacity(0.08))
                .padding(.horizontal, 12)

            // Navigation items
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(NavigationTab.allCases) { tab in
                        SidebarNavRow(
                            tab: tab,
                            isSelected: store.selectedTab == tab,
                            badgeCount: badgeCount(for: tab)
                        ) {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                store.selectedTab = tab
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
            }

            Spacer()

            // Live Activity & Terminal Toggle Footer
            VStack(spacing: 8) {
                if store.isRunningCommand {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(store.currentCommandTitle.isEmpty ? "Running brew..." : store.currentCommandTitle)
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(10)
                    .liquidGlassCard(cornerRadius: 12, tint: .cyan)
                }

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        store.showTerminalDrawer.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.cyan)
                        Text("Live Brew Console")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                        Spacer()
                        if !store.terminalLogs.isEmpty {
                            Text("\(store.terminalLogs.count)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.cyan.opacity(0.2)))
                        }
                        Image(systemName: store.showTerminalDrawer ? "chevron.down" : "chevron.up")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .liquidGlassCard(cornerRadius: 12, tint: store.showTerminalDrawer ? .cyan : nil, isInteractive: true)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
        }
        .background(VisualEffectBlur(material: .sidebar, blendingMode: .behindWindow))
    }

    private func badgeCount(for tab: NavigationTab) -> Int? {
        switch tab {
        case .packages:
            return store.installedPackages.isEmpty ? nil : store.installedPackages.count
        case .updates:
            return store.outdatedPackages.isEmpty ? nil : store.outdatedPackages.count
        case .services:
            let running = store.services.filter { $0.status == .started }.count
            return running > 0 ? running : nil
        case .taps:
            return store.taps.isEmpty ? nil : store.taps.count
        default:
            return nil
        }
    }
}

struct SidebarStatPill: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .liquidGlassCard(cornerRadius: 10, tint: color)
    }
}

struct SidebarNavRow: View {
    let tab: NavigationTab
    let isSelected: Bool
    let badgeCount: Int?
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: tab.iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : .cyan)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isSelected ? Color.cyan.opacity(0.85) : Color.cyan.opacity(0.14))
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(tab.rawValue)
                        .font(.system(size: 13, weight: isSelected ? .bold : .medium, design: .rounded))
                        .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.85))
                    Text(tab.subtitle)
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if let badgeCount {
                    Text("\(badgeCount)")
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .foregroundStyle(isSelected ? .white : .cyan)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isSelected ? Color.cyan.opacity(0.6) : Color.cyan.opacity(0.15))
                        )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.cyan.opacity(0.16))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [.white.opacity(0.55), .cyan.opacity(0.45)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.1
                                )
                        )
                        .shadow(color: .cyan.opacity(0.18), radius: 8, x: 0, y: 3)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

struct TopGlassHeaderBar: View {
    @ObservedObject var store: BrewStore

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Image(systemName: store.selectedTab.iconName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.cyan)
                    Text(store.selectedTab.rawValue)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                }
                Text(store.selectedTab.subtitle)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let status = store.statusBannerMessage {
                GlassBadge(status, icon: "sparkles", color: .mint)
                    .transition(.opacity)
            }

            GlassPillButton("Brew Update", icon: "arrow.triangle.2.circlepath", tint: .cyan, isDisabled: store.isRunningCommand) {
                Task { await store.updateHomebrew() }
            }

            GlassPillButton("Refresh", icon: "arrow.clockwise", tint: .indigo, isDisabled: store.isLoading) {
                Task { await store.refreshAll() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .liquidGlassCard(cornerRadius: 16)
    }
}
