// Đợt tồn đọng sau Phase F, T032: `AutoDateTime` sinh `ModelEdit` theo vòng đời bảng ngày cục bộ (`specs/011-…/data-model.md`):
// cột ngày thêm, thay, đổi tên hay bỏ; bảng xoá; tắt hay bật tuỳ chọn; thêm rồi bỏ trong phiên gộp về không. Phần thuần chạy trên mô hình
// `vm-f11/f11-desktop.pbix` (3 bảng cục bộ, 1 bảng mẫu); luồng đủ chạy trên tài liệu mới: nạp bảng, engine tính bảng ngày, lưu, mở lại.
import ColumnStore
import DAXEngine
import Foundation
import PBIXKit
import Testing
@testable import BIPro

@Suite struct AutoDateTimeTests {
    static var f11: URL? { F2Fixtures.desktop("vm-f11", "f11-desktop.pbix") }

    private func model(_ url: URL) throws -> ModelMetadata {
        let (abf, _) = try PBIXFile(data: try Data(contentsOf: url, options: .alwaysMapped)).loadDataModel()
        return try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb"))
    }

    /// GUID tuần tự để tên bảng và quan hệ ổn định trong test.
    final class Counter: @unchecked Sendable {
        var n = 0
        func next() -> UUID { n += 1; return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
    }

    private func table(_ name: String, _ columns: [(String, ModelMetadata.DataType)]) -> NewTable {
        NewTable(name: name, columns: columns.map { NewTableColumn(name: $0.0, dataType: $0.1) })
    }

    private func locals(_ m: ModelMetadata) -> [String] { m.tables.map(\.name).filter(AutoDateTime.isLocalTable) }
    private func templates(_ m: ModelMetadata) -> [String] { m.tables.map(\.name).filter(AutoDateTime.isTemplateTable) }

    @Test(.enabled(if: f11 != nil))
    func themBangCoCotNgayThemBoBangNgay() throws {
        let base = try model(try #require(Self.f11))
        let ids = Counter()
        let edits = AutoDateTime.expand([.addTable(table("Orders", [("Id", .int64), ("OrderDate", .dateTime), ("Note", .string)]))],
                                        model: base, id: ids.next)
        let after = try base.applying(ModelEdits(edits))
        // Đã có bảng mẫu: chỉ thêm một bảng cục bộ, quan hệ chỉ so phần ngày và variation.
        #expect(templates(after) == templates(base))
        #expect(locals(after).count == locals(base).count + 1)
        let v = try #require(after.variations.first { $0.table == "Orders" })
        #expect(v.column == "OrderDate" && v.hierarchy.name == "Date Hierarchy" && v.isDefault)
        #expect(v.hierarchy.table == "LocalDateTable_00000000-0000-0000-0000-000000000001")
        let r = try #require(after.dateTableRelationships.first { $0.name == v.relationship })
        #expect(r.name == "00000000-0000-0000-0000-000000000002")
        #expect(r.fromTable == "Orders" && r.fromColumn == "OrderDate" && r.toColumn == "Date" && r.joinOnDateBehavior == 2 && r.isActive)
        #expect(after.calculatedTableExpressions[v.hierarchy.table] == "Calendar(Date(Year(MIN('Orders'[OrderDate])), 1, 1), Date(Year(MAX('Orders'[OrderDate])), 12, 31))")
        // Bảng cục bộ ẩn khỏi người dùng, cột theo mẫu.
        #expect(!after.userTables.contains { $0.name == v.hierarchy.table })
        let columns = after.columns.filter { $0.tableName == v.hierarchy.table && $0.kind != .rowNumber }
        #expect(columns.map(\.name) == AutoDateTime.columns.map(\.name))
        #expect(columns.allSatisfy { $0.isHidden && $0.summarizeBy == 2 })
        #expect(columns.first { $0.name == "Month" }?.sortByColumnID == columns.first { $0.name == "MonthNo" }?.id)
    }

    @Test(.enabled(if: f11 != nil))
    func cotNgayAnHoacBangDanhDauNgayKhongSinh() throws {
        let base = try model(try #require(Self.f11))
        let edits: [ModelEdit] = [.addTable(table("Orders", [("OrderDate", .dateTime)])),
                                  .updateColumn(table: "Orders", name: "OrderDate", patch: ColumnPatch(isHidden: true))]
        // Ẩn trong cùng lô: không sinh (chỉ cột không ẩn).
        #expect(AutoDateTime.expand(edits, model: base) == edits)
        // Không có cột ngày: không thêm gì.
        let plain: [ModelEdit] = [.addTable(table("Plain", [("Id", .int64)]))]
        #expect(AutoDateTime.expand(plain, model: base) == plain)
        // Tuỳ chọn tắt: không thêm gì.
        let off = try base.applying(ModelEdits(AutoDateTime.toggle(enabled: false, model: base)))
        let one: [ModelEdit] = [.addTable(table("Orders", [("OrderDate", .dateTime)]))]
        #expect(AutoDateTime.expand(one, model: off) == one)
    }

    @Test(.enabled(if: f11 != nil))
    func xoaBangBoBoBangNgayVaBangMauKhiHet() throws {
        let base = try model(try #require(Self.f11))
        // Sales có hai cột ngày (hai bảng cục bộ); Customers còn một nên bảng mẫu ở lại. Quan hệ thường của Sales bỏ trước.
        let salesRelationships = base.relationships.filter { $0.fromTable == "Sales" || $0.toTable == "Sales" }.map { ModelEdit.deleteRelationship(name: $0.name) }
        let user = salesRelationships + [.dropTable(name: "Sales")]
        let edits = AutoDateTime.expand(user, model: base)
        let after = try base.applying(ModelEdits(edits))
        #expect(after.variations.map(\.table) == ["Customers"])
        #expect(locals(after).count == 1 && templates(after).count == 1)
        #expect(!after.tables.contains { $0.name == "Sales" })

        // Bỏ nốt Customers: bảng mẫu cũng đi.
        let customers = after.relationships.filter { $0.fromTable == "Customers" || $0.toTable == "Customers" }.map { ModelEdit.deleteRelationship(name: $0.name) }
        let last = try after.applying(ModelEdits(AutoDateTime.expand(customers + [.dropTable(name: "Customers")], model: after)))
        #expect(last.variations.isEmpty && locals(last).isEmpty && templates(last).isEmpty)
    }

    @Test(.enabled(if: f11 != nil))
    func doiTenCotNgayDungLaiBoBangNgay() throws {
        let base = try model(try #require(Self.f11))
        let v = try #require(base.variations.first { $0.table == "Customers" })
        let edits = AutoDateTime.expand([.updateColumn(table: "Customers", name: v.column, patch: ColumnPatch(name: "Ngày mới"))], model: base)
        let after = try base.applying(ModelEdits(edits))
        #expect(!after.tables.contains { $0.name == v.hierarchy.table })
        let added = try #require(after.variations.first { $0.table == "Customers" })
        #expect(added.column == "Ngày mới" && added.hierarchy.table != v.hierarchy.table)
        #expect(after.calculatedTableExpressions[added.hierarchy.table]?.contains("'Customers'[Ngày mới]") == true)
    }

    @Test(.enabled(if: f11 != nil))
    func tatRoiBatLai() throws {
        let base = try model(try #require(Self.f11))
        let off = try base.applying(ModelEdits(AutoDateTime.toggle(enabled: false, model: base)))
        #expect(off.variations.isEmpty && off.dateTableRelationships.isEmpty && locals(off).isEmpty && templates(off).isEmpty)
        #expect(off.modelAnnotations[AutoDateTime.modelAnnotation] == "0")
        #expect(off.userTables.map(\.name) == base.userTables.map(\.name) && off.relationships == base.relationships)

        let on = try off.applying(ModelEdits(AutoDateTime.toggle(enabled: true, model: off)))
        #expect(on.modelAnnotations[AutoDateTime.modelAnnotation] == "1")
        #expect(templates(on).count == 1)
        // Cùng các cột như Desktop đã sinh, GUID mới.
        #expect(Set(on.variations.map { "\($0.table)[\($0.column)]" }) == Set(base.variations.map { "\($0.table)[\($0.column)]" }))
        #expect(Set(locals(on)).isDisjoint(with: locals(base)))
    }

    /// Thêm bảng rồi xoá trong cùng phiên: bản gộp để lưu không còn gì của bảng lẫn bộ bảng ngày của nó.
    @Test(.enabled(if: f11 != nil))
    func themRoiXoaTrongPhienGopVeKhong() throws {
        let base = try model(try #require(Self.f11))
        var list = ModelEdits()
        for edit in AutoDateTime.expand([.addTable(table("Orders", [("OrderDate", .dateTime)]))], model: base) { list.append(edit) }
        let mid = try base.applying(list)
        for edit in AutoDateTime.expand([.dropTable(name: "Orders")], model: mid) { list.append(edit) }
        let end = try base.applying(list)
        #expect(end.variations == base.variations && Set(locals(end)) == Set(locals(base)))
        #expect(list.collapsingTableEdits().isEmpty)
    }
}

/// Luồng đủ trên tài liệu mới (bật tuỳ chọn): nạp bảng có cột ngày giờ, engine tính bảng ngày cục bộ, lưu rồi mở lại.
@Suite("Đợt tồn đọng sau Phase F: Auto date/time trong phiên", .serialized) @MainActor struct AutoDateTimeFlowTests {
    /// Ngày (số ngày từ 1899-12-30) cho `yyyy-mm-dd` cộng phần giờ.
    private func serial(_ y: Int, _ m: Int, _ d: Int, hours: Double = 0) -> Double {
        var c = DateComponents(); c.year = y; c.month = m; c.day = d
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "UTC")!
        let epoch = calendar.date(from: DateComponents(year: 1899, month: 12, day: 30))!
        return calendar.dateComponents([.day], from: epoch, to: calendar.date(from: c)!).day.map(Double.init)! + hours / 24
    }

    private func count(_ result: QueryResult) -> Int? {
        if case .integer(let i)? = result.tables.first?.rows.first?.first { return Int(i) }
        return nil
    }

    @Test func napBangTinhBangNgayLuuMoLai() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("autodate-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let untitled = try UntitledDocuments.create(root: root)
        let state = DocumentState(workspace: try Workspace(data: Data(contentsOf: untitled)), fileName: untitled.lastPathComponent, fileURL: untitled)
        #expect(state.fileOptions.autoDateTime)   // tài liệu mới bật sẵn (T033)

        // OrderDate có phần giờ; Shipped toàn BLANK.
        let data = try TableData(columns: [
            TableColumn(name: "Id", data: ColumnBuilder.integers([1, 2, 3])),
            TableColumn(name: "OrderDate", data: ColumnBuilder.dateTimes([serial(2024, 3, 5, hours: 10.5), serial(2025, 11, 1), nil])),
            TableColumn(name: "Shipped", data: ColumnBuilder.dateTimes([nil, nil, nil])),
        ])
        #expect(state.loadFromGetData([LoadedTable(name: "Orders", data: data)]) == nil)
        let metadata = try #require(state.workspace.metadata)
        #expect(metadata.variations.map(\.column).sorted() == ["OrderDate", "Shipped"])
        #expect(metadata.tables.filter { AutoDateTime.isTemplateTable($0.name) }.count == 1)
        #expect(state.workspace.runtime?.calculationErrors.isEmpty == true, "\(state.workspace.runtime?.calculationErrors ?? [:])")

        // Lịch đủ hai năm 2024–2025 (731 ngày); cột toàn BLANK cho một năm (365 ngày). Đếm bỏ dòng BLANK ảo (dòng Orders
        // không có ngày không khớp bảng ngày nên bảng ngày có dòng trống, như mọi bảng phía một).
        let order = try #require(metadata.variations.first { $0.column == "OrderDate" }).hierarchy.table
        let shipped = try #require(metadata.variations.first { $0.column == "Shipped" }).hierarchy.table
        let engine = try await state.workspace.daxEngine()
        #expect(count(try await engine.execute("EVALUATE ROW(\"n\", COUNTROWS(ALLNOBLANKROW('\(order)')))")) == 731)
        #expect(count(try await engine.execute("EVALUATE ROW(\"n\", COUNTROWS(ALLNOBLANKROW('\(shipped)')))")) == 365)
        // [SUY ĐOÁN, kiểm ở gate T037] Cột toàn BLANK: YEAR(BLANK) = 1899 và DATE cộng 1900 cho năm dưới 1900 nên lịch là năm 3799.
        let minYear = try await engine.execute("EVALUATE ROW(\"n\", MIN('\(shipped)'[Year]))")
        #expect(count(minYear) == count(try await engine.execute("EVALUATE ROW(\"n\", YEAR(DATE(YEAR(BLANK()), 1, 1)))")))

        // Quan hệ chỉ so phần ngày: đơn 10:30 ngày 5/3/2024 lọc được theo năm, tháng của bảng ngày.
        #expect(count(try await engine.execute("EVALUATE ROW(\"n\", CALCULATE(COUNTROWS(Orders), '\(order)'[Year] = 2024))")) == 1)
        #expect(count(try await engine.execute("EVALUATE ROW(\"n\", CALCULATE(COUNTROWS(Orders), '\(order)'[Month] = \"March\"))")) == 1)
        #expect(count(try await engine.execute("EVALUATE ROW(\"n\", CALCULATE(COUNTROWS(Orders), '\(order)'[Year] = 2025))")) == 1)

        // Lưu lần đầu rồi mở lại: variation, quan hệ và bảng ngày còn nguyên.
        let destination = root.appendingPathComponent("auto-date.pbix")
        #expect(try DocumentSaver.saveUntitled(editor: state.layout, source: untitled, to: destination, readOnlyRoots: [],
                                               backupDirectory: root.appendingPathComponent("Backups")).didWrite)
        let reopened = try Workspace(data: Data(contentsOf: destination))
        let back = try #require(reopened.metadata)
        #expect(back.modelAnnotations[AutoDateTime.modelAnnotation] == "1")
        #expect(Set(back.variations) == Set(metadata.variations))
        #expect(back.dateTableRelationships.count == 2 && back.dateTableRelationships.allSatisfy { $0.joinOnDateBehavior == 2 })
        #expect(back.userTables.map(\.name) == ["Orders"])
        let reEngine = try await reopened.daxEngine()
        #expect(count(try await reEngine.execute("EVALUATE ROW(\"n\", COUNTROWS(ALLNOBLANKROW('\(order)')))")) == 731)

        // Hoàn tác lần nạp: bảng cùng bộ bảng ngày biến mất (một bước).
        state.layout.undo()
        #expect(state.workspace.metadata?.variations.isEmpty == true)
    }

    /// Ca biên: ngày 1/1/1900 và 31/12/9999 trong cùng cột: lịch đủ 8 100 năm như Desktop sinh theo biểu thức (không giới hạn khoảng).
    @Test(.enabled(if: F2Fixtures.heavy)) func khoangNam1900Den9999() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("autodate-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let untitled = try UntitledDocuments.create(root: root)
        let state = DocumentState(workspace: try Workspace(data: Data(contentsOf: untitled)), fileName: untitled.lastPathComponent, fileURL: untitled)
        #expect(state.fileOptions.autoDateTime)   // tài liệu mới bật sẵn (T033)
        let data = try TableData(columns: [TableColumn(name: "D", data: ColumnBuilder.dateTimes([serial(1900, 1, 1), serial(9999, 12, 31)]))])
        #expect(state.loadFromGetData([LoadedTable(name: "T", data: data)]) == nil)
        let local = try #require(state.workspace.metadata?.variations.first).hierarchy.table
        let engine = try await state.workspace.daxEngine()
        #expect(state.workspace.runtime?.calculationErrors.isEmpty == true)
        let days = Int(serial(9999, 12, 31) - serial(1900, 1, 1)) + 1
        #expect(count(try await engine.execute("EVALUATE ROW(\"n\", COUNTROWS(ALLNOBLANKROW('\(local)')))")) == days)
        #expect(count(try await engine.execute("EVALUATE ROW(\"n\", MAX('\(local)'[Year]))")) == 9999)
    }

    /// Lần lưu thứ hai trong phiên: thêm bảng có cột ngày, rồi xoá bảng cũ (bộ bảng ngày của nó đi theo), tắt rồi bật lại không đổi gì.
    @Test func luuLanHaiGiuBoBangNgay() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("autodate-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let untitled = try UntitledDocuments.create(root: root)
        let state = DocumentState(workspace: try Workspace(data: Data(contentsOf: untitled)), fileName: untitled.lastPathComponent, fileURL: untitled)
        #expect(state.fileOptions.autoDateTime)   // tài liệu mới bật sẵn (T033)
        func table(_ name: String, year: Int) throws -> LoadedTable {
            LoadedTable(name: name, data: try TableData(columns: [TableColumn(name: "Ngày", data: ColumnBuilder.dateTimes([serial(year, 6, 1)]))]))
        }
        #expect(state.loadFromGetData([try table("A", year: 2020)]) == nil)
        let destination = root.appendingPathComponent("b.pbix")
        let first = try DocumentSaver.saveUntitled(editor: state.layout, source: untitled, to: destination, readOnlyRoots: [],
                                                   backupDirectory: root.appendingPathComponent("Backups"))
        #expect(first.didWrite)

        #expect(state.loadFromGetData([try table("B", year: 2021)]) == nil)
        #expect(state.modelEditor.apply(.dropTable(name: "A")) == nil)
        let model = try #require(state.workspace.metadata)
        #expect(state.modelEditor.apply(AutoDateTime.toggle(enabled: false, model: model)) == nil)
        #expect(state.applyFileOptions(FileOptions(autoDateTime: true, autodetectRelationships: true)) == nil)
        let second = try DocumentSaver.save(editor: state.layout, source: destination, to: destination, expectedStamp: first.newStamp,
                                            readOnlyRoots: [], backupDirectory: root.appendingPathComponent("Backups"))
        #expect(second.didWrite)
        let back = try #require(try Workspace(data: Data(contentsOf: destination)).metadata)
        #expect(back.userTables.map(\.name) == ["B"])
        #expect(back.variations.map { "\($0.table)[\($0.column)]" } == ["B[Ngày]"])
        #expect(back.tables.filter { AutoDateTime.isLocalTable($0.name) }.count == 1)
        #expect(back.tables.filter { AutoDateTime.isTemplateTable($0.name) }.count == 1)
        #expect(back.modelAnnotations[AutoDateTime.modelAnnotation] == "1")
    }
}
