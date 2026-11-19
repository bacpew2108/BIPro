// Phase F, T003: TableData (bảng trong bộ nhớ của Get Data / Power Query). Seam: hợp đồng data-model.md.
import Testing
@testable import ColumnStore

@Suite struct TableDataTests {
    private func sample() throws -> TableData {
        try TableData(columns: [
            TableColumn(name: "Id", data: ColumnBuilder.integers([1, 2, nil, 4])),
            TableColumn(name: "Name", data: ColumnBuilder.strings(["a", "", nil, "a"])),
        ])
    }

    @Test func buildsAndReadsCells() throws {
        let table = try sample()
        #expect(table.rowCount == 4)
        #expect(table.columns.map(\.name) == ["Id", "Name"])
        #expect(table.value(row: 0, column: 0) == .integer(1))
        #expect(table.value(row: 2, column: 0) == .blank)
        #expect(table.value(row: 1, column: 1) == .string(""))   // "" khác BLANK
        #expect(table.value(row: 2, column: 1) == .blank)
        #expect(table.index(ofColumn: "Name") == 1)
        #expect(table.index(ofColumn: "name") == nil)           // M phân biệt hoa thường
    }

    /// Đợt tồn đọng sau Phase F (T005, contracts/sources.md): kiểu M gốc của nguồn, mặc định không có; xem trước (`prefix`) giữ lại.
    @Test func sourceTypeDefaultsToNilAndSurvivesPrefix() throws {
        #expect(try sample().columns.allSatisfy { $0.sourceType == nil })
        let table = try TableData(columns: [
            TableColumn(name: "At", data: ColumnBuilder.dateTimes([1.5, nil]), sourceType: .dateTimeZone),
            TableColumn(name: "Raw", data: ColumnBuilder.strings(["", nil]), sourceType: .binary),
        ])
        #expect(table.prefix(1).columns.map(\.sourceType) == [.dateTimeZone, .binary])
        #expect(Set(MSourceType.allCases.map(\.rawValue)) == ["time", "duration", "dateTimeZone", "binary", "list", "record", "dateTime"])
    }

    @Test func rejectsRowCountMismatch() {
        #expect(throws: TableDataError.rowCountMismatch(column: "B", expected: 2, actual: 3)) {
            try TableData(columns: [
                TableColumn(name: "A", data: ColumnBuilder.integers([1, 2])),
                TableColumn(name: "B", data: ColumnBuilder.integers([1, 2, 3])),
            ])
        }
    }

    @Test func rejectsDuplicateAndEmptyNames() {
        #expect(throws: TableDataError.duplicateColumn("A")) {
            try TableData(columns: [
                TableColumn(name: "A", data: ColumnBuilder.integers([1])),
                TableColumn(name: "A", data: ColumnBuilder.integers([2])),
            ])
        }
        #expect(throws: TableDataError.emptyColumnName) {
            try TableData(columns: [TableColumn(name: "", data: ColumnBuilder.integers([1]))])
        }
    }

    @Test func errorMaskMustPointInsideTable() throws {
        let column = TableColumn(name: "A", data: ColumnBuilder.integers([1, 2]))
        let ok = try TableData(columns: [column], errorMask: [0: [1: "không đổi được kiểu"]])
        #expect(ok.error(row: 1, column: 0) == "không đổi được kiểu")
        #expect(ok.error(row: 0, column: 0) == nil)
        #expect(throws: TableDataError.errorOutOfRange(column: 0, row: 5)) {
            try TableData(columns: [column], errorMask: [0: [5: "x"]])
        }
        #expect(throws: TableDataError.errorOutOfRange(column: 3, row: 0)) {
            try TableData(columns: [column], errorMask: [3: [0: "x"]])
        }
    }

    @Test func prefixKeepsFirstRowsAndTypes() throws {
        let table = try TableData(columns: [
            TableColumn(name: "D", data: ColumnBuilder.dateTimes([45000, nil, 45002])),
            TableColumn(name: "B", data: ColumnBuilder.booleans([true, false, nil])),
            TableColumn(name: "C", data: ColumnBuilder.currency([100, nil, 300])),
            TableColumn(name: "F", data: ColumnBuilder.doubles([1.5, 2.5, nil])),
        ], errorMask: [0: [2: "lỗi"]])
        let head = table.prefix(2)
        #expect(head.rowCount == 2)
        #expect(head.columns.map(\.data.type) == [.dateTime, .boolean, .currency, .double])
        #expect(head.value(row: 0, column: 0) == .dateTime(45000))
        #expect(head.value(row: 1, column: 0) == .blank)
        #expect(head.value(row: 0, column: 1) == .boolean(true))
        #expect(head.value(row: 0, column: 2) == .currency(100))
        #expect(head.value(row: 1, column: 3) == .double(2.5))
        #expect(head.error(row: 2, column: 0) == nil)           // lỗi ngoài phạm vi bị bỏ
        #expect(table.prefix(99).rowCount == 3)
        #expect(table.prefix(0).rowCount == 0)
    }

    @Test func emptyTableHasZeroRows() throws {
        let table = try TableData(columns: [])
        #expect(table.rowCount == 0 && table.columns.isEmpty)
    }
}
