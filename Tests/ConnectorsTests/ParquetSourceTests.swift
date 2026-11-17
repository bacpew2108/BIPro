// Phase F, T089: nguồn Parquet tự viết. Tệp do pyarrow sinh (`scripts/f-samples/make_parquet.py`, công cụ chuẩn, không phải mã BI Pro):
// - `sales_2026.parquet` cùng dữ liệu với `sales_2026.csv` (cùng seed) → so từng ô với CSV đọc bằng `CSVSource`;
// - `parquet/types_*.parquet` cùng một bảng, mỗi tệp một cách mã hoá/nén → mọi biến thể giải ra như nhau; vài ô đối chiếu số viết tay từ công
//   thức sinh dữ liệu; ZSTD báo chưa hỗ trợ.
// Đối chiếu với bảng Desktop nạp (golden thật) ở `BIProTests/Query/ParquetGoldenTests`. Thiếu tệp mẫu thì bỏ qua.
import ColumnStore
import Foundation
import Testing
@testable import Connectors

@Suite struct ParquetSourceTests {
    private func load(_ name: String) async throws -> TableData? {
        guard let url = FFixtures.sample(name) else { return nil }
        let item = try #require(try await ParquetSource(url: url).items().first)
        return try await item.load(progress: nil)
    }

    private func cells(_ t: TableData, _ column: String) -> [StoredValue] {
        let c = t.index(ofColumn: column)!
        return (0..<t.rowCount).map { t.value(row: $0, column: c) }
    }

    @Test func salesKhopCSVCungDuLieu() async throws {
        guard let parquet = try await load("sales_2026.parquet"), let csvURL = FFixtures.sample("sales_2026.csv") else { return }
        let csvItem = try #require(try await CSVSource(url: csvURL).items().first)
        let csv = try await csvItem.load(progress: nil)
        #expect(parquet.rowCount == 10_000)
        #expect(parquet.columns.map(\.name) == ["OrderID", "OrderDate", "Region", "CustomerID", "Product", "Qty", "Price", "Amount"])
        #expect(parquet.columns.map(\.data.type) == [.integer, .dateTime, .string, .integer, .string, .integer, .double, .double])
        for name in ["OrderID", "OrderDate", "Region", "CustomerID", "Product", "Qty", "Price", "Amount"] {
            let ours = cells(parquet, name), theirs = cells(csv, name)
            #expect(ours == theirs, Comment(rawValue: name))
        }
        // 2026-03-02 (dòng 1 của CSV) = serial 46083.
        #expect(cells(parquet, "OrderDate").first == .dateTime(46_083))
    }

    @Test func moiBienTheMaHoaVaNenGiaiRaNhuNhau() async throws {
        guard let base = try await load("parquet/types_snappy.parquet") else { return }
        #expect(base.rowCount == 1000)
        #expect(base.columns.map(\.data.type) == [.integer, .integer, .boolean, .double, .double, .string, .dateTime, .dateTime, .dateTime, .double, .double])
        for variant in ["types_gzip", "types_plain", "types_v2", "types_groups"] {
            let other = try #require(try await load("parquet/\(variant).parquet"))
            #expect(other.rowCount == 1000)
            for column in base.columns.map(\.name) {
                #expect(cells(other, column) == cells(base, column), Comment(rawValue: "\(variant).\(column)"))
            }
        }
    }

    /// Ô viết tay từ công thức của `types_table` (i là chỉ số dòng 0…).
    @Test func oDoiChieuCongThucSinh() async throws {
        guard let t = try await load("parquet/types_snappy.parquet") else { return }
        let start = 46_023.0 + 8.5 / 24   // 2026-01-01 08:30
        // i = 0: mọi cột có điều kiện null đều null; Big = -600000000 / 10^4.
        #expect(cells(t, "Small")[0] == .blank && cells(t, "Flag")[0] == .blank && cells(t, "Name")[0] == .blank && cells(t, "Money")[0] == .blank)
        #expect(cells(t, "Big")[0] == .double(-60_000))
        #expect(cells(t, "StampMs")[0] == .dateTime(start))
        // i = 1.
        #expect(cells(t, "Id")[1] == .integer(2))
        #expect(cells(t, "Small")[1] == .integer(-99))
        #expect(cells(t, "Flag")[1] == .boolean(false) && cells(t, "Flag")[3] == .boolean(true))
        #expect(cells(t, "Ratio")[1] == .double(0.125))
        #expect(cells(t, "Value")[1] == .double(-299.25))
        #expect(cells(t, "Name")[1] == .string("Tên 1 ✓") && cells(t, "Name")[29] == .string(""))
        #expect(cells(t, "Day")[1] == .dateTime(46_023))
        #expect(cells(t, "Money")[1] == .double(-398.63))
        #expect(cells(t, "Big")[1] == .double(-59_876.5433))
        guard case .dateTime(let us) = cells(t, "StampUs")[1] else { Issue.record("StampUs"); return }
        #expect(abs((us - start) * 86_400 - 1.00025) < 1e-6)   // + 1 giây 250 µs
    }

    @Test func xemTruocChiDocSoDongCan() async throws {
        guard let url = FFixtures.sample("parquet/types_groups.parquet") else { return }
        let item = try #require(try await ParquetSource(url: url).items().first)
        #expect(item.rowCountHint == 1000)
        #expect(item.columns?.count == 11)
        let preview = try await item.preview(limit: 200)   // nhiều row group 128 dòng
        #expect(preview.rowCount == 200)
        #expect(cells(preview, "Id").last == .integer(200))
    }

    @Test func zstdVaTepKhongPhaiParquetBaoLoiRo() async throws {
        if let url = FFixtures.sample("parquet/types_zstd.parquet") {
            let item = try #require(try await ParquetSource(url: url).items().first)
            await #expect(throws: SourceError.unsupported("Parquet nén ZSTD")) { _ = try await item.load(progress: nil) }
        }
        if let csv = FFixtures.sample("sales_100.csv") {
            await #expect(throws: SourceError.self) { _ = try await ParquetSource(url: csv).items() }
        }
    }
}
