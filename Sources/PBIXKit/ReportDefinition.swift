import Foundation

/// Format-neutral report definition, decoded from either PBIR (`Report/definition/**`)
/// or the legacy single-file `Report/Layout`.
public struct ReportDefinition: Sendable {
    public var pages: [ReportPage]
    public var baseThemeName: String?
    public var customThemeName: String?

    public init(pages: [ReportPage], baseThemeName: String? = nil, customThemeName: String? = nil) {
        self.pages = pages
        self.baseThemeName = baseThemeName
        self.customThemeName = customThemeName
    }
}

public struct ReportPage: Sendable, Identifiable, Hashable {
    public let id: String
    public var displayName: String
    public var width: Double
    public var height: Double
    public var isHidden: Bool
    public var objects: ObjectProperties
    public var visuals: [ReportVisual]
    /// Nhóm visual (PBIR `visualGroup`, D7): `type == "visualGroup"`, khung tuyệt đối trên trang, không có truy vấn.
    /// Các visual con nằm trong `visuals` với `parentGroup` và toạ độ tuyệt đối.
    public var groups: [ReportVisual]

    public init(id: String, displayName: String, width: Double, height: Double, isHidden: Bool = false,
                objects: ObjectProperties = ObjectProperties(nil), visuals: [ReportVisual] = [], groups: [ReportVisual] = []) {
        self.id = id; self.displayName = displayName; self.width = width; self.height = height
        self.isHidden = isHidden; self.objects = objects; self.visuals = visuals; self.groups = groups
    }
}

public struct ReportVisual: Sendable, Identifiable, Hashable {
    public let id: String
    public var type: String
    public var x: Double, y: Double, z: Double
    public var width: Double, height: Double
    public var isHidden: Bool
    public var objects: ObjectProperties
    public var containerObjects: ObjectProperties
    public var fields: [ReportField]
    /// JSON gốc của visual (PBIR: cả `visual.json`; legacy: `singleVisual`). Bộ đọc truy vấn (Phase C) cần
    /// `query.queryState` có thứ tự, `active`, `sortDefinition`, `expansionStates`, `filterConfig`.
    public var raw: JSONValue = .null
    /// Mã nhóm chứa visual này (PBIR `parentGroupName`, D7). Khi có, `x`, `y` là toạ độ **tuyệt đối** trên trang
    /// (file ghi tương đối so với nhóm); `raw` vẫn là JSON nguyên văn của file.
    public var parentGroup: String?

    public init(id: String, type: String, x: Double = 0, y: Double = 0, z: Double = 0, width: Double = 0, height: Double = 0,
                isHidden: Bool = false, objects: ObjectProperties = ObjectProperties(nil),
                containerObjects: ObjectProperties = ObjectProperties(nil), fields: [ReportField] = [], raw: JSONValue = .null,
                parentGroup: String? = nil) {
        self.id = id; self.type = type; self.x = x; self.y = y; self.z = z; self.width = width; self.height = height
        self.isHidden = isHidden; self.objects = objects; self.containerObjects = containerObjects; self.fields = fields; self.raw = raw
        self.parentGroup = parentGroup
    }

    public static let groupType = "visualGroup"
    public var isGroup: Bool { type == Self.groupType }
    /// Tên hiển thị của nhóm (`visualGroup.displayName`).
    public var groupDisplayName: String? { raw["visualGroup"]?["displayName"]?.string }

    /// Visuals that need query results to render.
    public var isDataBound: Bool { !fields.isEmpty }
}

public struct ReportField: Sendable, Hashable {
    public enum Kind: String, Sendable { case column, measure, aggregation, hierarchyLevel, other }

    public var role: String
    public var kind: Kind
    public var entity: String
    public var property: String
    /// Aggregation function name for `.aggregation` (tiếng Việt, ví dụ "Tổng").
    public var function: String?
    /// Mã `Aggregation.Function` của PBIR (0 Sum … 8 Variance, VM-F10) cho `.aggregation`.
    public var aggregationFunction: Int?
    /// Tên phép gộp theo mã PBIR (VM-F10: 2 là Count (Distinct), 5 là Count).
    public static let aggregateNames = [0: "Tổng", 1: "Trung bình", 2: "Số lượng (riêng biệt)", 3: "Nhỏ nhất", 4: "Lớn nhất",
                                        5: "Số lượng", 6: "Trung vị", 7: "Độ lệch chuẩn", 8: "Phương sai"]
    public var displayName: String?
    public var queryRef: String
    /// `nativeQueryRef` và `active` của phần tử `projections[]` (PBIR); nil khi file không có.
    public var nativeQueryRef: String?
    public var active: Bool?

    public init(role: String, kind: Kind, entity: String, property: String, function: String? = nil,
                displayName: String? = nil, queryRef: String, nativeQueryRef: String? = nil, active: Bool? = nil,
                aggregationFunction: Int? = nil) {
        self.aggregationFunction = aggregationFunction
        self.role = role
        self.kind = kind
        self.entity = entity
        self.property = property
        self.function = function
        self.displayName = displayName
        self.queryRef = queryRef
        self.nativeQueryRef = nativeQueryRef
        self.active = active
    }

    public var label: String {
        if let displayName, !displayName.isEmpty { return displayName }
        if let function { return "\(function) của \(property)" }
        return property
    }
}

public enum ReportDecodingError: Error, CustomStringConvertible {
    case missing(String)
    public var description: String {
        switch self { case .missing(let p): "report part missing: \(p)" }
    }
}

extension PBIXFile {
    public func loadReport() throws -> ReportDefinition {
        switch reportFormat {
        case .pbir: return try loadPBIR()
        case .legacyLayout: return try loadLegacyLayout()
        case .none: return ReportDefinition(pages: [])
        }
    }

    /// Bytes of a registered/shared resource (images, themes) by item name.
    public func resource(named name: String) -> Data? {
        let match = archive.entries.first { $0.path.hasPrefix("Report/StaticResources/") && $0.path.hasSuffix("/" + name) }
        return match.flatMap { try? archive.read($0) }
    }

    // MARK: PBIR

    private func json(_ path: String) throws -> JSONValue {
        guard archive.entry(path) != nil else { throw ReportDecodingError.missing(path) }
        var data = try archive.read(path)
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { data = data.dropFirst(3) }
        return try JSONValue.parse(data)
    }

    private func loadPBIR() throws -> ReportDefinition {
        let root = "Report/definition/"
        let report = try json(root + "report.json")
        let pagesMeta = (try? json(root + "pages/pages.json")) ?? .null
        let pageDirectories = Set(archive.entries.compactMap { entry -> String? in
            guard entry.path.hasPrefix(root + "pages/"), entry.path.hasSuffix("/page.json") else { return nil }
            return entry.path.dropFirst((root + "pages/").count).split(separator: "/").first.map(String.init)
        })
        var order = pagesMeta["pageOrder"]?.array.compactMap(\.string) ?? []
        order += pageDirectories.subtracting(order).sorted()

        var pages: [ReportPage] = []
        for name in order where pageDirectories.contains(name) {
            let base = root + "pages/\(name)/"
            let page = try json(base + "page.json")
            var visuals: [ReportVisual] = []
            var groups: [ReportVisual] = []
            var documents: [(path: String, value: JSONValue)] = []
            for entry in archive.entries where entry.path.hasPrefix(base + "visuals/") && entry.path.hasSuffix("/visual.json") {
                documents.append((entry.path, try json(entry.path)))
            }
            // Nhóm trước: con của nhóm ghi toạ độ tương đối, cộng vào để mô hình dùng toạ độ tuyệt đối (D7).
            for (path, v) in documents where v["visual"] == nil && v["visualGroup"] != nil {
                let position = v["position"] ?? .null
                groups.append(ReportVisual(
                    id: v["name"]?.string ?? path, type: ReportVisual.groupType,
                    x: position["x"]?.number ?? 0, y: position["y"]?.number ?? 0, z: position["z"]?.number ?? 0,
                    width: position["width"]?.number ?? 0, height: position["height"]?.number ?? 0,
                    isHidden: v["isHidden"]?.bool ?? false, raw: v, parentGroup: v["parentGroupName"]?.string))
            }
            // Nhóm lồng nhau (VM-D8): nhóm con cũng ghi toạ độ tương đối so với nhóm cha; cộng gốc của mọi nhóm tổ tiên.
            let relative = Dictionary(groups.map { ($0.id, (x: $0.x, y: $0.y, parent: $0.parentGroup)) }, uniquingKeysWith: { first, _ in first })
            func absoluteOrigin(_ id: String) -> (x: Double, y: Double) {
                var x = 0.0, y = 0.0
                var seen: Set<String> = []
                var next: String? = id
                while let current = next, seen.insert(current).inserted, let group = relative[current] {
                    x += group.x; y += group.y
                    next = group.parent
                }
                return (x, y)
            }
            for index in groups.indices {
                let at = absoluteOrigin(groups[index].id)
                groups[index].x = at.x; groups[index].y = at.y
            }
            let origin = Dictionary(groups.map { ($0.id, (x: $0.x, y: $0.y)) }, uniquingKeysWith: { first, _ in first })
            for (path, v) in documents {
                guard let visual = v["visual"] else { continue }
                let position = v["position"] ?? .null
                let parent = v["parentGroupName"]?.string
                let shift = parent.flatMap { origin[$0] } ?? (x: 0, y: 0)
                visuals.append(ReportVisual(
                    id: v["name"]?.string ?? path,
                    type: visual["visualType"]?.string ?? "unknown",
                    x: (position["x"]?.number ?? 0) + shift.x, y: (position["y"]?.number ?? 0) + shift.y,
                    z: position["z"]?.number ?? 0,
                    width: position["width"]?.number ?? 0, height: position["height"]?.number ?? 0,
                    isHidden: v["isHidden"]?.bool ?? false,
                    objects: ObjectProperties(visual["objects"]),
                    containerObjects: ObjectProperties(visual["visualContainerObjects"]),
                    fields: Self.pbirFields(visual["query"]?["queryState"]), raw: v, parentGroup: parent))
            }
            pages.append(ReportPage(
                id: name, displayName: page["displayName"]?.string ?? name,
                width: page["width"]?.number ?? 1280, height: page["height"]?.number ?? 720,
                isHidden: page["visibility"]?.string == "HiddenInViewMode",
                objects: ObjectProperties(page["objects"]),
                visuals: visuals.sorted { $0.z < $1.z }, groups: groups.sorted { $0.z < $1.z }))
        }

        let themes = report["themeCollection"]
        return ReportDefinition(pages: pages,
                                baseThemeName: themes?["baseTheme"]?["name"]?.string,
                                customThemeName: themes?["customTheme"]?["name"]?.string)
    }

    static func pbirFields(_ queryState: JSONValue?) -> [ReportField] {
        var fields: [ReportField] = []
        for (role, state) in (queryState?.object ?? [:]).sorted(by: { $0.key < $1.key }) {
            for projection in state["projections"]?.array ?? [] {
                guard var field = parseField(projection["field"], aliases: [:]) else { continue }
                field.role = role
                field.displayName = projection["displayName"]?.string
                field.queryRef = projection["queryRef"]?.string ?? field.queryRef
                field.nativeQueryRef = projection["nativeQueryRef"]?.string
                field.active = projection["active"]?.bool
                fields.append(field)
            }
        }
        return fields
    }

    /// Một phần tử `projections[]` của PBIR thành `ReportField` (dùng bởi `PBIRQueryPatch`).
    static func pbirField(_ projection: JSONValue, role: String) -> ReportField? {
        guard var field = parseField(projection["field"], aliases: [:]) else { return nil }
        field.role = role
        field.displayName = projection["displayName"]?.string
        field.queryRef = projection["queryRef"]?.string ?? field.queryRef
        field.nativeQueryRef = projection["nativeQueryRef"]?.string
        field.active = projection["active"]?.bool
        return field
    }

    // MARK: Legacy Report/Layout

    private func loadLegacyLayout() throws -> ReportDefinition {
        let layout = try JSONValue.parse(try utf16Part("Report/Layout"))
        let config = layout["config"]?.string.flatMap { try? JSONValue.parse($0) }

        var pages: [ReportPage] = []
        for section in layout["sections"]?.array ?? [] {
            let sectionConfig = section["config"]?.string.flatMap { try? JSONValue.parse($0) }
            var visuals: [ReportVisual] = []
            for container in section["visualContainers"]?.array ?? [] {
                guard let c = container["config"]?.string.flatMap({ try? JSONValue.parse($0) }),
                      let single = c["singleVisual"] else { continue } // groups have singleVisualGroup instead
                let layoutPosition = c["layouts"]?[0]?["position"]
                visuals.append(ReportVisual(
                    id: c["name"]?.string ?? UUID().uuidString,
                    type: single["visualType"]?.string ?? "unknown",
                    x: container["x"]?.number ?? 0, y: container["y"]?.number ?? 0,
                    z: container["z"]?.number ?? layoutPosition?["z"]?.number ?? 0,
                    width: container["width"]?.number ?? 0, height: container["height"]?.number ?? 0,
                    isHidden: single["display"]?["mode"]?.string == "hidden",
                    objects: ObjectProperties(single["objects"]),
                    containerObjects: ObjectProperties(single["vcObjects"]),
                    fields: Self.legacyFields(single), raw: c, parentGroup: c["parentGroupName"]?.string))
            }
            pages.append(ReportPage(
                id: section["name"]?.string ?? UUID().uuidString,
                displayName: section["displayName"]?.string ?? "Page",
                width: section["width"]?.number ?? 1280, height: section["height"]?.number ?? 720,
                isHidden: sectionConfig?["visibility"]?.number == 1,
                objects: ObjectProperties(sectionConfig?["objects"]),
                visuals: visuals.sorted { $0.z < $1.z }))
        }
        let themes = config?["themeCollection"]
        return ReportDefinition(pages: pages,
                                baseThemeName: themes?["baseTheme"]?["name"]?.string,
                                customThemeName: themes?["customTheme"]?["name"]?.string)
    }

    private static func legacyFields(_ single: JSONValue) -> [ReportField] {
        let query = single["prototypeQuery"]
        var aliases: [String: String] = [:]
        for from in query?["From"]?.array ?? [] {
            if let name = from["Name"]?.string, let entity = from["Entity"]?.string { aliases[name] = entity }
        }
        var byRef: [String: ReportField] = [:]
        for select in query?["Select"]?.array ?? [] {
            if var field = parseField(select, aliases: aliases), let name = select["Name"]?.string {
                field.queryRef = name
                byRef[name] = field
            }
        }
        let columnProperties = single["columnProperties"]
        var fields: [ReportField] = []
        for (role, projections) in (single["projections"]?.object ?? [:]).sorted(by: { $0.key < $1.key }) {
            for projection in projections.array {
                guard let ref = projection["queryRef"]?.string, var field = byRef[ref] else { continue }
                field.role = role
                field.displayName = columnProperties?[ref]?["displayName"]?.string
                fields.append(field)
            }
        }
        return fields
    }

    // MARK: Shared field expressions


    private static func entity(_ expression: JSONValue?, aliases: [String: String]) -> String {
        let source = expression?["SourceRef"]
        if let entity = source?["Entity"]?.string { return entity }
        if let alias = source?["Source"]?.string { return aliases[alias] ?? alias }
        return ""
    }

    static func parseFieldExpression(_ json: JSONValue?) -> ReportField? { parseField(json, aliases: [:]) }

    static func parseField(_ json: JSONValue?, aliases: [String: String]) -> ReportField? {
        guard let json else { return nil }
        if let column = json["Column"] {
            let e = entity(column["Expression"], aliases: aliases), p = column["Property"]?.string ?? ""
            return ReportField(role: "", kind: .column, entity: e, property: p, queryRef: "\(e).\(p)")
        }
        if let measure = json["Measure"] {
            let e = entity(measure["Expression"], aliases: aliases), p = measure["Property"]?.string ?? ""
            return ReportField(role: "", kind: .measure, entity: e, property: p, queryRef: "\(e).\(p)")
        }
        if let aggregation = json["Aggregation"], var inner = parseField(aggregation["Expression"], aliases: aliases) {
            inner.kind = .aggregation
            let code = Int(aggregation["Function"]?.number ?? -1)
            inner.function = ReportField.aggregateNames[code] ?? "Gộp"
            inner.aggregationFunction = code >= 0 ? code : nil
            return inner
        }
        if let level = json["HierarchyLevel"] {
            let hierarchy = level["Expression"]?["Hierarchy"]
            let source = hierarchy?["Expression"]?["PropertyVariationSource"]?["Expression"] ?? hierarchy?["Expression"]
            let e = entity(source, aliases: aliases), l = level["Level"]?.string ?? ""
            return ReportField(role: "", kind: .hierarchyLevel, entity: e, property: l, queryRef: "\(e).\(l)")
        }
        return nil
    }
}

// MARK: - Theme

public struct ReportTheme: Sendable {
    public var dataColors: [String]
    public var background: String?
    public var foreground: String?
    /// Màu cảm xúc của theme (thác nước: tăng, trung tính, giảm). nil: dùng giá trị mặc định của Power BI.
    public var good: String?
    public var neutral: String?
    public var bad: String?

    public static let fallback = ReportTheme(
        dataColors: ["#118DFF", "#12239E", "#E66C37", "#6B007B", "#E044A7", "#744EC2", "#D9B300", "#D64550"],
        background: "#FFFFFF", foreground: "#252423")
}

extension PBIXFile {
    public func loadTheme(for report: ReportDefinition) -> ReportTheme {
        var theme = ReportTheme.fallback
        for name in [report.baseThemeName.map { $0.hasSuffix(".json") ? $0 : $0 + ".json" }, report.customThemeName] {
            guard let name, let data = resource(named: name), let json = try? JSONValue.parse(data) else { continue }
            let colors = json["dataColors"]?.array.compactMap(\.string) ?? []
            if !colors.isEmpty { theme.dataColors = colors }
            if let bg = json["background"]?.string { theme.background = bg }
            if let fg = json["foreground"]?.string { theme.foreground = fg }
            if let good = json["good"]?.string { theme.good = good }
            if let neutral = json["neutral"]?.string { theme.neutral = neutral }
            if let bad = json["bad"]?.string { theme.bad = bad }
        }
        return theme
    }
}
