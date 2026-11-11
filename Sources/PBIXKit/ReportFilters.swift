import Foundation

/// A filter card as shown in the Filters pane (report, page or visual level).
public struct ReportFilter: Sendable, Hashable, Identifiable {
    public enum Level: String, Sendable { case report, page, visual }

    public let id: String
    public let level: Level
    public let field: ReportField?
    /// `Categorical`, `Advanced`, `TopN`, `RelativeDate`, …
    public let type: String
    /// Human-readable condition, e.g. `không phải 9999`.
    public let summary: String
    public let isHidden: Bool
    public let isLocked: Bool
    /// JSON gốc của bộ lọc (`field`, `filter.Where`, `howCreated`…), để dịch sang DAX (Phase C).
    public let raw: JSONValue
    public var isActive: Bool { summary != ReportFilter.allLabel }

    public init(id: String, level: Level, field: ReportField?, type: String, summary: String, isHidden: Bool, isLocked: Bool,
                raw: JSONValue = .null) {
        self.id = id
        self.level = level
        self.field = field
        self.type = type
        self.summary = summary
        self.isHidden = isHidden
        self.isLocked = isLocked
        self.raw = raw
    }

    static let allLabel = "là (Tất cả)"
}

/// Phần dữ liệu của bookmark (khi không `suppressData`): bộ lọc và lựa chọn slicer đã lưu.
/// [QUAN SÁT, VM C2 B1] `explorationState.filters.byExpr`, `sections.<trang>.filters.byExpr`,
/// `visualContainers.<visual>.filters.byExpr`; lựa chọn slicer ở `singleVisual.objects.merge.general[0].properties.filter.filter`.
public struct BookmarkData: Sendable, Hashable {
    public var reportFilters: [ReportFilter] = []
    /// Trang có trong bookmark → bộ lọc cấp trang (có thể rỗng).
    public var pageFilters: [String: [ReportFilter]] = [:]
    /// Visual có trong bookmark → bộ lọc cấp visual (có thể rỗng).
    public var visualFilters: [String: [ReportFilter]] = [:]
    /// Visual có trong bookmark → điều kiện lựa chọn slicer (`filter` của `objects.general`), nếu có.
    public var slicerFilters: [String: JSONValue] = [:]

    public init() {}
}

public struct ReportBookmark: Sendable, Hashable, Identifiable {
    public let id: String
    public let displayName: String
    public let group: String?
    /// Trang mà bookmark ghi lại (`explorationState.activeSection`).
    public let activeSection: String?
    /// `options.suppressActiveSection`: áp bookmark không chuyển trang.
    public let suppressActiveSection: Bool
    /// `options.suppressData`: áp bookmark không đổi bộ lọc/slicer, chỉ đổi hiển thị.
    public let suppressData: Bool
    /// `options.applyOnlyToTargetVisuals` cùng `targetVisualNames`; nil khi áp cho mọi visual.
    public let targetVisualNames: [String]?
    /// Hiển thị mà bookmark ghi: id visual → `true` nếu `display.mode == hidden`. Chỉ có visual nằm trong bookmark.
    public let hidden: [String: Bool]
    /// Bộ lọc và slicer đã lưu; nil khi `suppressData`.
    public let data: BookmarkData?

    public init(id: String, displayName: String, group: String?, activeSection: String? = nil, suppressActiveSection: Bool = false,
                suppressData: Bool = false, targetVisualNames: [String]? = nil, hidden: [String: Bool] = [:],
                data: BookmarkData? = nil) {
        self.data = data
        self.id = id
        self.displayName = displayName
        self.group = group
        self.activeSection = activeSection
        self.suppressActiveSection = suppressActiveSection
        self.suppressData = suppressData
        self.targetVisualNames = targetVisualNames
        self.hidden = hidden
    }

    /// Đọc một file `*.bookmark.json` (PBIR).
    public static func parse(_ json: JSONValue, fallbackName: String, group: String?) -> ReportBookmark {
        let options = json["options"]
        var hidden: [String: Bool] = [:]
        for (_, section) in json["explorationState"]?["sections"]?.object ?? [:] {
            for (visualID, container) in section["visualContainers"]?.object ?? [:] {
                let mode = container["singleVisual"]?["display"]?["mode"]?.string
                hidden[visualID] = (mode == "hidden")
            }
        }
        // `options.suppressDisplay` (VM-D6): áp bookmark không đổi ẩn/hiện, dù explorationState vẫn ghi trạng thái hiển thị.
        if options?["suppressDisplay"]?.bool ?? false { hidden = [:] }
        let only = options?["applyOnlyToTargetVisuals"]?.bool ?? false
        let suppressData = options?["suppressData"]?.bool ?? false
        var data: BookmarkData?
        if !suppressData {
            var d = BookmarkData()
            let state = json["explorationState"]
            d.reportFilters = PBIXFile.filters(state?["filters"]?["byExpr"], level: .report)
            for (pageID, section) in state?["sections"]?.object ?? [:] {
                d.pageFilters[pageID] = PBIXFile.filters(section["filters"]?["byExpr"], level: .page)
                for (visualID, container) in section["visualContainers"]?.object ?? [:] {
                    d.visualFilters[visualID] = PBIXFile.filters(container["filters"]?["byExpr"], level: .visual)
                    // Bookmark thật của Power BI ghi lựa chọn slicer dưới `objects.merge.general` (xem VM-TODO-C2 B1); file visual dùng `objects.general`.
                    let objects = container["singleVisual"]?["objects"]
                    if let filter = objects?["merge"]?["general"]?[0]?["properties"]?["filter"]?["filter"]
                        ?? objects?["general"]?[0]?["properties"]?["filter"]?["filter"] {
                        d.slicerFilters[visualID] = filter
                    }
                }
            }
            data = d
        }
        return ReportBookmark(
            id: json["name"]?.string ?? fallbackName, displayName: json["displayName"]?.string ?? fallbackName, group: group,
            activeSection: json["explorationState"]?["activeSection"]?.string,
            suppressActiveSection: options?["suppressActiveSection"]?.bool ?? false,
            suppressData: suppressData,
            targetVisualNames: only ? (options?["targetVisualNames"]?.array ?? []).compactMap(\.string) : nil,
            hidden: hidden, data: data)
    }
}

extension PBIXFile {
    public func loadFilters(report: ReportDefinition) -> (report: [ReportFilter], pages: [String: [ReportFilter]], visuals: [String: [ReportFilter]]) {
        var pages: [String: [ReportFilter]] = [:]
        var visuals: [String: [ReportFilter]] = [:]
        var reportLevel: [ReportFilter] = []

        switch reportFormat {
        case .pbir:
            let root = "Report/definition/"
            if let json = try? jsonPart(root + "report.json") {
                reportLevel = Self.filters(json["filterConfig"]?["filters"], level: .report)
            }
            for page in report.pages {
                let base = root + "pages/\(page.id)/"
                if let json = try? jsonPart(base + "page.json") {
                    pages[page.id] = Self.filters(json["filterConfig"]?["filters"], level: .page)
                }
                for entry in archive.entries where entry.path.hasPrefix(base + "visuals/") && entry.path.hasSuffix("/visual.json") {
                    guard let json = try? jsonPart(entry.path), let name = json["name"]?.string else { continue }
                    let list = Self.filters(json["filterConfig"]?["filters"], level: .visual)
                    if !list.isEmpty { visuals[name] = list }
                }
            }
        case .legacyLayout:
            guard let layout = try? JSONValue.parse(try utf16Part("Report/Layout")) else { break }
            reportLevel = Self.filters(Self.embedded(layout["filters"]), level: .report)
            for section in layout["sections"]?.array ?? [] {
                guard let id = section["name"]?.string else { continue }
                pages[id] = Self.filters(Self.embedded(section["filters"]), level: .page)
                for container in section["visualContainers"]?.array ?? [] {
                    guard let name = Self.embedded(container["config"])?["name"]?.string else { continue }
                    let list = Self.filters(Self.embedded(container["filters"]), level: .visual)
                    if !list.isEmpty { visuals[name] = list }
                }
            }
        case .none:
            break
        }
        return (reportLevel, pages, visuals)
    }

    public func loadBookmarks() -> [ReportBookmark] {
        switch reportFormat {
        case .pbir:
            let root = "Report/definition/bookmarks/"
            var names: [String: String] = [:]
            var parsed: [String: JSONValue] = [:]
            for entry in archive.entries where entry.path.hasPrefix(root) && entry.path.hasSuffix(".bookmark.json") {
                if let json = try? jsonPart(entry.path), let name = json["name"]?.string {
                    names[name] = json["displayName"]?.string ?? name
                    parsed[name] = json
                }
            }
            var result: [ReportBookmark] = []
            func walk(_ items: [JSONValue], group: String?) {
                for item in items {
                    guard let name = item["name"]?.string else { continue }
                    if let children = item["children"]?.array {
                        walk(children.map { $0.string.map { JSONValue.object(["name": .string($0)]) } ?? $0 },
                             group: item["displayName"]?.string ?? name)
                    } else {
                        result.append(parsed[name].map { ReportBookmark.parse($0, fallbackName: name, group: group) }
                            ?? ReportBookmark(id: name, displayName: names[name] ?? name, group: group))
                    }
                }
            }
            walk((try? jsonPart(root + "bookmarks.json"))?["items"]?.array ?? [], group: nil)
            // Bookmarks missing from the index still exist on disk.
            for (name, display) in names.sorted(by: { $0.key < $1.key }) where !result.contains(where: { $0.id == name }) {
                result.append(parsed[name].map { ReportBookmark.parse($0, fallbackName: name, group: nil) }
                    ?? ReportBookmark(id: name, displayName: display, group: nil))
            }
            return result
        case .legacyLayout:
            guard let layout = try? JSONValue.parse(try utf16Part("Report/Layout")),
                  let config = Self.embedded(layout["config"]) else { return [] }
            var result: [ReportBookmark] = []
            for item in config["bookmarks"]?.array ?? [] {
                if let children = item["children"]?.array {
                    for child in children {
                        result.append(ReportBookmark(id: child["name"]?.string ?? UUID().uuidString,
                                                     displayName: child["displayName"]?.string ?? "",
                                                     group: item["displayName"]?.string))
                    }
                } else {
                    result.append(ReportBookmark(id: item["name"]?.string ?? UUID().uuidString,
                                                 displayName: item["displayName"]?.string ?? "", group: nil))
                }
            }
            return result
        case .none:
            return []
        }
    }

    func jsonPart(_ path: String) throws -> JSONValue {
        var data = try archive.read(path)
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { data = data.dropFirst(3) }
        return try JSONValue.parse(data)
    }

    /// Legacy layout stores nested JSON as strings.
    static func embedded(_ value: JSONValue?) -> JSONValue? {
        if let text = value?.string { return try? JSONValue.parse(text) }
        return value
    }

    public static func filters(_ list: JSONValue?, level: ReportFilter.Level) -> [ReportFilter] {
        (list?.array ?? []).enumerated().map { index, f in
            let field = parseFieldExpression(f["field"] ?? f["expression"])
            return ReportFilter(
                id: f["name"]?.string ?? "\(level.rawValue)-\(index)",
                level: level,
                field: field,
                type: f["type"]?.string ?? "Categorical",
                summary: describe(f["filter"], type: f["type"]?.string),
                isHidden: f["isHiddenInViewMode"]?.bool ?? false,
                isLocked: f["isLockedInViewMode"]?.bool ?? false,
                raw: f)
        }
    }

    // MARK: Condition text

    static func describe(_ filter: JSONValue?, type: String?) -> String {
        if type == "TopN" { return "Top N" }
        if type == "RelativeDate" || type == "RelativeTime" { return "khoảng thời gian tương đối" }
        guard let conditions = filter?["Where"]?.array, !conditions.isEmpty else { return ReportFilter.allLabel }
        return conditions.compactMap { describe(condition: $0["Condition"]) }.joined(separator: " và ")
    }

    private static func describe(condition: JSONValue?) -> String? {
        guard let c = condition else { return nil }
        if let inner = c["Not"]?["Expression"] {
            if let values = inner["In"]?["Values"] { return "không phải " + list(values) }
            return "không (" + (describe(condition: inner) ?? "?") + ")"
        }
        if let values = c["In"]?["Values"] { return "là " + list(values) }
        if let cmp = c["Comparison"] {
            let ops = [0: "=", 1: ">", 2: "≥", 3: "<", 4: "≤"]
            let value = cmp["Right"].flatMap { ReportLiteral(expression: $0) }.map(text) ?? "?"
            return "\(ops[Int(cmp["ComparisonKind"]?.number ?? 0)] ?? "=") \(value)"
        }
        if let and = c["And"] {
            return [describe(condition: and["Left"]), describe(condition: and["Right"])].compactMap { $0 }.joined(separator: " và ")
        }
        if let or = c["Or"] {
            return [describe(condition: or["Left"]), describe(condition: or["Right"])].compactMap { $0 }.joined(separator: " hoặc ")
        }
        if let between = c["Between"] {
            let lo = between["LowerBound"].flatMap { ReportLiteral(expression: $0) }.map(text) ?? "?"
            let hi = between["UpperBound"].flatMap { ReportLiteral(expression: $0) }.map(text) ?? "?"
            return "từ \(lo) đến \(hi)"
        }
        if let contains = c["Contains"] {
            return "chứa " + (contains["Right"].flatMap { ReportLiteral(expression: $0) }.map(text) ?? "?")
        }
        return "điều kiện nâng cao"
    }

    private static func list(_ values: JSONValue) -> String {
        let items = values.array.compactMap { tuple in tuple.array.first.flatMap { ReportLiteral(expression: $0) }.map(text) }
        if items.count > 3 { return items.prefix(3).joined(separator: ", ") + " +\(items.count - 3)" }
        return items.joined(separator: ", ")
    }

    private static func text(_ literal: ReportLiteral) -> String {
        switch literal {
        case .string(let s): s.isEmpty ? "(Trống)" : s
        case .number(let n): n == n.rounded() ? String(Int64(n)) : String(n)
        case .bool(let b): b ? "True" : "False"
        case .null: "(Trống)"
        case .themeColor, .resource: "?"
        }
    }
}

extension PBIXFile {
    /// The page Power BI reopens on: `pages.json` `activePageName` (PBIR) or `activeSectionIndex` (legacy).
    public var activePageID: String? {
        switch reportFormat {
        case .pbir:
            return (try? jsonPart("Report/definition/pages/pages.json"))?["activePageName"]?.string
        case .legacyLayout:
            guard let layout = try? JSONValue.parse(try utf16Part("Report/Layout")) else { return nil }
            let index = Int(Self.embedded(layout["config"])?["activeSectionIndex"]?.number ?? 0)
            return layout["sections"]?[index]?["name"]?.string
        case .none:
            return nil
        }
    }
}
