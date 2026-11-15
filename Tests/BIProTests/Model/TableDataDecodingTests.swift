// Phase F, T043: Table View đọc bảng nạp mới từ TableData như đọc bảng của file (DecodedColumn). Seam: `TableDataDecoding.decode`.
// Giá trị mong đợi là hằng viết tay, không tính lại bằng chính mã dưới test.
import ColumnStore
import PBIXKit
import Testing
@testable import BIPro

@Suite struct TableDataDecodingTests {
    private func data() throws -> TableData {
        try TableData(columns: [
            TableColumn(name: "I", data: ColumnBuilder.integers([7, nil, 7, -1])),
            TableColumn(name: "D", data: ColumnBuilder.doubles([1.5, 2.5, nil, 1.5])),
            TableColumn(name: "C", data: ColumnBuilder.currency([12_500, nil, 0, 10_000])),
            TableColumn(name: "T", data: ColumnBuilder.dateTimes([45_000, 45_001.5, nil, 45_000])),
            TableColumn(name: "B", data: ColumnBuilder.booleans([true, false, nil, true])),
            TableColumn(name: "S", data: ColumnBuilder.strings(["a", "", nil, "a"])),
        ])
    }

    @Test func moiOGiongGiaTriGoc() throws {
        let columns = TableDataDecoding.decode(try data(), names: ["I", "D", "C", "T", "B", "S"],
                                               types: [.int64, .double, .decimal, .dateTime, .boolean, .string])
        #expect(columns.map(\.name) == ["I", "D", "C", "T", "B", "S"])
        #expect(columns.allSatisfy { $0.count == 4 })
        #expect((0..<4).map { columns[0][$0] } == [.int(7), .null, .int(7), .int(-1)])
        #expect((0..<4).map { columns[1][$0] } == [.double(1.5), .double(2.5), .null, .double(1.5)])
        #expect((0..<4).map { columns[2][$0] } == [.decimal(1.25), .null, .decimal(0), .decimal(1)])
        #expect((0..<4).map { columns[3][$0] } == [.dateTime(45_000), .dateTime(45_001.5), .null, .dateTime(45_000)])
        #expect((0..<4).map { columns[4][$0] } == [.bool(true), .bool(false), .null, .bool(true)])
        #expect((0..<4).map { columns[5][$0] } == [.string("a"), .string(""), .null, .string("a")])
    }

    @Test func thuTuVaTenCotTheoMoHinh() throws {
        // Mô hình có thể đặt tên đã cắt khoảng trắng và thứ tự khác `TableData`.
        let table = try TableData(columns: [TableColumn(name: " A ", data: ColumnBuilder.integers([1])),
                                            TableColumn(name: "B", data: ColumnBuilder.integers([2]))])
        let columns = TableDataDecoding.decode(table, names: ["B", "A"], types: [.int64, .int64])
        #expect(columns.map(\.name) == ["B", "A"])
        #expect(columns[0][0] == .int(2) && columns[1][0] == .int(1))
    }

    @Test func cotThieuTrongDuLieuLaToanNull() throws {
        let table = try TableData(columns: [TableColumn(name: "A", data: ColumnBuilder.integers([1, 2]))])
        let columns = TableDataDecoding.decode(table, names: ["A", "Thieu"], types: [.int64, .string])
        #expect(columns[1].count == 2 && columns[1][0] == .null && columns[1][1] == .null)
    }

    @Test func cotDenseDocDuocTungDong() {
        let dense = ColumnData(type: .double, rowCount: 3, payload: .dense(.doubles([1, .nan, 3])))
        let table = try! TableData(columns: [TableColumn(name: "X", data: dense)])
        let columns = TableDataDecoding.decode(table, names: ["X"], types: [.double])
        #expect((0..<3).map { columns[0][$0] } == [.double(1), .null, .double(3)])
    }
}
