import Foundation

/// Phase E (T033): sửa phần `DiagramLayout` (JSON UTF-16LE của Model view) bằng cách ghép số vào văn bản đã có, giữ nguyên mọi
/// khoá khác (`scrollPosition`, cờ, thứ tự khoá) và mã hoá (BOM nếu có). Không sửa gì thì trả đúng byte vào.
public enum DiagramLayoutPatch {
    /// Đặt thẻ bảng `table` của tab `diagram` ở (x, y) (toạ độ sơ đồ, đơn vị như Desktop).
    public struct Move: Sendable, Hashable {
        public var diagram: String
        public var table: String
        public var x: Double
        public var y: Double

        public init(diagram: String, table: String, x: Double, y: Double) {
            self.diagram = diagram
            self.table = table
            self.x = x
            self.y = y
        }
    }

    /// Một tab trong danh sách mong muốn: `source` là chỉ số tab trong file gốc (nil = tab mới: nút rỗng, thu phóng 100, như Desktop ghi).
    public struct Tab: Sendable, Hashable {
        public var name: String
        public var source: Int?

        public init(name: String, source: Int?) {
            self.name = name
            self.source = source
        }
    }

    /// Gỡ nút của bảng `table` khỏi tab `diagram` (tên tab sau khi đổi): bảng vẫn ở trong mô hình.
    public struct Removal: Sendable, Hashable {
        public var diagram: String
        public var table: String

        public init(diagram: String, table: String) {
            self.diagram = diagram
            self.table = table
        }
    }

    /// `tabs`: danh sách tab mong muốn theo thứ tự (nil = giữ nguyên). Tab có `source` lấy nội dung từ tab đó của file (đổi tên nếu
    /// khác); tab của file không có mặt thì bị xoá; `ordinal` được đánh lại theo thứ tự mới như Desktop. `selected`: tab đang xem, ghi
    /// vào `selectedDiagram` khi đổi cấu trúc tab. `moves`/`zoom`/`removals` dùng tên tab sau khi đổi. `zoom`: tên tab → phần trăm
    /// thu phóng. `lineageTag`: dùng khi thẻ chưa có nút trong tab (thêm nút mới cỡ mặc định).
    public static func applying(tabs: [Tab]? = nil, selected: String? = nil, removals: [Removal] = [], moves: [Move], zoom: [String: Double],
                                to data: Data, lineageTag: (String) -> String? = { _ in nil }) throws -> Data {
        guard tabs != nil || !moves.isEmpty || !zoom.isEmpty || !removals.isEmpty else { return data }
        let hasBOM = data.count >= 2 && data[data.startIndex] == 0xFF && data[data.startIndex + 1] == 0xFE
        guard var text = String(data: hasBOM ? data.dropFirst(2) : data, encoding: .utf16LittleEndian) else {
            throw WriteError.invalid("DiagramLayout không phải UTF-16LE")
        }
        if let tabs { text = try restructure(text, tabs: tabs, selected: selected) }
        if !removals.isEmpty { text = try remove(removals, from: text) }
        guard !moves.isEmpty || !zoom.isEmpty else {
            var out = hasBOM ? Data([0xFF, 0xFE]) : Data()
            out.append(text.data(using: .utf16LittleEndian)!)
            return out
        }
        // Mỗi tab bắt đầu bằng `{"ordinal":`; tên tab đứng sau mảng nút.
        let marker = #"{"ordinal":"#
        var starts: [String.Index] = []
        var cursor = text.startIndex
        while let found = text.range(of: marker, range: cursor..<text.endIndex) { starts.append(found.lowerBound); cursor = found.upperBound }
        guard !starts.isEmpty else { throw WriteError.invalid("DiagramLayout không có tab nào") }
        func name(of start: String.Index, end: String.Index) -> String? {
            guard let key = text.range(of: #""name":""#, range: start..<end) else { return nil }
            return stringLiteral(in: text, from: key.upperBound)?.value
        }
        // Xử lý từ tab cuối về đầu để chỉ số của các tab trước không đổi.
        let diagrams = Set(moves.map(\.diagram)).union(zoom.keys)
        var handled = Set<String>()
        for (i, start) in starts.enumerated().reversed() {
            let end = i + 1 < starts.count ? starts[i + 1] : text.endIndex
            guard let diagram = name(of: start, end: end), diagrams.contains(diagram) else { continue }
            handled.insert(diagram)
            var segment = String(text[start..<end])
            for move in moves where move.diagram == diagram {
                segment = try place(move, in: segment, lineageTag: lineageTag)
            }
            if let percent = zoom[diagram] {
                segment = try setZoom(percent, in: segment)
            }
            text.replaceSubrange(start..<end, with: segment)
        }
        if let missing = diagrams.subtracting(handled).first { throw WriteError.invalid("DiagramLayout không có tab \(missing)") }
        var out = hasBOM ? Data([0xFF, 0xFE]) : Data()
        out.append(text.data(using: .utf16LittleEndian)!)
        return out
    }

    private static func number(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15 ? String(Int64(value)) : "\(value)"
    }

    private static func place(_ move: Move, in segment: String, lineageTag: (String) -> String?) throws -> String {
        let node = #""nodeIndex":"\#(move.table)""#
        if let found = segment.range(of: node) {
            // `{"location":{"x":…,"y":…},"nodeIndex":"…"`: tìm `"location":{` ngay trước nút.
            guard let locationKey = segment.range(of: #""location":{"#, options: .backwards, range: segment.startIndex..<found.lowerBound),
                  let close = segment.range(of: "}", range: locationKey.upperBound..<found.lowerBound) else {
                throw WriteError.invalid("nút \(move.table) trong DiagramLayout có dạng lạ")
            }
            var out = segment
            out.replaceSubrange(locationKey.upperBound..<close.lowerBound, with: #""x":\#(number(move.x)),"y":\#(number(move.y))"#)
            return out
        }
        // Thẻ chưa có nút: thêm nút cỡ mặc định cuối mảng `nodes` của tab này.
        guard let nodesEnd = segment.range(of: #"],"name":""#) ?? segment.range(of: "]", options: .backwards) else {
            throw WriteError.invalid("DiagramLayout không có mảng nút")
        }
        let tag = lineageTag(move.table).map { #","nodeLineageTag":"\#($0)""# } ?? ""
        let entry = #"{"location":{"x":\#(number(move.x)),"y":\#(number(move.y))},"nodeIndex":"\#(move.table)"\#(tag),"size":{"height":300,"width":234},"zIndex":0}"#
        var out = segment
        let separator = segment[..<nodesEnd.lowerBound].hasSuffix("[") ? "" : ","
        out.insert(contentsOf: separator + entry, at: nodesEnd.lowerBound)
        return out
    }

    private static func setZoom(_ percent: Double, in segment: String) throws -> String {
        guard let key = segment.range(of: #""zoomValue":"#) else { throw WriteError.invalid("tab không có zoomValue") }
        let rest = segment[key.upperBound...]
        let length = rest.prefix { "0123456789.-eE+".contains($0) }.count
        guard length > 0 else { throw WriteError.invalid("zoomValue lạ") }
        var out = segment
        let end = segment.index(key.upperBound, offsetBy: length)
        out.replaceSubrange(key.upperBound..<end, with: number(percent))
        return out
    }

    // MARK: Tab (VM-E6)

    /// Chuỗi JSON bắt đầu ngay sau dấu nháy mở: trả giá trị đã giải mã và vị trí dấu nháy đóng.
    private static func stringLiteral(in text: String, from start: String.Index) -> (value: String, close: String.Index)? {
        var index = start
        var escaped = false
        while index < text.endIndex {
            let c = text[index]
            if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" {
                let raw = "\"" + text[start..<index] + "\""
                guard let data = raw.data(using: .utf8),
                      let value = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? String else { return nil }
                return (value, index)
            }
            index = text.index(after: index)
        }
        return nil
    }

    static func jsonString(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 { out += String(format: "\\u%04x", scalar.value) } else { out.unicodeScalars.append(scalar) }
            }
        }
        return out + "\""
    }

    /// Phạm vi chính xác của từng phần tử trong mảng `diagrams` (quét ngoặc nhọn, bỏ qua chuỗi).
    private static func diagramRanges(in text: String) throws -> [Range<String.Index>] {
        guard let key = text.range(of: #""diagrams":["#) else { throw WriteError.invalid("DiagramLayout không có mảng diagrams") }
        var ranges: [Range<String.Index>] = []
        var index = key.upperBound
        var depth = 0
        var begin: String.Index?
        var inString = false, escaped = false
        while index < text.endIndex {
            let c = text[index]
            if inString {
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
            } else {
                switch c {
                case "\"": inString = true
                case "{": if depth == 0 { begin = index }; depth += 1
                case "}":
                    depth -= 1
                    if depth == 0, let b = begin { ranges.append(b..<text.index(after: index)); begin = nil }
                case "]": if depth == 0 { return ranges }
                default: break
                }
            }
            index = text.index(after: index)
        }
        throw WriteError.invalid("DiagramLayout: mảng diagrams không đóng")
    }

    private static func restructure(_ text: String, tabs: [Tab], selected: String?) throws -> String {
        let ranges = try diagramRanges(in: text)
        guard let first = ranges.first, let last = ranges.last else { throw WriteError.invalid("DiagramLayout không có tab nào") }
        var names: [String] = []
        var segments: [String] = []
        for range in ranges {
            let segment = String(text[range])
            guard let key = segment.range(of: #""name":""#), let literal = stringLiteral(in: segment, from: key.upperBound) else {
                throw WriteError.invalid("tab trong DiagramLayout không có tên")
            }
            names.append(literal.value)
            segments.append(segment)
        }
        guard tabs.map(\.name) != names || tabs.enumerated().contains(where: { $0.element.source != $0.offset }) else { return text }
        var sources = Set<Int>()
        for tab in tabs {
            guard let source = tab.source else { continue }
            guard source >= 0, source < segments.count, sources.insert(source).inserted else {
                throw WriteError.invalid("tab \(tab.name) trỏ tới tab nguồn không hợp lệ")
            }
        }
        var renamed: [String: String] = [:]
        var rebuilt: [String] = []
        for (i, tab) in tabs.enumerated() {
            if let source = tab.source {
                var segment = segments[source]
                if names[source] != tab.name {
                    let key = segment.range(of: #""name":""#)!
                    let close = stringLiteral(in: segment, from: key.upperBound)!.close
                    segment.replaceSubrange(segment.index(before: key.upperBound)...close, with: jsonString(tab.name))
                    renamed[names[source]] = tab.name
                }
                rebuilt.append(try setOrdinal(i, in: segment))
            } else {
                rebuilt.append(#"{"ordinal":\#(i),"scrollPosition":{"x":0,"y":0},"nodes":[],"name":\#(jsonString(tab.name)),"zoomValue":100,"pinKeyFieldsToTop":false,"showExtraHeaderInfo":false,"hideKeyFieldsWhenCollapsed":false,"tablesLocked":false}"#)
            }
        }
        var out = String(text[..<first.lowerBound]) + rebuilt.joined(separator: ",")
        var tail = String(text[last.upperBound...])
        // Khoá gốc: tab đang xem (nếu được yêu cầu), theo tên mới của tab đã đổi tên, hoặc tab đầu khi tab đó đã bị xoá.
        let finalNames = tabs.map(\.name)
        func setRoot(_ key: String, _ newValue: (String) -> String?) {
            guard let k = tail.range(of: "\"\(key)\":\""), let literal = stringLiteral(in: tail, from: k.upperBound),
                  let replacement = newValue(literal.value) else { return }
            tail.replaceSubrange(tail.index(before: k.upperBound)...literal.close, with: jsonString(replacement))
        }
        setRoot("selectedDiagram") { current in
            if let selected, finalNames.contains(selected) { return selected }
            if let name = renamed[current] { return name }
            return finalNames.contains(current) ? nil : finalNames.first
        }
        setRoot("defaultDiagram") { current in renamed[current] ?? (finalNames.contains(current) ? nil : finalNames.first) }
        out += tail
        return out
    }

    /// Đặt lại `"ordinal":N` ở đầu tab.
    private static func setOrdinal(_ value: Int, in segment: String) throws -> String {
        let marker = #"{"ordinal":"#
        guard segment.hasPrefix(marker) else { throw WriteError.invalid("tab trong DiagramLayout không bắt đầu bằng ordinal") }
        let digits = segment.dropFirst(marker.count).prefix { $0.isNumber }
        guard !digits.isEmpty else { throw WriteError.invalid("ordinal lạ") }
        guard String(digits) != String(value) else { return segment }
        return marker + String(value) + segment.dropFirst(marker.count + digits.count)
    }

    /// Gỡ các nút (đối tượng trong mảng `nodes`) của bảng đã chỉ định khỏi tab tương ứng.
    private static func remove(_ removals: [Removal], from text: String) throws -> String {
        var text = text
        let ranges = try diagramRanges(in: text)
        for (offset, range) in ranges.enumerated().reversed() {
            var segment = String(text[range])
            guard let key = segment.range(of: #""name":""#), let name = stringLiteral(in: segment, from: key.upperBound)?.value else { continue }
            let tables = Set(removals.filter { $0.diagram == name }.map(\.table))
            guard !tables.isEmpty, let nodesKey = segment.range(of: #""nodes":["#) else { continue }
            _ = offset
            // Duyệt các đối tượng nút; xoá từ cuối về đầu để vị trí các nút trước không đổi.
            let elements = try objectRanges(in: segment, from: nodesKey.upperBound)
            for element in elements.reversed() {
                let body = segment[element]
                guard let tag = body.range(of: #""nodeIndex":""#), let value = stringLiteral(in: segment, from: tag.upperBound)?.value,
                      tables.contains(value) else { continue }
                var lower = element.lowerBound, upper = element.upperBound
                if upper < segment.endIndex, segment[upper] == "," { upper = segment.index(after: upper) }
                else if lower > segment.startIndex, segment[segment.index(before: lower)] == "," { lower = segment.index(before: lower) }
                segment.removeSubrange(lower..<upper)
            }
            text.replaceSubrange(range, with: segment)
        }
        return text
    }

    /// Các đối tượng `{…}` cấp 1 của một mảng JSON bắt đầu ngay sau `[` ở `start` (quét ngoặc, bỏ qua chuỗi).
    private static func objectRanges(in text: String, from start: String.Index) throws -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var index = start
        var depth = 0
        var begin: String.Index?
        var inString = false, escaped = false
        while index < text.endIndex {
            let c = text[index]
            if inString {
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
            } else {
                switch c {
                case "\"": inString = true
                case "{": if depth == 0 { begin = index }; depth += 1
                case "}":
                    depth -= 1
                    if depth == 0, let b = begin { ranges.append(b..<text.index(after: index)); begin = nil }
                case "]": if depth == 0 { return ranges }
                default: break
                }
            }
            index = text.index(after: index)
        }
        throw WriteError.invalid("DiagramLayout: mảng nút không đóng")
    }
}
