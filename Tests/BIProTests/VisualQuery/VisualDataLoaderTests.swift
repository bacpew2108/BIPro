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
        #expect(first.query.contains("IGNORE('Fact_Trans'[Two])"))
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
}
