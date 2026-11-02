import AppKit
import SwiftUI

/// Mục menu ngữ cảnh hiển thị bên trái con trỏ chuột.
public enum LeftMenuItem: Equatable {
    case action(String, isEnabled: Bool, () -> Void)
    case submenu(String, [LeftMenuItem])
    case separator
    case sectionHeader(String)

    public static func action(_ title: String, _ action: @escaping () -> Void) -> LeftMenuItem {
        .action(title, isEnabled: true, action)
    }

    public static func == (lhs: LeftMenuItem, rhs: LeftMenuItem) -> Bool {
        switch (lhs, rhs) {
        case (.separator, .separator):
            return true
        case (.sectionHeader(let a), .sectionHeader(let b)):
            return a == b
        case (.action(let t1, let e1, _), .action(let t2, let e2, _)):
            return t1 == t2 && e1 == e2
        case (.submenu(let t1, let i1), .submenu(let t2, let i2)):
            return t1 == t2 && i1 == i2
        default:
            return false
        }
    }

    public var title: String? {
        switch self {
        case .action(let title, _, _): return title
        case .submenu(let title, _): return title
        case .sectionHeader(let title): return title
        case .separator: return nil
        }
    }

    public var isEnabled: Bool {
        switch self {
        case .action(_, let enabled, _): return enabled
        case .submenu: return true
        case .sectionHeader, .separator: return false
        }
    }
}

// MARK: - Geometry (Hàm tính vị trí thuần, dễ unit test)

public enum LeftMenuGeometry {
    public static func itemHeight(for item: LeftMenuItem) -> CGFloat {
        switch item {
        case .action, .submenu:
            return 30
        case .separator:
            return 9
        case .sectionHeader:
            return 24
        }
    }

    public static func calculateMenuSize(items: [LeftMenuItem], width: CGFloat = 270) -> NSSize {
        var height: CGFloat = 8 // padding trên 4pt + dưới 4pt
        for item in items {
            height += itemHeight(for: item)
        }
        return NSSize(width: width, height: height)
    }

    public static func calculateItemScreenFrame(
        menuFrame: NSRect,
        items: [LeftMenuItem],
        itemIndex: Int
    ) -> NSRect {
        guard itemIndex >= 0 && itemIndex < items.count else { return .zero }
        var topOffsetFromMenuTop: CGFloat = 4
        for i in 0..<itemIndex {
            topOffsetFromMenuTop += itemHeight(for: items[i])
        }
        let h = itemHeight(for: items[itemIndex])
        let itemMaxY = menuFrame.maxY - topOffsetFromMenuTop
        let itemMinY = itemMaxY - h
        return NSRect(x: menuFrame.minX, y: itemMinY, width: menuFrame.width, height: h)
    }

    /// Tính vị trí menu chính: mép phải nằm ở con trỏ, tràn mép dưới thì đẩy lên.
    public static func calculateMainMenuFrame(
        cursorPoint: NSPoint,
        menuSize: NSSize,
        screenVisibleFrame: NSRect
    ) -> NSRect {
        var x = cursorPoint.x - menuSize.width
        var y = cursorPoint.y - menuSize.height

        // Giới hạn trong màn hình theo chiều dọc: nếu tràn mép dưới thì đẩy lên
        if y < screenVisibleFrame.minY {
            y = screenVisibleFrame.minY
        }
        if y + menuSize.height > screenVisibleFrame.maxY {
            y = screenVisibleFrame.maxY - menuSize.height
        }

        // Nếu tràn mép trái màn hình thì lật sang phải con trỏ hoặc đẩy vào
        if x < screenVisibleFrame.minX {
            x = cursorPoint.x
            if x + menuSize.width > screenVisibleFrame.maxX {
                x = screenVisibleFrame.maxX - menuSize.width
            }
            if x < screenVisibleFrame.minX {
                x = screenVisibleFrame.minX
            }
        }

        return NSRect(x: x, y: y, width: menuSize.width, height: menuSize.height)
    }

    /// Tính vị trí menu con: sát bên trái panel chính, mép trên ngang dòng mở nó;
    /// nếu không đủ chỗ bên trái thì mở sang phải.
    public static func calculateSubmenuFrame(
        parentMenuFrame: NSRect,
        parentItemScreenFrame: NSRect,
        submenuSize: NSSize,
        screenVisibleFrame: NSRect
    ) -> NSRect {
        // Mép trên ngang dòng mở nó
        var y = parentItemScreenFrame.maxY - submenuSize.height

        // Giới hạn trong màn hình theo chiều dọc
        if y < screenVisibleFrame.minY {
            y = screenVisibleFrame.minY
        }
        if y + submenuSize.height > screenVisibleFrame.maxY {
            y = screenVisibleFrame.maxY - submenuSize.height
        }

        // Đặt sát bên trái panel chính
        var x = parentMenuFrame.minX - submenuSize.width

        // Nếu không đủ chỗ bên trái thì mở sang phải
        if x < screenVisibleFrame.minX {
            x = parentMenuFrame.maxX
            // Nếu mở sang phải mà tràn mép phải màn hình thì ép vào trong màn hình
            if x + submenuSize.width > screenVisibleFrame.maxX {
                x = screenVisibleFrame.maxX - submenuSize.width
            }
        }

        return NSRect(x: x, y: y, width: submenuSize.width, height: submenuSize.height)
    }
}

// MARK: - LeftMenuBuilder

public enum LeftMenuBuilder {
    public static func tableMenuItems(
        tableName: String,
        onTop100: @escaping () -> Void,
        onDefineNewMeasure: @escaping () -> Void = {},
        onCollapseAll: @escaping () -> Void = {},
        onExpandAll: @escaping () -> Void = {}
    ) -> [LeftMenuItem] {
        [
            .submenu("Truy vấn nhanh", [
                .action("Hiện 100 dòng đầu", isEnabled: true, onTop100),
                .separator,
                .action("Định nghĩa measure mới", isEnabled: true, onDefineNewMeasure)
            ]),
            .action("Đổi tên", isEnabled: false, {}),
            .action("Xoá khỏi mô hình", isEnabled: false, {}),
            .action("Ẩn trong chế độ báo cáo", isEnabled: false, {}),
            .separator,
            .action("Thu gọn tất cả", isEnabled: true, onCollapseAll),
            .action("Mở rộng tất cả", isEnabled: true, onExpandAll)
        ]
    }

    public static func measureMenuItems(
        onEvaluate: @escaping () -> Void,
        onDefineAndEvaluate: @escaping () -> Void,
        onDefineWithReferencesAndEvaluate: @escaping () -> Void,
        onDefineNewMeasure: @escaping () -> Void = {},
        onDefineAllMeasures: @escaping () -> Void = {},
        onCollapseAll: @escaping () -> Void = {},
        onExpandAll: @escaping () -> Void = {},
        onCopyFormula: @escaping () -> Void
    ) -> [LeftMenuItem] {
        [
            .submenu("Truy vấn nhanh", [
                .action("Đánh giá", isEnabled: true, onEvaluate),
                .action("Định nghĩa và đánh giá", isEnabled: true, onDefineAndEvaluate),
                .action("Định nghĩa kèm tham chiếu và đánh giá", isEnabled: true, onDefineWithReferencesAndEvaluate),
                .separator,
                .action("Định nghĩa measure mới", isEnabled: true, onDefineNewMeasure),
                .action("Định nghĩa mọi measure trong mô hình", isEnabled: true, onDefineAllMeasures)
            ]),
            .action("Đổi tên", isEnabled: false, {}),
            .action("Xoá khỏi mô hình", isEnabled: false, {}),
            .action("Ẩn trong chế độ báo cáo", isEnabled: false, {}),
            .separator,
            .action("Hiện tất cả", isEnabled: false, {}),
            .separator,
            .action("Thu gọn tất cả", isEnabled: true, onCollapseAll),
            .action("Mở rộng tất cả", isEnabled: true, onExpandAll),
            .separator,
            .action("Sao chép công thức", isEnabled: true, onCopyFormula)
        ]
    }

    public static func columnMenuItems(
        isCalculated: Bool,
        hasExpression: Bool,
        onPreviewData: @escaping () -> Void,
        onCollapseAll: @escaping () -> Void = {},
        onExpandAll: @escaping () -> Void = {},
        onCopyFormula: (() -> Void)? = nil
    ) -> [LeftMenuItem] {
        var items: [LeftMenuItem] = [
            .submenu("Truy vấn nhanh", [
                .action("Xem trước dữ liệu", isEnabled: true, onPreviewData)
            ]),
            .action("Đổi tên", isEnabled: false, {}),
            .action("Xoá khỏi mô hình", isEnabled: false, {}),
            .action("Ẩn trong chế độ báo cáo", isEnabled: false, {}),
            .separator,
            .action("Thu gọn tất cả", isEnabled: true, onCollapseAll),
            .action("Mở rộng tất cả", isEnabled: true, onExpandAll)
        ]
        if (isCalculated || hasExpression), let onCopyFormula {
            items.append(.separator)
            items.append(.action("Sao chép công thức", isEnabled: true, onCopyFormula))
        }
        return items
    }

    public static func modelGroupMenuItems(
        onCollapseAll: @escaping () -> Void,
        onExpandAll: @escaping () -> Void
    ) -> [LeftMenuItem] {
        [
            .action("Thu gọn tất cả", isEnabled: true, onCollapseAll),
            .action("Mở rộng tất cả", isEnabled: true, onExpandAll)
        ]
    }
}

// MARK: - SwiftUI Menu Views

struct LeftMenuListView: View {
    let items: [LeftMenuItem]
    let onSelectAction: (@escaping () -> Void) -> Void
    let onHoverSubmenu: (Int, [LeftMenuItem]) -> Void
    let onHoverNonSubmenu: () -> Void

    @State private var hoveredIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                rowView(item: item, index: index)
            }
        }
        .padding(.vertical, 4)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func rowView(item: LeftMenuItem, index: Int) -> some View {
        let isHovered = hoveredIndex == index
        switch item {
        case .action(let title, let isEnabled, let action):
            Button(action: {
                if isEnabled {
                    onSelectAction(action)
                }
            }) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 13))
                        .foregroundStyle(isEnabled ? Color.primary : Color.gray.opacity(0.45))
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(isHovered && isEnabled ? Color.black.opacity(0.05) : Color.clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .onHover { hovering in
                if hovering {
                    hoveredIndex = index
                    onHoverNonSubmenu()
                } else if hoveredIndex == index {
                    hoveredIndex = nil
                }
            }

        case .submenu(let title, let subItems):
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.gray.opacity(0.8))
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(isHovered ? Color.black.opacity(0.05) : Color.clear)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    hoveredIndex = index
                    onHoverSubmenu(index, subItems)
                }
            }

        case .separator:
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(height: 1)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)

        case .sectionHeader(let title):
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 24)
        }
    }
}

// MARK: - Controller điều khiển NSPanel

@MainActor
public final class LeftContextMenuController {
    public static let shared = LeftContextMenuController()

    private var mainPanel: NSPanel?
    private var submenuPanel: NSPanel?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var resignObserver: Any?
    private var appResignObserver: Any?

    private var currentItems: [LeftMenuItem] = []
    private var currentScreenVisibleFrame: NSRect = .zero

    private init() {}

    public var isShowing: Bool { mainPanel != nil }

    public func show(items: [LeftMenuItem], cursorScreenPoint: NSPoint, screenVisibleFrame: NSRect? = nil) {
        closeAll()

        guard !items.isEmpty else { return }
        self.currentItems = items

        let screenFrame = screenVisibleFrame ?? getScreenVisibleFrame(for: cursorScreenPoint)
        self.currentScreenVisibleFrame = screenFrame

        let menuSize = LeftMenuGeometry.calculateMenuSize(items: items)
        let mainFrame = LeftMenuGeometry.calculateMainMenuFrame(
            cursorPoint: cursorScreenPoint,
            menuSize: menuSize,
            screenVisibleFrame: screenFrame
        )

        let contentView = LeftMenuListView(
            items: items,
            onSelectAction: { [weak self] action in
                self?.closeAll()
                action()
            },
            onHoverSubmenu: { [weak self] index, subItems in
                self?.openSubmenu(itemIndex: index, subItems: subItems)
            },
            onHoverNonSubmenu: { [weak self] in
                self?.closeSubmenu()
            }
        )

        let hosting = NSHostingView(rootView: contentView)
        let panel = makePanel(contentView: hosting)
        panel.setFrame(mainFrame, display: true)
        self.mainPanel = panel

        panel.orderFront(nil)
        installMonitors()
    }

    private func openSubmenu(itemIndex: Int, subItems: [LeftMenuItem]) {
        guard let mainPanel else { return }
        closeSubmenu()

        let rowScreenFrame = LeftMenuGeometry.calculateItemScreenFrame(
            menuFrame: mainPanel.frame,
            items: currentItems,
            itemIndex: itemIndex
        )
        let subSize = LeftMenuGeometry.calculateMenuSize(items: subItems)
        let subFrame = LeftMenuGeometry.calculateSubmenuFrame(
            parentMenuFrame: mainPanel.frame,
            parentItemScreenFrame: rowScreenFrame,
            submenuSize: subSize,
            screenVisibleFrame: currentScreenVisibleFrame
        )

        let contentView = LeftMenuListView(
            items: subItems,
            onSelectAction: { [weak self] action in
                self?.closeAll()
                action()
            },
            onHoverSubmenu: { _, _ in },
            onHoverNonSubmenu: {}
        )

        let hosting = NSHostingView(rootView: contentView)
        let subPanel = makePanel(contentView: hosting)
        subPanel.setFrame(subFrame, display: true)
        self.submenuPanel = subPanel
        subPanel.orderFront(nil)
    }

    private func closeSubmenu() {
        submenuPanel?.close()
        submenuPanel = nil
    }

    public func closeAll() {
        removeMonitors()
        mainPanel?.close()
        mainPanel = nil
        submenuPanel?.close()
        submenuPanel = nil
        currentItems = []
    }

    private func makePanel(contentView: NSView) -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Controller giữ tham chiếu mạnh; để AppKit tự release khi close() sẽ giải phóng hai lần.
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.contentView = contentView
        return panel
    }

    private func getScreenVisibleFrame(for point: NSPoint) -> NSRect {
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) {
            return screen.visibleFrame
        }
        return NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
    }

    private func installMonitors() {
        removeMonitors()

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] event in
            guard let self = self, self.isShowing else { return event }

            if event.type == .keyDown && event.keyCode == 53 { // Phím Esc
                Task { @MainActor in self.closeAll() }
                return nil
            }

            if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type) {
                let screenPoint: NSPoint
                if let win = event.window {
                    screenPoint = win.convertToScreen(NSRect(origin: event.locationInWindow, size: .zero)).origin
                } else {
                    screenPoint = NSEvent.mouseLocation
                }

                let inMain = self.mainPanel?.frame.contains(screenPoint) ?? false
                let inSub = self.submenuPanel?.frame.contains(screenPoint) ?? false
                if !inMain && !inSub {
                    Task { @MainActor in self.closeAll() }
                    return event
                }
            }
            return event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.closeAll()
            }
        }

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.closeAll()
            }
        }

        appResignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.closeAll()
            }
        }
    }

    private func removeMonitors() {
        if let lm = localMonitor {
            NSEvent.removeMonitor(lm)
            localMonitor = nil
        }
        if let gm = globalMonitor {
            NSEvent.removeMonitor(gm)
            globalMonitor = nil
        }
        if let obs = resignObserver {
            NotificationCenter.default.removeObserver(obs)
            resignObserver = nil
        }
        if let obs = appResignObserver {
            NotificationCenter.default.removeObserver(obs)
            appResignObserver = nil
        }
    }
}

// MARK: - AppKit View & SwiftUI Modifier

public final class LeftContextMenuNSView: NSView {
    public var getItems: (() -> [LeftMenuItem])?

    public override var isFlipped: Bool { true }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        if let event = NSApp.currentEvent {
            if event.type == .rightMouseDown {
                return self
            }
            if event.type == .leftMouseDown && event.modifierFlags.contains(.control) {
                return self
            }
        }
        return nil
    }

    public override func rightMouseDown(with event: NSEvent) {
        showMenu(with: event)
    }

    public override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            showMenu(with: event)
        } else {
            super.mouseDown(with: event)
        }
    }

    private func showMenu(with event: NSEvent) {
        guard let getItems else { return }
        let items = getItems()
        guard !items.isEmpty else { return }

        guard let window = self.window else { return }
        let screenPoint = window.convertToScreen(NSRect(origin: event.locationInWindow, size: .zero)).origin
        LeftContextMenuController.shared.show(items: items, cursorScreenPoint: screenPoint)
    }
}

public struct LeftContextMenuRepresentable: NSViewRepresentable {
    let items: () -> [LeftMenuItem]

    public init(items: @escaping () -> [LeftMenuItem]) {
        self.items = items
    }

    public func makeNSView(context: Context) -> LeftContextMenuNSView {
        let view = LeftContextMenuNSView()
        view.getItems = items
        return view
    }

    public func updateNSView(_ nsView: LeftContextMenuNSView, context: Context) {
        nsView.getItems = items
    }
}

extension View {
    public func leftContextMenu(_ items: @escaping () -> [LeftMenuItem]) -> some View {
        self.overlay(LeftContextMenuRepresentable(items: items))
    }
}
