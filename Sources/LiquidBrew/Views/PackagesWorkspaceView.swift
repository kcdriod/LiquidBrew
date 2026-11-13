import SwiftUI

public struct PackagesWorkspaceView: View {
    @ObservedObject public var store: BrewStore
    @State private var pendingUninstall: BrewPackage?
    @State private var showUninstall = false
    public init(store: BrewStore) { self.store = store }

    private var selection: Binding<BrewPackage.ID?> {
        Binding(get: { store.selectedPackage?.id }, set: { id in
            store.selectedPackage = store.filteredPackages.first { $0.id == id }
        })
    }
    private var activePackage: BrewPackage? {
        store.filteredPackages.first { $0.id == store.selectedPackage?.id }
    }

    public var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Picker("Show", selection: $store.packageFilter) {
                        ForEach(PackageFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .frame(width: 220)
                    Spacer()
                    Text("\(store.filteredPackages.count) packages")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .glassToolbar()
                Table(store.filteredPackages, selection: selection) {
                    TableColumn("Name") { package in
                        Label(package.name, systemImage: package.isCask ? "app" : "shippingbox")
                    }.width(min: 150, ideal: 200)
                    TableColumn("Version", value: \.version).width(min: 85, ideal: 100)
                    TableColumn("Status") { package in
                        if store.installedSecurityFindings.contains(where: { $0.packageID == package.id }) {
                            Button { store.selectedTab = .security } label: {
                                Label("Review", systemImage: "exclamationmark.shield")
                            }.buttonStyle(.borderless).foregroundStyle(.orange)
                        } else if package.isOutdated {
                            Label("Update", systemImage: "arrow.up.circle").foregroundStyle(.orange)
                        } else if package.isPinned {
                            Label("Pinned", systemImage: "pin")
                        } else {
                            Text(package.isCask ? "Cask" : "Formula").foregroundStyle(.secondary)
                        }
                    }.width(85)
                }
                .scrollContentBackground(.hidden)
                .overlay {
                    if store.isLoading && store.installedPackages.isEmpty {
                        ProgressView("Loading packages…")
                    } else if store.filteredPackages.isEmpty {
                        ContentUnavailableView("No Packages", systemImage: "shippingbox", description: Text("Try another filter or search term."))
                    }
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            Group {
                if let package = activePackage {
                    PackageInspector(package: package, store: store) {
                        pendingUninstall = package
                        showUninstall = true
                    }
                    .id(package.id)
                } else {
                    ContentUnavailableView("Select a Package", systemImage: "shippingbox", description: Text("Choose a package to view its details and dependencies."))
                }
            }
            .frame(minWidth: 300, idealWidth: 340, maxWidth: 440, maxHeight: .infinity)
        }
        .confirmationDialog("Uninstall \(pendingUninstall?.name ?? "package")?", isPresented: $showUninstall, titleVisibility: .visible) {
            if let package = pendingUninstall {
                Button("Uninstall", role: .destructive) { Task { await store.uninstallPackage(package) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Homebrew will remove this package from your Mac.")
        }
    }
}

private struct PackageInspector: View {
    let package: BrewPackage
    @ObservedObject var store: BrewStore
    let uninstall: () -> Void
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label(package.name, systemImage: package.isCask ? "app" : "shippingbox")
                        .font(.title2.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    if let description = package.desc {
                        Text(description).font(.callout)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .liquidGlassCard(cornerRadius: 16)
                .listRowBackground(Color.clear)
            }
            Section("Information") {
                LabeledContent("Kind", value: package.isCask ? "Cask" : "Formula")
                LabeledContent("Installed", value: package.installedVersions.joined(separator: ", "))
                if let latest = package.outdatedVersion { LabeledContent("Latest", value: latest) }
                if let tap = package.tap { LabeledContent("Tap", value: tap) }
                if let license = package.license { LabeledContent("License", value: license) }
                if let date = package.installedTime { LabeledContent("Installed on", value: date.formatted(date: .abbreviated, time: .omitted)) }
                if let homepage = package.homepage, let url = URL(string: homepage) {
                    Link("Website", destination: url)
                }
            }
            Section("Actions") {
                if package.isOutdated {
                    Button("Upgrade Package") { Task { await store.upgradePackage(name: package.name, isCask: package.isCask) } }
                        .buttonStyle(.glassProminent)
                }
                if !package.isCask {
                    Button(package.isPinned ? "Unpin Package" : "Pin Package") { Task { await store.togglePin(package) } }
                    Button("Show Dependency Graph") { store.selectedTab = .graph }
                }
                Button("Uninstall…", role: .destructive, action: uninstall)
            }
            .buttonStyle(.glass)
            .disabled(store.isRunningCommand)
            if let caveats = package.caveats, !caveats.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section("Caveats") { Text(caveats).font(.callout).textSelection(.enabled) }
            }
            dependencySection("Dependencies", names: package.runtimeDependencies.isEmpty ? package.dependencies : package.runtimeDependencies)
            if !package.buildDependencies.isEmpty { dependencySection("Build Dependencies", names: package.buildDependencies) }
            dependencySection("Required By", names: store.reverseDependencies(for: package.name).map(\.name))
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .textSelection(.enabled)
    }
    private func dependencySection(_ title: String, names: [String]) -> some View {
        Section(title) {
            if names.isEmpty { Text("None").foregroundStyle(.secondary) }
            ForEach(names, id: \.self) { name in
                Button(name) {
                    if let match = store.installedPackages.first(where: { $0.name == name || $0.fullName == name }) {
                        store.packageFilter = .all
                        store.searchText = ""
                        store.selectedPackage = match
                    }
                }
                .buttonStyle(.link)
                .disabled(!store.installedPackages.contains { $0.name == name || $0.fullName == name })
            }
        }
    }
}
