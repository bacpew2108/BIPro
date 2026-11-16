// Phase F, T067/T068: golden Desktop 2.159 (VM-F4, 2026-11-16) cho Join, Group, Pivot, Unpivot, Combine. Cùng đoạn M chạy trong Power Query của
// Desktop (probe `docs/phase-f-evidence/vm-f4/golden/p1..p5.m`, bảng nhỏ viết tay) và ở đây; kỳ vọng chép từ màn hình Desktop.
// Mỗi dòng kết quả là "tên thí nghiệm" + `n=<số dòng> cols=<cột>` rồi từng dòng `giá trị,giá trị` (`~` = null).
import Foundation
import Testing
import ColumnStore
@testable import MEngine

@Suite struct DesktopProbeTests {
    private func probe(_ name: String) async throws -> [String: [String]] {
        let url = GoldenFixtures.root.appendingPathComponent("docs/phase-f-evidence/vm-f4/golden/\(name).m")
        let source = try String(contentsOf: url, encoding: .utf8)
        guard case .table(let table) = try await MEvaluator(environment: MEnvironment()).evaluate(source: source) else {
            throw MError.expression("probe \(name) không trả bảng")
        }
        var result: [String: [String]] = [:]
        for row in 0..<table.rowCount {
            guard case .string(let exp) = table.value(row: row, column: 0) else { continue }
            if table.error(row: row, column: 1) != nil { result[exp, default: []].append("Error"); continue }   // Desktop hiện ô lỗi là "Error"
            guard case .string(let line) = table.value(row: row, column: 1) else { continue }
            result[exp, default: []].append(line)
        }
        return result
    }

    private func expect(_ got: [String: [String]], _ name: String, _ lines: [String], sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(got[name] == lines, "\(name)", sourceLocation: sourceLocation)
    }

    @Test func p1JoinKinds() async throws {
        let got = try await probe("p1")
        let head = "cols=ID|Name|OID|Cust"
        expect(got, "inner", ["n=3 \(head)", "1,An,10,1", "1,An,11,1", "~,Zed,13,~"])
        expect(got, "left", ["n=4 \(head)", "1,An,10,1", "1,An,11,1", "~,Zed,13,~", "2,Bi,~,~"])
        expect(got, "right", ["n=4 \(head)", "1,An,10,1", "1,An,11,1", "~,Zed,13,~", "~,~,12,9"])
        expect(got, "full", ["n=5 \(head)", "1,An,10,1", "1,An,11,1", "~,Zed,13,~", "~,~,12,9", "2,Bi,~,~"])
        expect(got, "lanti", ["n=1 \(head)", "2,Bi,~,~"])
        expect(got, "ranti", ["n=1 \(head)", "~,~,12,9"])
        expect(got, "nRight", ["n=4 cols=ID|Name|OID", "1,An,10", "1,An,11", "~,Zed,13", "~,~,12"])
        #expect(got["nFull"]?.count == 6)   // n=5 + 5 dòng (Desktop: dòng đầu "1,An,10", "1,An,11"; phần còn lại chưa đọc)
        #expect(got["nFull"]?.prefix(3).elementsEqual(["n=5 cols=ID|Name|OID", "1,An,10", "1,An,11"]) == true)
    }

    @Test func p2GroupAndErrors() async throws {
        let got = try await probe("p2")
        expect(got, "grpGlobal", ["n=4 cols=Reg|Sum|N", "N,4,2", "S,7,2", "E,4,1", "~,13,2"])
        expect(got, "grpLocal", ["n=6 cols=Reg|N", "N,1", "S,1", "N,1", "E,1", "S,1", "~,2"])
        expect(got, "caseJoin", ["n=2 cols=K|K2|V", "a,a,1", "A,A,2"])
        expect(got, "typeJoin", ["n=0 cols=K|K2"])
        #expect(got["dupCols"]?.first?.hasPrefix("ERR ") == true)
        expect(got, "nestedDef", ["n=2 cols=ID|Name|OID", "1,An,10", "2,Bi,~"])
        expect(got, "combine", ["n=2 cols=A|B|C", "1,x,~", "~,y,true"])
        #expect(got["expandDup"]?.first?.hasPrefix("ERR ") == true)
        // Desktop cho cột `any` lẫn số và chữ ("n=2 cols=A", "1", "x"); BI Pro chuyển cột lẫn kiểu thành text (VM-F8: Close & Apply cũng nạp `string`).
        expect(got, "combMixed", ["n=2 cols=A", "1", "x"])
    }

    @Test func p3PivotUnpivot() async throws {
        let got = try await probe("p3")
        expect(got, "pivotSum", ["n=2 cols=K|a|b", "1,1,7", "2,3,~"])
        #expect(got["pivotNoAgg"]?.first == "n=2 cols=K|a|b")   // Desktop: dòng 1 có ô lỗi nên dòng kết quả đó là "Error", dòng 2 "2,3,~"
        #expect(got["pivotNoAgg"] == ["n=2 cols=K|a|b", "Error", "2,3,~"])
        expect(got, "pivotNoAggOk", ["n=2 cols=K|a|b", "1,1,2", "2,3,~"])
        expect(got, "unpivotOther", ["n=3 cols=Id|A|Val", "1,Q1,10", "1,Q2,20", "2,Q2,5"])
        expect(got, "unpivot", ["n=3 cols=Id|A|Val", "1,Q1,10", "1,Q2,20", "2,Q2,5"])
        expect(got, "grpCount", ["n=2 cols=Id|Count", "1,1", "2,1"])
        expect(got, "grpMedian", ["n=2 cols=P|M|Mx|D", "a,2,3,2", "b,3.5,5,2"])
    }

    @Test func pivotWithoutAggregationPutsTheErrorInTheCell() async throws {
        // Desktop (p3 pivotNoAgg): bảng vẫn có 2 dòng, ô (K=1, b) lỗi, không ném cả hàm.
        let value = try await MEvaluator(environment: MEnvironment()).evaluate(source: """
        Table.Pivot(#table({"K","P","V"}, {{2,"a",3},{1,"a",1},{1,"b",2},{1,"b",5}}), {"a","b"}, "P", "V")
        """)
        guard case .table(let table) = value else { Issue.record("phải là bảng"); return }
        #expect(table.rowCount == 2)
        #expect(table.error(row: 0, column: 2) != nil)
        #expect(table.error(row: 0, column: 1) == nil)
    }

    @Test func p4JoinOrderPlacesUnmatchedRowsLast() async throws {
        let got = try await probe("p4")
        // Thứ tự dòng khớp do Desktop quyết (băm), nên so tập; dòng không khớp luôn ở cuối (phải trước trái).
        func body(_ name: String) -> Set<String> { Set((got[name] ?? []).dropFirst()) }
        let matched: Set<String> = ["3,l3,3,r3", "3,l3,3,r3b", "2,l2,2,r2", "1,l1,1,r1", "1,l1b,1,r1"]
        #expect(got["inner"]?.first == "n=5 cols=K|L|K2|R")
        #expect(body("inner") == matched)
        #expect(got["left"]?.last == "5,l5,~,~")
        #expect(body("left") == matched.union(["5,l5,~,~"]))
        #expect(got["right"]?.last == "~,~,9,r9")
        #expect(got["full"]?.suffix(2).elementsEqual(["~,~,9,r9", "5,l5,~,~"]) == true)
        #expect(got["full"]?.first == "n=7 cols=K|L|K2|R")
        expect(got, "pivText", ["n=3 cols=K|a|b", "x,2,4", "y,3,~", "z,1,~"])
    }

    @Test func p5PivotSortsKeysAscendingNullFirst() async throws {
        let got = try await probe("p5")
        expect(got, "pivNum", ["n=4 cols=K|a", "~,4", "2,3", "9,2", "10,1"])
        expect(got, "pivMulti", ["n=4 cols=K1|K2|a", "1,b,4", "1,z,3", "2,a,2", "2,b,1"])
        expect(got, "grpDesc", ["n=3 cols=K|S", "10,1", "9,6", "2,3"])
    }
}
