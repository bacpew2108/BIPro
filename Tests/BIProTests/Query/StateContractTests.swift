// Phase F, T006: khung trạng thái Navigator và Query Editor. Seam: plan.md mục Thiết kế 5 (giao diện vẽ từ trạng thái).
import Testing
import Connectors
@testable import BIPro

@MainActor
@Suite struct FStateContractTests {
    @Test func navigatorToggleIgnoresUnknownItemsAndGatesLoad() {
        let state = NavigatorState()
        state.items = [NavigatorItem(id: "s1", name: "Sheet1", kind: .sheet)]
        #expect(!state.canLoad)
        state.toggle("zzz")
        #expect(state.checkedItemIDs.isEmpty)
        state.toggle("s1")
        state.phase = .ready
        #expect(state.canLoad)
        state.toggle("s1")
        #expect(!state.canLoad)
    }

    @Test func selectingQueryPicksLastStepAndBadIndexIsIgnored() {
        let state = QueryEditorState()
        let query = QueryModel(name: "Sales", steps: [
            QueryStep(name: "Source", expression: "x"), QueryStep(name: "Promoted Headers", expression: "y"),
        ])
        state.queries = [query]
        state.selectQuery(query.id)
        #expect(state.selectedStepIndex == 1)
        state.selectStep(0)
        #expect(state.selectedStepIndex == 0)
        state.selectStep(9)
        #expect(state.selectedStepIndex == 0)
        state.selectQuery(.init())   // không có
        #expect(state.selectedQuery?.name == "Sales")
    }
}
