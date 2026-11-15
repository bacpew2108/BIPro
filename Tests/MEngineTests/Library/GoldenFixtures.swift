// Phase F (T050): trợ giúp test cho thư viện M (lead viết, gói F-MFUN dùng, không sửa). Golden Desktop 2.159 ở
// `docs/phase-f-evidence/vm-f3/golden/`. Dữ liệu nguồn: `build/f-out/samples/sales_2026.xlsx` (trang `Sales`); thiếu thì test bỏ qua.
import Foundation
import Connectors
import ColumnStore
@testable import MEngine

enum GoldenFixtures {
    static let root: URL = {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) { return url }
            url.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }()

    static var salesWorkbook: URL? {
        let url = root.appendingPathComponent("build/f-out/samples/sales_2026.xlsx")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func golden(_ name: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent("docs/phase-f-evidence/vm-f3/golden/\(name)"), encoding: .utf8)
    }

    /// File TSV golden thành (tên cột, các hàng chuỗi). Ô rỗng giữ là "".
    static func tsv(_ name: String) throws -> (header: [String], rows: [[String]]) {
        let lines = try golden(name).split(whereSeparator: \.isNewline).map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
        return (lines[0], Array(lines.dropFirst()))
    }

    /// Trang `Sales` đã dò kiểu (tương đương `#"Promoted Headers"` trong golden: tiêu đề đã thăng, giá trị đã đọc theo ô Excel).
    /// Cột: OrderID, OrderDate (dateTime), Region, CustomerID, Product, Qty, Price, Amount; 500 dòng.
    static func salesPromoted() async throws -> TableData? {
        guard let url = salesWorkbook else { return nil }
        let items = try await ExcelSource(url: url, options: .init(promoteHeaders: true, detectTypes: true)).items()
        guard let sheet = items.first(where: { $0.name == "Sales" && $0.kind == .sheet }) else { return nil }
        return try await sheet.load(progress: nil)
    }

    /// Chạy M của golden (`chuoi-1.m` hoặc `chuoi-2.m`): bỏ ba dòng `Source`, `Sales_Sheet`, `#"Promoted Headers"` (đã thay bằng bảng
    /// `salesPromoted()` gán vào tên `Promoted Headers`), giữ nguyên các bước còn lại; `upTo` dừng ở một bước.
    static func run(_ goldenFile: String, upTo step: String? = nil) async throws -> MValue? {
        guard let promoted = try await salesPromoted() else { return nil }
        let source = try golden(goldenFile).split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.contains("Source = Excel.Workbook") && !$0.contains("Sales_Sheet =") && !$0.contains("#\"Promoted Headers\" =") }
            .joined(separator: "\n")
        let env = MEnvironment(bindings: ["Promoted Headers": .table(promoted)])
        return try await MEvaluator(environment: env).evaluate(source: source, upTo: step, rowLimit: nil)
    }
}
