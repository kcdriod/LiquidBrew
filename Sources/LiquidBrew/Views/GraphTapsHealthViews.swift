import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - 1. Interactive Dependency Graph Visualizer

public enum GraphLayoutMode: String, CaseIterable, Identifiable {
    case radial = "Radial Constellation"
    case hierarchical = "Hierarchical Tree"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .radial: return "circle.hexagongrid.fill"
        case .hierarchical: return "point.3.connected.trianglepath.dotted"
        }
    }
}

public enum GraphScopeMode: String, CaseIterable, Identifiable {
    case focused = "Focused Formula"
    case leavesNetwork = "Leaves Network"

    public var id: String { rawValue }
}

private enum GraphNodeRole: Equatable {
    case root
    case directDependency
    case transitiveDependency
    case reverseDependent
    case leafNode
}

private struct GraphNodeItem: Identifiable, Equatable {
    let id: String // package name
    let label: String
    let role: GraphNodeRole
    let position: CGPoint
    let package: BrewPackage?
    let depth: Int
}

private struct GraphEdgeItem: Identifiable, Equatable {
    var id: String { "\(from)->\(to)" }
    let from: String
    let to: String
    let isReverse: Bool
    let depth: Int
}

public struct DependencyGraphView: View {
    @ObservedObject public var store: BrewStore

    @State private var scopeMode: GraphScopeMode = .focused
    @State private var layoutMode: GraphLayoutMode = .radial
    @State private var focusedPackageName: String = ""
    @State private var selectedNodeName: String? = nil
    @State private var sidebarFilterText: String = ""
    @State private var showLeavesOnlyInSidebar: Bool = false

    // Viewport pan & zoom state
    @State private var panOffset: CGSize = .zero
    @State private var dragStartOffset: CGSize? = nil
    @State private var zoomScale: CGFloat = 1.0
    @State private var magnifyStartScale: CGFloat? = nil

    public init(store: BrewStore) {
        self.store = store
    }

    private var installedFormulae: [BrewPackage] {
        store.installedPackages
            .filter { !$0.isCask }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var filteredSidebarFormulae: [BrewPackage] {
        installedFormulae.filter { pkg in
            if showLeavesOnlyInSidebar && !pkg.isLeaf {
                return false
            }
            let query = store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if query.isEmpty { return true }
            return pkg.name.lowercased().contains(query) || (pkg.desc?.lowercased().contains(query) ?? false)
        }
    }

    private var packageMap: [String: BrewPackage] {
        Dictionary(uniqueKeysWithValues: installedFormulae.map { ($0.name, $0) })
    }

    private var activeFocusedPackage: BrewPackage? {
        if let pkg = packageMap[focusedPackageName] {
            return pkg
        }
        if let selected = store.selectedPackage, !selected.isCask {
            return selected
        }
        return installedFormulae.first(where: { $0.isLeaf }) ?? installedFormulae.first
    }

    private var inspectedPackage: BrewPackage? {
        if let selectedNodeName {
            if let pkg = packageMap[selectedNodeName] {
                return pkg
            }
            // Synthesize lightweight package representation for uninstalled/sub-dependency node
            return BrewPackage(
                name: selectedNodeName,
                desc: "Dependency node referenced in formula graph.",
                version: "runtime",
                isCask: false,
                isInstalledOnRequest: false,
                isLeaf: false
            )
        }
        return nil
    }

    public var body: some View {
        HSplitView {
            formulaSelectorSidebar
                .frame(minWidth: 200, idealWidth: 230, maxWidth: 300)
            VStack(spacing: 0) {
                graphTopToolbar.glassToolbar()
                graphCanvasContainer
                    .overlay(alignment: .bottomTrailing) {
                        if let inspected = inspectedPackage {
                            nodeInspectorHUD(for: inspected)
                                .frame(width: 280)
                                .padding(12)
                        }
                    }
                graphLegendPill
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { syncInitialSelection() }
        .onChange(of: installedFormulae.isEmpty) { _, isEmpty in
            if !isEmpty { syncInitialSelection() }
        }
        .onChange(of: store.selectedPackage) { _, package in
            if let package, !package.isCask {
                focusedPackageName = package.name
                selectedNodeName = package.name
            }
        }
    }

    private func syncInitialSelection() {
        if focusedPackageName.isEmpty {
            if let selected = store.selectedPackage, !selected.isCask {
                focusedPackageName = selected.name
                selectedNodeName = selected.name
            } else if let firstLeaf = installedFormulae.first(where: { $0.isLeaf }) ?? installedFormulae.first {
                focusedPackageName = firstLeaf.name
                selectedNodeName = firstLeaf.name
            }
        }
    }

    // MARK: - Sidebar

    private var formulaSelectorSidebar: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Scope", selection: $scopeMode) {
                    Text("Selected Formula").tag(GraphScopeMode.focused)
                    Text("Top-Level Network").tag(GraphScopeMode.leavesNetwork)
                }
                Toggle("Top-level packages only", isOn: $showLeavesOnlyInSidebar)
                    .toggleStyle(.checkbox)
            }
            .glassToolbar()
            List(filteredSidebarFormulae) { package in
                Button {
                    scopeMode = .focused
                    focusedPackageName = package.name
                    selectedNodeName = package.name
                    store.selectedPackage = package
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(package.name).fontWeight(.medium)
                        Text("\(package.dependencies.count) dependencies")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(activeFocusedPackage?.id == package.id ? Color.accentColor.opacity(0.15) : Color.clear)
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
        .onChange(of: scopeMode) { _, _ in resetViewport() }
    }

    private var graphTopToolbar: some View {
        HStack {
            Picker("Layout", selection: $layoutMode) {
                Text("Radial").tag(GraphLayoutMode.radial)
                Text("Tree").tag(GraphLayoutMode.hierarchical)
            }.frame(width: 160)
            Spacer()
            Button("Zoom Out", systemImage: "minus.magnifyingglass") { zoomScale = max(0.45, zoomScale - 0.2) }
                .labelStyle(.iconOnly).help("Zoom Out")
            Text("\(Int(zoomScale * 100))%")
                .font(.system(.caption, design: .monospaced)).frame(width: 40)
            Button("Zoom In", systemImage: "plus.magnifyingglass") { zoomScale = min(2.4, zoomScale + 0.2) }
                .labelStyle(.iconOnly).help("Zoom In")
            Button("Reset") { resetViewport() }
        }
        .controlSize(.small)
        .buttonStyle(.glass)
    }

    private func resetViewport() {
        panOffset = .zero
        zoomScale = 1.0
    }

    // MARK: - Graph Canvas & Geometry

    private var graphCanvasContainer: some View {
        GeometryReader { geo in
            let graph = computeGraph(in: geo.size)

            ZStack {
                // Subtle background grid + radial glow
                Canvas { context, size in
                    drawBackgroundGrid(context: &context, size: size)
                    drawEdges(context: &context, graph: graph)
                }

                // Interactive Node Overlay Buttons positioned in transformed space
                ForEach(graph.nodes) { node in
                    let transformedPos = transformPoint(node.position, in: geo.size)
                    graphNodeButton(node: node)
                        .scaleEffect( max(0.65, min(1.35, zoomScale * 0.92)) )
                        .position(transformedPos)
                }

                if graph.nodes.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.cyan.opacity(0.7))
                        Text("No Formula Dependencies Loaded")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.primary)
                        Text("Install Homebrew formulae or refresh package index to explore the interactive dependency constellation.")
                            .font(.system(size: 12.5, design: .rounded))
                            .foregroundStyle(Color.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 360)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let start = dragStartOffset ?? panOffset
                        if dragStartOffset == nil {
                            dragStartOffset = panOffset
                        }
                        panOffset = CGSize(
                            width: start.width + value.translation.width,
                            height: start.height + value.translation.height
                        )
                    }
                    .onEnded { _ in
                        dragStartOffset = nil
                    }
            )
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        let base = magnifyStartScale ?? zoomScale
                        if magnifyStartScale == nil {
                            magnifyStartScale = zoomScale
                        }
                        zoomScale = min(2.5, max(0.45, base * value))
                    }
                    .onEnded { _ in
                        magnifyStartScale = nil
                    }
            )
        }
        .clipped()
    }

    private func transformPoint(_ pt: CGPoint, in size: CGSize) -> CGPoint {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let dx = (pt.x - center.x) * zoomScale + panOffset.width
        let dy = (pt.y - center.y) * zoomScale + panOffset.height
        return CGPoint(x: center.x + dx, y: center.y + dy)
    }

    private func drawBackgroundGrid(context: inout GraphicsContext, size: CGSize) {
        let spacing: CGFloat = 38 * max(0.6, min(1.5, zoomScale))
        var gridPath = Path()
        let offsetX = panOffset.width.truncatingRemainder(dividingBy: spacing)
        let offsetY = panOffset.height.truncatingRemainder(dividingBy: spacing)

        var x = offsetX
        while x < size.width {
            gridPath.move(to: CGPoint(x: x, y: 0))
            gridPath.addLine(to: CGPoint(x: x, y: size.height))
            x += spacing
        }
        var y = offsetY
        while y < size.height {
            gridPath.move(to: CGPoint(x: 0, y: y))
            gridPath.addLine(to: CGPoint(x: size.width, y: y))
            y += spacing
        }
        context.stroke(gridPath, with: .color(Color.primary.opacity(0.06)), lineWidth: 0.7)
    }

    private func drawEdges(context: inout GraphicsContext, graph: (nodes: [GraphNodeItem], edges: [GraphEdgeItem])) {
        let posMap = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0.position) })
        let canvasSize = context.clipBoundingRect.size

        for edge in graph.edges {
            guard let rawFrom = posMap[edge.from], let rawTo = posMap[edge.to] else { continue }
            let p1 = transformPoint(rawFrom, in: canvasSize)
            let p2 = transformPoint(rawTo, in: canvasSize)

            var curve = Path()
            curve.move(to: p1)

            if layoutMode == .hierarchical {
                let midX = (p1.x + p2.x) / 2
                curve.addCurve(
                    to: p2,
                    control1: CGPoint(x: midX, y: p1.y),
                    control2: CGPoint(x: midX, y: p2.y)
                )
            } else {
                let mid = CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
                let dx = p2.x - p1.x
                let dy = p2.y - p1.y
                let normal = CGPoint(x: -dy * 0.14, y: dx * 0.14)
                let ctrl = CGPoint(x: mid.x + normal.x, y: mid.y + normal.y)
                curve.addQuadCurve(to: p2, control: ctrl)
            }

            let isHighlighted = (selectedNodeName == edge.from || selectedNodeName == edge.to)
            let strokeColor: Color = edge.isReverse
                ? (isHighlighted ? Color.purple : Color.purple.opacity(0.45))
                : (edge.depth == 1
                    ? (isHighlighted ? Color.cyan : Color.cyan.opacity(0.55))
                    : (isHighlighted ? Color.mint : Color.teal.opacity(0.38)))

            // Outer glow
            context.stroke(
                curve,
                with: .color(strokeColor.opacity(isHighlighted ? 0.35 : 0.15)),
                lineWidth: isHighlighted ? 5.5 : 3.2
            )

            // Crisp core filament
            context.stroke(
                curve,
                with: .linearGradient(
                    Gradient(colors: [strokeColor, strokeColor.opacity(0.65)]),
                    startPoint: p1,
                    endPoint: p2
                ),
                style: StrokeStyle(
                    lineWidth: isHighlighted ? 2.2 : 1.35,
                    lineCap: .round,
                    dash: edge.isReverse ? [5, 4] : []
                )
            )
        }
    }

    private func graphNodeButton(node: GraphNodeItem) -> some View {
        let isSelected = (selectedNodeName == node.id)
        let roleColor = colorForRole(node.role)

        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                selectedNodeName = node.id
                if let pkg = node.package {
                    store.selectedPackage = pkg
                }
            }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(roleColor)
                    .frame(width: node.role == .root ? 10 : 7.5, height: node.role == .root ? 10 : 7.5)
                    .shadow(color: roleColor.opacity(0.8), radius: 4)

                Text(node.label)
                    .font(.system(
                        size: node.role == .root ? 13 : 11.5,
                        weight: (node.role == .root || isSelected) ? .bold : .semibold,
                        design: .rounded
                    ))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, node.role == .root ? 13 : 10)
            .padding(.vertical, node.role == .root ? 8 : 5.5)
            .background {
                ZStack {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                    Capsule(style: .continuous)
                        .fill(roleColor.opacity(isSelected ? 0.32 : (node.role == .root ? 0.24 : 0.12)))
                    Capsule(style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isSelected ? 0.85 : 0.45),
                                    roleColor.opacity(isSelected ? 0.9 : 0.45)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isSelected ? 1.8 : 1.0
                        )
                }
                .shadow(color: roleColor.opacity(isSelected ? 0.45 : 0.18), radius: isSelected ? 12 : 6, x: 0, y: 3)
            }
        }
        .buttonStyle(.plain)
    }

    private func colorForRole(_ role: GraphNodeRole) -> Color {
        switch role {
        case .root: return .cyan
        case .directDependency: return .mint
        case .transitiveDependency: return .teal
        case .reverseDependent: return .purple
        case .leafNode: return .indigo
        }
    }

    // MARK: - Graph Layout Calculation

    private func computeGraph(in size: CGSize) -> (nodes: [GraphNodeItem], edges: [GraphEdgeItem]) {
        guard size.width > 50, size.height > 50 else { return ([], []) }

        if scopeMode == .leavesNetwork {
            return computeLeavesNetworkGraph(in: size)
        } else {
            return computeFocusedFormulaGraph(in: size)
        }
    }

    private func computeFocusedFormulaGraph(in size: CGSize) -> (nodes: [GraphNodeItem], edges: [GraphEdgeItem]) {
        guard let rootPkg = activeFocusedPackage else { return ([], []) }

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        var nodes: [GraphNodeItem] = []
        var edges: [GraphEdgeItem] = []
        var visited = Set<String>([rootPkg.name])

        nodes.append(
            GraphNodeItem(
                id: rootPkg.name,
                label: rootPkg.name,
                role: .root,
                position: layoutMode == .radial ? center : CGPoint(x: size.width * 0.44, y: center.y),
                package: rootPkg,
                depth: 0
            )
        )

        let directDeps = Array(Set(rootPkg.dependencies + rootPkg.runtimeDependencies)).sorted()
        let reverseDeps = store.reverseDependencies(for: rootPkg.name).map(\.name).sorted()

        // Collect second-level dependencies (capped for visual clarity)
        var secondLevelDeps: [(parent: String, child: String)] = []
        for depName in directDeps {
            visited.insert(depName)
        }
        for revName in reverseDeps {
            visited.insert(revName)
        }
        for depName in directDeps.prefix(10) {
            if let depPkg = packageMap[depName] {
                let subDeps = Set(depPkg.dependencies + depPkg.runtimeDependencies)
                for sub in subDeps.sorted().prefix(4) {
                    if !visited.contains(sub) {
                        visited.insert(sub)
                        secondLevelDeps.append((parent: depName, child: sub))
                    }
                    edges.append(GraphEdgeItem(from: depName, to: sub, isReverse: false, depth: 2))
                }
            }
        }

        if layoutMode == .radial {
            let minDim = min(size.width, size.height)
            let ring1Radius = max(125, minDim * 0.27)
            let ring2Radius = max(220, minDim * 0.43)

            // Combine reverse deps and direct deps in inner/middle arcs
            let totalRing1 = directDeps.count + reverseDeps.count
            for (idx, revName) in reverseDeps.enumerated() {
                let angle = angleForIndex(idx, total: max(1, totalRing1), startOffset: -.pi * 0.85)
                let pt = CGPoint(
                    x: center.x + cos(angle) * (ring1Radius * 0.92),
                    y: center.y + sin(angle) * (ring1Radius * 0.92)
                )
                nodes.append(
                    GraphNodeItem(
                        id: revName,
                        label: revName,
                        role: .reverseDependent,
                        position: pt,
                        package: packageMap[revName],
                        depth: 1
                    )
                )
                edges.append(GraphEdgeItem(from: revName, to: rootPkg.name, isReverse: true, depth: 1))
            }

            for (idx, depName) in directDeps.enumerated() {
                let angle = angleForIndex(idx + reverseDeps.count, total: max(1, totalRing1), startOffset: -.pi * 0.85)
                let pt = CGPoint(
                    x: center.x + cos(angle) * ring1Radius,
                    y: center.y + sin(angle) * ring1Radius
                )
                nodes.append(
                    GraphNodeItem(
                        id: depName,
                        label: depName,
                        role: .directDependency,
                        position: pt,
                        package: packageMap[depName],
                        depth: 1
                    )
                )
                edges.append(GraphEdgeItem(from: rootPkg.name, to: depName, isReverse: false, depth: 1))
            }

            for (idx, pair) in secondLevelDeps.enumerated() {
                let angle = angleForIndex(idx, total: max(1, secondLevelDeps.count), startOffset: -.pi * 0.5)
                let pt = CGPoint(
                    x: center.x + cos(angle) * ring2Radius,
                    y: center.y + sin(angle) * ring2Radius
                )
                nodes.append(
                    GraphNodeItem(
                        id: pair.child,
                        label: pair.child,
                        role: .transitiveDependency,
                        position: pt,
                        package: packageMap[pair.child],
                        depth: 2
                    )
                )
            }
        } else {
            // Hierarchical Tree columns: Left = Reverse Dependents, Center-Left = Root, Center-Right = Direct Deps, Right = Transitive Deps
            let colReverseX = size.width * 0.16
            let colDirectX = size.width * 0.68
            let colTransitiveX = size.width * 0.88

            for (idx, revName) in reverseDeps.enumerated() {
                let y = verticalSlot(index: idx, count: reverseDeps.count, height: size.height)
                nodes.append(
                    GraphNodeItem(
                        id: revName,
                        label: revName,
                        role: .reverseDependent,
                        position: CGPoint(x: colReverseX, y: y),
                        package: packageMap[revName],
                        depth: 1
                    )
                )
                edges.append(GraphEdgeItem(from: revName, to: rootPkg.name, isReverse: true, depth: 1))
            }

            for (idx, depName) in directDeps.enumerated() {
                let y = verticalSlot(index: idx, count: directDeps.count, height: size.height)
                nodes.append(
                    GraphNodeItem(
                        id: depName,
                        label: depName,
                        role: .directDependency,
                        position: CGPoint(x: colDirectX, y: y),
                        package: packageMap[depName],
                        depth: 1
                    )
                )
                edges.append(GraphEdgeItem(from: rootPkg.name, to: depName, isReverse: false, depth: 1))
            }

            for (idx, pair) in secondLevelDeps.enumerated() {
                let y = verticalSlot(index: idx, count: secondLevelDeps.count, height: size.height)
                nodes.append(
                    GraphNodeItem(
                        id: pair.child,
                        label: pair.child,
                        role: .transitiveDependency,
                        position: CGPoint(x: colTransitiveX, y: y),
                        package: packageMap[pair.child],
                        depth: 2
                    )
                )
            }
        }

        return (nodes, edges)
    }

    private func computeLeavesNetworkGraph(in size: CGSize) -> (nodes: [GraphNodeItem], edges: [GraphEdgeItem]) {
        let leaves = Array(installedFormulae.filter { $0.isLeaf }.prefix(14))
        let sourcePackages = leaves.isEmpty ? Array(installedFormulae.prefix(12)) : leaves
        guard !sourcePackages.isEmpty else { return ([], []) }

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        var nodes: [GraphNodeItem] = []
        var edges: [GraphEdgeItem] = []
        var sharedDepsOrdered: [String] = []
        var seenDeps = Set<String>()
        let leafNames = Set(sourcePackages.map(\.name))

        for leaf in sourcePackages {
            let deps = Set(leaf.dependencies + leaf.runtimeDependencies)
            for d in deps.sorted().prefix(4) where !leafNames.contains(d) {
                if !seenDeps.contains(d) && sharedDepsOrdered.count < 18 {
                    seenDeps.insert(d)
                    sharedDepsOrdered.append(d)
                }
                if seenDeps.contains(d) {
                    edges.append(GraphEdgeItem(from: leaf.name, to: d, isReverse: false, depth: 1))
                }
            }
        }

        if layoutMode == .radial {
            let minDim = min(size.width, size.height)
            let outerRadius = max(180, minDim * 0.39)
            let innerRadius = max(95, minDim * 0.20)

            for (idx, leaf) in sourcePackages.enumerated() {
                let angle = angleForIndex(idx, total: sourcePackages.count, startOffset: -.pi / 2)
                let pt = CGPoint(
                    x: center.x + cos(angle) * outerRadius,
                    y: center.y + sin(angle) * outerRadius
                )
                nodes.append(
                    GraphNodeItem(
                        id: leaf.name,
                        label: leaf.name,
                        role: .leafNode,
                        position: pt,
                        package: leaf,
                        depth: 0
                    )
                )
            }

            for (idx, depName) in sharedDepsOrdered.enumerated() {
                let angle = angleForIndex(idx, total: max(1, sharedDepsOrdered.count), startOffset: -.pi / 4)
                let pt = CGPoint(
                    x: center.x + cos(angle) * innerRadius,
                    y: center.y + sin(angle) * innerRadius
                )
                nodes.append(
                    GraphNodeItem(
                        id: depName,
                        label: depName,
                        role: .directDependency,
                        position: pt,
                        package: packageMap[depName],
                        depth: 1
                    )
                )
            }
        } else {
            let leftX = size.width * 0.28
            let rightX = size.width * 0.72

            for (idx, leaf) in sourcePackages.enumerated() {
                let y = verticalSlot(index: idx, count: sourcePackages.count, height: size.height)
                nodes.append(
                    GraphNodeItem(
                        id: leaf.name,
                        label: leaf.name,
                        role: .leafNode,
                        position: CGPoint(x: leftX, y: y),
                        package: leaf,
                        depth: 0
                    )
                )
            }

            for (idx, depName) in sharedDepsOrdered.enumerated() {
                let y = verticalSlot(index: idx, count: sharedDepsOrdered.count, height: size.height)
                nodes.append(
                    GraphNodeItem(
                        id: depName,
                        label: depName,
                        role: .directDependency,
                        position: CGPoint(x: rightX, y: y),
                        package: packageMap[depName],
                        depth: 1
                    )
                )
            }
        }

        return (nodes, edges)
    }

    private func angleForIndex(_ index: Int, total: Int, startOffset: CGFloat) -> CGFloat {
        guard total > 0 else { return 0 }
        return startOffset + (2 * .pi * CGFloat(index)) / CGFloat(total)
    }

    private func verticalSlot(index: Int, count: Int, height: CGFloat) -> CGFloat {
        let usableHeight = max(160, height - 150)
        let topMargin: CGFloat = 75
        guard count > 1 else { return height / 2 }
        return topMargin + (usableHeight * CGFloat(index)) / CGFloat(count - 1)
    }

    // MARK: - Legend & HUD Overlay

    private var graphLegendPill: some View {
        HStack(spacing: 12) {
            legendDot(color: .cyan, title: "Root Formula")
            legendDot(color: .mint, title: "Direct Dep")
            legendDot(color: .teal, title: "Transitive")
            legendDot(color: .purple, title: "Used By (Reverse)")
        }
        .glassToolbar()
    }

    private func legendDot(color: Color, title: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .fixedSize()
                .font(.system(size: 10.5, weight: .medium))
        }
    }

    private func nodeInspectorHUD(for pkg: BrewPackage) -> some View {
        let directDeps = Array(Set(pkg.dependencies + pkg.runtimeDependencies)).sorted()
        let revDeps = store.reverseDependencies(for: pkg.name)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(pkg.name)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        GlassBadge(pkg.version, color: .cyan)
                        if pkg.isLeaf {
                            GlassBadge("Leaf", icon: "leaf.fill", color: .mint)
                        }
                    }
                    if let desc = pkg.desc, !desc.isEmpty {
                        Text(desc)
                            .font(.system(size: 11.5, design: .rounded))
                            .lineLimit(2)
                    }
                }
                Spacer()
                Button("Close Inspector", systemImage: "xmark.circle.fill") {
                    withAnimation(.easeOut(duration: 0.2)) {
                        selectedNodeName = nil
                    }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .help("Close Inspector")
            }

            HStack(spacing: 10) {
                hudMetricPill(title: "Direct Deps", count: directDeps.count, color: .mint)
                hudMetricPill(title: "Used By", count: revDeps.count, color: .purple)
            }
            LabeledContent("Tap", value: pkg.tap ?? "core")
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)

            if !directDeps.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Requires (\(directDeps.count))")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            ForEach(directDeps, id: \.self) { dep in
                                Button {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                        scopeMode = .focused
                                        focusedPackageName = dep
                                        selectedNodeName = dep
                                    }
                                } label: {
                                    GlassBadge(dep, icon: "arrow.turn.down.right", color: .mint)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            if !revDeps.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Required By (\(revDeps.count))")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            ForEach(revDeps) { rev in
                                Button {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                        scopeMode = .focused
                                        focusedPackageName = rev.name
                                        selectedNodeName = rev.name
                                    }
                                } label: {
                                    GlassBadge(rev.name, icon: "arrow.uturn.up", color: .purple)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                if focusedPackageName != pkg.name && packageMap[pkg.name] != nil {
                    GlassPillButton("Focus Graph Here", icon: "scope", tint: .cyan) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            scopeMode = .focused
                            focusedPackageName = pkg.name
                            resetViewport()
                        }
                    }
                }

                Spacer()

                GlassPillButton("Inspect in Packages", icon: "shippingbox.fill", tint: .indigo, isProminent: true) {
                    store.selectedPackage = packageMap[pkg.name] ?? pkg
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        store.selectedTab = .packages
                    }
                }
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: 16, tint: .cyan.opacity(0.55))
    }

    private func hudMetricPill(title: String, count: Int, color: Color) -> some View {
        hudMetricPill(title: title, value: "\(count)", color: color)
    }

    private func hudMetricPill(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
            Text(title)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.opacity(0.1))
        )
    }
}
