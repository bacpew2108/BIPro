import Foundation

/// Một bookmark ghi được (D6): dạng tối giản mà Power BI Desktop đã mở (hai bookmark của Nhom6, VM-D1) và không ghi lại.
/// `specs/007-d6-bookmark-filter/research.md` R6. Chỉ hiển thị (ẩn/hiện visual) và trang; Data chưa ghi (R6).
public struct BookmarkSpec: Equatable, Sendable {
    public struct VisualState: Equatable, Sendable {
        public var id: String
        public var type: String
        public var hidden: Bool
        public init(id: String, type: String, hidden: Bool) { self.id = id; self.type = type; self.hidden = hidden }
    }

    /// Lựa chọn của một slicer cột đơn (bookmark Data): `values` rỗng = "All".
    public struct SlicerSelection: Equatable, Sendable {
        public var entity: String
        public var property: String
        public var values: [FilterLiteral]
        public init(entity: String, property: String, values: [FilterLiteral]) { self.entity = entity; self.property = property; self.values = values }
    }

    public var name: String
    public var displayName: String
    /// Trang ghi trong `activeSection` và `sections` (visual của trang này).
    public var page: String
    public var visuals: [VisualState]
    public var suppressActiveSection: Bool
    public var suppressData: Bool
    public var suppressDisplay: Bool
    /// Chỉ dùng khi `suppressData == false`: mã slicer → lựa chọn. Slicer của trang không có trong bảng này được đặt về "All".
    public var slicers: [String: SlicerSelection]

    public init(name: String, displayName: String, page: String, visuals: [VisualState],
                suppressActiveSection: Bool = false, suppressData: Bool = true, suppressDisplay: Bool = false,
                slicers: [String: SlicerSelection] = [:]) {
        self.name = name; self.displayName = displayName; self.page = page; self.visuals = visuals
        self.suppressActiveSection = suppressActiveSection; self.suppressData = suppressData; self.suppressDisplay = suppressDisplay
        self.slicers = slicers
    }
}

/// Ghép byte cho `bookmarks/bookmarks.json` và `bookmarks/<name>.bookmark.json` (D6). Phần không đổi giữ từng byte.
/// Xem `specs/007-d6-bookmark-filter/contracts/bookmark-filter-save.md`.
public enum PBIRBookmarkPatch {
    public static let bookmarkSchema = "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/bookmark/2.1.0/schema.json"
    public static let indexSchema = "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/bookmarksMetadata/1.0.0/schema.json"

    private static func token(_ text: String) -> String { String(decoding: PBIRPatch.jsonStringToken(text), as: UTF8.self) }

    // MARK: - File bookmark

    /// File `<name>.bookmark.json` mới, gọn một dòng, khoá theo thứ tự Desktop: `$schema`, `displayName`, `name`, `options`,
    /// `explorationState`. `options` theo VM-D6: `applyOnlyToTargetVisuals`, `targetVisualNames`, `suppressActiveSection`,
    /// `suppressData`, `suppressDisplay`.
    public static func newBookmarkJSON(_ spec: BookmarkSpec) -> Data {
        if !spec.suppressData { return newDataBookmarkJSON(spec) }
        var options = ["\"applyOnlyToTargetVisuals\":true", "\"targetVisualNames\":[\(spec.visuals.map { token($0.id) }.joined(separator: ","))]"]
        if spec.suppressActiveSection { options.append("\"suppressActiveSection\":true") }
        if spec.suppressData { options.append("\"suppressData\":true") }
        if spec.suppressDisplay { options.append("\"suppressDisplay\":true") }
        let containers = spec.visuals.map { visual -> String in
            let display = (visual.hidden && !spec.suppressDisplay) ? ",\"display\":{\"mode\":\"hidden\"}" : ""
            return "\(token(visual.id)):{\"singleVisual\":{\"visualType\":\(token(visual.type))\(display)}}"
        }.joined(separator: ",")
        let state = "{\"version\":\"1.0\",\"activeSection\":\(token(spec.page)),\"sections\":{\(token(spec.page)):{\"visualContainers\":{\(containers)}}}}"
        let text = "{\"$schema\":\(token(bookmarkSchema)),\"displayName\":\(token(spec.displayName)),\"name\":\(token(spec.name)),"
            + "\"options\":{\(options.joined(separator: ","))},\"explorationState\":\(state)}"
        return Data(text.utf8)
    }

    /// Bookmark có Data, dạng tối giản Desktop đã áp đúng (VM-D6 vòng 2): `options{targetVisualNames:[],…,preserveNewVisualVisibility}`,
    /// `explorationState` 1.3 chỉ có trang và `visualContainers`; slicer có lựa chọn ghi `objects.merge.general[0].properties.filter.filter`,
    /// slicer không có thì không ghi `objects` (Desktop đặt về "All"), visual ẩn ghi `display{mode:"hidden"}`.
    private static func newDataBookmarkJSON(_ spec: BookmarkSpec) -> Data {
        var options = ["\"targetVisualNames\":[]"]
        if spec.suppressActiveSection { options.append("\"suppressActiveSection\":true") }
        if spec.suppressDisplay { options.append("\"suppressDisplay\":true") }
        options.append("\"preserveNewVisualVisibility\":true")
        let containers = spec.visuals.map { visual -> String in
            var single = "\"visualType\":\(token(visual.type))"
            if let slicer = spec.slicers[visual.id], !slicer.values.isEmpty {
                let filter = PBIRFilterPatch.categoricalFilter(entity: slicer.entity, property: slicer.property, values: slicer.values, exclude: false)
                single += ",\"objects\":{\"merge\":{\"general\":[{\"properties\":{\"filter\":{\"filter\":\(filter)}}}]}}"
            }
            if visual.hidden && !spec.suppressDisplay { single += ",\"display\":{\"mode\":\"hidden\"}" }
            return "\(token(visual.id)):{\"singleVisual\":{\(single)}}"
        }.joined(separator: ",")
        let state = "{\"version\":\"1.3\",\"activeSection\":\(token(spec.page)),\"sections\":{\(token(spec.page)):{\"visualContainers\":{\(containers)}}}}"
        let text = "{\"$schema\":\(token(bookmarkSchema)),\"displayName\":\(token(spec.displayName)),\"name\":\(token(spec.name)),"
            + "\"options\":{\(options.joined(separator: ","))},\"explorationState\":\(state)}"
        return Data(text.utf8)
    }

    /// `json` với `displayName` đổi (chỉ đúng đoạn byte của giá trị).
    public static func renamingDisplayName(_ name: String, in json: Data) throws -> Data {
        let root = try parseObject(json)
        var bytes = [UInt8](json)
        if let range = JSONCursor.locate([.key("displayName")][...], in: bytes) {
            bytes.replaceSubrange(range, with: PBIRPatch.jsonStringToken(name))
        } else if let kids = JSONCursor.children(at: [], in: bytes),
                  let nameKid = kids.first(where: { $0.key.flatMap { JSONCursor.string(in: bytes, $0) } == "name" }) {
            // Bookmark không có `displayName` (file tay): chèn trước `name` như thứ tự Desktop.
            bytes.insert(contentsOf: Array("\"displayName\":".utf8) + PBIRPatch.jsonStringToken(name) + [UInt8(ascii: ",")], at: nameKid.start)
        } else {
            throw WriteError.invalid("bookmark has no displayName or name")
        }
        var expected = root
        expected["displayName"] = name
        try verify(Data(bytes), equals: expected, what: "bookmark rename")
        return Data(bytes)
    }

    /// Tên hiển thị và mã của một file bookmark.
    public static func identity(of json: Data) -> (name: String, displayName: String)? {
        guard let root = try? parseObject(json), let name = root["name"] as? String else { return nil }
        return (name, root["displayName"] as? String ?? name)
    }

    // MARK: - bookmarks.json

    /// `bookmarks.json` mới (khi file chưa có) hoặc thêm `{name}` vào cuối `items`.
    public static func addingItem(_ name: String, to json: Data?) throws -> Data {
        guard let json else {
            return Data("{\"$schema\":\(token(indexSchema)),\"items\":[{\"name\":\(token(name))}]}".utf8)
        }
        let root = try parseObject(json)
        var bytes = [UInt8](json)
        guard let array = JSONCursor.locate([.key("items")][...], in: bytes), bytes[array.lowerBound] == UInt8(ascii: "["),
              let kids = JSONCursor.children(at: [.key("items")], in: bytes) else { throw WriteError.invalid("bookmarks.json has no items array") }
        let entry = Array("{\"name\":\(token(name))}".utf8)
        if let last = kids.last {
            bytes.insert(contentsOf: [UInt8(ascii: ",")] + entry, at: last.value.upperBound)
        } else {
            bytes.insert(contentsOf: entry, at: array.lowerBound + 1)
        }
        var expected = root
        expected["items"] = (root["items"] as? [Any] ?? []) + [["name": name]]
        try verify(Data(bytes), equals: expected, what: "bookmarks.json add")
        return Data(bytes)
    }

    /// `bookmarks.json` với `items` sắp lại theo `names` (mục không có trong `names` giữ thứ tự cũ ở cuối). Nhóm (`children`) nguyên.
    public static func reorderingItems(_ names: [String], in json: Data) throws -> Data {
        let root = try parseObject(json)
        guard let items = root["items"] as? [[String: Any]] else { return json }
        var bytes = [UInt8](json)
        guard let kids = JSONCursor.children(at: [.key("items")], in: bytes), kids.count == items.count else { return json }
        func itemName(_ item: [String: Any]) -> String { (item["name"] as? String) ?? "" }
        var order: [Int] = []
        var used = Set<Int>()
        for name in names {
            if let index = items.indices.first(where: { !used.contains($0) && itemName(items[$0]) == name }) { order.append(index); used.insert(index) }
        }
        order += items.indices.filter { !used.contains($0) }
        guard order != Array(items.indices) else { return json }
        let separator: [UInt8] = kids.count >= 2 ? Array(bytes[kids[0].value.upperBound..<kids[1].value.lowerBound]) : [UInt8(ascii: ",")]
        var replacement: [UInt8] = []
        for (position, index) in order.enumerated() {
            if position > 0 { replacement += separator }
            replacement += Array(bytes[kids[index].value])
        }
        bytes.replaceSubrange(kids[0].value.lowerBound..<kids[kids.count - 1].value.upperBound, with: replacement)
        var expected = root
        expected["items"] = order.map { items[$0] }
        try verify(Data(bytes), equals: expected, what: "bookmarks.json reorder")
        return Data(bytes)
    }

    /// Tên các bookmark trong `items` (kể cả con của nhóm), theo thứ tự.
    public static func itemNames(in json: Data) -> [String] {
        guard let root = try? parseObject(json), let items = root["items"] as? [[String: Any]] else { return [] }
        var out: [String] = []
        for item in items {
            if let children = item["children"] as? [String] { out += children }
            else if let name = item["name"] as? String { out.append(name) }
        }
        return out
    }

    // MARK: - Nhóm bookmark (VM-D8 mục 5)

    /// Một nhóm bookmark trong `bookmarks.json`: mục cấp gốc có `children`.
    public struct Group: Equatable, Sendable {
        public var id: String
        public var displayName: String
        public var children: [String]
        public init(id: String, displayName: String, children: [String]) { self.id = id; self.displayName = displayName; self.children = children }
    }

    /// Các nhóm trong `items`, theo thứ tự.
    public static func groups(in json: Data) -> [Group] {
        guard let root = try? parseObject(json), let items = root["items"] as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let children = item["children"] as? [String], let name = item["name"] as? String else { return nil }
            return Group(id: name, displayName: item["displayName"] as? String ?? name, children: children)
        }
    }

    /// Gom các bookmark `names` đang là mục cấp gốc vào một nhóm mới, như Desktop ghi khi chọn Group ở Bookmarks pane:
    /// `{"name":"<id>","displayName":"Group 1","children":[…]}` đứng ở chỗ của bookmark đầu tiên, các bookmark đó không còn
    /// là mục cấp gốc. Thứ tự `children` theo thứ tự trong `items`. Tên không phải mục cấp gốc (đã ở nhóm khác, không có)
    /// bị bỏ qua; không còn tên nào thì trả nguyên `json`.
    public static func groupingItems(_ names: [String], id: String, displayName: String, in json: Data) throws -> Data {
        let root = try parseObject(json)
        guard let items = root["items"] as? [[String: Any]] else { throw WriteError.invalid("bookmarks.json has no items array") }
        var bytes = [UInt8](json)
        guard let kids = JSONCursor.children(at: [.key("items")], in: bytes), kids.count == items.count else {
            throw WriteError.invalid("bookmarks.json has no items array")
        }
        let wanted = Set(names)
        let found = items.indices.filter { items[$0]["children"] == nil && wanted.contains((items[$0]["name"] as? String) ?? "") }
        guard let first = found.first else { return json }
        let children = found.compactMap { items[$0]["name"] as? String }
        let text = "{\"name\":\(token(id)),\"displayName\":\(token(displayName)),\"children\":[\(children.map(token).joined(separator: ","))]}"
        // Bỏ các mục sau mục đầu (chỉ số của mục đầu không đổi), rồi thay mục đầu bằng mục nhóm.
        let others = Set(found.dropFirst())
        if !others.isEmpty { bytes = JSONCursor.removing(others, from: kids, in: bytes) }
        guard let place = JSONCursor.locate([.key("items"), .index(first)][...], in: bytes) else {
            throw WriteError.invalid("bookmarks.json items changed shape")
        }
        bytes.replaceSubrange(place, with: Array(text.utf8))
        var expectedItems: [Any] = []
        for (index, item) in items.enumerated() where !others.contains(index) {
            expectedItems.append(index == first ? ["name": id, "displayName": displayName, "children": children] as [String: Any] : item)
        }
        var expected = root
        expected["items"] = expectedItems
        try verify(Data(bytes), equals: expected, what: "bookmarks.json group")
        return Data(bytes)
    }

    /// Bỏ nhóm `id`: các bookmark con thành mục cấp gốc `{"name":…}` ngay tại chỗ của nhóm. Không có nhóm đó thì trả nguyên `json`.
    public static func ungroupingItem(_ id: String, in json: Data) throws -> Data {
        let root = try parseObject(json)
        guard let items = root["items"] as? [[String: Any]],
              let index = items.firstIndex(where: { $0["name"] as? String == id && $0["children"] is [String] }),
              let children = items[index]["children"] as? [String] else { return json }
        var bytes = [UInt8](json)
        guard let kids = JSONCursor.children(at: [.key("items")], in: bytes), kids.count == items.count else { return json }
        if children.isEmpty {
            bytes = JSONCursor.removing([index], from: kids, in: bytes)
        } else {
            bytes.replaceSubrange(kids[index].value, with: Array(children.map { "{\"name\":\(token($0))}" }.joined(separator: ",").utf8))
        }
        var expectedItems: [Any] = items
        expectedItems.replaceSubrange(index...index, with: children.map { ["name": $0] as [String: Any] })
        var expected = root
        expected["items"] = expectedItems
        try verify(Data(bytes), equals: expected, what: "bookmarks.json ungroup")
        return Data(bytes)
    }

    // MARK: - Helpers

    private static func parseObject(_ json: Data) throws -> [String: Any] {
        guard let root = try? JSONSerialization.jsonObject(with: json, options: []) as? [String: Any] else {
            throw WriteError.invalid("part is not a JSON object")
        }
        return root
    }

    private static func verify(_ data: Data, equals expected: [String: Any], what: String) throws {
        guard let actual = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              (expected as NSDictionary).isEqual(to: actual) else {
            throw WriteError.verificationFailed("\(what) splice changed other content")
        }
    }
}
