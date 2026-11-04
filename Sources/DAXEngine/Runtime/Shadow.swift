// Shadow filter context cho ALLSELECTED (FC, đợt 2), architecture.md §4.5.
//
// Mỗi iterator đẩy một khung là ngữ cảnh lúc bắt đầu lặp. ALLSELECTED đọc khung gần nhất có lọc cột đó.
// `FilterContext.pushingShadow()` lo việc bỏ shadow của khung trước khi đẩy, nên các khung không lồng nhau.
import ColumnStore

/// Ngăn xếp shadow. `frames` đi từ ngoài vào trong; khung cuối là gần nhất.
public struct ShadowStack: Sendable, Hashable {
    /// Mỗi khung là ngữ cảnh không kèm shadow (để tránh lồng vô hạn).
    public private(set) var frames: [FilterContext]
    /// Băm các khung, tính một lần khi dựng. `FilterContext.fingerprint` được gọi hàng trăm nghìn lần trong một truy vấn,
    /// còn các khung shadow (mỗi khung là cả một ngữ cảnh) thì không đổi, nên không băm lại từng lần.
    private var digest: Int

    public init(frames: [FilterContext] = []) {
        self.frames = frames
        self.digest = ShadowStack.digest(of: frames)
    }

    private static func digest(of frames: [FilterContext]) -> Int {
        var hasher = Hasher()
        for frame in frames { frame.hash(into: &hasher) }
        return hasher.finalize()
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(digest)
    }

    public static func == (lhs: ShadowStack, rhs: ShadowStack) -> Bool {
        lhs.digest == rhs.digest && lhs.frames == rhs.frames
    }

    public var isEmpty: Bool { frames.isEmpty }

    /// Ngăn xếp mới với `frame` đặt lên trên. Người gọi phải đảm bảo `frame` không có shadow.
    public func pushing(_ frame: FilterContext) -> ShadowStack {
        ShadowStack(frames: frames + [frame])
    }

    /// Ngăn xếp mới bỏ khung trên cùng.
    public func popping() -> ShadowStack {
        ShadowStack(frames: Array(frames.dropLast()))
    }

    /// Mục cột của khung gần nhất có lọc `column`. `nil` nếu không khung nào lọc cột đó.
    public func nearestItem(on column: ColumnID) -> FilterItem? {
        for frame in frames.reversed() {
            if let item = frame.items.first(where: { $0.column == column }) {
                return item
            }
        }
        return nil
    }

    /// Bộ lọc bảng của khung gần nhất trên `table`. `nil` nếu không có.
    public func nearestRowFilter(on table: TableID) -> RowsFilter? {
        for frame in frames.reversed() {
            if let filter = frame.rowFilters.first(where: { $0.table == table }) {
                return filter
            }
        }
        return nil
    }

    /// Hợp các cột có mục lọc trong mọi khung, theo thứ tự xuất hiện (dùng cho ALLSELECTED()).
    public func columnsWithFilters() -> [ColumnID] {
        var seen = Set<ColumnID>()
        var out: [ColumnID] = []
        for frame in frames {
            for item in frame.items where seen.insert(item.column).inserted {
                out.append(item.column)
            }
        }
        return out
    }

    /// Hợp các bảng có bộ lọc bảng trong mọi khung, theo thứ tự xuất hiện (dùng cho ALLSELECTED()).
    public func tablesWithRowFilters() -> [TableID] {
        var seen = Set<TableID>()
        var out: [TableID] = []
        for frame in frames {
            for filter in frame.rowFilters where seen.insert(filter.table).inserted {
                out.append(filter.table)
            }
        }
        return out
    }
}
