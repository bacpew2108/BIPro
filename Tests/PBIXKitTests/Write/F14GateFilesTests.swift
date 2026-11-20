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
            let saved = VertiPaqWriter.segmentSizeForNewTables
            VertiPaqWriter.segmentSizeForNewTables = size
            defer { VertiPaqWriter.segmentSizeForNewTables = saved }
            var changes = PBIXChanges()
            changes.modelEdits.append(.addTable(table))
            try PBIXWriter.build(source: base, changes: changes).data.write(to: out.appendingPathComponent(name))
        }
    }

    /// T068: thêm rồi sửa cột tính toán trên bảng nhiều đoạn do Desktop ghi (`f14-mid-desktop.pbix`, 3 đoạn).
    @Test func cotTinhToanTrenBangNhieuDoanDesktop() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let out = root.appendingPathComponent("build/f2-out/f14")
        let desktop = out.appendingPathComponent("f14-mid-desktop.pbix")
        guard FileManager.default.fileExists(atPath: desktop.path) else { return }

        let (abf, _) = try PBIXFile(url: desktop).loadDataModel()
        let model = try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb"))
        let cols = Dictionary(uniqueKeysWithValues: try VertiPaq.decodeTable("mid", metadata: model, abf: abf).map { ($0.name, $0) })
        let grp = try #require(cols["Grp"]), lo = try #require(cols["Lo"])
        let n = grp.count
        #expect(n == 2_500_000)
        var addVals: [Int64?] = []
        var editVals: [Int64?] = []
        addVals.reserveCapacity(n); editVals.reserveCapacity(n)
        for i in 0..<n {
            guard case .int(let g) = grp[i], case .int(let l) = lo[i] else { addVals.append(nil); editVals.append(nil); continue }
            addVals.append(g + l * 10)
            editVals.append(g * 2 + l)
        }

        let addedURL = out.appendingPathComponent("bipro-t068-add.pbix")
        var addChanges = PBIXChanges()
        addChanges.modelEdits.append(.addCalculatedColumn(table: "mid", name: "Tong", expression: "[Grp] + [Lo] * 10", dataType: .int64))
        addChanges.calculatedData = ["mid[Tong]": .int64(addVals)]
        try PBIXWriter.build(source: desktop, changes: addChanges).data.write(to: addedURL)

        let editedURL = out.appendingPathComponent("bipro-t068-edit.pbix")
        var editChanges = PBIXChanges()
        editChanges.modelEdits.append(.updateCalculatedColumn(table: "mid", name: "Tong", expression: "[Grp] * 2 + [Lo]", dataType: .int64))
        editChanges.calculatedData = ["mid[Tong]": .int64(editVals)]
        try PBIXWriter.build(source: addedURL, changes: editChanges).data.write(to: editedURL)

        // Kiểm đọc lại trong BI Pro khớp từng đoạn và từng ô.
        for (url, expected) in [(addedURL, addVals), (editedURL, editVals)] {
            let (abf2, _) = try PBIXFile(url: url).loadDataModel()
            let m2 = try ModelMetadata(sqlite: try abf2.contents(named: "metadata.sqlitedb"))
            let s = try #require(m2.storage(table: "mid", column: "Tong"))
            let segs = try VertiPaq.parseIDFMeta(Data(try abf2.contents(named: s.idfFiles[0] + "meta")), file: "m")
            #expect(segs.map(\.records) == [1_048_576, 1_048_576, 402_848])
            let decoded = try VertiPaq.decodeColumn(s, abf: abf2)
            for i in [0, 1, 1_048_575, 1_048_576, 2_097_151, 2_097_152, n - 1] {
                #expect(decoded[i] == .int(expected[i]!), "dòng \(i)")
            }
        }
    }
}
