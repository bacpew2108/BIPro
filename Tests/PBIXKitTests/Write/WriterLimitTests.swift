// Phase F, T028: giới hạn của bộ ghi T3: báo lỗi tiếng Việt, rõ nguyên nhân, không ghi nửa chừng (FR-051).
import Foundation
import Testing
@testable import PBIXKit

@Suite struct WriterLimitTests {
    private func message(_ body: () throws -> Void) -> String {
        do { try body(); return "" } catch let error as WriteError { return error.description } catch { return "\(error)" }
    }

    private func encode(named name: String = "T", _ columns: [VertiPaqWriter.ColumnInput]) throws {
        _ = try VertiPaqWriter.encodeTable(name: name, tableID: 1001, partitionID: 1002, rowNumberID: 1003, columns: columns)
    }

    @Test func bangVuotMotDoanDuLieuBiTuChoi() {
        // 8 388 609 dòng: không dựng cả bảng thật, chỉ cần đủ dòng để vượt giới hạn.
        let rows = VertiPaqWriter.maxRowsPerSegment + 1
        let text = message { try encode([.init(id: 1004, name: "A", values: .int64([Int64?](repeating: 1, count: rows)))]) }
        #expect(text.contains("vượt giới hạn") && text.contains("«T»"), Comment(rawValue: text))
    }

    @Test func tenCotTrungKhongPhanBietHoaThuong() {
        let text = message { try encode([.init(id: 1004, name: "Doanh Thu", values: .int64([1])), .init(id: 1005, name: "doanh thu", values: .int64([2]))]) }
        #expect(text.contains("trùng tên") && text.contains("không phân biệt hoa thường"), Comment(rawValue: text))
    }

    @Test func kyTuNulBiTuChoiOTenVaGiaTri() {
        #expect(message { try encode(named: "T\0x", [.init(id: 1004, name: "A", values: .int64([1]))]) }.contains("NUL"))
        #expect(message { try encode([.init(id: 1004, name: "A\0", values: .int64([1]))]) }.contains("NUL"))
        #expect(message { try encode([.init(id: 1004, name: "A", values: .string(["ok", "x\0y"]))]) }.contains("NUL"))
    }

    @Test func soKhongPhaiSoBiTuChoi() {
        #expect(message { try encode([.init(id: 1004, name: "A", values: .double([1, .nan]))]) }.contains("NaN"))
    }

    @Test func bangRongVaCotLechDongBiTuChoiTiengViet() {
        #expect(message { try encode([.init(id: 1004, name: "A", values: .int64([]))]) }.contains("không có dòng nào"))
        #expect(message { try encode([]) }.contains("không có cột nào"))
        #expect(message { try encode([.init(id: 1004, name: "A", values: .int64([1, 2])), .init(id: 1005, name: "B", values: .int64([1]))]) }.contains("cần 2"))
    }

    @Test func doRongBitVuot32BiTuChoi() {
        let text = message { _ = try VertiPaqWriter.bitWidthAndClass(for: UInt64(UInt32.max) + 1) }
        #expect(text.contains("tối đa 32"), Comment(rawValue: text))
    }

    /// Qua `PBIXWriter`: bảng lỗi làm cả lần lưu thất bại, không có bảng nào khác lọt vào (tất cả hoặc không).
    @Test(.enabled(if: FileManager.default.fileExists(atPath: DesktopGolden.path.path)))
    func motBangLoiLamCaLanLuuThatBai() throws {
        let good = NewTable(name: "Tot", columns: [NewTableColumn(name: "A", values: .int64([1, 2]))])
        let bad = NewTable(name: "Loi", columns: [NewTableColumn(name: "A", values: .int64([1])), NewTableColumn(name: "a", values: .int64([1]))])
        var changes = PBIXChanges()
        changes.modelEdits.append(.addTable(good))
        changes.modelEdits.append(.addTable(bad))
        do {
            _ = try PBIXWriter.build(source: DesktopGolden.path, changes: changes)
            Issue.record("phải báo lỗi")
        } catch let error as WriteError {
            #expect(error.description.contains("trùng tên"))
        }
    }
}
