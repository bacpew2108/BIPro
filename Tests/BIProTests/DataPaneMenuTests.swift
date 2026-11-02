import AppKit
import Foundation
import Testing
@testable import BIPro

@Suite struct DataPaneMenuTests {
    // MARK: - Tests cho LeftMenuGeometry (tính vị trí panel thuần)

    @Test func mainMenuDatMepPhaiTaiConTro() {
        let cursor = NSPoint(x: 800, y: 600)
        let menuSize = NSSize(width: 270, height: 320)
        let screen = NSRect(x: 0, y: 50, width: 1920, height: 1030)

        let frame = LeftMenuGeometry.calculateMainMenuFrame(
            cursorPoint: cursor,
            menuSize: menuSize,
            screenVisibleFrame: screen
        )

        // Mép phải của panel nằm ở con trỏ
        #expect(frame.maxX == cursor.x)
        #expect(frame.width == menuSize.width)
        #expect(frame.height == menuSize.height)
        #expect(frame.minX == cursor.x - menuSize.width)
        // Mép trên tại con trỏ khi không bị tràn
        #expect(frame.maxY == cursor.y)
    }

    @Test func mainMenuTranMepDuoiThiDayLen() {
        // Con trỏ ở gần đáy màn hình: y = 120, menu cao 300, screen.minY = 50
        // Bình thường: y = 120 - 300 = -180 < 50
        let cursor = NSPoint(x: 800, y: 120)
        let menuSize = NSSize(width: 270, height: 300)
        let screen = NSRect(x: 0, y: 50, width: 1920, height: 1030)

        let frame = LeftMenuGeometry.calculateMainMenuFrame(
            cursorPoint: cursor,
            menuSize: menuSize,
            screenVisibleFrame: screen
        )

        #expect(frame.minY == 50)
        #expect(frame.height == 300)
        #expect(frame.maxX == cursor.x)
    }

    @Test func submenuDatBenTraiPanelChinhVaNgangDongMoNo() {
        let parentMenuFrame = NSRect(x: 600, y: 300, width: 270, height: 300)
        let rowScreenFrame = NSRect(x: 600, y: 560, width: 270, height: 30) // maxY = 590
        let subSize = NSSize(width: 240, height: 180)
        let screen = NSRect(x: 0, y: 50, width: 1920, height: 1030)

        let frame = LeftMenuGeometry.calculateSubmenuFrame(
            parentMenuFrame: parentMenuFrame,
            parentItemScreenFrame: rowScreenFrame,
            submenuSize: subSize,
            screenVisibleFrame: screen
        )

        // Đặt sát bên trái panel chính: frame.maxX == parentMenuFrame.minX
        #expect(frame.maxX == parentMenuFrame.minX)
        #expect(frame.minX == parentMenuFrame.minX - subSize.width)
        // Mép trên ngang dòng mở nó: frame.maxY == rowScreenFrame.maxY
        #expect(frame.maxY == rowScreenFrame.maxY)
        #expect(frame.height == subSize.height)
    }

    @Test func submenuTuLatSangPhaiKhiThieuChoBenTrai() {
        // Panel chính ở x = 100, submenu rộng 240, screen.minX = 0
        // Bên trái: 100 - 240 = -140 < 0 (không đủ chỗ)
        let parentMenuFrame = NSRect(x: 100, y: 300, width: 270, height: 300)
        let rowScreenFrame = NSRect(x: 100, y: 560, width: 270, height: 30)
        let subSize = NSSize(width: 240, height: 180)
        let screen = NSRect(x: 0, y: 50, width: 1920, height: 1030)

        let frame = LeftMenuGeometry.calculateSubmenuFrame(
            parentMenuFrame: parentMenuFrame,
            parentItemScreenFrame: rowScreenFrame,
            submenuSize: subSize,
            screenVisibleFrame: screen
        )

        // Tự lật sang phải: sát mép phải panel chính
        #expect(frame.minX == parentMenuFrame.maxX)
        #expect(frame.width == subSize.width)
        #expect(frame.maxY == rowScreenFrame.maxY)
    }

    @Test func submenuTranMepDuoiThiDayLen() {
        let parentMenuFrame = NSRect(x: 600, y: 80, width: 270, height: 200)
        let rowScreenFrame = NSRect(x: 600, y: 100, width: 270, height: 30) // maxY = 130
        let subSize = NSSize(width: 240, height: 180) // 130 - 180 = -50 < 50
        let screen = NSRect(x: 0, y: 50, width: 1920, height: 1030)

        let frame = LeftMenuGeometry.calculateSubmenuFrame(
            parentMenuFrame: parentMenuFrame,
            parentItemScreenFrame: rowScreenFrame,
            submenuSize: subSize,
            screenVisibleFrame: screen
        )

        #expect(frame.minY == 50)
        #expect(frame.height == subSize.height)
        #expect(frame.maxX == parentMenuFrame.minX)
    }

    // MARK: - Tests cho ModelGroupMenuItems

    @Test func menuChoNutNhomTabMoHinh() {
        var actionsTriggered = [String]()
        let items = LeftMenuBuilder.modelGroupMenuItems(
            onCollapseAll: { actionsTriggered.append("collapse") },
            onExpandAll: { actionsTriggered.append("expand") }
        )

        // Nút nhóm trong tab Mô hình: chỉ có "Thu gọn tất cả" / "Mở rộng tất cả"
        #expect(items.count == 2)
        #expect(items[0].title == "Thu gọn tất cả" && items[0].isEnabled)
        #expect(items[1].title == "Mở rộng tất cả" && items[1].isEnabled)

        if case .action(_, _, let act) = items[0] {
            act()
            #expect(actionsTriggered.contains("collapse"))
        }
        if case .action(_, _, let act) = items[1] {
            act()
            #expect(actionsTriggered.contains("expand"))
        }
    }
}
