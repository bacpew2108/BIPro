import Foundation
import PBIXKit

/// Auto date/time như Power BI Desktop 2.159 (đợt tồn đọng sau Phase F, US2). T025 chốt mẫu; T032 thêm phần sinh `ModelEdit`.
///
/// Desktop lưu, với tuỳ chọn của file bật (chú thích mô hình `__PBI_TimeIntelligenceEnabled = 1`, mặc định cho tài liệu mới):
/// - một `DateTableTemplate_<guid>` cho mỗi mô hình: bảng tính toán ẩn, riêng tư;
/// - một `LocalDateTable_<guid>` cho mỗi cột Date hoặc DateTime của bảng người dùng: bảng tính toán ẩn, chỉ hiện như biến thể;
/// - quan hệ `T[c]` (nhiều) → `LocalDateTable_…[Date]` (một): tên là GUID trần, `JoinOnDateBehavior` 2, một chiều, hoạt động;
/// - một `Variation` "Variation" trên `T[c]`, trỏ quan hệ đó và phân cấp "Date Hierarchy" của bảng cục bộ, `IsDefault`.
/// Tắt tuỳ chọn: xoá hết các thứ trên, chú thích về 0, visual dùng phân cấp được viết lại thành cột thường. Bật lại: GUID mới.
///
/// Nguồn: `docs/phase-f2-evidence/vm-f11/QUAN-SAT.md` mục b; `w8.3.pbix` và `vm-f11/f11-desktop.pbix` cùng mẫu
/// (`Tests/PBIXKitTests/F2AutoDateGoldenTests.swift`; hằng số dưới đây kiểm lại ở `Tests/BIProTests/Model/AutoDateTemplateTests.swift`).
enum AutoDateTime {
    /// Chú thích mô hình: "1" bật, "0" tắt.
    static let modelAnnotation = "__PBI_TimeIntelligenceEnabled"

    static let templateTablePrefix = "DateTableTemplate_"
    static let localTablePrefix = "LocalDateTable_"

    /// Chú thích bảng mẫu (`IsHidden`, `IsPrivate`, không `ShowAsVariationsOnly`).
    static let templateTableAnnotations = ["__PBI_TemplateDateTable": "true", "DefaultItem": "DateHierarchy"]
    /// Chú thích bảng cục bộ (`IsHidden`, `ShowAsVariationsOnly`, không `IsPrivate`).
    static let localTableAnnotations = ["__PBI_LocalDateTable": "true"]

    /// Biểu thức bảng mẫu.
    static let templateExpression = "Calendar(Date(2015,1,1), Date(2015,1,1))"

    /// Biểu thức bảng cục bộ cho cột `table[column]`: lịch đủ các năm có trong cột.
    /// `[SUY ĐOÁN]` tên có `'` hoặc `]` được thoát như DAX thường (`''`, `]]`); hai file Desktop không có tên như vậy.
    static func localExpression(table: String, column: String) -> String {
        let source = "'\(table.replacingOccurrences(of: "'", with: "''"))'[\(column.replacingOccurrences(of: "]", with: "]]"))]"
        return "Calendar(Date(Year(MIN(\(source))), 1, 1), Date(Year(MAX(\(source))), 12, 31))"
    }

    /// Tên bảng mới: tiền tố + GUID chữ thường, như Desktop.
    static func tableName(prefix: String, id: UUID = UUID()) -> String { prefix + id.uuidString.lowercased() }

    /// Tên quan hệ ngày: GUID trần chữ thường (quan hệ tự phát hiện mới có tiền tố `AutoDetected_`).
    static func relationshipName(id: UUID = UUID()) -> String { id.uuidString.lowercased() }

    /// Một cột của bảng ngày (cả bảng mẫu và bảng cục bộ). Mọi cột ẩn, `SummarizeBy` None, chú thích `SummarizationSetBy = User`;
    /// `Date` là cột của `Calendar` (không biểu thức), các cột khác là cột tính toán.
    struct Column: Equatable {
        let name: String
        let expression: String?
        let dataType: ModelMetadata.DataType
        let dataCategory: String
        let formatString: String?
        let sortBy: String?
        /// Chú thích `TemplateId`; `Date` không có.
        let templateId: String?
    }

    static let columns: [Column] = [
        Column(name: "Date", expression: nil, dataType: .dateTime, dataCategory: "PaddedDateTableDates",
               formatString: "General Date", sortBy: nil, templateId: nil),
        Column(name: "Year", expression: "YEAR([Date])", dataType: .int64, dataCategory: "Years",
               formatString: "0", sortBy: nil, templateId: "Year"),
        Column(name: "MonthNo", expression: "MONTH([Date])", dataType: .int64, dataCategory: "MonthOfYear",
               formatString: "0", sortBy: nil, templateId: "MonthNumber"),
        Column(name: "Month", expression: "FORMAT([Date], \"MMMM\")", dataType: .string, dataCategory: "Months",
               formatString: nil, sortBy: "MonthNo", templateId: "Month"),
        Column(name: "QuarterNo", expression: "INT(([MonthNo] + 2) / 3)", dataType: .int64, dataCategory: "QuarterOfYear",
               formatString: "0", sortBy: nil, templateId: "QuarterNumber"),
        Column(name: "Quarter", expression: "\"Qtr \" & [QuarterNo]", dataType: .string, dataCategory: "Quarters",
               formatString: nil, sortBy: "QuarterNo", templateId: "Quarter"),
        Column(name: "Day", expression: "DAY([Date])", dataType: .int64, dataCategory: "DayOfMonth",
               formatString: "0", sortBy: nil, templateId: "Day"),
    ]

    static let columnAnnotations = ["SummarizationSetBy": "User"]

    /// Phân cấp ở bảng mẫu và mỗi bảng cục bộ; không ẩn; chú thích `TemplateId = DateHierarchy`.
    static let hierarchyName = "Date Hierarchy"
    static let hierarchyLevels = ["Year", "Quarter", "Month", "Day"]
    static let hierarchyAnnotations = ["TemplateId": "DateHierarchy"]

    /// Quan hệ ngày: `JoinOnDateBehavior` 2 (DatePartOnly), `CrossFilteringBehavior` 1 (một chiều).
    static let joinOnDateBehavior = 2
    static let crossFilteringBehavior = 1

    static let variationName = "Variation"
}

// MARK: - T032: sinh `ModelEdit` theo vòng đời (`specs/011-ton-dong-sau-phase-f/data-model.md`, "Bảng ngày cục bộ")

extension AutoDateTime {
    /// Tuỳ chọn của file đang bật.
    static func isEnabled(_ model: ModelMetadata) -> Bool { model.modelAnnotations[modelAnnotation] == "1" }

    static func isLocalTable(_ name: String) -> Bool { name.hasPrefix(localTablePrefix) }
    static func isTemplateTable(_ name: String) -> Bool { name.hasPrefix(templateTablePrefix) }

    /// Cột được sinh bảng ngày: cột ngày (kiểu `dateTime`, cả Date lẫn DateTime) không ẩn của bảng người dùng, trừ bảng đã đánh dấu
    /// là bảng ngày (`DataCategory = Time`) và cột ở phía nhiều của một quan hệ (tài liệu Power BI "Auto date/time": cột không phải phía
    /// "many" của quan hệ; `w8.3.pbix`: các cột ngày nối tới bảng `Ngày` không có bảng ngày cục bộ, T066).
    static func wantsLocalTable(_ column: ModelMetadata.Column, in model: ModelMetadata) -> Bool {
        guard column.dataType == .dateTime, !column.isHidden, column.kind != .rowNumber,
              let table = model.tables.first(where: { $0.name == column.tableName }), table.isUserTable, table.dataCategory != "Time" else { return false }
        if isManySide(table: column.tableName, column: column.name, in: model) { return false }
        return !isLocalTable(table.name) && !isTemplateTable(table.name)
    }

    /// Cột là đầu nhiều của một quan hệ thường (không tính quan hệ tới bảng ngày cục bộ).
    static func isManySide(table: String, column: String, in model: ModelMetadata) -> Bool {
        model.relationships.contains {
            ($0.fromTable == table && $0.fromColumn == column && $0.cardinality.hasPrefix("M"))
                || ($0.toTable == table && $0.toColumn == column && $0.cardinality.hasSuffix("M"))
        }
    }

    /// Thao tác dựng một bảng ngày (cột, cờ, phân cấp). Thứ tự theo `AutoDateWriteTests.localDateEdits` (T031): bảng và cột trước, cờ bảng sau
    /// cùng vì bộ ghi đặt `SystemFlags = 2` cho mọi cột đã có.
    private static func tableEdits(name: String, expression: String, template: Bool) -> [ModelEdit] {
        var edits: [ModelEdit] = [.addCalculatedTable(name: name, expression: expression,
                                                      columns: [ColumnSignature(name: "Date", dataType: .dateTime, sourceColumn: "[Date]")])]
        for column in columns {
            guard let expression = column.expression else { continue }
            edits.append(.addCalculatedColumn(table: name, name: column.name, expression: expression, dataType: column.dataType))
        }
        for column in columns {
            var annotations = columnAnnotations.mapValues { Assignment.set($0) }
            if let id = column.templateId { annotations["TemplateId"] = .set(id) }
            edits.append(.updateColumn(table: name, name: column.name, patch: ColumnPatch(
                isHidden: true, formatString: column.formatString.map { .set($0) }, summarizeBy: 2,
                dataCategory: .set(column.dataCategory), sortBy: column.sortBy.map { .set($0) }, annotations: annotations)))
        }
        let notes = (template ? templateTableAnnotations : localTableAnnotations).mapValues { Assignment.set($0) }
        edits.append(.updateTable(name: name, patch: template ? TablePatch(isHidden: true, isPrivate: true, annotations: notes)
                                                              : TablePatch(isHidden: true, showAsVariationsOnly: true, annotations: notes)))
        edits.append(.addHierarchy(NewHierarchy(table: name, name: hierarchyName,
                                                levels: hierarchyLevels.map { HierarchyLevel(name: $0, column: $0) },
                                                annotations: hierarchyAnnotations)))
        return edits
    }

    /// Bộ bảng ngày cục bộ cho `table[column]`: bảng, quan hệ chỉ so phần ngày, variation.
    static func addEdits(table: String, column: String, id: () -> UUID = UUID.init) -> [ModelEdit] {
        let local = tableName(prefix: localTablePrefix, id: id()), relationship = relationshipName(id: id())
        return tableEdits(name: local, expression: localExpression(table: table, column: column), template: false) + [
            .addRelationship(NewRelationship(name: relationship, fromTable: table, fromColumn: column, toTable: local, toColumn: "Date",
                                             crossFilteringBehavior: crossFilteringBehavior, joinOnDateBehavior: joinOnDateBehavior)),
            .addVariation(table: table, column: column, relationship: relationship, hierarchy: HierarchyRef(table: local, name: hierarchyName)),
        ]
    }

    static func templateEdits(id: () -> UUID = UUID.init) -> [ModelEdit] {
        tableEdits(name: tableName(prefix: templateTablePrefix, id: id()), expression: templateExpression, template: true)
    }

    /// Bỏ bộ bảng ngày của một variation: variation, quan hệ, phân cấp, bảng cục bộ (thứ tự bộ ghi cần).
    static func dropEdits(_ variation: ModelMetadata.Variation) -> [ModelEdit] {
        [.dropVariation(table: variation.table, column: variation.column), .deleteRelationship(name: variation.relationship),
         .dropHierarchy(table: variation.hierarchy.table, name: variation.hierarchy.name), .dropTable(name: variation.hierarchy.table)]
    }

    private static func templateDropEdits(_ model: ModelMetadata) -> [ModelEdit] {
        model.tables.filter { isTemplateTable($0.name) }.flatMap { table -> [ModelEdit] in
            let hierarchies = model.hierarchyNames(table.name)
            return hierarchies.map { .dropHierarchy(table: table.name, name: $0) } + [.dropTable(name: table.name)]
        }
    }

    /// Bật hoặc tắt tuỳ chọn trên mô hình hiệu lực `model`. Tắt: bỏ mọi bộ bảng ngày và bảng mẫu, chú thích về 0. Bật: chú thích 1, bảng mẫu,
    /// bộ bảng cho mọi cột ngày chưa có (GUID mới, như Desktop bật lại).
    static func toggle(enabled: Bool, model: ModelMetadata, id: () -> UUID = UUID.init) -> [ModelEdit] {
        if !enabled {
            return model.variations.flatMap(dropEdits) + templateDropEdits(model) + [.setModelAnnotation(name: modelAnnotation, value: "0")]
        }
        let covered = Set(model.variations.map { "\($0.table)\u{0}\($0.column)" })
        let wanted = model.columns.filter { wantsLocalTable($0, in: model) && !covered.contains("\($0.tableName)\u{0}\($0.name)") }
        var edits: [ModelEdit] = [.setModelAnnotation(name: modelAnnotation, value: "1")]
        if !wanted.isEmpty || !model.variations.isEmpty, !model.tables.contains(where: { isTemplateTable($0.name) }) { edits += templateEdits(id: id) }
        for column in wanted { edits += addEdits(table: column.tableName, column: column.name, id: id) }
        return edits
    }

    /// Thao tác của người dùng `edits` trên mô hình hiệu lực `model`, kèm thao tác Auto date/time khi tuỳ chọn bật:
    /// - trước: bỏ bộ bảng ngày của cột sắp mất, đổi tên, đổi dữ liệu hay công thức (bảng xoá hoặc thay, cột tính toán sửa hoặc xoá);
    /// - sau: thêm bộ bảng ngày cho cột ngày vừa có (bảng nạp, thay, bảng hay cột tính toán mới), bảng mẫu khi chưa có, bỏ bảng mẫu khi
    ///   không còn bảng cục bộ nào.
    /// Bảng thay dữ liệu thì bộ bảng dựng lại (GUID mới) vì khoảng năm theo dữ liệu mới. Mô hình không áp được thì trả nguyên `edits`
    /// để bước kiểm báo lý do.
    static func expand(_ edits: [ModelEdit], model: ModelMetadata, id: () -> UUID = UUID.init) -> [ModelEdit] {
        guard isEnabled(model), !edits.isEmpty else { return edits }
        // Đổi tuỳ chọn ngay trong lô: để `toggle` lo.
        if edits.contains(where: { if case .setModelAnnotation(modelAnnotation, _) = $0 { true } else { false } }) { return edits }
        var dropped: [String: ModelMetadata.Variation] = [:]   // "bảng\0cột" → variation bỏ trước
        func drop(_ test: (ModelMetadata.Variation) -> Bool) {
            for v in model.variations where test(v) { dropped["\(v.table)\u{0}\(v.column)"] = v }
        }
        var touched = Set<String>()   // bảng có cột cần xét sau (chữ thường) hoặc "bảng\0cột"
        for edit in edits {
            switch edit {
            case .dropTable(let t): drop { $0.table == t }
            case .replaceTable(let t, let new): drop { $0.table == t }; touched.insert(new.name)
            case .updateCalculatedTable(let t, _, _): drop { $0.table == t }; touched.insert(t)
            case .addTable(let new): touched.insert(new.name)
            case .addCalculatedTable(let t, _, _): touched.insert(t)
            case .deleteCalculatedColumn(let t, let c): drop { $0.table == t && $0.column == c }
            case .updateCalculatedColumn(let t, let c, _, _): drop { $0.table == t && $0.column == c }; touched.insert("\(t)\u{0}\(c)")
            case .addCalculatedColumn(let t, let c, _, _): touched.insert("\(t)\u{0}\(c)")
            case .addRelationship(let r):
                // Cột thành phía nhiều thì bỏ bảng ngày của nó (Desktop chỉ có bảng ngày cho cột không ở phía nhiều).
                if r.fromMany { drop { $0.table == r.fromTable && $0.column == r.fromColumn } }
                if r.toMany { drop { $0.table == r.toTable && $0.column == r.toColumn } }
            case .deleteRelationship(let name):
                if let r = model.relationships.first(where: { $0.name == name }) {
                    touched.insert("\(r.fromTable)\u{0}\(r.fromColumn)"); touched.insert("\(r.toTable)\u{0}\(r.toColumn)")
                }
            case .updateColumn(let t, let c, let patch):
                if let renamed = patch.name?.trimmingCharacters(in: .whitespacesAndNewlines), renamed != c {
                    drop { $0.table == t && $0.column == c }; touched.insert("\(t)\u{0}\(renamed)")
                }
            default: break
            }
        }
        let before = dropped.values.sorted { ($0.table, $0.column) < ($1.table, $1.column) }.flatMap(dropEdits)
        guard let after = try? model.applying(ModelEdits(before + edits)) else { return edits }
        let covered = Set(after.variations.map { "\($0.table)\u{0}\($0.column)" })
        let added = after.columns.filter {
            (touched.contains($0.tableName) || touched.contains("\($0.tableName)\u{0}\($0.name)")) && wantsLocalTable($0, in: after)
                && !covered.contains("\($0.tableName)\u{0}\($0.name)")
        }
        var trailing: [ModelEdit] = []
        let hasTemplate = after.tables.contains { isTemplateTable($0.name) }
        if !added.isEmpty, !hasTemplate { trailing += templateEdits(id: id) }
        for column in added { trailing += addEdits(table: column.tableName, column: column.name, id: id) }
        if added.isEmpty, after.variations.isEmpty, hasTemplate { trailing += templateDropEdits(after) }
        return before + edits + trailing
    }
}

private extension ModelMetadata {
    /// Tên phân cấp của bảng, kể cả bảng hệ thống (`hierarchies` chỉ có bảng thường): bảng ngày luôn có "Date Hierarchy".
    func hierarchyNames(_ table: String) -> [String] {
        let listed = hierarchies.filter { $0.tableName == table }.map(\.name)
        return listed.isEmpty ? [AutoDateTime.hierarchyName] : listed
    }
}
