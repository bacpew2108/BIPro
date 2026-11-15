// Phase F, T016: ModelMetadata.applying(.addTable/.replaceTable/.dropTable) trên mô hình Nhom6 thật (chỉ đọc).
// Seam: ModelMetadata.applying. Tên ModelEditError (tiếng Việt) là hợp đồng với giao diện.
import Foundation
import Testing
@testable import PBIXKit

@Suite("Phase F: bảng nạp vào mô hình", .enabled(if: ModelEditFixture.metadata != nil)) struct ModelEditTableTests {
    let base = ModelEditFixture.metadata!

    private func newTable(_ name: String = "Sales2026") -> NewTable {
        NewTable(name: name,
                 columns: [NewTableColumn(name: "OrderID", values: .int64([1, 2, 3])),
                           NewTableColumn(name: "Amount", values: .double([1.5, 2.5, 3.5])),
                           NewTableColumn(name: "Region", values: .string(["A", nil, "B"])),
                           NewTableColumn(name: "OrderDate", dataType: .dateTime)],
                 queryExpression: "let Source = 1 in Source")
    }

    private func columns(_ m: ModelMetadata, _ table: String) -> [ModelMetadata.Column] {
        m.columns.filter { $0.tableName == table }
    }

    private func refusal(_ edit: ModelEdit, on metadata: ModelMetadata? = nil) -> String? {
        do { _ = try (metadata ?? base).applying(ModelEdits([edit])); return nil } catch let e as ModelEditError { return e.reason } catch { return "\(error)" }
    }

    /// Bảng có quan hệ ở đầu "một" hoặc "nhiều": (bảng, cột đầu quan hệ).
    private var relatedTable: (table: String, column: String) {
        let r = base.relationships[0]
        return (r.fromTable, r.fromColumn)
    }

    // MARK: addTable

    @Test func themBangHienTrongMoHinhVoiCotDungKieu() throws {
        let result = try base.applying(ModelEdits([.addTable(newTable())]))
        let table = try #require(result.userTables.first { $0.name == "Sales2026" })
        let cols = columns(result, "Sales2026")
        #expect(cols.map(\.name) == ["OrderID", "Amount", "Region", "OrderDate"])
        #expect(cols.map(\.dataType) == [.int64, .double, .string, .dateTime])
        // Như Desktop (2026-11-15): số cộng dồn (3), số tên kết thúc "ID" đếm (6); chuỗi/ngày 2.
        #expect(cols.map(\.summarizeBy) == [6, 3, 2, 2])
        #expect(cols.allSatisfy { $0.kind == .data && $0.tableID == table.id && !$0.isHidden })
        #expect(result.partitionQueries["Sales2026"] == "let Source = 1 in Source")
        // Mô hình gốc không đổi.
        #expect(base.userTables.contains { $0.name == "Sales2026" } == false)
        #expect(result.userTables.count == base.userTables.count + 1)
    }

    @Test func idBangVaCotMoiLaDuyNhat() throws {
        let result = try base.applying(ModelEdits([.addTable(newTable("T1")), .addTable(newTable("T2"))]))
        let tableIDs = result.tables.map(\.id)
        let columnIDs = result.columns.map(\.id)
        #expect(Set(tableIDs).count == tableIDs.count)
        #expect(Set(columnIDs).count == columnIDs.count)
    }

    @Test func ketQuaOnDinhKhiApDungLai() throws {
        let edits = ModelEdits([.addTable(newTable())])
        let a = try base.applying(edits), b = try base.applying(edits)
        #expect(a.tables == b.tables)
        #expect(a.columns == b.columns)
    }

    @Test func tenBangTrungKhongPhanBietHoaThuongBiTuChoi() {
        let existing = base.userTables[0].name
        #expect(refusal(.addTable(newTable(existing.uppercased())))?.contains("trùng") == true)
    }

    @Test func tenBangRongHoacNULBiTuChoi() {
        #expect(refusal(.addTable(newTable("   "))) != nil)
        #expect(refusal(.addTable(newTable("A\0B"))) != nil)
    }

    @Test func tenCotTrungKhongPhanBietHoaThuongBiTuChoi() {
        let table = NewTable(name: "T", columns: [NewTableColumn(name: "Qty", values: .int64([1])),
                                                  NewTableColumn(name: "qty", values: .int64([2]))])
        #expect(refusal(.addTable(table))?.contains("Qty") == true)
    }

    @Test func bangKhongCotHoacCotTenRongBiTuChoi() {
        #expect(refusal(.addTable(NewTable(name: "T", columns: []))) != nil)
        #expect(refusal(.addTable(NewTable(name: "T", columns: [NewTableColumn(name: " ", values: .int64([1]))]))) != nil)
    }

    @Test func truyVanTatNapKhongTaoBang() throws {
        let table = NewTable(name: "Staging", columns: [NewTableColumn(name: "A", values: .int64([1]))], enableLoad: false)
        let result = try base.applying(ModelEdits([.addTable(table)]))
        #expect(result.tables == base.tables)
        #expect(result.columns == base.columns)
    }

    @Test func quanHeTuBangMoiToiBangCoSanHopLe() throws {
        let r = base.relationships[0]
        let target = try #require(base.columns.first { $0.tableName == r.toTable && $0.name == r.toColumn })
        let table = NewTable(name: "Fact2", columns: [NewTableColumn(name: "Key", dataType: target.dataType)])
        let rel = NewRelationship(fromTable: "Fact2", fromColumn: "Key", toTable: r.toTable, toColumn: r.toColumn)
        let result = try base.applying(ModelEdits([.addTable(table), .addRelationship(rel)]))
        #expect(result.relationships.contains { $0.fromTable == "Fact2" && $0.toTable == r.toTable })
    }

    // MARK: replaceTable

    @Test func thayBangGiuQuanHeVaIDCotKhiCotConTon() throws {
        let (name, keyColumn) = relatedTable
        let oldColumns = columns(base, name).filter { $0.kind == .data }
        let oldTable = try #require(base.userTables.first { $0.name == name })
        var cols = oldColumns.map { NewTableColumn(name: $0.name, dataType: $0.dataType) }
        cols.append(NewTableColumn(name: "ThemMoi", values: .int64([1])))
        let result = try base.applying(ModelEdits([.replaceTable(name: name, NewTable(name: name, columns: cols, queryExpression: "let X = 1 in X"))]))
        #expect(result.relationships == base.relationships)
        #expect(result.measures == base.measures)
        let newTable = try #require(result.userTables.first { $0.name == name })
        #expect(newTable.id == oldTable.id)
        let kept = try #require(columns(result, name).first { $0.name == keyColumn })
        #expect(kept.id == base.columns.first { $0.tableName == name && $0.name == keyColumn }?.id)
        let added = try #require(columns(result, name).first { $0.name == "ThemMoi" })
        #expect(!base.columns.contains { $0.id == added.id })
        #expect(result.partitionQueries[name] == "let X = 1 in X")
    }

    @Test func thayBangBoCotDauQuanHeBiTuChoiKemChoDung() {
        let (name, keyColumn) = relatedTable
        let others = columns(base, name).filter { $0.kind == .data && $0.name != keyColumn }
        let table = NewTable(name: name, columns: others.map { NewTableColumn(name: $0.name, dataType: $0.dataType) })
        let reason = refusal(.replaceTable(name: name, table))
        #expect(reason?.contains(keyColumn) == true)
        #expect(reason?.contains("quan hệ") == true)
    }

    @Test func thayBangBoCotKhongAiDungDuocPhep() throws {
        let used = Set(base.relationships.flatMap { [$0.fromTable + "\0" + $0.fromColumn, $0.toTable + "\0" + $0.toColumn] })
        let sortTargets = Set(base.columns.compactMap(\.sortByColumnID))
        let hierarchyCols = Set(base.hierarchies.flatMap { h in h.levels.map { h.tableName + "\0" + $0.columnName } })
        let userTableNames = Set(base.userTables.map(\.name))
        let candidate = try #require(base.columns.first { column in
            let key = column.tableName + "\0" + column.name
            return column.kind == .data && userTableNames.contains(column.tableName) && !used.contains(key)
                && !sortTargets.contains(column.id) && !hierarchyCols.contains(key)
        })
        let keep = columns(base, candidate.tableName).filter { $0.kind == .data && $0.id != candidate.id }
        let table = NewTable(name: candidate.tableName, columns: keep.map { NewTableColumn(name: $0.name, dataType: $0.dataType) })
        let result = try base.applying(ModelEdits([.replaceTable(name: candidate.tableName, table)]))
        #expect(!columns(result, candidate.tableName).contains { $0.name == candidate.name })
    }

    @Test func thayBangKhongCoBiTuChoi() {
        #expect(refusal(.replaceTable(name: "KhongCo", newTable()))?.contains("KhongCo") == true)
    }

    @Test func thayBangDoiTenCapNhatThamChieu() throws {
        let (name, _) = relatedTable
        let cols = columns(base, name).filter { $0.kind == .data }.map { NewTableColumn(name: $0.name, dataType: $0.dataType) }
        let result = try base.applying(ModelEdits([.replaceTable(name: name, NewTable(name: "DoiTen", columns: cols))]))
        #expect(!result.userTables.contains { $0.name == name })
        #expect(result.relationships.contains { $0.fromTable == "DoiTen" || $0.toTable == "DoiTen" })
        #expect(!result.relationships.contains { $0.fromTable == name || $0.toTable == name })
        #expect(result.measures.filter { $0.tableName == "DoiTen" }.count == base.measures.filter { $0.tableName == name }.count)
    }

    // MARK: dropTable

    @Test func xoaBangMoiChuaAiDung() throws {
        let result = try base.applying(ModelEdits([.addTable(newTable()), .dropTable(name: "Sales2026")]))
        #expect(!result.userTables.contains { $0.name == "Sales2026" })
        #expect(columns(result, "Sales2026").isEmpty)
        #expect(result.partitionQueries["Sales2026"] == nil)
    }

    @Test func xoaBangCoQuanHeBiTuChoi() {
        let (name, _) = relatedTable
        #expect(refusal(.dropTable(name: name))?.contains("quan hệ") == true)
    }

    @Test func xoaBangChuaMeasureBiTuChoi() throws {
        let hosted = NewMeasure(table: "Sales2026", name: "TongTien", expression: "SUM(Sales2026[Amount])")
        let edits = ModelEdits([.addTable(newTable()), .addMeasure(hosted), .dropTable(name: "Sales2026")])
        do {
            _ = try base.applying(edits)
            Issue.record("phải bị từ chối")
        } catch let error as ModelEditError {
            #expect(error.reason.contains("measure TongTien"))
        }
    }

    @Test func xoaBangDangDuocMeasureKhacDungBiTuChoi() throws {
        let host = try #require(base.userTables.first { $0.name != "Sales2026" })
        let user = NewMeasure(table: host.name, name: "DemBangMoi", expression: "COUNTROWS(Sales2026)")
        let edits = ModelEdits([.addTable(newTable()), .addMeasure(user), .dropTable(name: "Sales2026")])
        do {
            _ = try base.applying(edits)
            Issue.record("phải bị từ chối")
        } catch let error as ModelEditError {
            #expect(error.reason.contains("DemBangMoi"))
        }
    }

    @Test func xoaBangKhongCoBiTuChoi() {
        #expect(refusal(.dropTable(name: "KhongCo")) != nil)
    }
}
