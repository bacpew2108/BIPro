import Foundation
import PBIXKit
import Testing
@testable import BIPro

/// Phase E (T009): sửa mô hình đi qua cùng ngăn xếp hoàn tác với visual (D1 đến D7).
@Suite @MainActor struct ModelUndoTests {
    typealias S = SyntheticReport
    typealias Env = FieldEditingTests.Env

    static let addM = ModelEdit.addMeasure(NewMeasure(table: "Fact", name: "E_Test", expression: "1"))

    /// Bộ kiểm giả: chấp nhận mọi thứ trừ thao tác xoá (như mô hình thật không có measure đó).
    static let validate: (ModelEdits) throws -> Void = { edits in
        if edits.items.contains(where: { if case .deleteMeasure = $0 { true } else { false } }) {
            throw ModelEditError("Không có measure")
        }
    }

    @Test func suaMoHinhLaMotBuocHoanTacVaLamDirty() throws {
        let env = try Env(); defer { env.cleanUp() }
        var seen: [ModelEdits] = []
        env.editor.modelEditsChanged = { seen.append($0) }
        #expect(!env.editor.isDirty)
        #expect(env.editor.commitModel(ModelEdits([Self.addM])))
        #expect(env.editor.isDirty && env.editor.undoDepth == 1)
        #expect(env.editor.modelEdits.items == [Self.addM])
        env.editor.undo()
        #expect(env.editor.modelEdits.isEmpty && !env.editor.isDirty)
        env.editor.redo()
        #expect(env.editor.modelEdits.items == [Self.addM] && env.editor.isDirty)
        #expect(seen == [ModelEdits([Self.addM]), ModelEdits(), ModelEdits([Self.addM])])
    }

    @Test func khongDoiThiKhongTaoBuoc() throws {
        let env = try Env(); defer { env.cleanUp() }
        env.editor.commitModel(ModelEdits([Self.addM]))
        let depth = env.editor.undoDepth
        #expect(!env.editor.commitModel(ModelEdits([Self.addM])))
        #expect(env.editor.undoDepth == depth)
    }

    @Test func xenKeVisualVaMoHinhHoanTacDungThuTu() throws {
        let env = try Env(); defer { env.cleanUp() }
        env.editor.move([S.a1], dx: 24, dy: 8, snap: true)                            // 1
        env.editor.commitModel(ModelEdits([Self.addM]))                               // 2
        env.editor.move([S.a1], dx: 8, dy: 8, snap: true)                             // 3
        #expect(env.editor.undoDepth == 3)
        env.editor.undo()
        #expect(env.editor.modelEdits.items == [Self.addM] && env.editor.visual(S.a1)?.x == 64)
        env.editor.undo()
        #expect(env.editor.modelEdits.isEmpty && env.editor.visual(S.a1)?.x == 64)
        env.editor.undo()
        #expect(env.editor.visual(S.a1)?.x == 40 && !env.editor.isDirty)
    }

    @Test func luuDatMocSachVaHoanTacSauLuuVeTrangThaiDaLuu() throws {
        let env = try Env(); defer { env.cleanUp() }
        env.editor.commitModel(ModelEdits([Self.addM]))
        env.editor.markSaved()
        #expect(!env.editor.isDirty && env.editor.savedModelEdits.items == [Self.addM])
        env.editor.commitModel(ModelEdits([Self.addM, .updateMeasure(table: "Fact", name: "E_Test", patch: MeasurePatch(expression: "2"))]))
        #expect(env.editor.isDirty)
        env.editor.undo()
        #expect(!env.editor.isDirty)
    }

    @Test func modelEditorGopLanSuaLienTiepThanhMotBuoc() throws {
        let env = try Env(); defer { env.cleanUp() }
        let editor = ModelEditor(layout: env.editor, validate: Self.validate)
        #expect(editor.apply(Self.addM) == nil)
        #expect(editor.apply(.updateMeasure(table: "Fact", name: "E_Test", patch: MeasurePatch(expression: "2")), coalesceKey: "expr") == nil)
        #expect(editor.apply(.updateMeasure(table: "Fact", name: "E_Test", patch: MeasurePatch(expression: "22")), coalesceKey: "expr") == nil)
        // gộp: mục thêm vừa tạo hấp thụ hai lần sửa
        #expect(env.editor.modelEdits.items == [.addMeasure(NewMeasure(table: "Fact", name: "E_Test", expression: "22"))])
        #expect(env.editor.undoDepth <= 2)
    }

    @Test func modelEditorTuChoiThaoTacSaiKemLyDoVaKhongDoiGi() throws {
        let env = try Env(); defer { env.cleanUp() }
        let editor = ModelEditor(layout: env.editor, validate: Self.validate)
        let depth = env.editor.undoDepth
        let reason = editor.apply(.deleteMeasure(table: "Fact", name: "khong co"))
        #expect(reason == "Không có measure")
        #expect(env.editor.undoDepth == depth && env.editor.modelEdits.isEmpty && editor.refusal == reason)
        #expect(editor.apply(Self.addM) == nil && editor.refusal == nil)
    }
}
