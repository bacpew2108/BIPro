import AppKit
import Foundation
import SwiftUI
import Testing
import ColumnStore
import Connectors
import MEngine
@testable import BIPro

@Suite struct QueryEditorImageTests {

    @MainActor
    private func png(_ view: some View, size: CGSize) -> Data? {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height).background(Color.white))
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = 2
        guard let image = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    private func outputDirectory() throws -> URL {
        try FFixtures.outputDirectory("ui")
    }

    private func verifyImageRep(_ data: Data, expectedSize: CGSize, minColors: Int = 20) throws {
        let rep = try #require(NSBitmapImageRep(data: data))
        #expect(rep.pixelsWide == Int(expectedSize.width * 2))
        #expect(rep.pixelsHigh == Int(expectedSize.height * 2))

        let width = rep.pixelsWide
        let height = rep.pixelsHigh
        var colors = Set<UInt32>()
        let totalPixels = width * height
        let step = max(1, Int(sqrt(Double(totalPixels) / 2000.0)))
        for y in stride(from: 0, to: height, by: step) {
            for x in stride(from: 0, to: width, by: step) {
                if let color = rep.colorAt(x: x, y: y) {
                    let r = UInt32((color.redComponent * 255).rounded())
                    let g = UInt32((color.greenComponent * 255).rounded())
                    let b = UInt32((color.blueComponent * 255).rounded())
                    let a = UInt32((color.alphaComponent * 255).rounded())
                    let rgba = (r << 24) | (g << 16) | (b << 8) | a
                    colors.insert(rgba)
                }
            }
        }
        #expect(colors.count >= minColors, "Ảnh phải có ít nhất \(minColors) màu khác nhau (hiện có \(colors.count))")
    }

    private func createSampleTable() throws -> TableData {
        let col0 = TableColumn(name: "OrderID", data: ColumnBuilder.integers((1001...1012).map { Int64($0) }))
        let col1 = TableColumn(name: "OrderDate", data: ColumnBuilder.dateTimes((0..<12).map { 45350.0 + Double($0) }))
        let col2 = TableColumn(name: "Region", data: ColumnBuilder.strings([
            "Bắc", "Trung", "Nam", "Bắc", nil, "Nam", "Bắc", "Trung", "Nam", "Bắc", "Trung", "Nam"
        ]))
        let col3 = TableColumn(name: "Qty", data: ColumnBuilder.integers([
            12, 4, 25, 1, 8, 14, 3, 19, 2, 7, 30, 15
        ]))
        let col4 = TableColumn(name: "Amount", data: ColumnBuilder.doubles([
            440.0, 1820.5, 750.0, 0.0, 320.0, 1440.0, 95.0, 2300.0, 110.0, 85.0, 4120.0, 950.0
        ]))
        let errorMask: [Int: [Int: String]] = [
            4: [3: "DataFormat.Error: We couldn't convert to Number. Details: South"]
        ]
        return try TableData(columns: [col0, col1, col2, col3, col4], errorMask: errorMask)
    }

    @Test @MainActor func exportQEMainImage() async throws {
        let table = try createSampleTable()
        let state = QueryEditorState()
        let loaded = LoadedTable(name: "Sales", data: table, origin: LoadedOrigin(kind: .csv, location: "/tmp/sales.csv", itemName: "Sales", itemKind: .file))
        state.addQuery(from: loaded)
        await state.refresh()

        let dir = try outputDirectory()
        let size = CGSize(width: 1280, height: 800)
        let view = QueryEditorWindow(
            state: state,
            existingTableNames: [],
            onApply: {},
            onClose: {},
            scrollable: false,
            initialTab: .home,
            initialSelectedColumns: ["Region"]
        )
        let data = try #require(png(view, size: size))
        try verifyImageRep(data, expectedSize: size, minColors: 20)
        let fileURL = dir.appendingPathComponent("qe-main.png")
        try data.write(to: fileURL)
    }

    @Test @MainActor func exportQETransformImage() async throws {
        let table = try createSampleTable()
        let state = QueryEditorState()
        let loaded = LoadedTable(name: "Sales", data: table, origin: LoadedOrigin(kind: .csv, location: "/tmp/sales.csv", itemName: "Sales", itemKind: .file))
        state.addQuery(from: loaded)
        await state.refresh()

        state.perform(.filterEquals(column: "Region", values: [.text("Bắc"), .text("Nam")]))
        state.perform(.sortRows([SortKey(column: "Qty", descending: true)]))
        await state.refresh()

        let dir = try outputDirectory()
        let size = CGSize(width: 1280, height: 800)
        let view = QueryEditorWindow(
            state: state,
            existingTableNames: [],
            onApply: {},
            onClose: {},
            scrollable: false,
            initialTab: .transform,
            initialSelectedColumns: ["Qty"]
        )
        let data = try #require(png(view, size: size))
        try verifyImageRep(data, expectedSize: size, minColors: 20)
        let fileURL = dir.appendingPathComponent("qe-transform.png")
        try data.write(to: fileURL)
    }

    @Test @MainActor func exportQEErrorImage() async throws {
        let table = try createSampleTable()
        let state = QueryEditorState()
        let loaded = LoadedTable(name: "Sales", data: table, origin: LoadedOrigin(kind: .csv, location: "/tmp/sales.csv", itemName: "Sales", itemKind: .file))
        state.addQuery(from: loaded)
        await state.refresh()

        state.perform(.removeColumns(["OrderID"]))
        if let idx = state.selectedStepIndex {
            state.setExpression(at: idx, "Table.SelectRows(#\"Changed Type\", each ([NonExistentColumn] > 0))")
        }
        await state.refresh()

        let dir = try outputDirectory()
        let size = CGSize(width: 1280, height: 800)
        let view = QueryEditorWindow(
            state: state,
            existingTableNames: [],
            onApply: {},
            onClose: {},
            scrollable: false,
            initialTab: .home,
            initialSelectedColumns: ["Qty"]
        )
        let data = try #require(png(view, size: size))
        try verifyImageRep(data, expectedSize: size, minColors: 20)
        let fileURL = dir.appendingPathComponent("qe-error.png")
        try data.write(to: fileURL)
    }

    @Test @MainActor func exportQEAdvancedImage() async throws {
        let table = try createSampleTable()
        let state = QueryEditorState()
        let loaded = LoadedTable(name: "Sales", data: table, origin: LoadedOrigin(kind: .csv, location: "/tmp/sales.csv", itemName: "Sales", itemKind: .file))
        state.addQuery(from: loaded)
        await state.refresh()

        let dir = try outputDirectory()
        let size = CGSize(width: 760, height: 520)
        let view = AdvancedEditorContent(
            queryName: state.selectedQuery?.name ?? "Sales",
            initialSource: state.advancedSource,
            scrollable: false,
            onApply: { _ in nil },
            onCancel: {}
        )
        let data = try #require(png(view, size: size))
        try verifyImageRep(data, expectedSize: size, minColors: 15)
        let fileURL = dir.appendingPathComponent("qe-advanced.png")
        try data.write(to: fileURL)
    }
}
