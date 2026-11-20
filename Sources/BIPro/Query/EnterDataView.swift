// Đợt tồn đọng sau Phase F, T028: hộp "Tạo bảng" như "Create Table" của Desktop 2.159 (VM-F11a, ảnh a4, a5, a7, a9, a10 ở
// docs/phase-f2-evidence/vm-f11/). Lưới sửa được, dán từ bảng tính (⌘V hoặc nút "Dán"), băng "Bỏ tiêu đề" sau khi dòng đầu thành tiêu đề,
// ô Tên, Tải / Huỷ (hỏi xác nhận khi đã có dữ liệu). Chế độ sửa (bánh răng bước Source trong Query Editor): không có ô Tên, nút OK / Huỷ.

import AppKit
import SwiftUI

struct EnterDataView: View {
    enum Mode { case create, edit }

    @State var table: EnterDataTable
    var mode: Mode = .create
    /// Lưới lúc mở hộp: Huỷ chỉ hỏi xác nhận khi lưới đã khác (Desktop hỏi khi lưới có dữ liệu, VM-F11a ảnh a9).
    private let initial: EnterDataTable
    /// Tải (tạo) hoặc OK (sửa): trả lý do bị từ chối để hiện trong hộp, nil thì hộp đóng.
    var onCommit: (EnterDataTable) async -> String?
    var onCancel: () -> Void

    @State private var promotedBanner = false
    @State private var message: String?
    @State private var confirmCancel = false
    @State private var working = false

    init(table: EnterDataTable, mode: Mode = .create, onCommit: @escaping (EnterDataTable) async -> String?, onCancel: @escaping () -> Void) {
        _table = State(initialValue: table)
        initial = table
        self.mode = mode
        self.onCommit = onCommit
        self.onCancel = onCancel
    }

    private let cellWidth: CGFloat = 140
    private let indexWidth: CGFloat = 36

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tạo bảng").font(DS.Typeface.headlineMedium)
            if promotedBanner { banner }
            if let message { errorBanner(message) }
            grid
            if mode == .create {
                HStack(spacing: 8) {
                    Text("Tên:").font(DS.Typeface.body)
                    TextField("", text: $table.name).textFieldStyle(.roundedBorder).frame(width: 240)
                }
            }
            footer
        }
        .padding(24)
        .frame(width: 760, height: 560)
        .background(DS.Palette.canvas)
        .confirmationDialog("Bạn có chắc muốn thoát? Thay đổi trong bảng sẽ mất.", isPresented: $confirmCancel) {
            Button("Có", role: .destructive) { onCancel() }
            Button("Không", role: .cancel) {}
        }
    }

    // MARK: Băng thông báo

    private var banner: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill").foregroundStyle(DS.Palette.accent)
            Text("Dòng đầu của dữ liệu vừa dán đã thành tiêu đề cột.").font(DS.Typeface.body)
            Button("Bỏ tiêu đề") {
                table.demoteHeaders()
                promotedBanner = false
            }
            .buttonStyle(SecondaryButtonStyle())
            Spacer()
            Button { promotedBanner = false } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
        }
        .padding(8)
        .background(DS.Palette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(DS.Palette.danger)
            Text(text).font(DS.Typeface.body).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button { message = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
        }
        .padding(8)
        .background(DS.Palette.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: Lưới

    private var grid: some View {
        GeometryReader { proxy in
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section(header: headerRow) {
                    ForEach(table.rows.indices, id: \.self) { row in dataRow(row) }
                    HStack(spacing: 0) {
                        Button { table.addRow() } label: { Image(systemName: "plus").frame(width: indexWidth, height: 22) }
                            .buttonStyle(.plain)
                            .help("Thêm dòng")
                        Spacer(minLength: 0)
                    }
                }
            }
            // Lưới nhỏ hơn khung thì nằm góc trên trái như Desktop (ScrollView hai chiều mặc định canh giữa).
            .frame(minWidth: proxy.size.width, minHeight: proxy.size.height, alignment: .topLeading)
        }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Palette.chrome)
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(DS.Palette.separator))
        .onPasteCommand(of: [.plainText, .utf8PlainText], perform: { _ in pasteFromClipboard() })
        .contextMenu { Button("Dán") { pasteFromClipboard() } }
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: indexWidth, height: 24)
            ForEach(table.columns.indices, id: \.self) { column in
                TextField("", text: Binding(get: { table.columns[column] }, set: { edit($0, row: nil, column: column) }))
                    .textFieldStyle(.plain)
                    .font(DS.Typeface.headlineSmall)
                    .padding(.horizontal, 6)
                    .frame(width: cellWidth, height: 24, alignment: .leading)
                    .background(DS.Palette.separator.opacity(0.35))
                    .border(DS.Palette.separator, width: 0.5)
                    .contextMenu {
                        Button("Xoá cột") { table.removeColumn(column) }.disabled(table.columns.count == 1)
                    }
            }
            Button { table.addColumn() } label: { Image(systemName: "plus").frame(width: 28, height: 24) }
                .buttonStyle(.plain)
                .help("Thêm cột")
        }
        .background(DS.Palette.canvas)
    }

    private func dataRow(_ row: Int) -> some View {
        HStack(spacing: 0) {
            Text("\(row + 1)")
                .font(DS.Typeface.labelSmall)
                .foregroundStyle(DS.Palette.secondaryLabel)
                .frame(width: indexWidth, height: 22)
                .contextMenu { Button("Xoá dòng") { table.removeRow(row) } }
            ForEach(table.columns.indices, id: \.self) { column in
                TextField("", text: Binding(get: { table.rows.indices.contains(row) ? table.rows[row][column] : "" },
                                            set: { edit($0, row: row, column: column) }))
                    .textFieldStyle(.plain)
                    .font(DS.Typeface.body)
                    .padding(.horizontal, 6)
                    .frame(width: cellWidth, height: 22, alignment: .leading)
                    .background(DS.Palette.canvas)
                    .border(DS.Palette.separator, width: 0.5)
            }
        }
    }

    /// Ô vừa nhận chữ: khối nhiều ô (⌘V khi đang sửa ô) thì dán vào lưới từ ô đó và thôi sửa ô, để lưới vẽ lại; còn lại ghi vào ô.
    private func edit(_ value: String, row: Int?, column: Int) {
        guard EnterDataTable.isMultiCell(value) else {
            if let row { table.set(row: row, column: column, to: value) } else { table.renameColumn(column, to: value) }
            return
        }
        // Ô nhận "chữ cũ + khối dán": lấy khối từ clipboard khi có, không thì dùng cả chuỗi.
        let clipboard = NSPasteboard.general.string(forType: .string)
        let text = clipboard.map { value.contains($0) } == true ? clipboard! : value
        NSApp.keyWindow?.makeFirstResponder(nil)
        do {
            promotedBanner = try table.pasteIntoCell(text, row: row, column: column) || promotedBanner
            message = nil
        } catch {
            message = error.message
        }
    }

    private func pasteFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        do {
            promotedBanner = try table.paste(text)
            message = nil
        } catch {
            message = error.message
        }
    }

    // MARK: Nút

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Dán") { pasteFromClipboard() }.buttonStyle(SecondaryButtonStyle())
            if working { ProgressView().controlSize(.small) }
            Spacer()
            Button(mode == .create ? "Tải" : "OK") {
                working = true
                Task {
                    message = await onCommit(table)
                    working = false
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
            .disabled(working || (mode == .create && table.name.trimmingCharacters(in: .whitespaces).isEmpty))
            Button("Huỷ") {
                if table.isEmpty || table == initial { onCancel() } else { confirmCancel = true }
            }
            .buttonStyle(SecondaryButtonStyle())
            .keyboardShortcut(.cancelAction)
        }
    }
}
