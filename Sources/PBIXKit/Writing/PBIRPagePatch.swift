import Foundation

/// Edits to the page parts of a PBIR report: `pages/pages.json` (order and landing page), `pages/<id>/page.json`
/// (name, a new page, a copy of a page), the `visual.json` of a copied visual, and the references to a page in
/// bookmarks. Like `PBIRLayoutPatch` and `PBIRQueryPatch`, every edit splices bytes (what is not touched stays byte
/// for byte), then re-parses the result and compares it with the expected structure.
///
/// Contract: `specs/005-d5-quan-ly-trang/contracts/page-save.md`. Shapes observed on Power BI Desktop in VM-D5
/// (`docs/phase-d-evidence/vm-d5/QUAN-SAT.md`).
public enum PBIRPagePatch {
    public static let defaultPageSchema = "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/page/2.1.0/schema.json"

    /// What happens to a bookmark when pages go away.
    public enum BookmarkOutcome {
        /// Nothing in it mentions the pages.
        case unchanged
        /// It keeps working: the entries of the removed pages are gone from `explorationState.sections`.
        case trimmed(Data)
        /// Its `activeSection` is a removed page: the whole bookmark goes.
        case remove
    }

    // MARK: - A new page

    /// The `page.json` Power BI Desktop writes for an empty page (one line, no BOM): 1920 × 1080, `FitToPage`.
    public static func newPageJSON(id: String, displayName: String, schema: String?) -> Data {
        func token(_ text: String) -> String { String(decoding: PBIRPatch.jsonStringToken(text), as: UTF8.self) }
        let text = #"{"$schema":\#(token(schema ?? defaultPageSchema)),"name":\#(token(id)),"displayName":\#(token(displayName)),"displayOption":"FitToPage","height":1080,"width":1920}"#
        return Data(text.utf8)
    }

    // MARK: - pages.json

    /// `pagesJSON` with `pageOrder` set to `order` and, when `activePage` is not nil, `activePageName` set to it
    /// (added at the end when the file has none).
    public static func setPageOrder(_ order: [String], activePage: String?, in pagesJSON: Data) throws -> Data {
        let root = try parseObject(pagesJSON)
        var bytes = [UInt8](pagesJSON)
        guard let orderRange = JSONCursor.locate([.key("pageOrder")][...], in: bytes), bytes[orderRange.lowerBound] == UInt8(ascii: "[") else {
            throw WriteError.invalid("pages.json has no pageOrder array")
        }
        let old = JSONCursor.children(at: [.key("pageOrder")], in: bytes) ?? []
        let replacement = stringArrayText(order, replacing: old, array: orderRange, in: bytes)

        var edits: [(range: Range<Int>, text: [UInt8])] = [(orderRange, replacement)]
        var appendActive = false
        if let activePage {
            if let range = JSONCursor.locate([.key("activePageName")][...], in: bytes) {
                edits.append((range, PBIRPatch.jsonStringToken(activePage)))
            } else {
                appendActive = true
            }
        }
        for edit in edits.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            bytes.replaceSubrange(edit.range, with: edit.text)
        }
        if appendActive, let activePage {
            guard let close = bytes.lastIndex(of: UInt8(ascii: "}")) else { throw WriteError.invalid("pages.json is not an object") }
            bytes.insert(contentsOf: Array(#","activePageName":"#.utf8) + PBIRPatch.jsonStringToken(activePage), at: close)
        }

        var expected = root
        expected["pageOrder"] = order
        if let activePage { expected["activePageName"] = activePage }
        // `landingPageName` ("Set as landing page", VM-D5) that names a page that is gone would dangle: drop it.
        if let landing = root["landingPageName"] as? String, !order.contains(landing),
           let kids = JSONCursor.children(at: [], in: bytes),
           let index = kids.firstIndex(where: { $0.key.flatMap { JSONCursor.string(in: bytes, $0) } == "landingPageName" }) {
            bytes = JSONCursor.removing([index], from: kids, in: bytes)
            expected["landingPageName"] = nil
        }
        try verify(Data(bytes), equals: expected, what: "pages.json")
        return Data(bytes)
    }

    // MARK: - page.json

    /// `pageJSON` with `displayName` set (added after `name` when missing).
    public static func setPageDisplayName(_ name: String, in pageJSON: Data) throws -> Data {
        let root = try parseObject(pageJSON)
        var bytes = [UInt8](pageJSON)
        if let range = JSONCursor.locate([.key("displayName")][...], in: bytes) {
            bytes.replaceSubrange(range, with: PBIRPatch.jsonStringToken(name))
        } else if let nameRange = JSONCursor.locate([.key("name")][...], in: bytes) {
            bytes.insert(contentsOf: Array(#","displayName":"#.utf8) + PBIRPatch.jsonStringToken(name), at: nameRange.upperBound)
        } else {
            throw WriteError.invalid("page.json has no name")
        }
        var expected = root
        expected["displayName"] = name
        try verify(Data(bytes), equals: expected, what: "page.json")
        return Data(bytes)
    }

    /// Đặt mảng `visualInteractions` trong `page.json` theo đúng định dạng PBIR (VM-V11B `b2-d1.page.json`).
    /// Mảng rỗng thì gỡ khoá `visualInteractions`; giữ nguyên từng byte các khoá khác.
    public static func settingVisualInteractions(_ interactions: [PageVisualInteraction], in pageJSON: Data) throws -> Data {
        let root = try parseObject(pageJSON)
        var bytes = [UInt8](pageJSON)
        func tok(_ s: String) -> String { String(decoding: PBIRPatch.jsonStringToken(s), as: UTF8.self) }
        var expected = root

        if interactions.isEmpty {
            if let kids = JSONCursor.children(at: [], in: bytes),
               let index = kids.firstIndex(where: { $0.key.flatMap { JSONCursor.string(in: bytes, $0) } == "visualInteractions" }) {
                bytes = JSONCursor.removing([index], from: kids, in: bytes)
            }
            expected["visualInteractions"] = nil
        } else {
            let items = interactions.map { item in
                #"{"source":\#(tok(item.source)),"target":\#(tok(item.target)),"type":\#(tok(item.type.rawValue))}"#
            }
            let arrayText = "[" + items.joined(separator: ",") + "]"
            if let range = JSONCursor.locate([.key("visualInteractions")][...], in: bytes) {
                bytes.replaceSubrange(range, with: Array(arrayText.utf8))
            } else {
                guard let close = bytes.lastIndex(of: UInt8(ascii: "}")) else {
                    throw WriteError.invalid("page.json is not an object")
                }
                let kids = JSONCursor.children(at: [], in: bytes) ?? []
                let prefix = kids.isEmpty ? "" : ","
                bytes.insert(contentsOf: Array("\(prefix)\"visualInteractions\":\(arrayText)".utf8), at: close)
            }
            expected["visualInteractions"] = interactions.map {
                ["source": $0.source, "target": $0.target, "type": $0.type.rawValue]
            }
        }
        try verify(Data(bytes), equals: expected, what: "page.json visualInteractions")
        return Data(bytes)
    }

    /// A copy of `source` (a `page.json`) for a new page: `name` and `displayName` replaced, `pageBinding` dropped (a
    /// copy is not a second drillthrough page), and the visual ids in `visualInteractions` mapped to the copies' ids.
    public static func duplicatedPageJSON(_ source: Data, newName: String, displayName: String, visualIDMap: [String: String]) throws -> Data {
        let root = try parseObject(source)
        var bytes = [UInt8](source)

        var edits: [(range: Range<Int>, text: [UInt8])] = []
        guard let nameRange = JSONCursor.locate([.key("name")][...], in: bytes) else { throw WriteError.invalid("page.json has no name") }
        edits.append((nameRange, PBIRPatch.jsonStringToken(newName)))
        var insertDisplayName = false
        if let range = JSONCursor.locate([.key("displayName")][...], in: bytes) {
            edits.append((range, PBIRPatch.jsonStringToken(displayName)))
        } else {
            insertDisplayName = true
        }
        let rows = JSONCursor.children(at: [.key("visualInteractions")], in: bytes) ?? []
        for index in rows.indices {
            for key in ["source", "target"] {
                let path: [JSONPathStep] = [.key("visualInteractions"), .index(index), .key(key)]
                guard let range = JSONCursor.locate(path[...], in: bytes), let id = JSONCursor.string(in: bytes, range),
                      let mapped = visualIDMap[id] else { continue }
                edits.append((range, PBIRPatch.jsonStringToken(mapped)))
            }
        }
        for edit in edits.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            bytes.replaceSubrange(edit.range, with: edit.text)
        }
        if insertDisplayName, let range = JSONCursor.locate([.key("name")][...], in: bytes) {
            bytes.insert(contentsOf: Array(#","displayName":"#.utf8) + PBIRPatch.jsonStringToken(displayName), at: range.upperBound)
        }
        if let kids = JSONCursor.children(at: [], in: bytes),
           let index = kids.firstIndex(where: { $0.key.flatMap { JSONCursor.string(in: bytes, $0) } == "pageBinding" }) {
            bytes = JSONCursor.removing([index], from: kids, in: bytes)
        }

        var expected = root
        expected["name"] = newName
        expected["displayName"] = displayName
        expected["pageBinding"] = nil
        if let rows = root["visualInteractions"] as? [[String: Any]] {
            expected["visualInteractions"] = rows.map { row -> [String: Any] in
                var row = row
                for key in ["source", "target"] { if let id = row[key] as? String, let mapped = visualIDMap[id] { row[key] = mapped } }
                return row
            }
        }
        try verify(Data(bytes), equals: expected, what: "copied page.json")
        return Data(bytes)
    }

    // MARK: - visual.json of a copied visual

    /// `json` (a `visual.json`) with `name` set to `newName` and, when the visual has one and `parentGroupName` is
    /// given, `parentGroupName` set to it. Everything else, positions with decimals included, keeps its bytes.
    public static func renamedVisualJSON(_ json: Data, newName: String, parentGroupName: String?) throws -> Data {
        let root = try parseObject(json)
        var bytes = [UInt8](json)
        guard root["name"] is String, let nameRange = JSONCursor.locate([.key("name")][...], in: bytes) else {
            throw WriteError.invalid("visual.json has no name")
        }
        var edits: [(range: Range<Int>, text: [UInt8])] = [(nameRange, PBIRPatch.jsonStringToken(newName))]
        var expected = root
        expected["name"] = newName
        if let parentGroupName, root["parentGroupName"] is String,
           let range = JSONCursor.locate([.key("parentGroupName")][...], in: bytes) {
            edits.append((range, PBIRPatch.jsonStringToken(parentGroupName)))
            expected["parentGroupName"] = parentGroupName
        }
        for edit in edits.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            bytes.replaceSubrange(edit.range, with: edit.text)
        }
        try verify(Data(bytes), equals: expected, what: "copied visual.json")
        return Data(bytes)
    }

    // MARK: - Bookmarks

    /// What a bookmark becomes when the pages in `ids` are removed: it goes when its `activeSection` is one of them,
    /// loses their entries in `explorationState.sections` when it only mentions them there, and is left alone otherwise.
    public static func removingPageReferences(_ ids: Set<String>, fromBookmark json: Data) throws -> BookmarkOutcome {
        let root = try parseObject(json)
        guard !ids.isEmpty else { return .unchanged }
        let state = root["explorationState"] as? [String: Any]
        if let active = state?["activeSection"] as? String, ids.contains(active) { return .remove }
        let bytes = [UInt8](json)
        guard let sections = state?["sections"] as? [String: Any], !ids.isDisjoint(with: sections.keys),
              let kids = JSONCursor.children(at: [.key("explorationState"), .key("sections")], in: bytes) else { return .unchanged }
        let drop = Set(kids.indices.filter { index in
            kids[index].key.flatMap { JSONCursor.string(in: bytes, $0) }.map(ids.contains) ?? false
        })
        let result = JSONCursor.removing(drop, from: kids, in: bytes)
        var expected = root
        var newState = state ?? [:]
        newState["sections"] = sections.filter { !ids.contains($0.key) }
        expected["explorationState"] = newState
        try verify(Data(result), equals: expected, what: "bookmark")
        return .trimmed(Data(result))
    }

    /// `bookmarks.json` without the `items[]` entries named in `names`. A bookmark group (`children`) loses the removed
    /// names; a group left without children goes too.
    public static func bookmarkItemsRemoving(_ names: Set<String>, from json: Data) throws -> Data {
        let root = try parseObject(json)
        guard !names.isEmpty, let items = root["items"] as? [[String: Any]] else { return json }
        var bytes = [UInt8](json)
        guard let kids = JSONCursor.children(at: [.key("items")], in: bytes), kids.count == items.count else { return json }
        var drop = Set(items.indices.filter { names.contains((items[$0]["name"] as? String) ?? "") })
        var expectedItems: [[String: Any]] = []
        var childEdits: [(index: Int, remaining: [String])] = []
        for (index, item) in items.enumerated() where !drop.contains(index) {
            var kept = item
            if let children = item["children"] as? [String], !names.isDisjoint(with: children) {
                let remaining = children.filter { !names.contains($0) }
                if remaining.isEmpty { drop.insert(index); continue }
                childEdits.append((index, remaining))
                kept["children"] = remaining
            }
            expectedItems.append(kept)
        }
        guard !drop.isEmpty || !childEdits.isEmpty else { return json }
        // Sửa mảng `children` trước (từ cuối về đầu), rồi bỏ mục.
        for edit in childEdits.sorted(by: { $0.index > $1.index }) {
            let path: [JSONPathStep] = [.key("items"), .index(edit.index), .key("children")]
            guard let range = JSONCursor.locate(path[...], in: bytes), let old = JSONCursor.children(at: path, in: bytes) else { continue }
            bytes.replaceSubrange(range, with: stringArrayText(edit.remaining, replacing: old, array: range, in: bytes))
        }
        if !drop.isEmpty, let fresh = JSONCursor.children(at: [.key("items")], in: bytes) {
            bytes = JSONCursor.removing(drop, from: fresh, in: bytes)
        }
        var expected = root
        expected["items"] = expectedItems
        try verify(Data(bytes), equals: expected, what: "bookmarks.json")
        return Data(bytes)
    }

    // MARK: - Navigation buttons

    private static let navigationMarker = Data("PageNavigation".utf8)

    /// The pages in `knownPages` that a `visualLink` of type `PageNavigation` in this `visual.json` points to (any
    /// string value of that link equal to a known page id). The key that holds the target is not yet observed
    /// (Nhom6 has no such button), so every value of the link is considered.
    public static func pageNavigationTargets(in visualJSON: Data, knownPages: Set<String>) -> Set<String> {
        // Most visuals are not navigation buttons: skip the parse unless the link type is there at all.
        guard !knownPages.isEmpty, visualJSON.range(of: navigationMarker) != nil,
              let root = try? JSONValue.parse(visualJSON) else { return [] }
        var found = Set<String>()
        func literals(_ value: JSONValue) -> [String] {
            switch value {
            case .string(let text): [text.trimmingCharacters(in: CharacterSet(charactersIn: "'"))]
            case .object(let dict): dict.values.flatMap(literals)
            case .array(let items): items.flatMap(literals)
            default: []
            }
        }
        for object in ["visualContainerObjects", "objects"] {
            for link in root["visual"]?[object]?["visualLink"]?.array ?? [] {
                let properties = link["properties"]
                let type = properties?["type"]?["expr"]?["Literal"]?["Value"]?.string
                guard type == "'PageNavigation'" else { continue }
                for value in Array(properties?.object.values ?? [:].values) { found.formUnion(literals(value).filter(knownPages.contains)) }
            }
        }
        return found
    }

    // MARK: - Helpers

    /// The array text for `values`: elements joined the way the existing array joins them (compact stays compact,
    /// indented stays indented).
    private static func stringArrayText(_ values: [String], replacing old: [JSONCursor.Child], array: Range<Int>, in bytes: [UInt8]) -> [UInt8] {
        var prefix: [UInt8] = [], separator: [UInt8] = [UInt8(ascii: ",")], suffix: [UInt8] = []
        if let first = old.first, let last = old.last {
            prefix = Array(bytes[(array.lowerBound + 1)..<first.value.lowerBound])
            suffix = Array(bytes[last.value.upperBound..<(array.upperBound - 1)])
            separator = old.count >= 2 ? Array(bytes[old[0].value.upperBound..<old[1].value.lowerBound])
                                       : [UInt8(ascii: ",")] + prefix
        }
        var out: [UInt8] = [UInt8(ascii: "[")]
        if !values.isEmpty { out += prefix }
        for (index, value) in values.enumerated() {
            if index > 0 { out += separator }
            out += PBIRPatch.jsonStringToken(value)
        }
        if !values.isEmpty { out += suffix }
        out.append(UInt8(ascii: "]"))
        return out
    }

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
