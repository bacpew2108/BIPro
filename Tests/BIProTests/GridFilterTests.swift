import AppKit
import Foundation
import Testing
import DAXEngine
@testable import BIPro

@Suite struct GridFilterTests {

    @Test func giaTriPhanBietVaNhanTrong() {
        let table = ResultTable(
            columns: ["[val]"],
            rows: [
                [.integer(10)],
                [.blank],
                [.integer(-5)],
                [.integer(2)],
                [.integer(10)],
                [.blank]
            ]
        )

        let distinct = GridFilter.distinctValues(in: table, column: 0)
        #expect(distinct == [.integer(-5), .blank, .integer(2), .integer(10)])

        #expect(GridFilter.displayLabel(for: .blank) == "(Trống)")
        #expect(GridFilter.displayLabel(for: .integer(10)) == "10")
        #expect(GridFilter.displayLabel(for: .integer(-5)) == "-5")
    }

    @Test func giaTriPhanBietChuoiCoBlank() {
        let table = ResultTable(
            columns: ["[text]"],
            rows: [
                [.string("Banana")],
                [.blank],
                [.string("Apple")],
                [.string("apple")],
                [.string("Cherry")]
            ]
        )

        let distinct = GridFilter.distinctValues(in: table, column: 0)
        // BLANK coi như "" nên đứng đầu, sau đó Apple, Banana, Cherry
        #expect(distinct.first == .blank)
        let labels = distinct.map { GridFilter.displayLabel(for: $0) }
        #expect(labels.contains("(Trống)"))
        #expect(labels.contains("Banana"))
        #expect(labels.contains("Cherry"))
    }

    @Test func timKiemKhongPhanBietHoaThuongVaTimDuocTrong() {
        let values: [Value] = [
            .blank,
            .string("Hà Nội"),
            .string("Đà Nẵng"),
            .string("TP Hồ Chí Minh"),
            .integer(100)
        ]

        let searchEmpty = GridFilter.filterValues(values, query: "")
        #expect(searchEmpty == values)

        let searchTrong = GridFilter.filterValues(values, query: "trống")
        #expect(searchTrong == [.blank])

        let searchNang = GridFilter.filterValues(values, query: "nẵng")
        #expect(searchNang == [.string("Đà Nẵng")])

        let searchNum = GridFilter.filterValues(values, query: "100")
        #expect(searchNum == [.integer(100)])
    }

    @Test func locANDGiuaHaiCot() {
        let table = ResultTable(
            columns: ["[Region]", "[Year]"],
            rows: [
                [.string("Bắc"), .integer(2022)],   // 0
                [.string("Bắc"), .integer(2023)],   // 1
                [.string("Nam"), .integer(2022)],   // 2
                [.string("Nam"), .integer(2023)],   // 3
                [.string("Trung"), .integer(2024)]  // 4
            ]
        )

        // Lọc Vùng: Bắc hoặc Nam; Lọc Năm: 2022
        let filters: [Int: Set<Value>] = [
            0: [.string("Bắc"), .string("Nam")],
            1: [.integer(2022)]
        ]

        let visible = GridFilter.filteredAndSortedIndices(in: table, filters: filters)
        #expect(visible == [0, 2])
    }

    @Test func sapXepTangGiamCoBlank() {
        let table = ResultTable(
            columns: ["[num]"],
            rows: [
                [.integer(10)], // 0
                [.blank],       // 1
                [.integer(-5)]  // 2
            ]
        )

        // Ascending: -5 < 0 (BLANK) < 10
        let asc = GridFilter.filteredAndSortedIndices(
            in: table,
            filters: [:],
            sortKey: GridFilter.SortKey(column: 0, direction: .ascending)
        )
        #expect(asc == [2, 1, 0])

        // Descending: 10 > 0 (BLANK) > -5
        let desc = GridFilter.filteredAndSortedIndices(
            in: table,
            filters: [:],
            sortKey: GridFilter.SortKey(column: 0, direction: .descending)
        )
        #expect(desc == [0, 1, 2])
    }

    @Test func giuThuTuGocKhiBangNhau() {
        let table = ResultTable(
            columns: ["[Score]", "[Label]"],
            rows: [
                [.integer(5), .string("first")],   // 0
                [.integer(3), .string("second")],  // 1
                [.integer(5), .string("third")],   // 2
                [.integer(5), .string("fourth")],  // 3
                [.integer(1), .string("fifth")]    // 4
            ]
        )

        // Sắp tăng dần: 1 (dòng 4), 3 (dòng 1), 5 (dòng 0, 2, 3 giữ đúng thứ tự 0 -> 2 -> 3)
        let asc = GridFilter.filteredAndSortedIndices(
            in: table,
            filters: [:],
            sortKey: GridFilter.SortKey(column: 0, direction: .ascending)
        )
        #expect(asc == [4, 1, 0, 2, 3])

        // Sắp giảm dần: 5 (dòng 0, 2, 3 giữ đúng thứ tự 0 -> 2 -> 3), 3 (dòng 1), 1 (dòng 4)
        let desc = GridFilter.filteredAndSortedIndices(
            in: table,
            filters: [:],
            sortKey: GridFilter.SortKey(column: 0, direction: .descending)
        )
        #expect(desc == [0, 2, 3, 1, 4])
    }

    // MARK: - Tests cho Sửa 1 (Vùng bấm và vẽ icon trong ô tiêu đề)

    @Test func vungBamIconLocKhoang20ptVaKhongChongMep() {
        let colRect = NSRect(x: 100, y: 0, width: 120, height: 24)

        // Khi chưa sắp xếp: vùng bấm rộng 20 pt, sát mép phải
        let hitRect = ResultGrid.filterIconHitRect(in: colRect, isSorted: false)
        #expect(hitRect.width == 20)
        #expect(hitRect.height == 24)
        #expect(hitRect.maxX == colRect.maxX - 2) // chừa 2 pt cho divider kéo giãn

        // Bấm vào icon: nằm trong hitRect
        let iconCenter = NSPoint(x: colRect.maxX - 12, y: 12)
        #expect(hitRect.contains(iconCenter))

        // Bấm vào chữ tên cột: KHÔNG nằm trong hitRect (không mở popover)
        let textPoint = NSPoint(x: colRect.minX + 30, y: 12)
        #expect(!hitRect.contains(textPoint))

        // Bấm vào mép divider: KHÔNG nằm trong hitRect (để dành co giãn cột)
        let dividerPoint = NSPoint(x: colRect.maxX - 1, y: 12)
        #expect(!hitRect.contains(dividerPoint))
    }

    @Test func vungBamKhiSapXepMoRongBaoGomCaMuiTen() {
        let colRect = NSRect(x: 100, y: 0, width: 120, height: 24)

        // Khi đang sắp xếp: mở rộng ra 30 pt để phủ cả mũi tên
        let hitSorted = ResultGrid.filterIconHitRect(in: colRect, isSorted: true)
        #expect(hitSorted.width == 30)
        #expect(hitSorted.maxX == colRect.maxX - 2)

        let arrowPoint = NSPoint(x: colRect.maxX - 24, y: 12)
        #expect(hitSorted.contains(arrowPoint))
    }

    @MainActor @Test func kichThuocVaViTriVeIconVaMuiTen() {   // tạo NSTableHeaderCell: AppKit phải chạy trên main thread
        let colRect = NSRect(x: 0, y: 0, width: 100, height: 24)

        // Icon lọc: 12 pt, sát mép phải ô tiêu đề
        let filterRect = ResultGrid.filterIconDrawingRect(in: colRect)
        #expect(filterRect.width == 12)
        #expect(filterRect.height == 12)
        #expect(filterRect.maxX == colRect.maxX - 6)
        #expect(filterRect.minY == (colRect.height - 12) / 2)

        // Mũi tên: 10 pt, bên trái icon lọc
        let arrowRect = ResultGrid.sortArrowDrawingRect(in: colRect)
        #expect(arrowRect.width == 10)
        #expect(arrowRect.height == 10)
        #expect(arrowRect.maxX == filterRect.minX - 2)

        // Header cell thu hẹp vùng vẽ chữ 32 pt ở mép phải để chữ không đè lên icon
        let cell = FilterableTableHeaderCell(textCell: "Doanh thu")
        let drawRect = cell.drawingRect(forBounds: colRect)
        #expect(drawRect.maxX <= filterRect.minX)
    }
}
