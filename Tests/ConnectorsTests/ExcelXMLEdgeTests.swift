import Testing
import Foundation
@testable import Connectors

/// T105 (`/speckit-converge`, lỗi review T096): ô không có thuộc tính `r` bị bỏ; chữ phiên âm `rPh` lẫn vào shared string; inline string
/// mất khoảng trắng đầu/cuối và chỉ giữ đoạn chữ cuối. XML viết tay theo ECMA-376 (SpreadsheetML).
@Suite struct ExcelXMLEdgeTests {
    private func parse<D: XMLParserDelegate>(_ xml: String, _ delegate: D) -> D {
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = delegate
        _ = parser.parse()
        return delegate
    }

    private func text(_ cell: ExcelCell?) -> String? {
        if case .string(let s)? = cell?.value { return s }
        return nil
    }

    @Test func sharedStringIgnoresPhoneticRuns() {
        let xml = #"<sst><si><t>東京</t><rPh sb="0" eb="2"><t>トウキョウ</t></rPh><phoneticPr fontId="1"/></si><si><r><t xml:space="preserve">Hà </t></r><r><t>Nội</t></r></si></sst>"#
        #expect(parse(xml, SharedStringsParser()).strings == ["東京", "Hà Nội"])
    }

    @Test func cellsWithoutReferenceFollowPreviousCell() {
        let xml = """
            <worksheet><sheetData>
            <row r="1"><c t="inlineStr"><is><t>a</t></is></c><c><v>2</v></c><c r="E1"><v>5</v></c><c><v>6</v></c></row>
            <row><c><v>7</v></c></row>
            </sheetData></worksheet>
            """
        let cells = parse(xml, SheetParser(sharedStrings: [], isDateStyle: [:], date1904: false)).cells
        let positions = cells.map { "\($0.row),\($0.col)" }
        #expect(positions == ["0,0", "0,1", "0,4", "0,5", "1,0"])
    }

    @Test func inlineStringKeepsSpacesAndAllRuns() {
        let xml = #"<worksheet><sheetData><row r="1"><c r="A1" t="inlineStr"><is><r><t xml:space="preserve">  Hà </t></r><r><t>Nội  </t></r></is></c><c r="B1" t="str"><v> x </v></c></row></sheetData></worksheet>"#
        let cells = parse(xml, SheetParser(sharedStrings: [], isDateStyle: [:], date1904: false)).cells
        #expect(text(cells.first) == "  Hà Nội  ")
        #expect(text(cells.last) == " x ")
    }
}
