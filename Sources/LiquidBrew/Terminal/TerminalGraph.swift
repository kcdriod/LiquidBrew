import Foundation

typealias DependencyGraphSnapshot = (nodes: [GraphNodeItem], edges: [GraphEdgeItem])

struct TerminalGraphState {
    static let world = CGSize(width: 1000, height: 700)
    var layout = GraphLayoutMode.radial
    var scope = GraphScopeMode.focused
    var focusedName = ""
    var selectedName: String?
    var leavesOnly = false
    var zoom: CGFloat = 1
    var pan = CGSize.zero
    var expanded = false
    var inspector = false
    private var cachedPackages: [BrewPackage] = []
    private var cachedFocus = ""
    private var cachedLayout = GraphLayoutMode.radial
    private var cachedScope = GraphScopeMode.focused
    private var cachedGraph: DependencyGraphSnapshot = ([], [])
    private var targetPositions: [String: CGPoint] = [:]
    private var previousPositions: [String: CGPoint] = [:]
    private var displayedPositions: [String: CGPoint] = [:]
    private var transitionTime: Float = 0

    mutating func focus(_ name: String) {
        focusedName = name
        selectedName = name
        scope = .focused
    }

    mutating func resetViewport() { zoom = 1; pan = .zero }

    mutating func snapshot(packages: [BrewPackage], fallback: String?) -> DependencyGraphSnapshot {
        if !packages.contains(where: { $0.name == focusedName && !$0.isCask }) {
            focusedName = fallback ?? packages.first(where: { !$0.isCask })?.name ?? ""
        }
        if cachedPackages != packages || cachedFocus != focusedName || cachedLayout != layout || cachedScope != scope {
            cachedGraph = DependencyGraphLayout(packages: packages, focusedPackageName: focusedName, scopeMode: scope, layoutMode: layout).computeGraph(in: Self.world)
            cachedPackages = packages
            cachedFocus = focusedName
            cachedLayout = layout
            cachedScope = scope
        }
        if !cachedGraph.nodes.contains(where: { $0.id == selectedName }) {
            selectedName = cachedGraph.nodes.first?.id
        }
        return cachedGraph
    }

    func project(_ point: CGPoint, width: Int, height: Int) -> CGPoint {
        let center = CGPoint(x: Self.world.width / 2, y: Self.world.height / 2)
        return CGPoint(
            x: ((point.x - center.x) * zoom + center.x + pan.width) / Self.world.width * CGFloat(max(1, width - 1)),
            y: ((point.y - center.y) * zoom + center.y + pan.height) / Self.world.height * CGFloat(max(1, height - 1))
        )
    }

    mutating func interpolatedPositions(nodes: [GraphNodeItem], time: Float) -> [String: CGPoint] {
        let targets = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.position) })
        if targets != targetPositions {
            previousPositions = displayedPositions.isEmpty ? targets : displayedPositions
            targetPositions = targets
            transitionTime = time
        }
        let progress = CGFloat(max(0, min(1, (time - transitionTime) / 0.35)))
        let eased = progress * progress * (3 - 2 * progress)
        displayedPositions = targets
        for (name, target) in targets {
            let start = previousPositions[name] ?? target
            displayedPositions[name] = CGPoint(x: start.x + (target.x - start.x) * eased,
                                               y: start.y + (target.y - start.y) * eased)
        }
        return displayedPositions
    }
}

@MainActor
extension TerminalApp {
    var graphData: DependencyGraphSnapshot {
        graph.snapshot(packages: store.installedPackages, fallback: current?.package?.name)
    }

    var selectedGraphNode: GraphNodeItem? {
        graphData.nodes.first { $0.id == graph.selectedName }
    }

    func handleGraph(_ key: TerminalKey) -> Bool {
        switch key {
        case .left: graph.pan.width += 80
        case .right: graph.pan.width -= 80
        case .up: graph.pan.height += 70
        case .down: graph.pan.height -= 70
        case .text("+"), .text("="): graph.zoom = min(2.4, graph.zoom + 0.2)
        case .text("-"): graph.zoom = max(0.45, graph.zoom - 0.2)
        case .text("0"): graph.resetViewport()
        case .text("t"):
            graph.layout = graph.layout == .radial ? .hierarchical : .radial
            graph.resetViewport()
        case .text("n"):
            graph.scope = graph.scope == .focused ? .leavesNetwork : .focused
            graph.resetViewport()
        case .text("f"):
            graph.leavesOnly.toggle()
            selected = 0
        case .text("v"): graph.expanded.toggle()
        case .text("i"): graph.inspector.toggle(); detailOffset = 0
        case .tab, .text("]"): cycleGraphNode(1)
        case .text("["): cycleGraphNode(-1)
        case .enter:
            guard let node = selectedGraphNode, node.package != nil else {
                message = "Referenced dependency is not installed · i inspects it"
                return true
            }
            graph.focus(node.id)
            store.searchText = ""
            selected = rows.firstIndex(where: { $0.package?.name == node.id }) ?? 0
            graph.inspector = false
            graph.resetViewport()
            message = "Focused on \(node.id)"
        case .text("e"):
            guard let node = selectedGraphNode, let package = node.package else {
                message = "This dependency has no installed package entry"
                return true
            }
            tab = .packages
            store.packageFilter = .all
            store.searchText = ""
            selected = store.filteredPackages.firstIndex(where: { $0.id == package.id }) ?? 0
            detailExpanded = false
            detailOffset = 0
        case .escape where graph.inspector: graph.inspector = false
        case .pageUp where !graph.inspector && !showConsole: graph.pan.height += 160
        case .pageDown where !graph.inspector && !showConsole: graph.pan.height -= 160
        default: return false
        }
        return true
    }

    private func cycleGraphNode(_ direction: Int) {
        let nodes = graphData.nodes
        guard !nodes.isEmpty else { return }
        let index = nodes.firstIndex { $0.id == graph.selectedName } ?? 0
        graph.selectedName = nodes[(index + direction + nodes.count) % nodes.count].id
        detailOffset = 0
        if let node = selectedGraphNode {
            // Bring a keyboard-selected node into view after zooming or panning.
            graph.pan = CGSize(width: (TerminalGraphState.world.width / 2 - node.position.x) * graph.zoom,
                               height: (TerminalGraphState.world.height / 2 - node.position.y) * graph.zoom)
        }
    }

    func drawDependencyGraph(_ frame: inout TerminalFrame, x: Int, y: Int, width: Int, height: Int, time: Float) {
        let data = graphData
        let layout = graph.layout == .radial ? "RADIAL" : "TREE"
        let scope = graph.scope == .focused ? "FOCUSED" : "TOP-LEVEL NETWORK"
        frame.box(x: x, y: y, width: width, height: height, title: "\(layout) · \(scope) · \(Int(graph.zoom * 100))%")
        frame.text("t layout · n scope · +/- zoom · 0 reset · v expand", x: x + 2, y: y + 1, limit: width - 4, color: .muted)
        let canvasX = x + 2
        let canvasY = y + 3
        let canvasWidth = width - 4
        let canvasHeight = height - 6
        guard canvasWidth > 0, canvasHeight > 0 else { return }
        var canvas = TerminalFrame(width: canvasWidth, height: canvasHeight)
        canvas.fill(x: 0, y: 0, width: canvasWidth, height: canvasHeight, background: .panel)
        let interpolated = graph.interpolatedPositions(nodes: data.nodes, time: time)
        let positions = interpolated.mapValues { graph.project($0, width: canvasWidth, height: canvasHeight) }
        for (index, edge) in data.edges.enumerated() {
            guard let from = positions[edge.from], let to = positions[edge.to] else { continue }
            let highlighted = edge.from == graph.selectedName || edge.to == graph.selectedName
            let color: TerminalRGB = edge.isReverse ? .purple : (highlighted ? .cyan : .muted)
            let steps = max(8, min(600, Int(abs(to.x - from.x) + abs(to.y - from.y)) * 2))
            for step in 0...steps {
                if edge.isReverse && step % 6 < 2 { continue }
                let point = curvePoint(CGFloat(step) / CGFloat(steps), from: from, to: to)
                canvas.text(edge.isReverse ? "·" : "∙", x: Int(point.x.rounded()), y: Int(point.y.rounded()), color: color)
            }
            let phase = CGFloat((Double(time) * 0.4 + Double(index) * 0.13).truncatingRemainder(dividingBy: 1))
            let point = curvePoint(phase, from: from, to: to)
            canvas.text("●", x: Int(point.x.rounded()), y: Int(point.y.rounded()), color: color)
        }
        var occupied = Set<Int>()
        let ordered = data.nodes.sorted { left, right in
            if (left.id == graph.selectedName) != (right.id == graph.selectedName) { return left.id == graph.selectedName }
            if left.depth != right.depth { return left.depth < right.depth }
            return left.id < right.id
        }
        var visible = 0
        for node in ordered {
            guard let point = positions[node.id] else { continue }
            let nodeX = Int(point.x.rounded())
            let nodeY = Int(point.y.rounded())
            guard nodeX >= 0, nodeX < canvasWidth, nodeY >= 0, nodeY < canvasHeight else { continue }
            visible += 1
            let selected = node.id == graph.selectedName
            let color = graphColor(node.role)
            let label = TerminalText.clipped("\(selected ? "[" : "")\(node.label)\(selected ? "]" : "")", to: min(24, canvasWidth))
            let length = label.reduce(0) { $0 + TerminalText.width($1) }
            let labelX = max(0, min(canvasWidth - length, nodeX - length / 2))
            let candidates = [0, -1, 1, -2, 2, -3, 3].map { nodeY + $0 }.filter { $0 >= 0 && $0 < canvasHeight }
            if let labelY = candidates.first(where: { row in
                (max(0, labelX - 1)..<min(canvasWidth, labelX + length + 1)).allSatisfy { !occupied.contains(row * canvasWidth + $0) }
            }) {
                canvas.fill(x: labelX, y: labelY, width: length, height: 1, background: selected ? TerminalRGB(r: 35, g: 65, b: 80) : .panel)
                canvas.text(label, x: labelX, y: labelY, color: color, bold: selected || node.role == .root)
                for column in max(0, labelX - 1)..<min(canvasWidth, labelX + length + 1) { occupied.insert(labelY * canvasWidth + column) }
                if labelY != nodeY && !occupied.contains(nodeY * canvasWidth + nodeX) { canvas.text("○", x: nodeX, y: nodeY, color: color) }
            } else if !occupied.contains(nodeY * canvasWidth + nodeX) {
                canvas.text("○", x: nodeX, y: nodeY, color: color)
            }
        }
        for row in 0..<canvasHeight {
            for column in 0..<canvasWidth { frame.cells[(canvasY + row) * frame.width + canvasX + column] = canvas.cells[row * canvasWidth + column] }
        }
        frame.text("\(visible)/\(data.nodes.count) nodes · \(data.edges.count) edges · [ ] select · i inspect", x: x + 2, y: y + height - 2, limit: width - 4, color: .cyan)
        let legends: [(GraphNodeRole, String)] = [(.root, "Root"), (.directDependency, "Direct"), (.transitiveDependency, "Transitive"), (.reverseDependent, "Used by"), (.leafNode, "Leaf")]
        var legendX = x + 2
        for (role, title) in legends {
            guard legendX + title.count + 3 < x + width else { break }
            frame.text(" \(title) ", x: legendX, y: y + height - 1, color: graphColor(role))
            legendX += title.count + 3
        }
        if let selected = selectedGraphNode {
            message = "\(selected.label) · \(roleTitle(selected.role)) · Enter focus · e Packages · arrows pan"
        }
        if graph.inspector { drawGraphInspector(&frame, x: x, y: y, width: width, height: height) }
    }

    private func curvePoint(_ t: CGFloat, from: CGPoint, to: CGPoint) -> CGPoint {
        let inverse = 1 - t
        if graph.layout == .hierarchical {
            let midX = (from.x + to.x) / 2
            return CGPoint(x: pow(inverse, 3) * from.x + 3 * inverse * inverse * t * midX + 3 * inverse * t * t * midX + pow(t, 3) * to.x,
                           y: pow(inverse, 3) * from.y + 3 * inverse * inverse * t * from.y + 3 * inverse * t * t * to.y + pow(t, 3) * to.y)
        }
        let control = CGPoint(x: (from.x + to.x) / 2 - (to.y - from.y) * 0.14,
                              y: (from.y + to.y) / 2 + (to.x - from.x) * 0.14)
        return CGPoint(x: inverse * inverse * from.x + 2 * inverse * t * control.x + t * t * to.x,
                       y: inverse * inverse * from.y + 2 * inverse * t * control.y + t * t * to.y)
    }

    private func drawGraphInspector(_ frame: inout TerminalFrame, x: Int, y: Int, width: Int, height: Int) {
        guard let node = selectedGraphNode else { return }
        frame.box(x: x, y: y, width: width, height: height, title: "Node Inspector · i / Esc closes")
        let package = node.package
        let deps = Array(Set((package?.dependencies ?? []) + (package?.runtimeDependencies ?? []))).sorted()
        let reverse = store.reverseDependencies(for: node.id).map(\.name)
        let text = [node.label, roleTitle(node.role), package?.desc ?? "Referenced dependency · not installed", "Version  \(package?.version ?? "runtime")", "Tap      \(package?.tap ?? "—")", "", "REQUIRES (\(deps.count))"] + deps + ["", "REQUIRED BY (\(reverse.count))"] + reverse + ["", "[ / ] select nodes · Enter focus · e inspect in Packages"]
        let lines = text.flatMap { TerminalText.wrapped($0, width: width - 6) }
        let visible = max(1, height - 4)
        detailOffset = min(detailOffset, max(0, lines.count - visible))
        for (offset, line) in lines.dropFirst(detailOffset).prefix(visible).enumerated() {
            frame.text(line, x: x + 3, y: y + 2 + offset, limit: width - 6, color: offset == 0 ? .cyan : .text)
        }
    }

    private func graphColor(_ role: GraphNodeRole) -> TerminalRGB {
        switch role {
        case .root: return .cyan
        case .directDependency: return TerminalRGB(r: 114, g: 241, b: 175)
        case .transitiveDependency: return TerminalRGB(r: 71, g: 185, b: 181)
        case .reverseDependent: return .purple
        case .leafNode: return TerminalRGB(r: 152, g: 175, b: 255)
        }
    }

    private func roleTitle(_ role: GraphNodeRole) -> String {
        switch role {
        case .root: return "Root formula"
        case .directDependency: return "Direct dependency"
        case .transitiveDependency: return "Transitive dependency"
        case .reverseDependent: return "Used by (reverse)"
        case .leafNode: return "Top-level formula"
        }
    }
}
