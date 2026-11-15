// Phase F, T056: column profile ("dựa trên 1000 dòng đầu") và bộ nhớ đệm xem trước theo bước.
import Testing
import ColumnStore
@testable import MEngine

@Suite struct ColumnProfileTests {
    private func table(_ columns: [(String, ColumnData)], errors: [Int: [Int: String]] = [:]) throws -> TableData {
        try TableData(columns: columns.map { TableColumn(name: $0.0, data: $0.1) }, errorMask: errors)
    }

    @Test func soDemHopLeLoiTrongPhanBietDuyNhat() throws {
        let t = try table([("Qty", ColumnBuilder.integers([1, 2, 2, nil, 5])),
                           ("Name", ColumnBuilder.strings(["a", "", "a", nil, "b"]))],
                          errors: [0: [2: "DataFormat.Error"]])
        let stats = ColumnProfile.profile(t)
        #expect(stats.map(\.name) == ["Qty", "Name"])
        let qty = stats[0]
        // Dòng 2 của Qty là ô lỗi: không hợp lệ, không rỗng, không tính vào phân biệt.
        #expect((qty.valid, qty.error, qty.empty) == (3, 1, 1))
        #expect(qty.distinct == 4)   // 1, 2, 5 và null; ô lỗi không tính
        #expect(qty.min == .number(1) && qty.max == .number(5))
        #expect(qty.average == 8.0 / 3.0)
        let name = stats[1]
        #expect((name.valid, name.error, name.empty) == (3, 0, 2))   // "" và null đều là Empty
        #expect(name.distinct == 4 && name.unique == 3)               // "a"×2, "", null, "b"
        #expect(name.min == nil && name.average == nil)
    }

    @Test func chiLay1000DongDau() throws {
        let values = (0..<1500).map { Int64($0 % 10) }
        let stats = ColumnProfile.profile(try table([("N", ColumnBuilder.integers(values))]))[0]
        #expect(stats.valid == 1000 && stats.distinct == 10 && stats.unique == 0)
        #expect(stats.max == .number(9) && stats.average == 4.5)
        let all = ColumnProfile.profile(try table([("N", ColumnBuilder.integers(values))]), rowLimit: 1500)[0]
        #expect(all.valid == 1500)
    }

    @Test func phanBoSapTheoSoLanRoiTheoGiaTri() throws {
        let t = try table([("C", ColumnBuilder.strings(["b", "a", "b", "c", "b", "a"]))])
        let d = ColumnProfile.profile(t)[0].distribution
        #expect(d == [ValueCount(value: .text("b"), count: 3), ValueCount(value: .text("a"), count: 2), ValueCount(value: .text("c"), count: 1)])
    }

    @Test func ngayLaMinMaxNhungKhongCoTrungBinh() throws {
        let t = try table([("D", ColumnBuilder.dateTimes([46083, 46090, nil]))])
        let s = ColumnProfile.profile(t)[0]
        #expect(s.min == .dateTime(46083) && s.max == .dateTime(46090) && s.average == nil)
    }

    @Test func bangRongVaCotLogic() throws {
        let empty = try table([("A", ColumnBuilder.integers([]))])
        let s = ColumnProfile.profile(empty)[0]
        #expect((s.valid, s.error, s.empty, s.distinct, s.unique) == (0, 0, 0, 0, 0))
        #expect(s.min == nil)
        let b = ColumnProfile.profile(try table([("B", ColumnBuilder.booleans([true, false, true]))]))[0]
        #expect(b.distinct == 2 && b.unique == 1 && b.min == nil)
    }
}

@Suite struct PreviewCacheTests {
    private let query = MQuery(steps: [
        MStep(name: "Source", expression: "#table({\"A\"}, {{1}, {2}, {3}, {4}})"),
        MStep(name: "Doubled", expression: "Table.AddColumn(Source, \"B\", each [A] * 2)"),
        MStep(name: "Kept", expression: "Table.SelectRows(Doubled, each [B] > 2)"),
        MStep(name: "Reversed", expression: "Table.ReverseRows(Kept)"),
    ], resultName: "Reversed")

    private func rows(_ value: MValue) -> Int { if case .table(let t) = value { t.rowCount } else { -1 } }

    @Test func xemTruocTungBuocDungKetQua() async throws {
        let cache = MPreviewCache(environment: MEnvironment())
        #expect(rows(try await cache.preview(query, stepIndex: 0)) == 4)
        #expect(rows(try await cache.preview(query, stepIndex: 2)) == 3)
        let last = try await cache.preview(query, stepIndex: 3)
        guard case .table(let t) = last else { Issue.record("phải là bảng"); return }
        #expect(MTables.cell(t, row: 0, column: 0) == .number(4))
    }

    @Test func rowLimitCatXemTruocNhungKhongLamHongBuocSau() async throws {
        let cache = MPreviewCache(environment: MEnvironment())
        #expect(rows(try await cache.preview(query, stepIndex: 1, rowLimit: 2)) == 2)
        // Bước sau tính từ kết quả đầy đủ của bước trước, không từ 2 dòng đã cắt.
        #expect(rows(try await cache.preview(query, stepIndex: 2, rowLimit: 100)) == 3)
    }

    @Test func gapLaiBuocDaTinhKhongTinhLai() async throws {
        let cache = MPreviewCache(environment: MEnvironment())
        _ = try await cache.preview(query, stepIndex: 3)
        #expect(await cache.lastEvaluatedStepCount == 4)
        _ = try await cache.preview(query, stepIndex: 3)
        #expect(await cache.lastEvaluatedStepCount == 0)
        _ = try await cache.preview(query, stepIndex: 1)
        #expect(await cache.lastEvaluatedStepCount == 0)
    }

    @Test func doiMotBuocChiTinhLaiTuBuocDo() async throws {
        let cache = MPreviewCache(environment: MEnvironment())
        _ = try await cache.preview(query, stepIndex: 3)
        var changed = query
        changed.steps[2].expression = "Table.SelectRows(Doubled, each [B] > 4)"
        let value = try await cache.preview(changed, stepIndex: 3)
        #expect(rows(value) == 2)
        #expect(await cache.lastEvaluatedStepCount == 2)   // chỉ "Kept" và "Reversed"
    }

    @Test func buocLoiNemLoiVaKhongLamHongBoNho() async throws {
        let cache = MPreviewCache(environment: MEnvironment())
        var broken = query
        broken.steps[1].expression = "Table.AddColumn(Source, \"B\", each [Khong] * 2)"
        await #expect(throws: MError.self) { _ = try await cache.preview(broken, stepIndex: 3) }
        // Sửa lại thì chạy tiếp, bước Source vẫn dùng bản đã tính.
        #expect(rows(try await cache.preview(query, stepIndex: 3)) == 3)
        #expect(await cache.lastEvaluatedStepCount == 3)
    }

    @Test func buocNgoaiPhamViBaoLoi() async throws {
        let cache = MPreviewCache(environment: MEnvironment())
        await #expect(throws: MError.self) { _ = try await cache.preview(query, stepIndex: 9) }
    }
}
