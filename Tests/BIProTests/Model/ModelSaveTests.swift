import Foundation
import PBIXKit
import Testing
@testable import BIPro

/// Phase E (T010): lưu T2 qua `DocumentSaver` trên bản sao Nhom6 thật (BIPRO_HEAVY=1; mỗi lần lưu nén lại mô hình).
@Suite("Phase E: lưu T2", .enabled(if: EFixtures.heavy && EFixtures.nhom6 != nil), .serialized)
@MainActor
struct ModelSaveTests {
    @MainActor private struct Env {
        let dir: URL
        let source: URL
        let backups: URL
        let workspace: Workspace
        let editor: LayoutEditor
        let model: ModelEditor

        init(_ label: String) throws {
            dir = try EFixtures.outputDirectory("T010-\(label)")
            try? FileManager.default.removeItem(at: dir)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            source = dir.appendingPathComponent("Nhom6_e.pbix")
            try FileManager.default.copyItem(at: try #require(EFixtures.nhom6), to: source)
            backups = dir.appendingPathComponent("Backups", isDirectory: true)
            workspace = try Workspace(data: Data(contentsOf: source))
            let archive = workspace.pbix.archive
            editor = LayoutEditor.reading(archive: archive, report: workspace.report)
            let runtime = try #require(workspace.runtime)
            editor.modelBase = runtime.base
            editor.modelEditsChanged = { try? runtime.setEdits($0) }
            model = ModelEditor(layout: editor) { try runtime.validate($0) }
        }

        func save() throws -> SaveOutcome {
            try DocumentSaver.save(editor: editor, source: source, to: source, expectedStamp: nil,
                                   readOnlyRoots: [], backupDirectory: backups)
        }

        func savedModel() throws -> ModelMetadata {
            let (abf, _) = try PBIXFile(url: source).loadDataModel()
            return try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb"))
        }

        func cleanUp() { try? FileManager.default.removeItem(at: dir) }
    }

    static let add = ModelEdit.addMeasure(NewMeasure(table: "Dim_Account", name: "E_Test", expression: "COUNTROWS(Dim_Account)+1",
                                                     formatString: "0", dataType: 6))

    @Test func luuHaiLanTrongMotPhienGhiDungPhanThayDoi() throws {
        let env = try Env("hai-lan"); defer { env.cleanUp() }
        let originalModel = try env.savedModel()
        let originalArchive = try ZipArchive(url: env.source)

        // Lần 1: thêm measure.
        #expect(env.model.apply(Self.add) == nil)
        #expect(env.editor.isDirty)
        let first = try env.save()
        #expect(first.didWrite && !env.editor.isDirty)
        let afterFirst = try env.savedModel()
        #expect(afterFirst.measures.contains { $0.name == "E_Test" && $0.expression == "COUNTROWS(Dim_Account)+1" })
        // Mọi phần khác của file giữ nguyên (SecurityBindings còn, Report/** không đụng).
        let archive1 = try ZipArchive(url: env.source)
        for entry in originalArchive.entries where entry.path != "DataModel" {
            let now = try #require(archive1.entry(entry.path), Comment(rawValue: entry.path))
            #expect(now.crc32 == entry.crc32, Comment(rawValue: "\(entry.path) không được đổi"))
        }

        // Lần 2: sửa biểu thức (gộp vào mục thêm trong phiên) và lưu tiếp: file chỉ có một measure E_Test, biểu thức mới.
        #expect(env.model.apply(.updateMeasure(table: "Dim_Account", name: "E_Test", patch: MeasurePatch(expression: "COUNTROWS(Dim_Account)+2"))) == nil)
        _ = try env.save()
        let afterSecond = try env.savedModel()
        #expect(afterSecond.measures.filter { $0.name == "E_Test" }.map(\.expression) == ["COUNTROWS(Dim_Account)+2"])

        // Hoàn tác về trước lần lưu thứ hai rồi trước lần đầu, lưu: file trở về đúng mô hình gốc.
        env.editor.undo()
        env.editor.undo()
        #expect(env.editor.modelEdits.isEmpty && env.editor.isDirty)
        _ = try env.save()
        let restored = try env.savedModel()
        #expect(restored.measures == originalModel.measures)
        #expect(restored.relationships == originalModel.relationships)
        #expect(restored.columns == originalModel.columns)
    }

    @Test func suaRoiHoanTacKhongGhiGiVaKhongDirty() throws {
        let env = try Env("hoan-tac"); defer { env.cleanUp() }
        let before = try Data(contentsOf: env.source)
        #expect(env.model.apply(Self.add) == nil)
        env.editor.undo()
        #expect(!env.editor.isDirty)
        let outcome = try env.save()
        #expect(!outcome.didWrite)
        #expect(try Data(contentsOf: env.source) == before, "SC-005: file giống byte file gốc")
    }

    @Test func moHinhDocLaiBangMoHinhHieuLuc() throws {
        let env = try Env("hieu-luc"); defer { env.cleanUp() }
        let rel = try #require(env.workspace.runtime?.base.relationships.first { $0.isActive && $0.crossFilteringBehavior == 1 })
        #expect(env.model.apply(Self.add) == nil)
        #expect(env.model.apply(.updateRelationship(name: rel.name, patch: RelationshipPatch(crossFilteringBehavior: 2))) == nil)
        _ = try env.save()
        let saved = try env.savedModel()
        let effective = try #require(env.workspace.metadata)
        #expect(saved.relationships == effective.relationships)
        #expect(saved.columns == effective.columns)
        #expect(saved.measures.map(\.name).sorted() == effective.measures.map(\.name).sorted())
    }
}
