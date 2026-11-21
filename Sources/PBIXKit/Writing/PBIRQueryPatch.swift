import Foundation

/// Edits to `visual.query.queryState` of a PBIR `visual.json`: which fields sit in which well, in what order,
/// and the display name of each. Like `PBIRPatch` and `PBIRLayoutPatch`, every edit splices bytes, so what is not
/// touched stays byte-for-byte as it was, and the result is re-parsed and compared with the expected structure.
///
/// Contract: `specs/003-d2-build-pane-field-well/contracts/query-state-patch.md`.
public enum PBIRQueryPatch {
    /// One element of a well's `projections` array.
    public struct Element: Sendable, Equatable {
        public var field: ReportField
        /// The element's bytes as found in the file. Nil for an element that is new: it is written from the template.
        public var source: Data?

        public init(field: ReportField, source: Data?) {
            self.field = field
            self.source = source
        }

        /// The element without its `active` flag (the `Series` column of a shape map has none: VM-D12). Bytes found in the
        /// file lose only `"active":…` and its comma; a new element is written without the flag.
        public func withoutActive() -> Element {
            var copy = self
            copy.field.active = nil
            guard let source, var text = String(data: source, encoding: .utf8) else { return copy }
            for flag in [#","active":true"#, #","active":false"#, #""active":true,"#, #""active":false,"#] where text.contains(flag) {
                text = text.replacingOccurrences(of: flag, with: "")
                break
            }
            copy.source = Data(text.utf8)
            return copy
        }
    }

    /// A well (`Category`, `Y`, `Values`…) with its fields in order.
    public struct Well: Sendable, Equatable {
        public var role: String
        public var elements: [Element]

        public init(role: String, elements: [Element]) {
            self.role = role
            self.elements = elements
        }
    }

    // MARK: - Read

    private static let statePath: [JSONPathStep] = [.key("visual"), .key("query"), .key("queryState")]

    /// The wells of the visual, in file order, with the bytes of every element.
    public static func wells(in json: Data) throws -> [Well] {
        _ = try parseObject(json)
        let bytes = [UInt8](json)
        guard let roles = JSONCursor.children(at: statePath, in: bytes) else {
            if JSONCursor.locate(statePath[...], in: bytes) == nil { return [] }
            throw WriteError.invalid("queryState is not an object")
        }
        var wells: [Well] = []
        for role in roles {
            guard let keyRange = role.key, let name = JSONCursor.string(in: bytes, keyRange) else {
                throw WriteError.invalid("queryState has a malformed key")
            }
            let kids = try projections(of: name, in: bytes)
            var elements: [Element] = []
            for kid in kids {
                let slice = Data(bytes[kid.value])
                guard let value = try? JSONValue.parse(slice), let field = PBIXFile.pbirField(value, role: name) else {
                    throw WriteError.invalid("a projection of \(name) is not a field")
                }
                elements.append(Element(field: field, source: slice))
            }
            wells.append(Well(role: name, elements: elements))
        }
        return wells
    }

    /// The fields of the visual as `PBIXFile.loadReport()` lists them (roles by name, elements in file order).
    public static func fields(in json: Data) throws -> [ReportField] {
        let value = try JSONValue.parse(json)
        return PBIXFile.pbirFields(value["visual"]?["query"]?["queryState"])
    }

    /// A new element in the shape Power BI Desktop writes (observed in Nhom6): field, queryRef, nativeQueryRef,
    /// then displayName when the user renamed it.
    /// `active`: cờ `active` của cột trong ô (VM-D3 mục B: cột đầu của ô `true`, các cột sau `false` như hierarchy ở Nhom6;
    /// measure không có cờ).
    public static func newElement(kind: ReportField.Kind, entity: String, property: String, displayName: String?, role: String,
                                  active: Bool? = nil) -> Element {
        let field = ReportField(role: role, kind: kind, entity: entity, property: property, displayName: displayName,
                                queryRef: "\(entity).\(property)", nativeQueryRef: property, active: kind == .column ? active : nil)
        return Element(field: field, source: nil)
    }

    /// Tên phép gộp trong `queryRef` lúc Desktop thêm trường (VM-F10: `Sum(Sales.Amount)`, `CountNonNull(Sales.OrderID)`, `Min(Sales.Region)`).
    /// [SUY ĐOÁN] Avg, DistinctCount, Median, StandardDeviation, Variance: Desktop chỉ tạo trường với phép gộp mặc định của cột.
    static let queryRefAggregateNames = [0: "Sum", 1: "Avg", 2: "DistinctCount", 3: "Min", 4: "Max", 5: "CountNonNull", 6: "Median",
                                         7: "StandardDeviation", 8: "Variance"]
    /// Nhãn tiếng Anh Desktop ghi ở `nativeQueryRef` ("Sum of Amount", VM-F10).
    static let nativeAggregateNames = [0: "Sum", 1: "Average", 2: "Count", 3: "Min", 4: "Max", 5: "Count", 6: "Median",
                                       7: "Standard deviation", 8: "Variance"]

    /// Trường gộp ngầm mới (đợt tồn đọng sau Phase F, US1): cột kèm mã phép gộp. `nativeQueryRef` mặc định "<Phép gộp> of <cột>".
    public static func newAggregation(entity: String, property: String, function: Int, role: String,
                                      nativeQueryRef: String? = nil) -> Element {
        let field = ReportField(role: role, kind: .aggregation, entity: entity, property: property,
                                function: ReportField.aggregateNames[function],
                                queryRef: "\(queryRefAggregateNames[function] ?? "Sum")(\(entity).\(property))",
                                nativeQueryRef: nativeQueryRef ?? "\(nativeAggregateNames[function] ?? "Sum") of \(property)",
                                aggregationFunction: function)
        return Element(field: field, source: nil)
    }

    /// Đổi phép gộp của một trường gộp: như Desktop, giữ `queryRef` và tên đổi riêng, đổi `Function` và `nativeQueryRef`.
    public static func changingAggregation(_ element: Element, to function: Int, nativeQueryRef: String? = nil) -> Element {
        var field = element.field
        field.aggregationFunction = function
        field.function = ReportField.aggregateNames[function]
        field.nativeQueryRef = nativeQueryRef ?? "\(nativeAggregateNames[function] ?? "Sum") of \(field.property)"
        return Element(field: field, source: nil)
    }

    /// Một cấp của phân cấp, đúng dạng Desktop ghi khi thả cả phân cấp vào ô (VM-D11 mục 1): `HierarchyLevel`, `queryRef`
    /// `Bảng.Phân cấp.Cấp`, `nativeQueryRef` `Phân cấp Cấp`, `active: true` ở mọi cấp.
    public static func newHierarchyLevel(entity: String, hierarchy: String, level: String, role: String) -> Element {
        let field = ReportField(role: role, kind: .hierarchyLevel, entity: entity, property: level, displayName: nil,
                                queryRef: "\(entity).\(hierarchy).\(level)", nativeQueryRef: "\(hierarchy) \(level)", active: true)
        return Element(field: field, source: nil)
    }

    /// Một cấp của phân cấp ngày Auto date/time của cột `column` (VM-F11b, `visual-theo-nam.json`): `HierarchyLevel` trên
    /// `PropertyVariationSource`, `queryRef` `Bảng.Cột.Variation.Date Hierarchy.Cấp`, `nativeQueryRef` `Cột Cấp`.
    public static func newVariationLevel(entity: String, column: String, variation: String, hierarchy: String, level: String,
                                         role: String, active: Bool) -> Element {
        var field = ReportField(role: role, kind: .hierarchyLevel, entity: entity, property: level, displayName: nil,
                                queryRef: "\(entity).\(column).\(variation).\(hierarchy).\(level)", nativeQueryRef: "\(column) \(level)",
                                active: active)
        field.variationColumn = column
        field.variationName = variation
        return Element(field: field, source: nil)
    }

    // MARK: - Apply

    /// `json` with the wells replaced by `wells` (the final state of every well). A well whose elements are exactly
    /// the ones in the file, in the same order and without renames, keeps its bytes; wells not mentioned in `wells`
    /// (or with no elements) are removed; wells that are new are added at the end of `queryState`.
    public static func apply(_ wells: [Well], to json: Data) throws -> Data {
        let before = try wells_(in: json)
        let patched = try applyWells(wells, to: json)
        return try adjustingDefaultSort(patched, previous: before)
    }

    private static func wells_(in json: Data) throws -> [Well] { (try? Self.wells(in: json)) ?? [] }

    private static func applyWells(_ wells: [Well], to json: Data) throws -> Data {
        let root = try parseObject(json)
        var bytes = [UInt8](json)
        try validate(wells)
        let oldRefs = Set(((try? Self.wells(in: json)) ?? []).flatMap { $0.elements.map(\.field.queryRef) })
        guard JSONCursor.locate(statePath[...], in: bytes) != nil else {
            return try createQueryState(wells, in: json, root: root)
        }
        guard let roles = JSONCursor.children(at: statePath, in: bytes) else {
            throw WriteError.invalid("visual.json has an invalid query.queryState")
        }

        // Current state: role name → (children of its object, children of its projections).
        struct Current { var role: String; var kids: [JSONCursor.Child]; var projections: [JSONCursor.Child]?; var extraKeys: Bool }
        var current: [String: Current] = [:]
        var order: [String] = []
        for role in roles {
            guard let keyRange = role.key, let name = JSONCursor.string(in: bytes, keyRange) else {
                throw WriteError.invalid("queryState has a malformed key")
            }
            let objectKids = JSONCursor.children(at: statePath + [.key(name)], in: bytes) ?? []
            let projectionKids = objectKids.contains { key(of: $0, in: bytes) == "projections" }
                ? try projections(of: name, in: bytes) : nil
            current[name] = Current(role: name, kids: objectKids, projections: projectionKids,
                                    extraKeys: objectKids.contains { key(of: $0, in: bytes) != "projections" })
            order.append(name)
        }

        let wanted = wells.filter { !$0.elements.isEmpty }
        var expectedElements: [String: [Any]] = [:]   // for the final check

        // 1. Replace the projections array of every well that exists and changed (last to first).
        var replacements: [(range: Range<Int>, text: [UInt8])] = []
        for well in wanted {
            let texts = try well.elements.map { try elementBytes($0) }
            expectedElements[well.role] = try texts.map { try JSONSerialization.jsonObject(with: Data($0), options: [.fragmentsAllowed]) }
            guard let existing = current[well.role] else { continue }
            let old = existing.projections ?? []
            let unchanged = old.count == texts.count && zip(old, texts).allSatisfy { Array(bytes[$0.value]) == $1 }
            if unchanged { continue }
            guard existing.projections != nil,
                  let arrayRange = JSONCursor.locate((statePath + [.key(well.role), .key("projections")])[...], in: bytes) else {
                throw WriteError.invalid("\(well.role) has no projections array")
            }
            replacements.append((arrayRange, arrayText(texts, replacing: old, array: arrayRange, in: bytes)))
        }
        for edit in replacements.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            bytes.replaceSubrange(edit.range, with: edit.text)
        }

        // 2. Remove wells that are gone (a well with other keys keeps them and just gets an empty array).
        let keep = Set(wanted.map(\.role))
        var emptied: [String] = []
        if let kids = JSONCursor.children(at: statePath, in: bytes) {
            var drop = Set<Int>()
            for (index, kid) in kids.enumerated() {
                guard let name = key(of: kid, in: bytes), !keep.contains(name) else { continue }
                if current[name]?.extraKeys == true { emptied.append(name) } else { drop.insert(index) }
            }
            bytes = JSONCursor.removing(drop, from: kids, in: bytes)
        }
        for name in emptied {
            guard let arrayRange = JSONCursor.locate((statePath + [.key(name), .key("projections")])[...], in: bytes) else { continue }
            bytes.replaceSubrange(arrayRange, with: Array("[]".utf8))
            expectedElements[name] = []
        }

        // 3. Add new wells at the end of queryState.
        let added = wanted.filter { current[$0.role] == nil }
        if !added.isEmpty {
            guard let stateRange = JSONCursor.locate(statePath[...], in: bytes) else { throw WriteError.invalid("queryState vanished") }
            let kids = JSONCursor.children(at: statePath, in: bytes) ?? []
            var text: [UInt8] = []
            for (index, well) in added.enumerated() {
                if index > 0 || !kids.isEmpty { text.append(UInt8(ascii: ",")) }
                text += PBIRPatch.jsonStringToken(well.role)
                text += Array(#":{"projections":["#.utf8)
                text += Array(try well.elements.map { try elementBytes($0) }.joined(separator: [UInt8(ascii: ",")]))
                text += Array("]}".utf8)
            }
            let insertAt = kids.last?.value.upperBound ?? (stateRange.lowerBound + 1)
            bytes.insert(contentsOf: text, at: insertAt)
        }

        // 4. Check: the result is the old document with queryState changed as asked and nothing else.
        let result = Data(bytes)
        var expected = root
        guard var visual = expected["visual"] as? [String: Any], var query = visual["query"] as? [String: Any],
              var state = query["queryState"] as? [String: Any] else {
            throw WriteError.invalid("visual.json has no query.queryState")
        }
        for name in order where !keep.contains(name) {
            if current[name]?.extraKeys == true {
                var object = (state[name] as? [String: Any]) ?? [:]
                object["projections"] = [Any]()
                state[name] = object
            } else {
                state[name] = nil
            }
        }
        for well in wanted {
            var object = (state[well.role] as? [String: Any]) ?? [:]
            object["projections"] = expectedElements[well.role] ?? []
            state[well.role] = object
        }
        query["queryState"] = state
        visual["query"] = query
        expected["visual"] = visual
        guard let actual = try? JSONSerialization.jsonObject(with: result, options: []) as? [String: Any],
              (expected as NSDictionary).isEqual(to: actual) else {
            throw WriteError.verificationFailed("queryState splice changed other content")
        }
        // A field that left the visual takes its per-field formatting with it, as Power BI Desktop does (VM-D2, R-D2-f-*).
        let newRefs = Set(wells.flatMap { $0.elements.map(\.field.queryRef) })
        return try removingFormatSelectors(forQueryRefs: oldRefs.subtracting(newRefs), in: result)
    }

    /// `json` without the entries of `visual.objects.*` whose `selector.metadata` is one of `refs` (the formatting a
    /// removed field carried: column width, conditional formatting…). An object left with no entry is removed, and
    /// `objects` with it when nothing is left. Observed in Power BI Desktop (VM-D2 `R-D2-f-remove-filter`, `-format`).
    /// Filters (`filterConfig`) are not touched: Desktop keeps the filter of a removed field.
    public static func removingFormatSelectors(forQueryRefs refs: Set<String>, in json: Data) throws -> Data {
        guard !refs.isEmpty else { return json }
        let root = try parseObject(json)
        guard let visual = root["visual"] as? [String: Any], let objects = visual["objects"] as? [String: Any] else { return json }
        var keptObjects: [String: Any] = [:]
        var dropKeys = Set<String>()
        var dropEntries: [String: Set<Int>] = [:]
        for (key, value) in objects {
            guard let entries = value as? [Any] else { keptObjects[key] = value; continue }
            var drop = Set<Int>()
            for (index, entry) in entries.enumerated() {
                let selector = (entry as? [String: Any])?["selector"] as? [String: Any]
                if let metadata = selector?["metadata"] as? String, refs.contains(metadata) { drop.insert(index) }
            }
            if drop.isEmpty { keptObjects[key] = value }
            else if drop.count == entries.count { dropKeys.insert(key) }
            else {
                dropEntries[key] = drop
                keptObjects[key] = entries.enumerated().filter { !drop.contains($0.offset) }.map(\.element)
            }
        }
        guard !dropKeys.isEmpty || !dropEntries.isEmpty else { return json }
        var bytes = [UInt8](json)
        let objectsPath: [JSONPathStep] = [.key("visual"), .key("objects")]
        for (key, drop) in dropEntries.sorted(by: { $0.key < $1.key }) {
            guard let kids = JSONCursor.children(at: objectsPath + [.key(key)], in: bytes) else {
                throw WriteError.invalid("objects.\(key) is not an array")
            }
            bytes = JSONCursor.removing(drop, from: kids, in: bytes)
        }
        var expectedVisual = visual
        if keptObjects.isEmpty {
            guard let kids = JSONCursor.children(at: [.key("visual")], in: bytes),
                  let index = kids.firstIndex(where: { key(of: $0, in: bytes) == "objects" }) else { throw WriteError.invalid("objects vanished") }
            bytes = JSONCursor.removing([index], from: kids, in: bytes)
            expectedVisual["objects"] = nil
        } else {
            if !dropKeys.isEmpty {
                guard let kids = JSONCursor.children(at: objectsPath, in: bytes) else { throw WriteError.invalid("objects vanished") }
                let indices = Set(kids.indices.filter { key(of: kids[$0], in: bytes).map(dropKeys.contains) ?? false })
                bytes = JSONCursor.removing(indices, from: kids, in: bytes)
            }
            expectedVisual["objects"] = keptObjects
        }
        var expected = root
        expected["visual"] = expectedVisual
        guard let actual = try? JSONSerialization.jsonObject(with: Data(bytes), options: []) as? [String: Any],
              (expected as NSDictionary).isEqual(to: actual) else {
            throw WriteError.verificationFailed("removing format selectors changed other content")
        }
        return Data(bytes)
    }

    /// A visual that has no `queryState` yet (a new visual): `"query":{"queryState":{…}}` goes right after `visualType`
    /// (or `"queryState"` goes inside a `query` that exists without one). Nothing to write leaves the bytes alone.
    private static func createQueryState(_ wells: [Well], in json: Data, root: [String: Any]) throws -> Data {
        let wanted = wells.filter { !$0.elements.isEmpty }
        guard !wanted.isEmpty else { return json }
        guard root["visual"] is [String: Any] else { throw WriteError.invalid("visual.json has no visual") }
        var state: [UInt8] = [UInt8(ascii: "{")]
        var expectedRoles: [String: Any] = [:]
        for (index, well) in wanted.enumerated() {
            let texts = try well.elements.map { try elementBytes($0) }
            if index > 0 { state.append(UInt8(ascii: ",")) }
            state += PBIRPatch.jsonStringToken(well.role) + Array(#":{"projections":["#.utf8)
            state += Array(texts.joined(separator: [UInt8(ascii: ",")]))
            state += Array("]}".utf8)
            expectedRoles[well.role] = ["projections": try texts.map { try JSONSerialization.jsonObject(with: Data($0)) }]
        }
        state.append(UInt8(ascii: "}"))

        var bytes = [UInt8](json)
        let queryPath: [JSONPathStep] = [.key("visual"), .key("query")]
        if let query = JSONCursor.locate(queryPath[...], in: bytes) {
            guard bytes[query.lowerBound] == UInt8(ascii: "{") else { throw WriteError.invalid("query is not an object") }
            let hasKeys = !(JSONCursor.children(at: queryPath, in: bytes) ?? []).isEmpty
            bytes.insert(contentsOf: Array(#""queryState":"#.utf8) + state + (hasKeys ? [UInt8(ascii: ",")] : []), at: query.lowerBound + 1)
        } else {
            let typePath: [JSONPathStep] = [.key("visual"), .key("visualType")]
            guard let type = JSONCursor.locate(typePath[...], in: bytes) else { throw WriteError.invalid("visual.json has no visualType") }
            bytes.insert(contentsOf: Array(#","query":{"queryState":"#.utf8) + state + Array("}".utf8), at: type.upperBound)
        }

        var expected = root
        var visual = root["visual"] as! [String: Any]
        var query = (visual["query"] as? [String: Any]) ?? [:]
        query["queryState"] = expectedRoles
        visual["query"] = query
        expected["visual"] = visual
        guard let actual = try? JSONSerialization.jsonObject(with: Data(bytes), options: []) as? [String: Any],
              (expected as NSDictionary).isEqual(to: actual) else {
            throw WriteError.verificationFailed("queryState creation changed other content")
        }
        return Data(bytes)
    }

    // MARK: - Sắp xếp mặc định (VM-D3 mục B)

    /// Ô nhóm: cột ở đây định nghĩa trục, chuỗi hoặc hàng/cột của visual.
    private static let groupingRoles: Set<String> = ["Category", "Group", "Series", "Rows", "Columns", "Details"]
    /// Loại có `sortDefinition` mặc định theo measure đầu tiên: biểu đồ có trục, tròn, đồng hồ đo và `cardVisual` (VM-D3 B, VM-V11A).
    private static func sortsByFirstMeasure(_ type: String) -> Bool {
        type == "cardVisual" || type == "barChart" || type == "pieChart" || type == "gauge"
            || type.hasSuffix("BarChart") || type.hasSuffix("ColumnChart") || type == "columnChart"
            || type.contains("Combo") || type == "lineChart"
    }

    private static func groupingRefs(_ wells: [Well]) -> Set<String> {
        Set(wells.filter { groupingRoles.contains($0.role) }.flatMap { $0.elements.filter { $0.field.kind != .measure && $0.field.kind != .aggregation }.map(\.field.queryRef) })
    }

    /// Sau khi đổi trường, giữ `sortDefinition` mặc định (`isDefaultSort: true`) đúng như Desktop:
    /// - visual chỉ có measure và chưa có `sortDefinition`, **và ô `Y` (hoặc `Data`) vừa có measure đầu tiên** (trước đó trống):
    ///   thêm sắp giảm dần theo measure đó. Sửa khác trên file Desktop không có `sortDefinition` thì không tự thêm;
    /// - thêm cột nhóm khi đã có sắp xếp mặc định theo measure: giữ nguyên (VM-D8c);
    /// - cột Category mà sắp xếp mặc định trỏ tới bị thay bằng đúng một cột khác: sắp xếp chuyển sang cột mới, giữ hướng (VM-D9);
    /// - sắp xếp mặc định trỏ tới trường không còn trong visual (không có cột thay thế rõ ràng): bỏ.
    /// `sortDefinition` do người dùng đặt (`isDefaultSort` khác `true`) và mọi trường hợp còn lại giữ nguyên byte.
    static func adjustingDefaultSort(_ json: Data, previous: [Well]) throws -> Data {
        let root = try parseObject(json)
        guard let visual = root["visual"] as? [String: Any], let type = visual["visualType"] as? String,
              var query = visual["query"] as? [String: Any], query["queryState"] != nil else { return json }
        let wells = try Self.wells(in: json)
        let sort = query["sortDefinition"] as? [String: Any]
        let queryPath: [JSONPathStep] = [.key("visual"), .key("query")]
        var bytes = [UInt8](json)

        if let sort {
            // `sortDefinition` mặc định trỏ tới trường không còn trong visual (kể cả khi bỏ hết trường) bị bỏ hoặc chuyển cột.
            func target(_ sort: [String: Any]) -> (ref: String, kind: ReportField.Kind, direction: String)? {
                guard let first = (sort["sort"] as? [[String: Any]])?.first, var field = first["field"] as? [String: Any] else { return nil }
                // Trường gộp ngầm: đích là cột bên trong (VM-F10).
                let aggregated = field["Aggregation"] != nil
                if let aggregation = field["Aggregation"] as? [String: Any], let expression = aggregation["Expression"] as? [String: Any] {
                    field = expression
                }
                guard let kindKey = ["Measure", "Column"].first(where: { field[$0] != nil }),
                      let inner = field[kindKey] as? [String: Any],
                      let entity = (((inner["Expression"] as? [String: Any])?["SourceRef"]) as? [String: Any])?["Entity"] as? String,
                      let property = inner["Property"] as? String else { return nil }
                return ("\(entity).\(property)", aggregated ? .aggregation : kindKey == "Measure" ? .measure : .column,
                        first["direction"] as? String ?? "Ascending")
            }
            let sortTarget = target(sort)
            func contains(_ ref: String, in wells: [Well]) -> Bool {
                wells.contains { $0.elements.contains { "\($0.field.entity).\($0.field.property)" == ref } }
            }
            guard sort["isDefaultSort"] as? Bool == true, let sortTarget, !contains(sortTarget.ref, in: wells),
                  let kids = JSONCursor.children(at: queryPath, in: bytes),
                  let index = kids.firstIndex(where: { key(of: $0, in: bytes) == "sortDefinition" }) else {
                // Sắp xếp mặc định không có đích đọc được hoặc đích còn nguyên: nếu chỉ là mặc định thì giữ nguyên byte;
                // đích không đọc được (ví dụ `sort` rỗng) cũng giữ nguyên.
                return json
            }
            // Cột Category bị thay bằng đúng một cột: chuyển sắp xếp sang cột mới.
            var replacement: (role: String, index: Int)?
            if sortTarget.kind == .column {
                let oldRefs = groupingRefs(previous), newRefs = groupingRefs(wells)
                let added = newRefs.subtracting(oldRefs)
                if oldRefs.subtracting(newRefs) == [sortTarget.ref], added.count == 1,
                   let ref = added.first {
                    for well in wells where groupingRoles.contains(well.role) {
                        if let at = well.elements.firstIndex(where: { $0.field.queryRef == ref && $0.field.kind != .measure }) { replacement = (well.role, at) }
                    }
                }
            }
            bytes = JSONCursor.removing([index], from: kids, in: bytes)
            query["sortDefinition"] = nil
            var expected = root
            var expectedVisual = visual
            expectedVisual["query"] = query
            expected["visual"] = expectedVisual
            guard let actual = try? JSONSerialization.jsonObject(with: Data(bytes), options: []) as? [String: Any],
                  (expected as NSDictionary).isEqual(to: actual) else {
                throw WriteError.verificationFailed("default sort removal changed other content")
            }
            if let replacement {
                return try insertingSort(Data(bytes), role: replacement.role, index: replacement.index, direction: sortTarget.direction)
            }
            // Visual chỉ còn measure thì vẫn có sắp xếp mặc định mới theo measure đầu.
            return try adjustingDefaultSort(Data(bytes), previous: wells)
        } else {
            guard sortsByFirstMeasure(type), groupingRefs(wells).isEmpty,
                  !wells.contains(where: { groupingRoles.contains($0.role) && !$0.elements.isEmpty }) else { return json }
            let role = type == "cardVisual" ? "Data" : "Y"
            guard previous.first(where: { $0.role == role })?.elements.isEmpty ?? true else { return json }
            guard let well = wells.first(where: { $0.role == role }), let first = well.elements.first,
                  first.field.kind == .measure || first.field.kind == .aggregation else { return json }
            return try insertingSort(json, role: role, index: 0, direction: "Descending")
        }
    }

    /// Đổi loại sang biểu đồ có trục danh mục khi visual chưa có `sortDefinition`: Desktop thêm sắp tăng dần theo cột đầu của ô
    /// `role` (VM-D9 mục 1, VM-D12; cột ngày). Người gọi chỉ dùng khi biết cột đó là kiểu ngày; không có `Category` dạng cột thì giữ nguyên byte.
    public static func addingDefaultCategorySort(_ json: Data, role: String = "Category") throws -> Data {
        let root = try parseObject(json)
        guard let visual = root["visual"] as? [String: Any], let query = visual["query"] as? [String: Any],
              query["sortDefinition"] == nil, query["queryState"] != nil else { return json }
        guard let well = (try Self.wells(in: json)).first(where: { $0.role == role }), let first = well.elements.first,
              first.field.kind == .column else { return json }
        return try insertingSort(json, role: role, index: 0, direction: "Ascending")
    }

    /// Chèn `sortDefinition` mặc định (một khoá) theo trường của phần tử `index` của ô `role`, ở cuối `query` (đúng chỗ Desktop ghi).
    private static func insertingSort(_ json: Data, role: String, index: Int, direction: String) throws -> Data {
        let root = try parseObject(json)
        guard var visual = root["visual"] as? [String: Any], var query = visual["query"] as? [String: Any] else { return json }
        var bytes = [UInt8](json)
        let queryPath: [JSONPathStep] = [.key("visual"), .key("query")]
        guard let fieldRange = JSONCursor.locate((statePath + [.key(role), .key("projections"), .index(index), .key("field")])[...], in: bytes),
              let kids = JSONCursor.children(at: queryPath, in: bytes), let last = kids.last else { return json }
        let field = Array(bytes[fieldRange])
        guard let fieldJSON = try? JSONSerialization.jsonObject(with: Data(field), options: [.fragmentsAllowed]) else { return json }
        let text = Array(#","sortDefinition":{"sort":[{"field":"#.utf8) + field + Array(#","direction":"\#(direction)"}],"isDefaultSort":true}"#.utf8)
        bytes.insert(contentsOf: text, at: last.value.upperBound)
        query["sortDefinition"] = ["sort": [["field": fieldJSON, "direction": direction]], "isDefaultSort": true] as [String: Any]
        visual["query"] = query
        var expected = root
        expected["visual"] = visual
        guard let actual = try? JSONSerialization.jsonObject(with: Data(bytes), options: []) as? [String: Any],
              (expected as NSDictionary).isEqual(to: actual) else {
            throw WriteError.verificationFailed("default sort splice changed other content")
        }
        return Data(bytes)
    }

    // MARK: - Helpers

    private static func validate(_ wells: [Well]) throws {
        for well in wells {
            guard !well.role.isEmpty else { throw WriteError.invalid("a well has no name") }
            for element in well.elements {
                let field = element.field
                if element.source == nil {
                    guard !field.entity.isEmpty, !field.property.isEmpty else {
                        throw WriteError.invalid("a new field needs a table and a name")
                    }
                } else if (try? JSONValue.parse(element.source!)).map({ $0.object.isEmpty }) ?? true {
                    throw WriteError.invalid("the source of a field of \(well.role) is not a JSON object")
                }
            }
        }
    }

    /// Trường gộp ngầm, đúng thứ tự khoá Desktop ghi (VM-F10): `field.Aggregation{Expression{Column}, Function}`, `queryRef`,
    /// `nativeQueryRef`, rồi `displayName` nếu đổi tên.
    private static func aggregationBytes(_ field: ReportField) throws -> [UInt8] {
        guard let function = field.aggregationFunction else { throw WriteError.invalid("an aggregation needs a function") }
        var out = Array(#"{"field":{"Aggregation":{"Expression":{"Column":{"Expression":{"SourceRef":{"Entity":"#.utf8)
        out += PBIRPatch.jsonStringToken(field.entity)
        out += Array(#"}},"Property":"#.utf8) + PBIRPatch.jsonStringToken(field.property)
        out += Array(#"}},"Function":\#(function)}},"queryRef":"#.utf8) + PBIRPatch.jsonStringToken(field.queryRef)
        let native = (field.displayName?.isEmpty ?? true) ? (field.nativeQueryRef ?? field.property) : field.displayName!
        out += Array(#","nativeQueryRef":"#.utf8) + PBIRPatch.jsonStringToken(native)
        if let name = field.displayName, !name.isEmpty { out += Array(#","displayName":"#.utf8) + PBIRPatch.jsonStringToken(name) }
        out.append(UInt8(ascii: "}"))
        return out
    }

    private static func hierarchyLevelBytes(_ field: ReportField) throws -> [UInt8] {
        // `queryRef` là `Bảng.Phân cấp.Cấp` (phân cấp ngày: `Bảng.Cột.Variation.Phân cấp.Cấp`): phần giữa là tên phân cấp.
        let variation = field.variationColumn.map { ($0, field.variationName ?? "Variation") }
        let prefix = field.entity + "." + (variation.map { "\($0.0).\($0.1)." } ?? ""), suffix = "." + field.property
        guard field.queryRef.hasPrefix(prefix), field.queryRef.hasSuffix(suffix), field.queryRef.count > prefix.count + suffix.count else {
            throw WriteError.invalid("a hierarchy level needs a queryRef of the form Table.Hierarchy.Level")
        }
        let hierarchy = String(field.queryRef.dropFirst(prefix.count).dropLast(suffix.count))
        var out = Array(#"{"field":{"HierarchyLevel":{"Expression":{"Hierarchy":{"Expression":{"#.utf8)
        if let (column, name) = variation {
            out += Array(#""PropertyVariationSource":{"Expression":{"SourceRef":{"Entity":"#.utf8) + PBIRPatch.jsonStringToken(field.entity)
            out += Array(#"}},"Name":"#.utf8) + PBIRPatch.jsonStringToken(name)
            out += Array(#","Property":"#.utf8) + PBIRPatch.jsonStringToken(column) + Array("}".utf8)
        } else {
            out += Array(#""SourceRef":{"Entity":"#.utf8) + PBIRPatch.jsonStringToken(field.entity) + Array("}".utf8)
        }
        out += Array(#"},"Hierarchy":"#.utf8) + PBIRPatch.jsonStringToken(hierarchy)
        out += Array(#"}},"Level":"#.utf8) + PBIRPatch.jsonStringToken(field.property)
        out += Array(#"}},"queryRef":"#.utf8) + PBIRPatch.jsonStringToken(field.queryRef)
        let native = (field.displayName?.isEmpty ?? true) ? (field.nativeQueryRef ?? "\(hierarchy) \(field.property)") : field.displayName!
        out += Array(#","nativeQueryRef":"#.utf8) + PBIRPatch.jsonStringToken(native)
        if let active = field.active { out += Array(#","active":\#(active)"#.utf8) }
        if let name = field.displayName, !name.isEmpty { out += Array(#","displayName":"#.utf8) + PBIRPatch.jsonStringToken(name) }
        out.append(UInt8(ascii: "}"))
        return out
    }

    /// The bytes to write for one element: the source with its `displayName` brought up to date, or the template.
    private static func elementBytes(_ element: Element) throws -> [UInt8] {
        let field = element.field
        guard let source = element.source else {
            if field.kind == .hierarchyLevel { return try hierarchyLevelBytes(field) }
            if field.kind == .aggregation { return try aggregationBytes(field) }
            let kindKey: String
            switch field.kind {
            case .measure: kindKey = "Measure"
            case .column: kindKey = "Column"
            default: throw WriteError.invalid("only columns and measures can be added")
            }
            let ref = field.queryRef.isEmpty ? "\(field.entity).\(field.property)" : field.queryRef
            var out = Array(#"{"field":{"\#(kindKey)":{"Expression":{"SourceRef":{"Entity":"#.utf8)
            out += PBIRPatch.jsonStringToken(field.entity)
            out += Array(#"}},"Property":"#.utf8)
            out += PBIRPatch.jsonStringToken(field.property)
            out += Array(#"}},"queryRef":"#.utf8) + PBIRPatch.jsonStringToken(ref)
            let native = (field.displayName?.isEmpty ?? true) ? (field.nativeQueryRef ?? field.property) : field.displayName!
            out += Array(#","nativeQueryRef":"#.utf8) + PBIRPatch.jsonStringToken(native)
            // Desktop ghi `active` giữa `nativeQueryRef` và `displayName` (Nhom6, VM-D8 `datapoint-thanh.visual.json`).
            if field.kind == .column, let active = field.active { out += Array(#","active":\#(active)"#.utf8) }
            if let name = field.displayName, !name.isEmpty {
                out += Array(#","displayName":"#.utf8) + PBIRPatch.jsonStringToken(name)
            }
            out.append(UInt8(ascii: "}"))
            return out
        }
        let current = (try? JSONValue.parse(source))?["displayName"]?.string
        let wanted = (field.displayName?.isEmpty ?? true) ? nil : field.displayName
        guard current != wanted else { return [UInt8](source) }
        var bytes = [UInt8](source)
        if let existing = JSONCursor.locate([.key("displayName")][...], in: bytes) {
            if let wanted {
                bytes.replaceSubrange(existing, with: PBIRPatch.jsonStringToken(wanted))
            } else if let kids = JSONCursor.children(at: [], in: bytes), let index = kids.firstIndex(where: { key(of: $0, in: bytes) == "displayName" }) {
                bytes = JSONCursor.removing([index], from: kids, in: bytes)
            } else {
                throw WriteError.invalid("cannot remove displayName")
            }
        } else if let wanted {
            guard let close = bytes.lastIndex(of: UInt8(ascii: "}")) else { throw WriteError.invalid("element is not an object") }
            bytes.insert(contentsOf: Array(#","displayName":"#.utf8) + PBIRPatch.jsonStringToken(wanted), at: close)
        }
        // Power BI Desktop writes the new name to `nativeQueryRef` too (VM-D2 `R-D2-h-rename`); `queryRef` stays.
        // Clearing the name goes back to the field's own name.
        let native = wanted ?? field.property
        if let existing = JSONCursor.locate([.key("nativeQueryRef")][...], in: bytes),
           JSONCursor.string(in: bytes, existing) != native {
            bytes.replaceSubrange(existing, with: PBIRPatch.jsonStringToken(native))
        }
        return bytes
    }

    /// The array text for a well: elements joined the way the existing array joins them (compact stays compact,
    /// indented stays indented).
    private static func arrayText(_ texts: [[UInt8]], replacing old: [JSONCursor.Child], array: Range<Int>, in bytes: [UInt8]) -> [UInt8] {
        var prefix: [UInt8] = [], separator: [UInt8] = [UInt8(ascii: ",")], suffix: [UInt8] = []
        if let first = old.first, let last = old.last {
            prefix = Array(bytes[(array.lowerBound + 1)..<first.value.lowerBound])
            suffix = Array(bytes[last.value.upperBound..<(array.upperBound - 1)])
            separator = old.count >= 2 ? Array(bytes[old[0].value.upperBound..<old[1].value.lowerBound])
                                       : [UInt8(ascii: ",")] + prefix
        }
        var out: [UInt8] = [UInt8(ascii: "[")]
        if !texts.isEmpty { out += prefix }
        for (index, text) in texts.enumerated() {
            if index > 0 { out += separator }
            out += text
        }
        if !texts.isEmpty { out += suffix }
        out.append(UInt8(ascii: "]"))
        return out
    }

    private static func projections(of role: String, in bytes: [UInt8]) throws -> [JSONCursor.Child] {
        let path = statePath + [.key(role), .key("projections")]
        if JSONCursor.locate(path[...], in: bytes) == nil { return [] }
        guard let kids = JSONCursor.children(at: path, in: bytes) else {
            throw WriteError.invalid("\(role).projections is not an array")
        }
        return kids
    }

    private static func key(of child: JSONCursor.Child, in bytes: [UInt8]) -> String? {
        child.key.flatMap { JSONCursor.string(in: bytes, $0) }
    }

    private static func parseObject(_ json: Data) throws -> [String: Any] {
        guard let root = try? JSONSerialization.jsonObject(with: json, options: []) as? [String: Any] else {
            throw WriteError.invalid("part is not a JSON object")
        }
        return root
    }

    /// Ghi `visual.objects.data[0].properties.mode = "'<mode>'"` cho `slicer` cổ điển khi chưa có `objects.data`
    /// (VM-V11A `pop-slicer.visual.json`: cột số/ngày đặt mặc định `'Between'`). Đã có `objects.data` hoặc không phải `slicer` thì giữ nguyên byte.
    public static func settingSlicerModeIfUnset(_ mode: String, in json: Data) throws -> Data {
        guard let root = try? JSONValue.parse(json),
              root["visual"]?["visualType"]?.string == "slicer",
              root["visual"]?["objects"]?["data"] == nil else {
            return json
        }
        return try PBIRFormatPatch.apply([
            FormatEdit(scope: .objects, object: "data",
                       action: .set(property: "mode", value: #"{"expr":{"Literal":{"Value":"'\#(mode)'"}}}"#))
        ], to: json)
    }

    /// Ghi `visual.expansionStates` cho phân cấp hàng Matrix (`roles: ["Rows"]`, VM-V11B `b3-*-928f08c931d640590cd0.visual.json`).
    /// `expandedLiterals`: danh sách giá trị cấp 0 đang mở (vd `["'Midwest'"]`). Rỗng thì gỡ `expansionStates`.
    public static func settingRowExpansionStates(
        levels: [(entity: String, property: String, queryRef: String)],
        expandedLiterals: [String],
        in json: Data
    ) throws -> Data {
        guard var root = try? JSONSerialization.jsonObject(with: json, options: []) as? [String: Any],
              var visual = root["visual"] as? [String: Any] else {
            throw WriteError.invalid("visual.json has no visual object")
        }
        var bytes = [UInt8](json)
        func tok(_ s: String) -> String { String(decoding: PBIRPatch.jsonStringToken(s), as: UTF8.self) }

        let visualPath: [JSONPathStep] = [.key("visual")]
        if expandedLiterals.isEmpty || levels.count < 2 {
            if let kids = JSONCursor.children(at: visualPath, in: bytes),
               let idx = kids.firstIndex(where: { key(of: $0, in: bytes) == "expansionStates" }) {
                bytes = JSONCursor.removing([idx], from: kids, in: bytes)
            }
            visual["expansionStates"] = nil
        } else {
            let levelObjs = levels.enumerated().map { (i, lvl) -> String in
                if i < levels.count - 1 {
                    return #"{"queryRefs":[\#(tok(lvl.queryRef))],"isCollapsed":true,"identityKeys":[{"Column":{"Expression":{"SourceRef":{"Entity":\#(tok(lvl.entity))}},"Property":\#(tok(lvl.property))}}],"isPinned":true}"#
                } else {
                    return #"{"queryRefs":[\#(tok(lvl.queryRef))],"isCollapsed":true,"isPinned":true}"#
                }
            }
            let childrenObjs = expandedLiterals.map { lit in
                #"{"identityValues":[{"Literal":{"Value":\#(tok(lit))}}],"isToggled":true}"#
            }
            let stateText = #"[{"roles":["Rows"],"levels":[\#(levelObjs.joined(separator: ","))],"root":{"children":[\#(childrenObjs.joined(separator: ","))]}}]"#
            let path = visualPath + [.key("expansionStates")]
            if let range = JSONCursor.locate(path[...], in: bytes) {
                bytes.replaceSubrange(range, with: Array(stateText.utf8))
            } else if let vRange = JSONCursor.locate(visualPath[...], in: bytes) {
                let kids = JSONCursor.children(at: visualPath, in: bytes) ?? []
                let prefix = kids.isEmpty ? "" : ","
                bytes.insert(contentsOf: Array("\(prefix)\"expansionStates\":\(stateText)".utf8), at: vRange.upperBound - 1)
            }
            visual["expansionStates"] = try JSONSerialization.jsonObject(with: Data(stateText.utf8), options: [])
        }
        root["visual"] = visual
        guard let actual = try? JSONSerialization.jsonObject(with: Data(bytes), options: []) as? [String: Any],
              (root as NSDictionary).isEqual(to: actual) else {
            throw WriteError.verificationFailed("expansionStates splice changed other content")
        }
        return Data(bytes)
    }
}
