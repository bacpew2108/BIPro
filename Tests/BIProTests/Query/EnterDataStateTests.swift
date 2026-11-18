// Đợt tồn đọng sau Phase F, T027: hộp "Tạo bảng" (Enter Data) như Desktop 2.159 (VM-F11a, docs/phase-f2-evidence/vm-f11/QUAN-SAT.md mục a).
// Golden: dán đúng chuỗi clipboard đã dán vào Desktop (kể cả U+FEFF do cách dán của buổi VM) thì M sinh ra trùng từng byte với M Desktop
// lưu (`enter-data-table.m`; `Table (2)` trong `f11-desktop.pbix`, ngoài git).
import Foundation
import PBIXKit
import Testing
@testable import BIPro

@Suite struct EnterDataStateTests {
    private static let evidence = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("docs/phase-f2-evidence/vm-f11")

    /// Clipboard của buổi VM: tệp UTF-16 có BOM qua `clip`, nên ô đầu mang U+FEFF.
    static let pastedTable = "\u{FEFF}Tên\tSố lượng\tGhi chú\r\nÁo thun\t12\tmới\r\nQuần jean\t5\t\r\nGiày\t\tcũ\r\nMũ\t3.5\tđỏ\r\nTúi xách\t-7\tx\r\n"
    static let pastedTable2 = "\u{FEFF}Manager\tRegion\r\nAn\tTrung tâm\r\nBình\tEast\r\nChi\tWest\r\nDũng\tNorth\r\nEm\tSouth\r\n"

    @Test func danVaoLuoiTrongThiDongDauThanhTieuDe() throws {
        var table = EnterDataTable(name: "Table")
        #expect(table.columns == ["Column1"] && table.rows == [[""]])
        let promoted = try table.paste(Self.pastedTable)
        #expect(promoted)
        #expect(table.columns == ["\u{FEFF}Tên", "Số lượng", "Ghi chú"])
        #expect(table.rows.count == 5)
        #expect(table.rows[1] == ["Quần jean", "5", ""])
        #expect(table.rows[2] == ["Giày", "", "cũ"])
    }

    @Test func mTrungTungByteVoiDesktop() throws {
        var table = EnterDataTable(name: "Table")
        try table.paste(Self.pastedTable)
        let desktop = try String(contentsOf: Self.evidence.appendingPathComponent("enter-data-table.m"), encoding: .utf8)
        #expect(table.m == desktop)
    }

    @Test(.enabled(if: F2Fixtures.desktop("vm-f11", "f11-desktop.pbix") != nil))
    func mTable2TrungVoiDesktop() throws {
        let url = try #require(F2Fixtures.desktop("vm-f11", "f11-desktop.pbix"))
        let (abf, _) = try PBIXFile(data: try Data(contentsOf: url, options: .alwaysMapped)).loadDataModel()
        let metadata = try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb"))
        var table = EnterDataTable(name: "Table (2)")
        try table.paste(Self.pastedTable2)
        #expect(table.m == metadata.partitionQueries["Table (2)"])
    }

    @Test func docNguocMThanhLuoi() throws {
        let desktop = try String(contentsOf: Self.evidence.appendingPathComponent("enter-data-table.m"), encoding: .utf8)
        let table = try #require(EnterDataTable(name: "Table", m: desktop))
        #expect(table.columns == ["\u{FEFF}Tên", "Số lượng", "Ghi chú"])
        #expect(table.rows == [["Áo thun", "12", "mới"], ["Quần jean", "5", ""], ["Giày", "", "cũ"], ["Mũ", "3.5", "đỏ"], ["Túi xách", "-7", "x"]])
        #expect(table.m == desktop)
        #expect(EnterDataTable(name: "x", m: "let Source = Csv.Document(1) in Source") == nil)
    }

    /// Desktop: 1 cột × 3 000 dòng (kể cả tiêu đề) được nhận, 3 001 bị từ chối và lưới giữ nguyên.
    @Test func gioiHan3000O() throws {
        let accepted = (["X"] + (1..<3000).map(String.init)).joined(separator: "\r\n") + "\r\n"
        var table = EnterDataTable(name: "Table")
        try table.paste(accepted)
        #expect(table.rows.count == 2999)

        let refused = (["X"] + (1...3000).map(String.init)).joined(separator: "\r\n") + "\r\n"
        var other = EnterDataTable(name: "Table")
        #expect(throws: EnterDataTable.PasteError.tooLarge) { try other.paste(refused) }
        #expect(other.columns == ["Column1"] && other.rows == [[""]])
        #expect(EnterDataTable.PasteError.tooLarge.message.contains("3.000 ô"))
    }

    @Test func boTieuDeTraDongDauVeLuoi() throws {
        var table = EnterDataTable(name: "Table")
        try table.paste("A\tB\r\n1\t2\r\n")
        table.demoteHeaders()
        #expect(table.columns == ["Column1", "Column2"])
        #expect(table.rows == [["A", "B"], ["1", "2"]])
    }

    @Test func tenMacDinhVaHauToKhiTrung() {
        #expect(EnterDataTable.defaultName(taken: []) == "Table")
        #expect(EnterDataTable.defaultName(taken: ["Sales", "Table"]) == "Table (2)")
        #expect(EnterDataTable.defaultName(taken: ["Table", "table (2)"]) == "Table (3)")
    }

    @Test func themXoaDongCot() throws {
        var table = EnterDataTable(name: "Table")
        table.addColumn()
        #expect(table.columns == ["Column1", "Column2"] && table.rows == [["", ""]])
        table.addRow()
        table.set(row: 1, column: 1, to: "b")
        #expect(table.rows == [["", ""], ["", "b"]])
        table.renameColumn(0, to: "A")
        table.removeColumn(1)
        #expect(table.columns == ["A"] && table.rows == [[""], [""]])
        table.removeRow(0)
        #expect(table.rows == [[""]])
        table.removeRow(0)   // không bao giờ dưới một dòng
        #expect(table.rows == [[""]])
        table.removeColumn(0)   // không bao giờ dưới một cột
        #expect(table.columns == ["A"])
    }

    @Test func danLanHaiGhiDeTuOChon() throws {
        var table = EnterDataTable(name: "Table")
        try table.paste("A\tB\r\n1\t2\r\n")
        #expect(try table.paste("x\ty\tz\r\nw\r\n", row: 0, column: 1) == false)
        // [SUY ĐOÁN] dán vào lưới đã có dữ liệu: ghi đè từ ô chọn, thiếu cột/dòng thì thêm (cột mới tên "Column<n>").
        #expect(table.columns == ["A", "B", "Column3", "Column4"])
        #expect(table.rows == [["1", "x", "y", "z"], ["", "w", "", ""]])
    }

    @Test func kieuCotTheoDuLieu() throws {
        var table = EnterDataTable(name: "T")
        try table.paste("N\tD\tS\r\n1\t1.5\ta\r\n2\t\tb\r\n")
        #expect(table.m.contains(#"Table.TransformColumnTypes(Source,{{"N", Int64.Type}, {"D", type number}, {"S", type text}})"#))
    }
}
