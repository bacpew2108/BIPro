// Tiện ích test cho lọc theo giá trị trên cột dense (FC, đợt 3).
// Hai thứ: biến thể MiniBank với Dim_Date[full_date] mã hoá (cùng dữ liệu, để so kết quả dense và mã hoá),
// và một model nhỏ có cột dense (double có NaN, integer có BLANK) để kiểm ngữ nghĩa BLANK và khoá chiếu.
import ColumnStore
import DAXEngine
import DAXTestSupport

/// MiniBank với `Dim_Date[full_date]` được mã hoá. Dữ liệu giống hệt MiniBank gốc (cột dense).
struct FCEncodedDateSource: ColumnSource {
    let base: InMemoryColumnSource

    var schema: ModelSchema { base.schema }

    func rowCount(_ table: TableID) throws -> Int {
        try base.rowCount(table)
    }

    func loadColumn(_ id: ColumnID) throws -> ColumnData {
        let data = try base.loadColumn(id)
        guard id == MiniBank.Columns.DimDate.fullDate else { return data }
        let values: [Double?] = (0..<data.rowCount).map { row in
            if case .dateTime(let d) = data.value(at: row) { return d }
            return nil
        }
        return ColumnBuilder.dateTimes(values)
    }
}

/// Model nhỏ: bảng D (k mã hoá duy nhất, g chuỗi trùng, x dense double có NaN) và bảng F (fk mã hoá, v dense
/// integer có BLANK). Quan hệ F.fk → D.k hoạt động, một chiều.
///
/// Dữ liệu (F có 5 dòng, D có 4 dòng):
/// - D: k = [1, 2, 3, 4], g = [a, b, a, b], x = [2.0, 5.0, 2.0, NaN].
/// - F: fk = [1, 2, 3, 9, 4], v = [10, 20, 30, BLANK, 50]. Dòng F 3 có fk 9 không khớp, nên vào blank row ảo của D.
enum FCDenseModel {
    static let tDim = TableID(raw: 1)
    static let tFact = TableID(raw: 2)
    static let colK = ColumnID(table: tDim, index: 1)
    static let colG = ColumnID(table: tDim, index: 2)
    static let colX = ColumnID(table: tDim, index: 3)
    static let colFk = ColumnID(table: tFact, index: 1)
    static let colV = ColumnID(table: tFact, index: 2)

    static let schema = ModelSchema(
        culture: "en-US",
        tables: [
            ModelSchema.Table(id: tDim, name: "D", isHidden: false, isUserTable: true, isDateTable: false, columns: [
                column(colK, "k", .integer, isKey: true),
                column(colG, "g", .string),
                column(colX, "x", .double),
            ]),
            ModelSchema.Table(id: tFact, name: "F", isHidden: false, isUserTable: true, isDateTable: false, columns: [
                column(colFk, "fk", .integer),
                column(colV, "v", .integer),
            ]),
        ],
        relationships: [
            RelationshipSchema(id: RelationshipID(raw: 0), name: "F_D", manyColumn: colFk, oneColumn: colK,
                               isActive: true, crossFilter: .oneDirection),
        ])

    static func makeStore() -> ColumnStore {
        let d = ColumnData(type: .double, rowCount: 4, payload: .dense(.doubles([2.0, 5.0, 2.0, .nan])))
        // v: dense integer, dòng 3 là BLANK (đánh dấu trong blanks).
        let v = ColumnData(type: .integer, rowCount: 5,
                           payload: .dense(.integers([10, 20, 30, 0, 50],
                                                     blanks: RowSet(universe: 6, sortedRows: [3]))))
        let source = InMemoryColumnSource(
            schema: schema,
            rowCounts: [tDim: 4, tFact: 5],
            columns: [
                colK: ColumnBuilder.integers([1, 2, 3, 4]),
                colG: ColumnBuilder.strings(["a", "b", "a", "b"]),
                colX: d,
                colFk: ColumnBuilder.integers([1, 2, 3, 9, 4]),
                colV: v,
            ])
        return ColumnStore(source: source)
    }

    private static func column(_ id: ColumnID, _ name: String, _ type: DAXType,
                               isKey: Bool = false) -> ModelSchema.Column {
        ModelSchema.Column(id: id, name: name, type: type, isCalculated: false, isHidden: false,
                           isKey: isKey, sortByColumn: nil, formatString: nil)
    }
}
