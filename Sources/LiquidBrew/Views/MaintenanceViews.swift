import SwiftUI
import AppKit

public struct TapsBrewfileView: View {
    @ObservedObject public var store: BrewStore
    @State private var newTap = ""
    @State private var showAddTap = false
    @State private var pendingTap: BrewTap?
    @State private var showRemove = false
    @State private var importURL: URL?
    @State private var showImport = false
    public init(store: BrewStore) { self.store = store }
    private var taps: [BrewTap] {
        store.taps.filter { store.searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(store.searchText) }
    }
    public var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text("Repositories").font(.headline)
                    Spacer()
                    Button("Add Tap…", systemImage: "plus") { showAddTap = true }
                        .buttonStyle(.glass)
                        .disabled(store.isRunningCommand)
                }
                .glassToolbar()
                List(taps) { tap in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label(tap.name, systemImage: "shippingbox")
                                .fontWeight(.medium)
                            Spacer()
                            Button("Remove…") { pendingTap = tap; showRemove = true }
                                .buttonStyle(.glass)
                                .disabled(store.isRunningCommand)
                        }
                        Text("\(tap.formulaCount) formulae · \(tap.caskCount) casks\(tap.official ? " · Official" : "")")
                            .foregroundStyle(.secondary).font(.callout)
                        if let remote = tap.remote, let url = URL(string: remote) {
                            Link(remote, destination: url).font(.caption).lineLimit(1)
                        }
                    }.padding(.vertical, 6)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .overlay {
                    if taps.isEmpty { ContentUnavailableView("No Repositories", systemImage: "shippingbox", description: Text("Add a tap or try another search.")) }
                }
            }.frame(minWidth: 320, idealWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
            VStack(spacing: 0) {
                HStack {
                    Text("Brewfile").font(.headline)
                    Spacer()
                    Button("Regenerate", systemImage: "arrow.clockwise") { Task { await store.generateBrewfilePreview() } }
                        .buttonStyle(.glass)
                }
                .glassToolbar()
                ScrollView([.horizontal, .vertical]) {
                    Text(store.brewfilePreview.isEmpty ? "Generate a Brewfile to preview your installed packages." : store.brewfilePreview)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: true)
                        .padding(16)
                }
                .defaultScrollAnchor(.topLeading)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .clipShape(.rect(cornerRadius: 12))
                .padding(.horizontal, 12)
                HStack {
                    Button("Import…") { chooseImport() }
                    Button("Export…") { chooseExport() }
                    Spacer()
                    Button("Copy", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(store.brewfilePreview, forType: .string)
                    }.disabled(store.brewfilePreview.isEmpty)
                }
                .buttonStyle(.glass)
                .disabled(store.isRunningCommand)
                .glassToolbar()
            }.frame(minWidth: 320, idealWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $showAddTap) {
            Form {
                Text("Add Repository").font(.headline)
                TextField("Repository", text: $newTap, prompt: Text("owner/repository"))
                Text("Homebrew taps provide additional formulae and casks.").font(.callout).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { showAddTap = false }.keyboardShortcut(.cancelAction)
                    Button("Add Tap") {
                        let name = newTap.trimmingCharacters(in: .whitespacesAndNewlines)
                        showAddTap = false; newTap = ""
                        Task { await store.addTap(name: name) }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(newTap.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(24).frame(width: 400)
        }
        .confirmationDialog("Remove \(pendingTap?.name ?? "repository")?", isPresented: $showRemove, titleVisibility: .visible) {
            if let tap = pendingTap { Button("Remove Tap", role: .destructive) { Task { await store.removeTap(name: tap.name) } } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Install packages from this Brewfile?", isPresented: $showImport, titleVisibility: .visible) {
            if let url = importURL { Button("Install Packages") { Task { await store.importBrewfile(from: url) } } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Homebrew will install the packages declared in \(importURL?.lastPathComponent ?? "the selected file").") }
    }
    private func chooseImport() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a Brewfile to install its packages."
        if panel.runModal() == .OK, let url = panel.url { importURL = url; showImport = true }
    }
    private func chooseExport() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Brewfile"
        if panel.runModal() == .OK, let url = panel.url { Task { await store.exportBrewfile(to: url) } }
    }
}

public struct HealthCleanupView: View {
    @ObservedObject public var store: BrewStore
    @State private var confirmCleanup = false
    @State private var confirmAutoremove = false
    public init(store: BrewStore) { self.store = store }
    private var report: BrewHealthReport { store.healthReport }
    private var warnings: [String] {
        report.warnings.filter { store.searchText.isEmpty || $0.localizedCaseInsensitiveContains(store.searchText) }
    }
    public var body: some View {
        Form {
            Section("Homebrew") {
                LabeledContent("Version", value: report.brewVersion)
                LabeledContent("Location", value: report.homebrewPrefix)
                LabeledContent("Last Checked", value: report.checkedAt.formatted(date: .abbreviated, time: .shortened))
            }
            Section("Diagnostics") {
                Label(report.isHealthy ? "No issues reported" : "Homebrew reported warnings", systemImage: report.isHealthy ? "checkmark.circle" : "exclamationmark.triangle")
                    .foregroundStyle(report.isHealthy ? Color.green : Color.orange)
                Button("Run Diagnostics") { Task { await store.runDoctor() } }.disabled(store.isRunningCommand)
                if !warnings.isEmpty {
                    ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                        Text(warning).font(.callout).textSelection(.enabled)
                    }
                }
                DisclosureGroup("Diagnostic Output") {
                    Text(report.rawOutput).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                }
            }
            Section("Cache & Old Versions") {
                LabeledContent("Cache Size", value: report.formattedCacheSize)
                LabeledContent("Cache Location", value: report.cachePath)
                Button("Preview Cleanup") { Task { await store.runCleanup(dryRun: true) } }
                Button("Clean Up…") { confirmCleanup = true }
                if !report.cleanupDryRunItems.isEmpty {
                    DisclosureGroup("Cleanup Candidates (\(report.cleanupDryRunItems.count))") {
                        ForEach(Array(report.cleanupDryRunItems.enumerated()), id: \.offset) { _, item in
                            Text(item).font(.callout).textSelection(.enabled)
                        }
                    }
                }
            }.disabled(store.isRunningCommand)
            Section("Unused Dependencies") {
                Text("\(report.autoremoveCandidates.count) candidates").foregroundStyle(.secondary)
                ForEach(report.autoremoveCandidates, id: \.self) { Text($0).font(.callout) }
                Button("Remove Unused Dependencies…") { confirmAutoremove = true }
                    .disabled(store.isRunningCommand || report.autoremoveCandidates.isEmpty)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .buttonStyle(.glass)
        .confirmationDialog("Clean up old versions and cache?", isPresented: $confirmCleanup, titleVisibility: .visible) {
            Button("Clean Up", role: .destructive) { Task { await store.runCleanup(dryRun: false) } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Remove unused dependencies?", isPresented: $confirmAutoremove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { Task { await store.runAutoremove() } }
            Button("Cancel", role: .cancel) {}
        }
    }
}
