// specs/011 US5: tệp thử gate VM-F14 khoanh lỗi DBCC của bảng nhiều đoạn (chỉ sinh tệp, chạy tay với BIPRO_F14_GATE=1).
import Foundation
import Testing
@testable import PBIXKit

@Suite(.enabled(if: ProcessInfo.processInfo.environment["BIPRO_F14_GATE"] == "1"), .serialized)
struct F14GateFilesTests {
    @Test func sinhTepNhieuDoanVaMotDoan() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let base = root.appendingPathComponent("build/f2-out/f15/bipro-f15.pbix")
        let out = root.appendingPathComponent("build/f2-out/f14")
        let n = 2_500_000
        let names = ["Bắc", "Trung", "Nam", "Tây", "Đông"]
        let table = NewTable(name: "mid", columns: [
            NewTableColumn(name: "Grp", values: .int64((0..<n).map { Int64($0 % 37) })),
            NewTableColumn(name: "Ten", values: .string((0..<n).map { names[$0 % 5] })),
            NewTableColumn(name: "Lo", values: .int64((0..<n).map { Int64($0 / 100_000) })),
        ])
        for (name, size) in [("bipro-f14-mid-nhieu.pbix", VertiPaqWriter.recordsPerSegment), ("bipro-f14-mid-mot.pbix", Int.max)] {
            VertiPaqWriter.segmentSizeForNewTables = size
            defer { VertiPaqWriter.segmentSizeForNewTables = Int.max }
            var changes = PBIXChanges()
            changes.modelEdits.append(.addTable(table))
            try PBIXWriter.build(source: base, changes: changes).data.write(to: out.appendingPathComponent(name))
        }
    }
}
