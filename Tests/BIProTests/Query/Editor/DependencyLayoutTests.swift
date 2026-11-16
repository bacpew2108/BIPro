import Foundation
import Testing
@testable import BIPro

@Suite struct DependencyLayoutTests {

    @Test func testLinearPipelineDepthsAndOrder() {
        // Raw (source a.xlsx) -> Clean -> Final
        let nodes = [
            DependencyNode(id: "source:a.xlsx", title: "a.xlsx", kind: .source, enableLoad: true),
            DependencyNode(id: "query:Raw", title: "Raw", kind: .query, enableLoad: true),
            DependencyNode(id: "query:Clean", title: "Clean", kind: .query, enableLoad: true),
            DependencyNode(id: "query:Final", title: "Final", kind: .query, enableLoad: true)
        ]
        let edges = [
            DependencyEdge(from: "source:a.xlsx", to: "query:Raw"),
            DependencyEdge(from: "query:Raw", to: "query:Clean"),
            DependencyEdge(from: "query:Clean", to: "query:Final")
        ]
        let graph = DependencyGraphModel(nodes: nodes, edges: edges, cycle: nil)

        let layout = DependencyLayout(graph: graph)

        // Depths: 0, 1, 2, 3
        #expect(layout.depth(of: "source:a.xlsx") == 0)
        #expect(layout.depth(of: "query:Raw") == 1)
        #expect(layout.depth(of: "query:Clean") == 2)
        #expect(layout.depth(of: "query:Final") == 3)

        // Stable (column, row) coordinates
        #expect(layout.position(of: "source:a.xlsx") == DependencyPosition(column: 0, row: 0))
        #expect(layout.position(of: "query:Raw") == DependencyPosition(column: 1, row: 0))
        #expect(layout.position(of: "query:Clean") == DependencyPosition(column: 2, row: 0))
        #expect(layout.position(of: "query:Final") == DependencyPosition(column: 3, row: 0))

        // Downstream and Upstream
        #expect(layout.downstream(of: "query:Raw") == ["query:Clean", "query:Final"])
        #expect(layout.downstream(of: "query:Clean") == ["query:Final"])
        #expect(layout.downstream(of: "query:Final").isEmpty)

        #expect(layout.upstream(of: "query:Final") == ["query:Clean", "query:Raw", "source:a.xlsx"])
        #expect(layout.upstream(of: "query:Raw") == ["source:a.xlsx"])
        #expect(layout.upstream(of: "source:a.xlsx").isEmpty)
    }

    @Test func testMultipleSourcesAndBranches() {
        // Sources s1, s2
        // q1 uses s1, q2 uses s2
        // q3 merges q1 and q2 (uses both)
        let nodes = [
            DependencyNode(id: "source:s1", title: "s1", kind: .source, enableLoad: true),
            DependencyNode(id: "source:s2", title: "s2", kind: .source, enableLoad: true),
            DependencyNode(id: "query:q1", title: "q1", kind: .query, enableLoad: true),
            DependencyNode(id: "query:q2", title: "q2", kind: .query, enableLoad: false),
            DependencyNode(id: "query:q3", title: "q3", kind: .query, enableLoad: true)
        ]
        let edges = [
            DependencyEdge(from: "source:s1", to: "query:q1"),
            DependencyEdge(from: "source:s2", to: "query:q2"),
            DependencyEdge(from: "query:q1", to: "query:q3"),
            DependencyEdge(from: "query:q2", to: "query:q3")
        ]
        let graph = DependencyGraphModel(nodes: nodes, edges: edges, cycle: nil)
        let layout = DependencyLayout(graph: graph)

        #expect(layout.depth(of: "source:s1") == 0)
        #expect(layout.depth(of: "source:s2") == 0)
        #expect(layout.depth(of: "query:q1") == 1)
        #expect(layout.depth(of: "query:q2") == 1)
        #expect(layout.depth(of: "query:q3") == 2)

        #expect(layout.position(of: "source:s1") == DependencyPosition(column: 0, row: 0))
        #expect(layout.position(of: "source:s2") == DependencyPosition(column: 0, row: 1))
        #expect(layout.position(of: "query:q1") == DependencyPosition(column: 1, row: 0))
        #expect(layout.position(of: "query:q2") == DependencyPosition(column: 1, row: 1))
        #expect(layout.position(of: "query:q3") == DependencyPosition(column: 2, row: 0))

        #expect(layout.upstream(of: "query:q3") == ["query:q1", "query:q2", "source:s1", "source:s2"])
        #expect(layout.downstream(of: "source:s1") == ["query:q1", "query:q3"])
    }

    @Test func testCycleDoesNotHang() {
        // A <-> B cycle
        let nodes = [
            DependencyNode(id: "query:A", title: "A", kind: .query, enableLoad: true),
            DependencyNode(id: "query:B", title: "B", kind: .query, enableLoad: true)
        ]
        let edges = [
            DependencyEdge(from: "query:A", to: "query:B"),
            DependencyEdge(from: "query:B", to: "query:A")
        ]
        let graph = DependencyGraphModel(nodes: nodes, edges: edges, cycle: ["A", "B", "A"])

        let layout = DependencyLayout(graph: graph)

        // Must not hang, depths should be assigned
        let depthA = layout.depth(of: "query:A")
        let depthB = layout.depth(of: "query:B")
        #expect(depthA >= 1)
        #expect(depthB >= 1)

        // Upstream and Downstream must terminate and not include the node itself
        let upA = layout.upstream(of: "query:A")
        let downA = layout.downstream(of: "query:A")
        #expect(upA.contains("query:B"))
        #expect(!upA.contains("query:A"))
        #expect(downA.contains("query:B"))
        #expect(!downA.contains("query:A"))
    }

    @Test func testStandaloneQueryHasDepthOne() {
        let nodes = [
            DependencyNode(id: "query:Alone", title: "Alone", kind: .query, enableLoad: true)
        ]
        let graph = DependencyGraphModel(nodes: nodes, edges: [], cycle: nil)
        let layout = DependencyLayout(graph: graph)
        #expect(layout.depth(of: "query:Alone") == 1)
        #expect(layout.position(of: "query:Alone") == DependencyPosition(column: 1, row: 0))
        #expect(layout.upstream(of: "query:Alone").isEmpty)
        #expect(layout.downstream(of: "query:Alone").isEmpty)
    }
}
