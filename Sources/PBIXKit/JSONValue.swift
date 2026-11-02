import Foundation

/// Loosely typed JSON, used for report formatting objects whose schema is open-ended.
public enum JSONValue: Sendable, Hashable, Decodable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public static func parse(_ data: Data) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data)
    }

    public static func parse(_ text: String) throws -> JSONValue {
        try parse(Data(text.utf8))
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    public subscript(index: Int) -> JSONValue? {
        if case .array(let a) = self, a.indices.contains(index) { return a[index] }
        return nil
    }

    public var string: String? { if case .string(let s) = self { s } else { nil } }
    public var number: Double? { if case .number(let n) = self { n } else { nil } }
    public var bool: Bool? { if case .bool(let b) = self { b } else { nil } }
    public var array: [JSONValue] { if case .array(let a) = self { a } else { [] } }
    public var object: [String: JSONValue] { if case .object(let o) = self { o } else { [:] } }
}

/// A value from a report `expr`: `{"Literal": {"Value": "'text'"}}` and friends.
public enum ReportLiteral: Sendable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    /// `{"ThemeDataColor": {"ColorId": n, "Percent": p}}`
    case themeColor(id: Int, percent: Double)
    case resource(String)

    /// Parses Power BI literal syntax: `'text'`, `12D`, `3L`, `1.5M`, `true`, `null`, `datetime'...'`.
    public init(literal raw: String) {
        if raw.count >= 2, raw.hasPrefix("'"), raw.hasSuffix("'") {
            self = .string(String(raw.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'"))
        } else if raw == "true" || raw == "false" {
            self = .bool(raw == "true")
        } else if raw == "null" {
            self = .null
        } else if let last = raw.last, "DLMdlm".contains(last), let n = Double(raw.dropLast()) {
            self = .number(n)
        } else if let n = Double(raw) {
            self = .number(n)
        } else if raw.hasPrefix("datetime'") {
            self = .string(String(raw.dropFirst(9).dropLast()))
        } else {
            self = .string(raw)
        }
    }

    public init?(expression json: JSONValue?) {
        guard let json else { return nil }
        if let value = json["Literal"]?["Value"]?.string {
            self.init(literal: value)
        } else if let theme = json["ThemeDataColor"] {
            self = .themeColor(id: Int(theme["ColorId"]?.number ?? 0), percent: theme["Percent"]?.number ?? 0)
        } else if let item = json["ResourcePackageItem"]?["ItemName"]?.string {
            self = .resource(item)
        } else {
            return nil
        }
    }

    public var string: String? { if case .string(let s) = self { s } else { nil } }
    public var number: Double? { if case .number(let n) = self { n } else { nil } }
    public var bool: Bool? { if case .bool(let b) = self { b } else { nil } }
}

/// Formatting objects of a visual or page: `{"title": [{"properties": {...}, "selector": ...}]}`.
public struct ObjectProperties: Sendable, Hashable {
    public let json: JSONValue

    public init(_ json: JSONValue?) { self.json = json ?? .null }

    /// The first un-selected (or default-selector) instance of `object`, falling back to the first instance.
    private func properties(_ object: String) -> [String: JSONValue] {
        let instances = json[object]?.array ?? []
        let preferred = instances.first { $0["selector"] == nil || $0["selector"]?["id"]?.string == "default" }
        return (preferred ?? instances.first)?["properties"]?.object ?? [:]
    }

    /// All instances of `object` merged (later wins) — Power BI writes state variants as separate entries.
    private func mergedProperties(_ object: String) -> [String: JSONValue] {
        var merged: [String: JSONValue] = [:]
        for instance in json[object]?.array ?? [] {
            let selector = instance["selector"]
            // Skip hover/press states; keep default and unselected ones.
            if let id = selector?["id"]?.string, id != "default" { continue }
            for (k, v) in instance["properties"]?.object ?? [:] { merged[k] = v }
        }
        return merged
    }

    public func raw(_ object: String, _ property: String) -> JSONValue? {
        mergedProperties(object)[property] ?? properties(object)[property]
    }

    public func literal(_ object: String, _ property: String) -> ReportLiteral? {
        ReportLiteral(expression: raw(object, property)?["expr"])
    }

    /// A color property: `{"solid": {"color": {"expr": ...}}}`.
    public func color(_ object: String, _ property: String) -> ReportLiteral? {
        ReportLiteral(expression: raw(object, property)?["solid"]?["color"]?["expr"])
    }

    public func string(_ object: String, _ property: String) -> String? { literal(object, property)?.string }
    public func number(_ object: String, _ property: String) -> Double? { literal(object, property)?.number }
    public func bool(_ object: String, _ property: String) -> Bool? { literal(object, property)?.bool }
    public func has(_ object: String) -> Bool { json[object] != nil }
}
