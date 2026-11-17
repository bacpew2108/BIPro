// Phase F, T087: JSON và giá trị có cấu trúc trong M. Chuỗi bước giống Desktop sinh khi nạp JSON (`docs/phase-f-evidence/vm-f7/QUAN-SAT.md`);
// giá trị mong đợi viết tay từ văn bản JSON nhỏ trong test. Đối chiếu với kết quả Desktop trên `orders.json` ở `BIProTests/Query/JsonGoldenTests`.
import ColumnStore
import Testing
@testable import MEngine

@Suite struct JsonTests {
    private func eval(_ source: String) async throws -> MValue {
        try await MEvaluator(environment: MEnvironment()).evaluate(source: source, upTo: nil, rowLimit: nil)
    }

    private func table(_ source: String) async throws -> TableData {
        guard case .table(let t) = try await eval(source) else { throw MError.expression("kết quả không phải bảng") }
        return t
    }

    /// `"…"` của M: nhân đôi dấu ngoặc kép.
    private func m(_ text: String) -> String { "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }

    private let orders = #"[{"Id":1,"Customer":{"Name":"An","City":"HN"},"Lines":[{"Sku":"A","Qty":2},{"Sku":"B","Qty":1}],"Note":"x"},"#
        + #"{"Id":2,"Customer":{"Name":"Bình"},"Lines":[],"Note":null},"#
        + #"{"Id":3,"Customer":null,"Lines":[{"Sku":"C","Qty":5}]}]"#

    @Test func jsonDocumentGiuThuTuKhoaVaKieu() async throws {
        let value = try await eval("Json.Document(\(m(#"{"b":1.5,"a":[true,null,"xé\n"],"c":{}}"#)))")
        guard case .record(let fields) = value else { Issue.record("không phải bản ghi"); return }
        #expect(fields.map(\.name) == ["b", "a", "c"])
        guard case .number(1.5) = fields[0].value, case .list(let items) = fields[1].value, case .record(let inner) = fields[2].value else {
            Issue.record("sai kiểu: \(fields)"); return
        }
        #expect(inner.isEmpty)
        guard items.count == 3, case .logical(true) = items[0], case .null = items[1], case .text("xé\n") = items[2] else {
            Issue.record("sai phần tử: \(items)"); return
        }
    }

    @Test func jsonSaiBaoLoi() async {
        await #expect(throws: MError.self) { _ = try await self.eval("Json.Document(\(self.m(#"{"a":1,}"#)))") }
        await #expect(throws: MError.self) { _ = try await self.eval("Json.Document(\(self.m("[1, 2")))") }
    }

    /// Chuỗi bước như Desktop: đổi thành bảng, mở bản ghi (không tiền tố), mở Customer (tiền tố), danh sách thành dòng, mở bản ghi của dòng.
    @Test func chuoiBuocDesktopMoRongHet() async throws {
        let source = """
        let
            Source = Json.Document(\(m(orders))),
            #"Converted to Table" = Table.FromList(Source, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
            #"Expanded Column1" = Table.ExpandRecordColumn(#"Converted to Table", "Column1", {"Id", "Customer", "Lines", "Note"}, {"Id", "Customer", "Lines", "Note"}),
            #"Expanded Customer" = Table.ExpandRecordColumn(#"Expanded Column1", "Customer", {"Name", "City"}, {"Customer.Name", "Customer.City"}),
            #"Expanded Lines" = Table.ExpandListColumn(#"Expanded Customer", "Lines"),
            #"Expanded Lines1" = Table.ExpandRecordColumn(#"Expanded Lines", "Lines", {"Sku", "Qty"}, {"Lines.Sku", "Lines.Qty"}),
            #"Changed Type" = Table.TransformColumnTypes(#"Expanded Lines1",{{"Id", Int64.Type}, {"Customer.Name", type text}, {"Lines.Qty", Int64.Type}})
        in
            #"Changed Type"
        """
        let t = try await table(source)
        #expect(t.columns.map(\.name) == ["Id", "Customer.Name", "Customer.City", "Lines.Sku", "Lines.Qty", "Note"])
        // Đơn 1 có hai dòng hàng, đơn 2 danh sách rỗng (một dòng null), đơn 3 Customer null và không có Note.
        #expect(t.rowCount == 4)
        let ids = (0..<4).map { t.value(row: $0, column: 0) }
        #expect(ids == [.integer(1), .integer(1), .integer(2), .integer(3)])
        #expect((0..<4).map { t.value(row: $0, column: 1) } == [.string("An"), .string("An"), .string("Bình"), .blank])
        #expect((0..<4).map { t.value(row: $0, column: 2) } == [.string("HN"), .string("HN"), .blank, .blank])
        #expect((0..<4).map { t.value(row: $0, column: 3) } == [.string("A"), .string("B"), .blank, .string("C")])
        #expect((0..<4).map { t.value(row: $0, column: 4) } == [.integer(2), .integer(1), .blank, .integer(5)])
        #expect((0..<4).map { t.value(row: $0, column: 5) } == [.string("x"), .string("x"), .blank, .blank])
        #expect(t.structured.isEmpty)
    }

    @Test func bangCoOBanGhiGiuQuaChonVaDoiTenCot() async throws {
        let source = """
        let
            T = Table.FromRecords(Json.Document(\(m(orders))), null, MissingField.UseNull),
            R = Table.RenameColumns(Table.SelectColumns(T, {"Customer", "Id"}), {{"Customer", "Khách"}}),
            F = Table.FirstN(Table.Sort(R, {{"Id", Order.Descending}}), 2),
            E = Table.ExpandRecordColumn(F, "Khách", {"Name"})
        in
            E
        """
        let t = try await table(source)
        #expect(t.columns.map(\.name) == ["Name", "Id"])
        #expect((0..<2).map { t.value(row: $0, column: 0) } == [.blank, .string("Bình")])
    }

    @Test func oBanGhiHienChuRecordVaDoiKieuBaoLoi() async throws {
        let t = try await table("Table.FromList(Json.Document(\(m(orders))), Splitter.SplitByNothing())")
        #expect(t.columns.map(\.name) == ["Column1"])
        #expect(t.value(row: 0, column: 0) == .string("Record"))
        guard case .record(let fields) = MTables.cell(t, row: 2, column: 0) else { Issue.record("mất bản ghi"); return }
        #expect(fields.map(\.name) == ["Id", "Customer", "Lines"])
        await #expect(throws: MError.self) {
            _ = try await self.eval("Table.TransformColumnTypes(Table.FromList(Json.Document(\(self.m(self.orders))), Splitter.SplitByNothing()), {{\"Column1\", type text}})")
        }
    }

    @Test func fromListMacDinhTachDauPhayVaGiaTriThua() async throws {
        let t = try await table(#"Table.FromList({"a,b", "c", "d,e,f"}, null, {"X", "Y"}, "-", ExtraValues.Ignore)"#)
        #expect((0..<3).map { t.value(row: $0, column: 0) } == [.string("a"), .string("c"), .string("d")])
        #expect((0..<3).map { t.value(row: $0, column: 1) } == [.string("b"), .string("-"), .string("e")])
        let error = try await table(#"Table.FromList({"a,b", "c,d,e"}, null, 2)"#)
        #expect(error.error(row: 1, column: 1) != nil)
    }

    @Test func recordHam() async throws {
        let r = #"[a = 1, b = "x"]"#
        guard case .list(let names) = try await eval("Record.FieldNames(\(r))"), case .number(2) = try await eval("Record.FieldCount(\(r))"),
              case .text("x") = try await eval("Record.Field(\(r), \"b\")"), case .logical(false) = try await eval("Record.HasFields(\(r), {\"a\", \"z\"})")
        else { Issue.record("Record.* sai"); return }
        #expect(names.count == 2)
    }

    @Test func moBangTrongOCoCauTruc() async throws {
        let t = try await table(#"Table.ExpandTableColumn(Table.FromRecords({[K = 1, T = #table({"v"}, {{7}, {8}})], [K = 2, T = null]}), "T", {"v"})"#)
        #expect(t.rowCount == 3)
        #expect((0..<3).map { t.value(row: $0, column: 1) } == [.double(7), .double(8), .blank])
    }
}
