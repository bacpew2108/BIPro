// Đợt tồn đọng sau Phase F, T026: M mà hộp "Create Table" (Enter Data) của Desktop 2.159 sinh ra chạy được trong MEngine
// (VM-F11a, `docs/phase-f2-evidence/vm-f11/QUAN-SAT.md`). Hai nguồn đối chiếu độc lập:
// - bảng đã gõ vào Desktop (3 cột × 5 dòng: chữ Việt, số, ô trống), M nguyên văn ở `vm-f11/enter-data-table.m`;
// - dữ liệu Desktop lưu trong VertiPaq của `vm-f11/f11-desktop.pbix` cho cả `Table` và `Table (2)` (ngoài git, thiếu thì bỏ qua).
import ColumnStore
import Foundation
import PBIXKit
import Testing
@testable import MEngine

@Suite struct EnterDataMTests {
    private static let evidence = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("docs/phase-f2-evidence/vm-f11")
    private static let desktopFile: URL? = {
        let url = evidence.appendingPathComponent("f11-desktop.pbix")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }()

    private func eval(_ source: String) async throws -> MValue {
        try await MEvaluator(environment: MEnvironment()).evaluate(source: source, upTo: nil, rowLimit: nil)
    }

    private func table(_ source: String) async throws -> TableData {
        guard case .table(let table) = try await eval(source) else { throw MError.expression("không phải bảng") }
        return table
    }

    // MARK: Từng mảnh

    @Test func binaryFromTextVaDecompress() async throws {
        // "i1bKyFSKBQA=" là `["hi"]` nén Deflate thô (zlib, wbits -15), như phần nén của Enter Data.
        #expect(try await eval(#"Json.Document(Binary.Decompress(Binary.FromText("i1bKyFSKBQA=", BinaryEncoding.Base64), Compression.Deflate))"#)
                == .list([.text("hi")]))
        await #expect(throws: MError.self) { try await eval(#"Binary.FromText("@@", BinaryEncoding.Base64)"#) }
    }

    @Test func jsonDocumentNhanNhiPhan() async throws {
        #expect(try await eval(#"Json.Document(Binary.FromText("WzEsIngiXQ==", BinaryEncoding.Base64))"#)
                == .list([.number(1), .text("x")]))
    }

    @Test func tableFromRowsVoiTenCotVaKieu() async throws {
        let named = try await table(#"Table.FromRows({{1, "a"}, {2, "b"}}, {"N", "T"})"#)
        #expect(named.columns.map(\.name) == ["N", "T"])
        #expect(named.value(row: 1, column: 0) == .double(2) && named.value(row: 1, column: 1) == .string("b"))

        let typed = try await table(#"Table.FromRows({{"x"}}, type table [#"Cột A" = text])"#)
        #expect(typed.columns.map(\.name) == ["Cột A"])
        #expect(typed.value(row: 0, column: 0) == .string("x"))

        let numbered = try await table(#"Table.FromRows({{1, 2}})"#)
        #expect(numbered.columns.map(\.name) == ["Column1", "Column2"])
    }

    @Test func toanTuMetaGiuNguyenGiaTri() async throws {
        #expect(try await eval("1 meta [a = 1]") == .number(1))
        let typed = try await table(#"let _t = ((type nullable text) meta [Serialized.Text = true]) in Table.FromRows({{"x"}}, type table [A = _t])"#)
        #expect(typed.columns.map(\.name) == ["A"] && typed.value(row: 0, column: 0) == .string("x"))
    }

    // MARK: M nguyên văn của Desktop

    @Test func mEnterDataCuaDesktopRaDungBangDaGo() async throws {
        let source = try String(contentsOf: Self.evidence.appendingPathComponent("enter-data-table.m"), encoding: .utf8)
        let result = try await table(source)
        // U+FEFF đầu "Tên" có trong M do cách dán clipboard của buổi VM (QUAN-SAT mục a), giữ nguyên.
        #expect(result.columns.map(\.name) == ["\u{FEFF}Tên", "Số lượng", "Ghi chú"])
        #expect(result.rowCount == 5)
        let expected: [[StoredValue]] = [
            [.string("Áo thun"), .double(12), .string("mới")],
            [.string("Quần jean"), .double(5), .string("")],
            [.string("Giày"), .blank, .string("cũ")],
            [.string("Mũ"), .double(3.5), .string("đỏ")],
            [.string("Túi xách"), .double(-7), .string("x")],
        ]
        for (row, values) in expected.enumerated() {
            for (column, value) in values.enumerated() {
                #expect(result.value(row: row, column: column) == value, "dòng \(row) cột \(column)")
            }
        }
    }

    /// Chạy M lưu trong `Partition.QueryDefinition` của từng bảng Enter Data, so với giá trị Desktop đã lưu trong VertiPaq.
    @Test(.enabled(if: desktopFile != nil), arguments: ["Table", "Table (2)"])
    func mEnterDataRaDungDuLieuDesktopLuu(_ name: String) async throws {
        let file = try PBIXFile(data: try Data(contentsOf: try #require(Self.desktopFile), options: .alwaysMapped))
        let (abf, _) = try file.loadDataModel()
        let metadata = try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb"))
        let source = try #require(metadata.partitionQueries[name])
        let stored = try VertiPaq.decodeTable(name, metadata: metadata, abf: abf)
        let result = try await table(source)

        // Tên cột trong mô hình Desktop không có U+FEFF đầu dù M có (VM-F11a): bước nạp bỏ nó, MEngine giữ nguyên như M.
        #expect(result.columns.map { $0.name.hasPrefix("\u{FEFF}") ? String($0.name.dropFirst()) : $0.name } == stored.map(\.name))
        #expect(result.rowCount == stored.first?.count)
        for (column, decoded) in stored.enumerated() {
            for row in 0..<decoded.count {
                let expected: StoredValue = switch decoded[row] {
                case .null: .blank
                case .string(let s): .string(s)
                case .double(let d), .decimal(let d): .double(d)
                case .int(let i): .double(Double(i))
                case .bool(let b): .boolean(b)
                case .dateTime(let d): .dateTime(d)
                }
                #expect(result.value(row: row, column: column) == expected, "\(name) dòng \(row) cột \(decoded.name)")
            }
        }
    }
}
