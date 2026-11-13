import SwiftUI

struct SecurityCenterView: View {
    @ObservedObject var store: BrewStore
    @State private var pendingRemoval: BrewPackage?
    @State private var showRemoval = false

    private var findings: [SecurityFinding] {
        let query = store.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.installedSecurityFindings.filter { finding in
            query.isEmpty || finding.title.localizedCaseInsensitiveContains(query) || finding.packageID.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Package Security", systemImage: "shield.lefthalf.filled").font(.title2.bold())
                        Text("Checks at startup, after package changes and every six hours while LiquidBrew is open.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Check Now", systemImage: "arrow.clockwise") {
                        Task { await store.refreshPackages(); await store.refreshSecurity() }
                    }
                    .disabled(store.isCheckingSecurity || store.isLoading)
                    if store.isCheckingSecurity { ProgressView().controlSize(.small) }
                }
                Text("News matches are leads for review, not confirmation that your installed version is malicious. Available feed headlines from the last 90 days are checked by package name; short or ambiguous names are skipped. Homebrew warnings cover official taps only. No matches does not guarantee safety, and removed packages may no longer appear in Homebrew’s metadata.")
                    .font(.callout).foregroundStyle(.secondary)
                Toggle("Notify me about new matching reports", isOn: Binding(
                    get: { store.securityNotificationsEnabled },
                    set: { enabled in Task { await store.setSecurityNotifications(enabled) } }
                ))
                if let message = store.notificationMessage { Text(message).font(.callout).foregroundStyle(.orange) }

                GroupBox("Sources & Last Successful Check") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(PackageSecurityService.sources, id: \.id) { source in
                            let status = store.securitySources.first { $0.id == source.id }
                            HStack {
                                Link(source.name, destination: URL(string: source.url)!)
                                Spacer()
                                Text(status?.checkedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Not checked")
                                    .foregroundStyle(.secondary)
                            }
                            if let error = status?.error {
                                Text("Source unavailable: \(error). Previous warnings are retained and may be out of date.")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                        }
                    }.padding(8)
                }
                if findings.isEmpty {
                    ContentUnavailableView("No Matching Reports", systemImage: "shield", description: Text("Review source status above for coverage and connection errors."))
                        .frame(maxWidth: .infinity)
                }
                ForEach(findings) { finding in
                    if let package = store.installedPackages.first(where: { $0.id == finding.packageID }) {
                        findingCard(finding, package: package)
                    }
                }
            }.padding(24)
        }
        .confirmationDialog("Remove \(pendingRemoval?.name ?? "package")?", isPresented: $showRemoval, titleVisibility: .visible) {
            if let package = pendingRemoval {
                Button("Uninstall \(package.name)", role: .destructive) {
                    Task { await store.uninstallPackage(package) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let package = pendingRemoval {
                let dependents = store.reverseDependencies(for: package.name).map(\.name)
                Text("Homebrew will uninstall this package.\(dependents.isEmpty ? "" : " Required by: " + dependents.joined(separator: ", ") + ". Homebrew may refuse removal.") Removing a package does not undo damage from a compromise. Follow the report’s remediation guidance.")
            }
        }
    }

    private func findingCard(_ finding: SecurityFinding, package: BrewPackage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(finding.isMalwareWarning ? "Homebrew malware warning" : "Review required", systemImage: "exclamationmark.shield")
                    .font(.headline).foregroundStyle(finding.isMalwareWarning ? .red : .orange)
                Spacer()
                Text(package.isCask ? "Cask" : "Formula").foregroundStyle(.secondary)
            }
            Text(package.fullName).font(.title3.bold())
            Text("Installed: \(package.installedVersions.joined(separator: ", "))").font(.callout).foregroundStyle(.secondary)
            Text(finding.title).font(.headline).textSelection(.enabled)
            Text(finding.detail).font(.callout).textSelection(.enabled)
            if let date = finding.reportedAt { Text("Published \(date.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary) }
            HStack {
                Link("Read Source", destination: finding.url)
                Spacer()
                Button("Remove Package…", role: .destructive) { pendingRemoval = package; showRemoval = true }
                    .disabled(store.isRunningCommand)
            }.buttonStyle(.glass)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: 16)
    }
}
