// Gói Q: VisualDataLoader chạy truy vấn card qua engine thật (MiniBank), cache theo văn bản DAX.
import DAXEngine
import DAXTestSupport
import Testing
@testable import BIPro

@Suite struct VisualDataLoaderTests {
    private func cardSpec() -> VisualQuerySpec {
        let field = FieldInfo(queryRef: "Fact_Trans.Two", displayName: "Hai", role: "Values", formatString: "0", isMeasure: true)
        var spec = VisualQuerySpec(visualID: "card1", visualType: "card")
        spec.shape = .card
        spec.measures = [QueryMeasure(field: field, table: "Fact_Trans", measure: "Two", resultName: "Two", ignore: true, purpose: .value)]
        return spec
    }

    private func engine() -> DAXEngine {
        DAXEngine(store: MiniBank.makeStore(), catalog: Catalog(schema: MiniBank.schema, measures: [
            ModelMeasureInput(table: "Fact_Trans", name: "Two", expression: "1 + 1"),
        ]))
    }

    @Test func cardChayQuaEngineVaCache() async throws {
        let loader = VisualDataLoader(engine: engine(), maxConcurrent: 2)
        let first = try await loader.load(cardSpec())
        guard case .single(let s) = first.view else { Issue.record("không phải card: \(first.view)"); return }
        #expect(s.cell.value == .integer(2))
        #expect(s.cell.formatString == "0")
        #expect(!first.fromCache)
        // Card không bộ lọc: `ROW(...)` không IGNORE (VM-F10, đợt tồn đọng sau Phase F); có bộ lọc thì SUMMARIZECOLUMNS + IGNORE.
        #expect(first.query.contains("ROW(") && first.query.contains("\"Two\", 'Fact_Trans'[Two]"))
        let second = try await loader.load(cardSpec())
        #expect(second.fromCache)
    }

    @Test func nhieuTruyVanSongSongVuotGioiHan() async throws {
        let loader = VisualDataLoader(engine: engine(), maxConcurrent: 1)
        await loader.clearCache()
        try await withThrowingTaskGroup(of: DataView.self) { group in
            for _ in 0..<6 { group.addTask { try await loader.load(self.cardSpec()).view } }
            var count = 0
            for try await _ in group { count += 1 }
            #expect(count == 6)
        }
    }

    /// VM-D15 mục 3: bản đồ hình vừa đổi từ biểu đồ khác (có Series, chưa có Category) vẫn có giá trị Series để vẽ chú giải.
    @Test func banDoHinhChiCoSeriesLayGiaTriChuGiai() async throws {
        let legend = FieldInfo(queryRef: "Dim_District.city", displayName: "Thành phố", role: "Series", formatString: nil, isMeasure: false)
        var spec = VisualQuerySpec(visualID: "map1", visualType: "shapeMap")
        spec.shape = .shapeMap
        spec.secondary = [GroupField(field: legend, column: QueryColumn(table: "Dim_District", column: "city"), sortBy: nil)]
        spec.secondaryOrder = spec.secondary.flatMap(VisualQuerySpecReader.ascendingKeys)
        let loader = VisualDataLoader(engine: engine(), maxConcurrent: 2)
        let loaded = try await loader.load(spec)
        guard case .categorical(let data) = loaded.view else { Issue.record("không phải categorical: \(loaded.view)"); return }
        #expect(data.categories.isEmpty && data.measures.isEmpty)
        #expect(data.seriesField?.queryRef == "Dim_District.city")
        #expect(Set(data.series) == [.string("Hà Nội"), .string("TP. Hồ Chí Minh"), .string("Đà Nẵng")], "đủ ba thành phố của MiniBank")
        // Không có cả Series lẫn Category: vẫn là bản đồ trơn, không truy vấn.
        spec.secondary = []
        let plain = try await loader.load(spec)
        #expect(plain.query.isEmpty)
    }

    /// VM-D16 mục 2: có cả Category (vị trí) lẫn Series thì vẫn lấy chú giải, và các bang vẫn đủ.
    @Test func banDoHinhCoCaViTriLanSeriesVanCoChuGiai() async throws {
        let location = FieldInfo(queryRef: "Dim_District.state_name", displayName: "Bang", role: "Category", formatString: nil, isMeasure: false)
        let legend = FieldInfo(queryRef: "Dim_District.city", displayName: "Thành phố", role: "Series", formatString: nil, isMeasure: false)
        var spec = VisualQuerySpec(visualID: "map2", visualType: "shapeMap")
        spec.shape = .shapeMap
        spec.primary = [GroupField(field: location, column: QueryColumn(table: "Dim_District", column: "state_name"), sortBy: nil)]
        spec.secondary = [GroupField(field: legend, column: QueryColumn(table: "Dim_District", column: "city"), sortBy: nil)]
        spec.primaryOrder = spec.primary.flatMap(VisualQuerySpecReader.ascendingKeys)
        spec.secondaryOrder = spec.secondary.flatMap(VisualQuerySpecReader.ascendingKeys)
        let loaded = try await VisualDataLoader(engine: engine(), maxConcurrent: 2).load(spec)
        guard case .categorical(let data) = loaded.view else { Issue.record("không phải categorical"); return }
        #expect(!data.categories.isEmpty, "vẫn có các bang")
        #expect(Set(data.series) == [.string("Hà Nội"), .string("TP. Hồ Chí Minh"), .string("Đà Nẵng")])
        #expect(data.seriesField?.queryRef == "Dim_District.city")
    }

    /// VM-D15 mục 3: thang màu Color saturation mặc định của Desktop (Min #F8E5D8 đến Max #D9ECFB).
    @Test func thangMauSaturationMacDinhCuaDesktop() {
        func hex(_ c: (r: Double, g: Double, b: Double)) -> String {
            String(format: "#%02X%02X%02X", Int((c.r * 255).rounded()), Int((c.g * 255).rounded()), Int((c.b * 255).rounded()))
        }
        #expect(hex(ShapeMapView.saturationRGB(318_780, low: 318_780, high: 74_345_952)) == "#F8E5D8")
        #expect(hex(ShapeMapView.saturationRGB(74_345_952, low: 318_780, high: 74_345_952)) == "#D9ECFB")
        #expect(hex(ShapeMapView.saturationRGB(5, low: 5, high: 5)) == "#D9ECFB", "mọi bang cùng giá trị: màu Max, như Desktop")
    }
}
