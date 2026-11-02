// Kiểm tra biên của lan truyền (REL, đợt 1b) trên lược đồ tổng hợp nhỏ: đường mơ hồ, USERELATIONSHIP
// giải mơ hồ, cột FK dense, và đường sắp xếp khi bên một lớn. Đáp án tính tay trong từng test.
import Foundation
import Testing
@testable import ColumnStore
@testable import DAXTestSupport

@Suite struct RELPropagationEdgeTests {

    // Lược đồ tổng hợp: bảng A (khoá một) và bảng B (hai FK cùng trỏ tới A).
    static let tA = TableID(raw: 1)
    static let tB = TableID(raw: 2)
    static let aKey = ColumnID(table: tA, index: 1)
    static let bK1 = ColumnID(table: tB, index: 11)
    static let bK2 = ColumnID(table: tB, index: 12)

    private static func column(_ id: ColumnID, _ name: String, _ type: DAXType, key: Bool = false) -> ModelSchema.Column {
        ModelSchema.Column(id: id, name: name, type: type, isCalculated: false, isHidden: false,
                           isKey: key, sortByColumn: nil, formatString: nil)
    }

    private static func schema(_ relationships: [RelationshipSchema]) -> ModelSchema {
        ModelSchema(culture: "en-US", tables: [
            ModelSchema.Table(id: tA, name: "A", isHidden: false, isUserTable: true, isDateTable: false,
                              columns: [column(aKey, "key", .integer, key: true)]),
            ModelSchema.Table(id: tB, name: "B", isHidden: false, isUserTable: true, isDateTable: false,
                              columns: [column(bK1, "k1", .integer), column(bK2, "k2", .integer)]),
        ], relationships: relationships)
    }

    private static func rel(_ raw: Int, _ name: String, many: ColumnID, active: Bool) -> RelationshipSchema {
        RelationshipSchema(id: RelationshipID(raw: raw), name: name, manyColumn: many, oneColumn: aKey,
                           isActive: active, crossFilter: .oneDirection)
    }

    /// Hai quan hệ cùng nối B tới A, đều hoạt động. Đây là đường mơ hồ.
    private static func ambiguousStore() -> ColumnStore {
        let s = schema([rel(0, "r0", many: bK1, active: true), rel(1, "r1", many: bK2, active: true)])
        let source = InMemoryColumnSource(
            schema: s, rowCounts: [tA: 3, tB: 4],
            columns: [aKey: ColumnBuilder.integers([1, 2, 3]),
                      bK1: ColumnBuilder.integers([1, 2, 3, 1]),
                      bK2: ColumnBuilder.integers([1, 1, 2, 3])])
        return ColumnStore(source: source)
    }

    private func key(_ store: ColumnStore, _ value: Int64) throws -> CodeSet {
        let index = try store.index(RELPropagationEdgeTests.aKey)
        let code = try #require(index.code(of: .integer(value)))
        return CodeSet(column: RELPropagationEdgeTests.aKey, codes: [UInt32(code)])
    }

    // MARK: - Đường mơ hồ

    /// Hai đường hoạt động từ A tới B: báo lỗi, không đoán.
    @Test func twoActivePathsAreReportedAsAmbiguous() throws {
        let store = Self.ambiguousStore()
        let filter = try key(store, 2)
        do {
            _ = try Propagation.visibleRows(in: store, table: Self.tB, localFilters: [filter], overrides: [])
            Issue.record("phải báo lỗi mơ hồ")
        } catch let error as PropagationError {
            #expect(error == .ambiguousPath(from: Self.tA, to: Self.tB))
        }
    }

    /// USERELATIONSHIP bật r1 và tắt r0 (cùng cặp bảng), nên hết mơ hồ. Lọc A = 2 chỉ còn B dòng 2 (k2 = 2).
    @Test func userelationshipResolvesAmbiguityByDeactivatingSamePairRelationship() throws {
        let store = Self.ambiguousStore()
        let filter = try key(store, 2)
        let override = RelationshipOverride(relationship: RelationshipID(raw: 1), isActive: true)
        let rows = try Propagation.visibleRows(in: store, table: Self.tB, localFilters: [filter],
                                               overrides: [override])
        #expect(rows.rows == [2])
    }

    /// Không ghi đè: chỉ r0 hoạt động trong lược đồ này nếu r1 tắt. Lọc A = 2 cho dòng 1 (k1 = 2).
    @Test func singleActiveRelationshipPropagatesWithoutAmbiguity() throws {
        let s = Self.schema([Self.rel(0, "r0", many: Self.bK1, active: true),
                             Self.rel(1, "r1", many: Self.bK2, active: false)])
        let source = InMemoryColumnSource(
            schema: s, rowCounts: [Self.tA: 3, Self.tB: 4],
            columns: [Self.aKey: ColumnBuilder.integers([1, 2, 3]),
                      Self.bK1: ColumnBuilder.integers([1, 2, 3, 1]),
                      Self.bK2: ColumnBuilder.integers([1, 1, 2, 3])])
        let store = ColumnStore(source: source)
        let filter = try key(store, 2)
        let rows = try Propagation.visibleRows(in: store, table: Self.tB, localFilters: [filter], overrides: [])
        #expect(rows.rows == [1])
    }

    /// Ghi đè trỏ tới quan hệ không có trong model: báo lỗi có tên.
    @Test func overrideOfUnknownRelationshipIsRejected() throws {
        let store = Self.ambiguousStore()
        let override = RelationshipOverride(relationship: RelationshipID(raw: 99), isActive: true)
        do {
            _ = try Propagation.visibleRows(in: store, table: Self.tB, localFilters: [], overrides: [override])
            Issue.record("phải báo lỗi quan hệ không tồn tại")
        } catch let error as PropagationError {
            #expect(error == .unknownRelationship(RelationshipID(raw: 99)))
        }
    }

    // MARK: - Cột FK dense

    /// B.k1 là cột dense: [1, 2, 9, 3, BLANK]. Dòng 2 (khoá 9) và dòng 4 (BLANK) không khớp, nên vào blank ảo của A.
    private static func denseStore() -> ColumnStore {
        let s = schema([rel(0, "r0", many: bK1, active: true)])
        let denseFK = ColumnData(type: .integer, rowCount: 5,
                                 payload: .dense(.integers([1, 2, 9, 3, 0],
                                                           blanks: RowSet(universe: 6, sortedRows: [4]))))
        let source = InMemoryColumnSource(
            schema: s, rowCounts: [tA: 3, tB: 5],
            columns: [aKey: ColumnBuilder.integers([1, 2, 3]),
                      bK1: denseFK,
                      bK2: ColumnBuilder.integers([1, 1, 2, 3, 1])])
        return ColumnStore(source: source)
    }

    @Test func denseForeignKeyMapsUnmatchedRowsToBlankRow() throws {
        let store = Self.denseStore()
        let index = try store.relationshipIndex(Self.rel(0, "r0", many: Self.bK1, active: true))
        #expect(index.fkToPK == [0, 1, 3, 2, 3])
        #expect(index.hasUnmatched)
    }

    @Test func denseForeignKeyFilterByKeyKeepsMatchingRows() throws {
        let store = Self.denseStore()
        let filter = try key(store, 1)
        let rows = try Propagation.visibleRows(in: store, table: Self.tB, localFilters: [filter], overrides: [])
        #expect(rows.rows == [0])
    }

    /// Lọc A bằng BLANK: chỉ blank ảo của A còn lại, và B giữ các dòng FK không khớp (2 và 4).
    @Test func blankFilterOnDimensionKeepsDenseUnmatchedRows() throws {
        let store = Self.denseStore()
        let blank = CodeSet(column: Self.aKey, codes: [0])
        let aRows = try Propagation.visibleRows(in: store, table: Self.tA, localFilters: [blank], overrides: [])
        #expect(aRows.rows == [3], "blank ảo của A (chỉ số 3)")
        let bRows = try Propagation.visibleRows(in: store, table: Self.tB, localFilters: [blank], overrides: [])
        #expect(bRows.rows == [2, 4])
    }

    // MARK: - Bên một lớn: đường sắp xếp và đường bitset

    /// A có 200 khoá (0..199), B có 1001 dòng với khoá i % 200, trừ dòng 1000 có khoá 500 không khớp.
    private static func largeStore() -> ColumnStore {
        let s = schema([rel(0, "r0", many: bK1, active: true)])
        var aKeys: [Int64?] = []
        for i in 0..<200 { aKeys.append(Int64(i)) }
        var bKeys: [Int64?] = []
        for i in 0..<1000 { bKeys.append(Int64(i % 200)) }
        bKeys.append(500)
        let source = InMemoryColumnSource(
            schema: s, rowCounts: [tA: 200, tB: 1001],
            columns: [aKey: ColumnBuilder.integers(aKeys),
                      bK1: ColumnBuilder.integers(bKeys),
                      bK2: ColumnBuilder.integers(Array(repeating: 1, count: 1001))])
        return ColumnStore(source: source)
    }

    /// Một dòng bên một thì đi theo posting (sparse). Một tập lớn thì đi theo mảng bool. Cả hai đúng.
    @Test func oneRowsSortPathAndBitPathAgree() throws {
        let store = Self.largeStore()
        let index = try store.relationshipIndex(Self.rel(0, "r0", many: Self.bK1, active: true))
        #expect(index.oneRowCount == 200)
        #expect(index.hasUnmatched)

        // Tập nhỏ: 2 dòng bên nhiều, dòng 1000 không khớp nên trỏ tới blank (200).
        let small = RowSet(universe: 1002, sortedRows: [3, 1000])
        #expect(index.oneRows(from: small).rows == [3, 200])

        // Tập lớn: mọi dòng bên nhiều chẵn, bằng brute force.
        let evens = (0..<1001).filter { $0 % 2 == 0 }.map { UInt32($0) }
        let big = RowSet(universe: 1002, sortedRows: evens)
        var brute = Set<UInt32>()
        for m in evens {
            let i = Int(m)
            brute.insert(i < 1001 ? UInt32(index.fkToPK[i]) : 200)
        }
        #expect(index.oneRows(from: big).rows == brute.sorted())
    }

    /// Lên posting và quét, với bên một chỉ có khoá 3: các dòng có khoá 3 (3, 203, 403, 603, 803).
    @Test func manyRowsPostingAndScanAgreeOnLargeSide() throws {
        let store = Self.largeStore()
        let index = try store.relationshipIndex(Self.rel(0, "r0", many: Self.bK1, active: true))
        let one = RowSet(universe: 201, sortedRows: [3])
        let expected: [UInt32] = [3, 203, 403, 603, 803]
        #expect(index.manyRows(from: one, strategy: .postings).rows == expected)
        #expect(index.manyRows(from: one, strategy: .scan).rows == expected)
        #expect(index.manyRows(from: one).rows == expected)
    }
}
