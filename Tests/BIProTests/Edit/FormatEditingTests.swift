import Foundation
import PBIXKit
import Testing
@testable import BIPro

/// Sửa định dạng của visual qua `LayoutEditor` (D4): `specs/006-d4-format-pane/contracts/format-editing.md`.
@Suite @MainActor struct FormatEditingTests {
    typealias S = SyntheticReport

    struct Env {
        let dir: URL
        let archive: ZipArchive
        let editor: LayoutEditor

        @MainActor init(chart: Data? = nil) throws {
            dir = S.temporaryDirectory("format")
            let source = try S.make(in: dir, withChart: true, chart: chart, extra: S.formatExtras)
            archive = try ZipArchive(url: source)
            let archive = self.archive
            let report = try PBIXFile(url: source).loadReport()
            editor = LayoutEditor(report: report, sourceJSON: { page, id in try? archive.read(LayoutEditor.visualPath(page: page, id: id)) },
                                  pageSource: { page in try? archive.read(LayoutEditor.pagePath(page)) })
            editor.showPage("p1")
        }
        func cleanUp() { try? FileManager.default.removeItem(at: dir) }
    }

    static func literal(_ raw: JSONValue?, _ object: String, _ property: String, index: Int = 0) -> String? {
        raw?[object]?[index]?["properties"]?[property]?["expr"]?["Literal"]?["Value"]?.string
    }
    func objects(_ env: Env, _ id: String) -> JSONValue? { env.editor.visual(id)?.raw["visual"]?["objects"] }
    func container(_ env: Env, _ id: String) -> JSONValue? { env.editor.visual(id)?.raw["visual"]?["visualContainerObjects"] }

    // MARK: (a) sửa giá trị đã có

    @Test func settingAnExistingPropertyUpdatesRawObjectsAndTheUndoStack() throws {
        let env = try Env(); defer { env.cleanUp() }
        let depth = env.editor.undoDepth
        #expect(env.editor.setFormat(.number(28, tail: .d), scope: .objects, object: "labels", property: "fontSize", visual: S.f1) == nil)
        #expect(Self.literal(objects(env, S.f1), "labels", "fontSize") == "28D")
        #expect(env.editor.visual(S.f1)?.objects.number("labels", "fontSize") == 28)
        #expect(env.editor.undoDepth == depth + 1 && env.editor.isDirty)
        // Thuộc tính khác của cùng mục giữ nguyên.
        #expect(Self.literal(objects(env, S.f1), "labels", "labelPrecision") == "1D")
        env.editor.undo()
        #expect(Self.literal(objects(env, S.f1), "labels", "fontSize") == "20D" && !env.editor.isDirty)
    }

    @Test func theTailOfTheExistingValueIsKept() throws {
        let env = try Env(); defer { env.cleanUp() }
        // Nhom6 ghi `labelPrecision` đuôi D; ghi lại đuôi D dù kiểu của danh mục là L.
        #expect(env.editor.setFormat(.number(2, tail: .l), scope: .objects, object: "labels", property: "labelPrecision", visual: S.f1) == nil)
        #expect(Self.literal(objects(env, S.f1), "labels", "labelPrecision") == "2D")
    }

    @Test func togglesAndColorsAndTextsAreWrittenAsDesktopDoes() throws {
        let env = try Env(); defer { env.cleanUp() }
        #expect(env.editor.setFormat(.bool(false), scope: .objects, object: "categoryLabels", property: "show", visual: S.f1) == nil)
        #expect(Self.literal(objects(env, S.f1), "categoryLabels", "show") == "false")
        #expect(env.editor.setFormat(.color(.hex("#e4572e")), scope: .container, object: "title", property: "fontColor", visual: S.f1) == nil)
        #expect(container(env, S.f1)?["title"]?[0]?["properties"]?["fontColor"]?["solid"]?["color"]?["expr"]?["Literal"]?["Value"]?.string == "'#E4572E'")
        #expect(env.editor.setFormat(.text("It's a test"), scope: .container, object: "title", property: "text", visual: S.f1) == nil)
        #expect(Self.literal(container(env, S.f1), "title", "text") == "'It''s a test'")
        #expect(env.editor.visual(S.f1)?.containerObjects.string("title", "text") == "It's a test")
    }

    // MARK: (b), (c) từ chối

    @Test func invalidValuesAndUnknownTargetsAreRefusedWithoutAStep() throws {
        let env = try Env(); defer { env.cleanUp() }
        let depth = env.editor.undoDepth
        let before = env.editor.visual(S.f1)
        #expect(env.editor.setFormat(.number(99, tail: .d), scope: .objects, object: "labels", property: "fontSize", visual: S.f1)?.contains("1") == true)
        #expect(env.editor.setFormat(.color(.hex("#12")), scope: .container, object: "background", property: "color", visual: S.f1) != nil)
        #expect(env.editor.setFormat(.text("   "), scope: .container, object: "title", property: "text", visual: S.f1) != nil)
        #expect(env.editor.setFormat(.choice("'Left'"), scope: .objects, object: "legend", property: "position", visual: S.c1) != nil)
        // Khoá, thuộc tính, visual chưa quan sát hoặc không có.
        #expect(env.editor.setFormat(.bool(true), scope: .objects, object: "legend", property: "show", visual: S.f1) != nil)          // card không có legend
        #expect(env.editor.setFormat(.bool(true), scope: .objects, object: "labels", property: "madeUp", visual: S.f1) != nil)
        #expect(env.editor.setFormat(.number(5, tail: .d), scope: .objects, object: "labels", property: "bold", visual: S.f1) != nil) // sai kiểu
        #expect(env.editor.setFormat(.bool(true), scope: .objects, object: "labels", property: "bold", visual: "zzzzzzzzzzzzzzzzzzzz") != nil)
        #expect(env.editor.undoDepth == depth && env.editor.visual(S.f1) == before && !env.editor.isDirty)
        #expect(env.editor.fieldRefusal != nil)
    }

    @Test func groupedAndLegacyVisualsAreRefused() throws {
        let editor = LayoutEditor(report: LayoutEditorTests.report())
        editor.showPage("p1")
        // `kid` nằm trong nhóm; `a` không có visual.json nguồn (báo cáo định dạng cũ).
        #expect(editor.setFormat(.bool(true), scope: .container, object: "title", property: "show", visual: "kid")?.contains("nhóm") == true)
        #expect(editor.setFormat(.bool(true), scope: .container, object: "title", property: "show", visual: "a")?.contains("visual.json") == true)
        #expect(editor.formatEditingBlocker(for: "kid") != nil && editor.formatEditingBlocker(for: "a") != nil)
        #expect(editor.undoDepth == 0)
    }

    // MARK: (d) giá trị trùng

    @Test func settingTheSameValueMakesNoStep() throws {
        let env = try Env(); defer { env.cleanUp() }
        let depth = env.editor.undoDepth
        #expect(env.editor.setFormat(.number(20, tail: .d), scope: .objects, object: "labels", property: "fontSize", visual: S.f1) == nil)
        #expect(env.editor.setFormat(.bool(true), scope: .objects, object: "categoryLabels", property: "show", visual: S.f1) == nil)
        #expect(env.editor.undoDepth == depth && !env.editor.isDirty)
    }

    // MARK: (e) mục theo trường và mục chung

    @Test func onlyTheCommonEntryIsEditedWhenAnEntryIsBoundToAField() throws {
        let env = try Env(); defer { env.cleanUp() }
        #expect(env.editor.setFormat(.number(30, tail: .d), scope: .objects, object: "labels", property: "fontSize", visual: S.f5) == nil)
        let labels = try #require(objects(env, S.f5)?["labels"]?.array)
        #expect(labels.count == 2 && labels[0]["selector"]?["metadata"]?.string == "Fact.Balance")
        #expect(labels[0]["properties"]?["color"] != nil && labels[1]["properties"]?["fontSize"]?["expr"]?["Literal"]?["Value"]?.string == "30D")
        // Thuộc tính chỉ có ở mục theo trường (color) được thêm vào mục chung, mục theo trường không đổi.
        #expect(env.editor.setFormat(.bool(true), scope: .objects, object: "labels", property: "bold", visual: S.f5) == nil)
        #expect(objects(env, S.f5)?["labels"]?[0]?["properties"]?["bold"] == nil && objects(env, S.f5)?["labels"]?[1]?["properties"]?["bold"] != nil)
    }

    @Test func aKeyWithOnlyBoundEntriesIsNotEditable() throws {
        let only = Data(#"{"$schema":"s","name":"\#(S.c1)","position":{"x":600,"y":100,"z":4000,"height":300,"width":400,"tabOrder":4000},"visual":{"visualType":"card","query":{"queryState":{"Values":{"projections":[\#(S.proj("Measure", "Fact", "Balance"))]}}},"objects":{"labels":[{"properties":{"fontSize":\#(S.lit("12D"))},"selector":{"metadata":"Fact.Balance"}}]}}}"#.utf8)
        let env = try Env(chart: only); defer { env.cleanUp() }
        let reason = env.editor.setFormat(.number(30, tail: .d), scope: .objects, object: "labels", property: "fontSize", visual: S.c1)
        #expect(reason != nil && env.editor.undoDepth == 0)
        let state = try #require(env.editor.formatState(of: S.c1))
        #expect(state.objects.first { $0.card.objectKey == "labels" }?.isEditable == false)
        #expect(state.readOnly.contains { $0.object == "labels" && $0.property == nil })
    }

    // MARK: (f) trạng thái cho giao diện

    @Test func formatStateDescribesCardsValuesAndReadOnlyParts() throws {
        let env = try Env(); defer { env.cleanUp() }
        let state = try #require(env.editor.formatState(of: S.f1))
        #expect(state.type == "card")
        let labels = try #require(state.objects.first { $0.card.objectKey == "labels" })
        #expect(labels.isPresent && labels.isEditable)
        #expect(labels.values["fontSize"] == .number(20, tail: .d) && labels.values["labelPrecision"] == .number(1, tail: .d))
        let cat = try #require(state.objects.first { $0.card.objectKey == "categoryLabels" })
        #expect(cat.values["show"] == .bool(true) && cat.isPresent)
        let title = try #require(state.container.first { $0.card.objectKey == "title" })
        #expect(title.isPresent && title.values["show"] == .bool(true))
        #expect(state.container.first { $0.card.objectKey == "border" }?.isPresent == false)
        #expect(state.readOnly.isEmpty && state.blocker == nil)
        // visual có mục theo trường
        let bound = try #require(env.editor.formatState(of: S.f5))
        #expect(bound.readOnly.contains { $0.object == "labels" && $0.property == nil })
        #expect(env.editor.formatState(of: "zzzzzzzzzzzzzzzzzzzz") == nil)
    }

    // MARK: (g) visual mới

    @Test func aNewVisualTakesFormatInItsAddedBytes() throws {
        let env = try Env(); defer { env.cleanUp() }
        let id = try #require(env.editor.insertVisual(type: "card", visibleRect: CGRect(x: 0, y: 0, width: 800, height: 600)))
        env.editor.addField(FieldRef(kind: .measure, entity: "Fact", property: "Net"), to: "Values", visual: id)
        #expect(env.editor.setFormat(.bool(false), scope: .container, object: "title", property: "show", visual: id) == nil)
        let bytes = try #require(env.editor.edited["p1"]?.added[id])
        let root = try JSONValue.parse(bytes)
        #expect(Self.literal(root["visual"]?["visualContainerObjects"], "title", "show") == "false")
        #expect(Self.literal(container(env, id), "title", "show") == "false")
        // objects mới chèn trước visualContainerObjects
        #expect(env.editor.setFormat(.number(30, tail: .d), scope: .objects, object: "labels", property: "fontSize", visual: id) == nil)
        let text = String(decoding: try #require(env.editor.edited["p1"]?.added[id]), as: UTF8.self)
        #expect(text.range(of: #""objects""#)!.lowerBound < text.range(of: #""visualContainerObjects""#)!.lowerBound)
        #expect(env.editor.visual(id)?.fields.map(\.property) == ["Net"])
    }

    // MARK: (h) bản sao mang định dạng

    @Test func copiesCarryTheFormatTheyWereMadeWith() throws {
        let env = try Env(); defer { env.cleanUp() }
        env.editor.setFormat(.number(28, tail: .d), scope: .objects, object: "labels", property: "fontSize", visual: S.f1)
        env.editor.setFormat(.bool(false), scope: .container, object: "title", property: "show", visual: S.f1)
        let copies = env.editor.duplicate([S.f1])
        let copy = try #require(copies.first)
        #expect(Self.literal(objects(env, copy), "labels", "fontSize") == "28D")
        #expect(Self.literal(container(env, copy), "title", "show") == "false")
        // Nhân bản trang (D5) cũng mang định dạng.
        let newPage = try #require(env.editor.duplicatePage("p1"))
        let onCopy = env.editor.visuals(of: newPage).filter { $0.type == "card" && $0.raw["visual"]?["objects"]?["labels"]?[0]?["properties"]?["fontSize"] != nil }
        #expect(onCopy.contains { $0.objects.number("labels", "fontSize") == 28 })
    }

    // MARK: (i) sửa trường và định dạng không làm mất nhau

    @Test func fieldEditsAndFormatEditsKeepEachOther() throws {
        let env = try Env(); defer { env.cleanUp() }
        let measure = FieldRef(kind: .measure, entity: "Fact", property: "Balance")
        #expect(env.editor.setFormat(.bool(true), scope: .objects, object: "legend", property: "show", visual: S.c1) == nil)
        #expect(env.editor.addField(measure, to: "Y", visual: S.c1) == nil)
        let afterField = try #require(env.editor.visual(S.c1))
        #expect(Self.literal(afterField.raw["visual"]?["objects"], "legend", "show") == "true")
        #expect(afterField.raw["visual"]?["query"]?["queryState"]?["Y"]?["projections"]?.array.count == 3)
        // ngược lại: sửa trường chờ rồi sửa định dạng
        #expect(env.editor.setFormat(.bool(false), scope: .objects, object: "legend", property: "show", visual: S.c1) == nil)
        let after = try #require(env.editor.visual(S.c1))
        #expect(after.raw["visual"]?["query"]?["queryState"]?["Y"]?["projections"]?.array.count == 3)
        #expect(after.fields.filter { $0.role == "Y" }.map(\.property) == ["Credit", "Debit", "Balance"])
        #expect(Self.literal(after.raw["visual"]?["objects"], "legend", "show") == "false")
    }

    // MARK: (j) đổi loại bỏ khoá định dạng

    @Test func aKeyDroppedByATypeChangeDoesNotComeBack() throws {
        let env = try Env(); defer { env.cleanUp() }
        #expect(env.editor.setFormat(.bool(true), scope: .objects, object: "zoom", property: "show", visual: S.c1) == nil)
        #expect(env.editor.setFormat(.bool(true), scope: .objects, object: "legend", property: "show", visual: S.c1) == nil)
        #expect(objects(env, S.c1)?["zoom"] != nil)
        // combo → donut: bỏ trục và thanh thu phóng (VM-D3), giữ chú giải.
        let reason = env.editor.changeType(of: S.c1, to: "donutChart")
        try #require(reason == nil, "đổi loại bị chặn: \(reason ?? "")")
        #expect(objects(env, S.c1)?["zoom"] == nil && objects(env, S.c1)?["legend"] != nil)
        // Sửa định dạng tiếp theo không tạo lại khoá đã bỏ.
        #expect(env.editor.setFormat(.bool(false), scope: .objects, object: "legend", property: "show", visual: S.c1) == nil)
        #expect(objects(env, S.c1)?["zoom"] == nil)
        #expect(env.editor.edited["p1"]?.formats[S.c1]?.contains { $0.object == "zoom" } != true)
    }

    // MARK: US2: thêm thuộc tính chưa có và đặt lại

    func bytes(_ env: Env, _ id: String) throws -> String {
        let base = try #require(env.editor.jsonBeforeFormats(of: id, page: "p1"))
        return String(decoding: try env.editor.withFormats(base, page: "p1", id: id), as: UTF8.self)
    }

    @Test func aMissingCardAndPropertyAreAppendedAtTheEnd() throws {
        let env = try Env(); defer { env.cleanUp() }
        // c1 chưa có `objects`: tạo khoá phạm vi rồi thẻ rồi thuộc tính.
        #expect(env.editor.setFormat(.bool(true), scope: .objects, object: "legend", property: "show", visual: S.c1) == nil)
        #expect(env.editor.setFormat(.number(9, tail: .d), scope: .objects, object: "legend", property: "fontSize", visual: S.c1) == nil)
        let text = try bytes(env, S.c1)
        #expect(text.contains(#""objects":{"legend":[{"properties":{"show":\#(S.lit("true")),"fontSize":\#(S.lit("9D"))}}]}"#))
        #expect(text.range(of: #""query""#)!.lowerBound < text.range(of: #""objects""#)!.lowerBound)
        // f1 đã có `labels`: thuộc tính mới đứng sau thuộc tính cũ.
        #expect(env.editor.setFormat(.bool(true), scope: .objects, object: "labels", property: "bold", visual: S.f1) == nil)
        #expect(try bytes(env, S.f1).contains(#""labelPrecision":\#(S.lit("1D")),"bold":\#(S.lit("true"))}}]"#))
    }

    @Test func aVisualWithNoFormatAtAllGetsBothScopesInDesktopOrder() throws {
        let env = try Env(); defer { env.cleanUp() }
        #expect(env.editor.setFormat(.bool(false), scope: .container, object: "title", property: "show", visual: S.f4) == nil)
        #expect(env.editor.setFormat(.bool(true), scope: .objects, object: "cardImage", property: "show", visual: S.f4) == nil)
        let text = try bytes(env, S.f4)
        #expect(text.contains(#""cardImage":[{"properties":{"show":\#(S.lit("true"))},"selector":{"id":"default"}}]"#))
        #expect(text.range(of: #""objects""#)!.lowerBound < text.range(of: #""visualContainerObjects""#)!.lowerBound)
        #expect(text.range(of: #""visualContainerObjects""#)!.lowerBound < text.range(of: #""drillFilterOtherVisuals""#)!.lowerBound)
        // Mục của loại khác không mang selector.
        #expect(env.editor.setFormat(.bool(true), scope: .objects, object: "legend", property: "show", visual: S.c1) == nil)
        #expect(try !bytes(env, S.c1).contains("selector"))
    }

    /// VM-D8 mục 6: Desktop thêm `columnSubtotals` vào mục `subTotals` khi tắt tổng phụ theo cột.
    @Test func tablesCanAddASubtotalSwitchThatIsNotInTheFileYet() throws {
        let env = try Env(); defer { env.cleanUp() }
        #expect(env.editor.setFormat(.bool(false), scope: .objects, object: "subTotals", property: "columnSubtotals", visual: S.f3) == nil)
        #expect(try bytes(env, S.f3).contains(#""subTotals":[{"properties":{"rowSubtotals":\#(S.lit("false")),"columnSubtotals":\#(S.lit("false"))}}]"#))
        #expect(env.editor.setFormat(.bool(true), scope: .objects, object: "subTotals", property: "rowSubtotals", visual: S.f3) == nil)
        #expect(env.editor.setFormat(.number(14, tail: .d), scope: .objects, object: "columnHeaders", property: "fontSize", visual: S.f3) == nil)
    }

    @Test func resetRemovesTheWholeCardOrOnePropertyAndUndoBringsItBack() throws {
        let env = try Env(); defer { env.cleanUp() }
        let original = try bytes(env, S.f1)
        let depth = env.editor.undoDepth
        #expect(env.editor.resetFormat(scope: .objects, object: "labels", visual: S.f1) == nil)
        #expect(objects(env, S.f1)?["labels"] == nil && objects(env, S.f1)?["categoryLabels"] != nil)
        #expect(env.editor.undoDepth == depth + 1)
        env.editor.undo()
        #expect(try bytes(env, S.f1) == original && !env.editor.isDirty)
        // một thuộc tính: chỉ bỏ nó
        #expect(env.editor.resetFormat(scope: .objects, object: "labels", property: "labelPrecision", visual: S.f1) == nil)
        #expect(Self.literal(objects(env, S.f1), "labels", "labelPrecision") == nil && Self.literal(objects(env, S.f1), "labels", "fontSize") == "20D")
        // thuộc tính cuối của khoá cuối: bỏ luôn khoá phạm vi
        #expect(env.editor.resetFormat(scope: .container, object: "title", property: "show", visual: S.f1) == nil)
        #expect(container(env, S.f1) == nil)
        #expect(env.editor.visual(S.f1)?.containerObjects.has("title") == false)
    }

    @Test func resetOfSomethingNotInTheFileMakesNoStepAndAddedThenResetRoundTrips() throws {
        let env = try Env(); defer { env.cleanUp() }
        let depth = env.editor.undoDepth
        #expect(env.editor.resetFormat(scope: .container, object: "border", visual: S.f1) == nil)
        #expect(env.editor.resetFormat(scope: .objects, object: "labels", property: "bold", visual: S.f1) == nil)
        #expect(env.editor.undoDepth == depth && !env.editor.isDirty)
        let original = try bytes(env, S.c1)
        #expect(env.editor.setFormat(.bool(true), scope: .objects, object: "legend", property: "show", visual: S.c1) == nil)
        #expect(env.editor.setFormat(.bool(true), scope: .objects, object: "zoom", property: "show", visual: S.c1) == nil)
        #expect(env.editor.resetFormat(scope: .objects, object: "legend", visual: S.c1) == nil)
        #expect(env.editor.resetFormat(scope: .objects, object: "zoom", visual: S.c1) == nil)
        #expect(try bytes(env, S.c1) == original)   // về y như trước khi thêm, kể cả khoá phạm vi
    }

    @Test func resetIsRefusedForACardWithFieldBoundEntries() throws {
        let env = try Env(); defer { env.cleanUp() }
        let depth = env.editor.undoDepth
        #expect(env.editor.resetFormat(scope: .objects, object: "labels", visual: S.f5)?.contains("riêng theo trường") == true)
        #expect(env.editor.undoDepth == depth)
        // Đặt lại một thuộc tính của mục chung thì được.
        #expect(env.editor.resetFormat(scope: .objects, object: "labels", property: "fontSize", visual: S.f5) == nil)
        #expect(objects(env, S.f5)?["labels"]?[0]?["selector"]?["metadata"]?.string == "Fact.Balance")
    }

    @Test func resetOnAnAddedVisualRemovesFromItsBytes() throws {
        let env = try Env(); defer { env.cleanUp() }
        let id = try #require(env.editor.insertVisual(type: "card", visibleRect: CGRect(x: 0, y: 0, width: 800, height: 600)))
        let fresh = try #require(env.editor.edited["p1"]?.added[id])
        #expect(env.editor.setFormat(.bool(false), scope: .container, object: "title", property: "show", visual: id) == nil)
        #expect(env.editor.resetFormat(scope: .container, object: "title", visual: id) == nil)
        #expect(env.editor.edited["p1"]?.added[id] == fresh)
    }

    // MARK: US3: phạm vi Chung

    @Test func theTitleCanBeEditedAndExtended() throws {
        let env = try Env(); defer { env.cleanUp() }
        let id = S.f1
        #expect(env.editor.setFormat(.bool(false), scope: .container, object: "title", property: "show", visual: id) == nil)
        #expect(env.editor.setFormat(.number(16, tail: .d), scope: .container, object: "title", property: "fontSize", visual: id) == nil)
        #expect(env.editor.setFormat(.bool(false), scope: .container, object: "title", property: "bold", visual: id) == nil)
        #expect(env.editor.setFormat(.choice("'center'"), scope: .container, object: "title", property: "alignment", visual: id) == nil)
        #expect(env.editor.setFormat(.color(.theme(id: 2, percent: 0.2)), scope: .container, object: "title", property: "fontColor", visual: id) == nil)
        let props = try #require(container(env, id)?["title"]?[0]?["properties"])
        #expect(props["show"]?["expr"]?["Literal"]?["Value"]?.string == "false")
        #expect(props["fontSize"]?["expr"]?["Literal"]?["Value"]?.string == "16D")
        #expect(props["alignment"]?["expr"]?["Literal"]?["Value"]?.string == "'center'")
        #expect(props["fontColor"]?["solid"]?["color"]?["expr"]?["ThemeDataColor"]?["ColorId"]?.number == 2)
    }

    @Test func subTitleBackgroundBorderShadowPaddingAndHeaderAreCreatedLikeDesktop() throws {
        let env = try Env(); defer { env.cleanUp() }
        let id = S.f2
        #expect(env.editor.setFormat(.bool(true), scope: .container, object: "subTitle", property: "show", visual: id) == nil)
        #expect(env.editor.setFormat(.text("Phụ đề"), scope: .container, object: "subTitle", property: "text", visual: id) == nil)
        // `transparency` một mình: không ghi `show` (VM-D4 mục 2).
        #expect(env.editor.setFormat(.number(25, tail: .d), scope: .container, object: "background", property: "transparency", visual: id) == nil)
        #expect(container(env, id)?["background"]?[0]?["properties"]?.object.keys.sorted() == ["transparency"])
        #expect(env.editor.setFormat(.bool(true), scope: .container, object: "border", property: "show", visual: id) == nil)
        #expect(env.editor.setFormat(.number(20, tail: .d), scope: .container, object: "border", property: "radius", visual: id) == nil)
        #expect(env.editor.setFormat(.number(3, tail: .d), scope: .container, object: "border", property: "width", visual: id) == nil)
        #expect(env.editor.setFormat(.bool(true), scope: .container, object: "dropShadow", property: "show", visual: id) == nil)
        for side in ["top", "bottom", "left", "right"] {
            #expect(env.editor.setFormat(.number(8, tail: .d), scope: .container, object: "padding", property: side, visual: id) == nil)
        }
        #expect(env.editor.setFormat(.bool(false), scope: .container, object: "visualHeader", property: "show", visual: id) == nil)
        let keys = try #require(container(env, id)?.object.keys.sorted())
        #expect(keys == ["background", "border", "dropShadow", "padding", "subTitle", "title", "visualHeader"])
        // Khoá mới đứng sau khoá cũ theo thứ tự thêm (Desktop ghi như vậy).
        let text = try bytes(env, id)
        let order = ["\"title\"", "\"subTitle\"", "\"background\"", "\"border\"", "\"dropShadow\"", "\"padding\"", "\"visualHeader\""]
        let positions = order.map { text.range(of: $0, range: text.range(of: #""visualContainerObjects""#)!.lowerBound..<text.endIndex)!.lowerBound }
        #expect(positions == positions.sorted())
    }

    @Test func linkAndUnobservedGeneralKeysStayReadOnly() throws {
        let env = try Env(); defer { env.cleanUp() }
        #expect(env.editor.setFormat(.bool(true), scope: .container, object: "visualLink", property: "show", visual: S.f1) != nil)
        // Các số của bóng Desktop ghi cả bộ theo preset (VM-D8): chưa có trong file thì không thêm lẻ.
        #expect(env.editor.setFormat(.number(10, tail: .l), scope: .container, object: "dropShadow", property: "shadowBlur", visual: S.f1) != nil)
        #expect(env.editor.undoDepth == 0)
        let state = try #require(env.editor.formatState(of: S.f1))
        #expect(state.container.map(\.card.objectKey) == ["title", "subTitle", "divider", "background", "border", "dropShadow", "padding", "visualHeader"])
        // Màu bóng đã quan sát ở VM-D8 nên thêm được.
        #expect(env.editor.setFormat(.color(.hex("#FFFFFF")), scope: .container, object: "dropShadow", property: "color", visual: S.f1) == nil)
    }
}
