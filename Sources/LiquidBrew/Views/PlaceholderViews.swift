import SwiftUI

public struct PackagesWorkspaceView: View {
    @ObservedObject public var store: BrewStore
    public init(store: BrewStore) { self.store = store }
    public var body: some View { Text("Packages Workspace") }
}

public struct DiscoverWorkspaceView: View {
    @ObservedObject public var store: BrewStore
    public init(store: BrewStore) { self.store = store }
    public var body: some View { Text("Discover Workspace") }
}

public struct UpdatesCenterView: View {
    @ObservedObject public var store: BrewStore
    public init(store: BrewStore) { self.store = store }
    public var body: some View { Text("Updates Center") }
}

public struct ServicesDashboardView: View {
    @ObservedObject public var store: BrewStore
    public init(store: BrewStore) { self.store = store }
    public var body: some View { Text("Services Dashboard") }
}

public struct DependencyGraphView: View {
    @ObservedObject public var store: BrewStore
    public init(store: BrewStore) { self.store = store }
    public var body: some View { Text("Dependency Graph") }
}

public struct TapsBrewfileView: View {
    @ObservedObject public var store: BrewStore
    public init(store: BrewStore) { self.store = store }
    public var body: some View { Text("Taps & Brewfile") }
}

public struct HealthCleanupView: View {
    @ObservedObject public var store: BrewStore
    public init(store: BrewStore) { self.store = store }
    public var body: some View { Text("Health & Cleanup") }
}

public struct LiveTerminalDrawerView: View {
    @ObservedObject public var store: BrewStore
    public init(store: BrewStore) { self.store = store }
    public var body: some View { Text("Terminal Drawer") }
}
