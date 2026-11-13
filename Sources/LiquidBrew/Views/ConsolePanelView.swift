import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ConsolePanelView: View {
    @ObservedObject var store: BrewStore
    @AppStorage("console.wrapLines") private var wrapLines = true
    @AppStorage("console.showTimestamps") private var showTimestamps = false
    @State private var followOutput = true
    @State private var searchText = ""
    @State private var issuesOnly = false
    @State private var exportError: String?

    private var visibleEntries: [CommandLogEntry] {
        store.terminalLogs.filter {
            (!issuesOnly || $0.kind.isIssue) &&
            (searchText.isEmpty || $0.cleanText.localizedCaseInsensitiveContains(searchText))
        }
    }
    private var issueCount: Int { store.terminalLogs.filter { $0.kind.isIssue }.count }
    private var isFiltered: Bool { issuesOnly || !searchText.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            controls
            output
            Divider()
            footer
        }
        .background(Color(nsColor: .textBackgroundColor))
        .alert("Could Not Save Log", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK") { exportError = nil }
        } message: { Text(exportError ?? "") }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "terminal.fill").foregroundStyle(.teal)
                Text("Console").font(.headline)
                Spacer()
                Menu {
                    Button("Copy Visible Output", systemImage: "doc.on.doc") { copy(visibleEntries) }
                        .disabled(visibleEntries.isEmpty)
                    Button("Copy All Output") { copy(store.terminalLogs) }
                        .disabled(store.terminalLogs.isEmpty)
                    Button("Save Full Log…", systemImage: "square.and.arrow.up") { saveLog() }
                        .disabled(store.terminalLogs.isEmpty)
                    Divider()
                    Toggle("Wrap Long Lines", isOn: $wrapLines)
                    Toggle("Show Timestamps", isOn: $showTimestamps)
                    Divider()
                    Button("Clear Output", systemImage: "trash", role: .destructive) { store.clearTerminalLogs() }
                        .disabled(store.terminalLogs.isEmpty)
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Copy, save, and display options")
                Button { store.showTerminalDrawer = false } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .padding(4)
                .help("Hide Console (⌥⌘T)")
                .accessibilityLabel("Hide Console")
            }
            HStack(alignment: .top, spacing: 9) {
                if store.isRunningCommand { ProgressView().controlSize(.mini).padding(.top, 3) }
                else { Circle().fill(.teal).frame(width: 6, height: 6).padding(.top, 6) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.isRunningCommand ? store.currentCommandTitle : "Ready when you are")
                        .font(.callout.weight(.medium)).lineLimit(2)
                        .help(store.currentCommandTitle)
                    if store.isRunningCommand, let start = store.commandStartedAt {
                        HStack(spacing: 4) {
                            Text("Elapsed")
                            Text(start, style: .timer).monospacedDigit()
                        }.font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Homebrew activity & command output")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.25))
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find in output", text: $searchText)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Find in console output")
                if !searchText.isEmpty {
                    Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).accessibilityLabel("Clear console search")
                }
            }
            .font(.callout)
            .padding(8)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Picker("Output filter", selection: $issuesOnly) {
                    Text("All output").tag(false)
                    Text("Issues · \(issueCount)").tag(true)
                }.pickerStyle(.segmented).labelsHidden()
            }
        }
        .padding(12)
    }

    private var output: some View {
        ScrollViewReader { proxy in
            ScrollView(wrapLines ? .vertical : [.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if visibleEntries.isEmpty {
                        emptyState
                    }
                    ForEach(visibleEntries) { entry in
                        ConsoleOutputRow(entry: entry, wrapLines: wrapLines, showTimestamp: showTimestamps)
                            .id(entry.id)
                    }
                    Color.clear.frame(height: 1).id("console-bottom")
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            .onScrollPhaseChange { _, phase in
                if phase == .interacting { followOutput = false }
            }
            .onChange(of: store.terminalLogs.last?.id) { _, _ in
                if followOutput { proxy.scrollTo("console-bottom", anchor: .bottom) }
            }
            .onChange(of: followOutput) { _, follow in
                if follow { proxy.scrollTo("console-bottom", anchor: .bottom) }
            }
            .onChange(of: issuesOnly) { _, _ in
                if followOutput { proxy.scrollTo("console-bottom", anchor: .bottom) }
            }
            .onAppear {
                if followOutput { proxy.scrollTo("console-bottom", anchor: .bottom) }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: isFiltered ? "line.3.horizontal.decrease.circle" : "terminal")
                .font(.system(size: 26, weight: .light)).foregroundStyle(.teal)
            Text(isFiltered ? "No matching output" : "A clearer view of every command")
                .font(.callout.weight(.semibold))
            Text(isFiltered ? "Try another search or switch to All output." : "Install, update, or run diagnostics to see live progress here. Drag the left edge to resize this panel.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(isFiltered ? "\(visibleEntries.count) of \(store.terminalLogs.count) lines" : "\(store.terminalLogs.count) lines")
                .font(.caption).foregroundStyle(.secondary)
                .help("The console keeps the most recent 1,000 lines.")
            Spacer()
            Button { followOutput.toggle() } label: {
                Label(followOutput ? "Following" : "Jump to Latest", systemImage: followOutput ? "arrow.down.circle.fill" : "arrow.down.to.line")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(followOutput ? Color.teal : Color.primary)
            }
            .buttonStyle(.plain)
            .help(followOutput ? "Pause automatic scrolling" : "Resume automatic scrolling and jump to latest output")
        }
        .padding(12)
    }

    private func copy(_ entries: [CommandLogEntry]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ConsoleOutput.transcript(entries, timestamps: showTimestamps), forType: .string)
    }

    private func saveLog() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "LiquidBrew-console.log"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try ConsoleOutput.transcript(store.terminalLogs, timestamps: true).write(to: url, atomically: true, encoding: .utf8) }
        catch { exportError = error.localizedDescription }
    }
}

private struct ConsoleOutputRow: View {
    let entry: CommandLogEntry
    let wrapLines: Bool
    let showTimestamp: Bool

    private var color: Color {
        switch entry.kind {
        case .command: return .teal
        case .error: return .red
        case .warning: return .orange
        case .success: return .green
        case .progress: return .secondary
        case .diagnostic: return .secondary
        case .output: return .primary
        }
    }
    private var icon: String? {
        switch entry.kind {
        case .command: return "chevron.right"
        case .error: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .success: return "checkmark.circle.fill"
        case .progress: return "arrow.right"
        default: return nil
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if showTimestamp {
                Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
            Group {
                if let icon { Image(systemName: icon).foregroundStyle(color) }
                else { Color.clear }
            }
            .frame(width: 12, height: 16)
            .font(.system(size: 10, weight: .semibold))
            Text(entry.cleanText)
                .font(.system(size: 12, weight: entry.isCommandHeader ? .semibold : .regular, design: .monospaced))
                .foregroundStyle(color)
                .lineSpacing(4)
                .fixedSize(horizontal: !wrapLines, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, entry.isCommandHeader ? 10 : 5)
        .background {
            if entry.isCommandHeader { RoundedRectangle(cornerRadius: 8).fill(.teal.opacity(0.09)) }
            else if entry.kind == .error { RoundedRectangle(cornerRadius: 6).fill(.red.opacity(0.06)) }
            else if entry.kind == .warning { RoundedRectangle(cornerRadius: 6).fill(.orange.opacity(0.06)) }
        }
        .padding(.top, entry.isCommandHeader ? 10 : 0)
        .accessibilityElement(children: .combine)
    }
}
