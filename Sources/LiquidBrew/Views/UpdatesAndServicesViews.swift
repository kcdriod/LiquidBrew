import SwiftUI
import AppKit

public struct UpdatesCenterView: View {
    @ObservedObject public var store: BrewStore
    private var search: String { store.searchText }
    public init(store: BrewStore) { self.store = store }
    private var packages: [OutdatedPackage] {
        store.outdatedPackages.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }
    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(store.outdatedPackages.count) updates available").font(.headline)
                Spacer()
                Button("Check for Updates") { Task { await store.updateHomebrew() } }
                    .buttonStyle(.glass)
                Button("Upgrade All") { Task { await store.upgradeAll() } }
                    .buttonStyle(.glassProminent)
                    .disabled(store.outdatedPackages.isEmpty)
            }
            .disabled(store.isRunningCommand)
            .glassToolbar()
            if store.outdatedPackages.isEmpty {
                ContentUnavailableView("Up to Date", systemImage: "checkmark.circle", description: Text("No outdated packages were found in the last check."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(packages) { package in
                    HStack(spacing: 12) {
                        Image(systemName: package.isCask ? "app" : "shippingbox").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(package.name).fontWeight(.medium)
                            Text("\(package.installedVersions.joined(separator: ", ")) → \(package.currentVersion)")
                                .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        Spacer()
                        if package.isPinned {
                            Label("Pinned", systemImage: "pin").foregroundStyle(.secondary)
                        }
                        Button("Upgrade") { Task { await store.upgradePackage(name: package.name, isCask: package.isCask) } }
                            .buttonStyle(.glass)
                            .disabled(store.isRunningCommand || package.isPinned)
                    }.padding(.vertical, 6)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .overlay {
                    if packages.isEmpty { ContentUnavailableView.search(text: search) }
                }
            }
        }
    }
}

public struct ServicesDashboardView: View {
    @ObservedObject public var store: BrewStore
    private var search: String { store.searchText }
    public init(store: BrewStore) { self.store = store }
    private var services: [BrewServiceItem] {
        store.services.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
    }
    public var body: some View {
        Table(services) {
            TableColumn("Service", value: \.name).width(min: 130, ideal: 180)
            TableColumn("Status") { service in
                Label(service.status.displayTitle, systemImage: service.status == .started ? "circle.fill" : "circle")
                    .foregroundStyle(service.status.color)
            }.width(110)
            TableColumn("User") { Text($0.user ?? "—") }.width(min: 70, ideal: 110)
            TableColumn("Actions") { service in
                HStack {
                    Button(service.status == .started ? "Stop" : "Start") {
                        Task { await store.controlService(service, action: service.status == .started ? "stop" : "start") }
                    }
                    Button("Restart") { Task { await store.controlService(service, action: "restart") } }
                        .disabled(service.status != .started)
                }.buttonStyle(.glass).controlSize(.small).disabled(store.isRunningCommand)
            }.width(180)
        }
        .scrollContentBackground(.hidden)
        .overlay {
            if store.services.isEmpty {
                ContentUnavailableView("No Services", systemImage: "gearshape.2", description: Text("Installed Homebrew services appear here."))
            } else if services.isEmpty { ContentUnavailableView.search(text: search) }
        }
    }
}
