// Đợt tồn đọng sau Phase F, T029: màn "Thêm dữ liệu vào báo cáo" như "Add data to your report" của Desktop 2.159 (VM-F11a, ảnh a3,
// a11–a14 ở docs/phase-f2-evidence/vm-f11/): hiện giữa khung trang khi mô hình chưa có bảng người dùng nào, biến mất khi có bảng đầu tiên.
// Bốn ô (Excel, SQL Server, dán vào bảng trống, dữ liệu mẫu) và liên kết "Lấy dữ liệu từ nguồn khác →". BI Pro chưa có SQL Server và
// dữ liệu mẫu nên hai ô đó xám kèm lý do.

import Connectors
import SwiftUI

struct AddDataPanel: View {
    enum Action: Equatable { case excel, sqlServer, paste, sample, otherSource }

    struct Tile {
        let action: Action
        let title: String
        let symbol: String
        let tint: Color
        let disabledReason: String?
    }

    static let tiles: [Tile] = [
        Tile(action: .excel, title: "Nhập dữ liệu từ Excel", symbol: "tablecells", tint: DS.Palette.success, disabledReason: nil),
        Tile(action: .sqlServer, title: "Nhập dữ liệu từ SQL Server", symbol: "server.rack", tint: DS.Palette.accent,
             disabledReason: "BI Pro chưa hỗ trợ SQL Server"),
        Tile(action: .paste, title: "Dán dữ liệu vào bảng trống", symbol: "doc.on.clipboard", tint: DS.Palette.warning, disabledReason: nil),
        Tile(action: .sample, title: "Dùng dữ liệu mẫu", symbol: "cylinder", tint: DS.Palette.paperSecondaryLabel,
             disabledReason: "BI Pro chưa có dữ liệu mẫu"),
    ]

    /// Hiện khi mô hình nạp được bảng mà chưa có bảng người dùng nào.
    static func isShown(for state: DocumentState) -> Bool {
        _ = state.modelVersion   // `workspace` không phát thay đổi; đọc bộ đếm để view vẽ lại khi nạp hay hoàn tác bảng
        return state.getDataBlocker == nil && state.workspace.userTables.isEmpty
    }

    /// Ô Excel mở thẳng hộp chọn tệp Excel (như Desktop); dán mở hộp Tạo bảng; nguồn khác mở Get Data. Ô xám không làm gì.
    static func perform(_ action: Action, on state: DocumentState,
                        pickFile: (SourceKind) -> String? = GetDataFilePicker.pick) {
        switch action {
        case .excel: state.showGetData(kind: .excel, pickFile: pickFile)
        case .paste: state.showEnterData()
        case .otherSource: state.showGetData()
        case .sqlServer, .sample: break
        }
    }

    let state: DocumentState

    var body: some View {
        VStack(spacing: 14) {
            Text(tr(.addDataTitle)).font(.system(size: 22, weight: .semibold)).foregroundStyle(DS.Palette.paperLabel)
            Text(tr(.addDataSubtitle)).font(.system(size: 15)).foregroundStyle(DS.Palette.paperSecondaryLabel)
            HStack(spacing: 14) {
                ForEach(Self.tiles, id: \.title) { tile in tileView(tile) }
            }
            .padding(.top, 8)
            Button(bi("Lấy dữ liệu từ nguồn khác →", "Get data from another source →")) { Self.perform(.otherSource, on: state) }
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DS.Palette.paperLink)
                .padding(.top, 4)
        }
        .padding(28)
    }

    private func tileView(_ tile: Tile) -> some View {
        let enabled = tile.disabledReason == nil
        let displayTitle: String = switch tile.action {
        case .excel: bi(tile.title, "Import data from Excel")
        case .sqlServer: bi(tile.title, "Import data from SQL Server")
        case .paste: bi(tile.title, "Paste data into a blank table")
        case .sample: bi(tile.title, "Try a sample dataset")
        case .otherSource: bi(tile.title, "Get data from another source")
        }
        let displayDisabled: String? = switch tile.action {
        case .sqlServer: tile.disabledReason.map { bi($0, "SQL Server is not yet supported in BI Pro") }
        case .sample: tile.disabledReason.map { bi($0, "Sample dataset is not yet included in BI Pro") }
        default: tile.disabledReason
        }
        return Button { Self.perform(tile.action, on: state) } label: {
            VStack(spacing: 0) {
                Image(systemName: tile.symbol)
                    .font(.system(size: 24))
                    .foregroundStyle(enabled ? tile.tint : DS.Palette.paperTertiaryLabel)
                    .frame(maxWidth: .infinity, minHeight: 74)
                    .background(enabled ? tile.tint.opacity(0.14) : Color.black.opacity(0.04))
                Text(displayTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(enabled ? DS.Palette.paperLabel : DS.Palette.paperTertiaryLabel)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                    .padding(.horizontal, 10)
            }
            .frame(width: 160)
            .background(enabled ? DS.Palette.paperCard : DS.Palette.paperCardDisabled)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(DS.Palette.paperBorder, lineWidth: 1))
            .shadow(color: .black.opacity(enabled ? 0.10 : 0.04), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(displayDisabled ?? displayTitle)
    }
}
