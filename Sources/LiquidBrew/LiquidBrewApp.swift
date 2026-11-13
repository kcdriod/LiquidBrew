import SwiftUI
import AppKit

@main
struct LiquidBrewApp: App {
    @StateObject private var store = BrewStore()

    init() { NSWindow.allowsAutomaticWindowTabbing = false }

    var body: some Scene {
        WindowGroup("LiquidBrew") {
            MainContentView(store: store)
                .frame(minWidth: 980, minHeight: 620)
                .task {
                    await store.refreshAll()
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .seconds(6 * 60 * 60)) }
                        catch { break }
                        await store.refreshPackages()
                    }
                }
        }
        .defaultSize(width: 1180, height: 760)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Brew") {
                Button("Refresh") { Task { await store.refreshAll() } }
                    .keyboardShortcut("r")
                    .disabled(store.isLoading)
                Button("Update Homebrew Index") { Task { await store.updateHomebrew() } }
                    .keyboardShortcut("u", modifiers: [.command, .shift])
                    .disabled(store.isRunningCommand)
                Button("Upgrade All Outdated Packages") { Task { await store.upgradeAll() } }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                    .disabled(store.isRunningCommand || store.outdatedPackages.isEmpty)
                Divider()
                Toggle("Show Console", isOn: $store.showTerminalDrawer)
                    .keyboardShortcut("t", modifiers: [.command, .option])
            }
        }
    }
}

public struct MainContentView: View {
    @ObservedObject public var store: BrewStore
    public init(store: BrewStore) { self.store = store }

    public var body: some View {
        NavigationSplitView {
            List(selection: Binding<NavigationTab?>(
                get: { store.selectedTab },
                set: { if let tab = $0 { store.selectedTab = tab } }
            )) {
                Section("Library") {
                    navigationRow(.packages)
                    navigationRow(.discover)
                    navigationRow(.updates)
                }
                Section("Manage") {
                    navigationRow(.services)
                    navigationRow(.graph)
                    navigationRow(.taps)
                    navigationRow(.health)
                    navigationRow(.security)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
            .safeAreaInset(edge: .bottom) {
                Text("\(store.installedPackages.count) installed packages")
                    .font(.footnote)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .glassEffect()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        } detail: {
            workspaceContainer
            .background { GlassWorkspaceBackground() }
            .navigationTitle(store.selectedTab.rawValue)
            .modifier(WorkspaceSearchModifier(text: $store.searchText, tab: store.selectedTab))
            .onChange(of: store.selectedTab) { _, _ in store.searchText = "" }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { Task { await store.refreshAll() } } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .help("Refresh (⌘R)")
                    .disabled(store.isLoading)
                    Toggle(isOn: $store.showTerminalDrawer) {
                        Label("Console", systemImage: "sidebar.right")
                    }
                    .help("Toggle Console (⌥⌘T)")
                    Menu {
                        Button("Update Homebrew Index") { Task { await store.updateHomebrew() } }
                        Button("Upgrade All Outdated Packages") { Task { await store.upgradeAll() } }
                            .disabled(store.outdatedPackages.isEmpty)
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                    .disabled(store.isRunningCommand)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if !store.installedSecurityFindings.isEmpty && store.selectedTab != .security {
                    HStack {
                        Label("Security reports match \(Set(store.installedSecurityFindings.map(\.packageID)).count) installed package(s)", systemImage: "exclamationmark.shield")
                        Spacer()
                        Button("Review Reports") { store.selectedTab = .security }
                    }
                    .font(.callout)
                    .glassToolbar()
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if store.isRunningCommand || store.isLoading || store.statusBannerMessage != nil {
                    HStack(spacing: 8) {
                        if store.isRunningCommand || store.isLoading {
                            ProgressView().controlSize(.small)
                        }
                        Text(store.isRunningCommand ? store.currentCommandTitle : (store.statusBannerMessage ?? "Refreshing Homebrew…"))
                            .lineLimit(1)
                        Spacer()
                    }
                    .font(.footnote)
                    .glassToolbar()
                }
            }
            .inspector(isPresented: $store.showTerminalDrawer) {
                ConsolePanelView(store: store)
                    .inspectorColumnWidth(min: 320, ideal: 420, max: 760)
            }
        }
    }

    // Keep the window on screen when the console leaves less room for wide workspaces.
    // Each workspace retains its own split panes; only the available viewport shrinks.
    private var workspaceContainer: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                workspace
                    .frame(width: max(geometry.size.width, minimumWorkspaceWidth), height: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
    }

    private var minimumWorkspaceWidth: CGFloat {
        switch store.selectedTab {
        case .packages: return 730
        case .discover: return 620
        case .graph: return 710
        case .taps: return 650
        default: return 480
        }
    }

    @ViewBuilder private var workspace: some View {
        switch store.selectedTab {
        case .packages: PackagesWorkspaceView(store: store)
        case .discover: DiscoverWorkspaceView(store: store)
        case .updates: UpdatesCenterView(store: store)
        case .services: ServicesDashboardView(store: store)
        case .graph: DependencyGraphView(store: store)
        case .taps: TapsBrewfileView(store: store)
        case .health: HealthCleanupView(store: store)
        case .security: SecurityCenterView(store: store)
        }
    }

    private func navigationRow(_ tab: NavigationTab) -> some View {
        NavigationLink(value: tab) {
            Label(tab.rawValue, systemImage: tab.iconName)
                .badge(tab == .updates ? store.outdatedPackages.count : (tab == .security ? store.installedSecurityFindings.count : 0))
        }
    }
}

private struct WorkspaceSearchModifier: ViewModifier {
    @Binding var text: String
    let tab: NavigationTab
    @ViewBuilder func body(content: Content) -> some View {
        if tab == .discover { content }
        else { content.searchable(text: $text, placement: .toolbar, prompt: "Search \(tab.rawValue.lowercased())") }
    }
}
