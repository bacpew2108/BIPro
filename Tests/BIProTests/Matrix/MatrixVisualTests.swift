import AppKit
import DAXEngine
import Foundation
import PBIXKit
import SwiftUI
import Testing
@testable import BIPro

@Suite struct MatrixVisualTests {

    private var matrixData: MatrixData {
        guard case .matrix(let data) = DataViewSamples.matrixAgeByRegion else {
            fatalError("matrixAgeByRegion không phải .matrix")
        }
        return data
    }

    private var gradientRule: GradientRule {
        DataViewSamples.matrixAgeByRegionGradient
    }

    @Test func matrixLayoutSoTangTieuDeVaDoRongCot() {
        let data = matrixData
        var format = VisualFormat()
        format.matrix.columnWidths["Dim_Account.branch_region"] = 115
        format.matrix.columnWidths["Dim_Client.age_group_current"] = 130

        let layout = MatrixLayout(data: data, format: format)
        // Số tầng tiêu đề cột theo columnLevels
        #expect(layout.headerTiers == 3)
        // Số tầng tiêu đề đang hiển thị khi chưa mở rộng
        #expect(layout.activeHeaderTiers == 1)
        // Độ rộng cột tiêu đề hàng theo columnWidths
        #expect(layout.rowHeaderWidth == 130)
        // Độ rộng cột giá trị theo columnWidths
        #expect(layout.width(forColumn: 0) == 115)
    }

    @Test func matrixGradientMinMidMaxVaBlankAsZero() {
        let rule = gradientRule
        let minVal: Double = 100.0
        let maxVal: Double = 200.0
        let midVal: Double = 150.0

        let minColor = MatrixGradient.color(value: minVal, min: minVal, max: maxVal, rule: rule)
        let midColor = MatrixGradient.color(value: midVal, min: minVal, max: maxVal, rule: rule)
        let maxColor = MatrixGradient.color(value: maxVal, min: minVal, max: maxVal, rule: rule)

        #expect(minColor == Color(hex: "#F7FCF5"))
        #expect(midColor == Color(hex: "#A1D99B"))
        #expect(maxColor == Color(hex: "#31A354"))

        // BLANK với nullStrategy "asZero" (0.0 < minVal 100.0 nên nhận minColor)
        let blankColor = MatrixGradient.color(value: nil, min: minVal, max: maxVal, rule: rule)
        #expect(blankColor == Color(hex: "#F7FCF5"))
    }

    @Test func minMaxBoQuaOTong() {
        let data = matrixData
        let rule = gradientRule

        guard let mm = MatrixGradient.minMax(data: data, measureIndex: 0, rule: rule) else {
            Issue.record("Không tính được min/max")
            return
        }

        // Trong matrixAgeByRegion, khoảng min/max của các ô thân bảng là 190.67 và 253.64
        #expect(abs(mm.min - 190.67) < 0.001)
        #expect(abs(mm.max - 253.64) < 0.001)
    }

    @Test func decodeDataURIChuoiSVGThat() {
        let uri = "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 12 12'><path d='M6 1.5 L11 10.5 L1 10.5 Z' fill='%23FFD54F' stroke='%2367000D' stroke-width='1.2' stroke-linejoin='round'/></svg>"

        let data = MatrixIcon.decodeDataURI(uri)
        #expect(data != nil)

        if let data = data, let text = String(data: data, encoding: .utf8) {
            #expect(text.contains("fill='#FFD54F'"))
            #expect(text.contains("stroke='#67000D'"))
        }

        let image = MatrixIcon.image(from: uri)
        #expect(image != nil)
    }

    @Test @MainActor func xuatAnhMatrix() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Matrix
            .deletingLastPathComponent() // BIProTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
        let outDir = repoRoot.appendingPathComponent("build/c-out/visuals")
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let data = matrixData
        var format = VisualFormat()
        format.gradients = [gradientRule]
        format.matrix.valuesFontSize = 11
        format.matrix.rowHeaderFontSize = 11
        format.matrix.columnHeaderFontSize = 11

        let context = VisualRenderContext(format: format)
        let matrixView = MatrixVisualView(data: data, context: context, scrollable: false)

        let matrixURL = outDir.appendingPathComponent("matrixAgeByRegion.png")
        let renderer = ImageRenderer(content: matrixView.frame(width: 688, height: 380))
        renderer.scale = 2.0
        guard let nsImg = renderer.nsImage,
              let tiff = nsImg.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            Issue.record("Không tạo được ảnh matrix 688x380")
            return
        }
        #expect(!png.isEmpty)
        try png.write(to: matrixURL)
    }
}
