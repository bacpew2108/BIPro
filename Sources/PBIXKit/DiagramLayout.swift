import Foundation

/// Model view layout stored by Power BI Desktop in the `DiagramLayout` part
/// (UTF-16LE JSON): one entry per layout tab, with table card positions.
public struct DiagramLayout: Sendable {
    public struct Node: Sendable, Hashable {
        public let table: String
        public let x: Double, y: Double
        public let width: Double, height: Double
        public let z: Double
    }

    public struct Diagram: Sendable, Hashable, Identifiable {
        public var id: String { name }
        public let name: String
        public let ordinal: Int
        /// Percent, e.g. 60.
        public let zoom: Double
        public let nodes: [Node]
    }

    public let diagrams: [Diagram]
    public let defaultDiagram: String?

    public init(json: JSONValue) {
        diagrams = json["diagrams"]?.array.map { d in
            Diagram(name: d["name"]?.string ?? "All tables",
                    ordinal: Int(d["ordinal"]?.number ?? 0),
                    zoom: d["zoomValue"]?.number ?? 100,
                    nodes: d["nodes"]?.array.compactMap { n in
                        guard let table = n["nodeIndex"]?.string else { return nil }
                        return Node(table: table,
                                    x: n["location"]?["x"]?.number ?? 0, y: n["location"]?["y"]?.number ?? 0,
                                    width: n["size"]?["width"]?.number ?? 234, height: n["size"]?["height"]?.number ?? 224,
                                    z: n["zIndex"]?.number ?? 0)
                    } ?? [])
        }.sorted { $0.ordinal < $1.ordinal } ?? []
        defaultDiagram = json["defaultDiagram"]?.string
    }
}

extension PBIXFile {
    /// Present in files saved by the legacy format; PBIR-era files may omit it.
    public func loadDiagramLayout() -> DiagramLayout? {
        guard archive.entry("DiagramLayout") != nil,
              let text = try? utf16Part("DiagramLayout"),
              let json = try? JSONValue.parse(text) else { return nil }
        return DiagramLayout(json: json)
    }
}
