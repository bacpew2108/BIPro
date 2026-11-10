import Foundation
import PBIXKit
import Testing
@testable import BIPro

/// Hoàn tác chung với D1 (kéo, đổi cỡ, xoá, nhân bản) và D2 (sửa trường): một lịch sử, từng bước một.
@Suite @MainActor struct FieldEditingUndoTests {
    typealias S = SyntheticReport
    typealias Env = FieldEditingTests.Env
    static let measure = FieldEditingTests.measure
    static let column = FieldEditingTests.column

    func props(_ env: Env, _ role: String, id: String = S.c1) -> [String] {
        env.editor.visual(id)?.fields.filter { $0.role == role }.map(\.property) ?? []
    }

    @Test func fieldAndLayoutEditsUndoOneStepAtATimeInOrder() throws {
        let env = try Env(); defer { env.cleanUp() }
        let origin = env.editor.page("p1")
        env.editor.addField(Self.measure, to: "Y", visual: S.c1)       // 1
        env.editor.move([S.a1], dx: 24, dy: 8, snap: true)             // 2
        env.editor.removeField(role: "Y", index: 0, visual: S.c1)      // 3
        #expect(env.editor.undoDepth == 3)
        env.editor.undo()
        #expect(props(env, "Y") == ["Credit", "Debit", "Balance"] && env.editor.visual(S.a1)?.x == 64)
        env.editor.undo()
        #expect(env.editor.visual(S.a1)?.x == 40 && props(env, "Y") == ["Credit", "Debit", "Balance"])
        env.editor.undo()
        #expect(env.editor.page("p1") == origin && !env.editor.isDirty)
        env.editor.redo(); env.editor.redo(); env.editor.redo()
        #expect(props(env, "Y") == ["Debit", "Balance"] && env.editor.visual(S.a1)?.x == 64)
    }

    @Test func dragOfASingleFieldIsOneStepEvenWhenItMovesBetweenWells() throws {
        let env = try Env(); defer { env.cleanUp() }
        let depth = env.editor.undoDepth
        env.editor.moveField(role: "Y", index: 1, to: "Y2", visual: S.c1)
        #expect(env.editor.undoDepth == depth + 1)
        #expect(props(env, "Y") == ["Credit"] && props(env, "Y2") == ["Net", "Debit"])
        env.editor.undo()
        #expect(props(env, "Y") == ["Credit", "Debit"] && props(env, "Y2") == ["Net"])
    }

    @Test func deletingAndDuplicatingAnEditedVisualRoundTripsItsFields() throws {
        let env = try Env(); defer { env.cleanUp() }
        env.editor.addField(Self.measure, to: "Y", visual: S.c1)
        let edited = try #require(env.editor.visual(S.c1))
        // nhân bản: bản sao mang cấu hình trường đã sửa
        env.editor.select(S.c1)
        let copy = try #require(env.editor.duplicate([S.c1]).first)
        #expect(env.editor.visual(copy)?.fields.map(\.queryRef) == edited.fields.map(\.queryRef))
        #expect(env.editor.visual(copy)?.raw["visual"]?["query"] == edited.raw["visual"]?["query"])
        // xoá visual đã sửa rồi hoàn tác: trường trở lại
        env.editor.delete([S.c1])
        #expect(env.editor.visual(S.c1) == nil)
        env.editor.undo()
        #expect(env.editor.visual(S.c1) == edited)
    }

    /// Chuỗi ngẫu nhiên (hạt cố định) trộn D1 và D2; hoàn tác hết về trạng thái đầu, làm lại hết về trạng thái cuối.
    @Test func randomChainUndoesToTheStartAndRedoesToTheEnd() throws {
        let env = try Env(); defer { env.cleanUp() }
        var rng = SplitMix(seed: 20261110)
        let start = env.editor.page("p1")
        let startEdited = env.editor.edited
        let catalogMeasures = ["Balance", "Avg", "Credit", "Debit", "Net", "Fees"].map { FieldRef(kind: .measure, entity: "Fact", property: $0) }
        let catalogColumns = ["region", "age", "sex"].map { FieldRef(kind: .column, entity: "Dim_Client", property: $0, family: .text) }
        var applied = 0
        for _ in 0..<150 {
            let visuals = env.editor.visuals(of: "p1")
            guard let target = visuals.randomElement(using: &rng) else { break }
            let id = target.id
            let roles = ["Category", "Y", "Y2", "Tooltips", "Series", "Values"]
            switch Int.random(in: 0..<9, using: &rng) {
            case 0: env.editor.move([id], dx: Int.random(in: -40...40, using: &rng), dy: Int.random(in: -40...40, using: &rng), snap: true)
            case 1: env.editor.resize(id, handle: .se, dx: Int.random(in: -30...30, using: &rng), dy: Int.random(in: -30...30, using: &rng), snap: true)
            case 2: if visuals.count > 3 { env.editor.delete([id]) }
            case 3: if visuals.count < 12 { env.editor.select(id); _ = env.editor.duplicate([id]) }
            case 4: env.editor.addField((catalogMeasures + catalogColumns).randomElement(using: &rng)!, to: roles.randomElement(using: &rng)!, visual: id)
            case 5: env.editor.removeField(role: roles.randomElement(using: &rng)!, index: Int.random(in: 0..<3, using: &rng), visual: id)
            case 6: env.editor.reorderField(role: "Y", from: Int.random(in: 0..<3, using: &rng), to: Int.random(in: 0..<3, using: &rng), visual: id)
            case 7: env.editor.moveField(role: ["Y", "Y2", "Tooltips"].randomElement(using: &rng)!, index: 0, to: ["Y", "Y2", "Tooltips"].randomElement(using: &rng)!, visual: id)
            default: env.editor.renameField(role: roles.randomElement(using: &rng)!, index: 0, to: ["", "Tên A", "Tên B"].randomElement(using: &rng)!, visual: id)
            }
            applied += 1
        }
        #expect(env.editor.undoDepth > 20, "chuỗi phải thực sự đổi nhiều thứ (đổi được \(env.editor.undoDepth) bước)")
        let end = env.editor.page("p1"), endEdited = env.editor.edited
        let depth = env.editor.undoDepth
        for _ in 0..<depth { env.editor.undo() }
        #expect(env.editor.page("p1") == start && env.editor.edited == startEdited && !env.editor.isDirty)
        for _ in 0..<depth { env.editor.redo() }
        #expect(env.editor.page("p1") == end && env.editor.edited == endEdited)
        _ = applied
    }
}

/// Bộ sinh số giả ngẫu nhiên có hạt (kết quả giống nhau mỗi lần chạy).
struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
