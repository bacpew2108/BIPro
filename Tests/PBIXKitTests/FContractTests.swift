// Phase F, T006: khung hợp đồng ModelEdit cho bảng mới. Seam: contracts/t3-save.md.
import Testing
@testable import PBIXKit

@Suite struct FModelEditContractTests {
    private func table(_ name: String = "Sales") -> NewTable {
        NewTable(name: name, columns: [NewTableColumn(name: "Qty", values: .int64([1, 2, 3]))], queryExpression: "let Source = 1 in Source")
    }

    @Test func tableEditsNeedTierThree() {
        #expect(ModelEdits([.addTable(table())]).tier == .data)
        #expect(ModelEdits([.dropTable(name: "Sales")]).tier == .data)
        #expect(ModelEdits([.addCalculatedColumn(table: "Sales", name: "Dt", expression: "1", dataType: .int64)]).tier == .data)
        #expect(ModelEdits([.updateTable(name: "Sales", patch: TablePatch(isHidden: true))]).tier == .metadata)
        #expect(ModelEdits().tier == .report)
    }

    @Test func mixedEditsTakeTheHighestTier() {
        let edits = ModelEdits([.deleteRelationship(name: "r"), .addTable(table())])
        #expect(edits.tier == .data)
    }

    @Test func newTableComparesByIdentityNotContent() {
        let a = table(), b = table()
        #expect(ModelEdit.addTable(a) == ModelEdit.addTable(a))
        #expect(ModelEdit.addTable(a) != ModelEdit.addTable(b))
        #expect(Set([ModelEdit.addTable(a), ModelEdit.addTable(a)]).count == 1)
    }
}
