import AppKit
import DAXEngine
import Foundation
import PBIXKit
import SwiftUI
import Testing
@testable import BIPro

@Suite struct CardVisualTests {

    @Test func cardCreditInflowDungDinhDangPowerBI() {
        guard case .single(let data) = DataViewSamples.cardCreditInflow else {
            Issue.record("cardCreditInflow không phải .single")
            return
        }
        var format = VisualFormat()
        format.dataLabels.displayUnits = .auto
        // Chuỗi hiển thị của cardCreditInflow là "$3bn"
        let text = CardVisual.text(for: data, format: format)
        #expect(text == "$3bn")
    }

    @Test func cardDeltaMauChuLayTuFontColor() {
        guard case .single(let data) = DataViewSamples.cardDeltaLabel else {
            Issue.record("cardDeltaLabel không phải .single")
            return
        }
        let format = VisualFormat()
        let color = CardVisual.valueColor(for: data, format: format)
        #expect(color == Color(hex: "#2E7D32"))
    }

    @Test func cardBlankHienNhanTrong() {
        let measureInfo = FieldInfo(
            queryRef: "Fact.BlankVal",
            displayName: "Giá trị rỗng",
            role: "Values",
            formatString: nil,
            isMeasure: true
        )
        let blankData = SingleValueData(measure: measureInfo, cell: .blank)
        let format = VisualFormat()
        #expect(CardVisual.text(for: blankData, format: format) == "(Trống)")
    }

    @Test func anNhanDanhMuc() {
        guard case .single(let data) = DataViewSamples.cardCreditInflow else { return }
        var format = VisualFormat()
        format.categoryLabels.show = false
        let context = VisualRenderContext(format: format)
        let view = CardVisualView(data: data, context: context)
        #expect(view.context.format.categoryLabels.show == false)
    }

    @Test @MainActor func xuatAnhCard() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Card
            .deletingLastPathComponent() // BIProTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
        let outDir = repoRoot.appendingPathComponent("build/c-out/visuals")
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        // 1. Card 300x108
        guard case .single(let creditData) = DataViewSamples.cardCreditInflow else { return }
        var creditFormat = VisualFormat()
        creditFormat.dataLabels.fontSize = 20
        creditFormat.dataLabels.color = .string("#2E7D32")
        creditFormat.categoryLabels.show = true
        creditFormat.categoryLabels.fontSize = 10
        let creditContext = VisualRenderContext(format: creditFormat)
        let creditView = CardVisualView(data: creditData, context: creditContext)

        let creditURL = outDir.appendingPathComponent("cardCreditInflow.png")
        let renderer1 = ImageRenderer(content: creditView.frame(width: 300, height: 108).background(Color.white))
        renderer1.scale = 2.0
        guard let nsImg1 = renderer1.nsImage,
              let tiff1 = nsImg1.tiffRepresentation,
              let rep1 = NSBitmapImageRep(data: tiff1),
              let png1 = rep1.representation(using: .png, properties: [:]) else {
            Issue.record("Không tạo được ảnh card 300x108")
            return
        }
        #expect(!png1.isEmpty)
        try png1.write(to: creditURL)

        // 2. Card Δ 236x26
        guard case .single(let deltaData) = DataViewSamples.cardDeltaLabel else { return }
        var deltaFormat = VisualFormat()
        deltaFormat.dataLabels.fontSize = 9
        deltaFormat.categoryLabels.show = false
        let deltaContext = VisualRenderContext(format: deltaFormat)
        let deltaView = CardVisualView(data: deltaData, context: deltaContext)

        let deltaURL = outDir.appendingPathComponent("cardDeltaLabel.png")
        let renderer2 = ImageRenderer(content: deltaView.frame(width: 236, height: 26).background(Color.white))
        renderer2.scale = 2.0
        guard let nsImg2 = renderer2.nsImage,
              let tiff2 = nsImg2.tiffRepresentation,
              let rep2 = NSBitmapImageRep(data: tiff2),
              let png2 = rep2.representation(using: .png, properties: [:]) else {
            Issue.record("Không tạo được ảnh card Δ 236x26")
            return
        }
        #expect(!png2.isEmpty)
        try png2.write(to: deltaURL)
    }
}
