// Tiện ích test cho F-TIME (đợt 3). Các biến thể của MiniBank chỉ đổi cách mã hoá hoặc lược đồ; dữ liệu giữ nguyên.
// Đáp án của mọi test F-TIME tính bằng Python stdlib (scratchpad/ftime3/oracle_ftime.py), không dùng Swift để tính.
import Testing
import ColumnStore
import DAXTestSupport
@testable import DAXEngine

/// Biến thể MiniBank với `Dim_Date[full_date]` được mã hoá. Dữ liệu giống hệt MiniBank.
/// Cần vì FilterContext chưa lọc theo giá trị trên cột dense (xem FTimeMiniBankTests, mục known issue).
struct FTEncodedDateSource: ColumnSource {
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

/// Biến thể MiniBank với `Dim_Date` không được đánh dấu bảng ngày (dataCategory khác Time).
struct FTUnmarkedSource: ColumnSource {
    let base: InMemoryColumnSource

    var schema: ModelSchema {
        let s = base.schema
        let tables = s.tables.map { t -> ModelSchema.Table in
            guard t.id == MiniBank.Tables.dimDate else { return t }
            return ModelSchema.Table(id: t.id, name: t.name, isHidden: t.isHidden, isUserTable: t.isUserTable,
                                     isDateTable: false, columns: t.columns)
        }
        return ModelSchema(culture: s.culture, tables: tables, relationships: s.relationships)
    }

    func rowCount(_ table: TableID) throws -> Int {
        try base.rowCount(table)
    }

    func loadColumn(_ id: ColumnID) throws -> ColumnData {
        try base.loadColumn(id)
    }
}

/// Measure của MiniBank cộng thêm các measure time intelligence dùng trong test F-TIME.
enum FTMeasures {
    static let all: [ModelMeasureInput] = MiniBank.measures.map {
        ModelMeasureInput(table: $0.table, name: $0.name, expression: $0.expression)
    } + [
        // Cùng kỳ năm trước của ngữ cảnh. Bộ lọc năm còn lại nên giao với năm trước (thường BLANK khi lọc theo năm).
        ModelMeasureInput(table: "Fact_Trans", name: "Prev Year Amount",
                          expression: "CALCULATE ( [Trans Amount], SAMEPERIODLASTYEAR ( Dim_Date[full_date] ) )"),
        // Cùng kỳ năm trước, bỏ bộ lọc Dim_Date trước khi áp ngày (khuôn Nhom6).
        ModelMeasureInput(table: "Fact_Trans", name: "Prev Year Amount Bo Loc Nam",
                          expression: "CALCULATE ( [Trans Amount], REMOVEFILTERS ( Dim_Date ), SAMEPERIODLASTYEAR ( Dim_Date[full_date] ) )"),
        // Tháng trước của ngữ cảnh (DATEADD với khoảng MONTH).
        ModelMeasureInput(table: "Fact_Trans", name: "Prev Month Amount",
                          expression: "CALCULATE ( [Trans Amount], DATEADD ( Dim_Date[full_date], -1, MONTH ) )"),
        // Khuôn Δ của MiniBank với mốc cố định 25/12/2024 (thay MAX để không phụ thuộc F-AGG+TABLE).
        ModelMeasureInput(table: "Fact_Trans", name: "Delta Khuon",
                          expression: """
                          VAR endDt = DATE ( 2024, 12, 25 )
                          VAR curDates = FILTER ( VALUES ( Dim_Date[full_date] ), Dim_Date[full_date] >= DATE ( YEAR ( endDt ), 1, 1 ) && Dim_Date[full_date] <= endDt )
                          VAR cur = CALCULATE ( [Trans Amount], curDates, REMOVEFILTERS ( Dim_Date ) )
                          VAR prev = CALCULATE ( [Trans Amount], SAMEPERIODLASTYEAR ( curDates ), REMOVEFILTERS ( Dim_Date ) )
                          RETURN DIVIDE ( cur - prev, prev )
                          """),
        // Row context: với mỗi ngày của năm 2024, lấy giao dịch của cùng ngày năm trước (cần SUMX của F-AGG+TABLE).
        ModelMeasureInput(table: "Fact_Trans", name: "Prev Year Sumx",
                          expression: """
                          SUMX (
                              FILTER ( VALUES ( Dim_Date[full_date] ), Dim_Date[full_date] >= DATE ( 2024, 1, 1 ) && Dim_Date[full_date] <= DATE ( 2024, 12, 31 ) ),
                              CALCULATE ( SUM ( Fact_Trans[amount] ), DATEADD ( Dim_Date[full_date], -1, YEAR ) )
                          )
                          """),
    ]
}

/// Engine trên một nguồn cột, với đầy đủ measure của MiniBank và measure F-TIME.
func ftEngine(_ source: ColumnSource) -> DAXEngine {
    DAXEngine(store: ColumnStore(source: source),
              catalog: Catalog(schema: source.schema, measures: FTMeasures.all))
}

/// Bộ lọc năm của Dim_Date (cột mã hoá, đúng trong mọi biến thể).
func ftNam(_ year: Int64) -> FilterItem {
    FilterItem(column: MiniBank.Columns.DimDate.year, values: [.integer(year)])
}

/// Kiểm truy vấn phải ném DAXError với đúng `kind` và thông báo chứa `text`.
func ftExpectDAXError(_ engine: DAXEngine, _ query: String, kind: DAXError.Kind, contains text: String,
                      sourceLocation: SourceLocation = #_sourceLocation) async {
    do {
        _ = try await engine.execute(query)
        Issue.record("kỳ vọng lỗi \(kind) nhưng truy vấn chạy xong: \(query)", sourceLocation: sourceLocation)
    } catch {
        #expect(error.kind == kind, "loại lỗi: \(error.kind)", sourceLocation: sourceLocation)
        #expect(error.message.contains(text), "thông báo: \(error.message)", sourceLocation: sourceLocation)
    }
}
