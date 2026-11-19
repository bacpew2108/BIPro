// Đợt tồn đọng sau Phase F, T022 (US3): cột tính toán dùng hàm văn bản DAX mới (gói F2-DAXTEXT) trên bảng mẫu `text_cases.csv` của
// buổi VM-F12, lưu, mở lại; giá trị đã lưu bằng golden Desktop (`docs/phase-f2-evidence/vm-f12/golden.tsv`, các ca trên cột của
// bảng `HCol`, cùng biểu thức). Để lại `build/f2-out/f12/bipro-f12.pbix` cho gate T023. Thiếu mẫu hoặc golden thì bỏ qua.
import ColumnStore
import DAXEngine
import Foundation
import PBIXKit
import Testing
@testable import BIPro

@Suite("Đợt F2: cột tính toán dùng hàm văn bản", .enabled(if: F2Fixtures.sample("text_cases.csv") != nil
                                                          && F2Fixtures.desktop("vm-f12", "golden.tsv") != nil), .serialized)
@MainActor
struct F2TextCalcTests {
    /// Ca của golden (tên cột tính toán, biểu thức). Chỉ chọn ca không có ô lỗi: một ô lỗi làm hỏng cả cột tính toán.
    static let cases: [(name: String, expr: String)] = [
        ("UPPER-Txt", "UPPER([Txt])"),
        ("MID-2-3", "MID([Txt], 2, 3)"),
        ("SUBST-a", #"SUBSTITUTE([Txt], "a", "X")"#),
        ("SUBST-a-2", #"SUBSTITUTE([Txt], "a", "X", 2)"#),
        ("SUBST-nfd", ##"SUBSTITUTE([Nfd], UNICHAR(7897), "#")"##),
        ("LEN-Txt", "LEN([Txt])"),
        ("LOWER-Nfd", "LOWER([Nfd])"),
        ("TRIM-Txt", "TRIM([Txt])"),
        ("REPLACE-2-3", #"REPLACE([Txt], 2, 3, "__")"#),
        ("RIGHT-3", "RIGHT([Txt], 3)"),
        ("REPT-2", "REPT([Txt], 2)"),
        ("FIND-a", #"FIND("a", [Txt], 1, -1)"#),
        ("EXACT-Txt-Nfd", "EXACT([Txt], [Nfd])"),
        ("UNICODE-Txt", "UNICODE([Txt])"),
        ("FIXED-Num-1", "FIXED([Num], 1)"),
        ("COMBINE-Txt-Num", #"COMBINEVALUES("|", [Txt], [Num])"#),
    ]

    /// golden.tsv: Case, Table, ID, Expr, Result (thoát `\\`, `\t`, `\n`, `\r`).
    static func golden() throws -> [String: [Int: String]] {
        let text = try String(contentsOf: try #require(F2Fixtures.desktop("vm-f12", "golden.tsv")), encoding: .utf8)
        var result: [String: [Int: String]] = [:]
        for line in text.split(separator: "\n").dropFirst() {
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count == 5, f[1] == "HCol", let id = Int(f[2]) else { continue }
            result[f[0], default: [:]][id] = unescape(f[4])
        }
        return result
    }

    static func unescape(_ s: String) -> String {
        var out = "", it = s.makeIterator()
        while let c = it.next() {
            guard c == "\\", let n = it.next() else { out.append(c); continue }
            switch n { case "t": out.append("\t"); case "n": out.append("\n"); case "r": out.append("\r"); default: out.append(n) }
        }
        return out
    }

    /// Mã hoá giá trị như buổi VM-F12: `B`, `T:<chuỗi>`, `L:<TRUE|FALSE>`, `N:<số>` (số so theo giá trị).
    static func matches(_ value: Value, _ golden: String) -> Bool {
        switch value {
        case .blank: return golden == "B"
        case .string(let s): return golden == "T:" + s
        case .boolean(let b): return golden == "L:" + (b ? "TRUE" : "FALSE")
        case .integer(let v): return golden.hasPrefix("N:") && Double(golden.dropFirst(2)) == Double(v)
        case .double(let v): return golden.hasPrefix("N:") && Double(golden.dropFirst(2)).map { abs($0 - v) <= 1e-9 * max(1, abs(v)) } == true
        default: return false
        }
    }

    private func stored(_ workspace: Workspace, _ table: String, _ column: String) throws -> [Value] {
        let engine = try workspace.daxEngine()
        let id = try #require(engine.store.schema.column(table: table, name: column)?.id)
        let data = try engine.store.column(id)
        return (0..<(try engine.store.rowCount(id.table))).map { Value(stored: data.value(at: $0)) }
    }

    @Test func cotTinhToanHamVanBanLuuMoLaiBangGolden() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("f2text-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let untitled = try UntitledDocuments.create(root: root)
        let state = DocumentState(workspace: try Workspace(data: Data(contentsOf: untitled)), fileName: untitled.lastPathComponent, fileURL: untitled)

        // Nạp text_cases.csv như buổi VM-F12 (Get Data ▸ Text/CSV ▸ Load, không sửa gì).
        let csv = try #require(F2Fixtures.sample("text_cases.csv"))
        state.showGetData(kind: .csv, pickFile: { _ in csv.path })
        let navigator = try #require(state.getDataState)
        for _ in 0..<200 where navigator.phase == .choosingSource || navigator.phase == .listingItems { try await Task.sleep(for: .milliseconds(25)) }
        for item in navigator.items { navigator.toggle(item.id) }
        let loaded = try #require(await navigator.load(existingNames: state.existingTableNames))
        state.closeGetData()
        #expect(state.loadFromGetData(loaded) == nil)
        #expect(state.workspace.rowCount("text_cases") == 20)

        for c in Self.cases {
            #expect(await state.addCalculatedColumn(table: "text_cases", formula: "\(c.name) = \(c.expr)") == nil, "\(c.name)")
        }
        #expect(state.workspace.runtime?.calculationErrors.isEmpty == true, "\(state.workspace.runtime?.calculationErrors ?? [:])")

        let destination = try F2Fixtures.outputDirectory("f12").appendingPathComponent("bipro-f12.pbix")
        try? FileManager.default.removeItem(at: destination)
        #expect(try DocumentSaver.saveUntitled(editor: state.layout, source: untitled, to: destination, readOnlyRoots: [],
                                               backupDirectory: root.appendingPathComponent("Backups")).didWrite)

        let reopened = try Workspace(data: Data(contentsOf: destination))
        let model = try #require(reopened.metadata)
        let golden = try Self.golden()
        let ids = try stored(reopened, "text_cases", "ID")
        var mismatches: [String] = []
        for c in Self.cases {
            #expect(model.columns.first { $0.tableName == "text_cases" && $0.name == c.name }?.kind == .calculated, "\(c.name)")
            let expected = try #require(golden[c.name], "\(c.name)")
            for (row, value) in try stored(reopened, "text_cases", c.name).enumerated() {
                guard case .integer(let id) = ids[row], let want = expected[Int(id)] else { mismatches.append("\(c.name)#?"); continue }
                if !Self.matches(value, want) { mismatches.append("\(c.name)#\(id): \(value) ≠ \(want)") }
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches.joined(separator: "\n"))")
    }
}
