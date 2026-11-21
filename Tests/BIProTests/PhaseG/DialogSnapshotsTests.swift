import AppKit
import ColumnStore
import Connectors
import Foundation
import MEngine
import SwiftUI
import Testing
@testable import BIPro

@Suite("PhaseG2 — Secondary Dialogs Dark Mode & English Snapshots")
@MainActor
struct DialogSnapshotsTests {
    private static let outputDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("build/g-out/g2-dialogs", isDirectory: true)

    private func renderDarkPNG(_ view: some View, size: CGSize) throws -> (Data, NSBitmapImageRep) {
        let renderer = ImageRenderer(
            content: view
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, .dark)
        )
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = 2
        let cg = try #require(renderer.cgImage)
        let rep = NSBitmapImageRep(cgImage: cg)
        let data = try #require(rep.representation(using: .png, properties: [:]))
        #expect(data.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))
        return (data, rep)
    }

    /// Kiểm tra ảnh có nền tối thực sự (không bị trôi về trắng chói) và đủ sắc độ UI.
    private func verifyDarkSnapshot(_ rep: NSBitmapImageRep, name: String, minColors: Int = 12) {
        let w = rep.pixelsWide
        let h = rep.pixelsHigh
        #expect(w >= 400 && h >= 200, "\(name) kích thước bất thường: \(w)x\(h)")

        var colors = Set<UInt32>()
        var luminanceSum = 0.0
        var samples = 0
        let step = max(1, Int(sqrt(Double(w * h) / 2500.0)))
        for y in stride(from: 0, to: h, by: step) {
            for x in stride(from: 0, to: w, by: step) {
                if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) {
                    let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
                    luminanceSum += 0.2126 * r + 0.7152 * g + 0.0722 * b
                    samples += 1
                    let key = (UInt32((r * 255).rounded()) << 16)
                        | (UInt32((g * 255).rounded()) << 8)
                        | UInt32((b * 255).rounded())
                    colors.insert(key)
                }
            }
        }
        let avgLum = samples > 0 ? luminanceSum / Double(samples) : 1.0
        #expect(colors.count >= minColors, "\(name) quá ít màu (\(colors.count))")
        #expect(avgLum < 0.35, "\(name) nền quá sáng cho Dark Mode (avgLum=\(String(format: "%.3f", avgLum)))")
    }

    private func sampleTable() throws -> TableData {
        let col0 = TableColumn(name: "OrderID", data: ColumnBuilder.integers((1001...1008).map { Int64($0) }))
        let col1 = TableColumn(name: "Region", data: ColumnBuilder.strings(["North", "Central", "South", "North", nil, "South", "North", "Central"]))
        let col2 = TableColumn(name: "Qty", data: ColumnBuilder.integers([12, 4, 25, 1, 8, 14, 3, 19]))
        let col3 = TableColumn(name: "Amount", data: ColumnBuilder.doubles([440.0, 1820.5, 750.0, 95.0, 320.0, 1440.0, 110.0, 2300.0]))
        return try TableData(columns: [col0, col1, col2, col3])
    }

    @Test("Kết xuất 7 hộp thoại phụ ở Dark Mode + Tiếng Anh và kiểm chứng độ tương phản tối")
    func renderAllSecondaryDialogsDarkEnglish() async throws {
        try FileManager.default.createDirectory(at: Self.outputDir, withIntermediateDirectories: true)

        let prevLang = AppPreferences.shared.language
        let prevApp = AppPreferences.shared.appearance
        defer {
            AppPreferences.shared.language = prevLang
            AppPreferences.shared.appearance = prevApp
        }
        AppPreferences.shared.language = .en
        AppPreferences.shared.appearance = .dark

        // 1. Get Data Dialog
        do {
            let navState = NavigatorState()
            let (data, rep) = try renderDarkPNG(GetDataDialogView(state: navState, scrollable: false), size: CGSize(width: 840, height: 580))
            verifyDarkSnapshot(rep, name: "get-data-dark-en.png")
            try data.write(to: Self.outputDir.appendingPathComponent("get-data-dark-en.png"))
        }

        // 2. Navigator Dialog
        do {
            let navState = NavigatorState()
            if let url = FFixtures.sample("sales_2026.xlsx") {
                await navState.openSource(kind: .excel, location: url.path)
                if let first = navState.items.first {
                    navState.toggle(first.id)
                    await navState.showPreview(first.id)
                }
            }
            let (data, rep) = try renderDarkPNG(NavigatorView(state: navState, onTransform: { _ in }, scrollable: false), size: CGSize(width: 960, height: 620))
            verifyDarkSnapshot(rep, name: "navigator-dark-en.png")
            try data.write(to: Self.outputDir.appendingPathComponent("navigator-dark-en.png"))
        }

        // 3. Enter Data Dialog
        do {
            var table = EnterDataTable(name: "SalesTargets")
            try table.paste("Region\tTarget\tOwner\nNorth\t12000\tAlice\nCentral\t9500\tBob\nSouth\t15400\tCarol")
            let view = EnterDataView(table: table, mode: .create, scrollable: false, onCommit: { _ in nil }, onCancel: {})
            let (data, rep) = try renderDarkPNG(view, size: CGSize(width: 760, height: 560))
            verifyDarkSnapshot(rep, name: "enter-data-dark-en.png")
            try data.write(to: Self.outputDir.appendingPathComponent("enter-data-dark-en.png"))
        }

        // 4. Power Query Editor Window
        do {
            let table = try sampleTable()
            let qeState = QueryEditorState()
            let loaded = LoadedTable(name: "Sales", data: table, origin: LoadedOrigin(kind: .csv, location: "/tmp/sales.csv", itemName: "Sales", itemKind: .file))
            qeState.addQuery(from: loaded)
            await qeState.refresh()
            let view = QueryEditorWindow(
                state: qeState,
                existingTableNames: [],
                onApply: {},
                onClose: {},
                scrollable: false,
                initialTab: .home,
                initialSelectedColumns: ["Region"]
            )
            let (data, rep) = try renderDarkPNG(view, size: CGSize(width: 1280, height: 800))
            verifyDarkSnapshot(rep, name: "query-editor-dark-en.png")
            try data.write(to: Self.outputDir.appendingPathComponent("query-editor-dark-en.png"))
        }

        // 5. File Options Dialog
        do {
            let view = FileOptionsView(
                options: FileOptions(autoDateTime: true, autodetectRelationships: true),
                autoDateTimeBlocker: nil,
                onCommit: { _ in nil },
                onCancel: {}
            )
            let (data, rep) = try renderDarkPNG(view, size: CGSize(width: 460, height: 260))
            verifyDarkSnapshot(rep, name: "file-options-dark-en.png")
            try data.write(to: Self.outputDir.appendingPathComponent("file-options-dark-en.png"))
        }

        // 6. Export Sheet (PDF)
        do {
            let view = ExportSheet(
                kind: .pdf,
                visiblePageCount: 4,
                currentPageName: "Overview",
                isExporting: .constant(false),
                progressText: .constant(""),
                errorMessage: .constant(nil),
                onExportPDF: { _ in },
                onExportPNG: { _ in },
                onCancel: {}
            )
            let (data, rep) = try renderDarkPNG(view, size: CGSize(width: 420, height: 220))
            verifyDarkSnapshot(rep, name: "export-sheet-pdf-dark-en.png")
            try data.write(to: Self.outputDir.appendingPathComponent("export-sheet-pdf-dark-en.png"))
        }

        // 7. Export Sheet (PNG)
        do {
            let view = ExportSheet(
                kind: .png,
                visiblePageCount: 4,
                currentPageName: "Overview",
                isExporting: .constant(false),
                progressText: .constant(""),
                errorMessage: .constant(nil),
                onExportPDF: { _ in },
                onExportPNG: { _ in },
                onCancel: {}
            )
            let (data, rep) = try renderDarkPNG(view, size: CGSize(width: 420, height: 200))
            verifyDarkSnapshot(rep, name: "export-sheet-png-dark-en.png")
            try data.write(to: Self.outputDir.appendingPathComponent("export-sheet-png-dark-en.png"))
        }
    }
}
