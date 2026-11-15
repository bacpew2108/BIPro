import Foundation
import Testing
@testable import PBIXKit

/// Phase E (T033): ghép vị trí thẻ bảng vào `DiagramLayout` (UTF-16LE JSON) giữ nguyên mọi phần khác.
@Suite struct DiagramLayoutPatchTests {
    static let json = #"{"version":"1.1.0","diagrams":[{"ordinal":0,"scrollPosition":{"x":0,"y":0},"nodes":[{"location":{"x":10.5,"y":20},"nodeIndex":"A","nodeLineageTag":"t-a","size":{"height":300,"width":234},"zIndex":0},{"location":{"x":300,"y":40.25},"nodeIndex":"B","nodeLineageTag":"t-b","size":{"height":152,"width":234},"zIndex":0}],"name":"All tables","zoomValue":60,"pinKeyFieldsToTop":false},{"ordinal":1,"scrollPosition":{"x":0,"y":0},"nodes":[{"location":{"x":1,"y":2},"nodeIndex":"A","nodeLineageTag":"t-a","size":{"height":300,"width":234},"zIndex":0}],"name":"Tab hai","zoomValue":100}],"selectedDiagram":"All tables","defaultDiagram":"All tables"}"#

    private func data(_ text: String, bom: Bool = false) -> Data {
        (bom ? Data([0xFF, 0xFE]) : Data()) + text.data(using: .utf16LittleEndian)!
    }

    private func text(_ d: Data) -> String { d.utf16LEString() }

    /// Danh sách tab theo vị trí: tab thứ i < `fileCount` lấy từ tab thứ i của file, phần còn lại là tab mới.
    private func positional(_ names: [String], fileCount: Int = 2) -> [DiagramLayoutPatch.Tab] {
        names.enumerated().map { .init(name: $0.element, source: $0.offset < fileCount ? $0.offset : nil) }
    }

    /// File có ba tab: "All tables" (A, B), "Tab hai" (A), "Tab ba" (B, C); đang chọn "Tab ba".
    static let json3 = json
        .replacingOccurrences(of: #""name":"Tab hai","zoomValue":100}"#,
                              with: #""name":"Tab hai","zoomValue":100},{"ordinal":2,"scrollPosition":{"x":0,"y":0},"nodes":[{"location":{"x":5,"y":6},"nodeIndex":"B","nodeLineageTag":"t-b","size":{"height":300,"width":234},"zIndex":0},{"location":{"x":7,"y":8},"nodeIndex":"C","nodeLineageTag":"t-c","size":{"height":300,"width":234},"zIndex":0}],"name":"Tab ba","zoomValue":80}"#)
        .replacingOccurrences(of: #""selectedDiagram":"All tables""#, with: #""selectedDiagram":"Tab ba""#)

    @Test func khongSuaThiGiongByte() throws {
        let original = data(Self.json)
        #expect(try DiagramLayoutPatch.applying(moves: [], zoom: [:], to: original) == original)
    }

    @Test func doiViTriChiDoiHaiSoCuaDungTheTrongDungTab() throws {
        let out = try DiagramLayoutPatch.applying(moves: [.init(diagram: "All tables", table: "B", x: 123.75, y: -50)], zoom: [:], to: data(Self.json))
        let expected = Self.json.replacingOccurrences(of: #"{"location":{"x":300,"y":40.25},"nodeIndex":"B""#, with: #"{"location":{"x":123.75,"y":-50},"nodeIndex":"B""#)
        #expect(text(out) == expected)
    }

    @Test func tabKhacVaTheKhacGiuNguyen() throws {
        let out = text(try DiagramLayoutPatch.applying(moves: [.init(diagram: "Tab hai", table: "A", x: 7, y: 8)], zoom: [:], to: data(Self.json)))
        #expect(out.contains(#"{"location":{"x":10.5,"y":20},"nodeIndex":"A""#))           // thẻ A ở tab 1 không đổi
        #expect(out.contains(#"{"location":{"x":7,"y":8},"nodeIndex":"A""#))               // thẻ A ở tab 2 đổi
    }

    @Test func thuPhongTheoTab() throws {
        let out = text(try DiagramLayoutPatch.applying(moves: [], zoom: ["All tables": 85], to: data(Self.json)))
        #expect(out.contains(#""name":"All tables","zoomValue":85,"#) && out.contains(#""name":"Tab hai","zoomValue":100}"#))
    }

    @Test func giuBomVaMaHoaUTF16LE() throws {
        let original = data(Self.json, bom: true)
        let out = try DiagramLayoutPatch.applying(moves: [.init(diagram: "All tables", table: "A", x: 1, y: 2)], zoom: [:], to: original)
        #expect(out.prefix(2) == Data([0xFF, 0xFE]))
        #expect(text(out).contains(#"{"location":{"x":1,"y":2},"nodeIndex":"A""#))
    }

    @Test func theChuaCoNutThiThem() throws {
        let out = text(try DiagramLayoutPatch.applying(moves: [.init(diagram: "All tables", table: "C", x: 5, y: 6)], zoom: [:], to: data(Self.json),
                                                       lineageTag: { $0 == "C" ? "t-c" : nil }))
        #expect(out.contains(#"{"location":{"x":5,"y":6},"nodeIndex":"C","nodeLineageTag":"t-c","size":{"height":300,"width":234},"zIndex":0}"#))
        // JSON vẫn hợp lệ và đọc được
        let parsed = try JSONValue.parse(out)
        #expect(parsed["diagrams"]?.array[0]["nodes"]?.array.count == 3)
    }

    @Test func tabKhongCoBiTuChoi() {
        #expect(throws: WriteError.self) {
            try DiagramLayoutPatch.applying(moves: [.init(diagram: "Khong co", table: "A", x: 1, y: 2)], zoom: [:], to: data(Self.json))
        }
    }

    @Test func soThapPhanVietNganNhat() throws {
        let out = text(try DiagramLayoutPatch.applying(moves: [.init(diagram: "All tables", table: "A", x: 1137.520738768936, y: 40)], zoom: [:], to: data(Self.json)))
        #expect(out.contains(#"{"location":{"x":1137.520738768936,"y":40},"nodeIndex":"A""#))
    }

    // MARK: Tab bố cục (VM-E6)

    @Test func themTabMoiGhiNhuDesktop() throws {
        let out = text(try DiagramLayoutPatch.applying(tabs: positional(["All tables", "Tab hai", "Layout 1"]), selected: "Layout 1", moves: [], zoom: [:], to: data(Self.json)))
        let tail = #"{"ordinal":2,"scrollPosition":{"x":0,"y":0},"nodes":[],"name":"Layout 1","zoomValue":100,"pinKeyFieldsToTop":false,"showExtraHeaderInfo":false,"hideKeyFieldsWhenCollapsed":false,"tablesLocked":false}],"selectedDiagram":"Layout 1","defaultDiagram":"All tables"}"#
        #expect(out.hasSuffix(tail))
        // phần trước giữ nguyên byte
        #expect(out.hasPrefix(String(Self.json.prefix(Self.json.count - #"],"selectedDiagram":"All tables","defaultDiagram":"All tables"}"#.count - 1))))
        let parsed = try JSONValue.parse(out)
        #expect(parsed["diagrams"]?.array.count == 3 && parsed["selectedDiagram"]?.string == "Layout 1")
    }

    @Test func tabMoiCoTheDuocDatVaoDungTab() throws {
        let out = text(try DiagramLayoutPatch.applying(tabs: positional(["All tables", "Tab hai", "Layout 1"]), selected: "Layout 1",
                                                       moves: [.init(diagram: "Layout 1", table: "B", x: 380, y: 449)], zoom: [:], to: data(Self.json),
                                                       lineageTag: { $0 == "B" ? "t-b" : nil }))
        #expect(out.contains(#""nodes":[{"location":{"x":380,"y":449},"nodeIndex":"B","nodeLineageTag":"t-b","size":{"height":300,"width":234},"zIndex":0}],"name":"Layout 1""#))
        let parsed = try JSONValue.parse(out)
        #expect(parsed["diagrams"]?.array[2]["nodes"]?.array.count == 1 && parsed["diagrams"]?.array[0]["nodes"]?.array.count == 2)
    }

    @Test func doiTenTabTheoThuTuVaGiuNut() throws {
        let out = text(try DiagramLayoutPatch.applying(tabs: positional(["All tables", "Bố cục \"hai\" \\ 2"]), moves: [.init(diagram: "Bố cục \"hai\" \\ 2", table: "A", x: 7, y: 8)], zoom: [:], to: data(Self.json)))
        let parsed = try JSONValue.parse(out)
        #expect(parsed["diagrams"]?.array[1]["name"]?.string == "Bố cục \"hai\" \\ 2")
        #expect(out.contains(#""name":"Bố cục \"hai\" \\ 2","zoomValue":100}"#))
        #expect(out.contains(#"{"location":{"x":7,"y":8},"nodeIndex":"A""#))
        #expect(parsed["selectedDiagram"]?.string == "All tables")                 // chọn tab nào không đổi nếu không yêu cầu
    }

    @Test func doiTenTabDangChonThiSelectedDiagramTheoSau() throws {
        let json = Self.json.replacingOccurrences(of: #""selectedDiagram":"All tables""#, with: #""selectedDiagram":"Tab hai""#)
        let out = text(try DiagramLayoutPatch.applying(tabs: positional(["All tables", "Moi"]), moves: [], zoom: [:], to: data(json)))
        #expect(out.contains(#""selectedDiagram":"Moi""#))
    }

    @Test func danhSachTabGiongFileThiGiongByte() throws {
        let original = data(Self.json)
        #expect(try DiagramLayoutPatch.applying(tabs: positional(["All tables", "Tab hai"]), moves: [], zoom: [:], to: original) == original)
    }

    @Test func tabDoiTenRoiThuPhongTheoTenMoi() throws {
        let out = text(try DiagramLayoutPatch.applying(tabs: positional(["All tables", "Moi"]), moves: [], zoom: ["Moi": 70], to: data(Self.json)))
        #expect(out.contains(#""name":"Moi","zoomValue":70}"#))
    }

    // MARK: Xoá tab, gỡ bảng khỏi tab (VM-E7)

    @Test func xoaTabGiuaDanhSoLaiOrdinalVaBoNoiDungTab() throws {
        let tabs: [DiagramLayoutPatch.Tab] = [.init(name: "All tables", source: 0), .init(name: "Tab ba", source: 2)]
        let out = text(try DiagramLayoutPatch.applying(tabs: tabs, moves: [], zoom: [:], to: data(Self.json3)))
        let parsed = try JSONValue.parse(out)
        let diagrams = try #require(parsed["diagrams"]?.array)
        #expect(diagrams.count == 2 && diagrams[1]["name"]?.string == "Tab ba" && diagrams[1]["ordinal"]?.number == 1)
        #expect(!out.contains("Tab hai"))
        // tab giữ lại giữ nguyên byte, trừ ordinal
        #expect(out.contains(#""ordinal":1,"scrollPosition":{"x":0,"y":0},"nodes":[{"location":{"x":5,"y":6},"nodeIndex":"B""#))
        #expect(parsed["selectedDiagram"]?.string == "Tab ba")           // tab đang chọn vẫn còn
    }

    @Test func xoaTabDangChonThiVeTabDau() throws {
        let tabs: [DiagramLayoutPatch.Tab] = [.init(name: "All tables", source: 0), .init(name: "Tab hai", source: 1)]
        let out = text(try DiagramLayoutPatch.applying(tabs: tabs, moves: [], zoom: [:], to: data(Self.json3)))
        #expect(try JSONValue.parse(out)["selectedDiagram"]?.string == "All tables")
        #expect(try JSONValue.parse(out)["diagrams"]?.array.count == 2)
    }

    @Test func xoaTabRoiThemTabMoiOrdinalLienTuc() throws {
        let tabs: [DiagramLayoutPatch.Tab] = [.init(name: "All tables", source: 0), .init(name: "Tab ba", source: 2), .init(name: "Layout 2", source: nil)]
        let out = text(try DiagramLayoutPatch.applying(tabs: tabs, selected: "Layout 2", moves: [], zoom: [:], to: data(Self.json3)))
        let diagrams = try #require(try JSONValue.parse(out)["diagrams"]?.array)
        #expect(diagrams.map { $0["ordinal"]?.number } == [0, 1, 2] && diagrams.map { $0["name"]?.string } == ["All tables", "Tab ba", "Layout 2"])
    }

    @Test func danhSachTabNguonSaiBiTuChoi() {
        #expect(throws: WriteError.self) {
            try DiagramLayoutPatch.applying(tabs: [.init(name: "All tables", source: 0), .init(name: "X", source: 7)], moves: [], zoom: [:], to: data(Self.json3))
        }
        #expect(throws: WriteError.self) {
            try DiagramLayoutPatch.applying(tabs: [.init(name: "All tables", source: 0), .init(name: "X", source: 0)], moves: [], zoom: [:], to: data(Self.json3))
        }
    }

    @Test func goBangKhoiTabChiBoNutDoTrongTabDo() throws {
        let out = text(try DiagramLayoutPatch.applying(removals: [.init(diagram: "Tab ba", table: "B")], moves: [], zoom: [:], to: data(Self.json3)))
        let diagrams = try #require(try JSONValue.parse(out)["diagrams"]?.array)
        #expect(diagrams[2]["nodes"]?.array.map { $0["nodeIndex"]?.string } == ["C"])
        #expect(diagrams[0]["nodes"]?.array.count == 2 && diagrams[1]["nodes"]?.array.count == 1)   // tab khác không đổi
        #expect(out.contains(#""nodes":[{"location":{"x":7,"y":8},"nodeIndex":"C""#))                // không sót dấu phẩy
    }

    @Test func goNutCuoiVaNutDuNhatDeMangHopLe() throws {
        let out = text(try DiagramLayoutPatch.applying(removals: [.init(diagram: "Tab ba", table: "C"), .init(diagram: "Tab hai", table: "A")], moves: [], zoom: [:], to: data(Self.json3)))
        let diagrams = try #require(try JSONValue.parse(out)["diagrams"]?.array)
        #expect(diagrams[2]["nodes"]?.array.map { $0["nodeIndex"]?.string } == ["B"] && diagrams[1]["nodes"]?.array.isEmpty == true)
        #expect(out.contains(#""nodes":[],"name":"Tab hai""#))
    }

    @Test func goNutRoiDoiTenTabVanDungTab() throws {
        let tabs: [DiagramLayoutPatch.Tab] = [.init(name: "All tables", source: 0), .init(name: "Tab hai", source: 1), .init(name: "Ba", source: 2)]
        let out = text(try DiagramLayoutPatch.applying(tabs: tabs, removals: [.init(diagram: "Ba", table: "B")], moves: [], zoom: [:], to: data(Self.json3)))
        let diagrams = try #require(try JSONValue.parse(out)["diagrams"]?.array)
        #expect(diagrams[2]["name"]?.string == "Ba" && diagrams[2]["nodes"]?.array.map { $0["nodeIndex"]?.string } == ["C"])
    }
}
