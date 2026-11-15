import Foundation
import PBIXKit

/// Phase E (T025): đề xuất quan hệ khi kéo một cột thả lên cột khác ở Model view. Quy tắc dò theo hộp thoại "New relationship"
/// của Desktop (`docs/phase-e-evidence/vm-e3/QUAN-SAT.md`): phía duy nhất là phía một, phía còn lại là phía nhiều (đầu "từ");
/// hướng lọc mặc định một chiều; quan hệ mới giữa hai bảng đã nối hoạt động thì không hoạt động.
struct RelationshipDraft: Equatable {
    struct ColumnRef: Hashable {
        var table: String
        var column: String
    }

    struct Refusal: Error, Equatable {
        var reason: String
    }

    var relationship: NewRelationship
    /// Lời nhắn cho người dùng ở hộp xác nhận (ví dụ vì sao quan hệ không hoạt động).
    var notes: [String]
    /// `true` khi quan hệ buộc không hoạt động (không cho bật).
    var forcedInactive: Bool

    /// `isUnique`: cột có toàn giá trị khác nhau (phía một). Trả `Result` với lý do tiếng Việt khi không tạo được.
    static func propose(model: ModelMetadata, drag: ColumnRef, drop: ColumnRef, isUnique: (ColumnRef) -> Bool) -> Result<RelationshipDraft, Refusal> {
        guard drag.table != drop.table else { return .failure(Refusal(reason: "Hai cột phải ở hai bảng khác nhau.")) }
        guard let a = model.columns.first(where: { $0.tableName == drag.table && $0.name == drag.column && $0.kind != .rowNumber }),
              let b = model.columns.first(where: { $0.tableName == drop.table && $0.name == drop.column && $0.kind != .rowNumber }) else {
            return .failure(Refusal(reason: "Không tìm thấy cột \(drag.table)[\(drag.column)] hoặc \(drop.table)[\(drop.column)]."))
        }
        guard a.kind != .calculated, b.kind != .calculated else {
            return .failure(Refusal(reason: "Cột tính toán chưa dùng làm đầu quan hệ được."))
        }
        guard a.dataType == b.dataType else {
            return .failure(Refusal(reason: "Hai cột khác kiểu dữ liệu (\(a.dataType) và \(b.dataType))."))
        }
        let same = model.relationships.contains {
            Set(["\($0.fromTable)[\($0.fromColumn)]", "\($0.toTable)[\($0.toColumn)]"]) == Set(["\(drag.table)[\(drag.column)]", "\(drop.table)[\(drop.column)]"])
        }
        guard !same else { return .failure(Refusal(reason: "Đã có quan hệ nối đúng hai cột này.")) }

        let aUnique = isUnique(drag), bUnique = isUnique(drop)
        switch (aUnique, bUnique) {
        case (true, true):
            return .failure(Refusal(reason: "Cả hai cột đều có giá trị duy nhất: quan hệ một-một chưa được hỗ trợ."))
        case (false, false):
            return .failure(Refusal(reason: "Cả hai cột đều có giá trị trùng: quan hệ nhiều-nhiều chưa được hỗ trợ. Một phía phải có giá trị duy nhất."))
        default: break
        }
        let many = aUnique ? drop : drag, one = aUnique ? drag : drop

        var notes: [String] = []
        var forcedInactive = false
        let hasActive = model.relationships.contains {
            $0.isActive && Set([$0.fromTable, $0.toTable]) == Set([many.table, one.table])
        }
        if hasActive {
            forcedInactive = true
            notes.append("Đã có quan hệ hoạt động giữa \(many.table) và \(one.table), nên quan hệ mới không hoạt động.")
        } else if Self.connected(model, many.table, one.table) {
            forcedInactive = true
            notes.append("Hai bảng đã nối với nhau qua các quan hệ hoạt động khác; bật thêm quan hệ này tạo đường lọc mơ hồ, nên nó không hoạt động.")
        }
        let relationship = NewRelationship(name: UUID().uuidString.lowercased(), fromTable: many.table, fromColumn: many.column,
                                           toTable: one.table, toColumn: one.column, fromMany: true, toMany: false,
                                           isActive: !forcedInactive, crossFilteringBehavior: 1)
        return .success(RelationshipDraft(relationship: relationship, notes: notes, forcedInactive: forcedInactive))
    }

    /// Hai bảng có nối được với nhau bằng các quan hệ hoạt động (bỏ qua hướng) không.
    private static func connected(_ model: ModelMetadata, _ a: String, _ b: String) -> Bool {
        var adjacency: [String: Set<String>] = [:]
        for r in model.relationships where r.isActive {
            adjacency[r.fromTable, default: []].insert(r.toTable)
            adjacency[r.toTable, default: []].insert(r.fromTable)
        }
        var seen: Set<String> = [a], queue = [a]
        while let t = queue.popLast() {
            if t == b { return true }
            for next in adjacency[t] ?? [] where seen.insert(next).inserted { queue.append(next) }
        }
        return false
    }
}
