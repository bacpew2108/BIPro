import Foundation
import PBIXKit
import Testing
@testable import BIPro

/// Sửa trường của visual qua `LayoutEditor` (D2): thêm, bỏ, một bước hoàn tác, từ chối, đọc lại từ `raw`.
@Suite @MainActor struct FieldEditingTests {
    typealias S = SyntheticReport

    struct Env {
        let dir: URL
        let source: URL
        let archive: ZipArchive
        let editor: LayoutEditor

        @MainActor init(chart: Data? = nil) throws {
            dir = SyntheticReport.temporaryDirectory("fields")
            source = try SyntheticReport.make(in: dir, withChart: true, chart: chart)
            archive = try ZipArchive(url: source)
            let archive = self.archive
            let report = try PBIXFile(url: source).loadReport()
            editor = LayoutEditor(report: report, sourceJSON: { page, id in
                try? archive.read(LayoutEditor.visualPath(page: page, id: id))
            })
            editor.showPage("p1")
        }
        func cleanUp() { try? FileManager.default.removeItem(at: dir) }
    }

    static let measure = FieldRef(kind: .measure, entity: "Fact", property: "Balance")
    static let column = FieldRef(kind: .column, entity: "Dim_Client", property: "region", family: .text)

    func props(_ env: Env, _ role: String, id: String = S.c1) -> [String] {
        env.editor.visual(id)?.fields.filter { $0.role == role }.map(\.property) ?? []
    }

    // MARK: thêm

    @Test func addAppendsAndUpdatesFieldsAndRawTogether() throws {
        let env = try Env(); defer { env.cleanUp() }
        let before = env.editor.undoDepth
        #expect(env.editor.addField(Self.measure, to: "Y", visual: S.c1) == nil)
        #expect(props(env, "Y") == ["Credit", "Debit", "Balance"])
        #expect(env.editor.undoDepth == before + 1 && env.editor.isDirty)
        // raw cùng cập nhật: bộ đọc truy vấn đọc từ raw
        let raw = try #require(env.editor.visual(S.c1)?.raw["visual"]?["query"]?["queryState"]?["Y"]?["projections"]?.array)
        #expect(raw.count == 3 && raw.last?["queryRef"]?.string == "Fact.Balance" && raw.last?["nativeQueryRef"]?.string == "Balance")
        // các trường khác không đổi
        #expect(props(env, "Category") == ["month_name"] && props(env, "Y2") == ["Net"] && props(env, "Tooltips") == ["Avg"])
        // ô mới (Series không có trong file và chưa kiểm ở loại combo cột nhóm) bị từ chối
        #expect(env.editor.addField(Self.column, to: "Series", visual: S.c1)?.contains("chưa kiểm") == true)
        #expect(env.editor.undoDepth == before + 1)
    }

    @Test func addToSingleWellReplacesAndRefusesWrongKindWithoutChangingAnything() throws {
        let env = try Env(); defer { env.cleanUp() }
        #expect(env.editor.addField(Self.column, to: "Category", visual: S.c1) == nil)
        #expect(props(env, "Category") == ["region"])
        let depth = env.editor.undoDepth
        let reason = env.editor.addField(Self.column, to: "Y", visual: S.c1)
        #expect(reason?.contains("measure") == true)
        #expect(env.editor.undoDepth == depth)
        #expect(env.editor.fieldRefusal == reason)
        // measure trùng thì thêm được (VM-D2 R-D2-h-dup)
        #expect(env.editor.addField(FieldRef(kind: .measure, entity: "Fact", property: "Credit"), to: "Y", visual: S.c1) == nil)
        #expect(props(env, "Y").filter { $0 == "Credit" }.count == 2)
    }

    // MARK: bỏ

    @Test func removeDropsOneFieldAndTheEmptyWell() throws {
        let env = try Env(); defer { env.cleanUp() }
        #expect(env.editor.removeField(role: "Y", index: 1, visual: S.c1) == nil)
        #expect(props(env, "Y") == ["Credit"])
        #expect(env.editor.removeField(role: "Tooltips", index: 0, visual: S.c1) == nil)
        #expect(props(env, "Tooltips").isEmpty)
        let queryState = try #require(env.editor.visual(S.c1)?.raw["visual"]?["query"]?["queryState"]?.object)
        #expect(queryState["Tooltips"] == nil)
        // visual hết trường bắt buộc vẫn tồn tại (không ném lỗi): bỏ hết Y và Y2
        #expect(env.editor.removeField(role: "Y", index: 0, visual: S.c1) == nil)
        #expect(env.editor.removeField(role: "Y2", index: 0, visual: S.c1) == nil)
        #expect(env.editor.visual(S.c1)?.fields.map(\.property) == ["month_name"])
    }

    @Test func removeIsBlockedWhileTheFieldDrivesTheSort() throws {
        let env = try Env(); defer { env.cleanUp() }
        let depth = env.editor.undoDepth
        let reason = env.editor.removeField(role: "Category", index: 0, visual: S.c1)
        #expect(reason?.contains("sắp xếp") == true)
        #expect(props(env, "Category") == ["month_name"] && env.editor.undoDepth == depth)
    }

    // MARK: một bước hoàn tác

    @Test func eachEditIsOneUndoStepAndUndoRestoresFieldsAndRaw() throws {
        let env = try Env(); defer { env.cleanUp() }
        let original = try #require(env.editor.visual(S.c1))
        _ = env.editor.addField(Self.measure, to: "Y", visual: S.c1)
        _ = env.editor.removeField(role: "Y2", index: 0, visual: S.c1)
        #expect(env.editor.undoDepth == 2)
        env.editor.undo()
        #expect(props(env, "Y2") == ["Net"] && props(env, "Y") == ["Credit", "Debit", "Balance"])
        env.editor.undo()
        #expect(env.editor.visual(S.c1) == original)
        #expect(!env.editor.isDirty)
        env.editor.redo(); env.editor.redo()
        #expect(props(env, "Y") == ["Credit", "Debit", "Balance"] && props(env, "Y2").isEmpty)
    }

    // MARK: điều kiện sửa

    @Test func editingIsRefusedForGroupMembersMissingVisualsAndVisualsWithoutQueryState() throws {
        let env = try Env(); defer { env.cleanUp() }
        // card mẫu không có queryState: D2 không tạo queryState mới cho visual chưa có
        #expect(env.editor.addField(Self.measure, to: "Values", visual: S.a1) != nil)
        #expect(env.editor.addField(Self.measure, to: "Y", visual: "zzzzzzzzzzzzzzzzzzzz") != nil)
        #expect(env.editor.removeField(role: "Y", index: 9, visual: S.c1) != nil)
    }

    @Test func nothingChangesInOtherVisualsOrPages() throws {
        let env = try Env(); defer { env.cleanUp() }
        let others = ["p1": [S.a1, S.a2, S.a3].compactMap { env.editor.visual($0) }]
        _ = env.editor.addField(Self.measure, to: "Y", visual: S.c1)
        #expect([S.a1, S.a2, S.a3].compactMap { env.editor.visual($0) } == others["p1"])
        #expect(env.editor.edited["p2"] == nil)
    }

    // MARK: Đổi thứ tự và chuyển ô (US4)

    func projection(_ env: Env, _ role: String, _ index: Int) -> JSONValue? {
        env.editor.visual(S.c1)?.raw["visual"]?["query"]?["queryState"]?[role]?["projections"]?[index]
    }

    @Test func reorderChangesTheOrderOnlyAndKeepsQueryRefs() throws {
        let env = try Env(); defer { env.cleanUp() }
        let credit = projection(env, "Y", 0), debit = projection(env, "Y", 1)
        #expect(env.editor.reorderField(role: "Y", from: 1, to: 0, visual: S.c1) == nil)
        #expect(props(env, "Y") == ["Debit", "Credit"])
        #expect(projection(env, "Y", 0) == debit && projection(env, "Y", 1) == credit)
        #expect(env.editor.undoDepth == 1)
        // vẫn chỗ cũ thì không tạo bước
        #expect(env.editor.reorderField(role: "Y", from: 0, to: 0, visual: S.c1) == nil)
        #expect(env.editor.undoDepth == 1)
        #expect(env.editor.reorderField(role: "Y", from: 0, to: 7, visual: S.c1) != nil)
    }

    @Test func moveBetweenYAndY2KeepsTheElementBytesAndTheOldWellDropsWhenEmpty() throws {
        let env = try Env(); defer { env.cleanUp() }
        let debit = projection(env, "Y", 1)
        #expect(env.editor.moveField(role: "Y", index: 1, to: "Y2", visual: S.c1) == nil)
        #expect(props(env, "Y") == ["Credit"] && props(env, "Y2") == ["Net", "Debit"])
        #expect(projection(env, "Y2", 1) == debit)
        // ô đích không nhận loại trường: từ chối, trường ở chỗ cũ
        let depth = env.editor.undoDepth
        #expect(env.editor.moveField(role: "Y2", index: 0, to: "Category", visual: S.c1) != nil)
        #expect(props(env, "Y2") == ["Net", "Debit"] && env.editor.undoDepth == depth)
        // trường duy nhất của Tooltips chuyển đi thì Tooltips biến mất
        #expect(env.editor.moveField(role: "Tooltips", index: 0, to: "Y", visual: S.c1) == nil)
        #expect(env.editor.visual(S.c1)?.raw["visual"]?["query"]?["queryState"]?.object["Tooltips"] == nil)
        #expect(props(env, "Y") == ["Credit", "Avg"])
        // chuyển sang chính ô hiện tại thì không đổi
        let depth2 = env.editor.undoDepth
        #expect(env.editor.moveField(role: "Y", index: 0, to: "Y", visual: S.c1) == nil)
        #expect(env.editor.undoDepth == depth2)
    }

    @Test func hierarchyLevelsKeepTheirBytesWhenReordered() throws {
        let level = #"{"field":{"HierarchyLevel":{"Expression":{"Hierarchy":{"Expression":{"SourceRef":{"Entity":"Dim_Date"}},"Hierarchy":"Thời gian"}},"Level":"Năm"}},"queryRef":"Dim_Date.Thời gian.Năm","nativeQueryRef":"Năm","active":true}"#
        let level2 = #"{"field":{"HierarchyLevel":{"Expression":{"Hierarchy":{"Expression":{"SourceRef":{"Entity":"Dim_Date"}},"Hierarchy":"Thời gian"}},"Level":"Quý"}},"queryRef":"Dim_Date.Thời gian.Quý","nativeQueryRef":"Quý","active":true}"#
        let chart = Data(#"{"name":"\#(S.c1)","position":{"x":600,"y":100,"z":4000,"height":300,"width":400,"tabOrder":4000},"visual":{"visualType":"lineClusteredColumnComboChart","query":{"queryState":{"Category":{"projections":[\#(level),\#(level2)]},"Y":{"projections":[\#(S.proj("Measure", "Fact", "Credit"))]}}}}}"#.utf8)
        let env = try Env(chart: chart); defer { env.cleanUp() }
        #expect(props(env, "Category") == ["Năm", "Quý"])
        let first = projection(env, "Category", 0), second = projection(env, "Category", 1)
        #expect(env.editor.reorderField(role: "Category", from: 0, to: 1, visual: S.c1) == nil)
        #expect(projection(env, "Category", 0) == second && projection(env, "Category", 1) == first)
        // sang ô cột (Y) bị từ chối: cấp hierarchy là loại cột, Y chỉ nhận measure
        #expect(env.editor.moveField(role: "Category", index: 0, to: "Y", visual: S.c1) != nil)
        let changes = try env.editor.makeChanges(archive: env.archive)
        let written = try #require(changes.reportParts[LayoutEditor.visualPath(page: "p1", id: S.c1)])
        let text = String(decoding: written, as: UTF8.self)
        #expect(text.contains(level) && text.contains(level2), "hai phần tử giữ nguyên từng byte")
    }

    // MARK: Đổi tên hiển thị (US5)

    @Test func renameSetsAndClearsDisplayNameWithoutTouchingQueryRefOrReferences() throws {
        let env = try Env(); defer { env.cleanUp() }
        let sortBefore = env.editor.visual(S.c1)?.raw["visual"]?["query"]?["sortDefinition"]
        #expect(env.editor.renameField(role: "Category", index: 0, to: "  Tháng  ", visual: S.c1) == nil)
        let category = try #require(env.editor.visual(S.c1)?.fields.first { $0.role == "Category" })
        #expect(category.displayName == "Tháng" && category.label == "Tháng" && category.queryRef == "Dim_Date.month_name")
        // sắp xếp theo trường đó vẫn đúng (queryRef và sortDefinition không đổi)
        #expect(env.editor.visual(S.c1)?.raw["visual"]?["query"]?["sortDefinition"] == sortBefore)
        let json = try #require(env.archive.read(LayoutEditor.visualPath(page: "p1", id: S.c1)) as Data?)
        #expect(!FieldReferences.find(in: json, entity: "Dim_Date", property: "month_name", queryRef: "Dim_Date.month_name").isEmpty)
        // rỗng hoặc bằng tên gốc thì bỏ displayName; đặt lại đúng tên cũ thì không tạo bước
        let depth = env.editor.undoDepth
        #expect(env.editor.renameField(role: "Category", index: 0, to: "Tháng", visual: S.c1) == nil)
        #expect(env.editor.undoDepth == depth)
        #expect(env.editor.renameField(role: "Category", index: 0, to: "month_name", visual: S.c1) == nil)
        #expect(env.editor.visual(S.c1)?.fields.first { $0.role == "Category" }?.displayName == nil)
        #expect(env.editor.renameField(role: "Y", index: 0, to: "", visual: S.c1) == nil)   // "Tiền vào" có sẵn trong file
        #expect(env.editor.visual(S.c1)?.fields.first { $0.role == "Y" }?.displayName == nil)
        #expect(env.editor.renameField(role: "Y", index: 9, to: "x", visual: S.c1) != nil)
    }
}
