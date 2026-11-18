// Đợt tồn đọng sau Phase F, T029: màn "Thêm dữ liệu vào báo cáo" trên khung trống của tài liệu mới (VM-F11a, ảnh a3, a11–a14):
// bốn ô và liên kết nguồn khác; Excel mở chọn tệp Excel, "Dán dữ liệu vào bảng trống" mở hộp Tạo bảng, nguồn khác mở Get Data;
// SQL Server và dữ liệu mẫu hiện xám kèm lý do; màn biến mất khi có bảng đầu tiên.
import Connectors
import Foundation
import Testing
@testable import BIPro

@Suite("Đợt F2: màn thêm dữ liệu", .serialized) @MainActor struct AddDataPanelTests {
    private func newDocument() throws -> (DocumentState, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("adddata-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = try UntitledDocuments.create(root: root)
        return (DocumentState(workspace: try Workspace(data: Data(contentsOf: url)), fileName: url.lastPathComponent, fileURL: url), root)
    }

    @Test func hienODungNhuDesktop() throws {
        let (state, root) = try newDocument(); defer { try? FileManager.default.removeItem(at: root) }
        #expect(AddDataPanel.isShown(for: state))
        #expect(AddDataPanel.tiles.map(\.title) == ["Nhập dữ liệu từ Excel", "Nhập dữ liệu từ SQL Server", "Dán dữ liệu vào bảng trống",
                                                    "Dùng dữ liệu mẫu"])
        #expect(AddDataPanel.tiles.filter { $0.disabledReason != nil }.map(\.action) == [.sqlServer, .sample])
    }

    @Test func bamOMoDungHopThoai() throws {
        let (state, root) = try newDocument(); defer { try? FileManager.default.removeItem(at: root) }
        AddDataPanel.perform(.paste, on: state)
        #expect(state.enterData?.name == "Table")
        state.closeEnterData()
        AddDataPanel.perform(.otherSource, on: state)
        #expect(state.getDataState != nil)
        state.closeGetData()
        AddDataPanel.perform(.sqlServer, on: state)   // xám: không mở gì
        #expect(state.getDataState == nil && state.enterData == nil)
        var picked: SourceKind?
        AddDataPanel.perform(.excel, on: state, pickFile: { kind in picked = kind; return nil })
        #expect(picked == .excel)
        #expect(state.getDataState == nil)   // huỷ chọn tệp thì không mở gì
    }

    @Test func bienMatKhiCoBangDauTien() async throws {
        let (state, root) = try newDocument(); defer { try? FileManager.default.removeItem(at: root) }
        state.showEnterData()
        #expect(await state.loadEnterData(try #require(state.enterData)) == nil)
        #expect(!AddDataPanel.isShown(for: state))
        state.layout.undo()
        #expect(AddDataPanel.isShown(for: state))
    }

    /// T038: có bảng mà trang chưa có visual thì giữa khung là gợi ý "Dựng visual từ dữ liệu" (Desktop: "Build visuals with your
    /// data", ảnh a6), không có nút; có visual đầu tiên thì gợi ý biến mất.
    @Test func goiYDungVisualKhiCoBangMaTrangTrong() async throws {
        let (state, root) = try newDocument(); defer { try? FileManager.default.removeItem(at: root) }
        #expect(!CanvasHint.isShown(for: state))   // chưa có bảng: màn thêm dữ liệu
        state.showEnterData()
        try state.enterData?.paste("k\n1")
        #expect(await state.loadEnterData(try #require(state.enterData)) == nil)
        #expect(CanvasHint.isShown(for: state))
        #expect(state.layout.insertVisual(type: "clusteredColumnChart", visibleRect: nil) != nil, "\(state.layout.fieldRefusal ?? "")")
        #expect(!CanvasHint.isShown(for: state))
    }
}
