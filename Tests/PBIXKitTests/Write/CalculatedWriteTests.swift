// Phase F, T084: ghi cột tính toán vào bảng đã có của file Desktop và ghi bảng tính toán, rồi đọc lại từng ô bằng bộ giải mã.
// Dạng dòng siêu dữ liệu theo file Desktop (`docs/phase-f-evidence/vm-f6/QUAN-SAT.md`). Chạy trên `tuan6.2.pbix` (bảng Marketing 1363 dòng).
import Foundation
import Testing
@testable import PBIXKit

@Suite(.enabled(if: FileManager.default.fileExists(atPath: DesktopGolden.path.path))) struct CalculatedWriteTests {
    private func build(_ edits: [ModelEdit], calculated: [String: VertiPaqWriter.Values]) throws -> Data {
        var changes = PBIXChanges()
        for edit in edits { changes.modelEdits.append(edit) }
        changes.calculatedData = calculated
        return try PBIXWriter.build(source: DesktopGolden.path, changes: changes).data
    }

    private func open(_ data: Data) throws -> (ABFBackup, ModelMetadata) {
        let (abf, _) = try PBIXFile(data: data).loadDataModel()
        return (abf, try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb")))
    }

    @Test func cotTinhToanVaoBangDaCoDocLaiDungTungO() throws {
        let values: [Int64?] = (0..<1363).map { $0 % 11 == 0 ? nil : Int64($0 % 7) }
        let data = try build([.addCalculatedColumn(table: "Marketing", name: "Nhóm", expression: "MOD(1, 7)", dataType: .int64)],
                             calculated: ["Marketing[Nhóm]": .int64(values)])
        let (abf, metadata) = try open(data)
        let column = try #require(metadata.columns.first { $0.tableName == "Marketing" && $0.name == "Nhóm" })
        #expect(column.kind == .calculated && column.expression == "MOD(1, 7)" && column.dataType == .int64)
        let decoded = Dictionary(uniqueKeysWithValues: try VertiPaq.decodeTable("Marketing", metadata: metadata, abf: abf).map { ($0.name, $0) })
        let nhom = try #require(decoded["Nhóm"])
        #expect(nhom.count == 1363)
        #expect((0..<1363).allSatisfy { nhom[$0] == (values[$0].map { .int($0) } ?? .null) })
        // Cột cũ của bảng vẫn đọc đủ.
        #expect(decoded.values.allSatisfy { $0.count == 1363 })
    }

    @Test func cotChuoiVaBangTinhToan() throws {
        let labels: [String?] = (0..<1363).map { $0 % 3 == 0 ? "Ba" : ($0 % 3 == 1 ? "Một" : nil) }
        let days: [Double?] = (0..<10).map { 45_292 + Double($0) }
        let data = try build([
            .addCalculatedColumn(table: "Marketing", name: "Nhãn", expression: "\"x\"", dataType: .string),
            .addCalculatedTable(name: "Lịch", expression: "CALENDAR(DATE(2024,1,1), DATE(2024,1,10))",
                                columns: [ColumnSignature(name: "Date", dataType: .dateTime)]),
        ], calculated: ["Marketing[Nhãn]": .string(labels), "Lịch[Date]": .dateTime(days)])
        let (abf, metadata) = try open(data)
        let table = try #require(metadata.tables.first { $0.name == "Lịch" })
        #expect(table.isCalculatedUserTable && table.systemFlags == 2)
        #expect(metadata.calculatedTableExpressions["Lịch"] == "CALENDAR(DATE(2024,1,1), DATE(2024,1,10))")
        #expect(metadata.partitionQueries["Lịch"] == nil)
        let dateColumn = try #require(metadata.columns.first { $0.tableName == "Lịch" && $0.name == "Date" })
        #expect(dateColumn.kind == .calculatedTableColumn && dateColumn.dataType == .dateTime && dateColumn.sourceColumn == "[Date]")
        let lich = try #require(try VertiPaq.decodeTable("Lịch", metadata: metadata, abf: abf).first { $0.name == "Date" })
        #expect((0..<10).map { lich[$0] } == days.map { .dateTime($0!) })
        let nhan = try #require(try VertiPaq.decodeTable("Marketing", metadata: metadata, abf: abf).first { $0.name == "Nhãn" })
        #expect((0..<1363).allSatisfy { nhan[$0] == (labels[$0].map { .string($0) } ?? .null) })
        // Bảng tính toán không phải truy vấn: không vào thứ tự truy vấn.
        #expect(metadata.modelAnnotations["PBI_QueryOrder"]?.contains("Lịch") != true)
    }

    @Test func thieuGiaTriDaTinhThiTuChoi() {
        #expect(throws: (any Error).self) {
            _ = try build([.addCalculatedColumn(table: "Marketing", name: "X", expression: "1", dataType: .int64)], calculated: [:])
        }
    }
}
