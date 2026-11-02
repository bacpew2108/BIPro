import AppKit
import DAXEngine
import Foundation
import PBIXKit
import SwiftUI
import Testing
@testable import BIPro

@Suite struct DropdownSlicerTests {

    private var slicerData: SlicerData {
        guard case .slicer(let data) = DataViewSamples.slicerYearQuarterMonth else {
            fatalError("slicerYearQuarterMonth không phải .slicer")
        }
        return data
    }

    @Test func chonDon() {
        let roots = slicerData.roots
        let emptySelection = SlicerSelection([])

        // Bấm chọn một năm (2016)
        let path2016: [Value] = [.integer(2016)]
        let sel1 = SlicerTree.toggle(selection: emptySelection, path: path2016, additive: false, roots: roots)
        #expect(sel1.paths == [path2016])
        #expect(SlicerTree.state(of: path2016, in: sel1, roots: roots) == .on)

        // Bấm lại chính dòng đó trong single select -> deselect về rỗng
        let sel2 = SlicerTree.toggle(selection: sel1, path: path2016, additive: false, roots: roots)
        #expect(sel2.isEmpty)
    }

    @Test func cmdThemBot() {
        let roots = slicerData.roots
        let path2016: [Value] = [.integer(2016)]
        let path2017: [Value] = [.integer(2017)]

        // Bắt đầu từ 2016
        let sel1 = SlicerSelection([path2016])

        // ⌘ bấm 2017: thêm vào
        let sel2 = SlicerTree.toggle(selection: sel1, path: path2017, additive: true, roots: roots)
        #expect(sel2.paths == [path2016, path2017])
        #expect(SlicerTree.state(of: path2016, in: sel2, roots: roots) == .on)
        #expect(SlicerTree.state(of: path2017, in: sel2, roots: roots) == .on)

        // ⌘ bấm lại 2016: bớt ra
        let sel3 = SlicerTree.toggle(selection: sel2, path: path2016, additive: true, roots: roots)
        #expect(sel3.paths == [path2017])
        #expect(SlicerTree.state(of: path2016, in: sel3, roots: roots) == .off)
        #expect(SlicerTree.state(of: path2017, in: sel3, roots: roots) == .on)
    }

    @Test func chonChaRoiBamConVaTrangThaiMixed() {
        let roots = slicerData.roots
        let path2016: [Value] = [.integer(2016)]
        let pathQ1: [Value] = [.integer(2016), .string("Q1")]

        // 1. Chọn cha (2016)
        let sel1 = SlicerSelection([path2016])
        #expect(SlicerTree.state(of: path2016, in: sel1, roots: roots) == .on)
        #expect(SlicerTree.state(of: pathQ1, in: sel1, roots: roots) == .on)

        // 2. Bấm con (Q1) ở chế độ chọn đơn
        let sel2 = SlicerTree.toggle(selection: sel1, path: pathQ1, additive: false, roots: roots)
        #expect(sel2.paths == [pathQ1])

        // 3. Trạng thái của con là .on, trạng thái của cha trở thành .mixed
        #expect(SlicerTree.state(of: pathQ1, in: sel2, roots: roots) == .on)
        #expect(SlicerTree.state(of: path2016, in: sel2, roots: roots) == .mixed)
    }

    @Test func summaryHienThiDung() {
        let roots = slicerData.roots

        // Chưa chọn gì -> "All"
        #expect(SlicerTree.summary(selection: SlicerSelection([]), roots: roots) == "All")

        // Chọn 1 giá trị -> tên giá trị
        let sel2016 = SlicerSelection([[.integer(2016)]])
        #expect(SlicerTree.summary(selection: sel2016, roots: roots) == "2016")

        // Chọn nhiều giá trị -> "Nhiều lựa chọn"
        let selMulti = SlicerSelection([[.integer(2016)], [.integer(2017)]])
        #expect(SlicerTree.summary(selection: selMulti, roots: roots) == "Nhiều lựa chọn")
    }

    @Test @MainActor func xuatAnhSlicerDong() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Slicer
            .deletingLastPathComponent() // BIProTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
        let outDir = repoRoot.appendingPathComponent("build/c-out/visuals")
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let data = slicerData
        var format = VisualFormat()
        format.slicer.headerShow = true
        format.slicer.headerFontColor = .string("#14213D")
        format.slicer.headerTextSize = 10
        let context = VisualRenderContext(format: format)
        let slicerView = DropdownSlicerView(data: data, title: "Năm, Quý, Tháng", context: context)

        let slicerURL = outDir.appendingPathComponent("slicerYearQuarterMonth.png")
        let renderer = ImageRenderer(content: slicerView.frame(width: 364, height: 64))
        renderer.scale = 2.0
        guard let nsImg = renderer.nsImage,
              let tiff = nsImg.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            Issue.record("Không tạo được ảnh slicer 364x64")
            return
        }
        #expect(!png.isEmpty)
        try png.write(to: slicerURL)
    }
}
