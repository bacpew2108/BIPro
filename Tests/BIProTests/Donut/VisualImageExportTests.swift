import AppKit
import DAXEngine
import Foundation
import PBIXKit
import SwiftUI
import Testing
@testable import BIPro

@Suite struct VisualImageExportTests {

    @MainActor
    private func renderToPNG(view: some View, targetSize: CGSize) -> Data? {
        let renderer = ImageRenderer(content: view.frame(width: targetSize.width, height: targetSize.height))
        renderer.proposedSize = ProposedViewSize(targetSize)
        renderer.scale = 2.0
        if let cgImage = renderer.cgImage {
            let rep = NSBitmapImageRep(cgImage: cgImage)
            return rep.representation(using: .png, properties: [:])
        }
        if let nsImage = renderer.nsImage,
           let tiff = nsImage.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff) {
            return rep.representation(using: .png, properties: [:])
        }
        return nil
    }

    @Test @MainActor func exportAllVisualPNGs() throws {
        let fileURL = URL(fileURLWithPath: #filePath)
        let repoRoot = fileURL
            .deletingLastPathComponent() // Donut
            .deletingLastPathComponent() // BIProTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
        let outDir = repoRoot.appendingPathComponent("build/c-out/visuals")
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let fixtureURL = repoRoot.appendingPathComponent("Tests/BIProTests/Map/Fixtures/usa.states.topo.json")
        let topoData = try Data(contentsOf: fixtureURL)
        let topoMap = try TopoJSON.decode(topoData)

        // 1. donut.png (420x380, từ donutPurpose)
        guard case .categorical(let donutData) = DataViewSamples.donutPurpose else {
            Issue.record("donutPurpose không phải categorical")
            return
        }
        var donutFormat = VisualFormat()
        donutFormat.dataLabels.precision = 1
        donutFormat.legend.position = "Bottom"
        let donutView = DonutChartView(
            data: donutData,
            context: VisualRenderContext(format: donutFormat),
            interactive: false
        )
        let donutSize = CGSize(width: 420, height: 380)
        let pngDonut = renderToPNG(view: donutView, targetSize: donutSize)
        #expect(pngDonut != nil && !pngDonut!.isEmpty)
        if let data = pngDonut {
            try data.write(to: outDir.appendingPathComponent("donut.png"))
        }

        // 2. donutHighlight.png (420x380, cùng mẫu, highlights mỗi lát x0.4)
        var donutHighlightData = donutData
        var hlGrid = donutData.values
        for m in hlGrid.indices {
            for s in hlGrid[m].indices {
                for c in hlGrid[m][s].indices {
                    if let v = NumberDisplay.numericValue(hlGrid[m][s][c].value) {
                        hlGrid[m][s][c] = DataCell(.double(v * 0.4), formatString: hlGrid[m][s][c].formatString)
                    }
                }
            }
        }
        donutHighlightData.highlights = hlGrid
        let donutHlView = DonutChartView(
            data: donutHighlightData,
            context: VisualRenderContext(format: donutFormat),
            interactive: false
        )
        let pngDonutHl = renderToPNG(view: donutHlView, targetSize: donutSize)
        #expect(pngDonutHl != nil && !pngDonutHl!.isEmpty)
        if let data = pngDonutHl {
            try data.write(to: outDir.appendingPathComponent("donutHighlight.png"))
        }

        // 3. treemap.png (640x380, mẫu 2 cấp)
        guard case .categorical(let treemapData) = DataViewSamples.treemapProducts else {
            Issue.record("treemapProducts không phải categorical")
            return
        }
        let treemapView = TreemapView(
            data: treemapData,
            context: VisualRenderContext(),
            interactive: false
        )
        let treemapSize = CGSize(width: 640, height: 380)
        let pngTreemap = renderToPNG(view: treemapView, targetSize: treemapSize)
        #expect(pngTreemap != nil && !pngTreemap!.isEmpty)
        if let data = pngTreemap {
            try data.write(to: outDir.appendingPathComponent("treemap.png"))
        }

        // 4. treemapOneLevel.png (640x380, 2 nhóm như page-D3.png)
        let catLevels = [FieldInfo(queryRef: "Product", displayName: "Sản phẩm", role: "Group", isMeasure: false)]
        let categories = ["Bank account or service", "Credit card"].map { CategoryKey(values: [.string($0)]) }
        let measures = [FieldInfo(queryRef: "Complaints", displayName: "Số khiếu nại", role: "Values", formatString: "#,0", isMeasure: true)]
        let oneLevelValues: [[[DataCell]]] = [[[
            DataCell(.double(14_091), formatString: "#,0"),
            DataCell(.double(9_328), formatString: "#,0")
        ]]]
        let treemapOneLevelData = CategoricalData(
            categoryLevels: catLevels,
            categories: categories,
            seriesField: nil,
            series: [],
            measures: measures,
            values: oneLevelValues,
            highlights: nil,
            isReduced: false
        )
        let treemapOneLevelView = TreemapView(
            data: treemapOneLevelData,
            context: VisualRenderContext(),
            interactive: false
        )
        let pngTreemapOne = renderToPNG(view: treemapOneLevelView, targetSize: treemapSize)
        #expect(pngTreemapOne != nil && !pngTreemapOne!.isEmpty)
        if let data = pngTreemapOne {
            try data.write(to: outDir.appendingPathComponent("treemapOneLevel.png"))
        }

        // 5. shapeMap.png (616x380, ít nhất 8 bang gồm New Mexico, California, Arizona, Alaska, Hawaii)
        let stateNames = [
            "California", "New Mexico", "Arizona", "Texas",
            "Florida", "Washington", "Alaska", "Hawaii", "New York"
        ]
        let stateColors = [
            "#C0392B", "#C0392B", "#E65100", "#81B29A",
            "#E65100", "#81B29A", "#81B29A", "#81B29A", "#81B29A"
        ]
        let stateAmounts: [Double] = [21e6, 8e6, 6e6, 15e6, 9e6, 4e6, 3e6, 2e6, 12e6]
        let shapeMapData = CategoricalData(
            categoryLevels: [FieldInfo(queryRef: "Dim_District.state_name", displayName: "Bang", role: "Category", isMeasure: false)],
            categories: stateNames.map { CategoryKey(values: [.string($0)]) },
            seriesField: nil,
            series: [],
            measures: [FieldInfo(queryRef: "Fact_Loan.Amount", displayName: "Giá trị cho vay", role: "Values", formatString: "\\$#,0", isMeasure: true)],
            values: [[zip(stateAmounts, stateColors).map { DataCell(.double($0), formatString: "\\$#,0", fillColor: $1) }]],
            highlights: nil,
            isReduced: false
        )
        let shapeMapView = ShapeMapView(
            data: shapeMapData,
            map: topoMap,
            context: VisualRenderContext(),
            interactive: false
        )
        let shapeMapSize = CGSize(width: 616, height: 380)
        let pngShapeMap = renderToPNG(view: shapeMapView, targetSize: shapeMapSize)
        #expect(pngShapeMap != nil && !pngShapeMap!.isEmpty)
        if let data = pngShapeMap {
            try data.write(to: outDir.appendingPathComponent("shapeMap.png"))
        }

        // 6. tooltip.png (khung tooltip với 5 dòng như tooltip-bar.png)
        let tooltipRows = [
            TooltipRow(name: "Nhóm tuổi lúc vay", value: "35-49"),
            TooltipRow(name: "NPL% (số HĐ)", value: "11%"),
            TooltipRow(name: "NPL% (giá trị)", value: "14%"),
            TooltipRow(name: "Số HĐ nợ xấu", value: "26"),
            TooltipRow(name: "Số HĐ", value: "227")
        ]
        let tooltipView = VisualTooltipView(rows: tooltipRows)
        let tooltipSize = CGSize(width: 280, height: 200)
        let pngTooltip = renderToPNG(view: tooltipView, targetSize: tooltipSize)
        #expect(pngTooltip != nil && !pngTooltip!.isEmpty)
        if let data = pngTooltip {
            try data.write(to: outDir.appendingPathComponent("tooltip.png"))
        }
    }
}
