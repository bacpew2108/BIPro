// Wave 4A (T006): Hộp "Xem dữ liệu" (Show as a table) hiển thị bảng số liệu đã tính của visual đang chọn kèm Export CSV nhanh.
import PBIXKit
import SwiftUI

struct VisualDataTableSheet: View {
    let visual: ReportVisual
    let view: DataView
    let onExportCSV: () -> Void
    let onClose: () -> Void

    private var tableData: (headers: [String], rows: [[String]])? {
        try? VisualCSVExporter.tabularRows(from: view)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "tablecells")
                    .font(.system(size: 18))
                    .foregroundStyle(DS.Palette.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(VisualCatalog.displayTitle(visual))
                        .font(DS.Typeface.headlineMedium)
                        .foregroundStyle(DS.Palette.label)
                    if let tableData {
                        Text(bi("\(tableData.rows.count) dòng · \(tableData.headers.count) cột",
                                "\(tableData.rows.count) rows · \(tableData.headers.count) columns"))
                            .font(DS.Typeface.labelSmall)
                            .foregroundStyle(DS.Palette.secondaryLabel)
                    }
                }
                Spacer()
                Button {
                    onExportCSV()
                } label: {
                    Label(bi("Xuất CSV…", "Export CSV…"), systemImage: "square.and.arrow.up")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(tableData == nil)

                Button(bi("Đóng", "Close")) { onClose() }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }

            if let data = tableData, !data.headers.isEmpty {
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 0) {
                            ForEach(Array(data.headers.enumerated()), id: \.offset) { _, h in
                                Text(h)
                                    .font(DS.Typeface.bodySmall.weight(.semibold))
                                    .foregroundStyle(DS.Palette.label)
                                    .lineLimit(1)
                                    .frame(minWidth: 130, maxWidth: 220, alignment: .leading)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(DS.Palette.chrome)
                            }
                        }
                        Divider()
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(data.rows.prefix(1000).enumerated()), id: \.offset) { rIdx, row in
                                HStack(spacing: 0) {
                                    ForEach(Array(data.headers.indices), id: \.self) { cIdx in
                                        let cell = cIdx < row.count ? row[cIdx] : ""
                                        Text(cell)
                                            .font(DS.Typeface.mono)
                                            .foregroundStyle(DS.Palette.label)
                                            .lineLimit(1)
                                            .frame(minWidth: 130, maxWidth: 220, alignment: .leading)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                    }
                                }
                                .background(rIdx.isMultiple(of: 2) ? DS.Palette.canvas : DS.Palette.chrome.opacity(0.45))
                            }
                        }
                    }
                }
                .background(DS.Palette.canvas)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DS.Palette.separator))
                if data.rows.count > 1000 {
                    Text(bi("Đang hiển thị 1.000 dòng đầu tiên. Dùng \"Xuất CSV…\" để tải toàn bộ \(data.rows.count) dòng.",
                            "Showing first 1,000 rows. Use \"Export CSV…\" to export all \(data.rows.count) rows."))
                        .font(DS.Typeface.labelSmall)
                        .foregroundStyle(DS.Palette.secondaryLabel)
                }
            } else {
                ContentUnavailableView(
                    bi("Chưa có dữ liệu bảng", "No tabular data"),
                    systemImage: "tablecells",
                    description: Text(bi("Visual này không có dữ liệu số liệu hoặc đang tải.", "This visual has no tabular data or is still loading."))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
        .frame(minWidth: 700, idealWidth: 860, minHeight: 460, idealHeight: 560)
        .background(DS.Palette.canvas)
    }
}
