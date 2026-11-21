import AppKit
import DAXEngine
import Foundation
import PBIXKit
import SwiftUI
import Testing
@testable import BIPro

@Suite("US3 — Offline Geo Atlas & GeoMapView")
struct GeoMapTests {

    @Test("OfflineGeoAtlas resolves US states (full + postal) and countries offline")
    func offlineGeoLookup() {
        #expect(OfflineGeoAtlas.lookup("California")?.isUSState == true)
        #expect(OfflineGeoAtlas.lookup("CA")?.isUSState == true)
        #expect(OfflineGeoAtlas.lookup("New York")?.isUSState == true)
        #expect(OfflineGeoAtlas.lookup("Vietnam")?.isUSState == false)
        #expect(OfflineGeoAtlas.lookup("Việt Nam")?.isUSState == false)
        #expect(OfflineGeoAtlas.lookup("UnknownLand123") == nil)
    }

    @Test("GeoMapLayout computes normalized coordinates and bubble radii")
    func geoMapLayoutMath() {
        let cat = FieldInfo(queryRef: "Geo.State", displayName: "State", role: "Category", formatString: nil, isMeasure: false)
        let sz = FieldInfo(queryRef: "Sales.Rev", displayName: "Rev", role: "Size", formatString: "#,0", isMeasure: true)
        let data = CategoricalData(
            categoryLevels: [cat],
            categories: [
                CategoryKey(values: [.string("California")]),
                CategoryKey(values: [.string("Texas")]),
                CategoryKey(values: [.string("New York")]),
            ],
            seriesField: nil,
            series: [],
            measures: [sz],
            values: [[[DataCell(.double(100)), DataCell(.double(400)), DataCell(.double(900))]]],
            highlights: nil,
            isReduced: false
        )
        let layout = GeoMapLayout(data: data)
        #expect(layout.points.count == 3)
        #expect(layout.unmatchedCount == 0)
        #expect(layout.points[2].radius > layout.points[0].radius)
    }

    @MainActor
    @Test("GeoMapView renders map and filledMap cleanly offline")
    func renderGeoMaps() {
        let cat = FieldInfo(queryRef: "Geo.Country", displayName: "Country", role: "Category", formatString: nil, isMeasure: false)
        let sz = FieldInfo(queryRef: "Sales.Rev", displayName: "Rev", role: "Size", formatString: "#,0", isMeasure: true)
        let data = CategoricalData(
            categoryLevels: [cat],
            categories: [
                CategoryKey(values: [.string("Vietnam")]),
                CategoryKey(values: [.string("Japan")]),
                CategoryKey(values: [.string("United States")]),
            ],
            seriesField: nil,
            series: [],
            measures: [sz],
            values: [[[DataCell(.double(120)), DataCell(.double(340)), DataCell(.double(800))]]],
            highlights: nil,
            isReduced: false
        )
        let ctx = VisualRenderContext(
            theme: ReportTheme.fallback,
            format: VisualFormat(objects: ObjectProperties(nil)),
            selection: [],
            slicerSelection: SlicerSelection(),
            actions: .none,
            visualSize: CGSize(width: 340, height: 220),
            isExporting: true
        )
        for isFilled in [false, true] {
            let view = GeoMapView(data: data, isFilled: isFilled, topoMap: nil, context: ctx, interactive: false)
            let renderer = ImageRenderer(content: view.frame(width: 340, height: 220).background(Color.white))
            renderer.scale = 1
            let cg = renderer.cgImage
            #expect(cg != nil)
            #expect((cg?.width ?? 0) > 0 && (cg?.height ?? 0) > 0)
        }
    }
}
