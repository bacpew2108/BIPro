import DAXEngine
import PBIXKit
import SwiftUI

/// "Data point table" (Data / Drill ▸ Show): bảng các điểm dữ liệu đang chọn trên visual (như "Show data point as a table" của Desktop):
/// mỗi dòng một điểm chọn, mỗi cột một trường chiều của điểm; kèm các cột số liệu của dòng khớp trong bảng của visual khi tìm được.
struct DataPointTableSheet: View {
    let visual: ReportVisual
    let selection: SelectionState
    let view: DataView?
    let onClose: () -> Void

    /// Cột chiều theo thứ tự `columns` của lựa chọn.
    private var dimensionColumns: [CrossColumn] { selection.columns }

    private func label(_ point: DataPointID) -> String {
        var parts: [String] = []
        for dim in dimensionColumns {
            if let v = point.values[dim.queryRef] { parts.append(UserFilter.display(v)) } else { parts.append("") }
        }
        return parts.joined(separator: "\u{1}")
    }

    private var points: [DataPointID] {
        selection.points.sorted { label($0) < label($1) }
    }

    /// Bảng của visual (nếu đọc được) để lấy số liệu của dòng khớp điểm.
    private var visualTable: (headers: [String], rows: [[String]])? {
        view.flatMap { try? VisualCSVExporter.tabularRows(from: $0) }
    }

    private struct Built { var headers: [String]; var rows: [[String]] }

    private var built: Built {
        let dims = dimensionColumns
        var headers = dims.map { $0.column.column }
        var rows: [[String]] = []
        for point in points {
            var row: [String] = []
            for dim in dims {
                if let v = point.values[dim.queryRef] { row.append(UserFilter.display(v)) } else { row.append("") }
            }
            rows.append(row)
        }
        // Số liệu: ghép với dòng của bảng visual có cùng giá trị chiều. Tìm cột chiều theo tên; không có thì lấy các cột đầu
        // (bảng của biểu đồ liệt kê các cấp danh mục trước, rồi tới số liệu) và chỉ dùng khi ít nhất một điểm khớp được một dòng.
        if let table = visualTable, !rows.isEmpty {
            let named: [Int?] = dims.map { dim in table.headers.firstIndex { $0 == dim.column.column || $0.hasSuffix("[\(dim.column.column)]") } }
            let byName = named.allSatisfy { $0 != nil } ? named.compactMap { $0 } : []
            let candidates: [[Int]] = [byName, Array(0..<min(dims.count, table.headers.count))].filter { !$0.isEmpty }
            for index in candidates {
                let measureColumns = table.headers.indices.filter { !index.contains($0) }
                func match(_ row: [String]) -> [String]? {
                    table.rows.first { tr in zip(index, row).allSatisfy { i, v in tr[i] == v } }
                }
                guard !measureColumns.isEmpty, rows.contains(where: { match($0) != nil }) else { continue }
                headers += measureColumns.map { table.headers[$0] }
                rows = rows.map { row in row + measureColumns.map { match(row)?[$0] ?? "" } }
                break
            }
        }
        return Built(headers: headers, rows: rows)
    }

    var body: some View {
        let table = built
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "tablecells.badge.ellipsis").font(.system(size: 18)).foregroundStyle(DS.Palette.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(bi("Bảng điểm dữ liệu", "Data point table")).font(DS.Typeface.headlineMedium)
                    Text("\(VisualCatalog.displayTitle(visual)) · " + bi("\(table.rows.count) điểm đã chọn", table.rows.count == 1 ? "1 selected point" : "\(table.rows.count) selected points"))
                        .font(DS.Typeface.labelSmall).foregroundStyle(DS.Palette.secondaryLabel).lineLimit(1)
                }
                Spacer()
                Button(bi("Đóng", "Close"), action: onClose).buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.cancelAction)
            }
            if table.rows.isEmpty {
                Text(bi("Chọn một điểm dữ liệu trên visual (bấm vào cột, thanh, lát…) rồi mở lại.",
                        "Select a data point on the visual (click a bar, slice…) and open this again."))
                    .foregroundStyle(DS.Palette.secondaryLabel).padding(24).frame(maxWidth: .infinity)
            } else {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 0) {
                            ForEach(Array(table.headers.enumerated()), id: \.offset) { _, h in cell(h, header: true) }
                        }
                        ForEach(Array(table.rows.enumerated()), id: \.offset) { i, row in
                            HStack(spacing: 0) {
                                ForEach(Array(row.enumerated()), id: \.offset) { _, v in cell(v, header: false) }
                            }
                            .background(i.isMultiple(of: 2) ? Color.clear : DS.Palette.controlFill.opacity(0.4))
                        }
                    }
                }
                .frame(minHeight: 180, maxHeight: 360, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 6).strokeBorder(DS.Palette.separator))
            }
        }
        .padding(20)
        .frame(width: 640)
        .background(DS.Palette.canvas)
    }

    private func cell(_ text: String, header: Bool) -> some View {
        Text(text).font(header ? DS.Typeface.bodySmall.weight(.semibold) : DS.Typeface.bodySmall)
            .foregroundStyle(DS.Palette.label).lineLimit(1)
            .frame(minWidth: 90, maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(header ? DS.Palette.chrome : Color.clear)
    }
}
