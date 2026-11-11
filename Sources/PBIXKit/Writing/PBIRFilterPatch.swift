import Foundation

/// Giá trị trong điều kiện lọc, ghi theo kiểu Power BI: chuỗi `'x'` (nháy đơn gấp đôi), số nguyên `…L`, số thực `…D`, `true`/`false`.
public enum FilterLiteral: Equatable, Sendable {
    case string(String)
    case integer(Int64)
    case decimal(Double)
    case boolean(Bool)

    var text: String {
        switch self {
        case .string(let s): "'" + s.replacingOccurrences(of: "'", with: "''") + "'"
        case .integer(let n): "\(n)L"
        case .decimal(let d): (d == d.rounded() && abs(d) < 1e15 ? String(Int64(d)) : "\(d)") + "D"
        case .boolean(let b): b ? "true" : "false"
        }
    }
}

/// Một thẻ lọc trong `filterConfig.filters` (D6). `filter` là văn bản JSON của khoá `filter` (nil: thẻ chưa chọn gì).
public struct FilterCardSpec: Equatable, Sendable {
    public enum Kind: String, Sendable { case column = "Column", measure = "Measure" }
    public var name: String
    public var kind: Kind
    public var entity: String
    public var property: String
    /// `Categorical`, `Advanced`, `TopN`.
    public var type: String
    public var filter: String?
    /// Thẻ do người dùng thêm ghi `"howCreated":"User"` (VM-D6).
    public var howCreated: String?

    public init(name: String, kind: Kind = .column, entity: String, property: String, type: String, filter: String? = nil,
                howCreated: String? = "User") {
        self.name = name; self.kind = kind; self.entity = entity; self.property = property
        self.type = type; self.filter = filter; self.howCreated = howCreated
    }
}

/// Ghép byte thẻ lọc vào `report.json`, `page.json`, `visual.json` (D6): `filterConfig.filters`. Phần khác giữ từng byte.
/// Dạng thẻ theo VM-D6 (`specs/007-d6-bookmark-filter/research.md` R2, R7).
public enum PBIRFilterPatch {
    public enum Level: Sendable { case report, page, visual }

    public enum Change: Equatable, Sendable {
        /// Thêm ở cuối, hoặc (cùng `name`) chỉ thay `type` và `filter` của thẻ có sẵn, giữ các khoá khác.
        case upsert(FilterCardSpec)
        case remove(name: String)
    }

    // MARK: - Dựng JSON

    private static func token(_ text: String) -> String { String(decoding: PBIRPatch.jsonStringToken(text), as: UTF8.self) }

    /// Bí danh `From` mà Desktop đặt: chữ cái đầu của bảng, viết thường (VM-D6); trùng bảng khác thì thêm số.
    public static func aliases(for entities: [String]) -> [String: String] {
        var out: [String: String] = [:]
        var used = Set<String>()
        for entity in entities where out[entity] == nil {
            let letter = String(entity.first.map { Character($0.lowercased()) } ?? "t")
            var alias = letter, n = 1
            while used.contains(alias) { n += 1; alias = letter + String(n) }
            used.insert(alias); out[entity] = alias
        }
        return out
    }

    private static func column(alias: String, property: String) -> String {
        "{\"Column\":{\"Expression\":{\"SourceRef\":{\"Source\":\(token(alias))}},\"Property\":\(token(property))}}"
    }

    private static func from(_ aliases: [(entity: String, alias: String)]) -> String {
        "[" + aliases.map { "{\"Name\":\(token($0.alias)),\"Entity\":\(token($0.entity)),\"Type\":0}" }.joined(separator: ",") + "]"
    }

    /// Basic: `In` hoặc `Not In`. Nhiều giá trị ghi `Values:[[v1],[v2]]` ([SUY ĐOÁN] cho nhiều giá trị: Nhom6 chỉ có một giá trị; kiểm ở T035).
    public static func categoricalFilter(entity: String, property: String, values: [FilterLiteral], exclude: Bool) -> String {
        let alias = aliases(for: [entity])[entity] ?? "t"
        let list = values.map { "[{\"Literal\":{\"Value\":\(token($0.text))}}]" }.joined(separator: ",")
        let inExpr = "{\"In\":{\"Expressions\":[\(column(alias: alias, property: property))],\"Values\":[\(list)]}}"
        let condition = exclude ? "{\"Not\":{\"Expression\":\(inExpr)}}" : inExpr
        return "{\"Version\":2,\"From\":\(from([(entity, alias)])),\"Where\":[{\"Condition\":\(condition)}]}"
    }

    public enum TextOperator: Sendable { case contains, startsWith }

    public struct TextCondition: Equatable, Sendable {
        public var op: TextOperator
        public var negated: Bool
        public var text: String
        public init(_ op: TextOperator, negated: Bool = false, text: String) { self.op = op; self.negated = negated; self.text = text }
    }

    /// Advanced chữ (VM-D6): `Contains`, `StartsWith`, `Not{…}`, `And` của hai điều kiện. Nhiều hơn hai hoặc Or: chưa quan sát.
    public static func advancedTextFilter(entity: String, property: String, conditions: [TextCondition]) -> String? {
        guard (1...2).contains(conditions.count) else { return nil }
        let alias = aliases(for: [entity])[entity] ?? "t"
        func node(_ c: TextCondition) -> String {
            let name = c.op == .contains ? "Contains" : "StartsWith"
            let inner = "{\"\(name)\":{\"Left\":\(column(alias: alias, property: property)),\"Right\":{\"Literal\":{\"Value\":\(token(FilterLiteral.string(c.text).text))}}}}"
            return c.negated ? "{\"Not\":{\"Expression\":\(inner)}}" : inner
        }
        let condition = conditions.count == 1 ? node(conditions[0]) : "{\"And\":{\"Left\":\(node(conditions[0])),\"Right\":\(node(conditions[1]))}}"
        return "{\"Version\":2,\"From\":\(from([(entity, alias)])),\"Where\":[{\"Condition\":\(condition)}]}"
    }

    /// Top N (VM-D6, mẫu Top; Bottom chưa quan sát): `From` có truy vấn con chọn `count` giá trị đầu theo measure.
    public static func topNFilter(entity: String, property: String, measureEntity: String, measureProperty: String, count: Int) -> String {
        var entities = [entity]
        if measureEntity != entity { entities.append(measureEntity) }
        let map = aliases(for: entities)
        let d = map[entity] ?? "d", f = map[measureEntity] ?? d
        var inner = [(entity, d)]
        if measureEntity != entity { inner.append((measureEntity, f)) }
        let select = "[{\"Column\":{\"Expression\":{\"SourceRef\":{\"Source\":\(token(d))}},\"Property\":\(token(property))},\"Name\":\"field\"}]"
        let order = "[{\"Direction\":2,\"Expression\":{\"Measure\":{\"Expression\":{\"SourceRef\":{\"Source\":\(token(f))}},\"Property\":\(token(measureProperty))}}}]"
        let query = "{\"Version\":2,\"From\":\(from(inner)),\"Select\":\(select),\"OrderBy\":\(order),\"Top\":\(count)}"
        let sub = "{\"Name\":\"subquery\",\"Expression\":{\"Subquery\":{\"Query\":\(query)}},\"Type\":2}"
        let outerFrom = "[\(sub),{\"Name\":\(token(d)),\"Entity\":\(token(entity)),\"Type\":0}]"
        let condition = "{\"In\":{\"Expressions\":[\(column(alias: d, property: property))],\"Table\":{\"SourceRef\":{\"Source\":\"subquery\"}}}}"
        return "{\"Version\":2,\"From\":\(outerFrom),\"Where\":[{\"Condition\":\(condition)}]}"
    }

    /// Văn bản JSON của một thẻ mới: `name`, `field`, `type`, `filter?`, `howCreated?` (thứ tự Desktop).
    public static func cardJSON(_ card: FilterCardSpec) -> String {
        let field = "{\"\(card.kind.rawValue)\":{\"Expression\":{\"SourceRef\":{\"Entity\":\(token(card.entity))}},\"Property\":\(token(card.property))}}"
        var out = "{\"name\":\(token(card.name)),\"field\":\(field),\"type\":\(token(card.type))"
        if let filter = card.filter { out += ",\"filter\":\(filter)" }
        if let how = card.howCreated { out += ",\"howCreated\":\(token(how))" }
        return out + "}"
    }

    /// Mã thẻ mới: 20 hex ngẫu nhiên không trùng `taken`.
    public static func makeCardName(avoiding taken: Set<String>) -> String { PBIRLayoutPatch.makeVisualName(avoiding: taken) }

    // MARK: - Ghép byte

    /// Các khoá của `report.json`/`page.json`/`visual.json` mà `filterConfig` mới đứng sau (VM-D6: `page.json` sau `width`,
    /// `visual.json` sau `visual`; `report.json` chưa có mẫu thiếu `filterConfig`, đặt sau `themeCollection`).
    private static func anchors(for level: Level) -> [String] {
        switch level {
        case .report: ["themeCollection", "$schema"]
        case .page: ["width", "height", "displayOption", "displayName", "name", "$schema"]
        case .visual: ["visual", "position", "name", "$schema"]
        }
    }

    public static func apply(_ changes: [Change], level: Level, to json: Data) throws -> Data {
        guard !changes.isEmpty else { return json }
        guard var model = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] else { throw WriteError.invalid("part is not a JSON object") }
        var bytes = [UInt8](json)
        var cards = ((model["filterConfig"] as? [String: Any])?["filters"] as? [[String: Any]]) ?? []
        let hadConfig = model["filterConfig"] != nil
        let hadFilters = (model["filterConfig"] as? [String: Any])?["filters"] != nil

        for change in changes {
            switch change {
            case .upsert(let card):
                if let index = cards.firstIndex(where: { ($0["name"] as? String) == card.name }) {
                    try modifyCard(at: index, with: card, in: &bytes)
                    var updated = cards[index]
                    updated["type"] = card.type
                    if let filter = card.filter { updated["filter"] = try parseFragment(filter) } else { updated["filter"] = nil }
                    cards[index] = updated
                } else {
                    let text = Array(cardJSON(card).utf8)
                    try appendCard(text, level: level, in: &bytes, hadFilters: cards.count > 0 || hadFilters)
                    cards.append(try parseObject(Data(text)))
                }
            case .remove(let name):
                guard let index = cards.firstIndex(where: { ($0["name"] as? String) == name }) else { continue }
                try removeCard(at: index, in: &bytes)
                cards.remove(at: index)
            }
            // Sau mỗi thay đổi `bytes` hợp lệ để lần sau tìm đúng chỗ.
        }

        // Mô hình mong đợi.
        if cards.isEmpty {
            if hadConfig, (model["filterConfig"] as? [String: Any])?.count == 1 { model["filterConfig"] = nil }
            else if hadConfig { var config = model["filterConfig"] as! [String: Any]; config["filters"] = []; model["filterConfig"] = config }
        } else {
            var config = (model["filterConfig"] as? [String: Any]) ?? [:]
            config["filters"] = cards
            model["filterConfig"] = config
        }
        guard let actual = (try? JSONSerialization.jsonObject(with: Data(bytes))) as? [String: Any],
              (model as NSDictionary).isEqual(to: actual) else {
            throw WriteError.verificationFailed("filterConfig splice changed other content")
        }
        return Data(bytes)
    }

    private static func filtersPath() -> [JSONPathStep] { [.key("filterConfig"), .key("filters")] }

    private static func keyName(_ kid: JSONCursor.Child, _ bytes: [UInt8]) -> String? { kid.key.flatMap { JSONCursor.string(in: bytes, $0) } }

    /// Chỉ đổi `type` và `filter` của thẻ có sẵn; mọi khoá khác (`name`, `field`, `howCreated`, `isLockedInViewMode`…) giữ nguyên.
    private static func modifyCard(at index: Int, with card: FilterCardSpec, in bytes: inout [UInt8]) throws {
        let base: [JSONPathStep] = filtersPath() + [.index(index)]
        func children() throws -> [JSONCursor.Child] {
            guard let kids = JSONCursor.children(at: base, in: bytes) else { throw WriteError.invalid("filter card is not an object") }
            return kids
        }
        var kids = try children()
        if let t = kids.first(where: { keyName($0, bytes) == "type" }) {
            bytes.replaceSubrange(t.value, with: Array(token(card.type).utf8))
            kids = try children()
        }
        let existing = kids.first(where: { keyName($0, bytes) == "filter" })
        switch (card.filter, existing) {
        case (let filter?, let k?):
            bytes.replaceSubrange(k.value, with: Array(filter.utf8))
        case (let filter?, nil):
            if let how = kids.first(where: { keyName($0, bytes) == "howCreated" }) {
                bytes.insert(contentsOf: Array("\"filter\":\(filter),".utf8), at: how.start)
            } else if let last = kids.last {
                bytes.insert(contentsOf: Array(",\"filter\":\(filter)".utf8), at: last.value.upperBound)
            }
        case (nil, let k?):
            if let at = kids.firstIndex(where: { $0.start == k.start }) { bytes = JSONCursor.removing([at], from: kids, in: bytes) }
        case (nil, nil):
            break
        }
    }

    private static func appendCard(_ text: [UInt8], level: Level, in bytes: inout [UInt8], hadFilters: Bool) throws {
        if let array = JSONCursor.locate(filtersPath()[...], in: bytes), bytes[array.lowerBound] == UInt8(ascii: "["),
           let kids = JSONCursor.children(at: filtersPath(), in: bytes) {
            if let last = kids.last { bytes.insert(contentsOf: [UInt8(ascii: ",")] + text, at: last.value.upperBound) }
            else { bytes.insert(contentsOf: text, at: array.lowerBound + 1) }
            return
        }
        // `filterConfig` có nhưng chưa có `filters`: thêm `filters` vào cuối `filterConfig`.
        if let config = JSONCursor.locate([.key("filterConfig")][...], in: bytes), bytes[config.lowerBound] == UInt8(ascii: "{") {
            let kids = JSONCursor.children(at: [.key("filterConfig")], in: bytes) ?? []
            let piece = Array("\"filters\":[".utf8) + text + [UInt8(ascii: "]")]
            if let last = kids.last { bytes.insert(contentsOf: [UInt8(ascii: ",")] + piece, at: last.value.upperBound) }
            else { bytes.insert(contentsOf: piece, at: config.lowerBound + 1) }
            return
        }
        // Chưa có `filterConfig`: chèn sau khoá neo theo cấp.
        let rootKids = JSONCursor.children(at: [], in: bytes) ?? []
        let entry = Array("\"filterConfig\":{\"filters\":[".utf8) + text + Array("]}".utf8)
        for anchor in anchors(for: level) {
            if let kid = rootKids.first(where: { $0.key.flatMap { JSONCursor.string(in: bytes, $0) } == anchor }) {
                bytes.insert(contentsOf: [UInt8(ascii: ",")] + entry, at: kid.value.upperBound)
                return
            }
        }
        if let last = rootKids.last { bytes.insert(contentsOf: [UInt8(ascii: ",")] + entry, at: last.value.upperBound) }
        else if let open = bytes.firstIndex(of: UInt8(ascii: "{")) { bytes.insert(contentsOf: entry, at: open + 1) }
        else { throw WriteError.invalid("part is not a JSON object") }
    }

    private static func removeCard(at index: Int, in bytes: inout [UInt8]) throws {
        guard let kids = JSONCursor.children(at: filtersPath(), in: bytes) else { throw WriteError.invalid("filterConfig.filters missing") }
        if kids.count > 1 {
            bytes = JSONCursor.removing([index], from: kids, in: bytes)
            return
        }
        // Thẻ cuối cùng: bỏ cả `filterConfig` nếu nó chỉ có `filters` (VM-D6: `page.json` về đúng byte cũ), ngược lại để `filters:[]`.
        let configKids = JSONCursor.children(at: [.key("filterConfig")], in: bytes) ?? []
        if configKids.count == 1 {
            let rootKids = JSONCursor.children(at: [], in: bytes) ?? []
            if let at = rootKids.firstIndex(where: { $0.key.flatMap { JSONCursor.string(in: bytes, $0) } == "filterConfig" }) {
                bytes = JSONCursor.removing([at], from: rootKids, in: bytes)
                return
            }
        }
        bytes = JSONCursor.removing([index], from: kids, in: bytes)
    }

    private static func parseObject(_ data: Data) throws -> [String: Any] {
        guard let value = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw WriteError.invalid("card is not an object") }
        return value
    }

    private static func parseFragment(_ text: String) throws -> Any {
        guard let value = try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed]) else { throw WriteError.invalid("filter is not JSON") }
        return value
    }
}
