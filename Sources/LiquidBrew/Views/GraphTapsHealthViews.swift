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
            let query = sidebarFilterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
        return activeFocusedPackage
    }

    public var body: some View {
        HStack(spacing: 16) {
            // Left Formula Selector Sidebar
            formulaSelectorSidebar
                .frame(width: 265)

            // Main Graph Canvas + Controls + Floating HUD
            ZStack {
                graphCanvasContainer

                VStack(spacing: 0) {
                    graphTopToolbar
                        .padding(14)

                    Spacer()

                    HStack(alignment: .bottom, spacing: 14) {
                        graphLegendPill

                        Spacer()

                        if let inspected = inspectedPackage {
                            nodeInspectorHUD(for: inspected)
                                .frame(width: 340)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(14)
                }
            }
            .liquidGlassCard(cornerRadius: 20)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
        .onAppear {
            syncInitialSelection()
        }
        .onChange(of: store.selectedPackage) { _, newValue in
            if let pkg = newValue, !pkg.isCask {
                focusedPackageName = pkg.name
                selectedNodeName = pkg.name
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Formulae Nodes", systemImage: "point.3.filled.connected.trianglepath.dotted")
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.primary)
                Spacer()
                GlassBadge("\(filteredSidebarFormulae.count)", color: .cyan)
            }

            // Scope Switcher
            HStack(spacing: 6) {
                ForEach(GraphScopeMode.allCases) { mode in
                    let isSelected = scopeMode == mode
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                            scopeMode = mode
                            resetViewport()
                        }
                    } label: {
                        Text(mode.rawValue)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .foregroundStyle(isSelected ? Color.white : Color.secondary)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(isSelected ? Color.cyan.opacity(0.75) : Color.white.opacity(0.05))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.18))
            )

            // Search box + Leaves filter
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.secondary)
                TextField("Filter formulae...", text: $sidebarFilterText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .rounded))
                if !sidebarFilterText.isEmpty {
                    Button {
                        sidebarFilterText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
                    )
            )

            Toggle(isOn: $showLeavesOnlyInSidebar) {
                HStack(spacing: 5) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.mint)
                    Text("Top-level leaves only")
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.secondary)
                }
            }
            .toggleStyle(.checkbox)

            Divider()
                .overlay(Color.white.opacity(0.08))

            if filteredSidebarFormulae.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 26))
                        .foregroundStyle(Color.secondary)
                    Text("No matching formulae")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(filteredSidebarFormulae) { pkg in
                            let isSelected = (activeFocusedPackage?.name == pkg.name && scopeMode == .focused) || (selectedNodeName == pkg.name)
                            Button {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                    scopeMode = .focused
                                    focusedPackageName = pkg.name
                                    selectedNodeName = pkg.name
                                    store.selectedPackage = pkg
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(pkg.isLeaf ? Color.mint : Color.cyan)
                                        .frame(width: 7, height: 7)

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 5) {
                                            Text(pkg.name)
                                                .font(.system(size: 12.5, weight: isSelected ? .bold : .semibold, design: .rounded))
                                                .foregroundStyle(isSelected ? Color.white : Color.primary)
                                                .lineLimit(1)
                                            if pkg.isLeaf {
                                                Text("LEAF")
                                                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                                                    .padding(.horizontal, 4)
                                                    .padding(.vertical, 1)
                                                    .foregroundStyle(Color.mint)
                                                    .background(Capsule().fill(Color.mint.opacity(0.16)))
                                            }
                                        }
                                        let depCount = Set(pkg.dependencies + pkg.runtimeDependencies).count
                                        let revCount = store.reverseDependencies(for: pkg.name).count
                                        Text("\(depCount) deps • \(revCount) dependents")
                                            .font(.system(size: 10, weight: .regular, design: .rounded))
                                            .foregroundStyle(Color.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(isSelected ? Color.cyan : Color.secondary.opacity(0.5))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(isSelected ? Color.cyan.opacity(0.22) : Color.white.opacity(0.03))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .strokeBorder(isSelected ? Color.cyan.opacity(0.55) : Color.clear, lineWidth: 1)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: 20)
    }

    // MARK: - Top Graph Toolbar

    private var graphTopToolbar: some View {
        HStack(spacing: 10) {
            // Layout mode picker
            HStack(spacing: 4) {
                ForEach(GraphLayoutMode.allCases) { mode in
                    let isSelected = layoutMode == mode
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                            layoutMode = mode
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: mode == .radial ? "circle.hexagongrid.fill" : "list.bullet.indent")
                                .font(.system(size: 11, weight: .semibold))
                            Text(mode.rawValue)
                                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isSelected ? Color.cyan.opacity(0.8) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .liquidGlassCard(cornerRadius: 20)

            Spacer()

            // Zoom Controls
            HStack(spacing: 6) {
                GlassPillButton("", icon: "minus.magnifyingglass", tint: .cyan) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        zoomScale = max(0.45, zoomScale - 0.2)
                    }
                }
                Text("\(Int(zoomScale * 100))%")
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.secondary)
                    .frame(width: 46)
                GlassPillButton("", icon: "plus.magnifyingglass", tint: .cyan) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        zoomScale = min(2.4, zoomScale + 0.2)
                    }
                }
                GlassPillButton("Reset View", icon: "scope", tint: .indigo) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        resetViewport()
                    }
                }
            }
            .padding(5)
            .liquidGlassCard(cornerRadius: 20)
        }
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
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
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
        context.stroke(gridPath, with: .color(Color.white.opacity(0.035)), lineWidth: 0.7)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .liquidGlassCard(cornerRadius: 14)
    }

    private func legendDot(color: Color, title: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(Color.secondary)
        }
    }

    private func nodeInspectorHUD(for pkg: BrewPackage) -> some View {
        let directDeps = Array(Set(pkg.dependencies + pkg.runtimeDependencies)).sorted()
        let revDeps = store.reverseDependencies(for: pkg.name)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(pkg.name)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.primary)
                        GlassBadge(pkg.version, color: .cyan)
                        if pkg.isLeaf {
                            GlassBadge("Leaf", icon: "leaf.fill", color: .mint)
                        }
                    }
                    if let desc = pkg.desc, !desc.isEmpty {
                        Text(desc)
                            .font(.system(size: 11.5, design: .rounded))
                            .foregroundStyle(Color.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        selectedNodeName = nil
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                hudMetricPill(title: "Direct Deps", count: directDeps.count, color: .mint)
                hudMetricPill(title: "Used By", count: revDeps.count, color: .purple)
                hudMetricPill(title: "Tap", value: pkg.tap ?? "core", color: .cyan)
            }

            if !directDeps.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Requires (\(directDeps.count))")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.secondary)
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
                        .foregroundStyle(Color.secondary)
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
        .liquidGlassCard(cornerRadius: 16, tint: .cyan)
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
                .foregroundStyle(Color.secondary)
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

// MARK: - 2. Taps & Brewfile Manager

public struct TapsBrewfileView: View {
    @ObservedObject public var store: BrewStore

    @State private var newTapName: String = ""
    @State private var tapFilterText: String = ""

    public init(store: BrewStore) {
        self.store = store
    }

    private var filteredTaps: [BrewTap] {
        let query = tapFilterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty { return store.taps }
        return store.taps.filter {
            $0.name.lowercased().contains(query) ||
            ($0.remote?.lowercased().contains(query) ?? false)
        }
    }

    public var body: some View {
        HStack(spacing: 16) {
            // Left Column: Tap Repositories Manager
            tapsPanel
                .frame(maxWidth: .infinity)

            // Right Column: Brewfile Bundle Studio
            brewfileStudioPanel
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
        .task {
            if store.taps.isEmpty {
                await store.refreshTaps()
            }
            if store.brewfilePreview.isEmpty {
                await store.generateBrewfilePreview()
            }
        }
    }

    // MARK: - Taps Panel

    private var tapsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Panel Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Image(systemName: "spigot.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.cyan)
                        Text("Tap Repositories")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.primary)
                        GlassBadge("\(store.taps.count) Active", color: .cyan)
                    }
                    Text("Third-party & official formula/cask repositories")
                        .font(.system(size: 11.5, design: .rounded))
                        .foregroundStyle(Color.secondary)
                }
                Spacer()
                GlassPillButton("Refresh", icon: "arrow.clockwise", tint: .cyan, isDisabled: store.isLoading) {
                    Task { await store.refreshTaps() }
                }
            }

            // Add New Tap Bar
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.cyan)

                TextField("Add repository (e.g. homebrew/cask-fonts or user/repo)...", text: $newTapName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, design: .monospaced))
                    .onSubmit {
                        submitNewTap()
                    }

                GlassPillButton(
                    "Tap Repository",
                    icon: "arrow.down.circle.fill",
                    tint: .cyan,
                    isProminent: true,
                    isDisabled: newTapName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isRunningCommand
                ) {
                    submitNewTap()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .liquidGlassCard(cornerRadius: 14, tint: .cyan)

            // Filter bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondary)
                TextField("Search tapped repositories...", text: $tapFilterText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .rounded))
                if !tapFilterText.isEmpty {
                    Button {
                        tapFilterText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.8)
                    )
            )

            // Taps List
            if filteredTaps.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "spigot")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.secondary)
                    Text(store.taps.isEmpty ? "No Taps Found" : "No Matching Taps")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.primary)
                    Text("Add a GitHub repository in user/repo format above to expand available packages.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Color.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredTaps) { tap in
                            tapCard(tap)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(16)
        .liquidGlassCard(cornerRadius: 20)
    }

    private func tapCard(_ tap: BrewTap) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: tap.official ? "checkmark.seal.fill" : "shippingbox.and.arrow.backward.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(tap.official ? Color.mint : Color.cyan)

                Text(tap.name)
                    .font(.system(size: 13.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.primary)

                if tap.official {
                    GlassBadge("Official", icon: "star.fill", color: .mint)
                } else {
                    GlassBadge("Community", color: .indigo)
                }

                Spacer()

                GlassPillButton(
                    "Untap",
                    icon: "trash",
                    tint: .red,
                    isDisabled: store.isRunningCommand
                ) {
                    Task { await store.removeTap(name: tap.name) }
                }
            }

            if let remote = tap.remote, !remote.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondary)
                    Text(remote)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            HStack(spacing: 8) {
                GlassBadge("\(tap.formulaCount) Formulae", icon: "terminal", color: .cyan)
                GlassBadge("\(tap.caskCount) Casks", icon: "macwindow", color: .purple)
                if let path = tap.path, !path.isEmpty {
                    Text(path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.secondary.opacity(0.75))
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Spacer()
            }
        }
        .padding(12)
        .liquidGlassCard(cornerRadius: 14, tint: tap.official ? .mint : .cyan, isInteractive: true)
    }

    private func submitNewTap() {
        let trimmed = newTapName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        newTapName = ""
        Task {
            await store.addTap(name: trimmed)
        }
    }

    // MARK: - Brewfile Studio Panel

    private var brewfileStudioPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.indigo)
                        Text("Brewfile Bundle Studio")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.primary)
                    }
                    Text("Declarative system snapshot via brew bundle")
                        .font(.system(size: 11.5, design: .rounded))
                        .foregroundStyle(Color.secondary)
                }

                Spacer()

                GlassPillButton(
                    "Generate Preview",
                    icon: "wand.and.stars",
                    tint: .cyan,
                    isDisabled: store.isRunningCommand
                ) {
                    Task { await store.generateBrewfilePreview() }
                }
            }

            // Action Bar for Export & Import
            HStack(spacing: 10) {
                GlassPillButton(
                    "Export Brewfile...",
                    icon: "square.and.arrow.up.fill",
                    tint: .cyan,
                    isProminent: true,
                    isDisabled: store.isRunningCommand
                ) {
                    promptExportBrewfile()
                }

                GlassPillButton(
                    "Import / Run Brewfile...",
                    icon: "square.and.arrow.down.fill",
                    tint: .mint,
                    isDisabled: store.isRunningCommand
                ) {
                    promptImportBrewfile()
                }

                Spacer()

                if !store.brewfilePreview.isEmpty {
                    GlassPillButton("Copy", icon: "doc.on.doc", tint: .indigo) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(store.brewfilePreview, forType: .string)
                    }
                }
            }

            // Monospaced Syntax-Highlighted Code View
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.32))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    )

                let lines = brewfilePreviewLines
                ScrollView([.vertical, .horizontal]) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text("\(idx + 1)")
                                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                                    .foregroundStyle(Color.secondary.opacity(0.45))
                                    .frame(width: 28, alignment: .trailing)

                                styledBrewfileLine(line)
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(16)
        .liquidGlassCard(cornerRadius: 20)
    }

    private var brewfilePreviewLines: [String] {
        if !store.brewfilePreview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return store.brewfilePreview.components(separatedBy: .newlines)
        }
        // Synthesize live preview from current store state if preview hasn't been generated yet
        var synthesized: [String] = [
            "# LiquidBrew Declarative Bundle Preview",
            "# Click 'Generate Preview' to run `brew bundle dump` live",
            ""
        ]
        for tap in store.taps {
            synthesized.append("tap \"\(tap.name)\"")
        }
        if !store.taps.isEmpty { synthesized.append("") }
        for formula in store.installedPackages.filter({ !$0.isCask && $0.isLeaf }) {
            synthesized.append("brew \"\(formula.name)\"")
        }
        let casks = store.installedPackages.filter { $0.isCask }
        if !casks.isEmpty { synthesized.append("") }
        for cask in casks {
            synthesized.append("cask \"\(cask.name)\"")
        }
        return synthesized
    }

    private func styledBrewfileLine(_ line: String) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let color: Color
        if trimmed.hasPrefix("#") {
            color = Color.secondary
        } else if trimmed.hasPrefix("tap ") {
            color = Color.cyan
        } else if trimmed.hasPrefix("brew ") {
            color = Color.mint
        } else if trimmed.hasPrefix("cask ") {
            color = Color.purple
        } else if trimmed.hasPrefix("mas ") || trimmed.hasPrefix("vscode ") {
            color = Color.orange
        } else {
            color = Color.primary
        }

        return Text(line.isEmpty ? " " : line)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(color)
            .textSelection(.enabled)
    }

    private func promptExportBrewfile() {
        let panel = NSSavePanel()
        panel.title = "Export Homebrew Brewfile"
        panel.nameFieldStringValue = "Brewfile"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await store.exportBrewfile(to: url)
            }
        }
    }

    private func promptImportBrewfile() {
        let panel = NSOpenPanel()
        panel.title = "Import & Run Brewfile"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await store.importBrewfile(from: url)
            }
        }
    }
}

// MARK: - 3. System Health & Cleanup Center

public struct HealthCleanupView: View {
    @ObservedObject public var store: BrewStore

    @State private var showRawDoctorOutput: Bool = false

    public init(store: BrewStore) {
        self.store = store
    }

    private var report: BrewHealthReport {
        store.healthReport
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Top Hero Health Status Card
                healthHeroBanner

                // Three-Column / Grid Action Cards
                HStack(alignment: .top, spacing: 16) {
                    // 1. Brew Doctor Diagnostics
                    doctorDiagnosticsCard
                        .frame(maxWidth: .infinity)

                    // 2. Cache & Disk Space Cleanup
                    cacheCleanupCard
                        .frame(maxWidth: .infinity)

                    // 3. Orphaned Dependencies (Autoremove)
                    autoremoveCard
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 22)
        }
        .task {
            await store.refreshHealth()
        }
    }

    // MARK: - Hero Banner

    private var healthHeroBanner: some View {
        let isHealthy = report.isHealthy && report.warnings.isEmpty
        let statusTint: Color = isHealthy ? .mint : .orange

        return HStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [statusTint.opacity(0.45), statusTint.opacity(0.08)],
                            center: .center,
                            startRadius: 4,
                            endRadius: 36
                        )
                    )
                    .frame(width: 68, height: 68)
                    .overlay(
                        Circle()
                            .strokeBorder(statusTint.opacity(0.6), lineWidth: 1.5)
                    )

                Image(systemName: isHealthy ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(statusTint)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 10) {
                    Text(isHealthy ? "Your System is Ready to Brew" : "\(report.warnings.count) Doctor Warning\(report.warnings.count == 1 ? "" : "s") Detected")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.primary)

                    GlassBadge(
                        isHealthy ? "100% Healthy" : "Attention Needed",
                        icon: isHealthy ? "sparkles" : "stethoscope",
                        color: statusTint
                    )
                }

                HStack(spacing: 16) {
                    Label(report.brewVersion, systemImage: "mug.fill")
                    Label("Prefix: \(report.homebrewPrefix)", systemImage: "folder.fill")
                    Label("Cache: \(report.formattedCacheSize)", systemImage: "internaldrive.fill")
                    Label("Checked \(report.checkedAt.formatted(date: .omitted, time: .shortened))", systemImage: "clock.fill")
                }
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(Color.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                GlassPillButton(
                    "Run Full Check",
                    icon: "stethoscope",
                    tint: .cyan,
                    isProminent: true,
                    isDisabled: store.isRunningCommand
                ) {
                    Task {
                        await store.runDoctor()
                        await store.refreshHealth()
                    }
                }
            }
        }
        .padding(18)
        .liquidGlassCard(cornerRadius: 20, tint: statusTint)
    }

    // MARK: - 1. Brew Doctor Diagnostics Card

    private var doctorDiagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "stethoscope")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.cyan)
                Text("Brew Doctor Diagnostics")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.primary)
                Spacer()
                GlassBadge(
                    report.warnings.isEmpty ? "Clean" : "\(report.warnings.count) Issues",
                    color: report.warnings.isEmpty ? .mint : .orange
                )
            }

            Text("Audits your local Homebrew installation for broken symlinks, unlinked kegs, and PATH configuration issues.")
                .font(.system(size: 11.5, design: .rounded))
                .foregroundStyle(Color.secondary)

            HStack(spacing: 8) {
                GlassPillButton(
                    "Run Doctor",
                    icon: "play.fill",
                    tint: .cyan,
                    isProminent: true,
                    isDisabled: store.isRunningCommand
                ) {
                    Task { await store.runDoctor() }
                }

                GlassPillButton(
                    showRawDoctorOutput ? "Hide Raw Output" : "Raw Output",
                    icon: "terminal",
                    tint: .indigo
                ) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        showRawDoctorOutput.toggle()
                    }
                }
            }

            Divider()
                .overlay(Color.white.opacity(0.08))

            if showRawDoctorOutput {
                ScrollView {
                    Text(report.rawOutput.isEmpty ? "Your system is ready to brew." : report.rawOutput)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(10)
                }
                .frame(minHeight: 160, maxHeight: 260)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.28))
                )
            } else if report.warnings.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.mint)
                    Text("No Diagnostic Warnings")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.primary)
                    Text("All kegs, compilers, and environment variables passed inspection.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Color.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(report.warnings.enumerated()), id: \.offset) { _, warning in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.orange)
                                    .padding(.top, 2)
                                Text(warning)
                                    .font(.system(size: 11.5, design: .rounded))
                                    .foregroundStyle(Color.primary)
                                    .textSelection(.enabled)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.orange.opacity(0.1))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(Color.orange.opacity(0.3), lineWidth: 0.8)
                                    )
                            )
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
        .padding(16)
        .liquidGlassCard(cornerRadius: 20)
    }

    // MARK: - 2. Cache & Disk Space Cleanup Card

    private var cacheCleanupCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.purple)
                Text("Cache & Disk Cleanup")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.primary)
                Spacer()
                GlassBadge(report.formattedCacheSize, color: .purple)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Cached downloads & old bottle archives:")
                    .font(.system(size: 11.5, design: .rounded))
                    .foregroundStyle(Color.secondary)
                Text(report.cachePath)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Color.secondary.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack(spacing: 8) {
                GlassPillButton(
                    "Preview (Dry Run)",
                    icon: "magnifyingglass",
                    tint: .cyan,
                    isDisabled: store.isRunningCommand
                ) {
                    Task { await store.runCleanup(dryRun: true) }
                }

                GlassPillButton(
                    "Clean Cache Now",
                    icon: "sparkles",
                    tint: .purple,
                    isProminent: true,
                    isDisabled: store.isRunningCommand
                ) {
                    Task { await store.runCleanup(dryRun: false) }
                }
            }

            Divider()
                .overlay(Color.white.opacity(0.08))

            if report.cleanupDryRunItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 26))
                        .foregroundStyle(Color.purple.opacity(0.8))
                    Text("Cache is Tidy")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.primary)
                    Text("Click 'Preview (Dry Run)' to scan for stale downloads or outdated keg versions.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Color.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Reclaimable Items (\(report.cleanupDryRunItems.count))")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.secondary)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 5) {
                            ForEach(Array(report.cleanupDryRunItems.enumerated()), id: \.offset) { _, item in
                                HStack(spacing: 6) {
                                    Image(systemName: "doc.zipper")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color.purple)
                                    Text(item)
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundStyle(Color.primary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.white.opacity(0.04))
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 230)
                }
            }
        }
        .padding(16)
        .liquidGlassCard(cornerRadius: 20)
    }

    // MARK: - 3. Orphaned Dependencies (Autoremove) Card

    private var autoremoveCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "scissors")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.mint)
                Text("Orphaned Dependencies")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.primary)
                Spacer()
                GlassBadge("\(report.autoremoveCandidates.count) Orphans", color: report.autoremoveCandidates.isEmpty ? .mint : .orange)
            }

            Text("Formulae installed automatically as dependencies that are no longer required by any top-level package.")
                .font(.system(size: 11.5, design: .rounded))
                .foregroundStyle(Color.secondary)

            HStack(spacing: 8) {
                GlassPillButton(
                    "Run Autoremove",
                    icon: "trash.slash.fill",
                    tint: .mint,
                    isProminent: true,
                    isDisabled: store.isRunningCommand || report.autoremoveCandidates.isEmpty
                ) {
                    Task { await store.runAutoremove() }
                }

                GlassPillButton(
                    "Rescan",
                    icon: "arrow.clockwise",
                    tint: .cyan,
                    isDisabled: store.isLoading
                ) {
                    Task { await store.refreshHealth() }
                }
            }

            Divider()
                .overlay(Color.white.opacity(0.08))

            if report.autoremoveCandidates.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "leaf.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.mint)
                    Text("Zero Unused Dependencies")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.primary)
                    Text("Every installed dependency formula is actively referenced by an installed package.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(Color.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Unused Formulae (\(report.autoremoveCandidates.count))")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.secondary)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(report.autoremoveCandidates, id: \.self) { candidate in
                                HStack(spacing: 8) {
                                    Image(systemName: "cube.box")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.orange)
                                    Text(candidate)
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(Color.primary)
                                    Spacer()
                                    GlassBadge("Unused", color: .orange)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.orange.opacity(0.08))
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 230)
                }
            }
        }
        .padding(16)
        .liquidGlassCard(cornerRadius: 20)
    }
}
