// Phase F, T008: bộ file mẫu có mặt (nếu chưa sinh thì bỏ qua, không làm đỏ).
import Testing
import Foundation

@Suite struct FFixturesTests {
    @Test func rootHasPackageManifest() {
        #expect(FileManager.default.fileExists(atPath: FFixtures.root.appendingPathComponent("Package.swift").path))
    }

    @Test(.enabled(if: FFixtures.sample("sales_2026.csv") != nil, "chạy scripts/f-samples/make_samples.py trước"))
    func samplesAreGenerated() throws {
        for name in ["sales_2026.csv", "sales_2026.xlsx", "sales_2026.sqlite", "orders.json", "customers.csv", "sales_dirty.csv"] {
            #expect(FFixtures.sample(name) != nil, "thiếu \(name)")
        }
        let csv = try String(contentsOf: FFixtures.sample("sales_2026.csv")!, encoding: .utf8)
        #expect(csv.split(whereSeparator: \.isNewline).count == 10_001)   // tiêu đề + 10 000 dòng
    }
}
