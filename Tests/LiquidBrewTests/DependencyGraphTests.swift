import XCTest
@testable import LiquidBrew

final class DependencyGraphTests: XCTestCase {
    private var packages: [BrewPackage] {
        [BrewPackage(name: "root", version: "1", isLeaf: true, dependencies: ["direct"], runtimeDependencies: ["runtime"]),
         BrewPackage(name: "direct", version: "1", isLeaf: false, dependencies: ["transitive"]),
         BrewPackage(name: "transitive", version: "1", isLeaf: false),
         BrewPackage(name: "consumer", version: "1", dependencies: ["root"]),
         BrewPackage(name: "app", version: "1", isCask: true, dependencies: ["root"])]
    }

    func testFocusedGraphHasGuiRolesAndRuntimeReverseAndTransitiveEdges() {
        let data = DependencyGraphLayout(packages: packages, focusedPackageName: "root", scopeMode: .focused, layoutMode: .radial).computeGraph(in: TerminalGraphState.world)
        let roles = Dictionary(uniqueKeysWithValues: data.nodes.map { ($0.id, $0.role) })
        XCTAssertEqual(roles["root"], .root)
        XCTAssertEqual(roles["direct"], .directDependency)
        XCTAssertEqual(roles["runtime"], .directDependency)
        XCTAssertEqual(roles["consumer"], .reverseDependent)
        XCTAssertEqual(roles["transitive"], .transitiveDependency)
        XCTAssertEqual(roles["app"], .reverseDependent)
        XCTAssertNil(data.nodes.first { $0.id == "runtime" }?.package)
        XCTAssertTrue(data.edges.contains { $0.from == "direct" && $0.to == "transitive" && $0.depth == 2 })
        XCTAssertTrue(data.edges.contains { $0.from == "consumer" && $0.to == "root" && $0.isReverse })
    }

    func testBothLayoutsHaveTheSameRelationshipsAndDifferentCoordinates() {
        for scope in GraphScopeMode.allCases {
            let radial = DependencyGraphLayout(packages: packages, focusedPackageName: "root", scopeMode: scope, layoutMode: .radial).computeGraph(in: TerminalGraphState.world)
            let tree = DependencyGraphLayout(packages: packages, focusedPackageName: "root", scopeMode: scope, layoutMode: .hierarchical).computeGraph(in: TerminalGraphState.world)
            XCTAssertEqual(Set(radial.nodes.map(\.id)), Set(tree.nodes.map(\.id)))
            XCTAssertEqual(Set(radial.edges.map(\.id)), Set(tree.edges.map(\.id)))
            XCTAssertNotEqual(radial.nodes.map(\.position), tree.nodes.map(\.position))
        }
    }

    func testCyclesDoNotDuplicateNodeIdsOrLeaveDanglingEdges() {
        let packages = [BrewPackage(name: "root", version: "1", dependencies: ["other"]), BrewPackage(name: "other", version: "1", dependencies: ["root"])]
        let data = DependencyGraphLayout(packages: packages, focusedPackageName: "root", scopeMode: .focused, layoutMode: .radial).computeGraph(in: TerminalGraphState.world)
        let ids = Set(data.nodes.map(\.id))
        XCTAssertEqual(ids.count, data.nodes.count)
        XCTAssertTrue(data.edges.allSatisfy { ids.contains($0.from) && ids.contains($0.to) })
    }

    func testNetworkUsesTheSameBoundsAsTheGui() {
        let many = (0..<30).map { index in BrewPackage(name: "leaf\(index)", version: "1", isLeaf: true, dependencies: (0..<8).map { "dep\(index)-\($0)" }) }
        let data = DependencyGraphLayout(packages: many, focusedPackageName: "leaf0", scopeMode: .leavesNetwork, layoutMode: .radial).computeGraph(in: TerminalGraphState.world)
        XCTAssertEqual(data.nodes.filter { $0.role == .leafNode }.count, 14)
        XCTAssertLessThanOrEqual(data.nodes.filter { $0.role == .directDependency }.count, 18)
        XCTAssertTrue(data.edges.allSatisfy { $0.depth == 1 && !$0.isReverse })
    }

    @MainActor func testTerminalGraphControlsSelectionFocusAndPackageJump() throws {
        let app = TerminalApp(options: try TerminalOptions(arguments: ["--demo"]), animation: try TerminalAnimation(mode: "cpu"))
        app.store.installedPackages = packages
        app.tab = .graph
        app.graph.focus("root")
        app.handle(.text("t"))
        XCTAssertEqual(app.graph.layout, .hierarchical)
        app.handle(.text("n"))
        XCTAssertEqual(app.graph.scope, .leavesNetwork)
        app.handle(.text("n"))
        app.handle(.text("+"))
        XCTAssertGreaterThan(app.graph.zoom, 1)
        app.handle(.right)
        XCTAssertLessThan(app.graph.pan.width, 0)
        app.handle(.text("0"))
        XCTAssertEqual(app.graph.zoom, 1)
        XCTAssertEqual(app.graph.pan, .zero)
        app.graph.selectedName = "direct"
        app.handle(.text("i"))
        XCTAssertTrue(app.graph.inspector)
        app.handle(.escape)
        XCTAssertFalse(app.graph.inspector)
        app.handle(.enter)
        XCTAssertEqual(app.graph.focusedName, "direct")
        XCTAssertEqual(app.graph.scope, .focused)
        app.handle(.text("e"))
        XCTAssertEqual(app.tab, .packages)
        XCTAssertEqual(app.current?.package?.name, "direct")
    }

    @MainActor func testUninstalledNodeCanBeInspectedWithoutRefocusingOrPackageMutation() throws {
        let app = TerminalApp(options: try TerminalOptions(arguments: ["--demo"]), animation: try TerminalAnimation(mode: "cpu"))
        app.store.installedPackages = packages
        app.tab = .graph
        app.graph.focus("root")
        app.graph.selectedName = "runtime"
        app.handle(.enter)
        XCTAssertEqual(app.graph.focusedName, "root")
        app.handle(.text("e"))
        XCTAssertEqual(app.tab, .graph)
        app.handle(.text("x"))
        XCTAssertNil(app.confirmation)
        app.handle(.text("i"))
        XCTAssertTrue(app.screen(width: 100, height: 34, time: 0).plainText.contains("runtime"))
    }

    func testCoordinatesAnimateBetweenLayoutsAndPanZoomProject() {
        var graph = TerminalGraphState()
        let root = BrewPackage(name: "root", version: "1")
        let start = GraphNodeItem(id: "root", label: "root", role: .root, position: CGPoint(x: 100, y: 100), package: root, depth: 0)
        let end = GraphNodeItem(id: "root", label: "root", role: .root, position: CGPoint(x: 900, y: 600), package: root, depth: 0)
        _ = graph.interpolatedPositions(nodes: [start], time: 0)
        _ = graph.interpolatedPositions(nodes: [end], time: 1)
        let halfway = graph.interpolatedPositions(nodes: [end], time: 1.175)["root"]!
        XCTAssertEqual(halfway.x, 500, accuracy: 1)
        XCTAssertEqual(graph.interpolatedPositions(nodes: [end], time: 2)["root"], end.position)
        XCTAssertEqual(graph.project(CGPoint(x: 500, y: 350), width: 101, height: 71), CGPoint(x: 50, y: 35))
    }

    @MainActor func testGraphRendersEveryModeAtCompactAndWideSizes() throws {
        let app = TerminalApp(options: try TerminalOptions(arguments: ["--demo"]), animation: try TerminalAnimation(mode: "cpu"))
        app.store.installedPackages = packages
        app.tab = .graph
        app.graph.focus("root")
        for scope in GraphScopeMode.allCases {
            for layout in GraphLayoutMode.allCases {
                app.graph.scope = scope
                app.graph.layout = layout
                for width in [80, 120, 180] {
                    for height in [24, 40] {
                        for inspector in [false, true] {
                            app.graph.inspector = inspector
                            let frame = app.screen(width: width, height: height, time: 1)
                            XCTAssertEqual(frame.cells.count, width * height)
                            XCTAssertTrue(frame.plainText.contains(inspector ? "Node Inspector" : (layout == .radial ? "RADIAL" : "TREE")))
                        }
                    }
                }
            }
        }
    }
}
