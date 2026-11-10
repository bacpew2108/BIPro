import Foundation
import PBIXKit
import Testing
@testable import BIPro

/// Giá trị định dạng (D4): đọc, kiểm, dựng JSON như Desktop ghi (`specs/006-d4-format-pane/research.md` R5, QUAN-SAT mục 1).
@Suite struct FormatValueTests {
    static func json(_ text: String) -> JSONValue { try! JSONValue.parse(text) }
    static func lit(_ value: String) -> JSONValue { json(#"{"expr":{"Literal":{"Value":"\#(value)"}}}"#) }

    // MARK: (a) đọc

    @Test func readsEachKindFromTheJSON() {
        #expect(FormatValue.read(Self.lit("true"), kind: .bool) == .bool(true))
        #expect(FormatValue.read(Self.lit("false"), kind: .bool) == .bool(false))
        #expect(FormatValue.read(Self.lit("16D"), kind: .number(min: 1, max: 50, step: 1, tail: .d)) == .number(16, tail: .d))
        #expect(FormatValue.read(Self.lit("1L"), kind: .number(min: 0, max: 10, step: 1, tail: .l)) == .number(1, tail: .l))
        #expect(FormatValue.read(Self.lit("'center'"), kind: .choice([FormatChoice(title: "Giữa", literal: "'center'")])) == .choice("'center'"))
        #expect(FormatValue.read(Self.lit("0D"), kind: .choice([FormatChoice(title: "Tự động", literal: "0D")])) == .choice("0D"))
        #expect(FormatValue.read(Self.lit("'It''s a test'"), kind: .text(maxLength: 200, allowsEmpty: false)) == .text("It's a test"))
        #expect(FormatValue.read(Self.json(#"{"solid":{"color":{"expr":{"Literal":{"Value":"'#E4572E'"}}}}}"#), kind: .color) == .color(.hex("#E4572E")))
        #expect(FormatValue.read(Self.json(#"{"solid":{"color":{"expr":{"ThemeDataColor":{"ColorId":2,"Percent":0.2}}}}}"#), kind: .color) == .color(.theme(id: 2, percent: 0.2)))
    }

    @Test func absentValuesAreNilAndOddShapesAreUnsupported() {
        #expect(FormatValue.read(nil, kind: .bool) == nil)
        // Màu theo measure (fx) và giá trị lạ: chỉ-đọc.
        let measureColor = Self.json(#"{"solid":{"color":{"expr":{"Measure":{"Expression":{"SourceRef":{"Entity":"T"}},"Property":"M"}}}}}"#)
        if case .unsupported? = FormatValue.read(measureColor, kind: .color) {} else { Issue.record("expected unsupported for a measure color") }
        if case .unsupported? = FormatValue.read(Self.lit("'abc'"), kind: .bool) {} else { Issue.record("a string is not a bool") }
        if case .unsupported? = FormatValue.read(Self.lit("'abc'"), kind: .number(min: 0, max: 1, step: 1, tail: .d)) {} else { Issue.record("a string is not a number") }
    }

    // MARK: (b) dựng JSON giá trị

    @Test func buildsTheJSONDesktopWrites() throws {
        #expect(try FormatValue.bool(true).json(kind: .bool) == #"{"expr":{"Literal":{"Value":"true"}}}"#)
        #expect(try FormatValue.number(16, tail: .d).json(kind: .number(min: 1, max: 50, step: 1, tail: .d)) == #"{"expr":{"Literal":{"Value":"16D"}}}"#)
        #expect(try FormatValue.number(2.5, tail: .d).json(kind: .number(min: 0, max: 100, step: 0.5, tail: .d)) == #"{"expr":{"Literal":{"Value":"2.5D"}}}"#)
        #expect(try FormatValue.number(1, tail: .l).json(kind: .number(min: 0, max: 10, step: 1, tail: .l)) == #"{"expr":{"Literal":{"Value":"1L"}}}"#)
        // Giữ đuôi của giá trị cũ (Nhom6 ghi `labelPrecision` đuôi D).
        #expect(try FormatValue.number(2, tail: .l).json(kind: .number(min: 0, max: 10, step: 1, tail: .l), keepingTail: .d) == #"{"expr":{"Literal":{"Value":"2D"}}}"#)
        #expect(try FormatValue.text("It's a test").json(kind: .text(maxLength: 200, allowsEmpty: false)) == #"{"expr":{"Literal":{"Value":"'It''s a test'"}}}"#)
        #expect(try FormatValue.text("Doanh thu ‘lạ’ / ñ").json(kind: .text(maxLength: 200, allowsEmpty: false)) == #"{"expr":{"Literal":{"Value":"'Doanh thu ‘lạ’ / ñ'"}}}"#)
        #expect(try FormatValue.color(.hex("#e4572e")).json(kind: .color) == #"{"solid":{"color":{"expr":{"Literal":{"Value":"'#E4572E'"}}}}}"#)
        #expect(try FormatValue.color(.theme(id: 2, percent: 0.2)).json(kind: .color) == #"{"solid":{"color":{"expr":{"ThemeDataColor":{"ColorId":2,"Percent":0.2}}}}}"#)
        #expect(try FormatValue.color(.theme(id: 0, percent: 0)).json(kind: .color) == #"{"solid":{"color":{"expr":{"ThemeDataColor":{"ColorId":0,"Percent":0}}}}}"#)
        let choice = FormatKind.choice([FormatChoice(title: "Dưới", literal: "'Bottom'")])
        #expect(try FormatValue.choice("'Bottom'").json(kind: choice) == #"{"expr":{"Literal":{"Value":"'Bottom'"}}}"#)
    }

    @Test func quotesAndBackslashesAreEscapedInJSON() throws {
        let built = try FormatValue.text("a\"b\\c").json(kind: .text(maxLength: 200, allowsEmpty: false))
        let parsed = try JSONValue.parse(built)
        #expect(parsed["expr"]?["Literal"]?["Value"]?.string == "'a\"b\\c'")
    }

    // MARK: (c) kiểm

    @Test func validatesNumbers() {
        let kind = FormatKind.number(min: 1, max: 50, step: 1, tail: .d)
        #expect(FormatValue.number(16, tail: .d).validate(kind: kind) == nil)
        #expect(FormatValue.number(0, tail: .d).validate(kind: kind) != nil)
        #expect(FormatValue.number(51, tail: .d).validate(kind: kind) != nil)
        #expect(FormatValue.number(.nan, tail: .d).validate(kind: kind) != nil)
        #expect(FormatValue.number(.infinity, tail: .d).validate(kind: kind) != nil)
        #expect(FormatValue.number(16, tail: .d).validate(kind: kind) == nil)
        #expect(FormatValue.number(1, tail: .d).validate(kind: .number(min: 0, max: 100, step: 1, tail: .d)) == nil)
    }

    @Test func validatesTextColorsAndChoices() {
        let title = FormatKind.text(maxLength: 200, allowsEmpty: false)
        #expect(FormatValue.text("Tiêu đề").validate(kind: title) == nil)
        #expect(FormatValue.text("").validate(kind: title) != nil)
        #expect(FormatValue.text("   ").validate(kind: title) != nil)
        #expect(FormatValue.text(String(repeating: "a", count: 201)).validate(kind: title) != nil)
        #expect(FormatValue.text("").validate(kind: .text(maxLength: 10, allowsEmpty: true)) == nil)
        #expect(FormatValue.color(.hex("#E4572E")).validate(kind: .color) == nil)
        #expect(FormatValue.color(.hex("E4572E")).validate(kind: .color) == nil)   // thiếu # thì chuẩn hoá được
        #expect(FormatValue.color(.hex("#E4572")).validate(kind: .color) != nil)
        #expect(FormatValue.color(.hex("#GGGGGG")).validate(kind: .color) != nil)
        #expect(FormatValue.color(.theme(id: 12, percent: 0)).validate(kind: .color) != nil)
        #expect(FormatValue.color(.theme(id: 3, percent: 2)).validate(kind: .color) != nil)
        let choice = FormatKind.choice([FormatChoice(title: "Dưới", literal: "'Bottom'"), FormatChoice(title: "Trên", literal: "'Top'")])
        #expect(FormatValue.choice("'Top'").validate(kind: choice) == nil)
        #expect(FormatValue.choice("'Left'").validate(kind: choice) != nil)
    }

    @Test func normalisesHexToUpperCaseWithHash() throws {
        #expect(try FormatValue.color(.hex("e4572e")).json(kind: .color) == #"{"solid":{"color":{"expr":{"Literal":{"Value":"'#E4572E'"}}}}}"#)
    }

    // MARK: (d) khoá gộp

    @Test func coalesceKeyNamesVisualScopeObjectAndProperty() {
        let target = FormatTarget(visualID: "v1", scope: .container, object: "title", property: "fontSize")
        #expect(target.coalesceKey == "format:v1:container.title.fontSize")
        #expect(FormatTarget(visualID: "v1", scope: .objects, object: "labels", property: "fontSize").coalesceKey == "format:v1:objects.labels.fontSize")
    }
}
