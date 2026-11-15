// Phase F, T060: bảng đã có trong file (DecodedColumn) thành TableData cho Query Editor. Seam: `TableDataEncoding.tableData(from:)`.
// Đi vòng decode → encode rồi so từng ô với hằng viết tay.
import ColumnStore
import PBIXKit
import Testing
@testable import BIPro

@Suite struct TableDataEncodingTests {
    @Test func moiOGiuNguyenKhiDiVongTron() throws {
        let source = try TableData(columns: [
            TableColumn(name: "I", data: ColumnBuilder.integers([7, nil, -1])),
            TableColumn(name: "D", data: ColumnBuilder.doubles([1.5, nil, 2.25])),
            TableColumn(name: "C", data: ColumnBuilder.currency([12_500, nil, 10_000])),
            TableColumn(name: "T", data: ColumnBuilder.dateTimes([45_000, nil, 45_001.5])),
            TableColumn(name: "B", data: ColumnBuilder.booleans([true, nil, false])),
            TableColumn(name: "S", data: ColumnBuilder.strings(["a", nil, ""])),
        ])
        let decoded = TableDataDecoding.decode(source, names: ["I", "D", "C", "T", "B", "S"],
                                               types: [.int64, .double, .decimal, .dateTime, .boolean, .string])
        let back = try #require(TableDataEncoding.tableData(from: decoded))
        #expect(back.rowCount == 3)
        #expect(back.columns.map(\.name) == ["I", "D", "C", "T", "B", "S"])
        let rows = (0..<3).map { row in back.columns.map { $0.data.value(at: row) } }
        #expect(rows[0] == [.integer(7), .double(1.5), .currency(12_500), .dateTime(45_000), .boolean(true), .string("a")])
        #expect(rows[1] == [.blank, .blank, .blank, .blank, .blank, .blank])
        #expect(rows[2] == [.integer(-1), .double(2.25), .currency(10_000), .dateTime(45_001.5), .boolean(false), .string("")])
    }

    @Test func khongCotThiNil() {
        #expect(TableDataEncoding.tableData(from: []) == nil)
    }

    @Test func tenCotTrungThiNil() {
        let a = DecodedColumn(name: "A", dataType: .int64, storage: .values([1]))
        #expect(TableDataEncoding.tableData(from: [a, a]) == nil)
    }

    @Test func duongNhanhChoCotTheoGiaTriVaCotTrong() throws {
        let columns = [
            DecodedColumn(name: "D", dataType: .double, storage: .values([1.5, .nan, 2.5])),
            DecodedColumn(name: "T", dataType: .dateTime, storage: .values([45_000, 45_001, .nan])),
            DecodedColumn(name: "E", dataType: .string, storage: .empty(count: 3)),
            DecodedColumn(name: "S", dataType: .string, storage: .dictionary(codes: [1, -1, 0], dictionary: [.string("a"), .string("b")])),
        ]
        let table = try #require(TableDataEncoding.tableData(from: columns))
        let rows = (0..<3).map { row in table.columns.map { $0.data.value(at: row) } }
        #expect(rows[0] == [.double(1.5), .dateTime(45_000), .blank, .string("b")])
        #expect(rows[1] == [.blank, .dateTime(45_001), .blank, .blank])
        #expect(rows[2] == [.double(2.5), .blank, .blank, .string("a")])
    }

    @Test func tuDienHonHaiTramNamMuoiLamMuc() throws {
        let entries = (0..<300).map { CellValue.int(Int64($0 * 3)) }
        let codes = (0..<1000).map { Int32($0 % 300) }
        let table = try #require(TableDataEncoding.tableData(from: [DecodedColumn(name: "N", dataType: .int64, storage: .dictionary(codes: codes, dictionary: entries))]))
        #expect(table.rowCount == 1000)
        #expect(table.columns[0].data.value(at: 0) == .integer(0))
        #expect(table.columns[0].data.value(at: 299) == .integer(897))
        #expect(table.columns[0].data.value(at: 300) == .integer(0))
        #expect(table.columns[0].data.value(at: 999) == .integer(Int64((999 % 300) * 3)))
    }
}
