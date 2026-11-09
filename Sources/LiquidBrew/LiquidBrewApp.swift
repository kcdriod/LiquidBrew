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
                .frame(minWidth: 1180, minHeight: 740)
                .background(LiquidMeshBackground())
                .task {
                    await store.refreshAll()
                }
        }
        .defaultSize(width: 1280, height: 800)
        .windowToolbarStyle(.unified(showsTitle: true))
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
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
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
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    public init(store: BrewStore) {
        self.store = store
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            LiquidSidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 215, ideal: 230, max: 260)
        } detail: {
            ZStack(alignment: .bottom) {
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

                if store.showTerminalDrawer {
                    LiveTerminalDrawerView(store: store)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(20)
                }
            }
            .navigationTitle(store.selectedTab.rawValue)
            .navigationSubtitle(store.selectedTab.subtitle)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if store.isRunningCommand {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text(store.currentCommandTitle.isEmpty ? "Working…" : store.currentCommandTitle)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .glassEffect(.regular, in: Capsule())
                    } else if let status = store.statusBannerMessage {
                        Text(status)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .glassEffect(.regular, in: Capsule())
                    }

                    Button {
                        Task { await store.updateHomebrew() }
                    } label: {
                        Label("Update Index", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .help("Run brew update")
                    .disabled(store.isRunningCommand)

                    Button {
                        Task { await store.refreshAll() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .help("Refresh Homebrew packages and status")
                    .disabled(store.isLoading)

                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                            store.showTerminalDrawer.toggle()
                        }
                    } label: {
                        Label("Console", systemImage: "terminal")
                    }
                    .help("Toggle Live Brew Console (⌥⌘T)")
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

struct LiquidSidebarView: View {
    @ObservedObject var store: BrewStore

    var body: some View {
        List(selection: $store.selectedTab) {
            Section("Library") {
                sidebarItem(for: .packages)
                sidebarItem(for: .discover)
                sidebarItem(for: .updates)
            }

            Section("System & Tools") {
                sidebarItem(for: .services)
                sidebarItem(for: .graph)
                sidebarItem(for: .taps)
                sidebarItem(for: .health)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    SidebarMetricCapsule(
                        title: "Formulae",
                        count: store.installedPackages.filter { !$0.isCask }.count,
                        tint: .cyan
                    )
                    SidebarMetricCapsule(
                        title: "Casks",
                        count: store.installedPackages.filter { $0.isCask }.count,
                        tint: .indigo
                    )
                    SidebarMetricCapsule(
                        title: "Updates",
                        count: store.outdatedPackages.count,
                        tint: store.outdatedPackages.isEmpty ? .green : .orange
                    )
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
    }

    @ViewBuilder
    private func sidebarItem(for tab: NavigationTab) -> some View {
        NavigationLink(value: tab) {
            Label {
                Text(tab.rawValue)
                    .font(.system(size: 13, weight: .medium))
            } icon: {
                Image(systemName: tab.iconName)
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .badge(badgeCount(for: tab) ?? 0)
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

struct SidebarMetricCapsule: View {
    let title: String
    let count: Int
    let tint: Color

    var body: some View {
        VStack(spacing: 1) {
            Text("\(count)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.primary)
            Text(title)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Color.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .glassEffect(.regular.tint(tint.opacity(0.18)), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
