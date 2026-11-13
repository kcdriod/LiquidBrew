import SwiftUI

public struct DiscoverWorkspaceView: View {
    @ObservedObject public var store: BrewStore
    @State private var catalog: DiscoverCatalog = .formulae
    @State private var mode: DiscoverChartMode = .top
    @State private var searchScope: PackageFilter = .all
    public init(store: BrewStore) { self.store = store }

    private var query: String { store.discoverSearchText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var snapshot: DiscoverChartSnapshot? { store.discoverCharts[catalog] }
    private var chartEntries: [DiscoverChartEntry] { mode == .top ? snapshot?.top ?? [] : snapshot?.trending ?? [] }
    private var searchResults: [BrewPackage] {
        store.discoverResults.filter { searchScope == .all || (searchScope == .casks ? $0.isCask : !$0.isCask) }
    }

    public var body: some View {
        VStack(spacing: 0) {
            searchBar
            if query.isEmpty { charts }
            else { searchContent }
        }
        .task(id: catalog) { await store.loadDiscoverCharts(catalog) }
        .onChange(of: store.discoverSearchText) { _, _ in store.resetDiscoverSearch() }
        .task(id: store.discoverSearchText) {
            guard !query.isEmpty else { return }
            do { try await Task.sleep(for: .milliseconds(350)) }
            catch { return }
            guard !Task.isCancelled, !store.hasSearchedDiscover else { return }
            await store.searchRemotePackages(query: store.discoverSearchText)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search packages and apps", text: $store.discoverSearchText)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Search packages and apps")
                    .onSubmit { Task { await store.searchRemotePackages(query: store.discoverSearchText) } }
                if !store.discoverSearchText.isEmpty {
                    Button { store.discoverSearchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).accessibilityLabel("Clear package search")
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            Button("Search") { Task { await store.searchRemotePackages(query: store.discoverSearchText) } }
                .buttonStyle(.glassProminent)
                .disabled(query.isEmpty || store.isSearchingDiscover)
        }
        .padding(16)
    }

    private var charts: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("Charts", selection: $mode) {
                    ForEach(DiscoverChartMode.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).frame(width: 240)
                Spacer()
                Picker("Package kind", selection: $catalog) {
                    ForEach(DiscoverCatalog.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden().frame(width: 175)
                Button { Task { await store.loadDiscoverCharts(catalog, force: true) } } label: {
                    Label("Refresh Charts", systemImage: "arrow.clockwise")
                }
                .labelStyle(.iconOnly).help("Refresh Charts")
                .disabled(store.loadingDiscoverCharts.contains(catalog))
            }
            .glassToolbar()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    chartIntroduction
                    if let error = store.discoverChartErrors[catalog] {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(snapshot == nil ? "Couldn’t Load Charts" : "Showing Saved Charts", systemImage: "wifi.exclamationmark")
                                .font(.headline).foregroundStyle(.orange)
                            Text(error).font(.callout).foregroundStyle(.secondary)
                            Button("Try Again") { Task { await store.loadDiscoverCharts(catalog, force: true) } }
                        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).liquidGlassCard()
                    }
                    if let warning = snapshot?.warning {
                        Label(warning, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
                    }
                    if store.loadingDiscoverCharts.contains(catalog), snapshot == nil {
                        ProgressView("Loading Homebrew charts…").frame(maxWidth: .infinity).padding(40)
                    } else if chartEntries.isEmpty && store.discoverChartErrors[catalog] == nil {
                        ContentUnavailableView("No Rankings Available", systemImage: "chart.bar", description: Text("Try refreshing charts or search for a package above."))
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(Array(chartEntries.enumerated()), id: \.element.id) { index, entry in
                        chartRow(entry, rank: index + 1)
                    }
                    Link("About Homebrew analytics", destination: URL(string: "https://formulae.brew.sh/docs/api/#analytics")!)
                        .font(.caption).padding(.top, 6)
                }
                .padding(.horizontal, 20).padding(.bottom, 24)
            }
        }
    }

    private var chartIntroduction: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(mode == .top ? "Most Popular" : "Gaining Momentum", systemImage: mode == .top ? "chart.bar.fill" : "arrow.up.right")
                    .font(.title2.bold())
                Spacer()
                if store.loadingDiscoverCharts.contains(catalog), snapshot != nil { ProgressView().controlSize(.small) }
            }
            Text(chartDescription).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let snapshot {
                Text("\(mode == .top ? snapshot.topPeriod : snapshot.trendPeriod) · Updated \(snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 10)
    }

    private var chartDescription: String {
        if mode == .trending {
            return "Growth in daily reported installs: the latest 30 days versus the preceding 60. Requires at least 500 recent installs, 100 prior installs and 10% growth. Formulae use installs requested directly, excluding dependencies."
        }
        if snapshot?.usesDownloads == true {
            return "Ranked by 30-day package downloads, across versions and platforms. Covers Homebrew’s measured subset of \(snapshot?.downloadCoverage ?? 1000) formulae. Downloads can include repeat downloads and CI; they are not unique users."
        }
        return catalog.isCask
            ? "Ranked by reported app installs over 30 days. Homebrew does not provide comparable download totals for casks. These are analytics events, not unique users."
            : "Ranked by reported direct installs over 30 days, excluding dependencies. These are analytics events, not unique users."
    }

    private func chartRow(_ entry: DiscoverChartEntry, rank: Int) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Text(String(format: "%02d", rank)).font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(rank <= 3 ? Color.teal : Color.secondary).frame(width: 36)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(entry.package.name).font(.headline)
                    if let growth = entry.growth {
                        Text("+\((growth * 100).formatted(.number.precision(.fractionLength(0))))%")
                            .font(.caption.weight(.semibold)).foregroundStyle(.green)
                            .padding(.horizontal, 6).padding(.vertical, 3).background(.green.opacity(0.1), in: Capsule())
                    }
                }
                if let desc = entry.package.desc { Text(desc).font(.callout).foregroundStyle(.secondary).lineLimit(2) }
                Text("\(entry.count.formatted()) \(mode == .top && snapshot?.usesDownloads == true ? "downloads" : "reported installs") · 30 days")
                    .font(.caption).foregroundStyle(.secondary)
                if let maximum = chartEntries.first?.count, maximum > 0, mode == .top {
                    GeometryReader { geometry in
                        Capsule().fill(.teal.opacity(0.12))
                            .overlay(alignment: .leading) {
                                Capsule().fill(.teal.opacity(0.55)).frame(width: max(3, geometry.size.width * min(1, Double(entry.count) / Double(maximum))))
                            }
                    }.frame(height: 3).frame(maxWidth: 240).accessibilityHidden(true)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 8) {
                installAction(entry.package)
                Link("Details", destination: URL(string: "https://formulae.brew.sh/\(entry.package.isCask ? "cask" : "formula")/\(entry.package.name)")!)
                    .font(.caption)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: 14)
    }

    private var searchContent: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Show", selection: $searchScope) {
                    Text("All").tag(PackageFilter.all)
                    Text("Formulae").tag(PackageFilter.formulae)
                    Text("Casks").tag(PackageFilter.casks)
                }.pickerStyle(.segmented).frame(width: 244)
                Spacer()
                if store.hasSearchedDiscover && !store.isSearchingDiscover && store.discoverSearchError == nil {
                    Text("\(searchResults.count) results").font(.callout).foregroundStyle(.secondary)
                }
            }.glassToolbar()
            if store.isSearchingDiscover || !store.hasSearchedDiscover {
                ProgressView("Searching Homebrew…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = store.discoverSearchError {
                VStack(spacing: 12) {
                    ContentUnavailableView("Search Unavailable", systemImage: "exclamationmark.magnifyingglass", description: Text(error))
                    Button("Try Again") { Task { await store.searchRemotePackages(query: store.discoverSearchText) } }.buttonStyle(.glass)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if searchResults.isEmpty {
                ContentUnavailableView("No Results", systemImage: "magnifyingglass", description: Text("Try another package name or change the filter."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(searchResults) { package in
                    HStack(spacing: 12) {
                        Image(systemName: package.isCask ? "app" : "shippingbox").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(package.name).fontWeight(.medium)
                            Text(package.desc ?? (package.isCask ? "macOS app" : "Homebrew formula")).font(.callout).foregroundStyle(.secondary)
                            Text("\(package.isCask ? "Cask" : "Formula") · \(package.version)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        installAction(package)
                    }.padding(.vertical, 6)
                }.listStyle(.inset).scrollContentBackground(.hidden)
            }
        }
    }

    @ViewBuilder private func installAction(_ package: BrewPackage) -> some View {
        if store.installedPackages.contains(where: { $0.id == package.id }) {
            Label("Installed", systemImage: "checkmark").font(.callout).foregroundStyle(.secondary)
        } else {
            Button("Install") { Task { await store.installPackage(name: package.name, isCask: package.isCask) } }
                .buttonStyle(.glass).disabled(store.isRunningCommand)
        }
    }
}
