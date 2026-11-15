import Foundation
import Testing
@testable import PBIXKit

/// Metadata của Nhom6 thật (chỉ đọc). Bỏ qua khi không có file.
enum ModelEditFixture {
    /// Bytes `metadata.sqlitedb` của Nhom6.
    static let data: Data? = {
        guard let url = EditFixture.nhom6 else { return nil }
        return try? PBIXFile(url: url).loadDataModel().0.contents(named: "metadata.sqlitedb")
    }()
    static let metadata: ModelMetadata? = data.flatMap { try? ModelMetadata(sqlite: $0) }
}

@Suite("Phase E: ModelMetadata.applying", .enabled(if: ModelEditFixture.metadata != nil)) struct ModelEditTests {
    let base = ModelEditFixture.metadata!

    private func measure(_ m: ModelMetadata, _ table: String, _ name: String) -> ModelMetadata.Measure? {
        m.measures.first { $0.tableName == table && $0.name == name }
    }

    @Test func themMeasureHienTrongMoHinhHieuLuc() throws {
        let edits = ModelEdits([.addMeasure(NewMeasure(table: "Dim_Account", name: "E_Test",
                                                       expression: "COUNTROWS(Dim_Account)+1", formatString: "0",
                                                       displayFolder: "Thu muc E", description: "mo ta E"))])
        let result = try base.applying(edits)
        let added = try #require(measure(result, "Dim_Account", "E_Test"))
        #expect(added.expression == "COUNTROWS(Dim_Account)+1")
        #expect(added.formatString == "0")
        #expect(added.displayFolder == "Thu muc E")
        #expect(added.description == "mo ta E")
        #expect(result.measures.count == base.measures.count + 1)
        #expect(measure(base, "Dim_Account", "E_Test") == nil)
    }

    @Test func suaMeasureGiuNguyenPhanKhongDoi() throws {
        let original = try #require(base.measures.first { !$0.expression.isEmpty && $0.formatString != nil && !$0.isHidden })
        let edits = ModelEdits([.updateMeasure(table: original.tableName, name: original.name,
                                               patch: MeasurePatch(expression: "1+1", displayFolder: .set("Thu muc"), isHidden: true))])
        let result = try base.applying(edits)
        let changed = try #require(measure(result, original.tableName, original.name))
        #expect(changed.expression == "1+1")
        #expect(changed.displayFolder == "Thu muc")
        #expect(changed.isHidden)
        #expect(changed.formatString == original.formatString)
        #expect(changed.lineageTag == original.lineageTag)
        #expect(result.measures.count == base.measures.count)
    }

    @Test func xoaMeasure() throws {
        let original = try #require(base.measures.first)
        let result = try base.applying(ModelEdits([.deleteMeasure(table: original.tableName, name: original.name)]))
        #expect(measure(result, original.tableName, original.name) == nil)
        #expect(result.measures.count == base.measures.count - 1)
    }

    @Test func doiTenMeasure() throws {
        let original = try #require(base.measures.first)
        let result = try base.applying(ModelEdits([.updateMeasure(table: original.tableName, name: original.name,
                                                                  patch: MeasurePatch(name: "Ten Moi"))]))
        #expect(measure(result, original.tableName, "Ten Moi") != nil)
        #expect(measure(result, original.tableName, original.name) == nil)
    }

    @Test func themLienTiepGomCacThaoTacTheoThuTu() throws {
        let edits = ModelEdits([
            .addMeasure(NewMeasure(table: "Dim_Account", name: "E_Test", expression: "1")),
            .updateMeasure(table: "Dim_Account", name: "E_Test", patch: MeasurePatch(expression: "2")),
        ])
        let result = try base.applying(edits)
        #expect(measure(result, "Dim_Account", "E_Test")?.expression == "2")
    }

    @Test func khongCoThaoTacThiGiuNguyen() throws {
        let result = try base.applying(ModelEdits())
        #expect(result.measures == base.measures)
        #expect(result.relationships == base.relationships)
        #expect(result.columns == base.columns)
    }

    // Quy tắc kiểm hợp lệ (data-model.md)

    @Test func tenMeasureTrungHoacRongBiTuChoi() throws {
        let existing = try #require(base.measures.first)
        func rejects(_ edits: [ModelEdit]) -> Bool {
            do { _ = try base.applying(ModelEdits(edits)); return false } catch is ModelEditError { return true } catch { return false }
        }
        // trùng measure khác hoa thường
        #expect(rejects([.addMeasure(NewMeasure(table: existing.tableName, name: existing.name.uppercased(), expression: "1"))]))
        // trùng cột cùng bảng
        let userTableNames = Set(base.userTables.map(\.name))
        let column = try #require(base.columns.first { $0.kind == .data && userTableNames.contains($0.tableName) })
        #expect(rejects([.addMeasure(NewMeasure(table: column.tableName, name: column.name, expression: "1"))]))
        // trùng tên bảng
        #expect(rejects([.addMeasure(NewMeasure(table: existing.tableName, name: existing.tableName, expression: "1"))]))
        // rỗng, NUL, bảng không có
        #expect(rejects([.addMeasure(NewMeasure(table: existing.tableName, name: "  ", expression: "1"))]))
        #expect(rejects([.addMeasure(NewMeasure(table: existing.tableName, name: "a\0b", expression: "1"))]))
        #expect(rejects([.addMeasure(NewMeasure(table: "Khong Co", name: "X", expression: "1"))]))
        // sửa/xoá measure không có; đổi tên thành tên trùng
        #expect(rejects([.updateMeasure(table: existing.tableName, name: "Khong Co", patch: MeasurePatch(expression: "1"))]))
        #expect(rejects([.deleteMeasure(table: existing.tableName, name: "Khong Co")]))
        let other = try #require(base.measures.first { $0.tableName == existing.tableName && $0.name != existing.name })
        #expect(rejects([.updateMeasure(table: existing.tableName, name: existing.name, patch: MeasurePatch(name: other.name))]))
    }

    // Quan hệ

    @Test func suaThuocTinhQuanHe() throws {
        let rel = try #require(base.relationships.first { $0.isActive && $0.crossFilteringBehavior == 1 })
        let result = try base.applying(ModelEdits([.updateRelationship(
            name: rel.name, patch: RelationshipPatch(isActive: false, crossFilteringBehavior: 2))]))
        let changed = try #require(result.relationships.first { $0.name == rel.name })
        #expect(!changed.isActive)
        #expect(changed.crossFilteringBehavior == 2)
        #expect(changed.fromTable == rel.fromTable && changed.toColumn == rel.toColumn && changed.cardinality == rel.cardinality)
        #expect(result.relationships.count == base.relationships.count)
        #expect(base.relationships.first { $0.name == rel.name }?.isActive == true)
    }

    @Test func quanHeSaiBiTuChoi() throws {
        let rel = try #require(base.relationships.first)
        func rejects(_ edit: ModelEdit) -> Bool {
            do { _ = try base.applying(ModelEdits([edit])); return false } catch is ModelEditError { return true } catch { return false }
        }
        #expect(rejects(.updateRelationship(name: "khong co", patch: RelationshipPatch(isActive: false))))
        #expect(rejects(.updateRelationship(name: rel.name, patch: RelationshipPatch(crossFilteringBehavior: 3))))
        #expect(rejects(.updateRelationship(name: rel.name, patch: RelationshipPatch(crossFilteringBehavior: 0))))
    }

    @Test func khongBatHaiQuanHeHoatDongGiuaCungHaiBang() throws {
        // Fact_CRM_Complaint → Dim_Date có một quan hệ hoạt động (ngày nhận) và một không hoạt động (ngày gửi).
        let inactive = try #require(base.relationships.first { !$0.isActive })
        do {
            _ = try base.applying(ModelEdits([.updateRelationship(name: inactive.name, patch: RelationshipPatch(isActive: true))]))
            Issue.record("bật thêm quan hệ hoạt động giữa cùng hai bảng phải bị từ chối")
        } catch let error as ModelEditError {
            #expect(error.reason.contains("hoạt động"))
        }
        // tắt quan hệ đang hoạt động rồi bật quan hệ kia (hai thao tác liền nhau) thì được
        let active = try #require(base.relationships.first {
            $0.isActive && $0.fromTable == inactive.fromTable && $0.toTable == inactive.toTable
        })
        let swapped = try base.applying(ModelEdits([
            .updateRelationship(name: active.name, patch: RelationshipPatch(isActive: false)),
            .updateRelationship(name: inactive.name, patch: RelationshipPatch(isActive: true)),
        ]))
        #expect(swapped.relationships.filter { $0.isActive && $0.fromTable == inactive.fromTable && $0.toTable == inactive.toTable }.count == 1)
    }

    @Test func anHienBang() throws {
        let table = try #require(base.userTables.first { !$0.isHidden })
        let hidden = try base.applying(ModelEdits([.updateTable(name: table.name, patch: TablePatch(isHidden: true))]))
        #expect(hidden.tables.first { $0.name == table.name }?.isHidden == true && hidden.tables.count == base.tables.count)
        #expect(ModelMetadata.edits(from: base, to: hidden).items == [.updateTable(name: table.name, patch: TablePatch(isHidden: true))])
        #expect(throws: ModelEditError.self) { try base.applying(ModelEdits([.updateTable(name: "khong co", patch: TablePatch(isHidden: true))])) }
    }

    // Cột

    @Test func suaThuocTinhCot() throws {
        let userTableNames = Set(base.userTables.map(\.name))
        let column = try #require(base.columns.first { $0.kind == .data && userTableNames.contains($0.tableName) && !$0.isHidden && $0.displayFolder == nil })
        let patch = ColumnPatch(isHidden: true, formatString: .set("0.00"), summarizeBy: 3,
                                dataCategory: .set("City"), displayFolder: .set("Thu muc"), description: .set("mo ta"))
        let result = try base.applying(ModelEdits([.updateColumn(table: column.tableName, name: column.name, patch: patch)]))
        let changed = try #require(result.columns.first { $0.id == column.id })
        #expect(changed.isHidden)
        #expect(changed.formatString == "0.00")
        #expect(changed.summarizeBy == 3)
        #expect(changed.dataCategory == "City")
        #expect(changed.displayFolder == "Thu muc")
        #expect(changed.description == "mo ta")
        #expect(changed.dataType == column.dataType && changed.lineageTag == column.lineageTag)
        let cleared = try result.applying(ModelEdits([.updateColumn(table: column.tableName, name: column.name,
                                                                    patch: ColumnPatch(formatString: .clear, displayFolder: .clear))]))
        let again = try #require(cleared.columns.first { $0.id == column.id })
        #expect(again.formatString == nil && again.displayFolder == nil && again.description == "mo ta")
    }

    @Test func sapXepTheoCotPhaiCungBang() throws {
        let userTableNames = Set(base.userTables.map(\.name))
        let data = base.columns.filter { $0.kind == .data && userTableNames.contains($0.tableName) }
        let a = try #require(data.first)
        let sameTable = try #require(data.first { $0.tableName == a.tableName && $0.id != a.id })
        let otherTable = try #require(data.first { $0.tableName != a.tableName })
        let ok = try base.applying(ModelEdits([.updateColumn(table: a.tableName, name: a.name, patch: ColumnPatch(sortBy: .set(sameTable.name)))]))
        #expect(ok.columns.first { $0.id == a.id }?.sortByColumnID == sameTable.id)
        let cleared = try ok.applying(ModelEdits([.updateColumn(table: a.tableName, name: a.name, patch: ColumnPatch(sortBy: .clear))]))
        #expect(cleared.columns.first { $0.id == a.id }?.sortByColumnID == nil)
        func rejects(_ sort: String) -> Bool {
            do { _ = try base.applying(ModelEdits([.updateColumn(table: a.tableName, name: a.name, patch: ColumnPatch(sortBy: .set(sort)))])); return false }
            catch is ModelEditError { return true } catch { return false }
        }
        #expect(rejects(otherTable.name) || otherTable.tableName != a.tableName)   // tên cột của bảng khác không tìm thấy trong bảng này (trừ khi trùng tên)
        #expect(rejects(a.name))      // chính nó
        #expect(rejects("khong co"))
    }

    @Test func doiTenCotChiKhiKhongConNoiDung() throws {
        let userTableNames = Set(base.userTables.map(\.name))
        let relationshipColumns = Set(base.relationships.flatMap { [$0.fromTable + "." + $0.fromColumn, $0.toTable + "." + $0.toColumn] })
        let sortTargets = Set(base.columns.compactMap(\.sortByColumnID))
        let free = try #require(base.columns.first {
            $0.kind == .data && userTableNames.contains($0.tableName) && !relationshipColumns.contains($0.tableName + "." + $0.name)
                && !sortTargets.contains($0.id)
        })
        let renamed = try base.applying(ModelEdits([.updateColumn(table: free.tableName, name: free.name, patch: ColumnPatch(name: "Cot Moi"))]))
        #expect(renamed.columns.contains { $0.tableName == free.tableName && $0.name == "Cot Moi" })
        // đầu của một quan hệ: bị từ chối
        let rel = try #require(base.relationships.first)
        do {
            _ = try base.applying(ModelEdits([.updateColumn(table: rel.fromTable, name: rel.fromColumn, patch: ColumnPatch(name: "Doi Ten"))]))
            Issue.record("đổi tên đầu quan hệ phải bị từ chối")
        } catch is ModelEditError {}
        // trùng tên cột khác
        let sibling = try #require(base.columns.first { $0.tableName == free.tableName && $0.id != free.id })
        do {
            _ = try base.applying(ModelEdits([.updateColumn(table: free.tableName, name: free.name, patch: ColumnPatch(name: sibling.name))]))
            Issue.record("tên trùng phải bị từ chối")
        } catch is ModelEditError {}
    }
}

@Suite("Phase E: ModelMetadata.edits(from:to:)", .enabled(if: ModelEditFixture.metadata != nil)) struct ModelDiffTests {
    let base = ModelEditFixture.metadata!

    private func plain(_ list: [ModelMetadata.Measure]) -> [String] {
        list.map { "\($0.tableName)|\($0.name)|\($0.expression)|\($0.formatString ?? "-")|\($0.displayFolder ?? "-")|\($0.description ?? "-")|\($0.isHidden)|\($0.dataType)" }.sorted()
    }

    @Test func diffTaoLaiDungMoHinhDich() throws {
        let userTableNames = Set(base.userTables.map(\.name))
        let measure = try #require(base.measures.first { $0.formatStringDefinition == nil })
        let other = try #require(base.measures.last { $0.formatStringDefinition == nil && $0.name != measure.name })
        let rel = try #require(base.relationships.first { $0.isActive })
        let column = try #require(base.columns.first { $0.kind == .data && userTableNames.contains($0.tableName) && !$0.isHidden })
        let edits = ModelEdits([
            .addMeasure(NewMeasure(table: "Dim_Account", name: "E_Test", expression: "1", formatString: "0", dataType: 6)),
            .updateMeasure(table: measure.tableName, name: measure.name, patch: MeasurePatch(expression: "2", displayFolder: .set("F"))),
            .deleteMeasure(table: other.tableName, name: other.name),
            .updateRelationship(name: rel.name, patch: RelationshipPatch(isActive: false, crossFilteringBehavior: 2)),
            .updateColumn(table: column.tableName, name: column.name, patch: ColumnPatch(isHidden: true, summarizeBy: 3)),
        ])
        let target = try base.applying(edits)
        let diff = ModelMetadata.edits(from: base, to: target)
        let rebuilt = try base.applying(diff)
        #expect(plain(rebuilt.measures) == plain(target.measures))
        #expect(rebuilt.relationships == target.relationships)
        #expect(rebuilt.columns == target.columns)
        // không đổi gì thì không có thao tác
        #expect(ModelMetadata.edits(from: base, to: base).isEmpty)
    }

    @Test func diffCoThemVaXoaQuanHe() throws {
        let victim = try #require(base.relationships.first { $0.fromTable == "Fact_Loan" })
        let added = NewRelationship(name: "aaaaaaaa-1111-2222-3333-444444444444", fromTable: "Fact_Loan", fromColumn: "loan_count",
                                    toTable: "Dim_Client", toColumn: "client_key", isActive: false)
        let target = try base.applying(ModelEdits([.deleteRelationship(name: victim.name), .addRelationship(added)]))
        let delta = ModelMetadata.edits(from: base, to: target)
        #expect(delta.items.contains(.deleteRelationship(name: victim.name)) && delta.items.contains(.addRelationship(added)))
        #expect(try base.applying(delta).relationships.map(\.name).sorted() == target.relationships.map(\.name).sorted())
        // chiều ngược lại (hoàn tác sau khi đã lưu): bỏ quan hệ mới, thêm lại quan hệ đã xoá
        let back = ModelMetadata.edits(from: target, to: base)
        #expect(back.items.contains(.deleteRelationship(name: added.name)))
        #expect(back.items.contains { if case .addRelationship(let r) = $0 { r.name == victim.name && r.fromMany && !r.toMany } else { false } })
    }

    @Test func diffDoiTenMeasureGiuIDQuaLineageTag() throws {
        let measure = try #require(base.measures.first { $0.lineageTag != nil })
        let renamed = try base.applying(ModelEdits([.updateMeasure(table: measure.tableName, name: measure.name, patch: MeasurePatch(name: "Ten Moi", expression: "1"))]))
        let delta = ModelMetadata.edits(from: base, to: renamed)
        #expect(delta.items == [.updateMeasure(table: measure.tableName, name: measure.name, patch: MeasurePatch(name: "Ten Moi", expression: "1"))])
    }

    @Test func diffTuMoHinhDaLuuDenMoHinhMoi() throws {
        let saved = try base.applying(ModelEdits([.addMeasure(NewMeasure(table: "Dim_Account", name: "E_Test", expression: "1"))]))
        let target = try base.applying(ModelEdits([.addMeasure(NewMeasure(table: "Dim_Account", name: "E_Test", expression: "2", displayFolder: "F"))]))
        let delta = ModelMetadata.edits(from: saved, to: target)
        #expect(delta.items == [.updateMeasure(table: "Dim_Account", name: "E_Test",
                                               patch: MeasurePatch(expression: "2", displayFolder: .set("F")))])
    }
}

/// `ModelEdits.appending` gộp thao tác liền kề cùng một đối tượng (không cần file thật).
@Suite("Phase E: ModelEdits.appending") struct ModelEditsAppendingTests {
    @Test func haiLanSuaBieuThucThanhMot() {
        var edits = ModelEdits()
        edits = edits.appending(.updateMeasure(table: "T", name: "M", patch: MeasurePatch(expression: "1")))
        edits = edits.appending(.updateMeasure(table: "T", name: "M", patch: MeasurePatch(expression: "2", displayFolder: .set("F"))))
        #expect(edits.items == [.updateMeasure(table: "T", name: "M", patch: MeasurePatch(expression: "2", displayFolder: .set("F")))])
    }

    @Test func suaMeasureVuaThemGopVaoThem() {
        var edits = ModelEdits([.addMeasure(NewMeasure(table: "T", name: "M", expression: "1"))])
        edits = edits.appending(.updateMeasure(table: "T", name: "M", patch: MeasurePatch(name: "N", expression: "2", formatString: .set("0"))))
        #expect(edits.items == [.addMeasure(NewMeasure(table: "T", name: "N", expression: "2", formatString: "0"))])
        // và sửa tiếp theo tên mới
        edits = edits.appending(.updateMeasure(table: "T", name: "N", patch: MeasurePatch(isHidden: true)))
        #expect(edits.items == [.addMeasure(NewMeasure(table: "T", name: "N", expression: "2", formatString: "0", isHidden: true))])
    }

    @Test func themRoiXoaThanhKhong() {
        var edits = ModelEdits([.addMeasure(NewMeasure(table: "T", name: "M", expression: "1"))])
        edits = edits.appending(.deleteMeasure(table: "T", name: "M"))
        #expect(edits.isEmpty)
    }

    @Test func suaRoiXoaThanhXoa() {
        var edits = ModelEdits([.updateMeasure(table: "T", name: "M", patch: MeasurePatch(expression: "1"))])
        edits = edits.appending(.deleteMeasure(table: "T", name: "M"))
        #expect(edits.items == [.deleteMeasure(table: "T", name: "M")])
    }

    @Test func suaDoiTenRoiSuaTiepTheoTenMoi() {
        var edits = ModelEdits([.updateMeasure(table: "T", name: "M", patch: MeasurePatch(name: "N"))])
        edits = edits.appending(.updateMeasure(table: "T", name: "N", patch: MeasurePatch(expression: "9")))
        #expect(edits.items == [.updateMeasure(table: "T", name: "M", patch: MeasurePatch(name: "N", expression: "9"))])
    }

    @Test func quanHeVaCotGopRiengTheoDoiTuong() {
        var edits = ModelEdits()
        edits = edits.appending(.updateRelationship(name: "r", patch: RelationshipPatch(isActive: false)))
        edits = edits.appending(.updateRelationship(name: "r", patch: RelationshipPatch(crossFilteringBehavior: 2)))
        edits = edits.appending(.updateRelationship(name: "s", patch: RelationshipPatch(isActive: true)))
        #expect(edits.items == [
            .updateRelationship(name: "r", patch: RelationshipPatch(isActive: false, crossFilteringBehavior: 2)),
            .updateRelationship(name: "s", patch: RelationshipPatch(isActive: true)),
        ])
        edits = edits.appending(.updateColumn(table: "T", name: "c", patch: ColumnPatch(isHidden: true)))
        edits = edits.appending(.updateColumn(table: "T", name: "c", patch: ColumnPatch(isHidden: false, formatString: .set("0"))))
        #expect(edits.items.last == .updateColumn(table: "T", name: "c", patch: ColumnPatch(isHidden: false, formatString: .set("0"))))
        #expect(edits.items.count == 3)
    }

    @Test func thaoTacKhongLienKeKhongGop() {
        var edits = ModelEdits([.updateMeasure(table: "T", name: "M", patch: MeasurePatch(expression: "1"))])
        edits = edits.appending(.updateMeasure(table: "T", name: "Q", patch: MeasurePatch(expression: "2")))
        edits = edits.appending(.updateMeasure(table: "T", name: "M", patch: MeasurePatch(expression: "3")))
        #expect(edits.items.count == 3)
    }
}
