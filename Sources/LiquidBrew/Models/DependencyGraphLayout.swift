import Foundation

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

enum GraphNodeRole: Equatable {
    case root
    case directDependency
    case transitiveDependency
    case reverseDependent
    case leafNode
}

struct GraphNodeItem: Identifiable, Equatable {
    let id: String // package name
    let label: String
    let role: GraphNodeRole
    let position: CGPoint
    let package: BrewPackage?
    let depth: Int
}

struct GraphEdgeItem: Identifiable, Equatable {
    var id: String { "\(from)->\(to)" }
    let from: String
    let to: String
    let isReverse: Bool
    let depth: Int
}

// Both interfaces use the same node roles, scope limits, edges, and layout coordinates.
struct DependencyGraphLayout {
    let packages: [BrewPackage]
    let focusedPackageName: String
    let scopeMode: GraphScopeMode
    let layoutMode: GraphLayoutMode

    private var installedFormulae: [BrewPackage] {
        packages.filter { !$0.isCask }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var packageMap: [String: BrewPackage] {
        Dictionary(installedFormulae.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var activeFocusedPackage: BrewPackage? { packageMap[focusedPackageName] }

    private func reverseDependencies(for name: String) -> [BrewPackage] {
        packages.filter { $0.dependencies.contains(name) || $0.runtimeDependencies.contains(name) }
    }

    func computeGraph(in size: CGSize) -> (nodes: [GraphNodeItem], edges: [GraphEdgeItem]) {
        guard size.width > 50, size.height > 50 else { return ([], []) }

        let graph = scopeMode == .leavesNetwork
            ? computeLeavesNetworkGraph(in: size)
            : computeFocusedFormulaGraph(in: size)
        var seen = Set<String>()
        let nodes = graph.nodes.filter { seen.insert($0.id).inserted }
        var seenEdges = Set<String>()
        let edges = graph.edges.filter {
            seen.contains($0.from) && seen.contains($0.to) && seenEdges.insert($0.id).inserted
        }
        return (nodes, edges)
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
        let reverseDeps = reverseDependencies(for: rootPkg.name).map(\.name).sorted()

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

}
