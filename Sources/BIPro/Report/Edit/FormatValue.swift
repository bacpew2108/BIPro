import Foundation
import PBIXKit

/// Đuôi của số trong literal Power BI: `D` (số thực) hoặc `L` (số nguyên), như `16D`, `1L` (QUAN-SAT mục 1).
enum NumberTail: String, Equatable { case d = "D", l = "L" }

/// Một lựa chọn cố định của ô chọn: nhãn Việt và literal ghi vào file (`'Bottom'`, `0D`).
struct FormatChoice: Equatable {
    let title: String
    let literal: String
}

/// Kiểu điều khiển và giá trị cho phép của một thuộc tính (`specs/006-d4-format-pane/data-model.md`).
enum FormatKind: Equatable {
    case bool
    case number(min: Double, max: Double, step: Double, tail: NumberTail)
    case choice([FormatChoice])
    case color
    case text(maxLength: Int, allowsEmpty: Bool)
}

enum FormatColor: Equatable {
    case theme(id: Int, percent: Double)
    case hex(String)
}

struct FormatError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// Giá trị định dạng đọc từ JSON hoặc người dùng nhập, trước khi ghi.
enum FormatValue: Equatable {
    case bool(Bool)
    case number(Double, tail: NumberTail)
    /// Literal thô của lựa chọn: `'center'`, `0D`.
    case choice(String)
    case color(FormatColor)
    case text(String)
    /// Kiểu giá trị chưa hỗ trợ (màu theo measure, biểu thức khác): chỉ-đọc.
    case unsupported(String)

    // MARK: Đọc

    /// Giá trị của một thuộc tính (`properties[tên]`), nil khi thuộc tính vắng mặt.
    static func read(_ raw: JSONValue?, kind: FormatKind) -> FormatValue? {
        guard let raw else { return nil }
        func unsupported(_ why: String) -> FormatValue { .unsupported(why) }
        if case .color = kind {
            guard let expr = raw["solid"]?["color"]?["expr"] else { return unsupported(biN("không phải màu cố định", "not a fixed color")) }
            if let theme = expr["ThemeDataColor"] {
                return .color(.theme(id: Int(theme["ColorId"]?.number ?? 0), percent: theme["Percent"]?.number ?? 0))
            }
            if let value = expr["Literal"]?["Value"]?.string, value.hasPrefix("'#"), value.hasSuffix("'") {
                return .color(.hex(String(value.dropFirst().dropLast())))
            }
            return unsupported(biN("màu theo công thức hoặc trường", "color by formula or field"))
        }
        guard let value = raw["expr"]?["Literal"]?["Value"]?.string else { return unsupported(biN("không phải giá trị cố định", "not a fixed value")) }
        switch kind {
        case .bool:
            guard value == "true" || value == "false" else { return unsupported(biN("không phải đúng/sai", "not true/false")) }
            return .bool(value == "true")
        case .number(_, _, _, let defaultTail):
            guard let last = value.last, let n = Double(value.dropLast()), let tail = NumberTail(rawValue: String(last)) else {
                if let n = Double(value) { return .number(n, tail: defaultTail) }
                return unsupported(biN("không phải số", "not a number"))
            }
            return .number(n, tail: tail)
        case .choice:
            return .choice(value)
        case .text:
            if case .string(let s) = ReportLiteral(literal: value) { return .text(s) }
            return unsupported(biN("không phải chữ", "not text"))
        case .color:
            return unsupported(biN("không phải màu", "not a color"))
        }
    }

    // MARK: Kiểm

    /// Lý do từ chối (tiếng Việt) hoặc nil khi hợp lệ.
    func validate(kind: FormatKind) -> String? {
        switch (self, kind) {
        case (.bool, .bool):
            return nil
        case (.number(let n, _), .number(let min, let max, _, _)):
            guard n.isFinite, n >= min, n <= max else { return biN("Nhập số từ \(Self.format(min)) đến \(Self.format(max)).", "Enter a number from \(Self.format(min)) to \(Self.format(max)).") }
            return nil
        case (.choice(let literal), .choice(let options)):
            return options.contains { $0.literal == literal } ? nil : biN("Giá trị này chưa quan sát ở Power BI Desktop nên chưa dùng được.", "This value hasn't been observed in Power BI Desktop, so it can't be used yet.")
        case (.color(let color), .color):
            switch color {
            case .hex(let text):
                return Self.normalisedHex(text) == nil ? biN("Màu cần dạng #RRGGBB (6 chữ số hex).", "A color must be in the form #RRGGBB (6 hex digits).") : nil
            case .theme(let id, let percent):
                guard (0...9).contains(id), percent >= -1, percent <= 1 else { return biN("Màu theme không hợp lệ.", "The theme color isn't valid.") }
                return nil
            }
        case (.text(let text), .text(let maxLength, let allowsEmpty)):
            if !allowsEmpty, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return biN("Không để trống. Muốn bỏ thì tắt công tắc.", "Can't be empty. To remove it, turn the toggle off.")
            }
            return text.count > maxLength ? biN("Tối đa \(maxLength) ký tự.", "Up to \(maxLength) characters.") : nil
        case (.unsupported, _):
            return biN("Kiểu giá trị này chưa sửa được.", "This value type can't be edited yet.")
        default:
            return biN("Giá trị không đúng kiểu của thuộc tính.", "The value isn't the right type for the property.")
        }
    }

    // MARK: Dựng JSON

    /// Chuỗi JSON của giá trị đúng cách Desktop ghi. `keepingTail`: đuôi của giá trị cũ (nếu có) thắng đuôi của kiểu.
    func json(kind: FormatKind, keepingTail: NumberTail? = nil) throws -> String {
        if let reason = validate(kind: kind) { throw FormatError(reason) }
        switch self {
        case .bool(let on):
            return Self.literalJSON(on ? "true" : "false")
        case .number(let n, let tail):
            return Self.literalJSON(Self.format(n) + (keepingTail ?? tail).rawValue)
        case .choice(let literal):
            return Self.literalJSON(literal)
        case .text(let text):
            return Self.literalJSON("'" + text.replacingOccurrences(of: "'", with: "''") + "'")
        case .color(.hex(let text)):
            let hex = "'" + (Self.normalisedHex(text) ?? text) + "'"
            return "{\"solid\":{\"color\":{\"expr\":{\"Literal\":{\"Value\":" + Self.stringToken(hex) + "}}}}}"
        case .color(.theme(let id, let percent)):
            return #"{"solid":{"color":{"expr":{"ThemeDataColor":{"ColorId":\#(id),"Percent":\#(Self.format(percent))}}}}}"#
        case .unsupported:
            throw FormatError(biN("Kiểu giá trị này chưa sửa được.", "This value type can't be edited yet."))
        }
    }

    // MARK: Trợ giúp

    /// `{"expr":{"Literal":{"Value":"<value>"}}}` với `value` được thoát đúng chuẩn JSON.
    static func literalJSON(_ value: String) -> String {
        "{\"expr\":{\"Literal\":{\"Value\":" + stringToken(value) + "}}}"
    }

    /// Chữ `value` thành một token chuỗi JSON (có nháy kép), giữ nguyên chữ Unicode, không thoát dấu `/`.
    static func stringToken(_ value: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = (try? encoder.encode(value)) ?? Data("\"\"".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    /// `#e4572e` hoặc `e4572e` → `#E4572E`; nil khi không đủ 6 chữ số hex.
    static func normalisedHex(_ text: String) -> String? {
        var s = text.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, s.allSatisfy({ $0.isHexDigit }) else { return nil }
        return "#" + s.uppercased()
    }

    /// Số nguyên in không có phần thập phân (`16`), còn lại in đủ (`2.5`).
    static func format(_ n: Double) -> String {
        n == n.rounded() && abs(n) < 1e15 ? String(Int(n)) : String(n)
    }
}

/// Một thuộc tính của một visual, dùng làm khoá gộp bước hoàn tác (`specs/006-d4-format-pane/research.md` R8).
struct FormatTarget: Hashable {
    let visualID: String
    let scope: FormatScope
    let object: String
    let property: String
    /// `queryRef` của chuỗi khi sửa định dạng theo chuỗi.
    var series: String? = nil

    var coalesceKey: String { "format:\(visualID):\(scope.rawValue).\(object).\(property)" + (series.map { "@" + $0 } ?? "") }
}
