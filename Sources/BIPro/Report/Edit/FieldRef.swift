import AppKit
import PBIXKit
import SwiftUI
import UniformTypeIdentifiers

/// Một trường của mô hình (cột hoặc measure) đang được kéo từ pane Dữ liệu hoặc chọn từ menu "Thêm trường".
/// Xem `specs/003-d2-build-pane-field-well/data-model.md`.
struct FieldRef: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case column, measure }
    enum Family: String, Codable, Sendable { case numeric, text, date, boolean, other }

    var kind: Kind
    var entity: String
    var property: String
    /// Nhóm kiểu dữ liệu của cột (measure: `.other`).
    var family: Family = .other
    /// AMO `summarizeBy` của cột (1 mặc định, 2 không, 3 tổng, …); measure: nil.
    var summarizeBy: Int?

    var queryRef: String { "\(entity).\(property)" }

    init(kind: Kind, entity: String, property: String, family: Family = .other, summarizeBy: Int? = nil) {
        self.kind = kind; self.entity = entity; self.property = property; self.family = family; self.summarizeBy = summarizeBy
    }

    init(column: ModelMetadata.Column) {
        let family: Family
        switch column.dataType {
        case .int64, .double, .decimal: family = .numeric
        case .string: family = .text
        case .dateTime: family = .date
        case .boolean: family = .boolean
        default: family = .other
        }
        self.init(kind: .column, entity: column.tableName, property: column.name, family: family, summarizeBy: column.summarizeBy)
    }

    init(measure: ModelMetadata.Measure) {
        self.init(kind: .measure, entity: measure.tableName, property: measure.name)
    }
}

// MARK: - Kéo thả (NSItemProvider, văn bản JSON: chạy ổn trong cửa sổ có nhiều lớp SwiftUI/AppKit)

extension FieldRef {
    static let dragPrefix = "bipro-field:"

    /// Chuỗi kéo thả: tiền tố cố định rồi JSON. Văn bản không có tiền tố thì không phải trường của BI Pro.
    var dragString: String {
        guard let data = try? JSONEncoder().encode(self) else { return Self.dragPrefix }
        return Self.dragPrefix + String(decoding: data, as: UTF8.self)
    }

    init?(dragString: String) {
        guard dragString.hasPrefix(Self.dragPrefix),
              let field = try? JSONDecoder().decode(FieldRef.self, from: Data(dragString.dropFirst(Self.dragPrefix.count).utf8))
        else { return nil }
        self = field
    }

    var itemProvider: NSItemProvider { NSItemProvider(object: dragString as NSString) }
}

/// Cái được thả vào Build pane: trường từ pane Dữ liệu, hoặc một trường đang nằm trong một ô (đổi thứ tự, chuyển ô).
enum BuildDrop {
    case field(FieldRef)
    case well(role: String, index: Int)

    static let wellPrefix = "bipro-well:"

    static func wellString(role: String, index: Int) -> String { "\(wellPrefix)\(index):\(role)" }

    init?(string: String) {
        if let field = FieldRef(dragString: string) { self = .field(field); return }
        guard string.hasPrefix(Self.wellPrefix) else { return nil }
        let rest = string.dropFirst(Self.wellPrefix.count)
        guard let colon = rest.firstIndex(of: ":"), let index = Int(rest[..<colon]) else { return nil }
        self = .well(role: String(rest[rest.index(after: colon)...]), index: index)
    }

    /// Đọc các mục được thả (bất đồng bộ), chỉ giữ mục hợp lệ của BI Pro.
    static func load(from providers: [NSItemProvider], completion: @escaping ([BuildDrop]) -> Void) {
        var result: [BuildDrop] = []
        let group = DispatchGroup()
        for provider in providers where provider.canLoadObject(ofClass: NSString.self) {
            group.enter()
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                if let text = object as? String, let drop = BuildDrop(string: text) { result.append(drop) }
                group.leave()
            }
        }
        group.notify(queue: .main) { completion(result) }
    }
}
