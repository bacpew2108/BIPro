import AppKit
import Foundation
import SwiftUI
import Testing
import ColumnStore
import Connectors
@testable import BIPro

@Suite struct GetDataImageTests {

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

    @Test @MainActor func exportGetDataImage() async throws {
        let state = NavigatorState()
        let dir = try outputDirectory()
        let size = CGSize(width: 840, height: 580)
        let view = GetDataDialogView(state: state, scrollable: false)
        let data = try #require(png(view, size: size))
        try verifyImageRep(data, expectedSize: size, minColors: 20)
        let fileURL = dir.appendingPathComponent("get-data.png")
        try data.write(to: fileURL)
    }

    @Test @MainActor func exportNavigatorExcelImages() async throws {
        guard let url = FFixtures.sample("sales_2026.xlsx") else { return }
        let state = NavigatorState()
        await state.openSource(kind: .excel, location: url.path)
        #expect(state.phase == .ready)

        if let sales = state.items.first(where: { $0.name == "Sales" }) {
            state.toggle(sales.id)
            await state.showPreview(sales.id)
        }
        if let customers = state.items.first(where: { $0.name == "Customers" }) {
            state.toggle(customers.id)
        }

        let dir = try outputDirectory()
        let size = CGSize(width: 960, height: 620)

        // 1. navigator-excel.png
        let viewExcel = NavigatorView(state: state, scrollable: false)
        let dataExcel = try #require(png(viewExcel, size: size))
        try verifyImageRep(dataExcel, expectedSize: size, minColors: 20)
        try dataExcel.write(to: dir.appendingPathComponent("navigator-excel.png"))

        // 2. navigator-loading.png
        state.phase = .loading
        state.progress = 0.4
        let viewLoading = NavigatorView(state: state, scrollable: false)
        let dataLoading = try #require(png(viewLoading, size: size))
        try verifyImageRep(dataLoading, expectedSize: size, minColors: 20)
        try dataLoading.write(to: dir.appendingPathComponent("navigator-loading.png"))
    }

    @Test @MainActor func exportNavigatorErrorImage() async throws {
        let state = NavigatorState()
        await state.openSource(kind: .excel, location: "/khong/co/file.xlsx")
        #expect(state.items.isEmpty)
        if case .failed = state.phase {
            // expected
        } else {
            Issue.record("State should be failed for non-existent file")
        }

        let dir = try outputDirectory()
        let size = CGSize(width: 960, height: 620)
        let view = NavigatorView(state: state, scrollable: false)
        let data = try #require(png(view, size: size))
        try verifyImageRep(data, expectedSize: size, minColors: 20)
        try data.write(to: dir.appendingPathComponent("navigator-error.png"))
    }

    @Test @MainActor func getDataFlowViewIntegration() async throws {
        guard let url = FFixtures.sample("sales_2026.csv") else { return }
        let state = NavigatorState()
        #expect(state.phase == .choosingSource)

        var loadedTables: [LoadedTable]?
        var transformedTables: [LoadedTable]?
        var closed = false

        let flowView = GetDataFlowView(
            state: state,
            existingTableNames: ["Existing"],
            pickFile: { _ in url.path },
            onLoad: { tables in loadedTables = tables; return nil },
            onTransform: { tables in transformedTables = tables },
            onClose: { closed = true },
            scrollable: false
        )

        // Verify flowView body can be built
        _ = flowView.body

        // Initial phase is .choosingSource
        #expect(state.phase == .choosingSource)
        #expect(!closed)
        #expect(loadedTables == nil)
        #expect(transformedTables == nil)

        // Open source
        await state.openSource(kind: .csv, location: url.path)
        #expect(state.phase == .ready)
        #expect(state.items.count == 1)

        // Single item should be auto-checked and previewed
        let itemId = try #require(state.items.first?.id)
        #expect(state.items.first?.name == "sales_2026")

        // Load tables
        state.toggle(itemId) // ensures checked if not already
        let tables = await state.load(existingNames: ["Existing"])
        #expect(tables != nil)
        #expect(tables?.count == 1)
        #expect(tables?.first?.name == "sales_2026")
    }
}
