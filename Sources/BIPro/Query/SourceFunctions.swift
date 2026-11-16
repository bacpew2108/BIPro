// Phase F (T063): hàm nguồn của M cho truy vấn đọc từ file: `File.Contents`, `Csv.Document`, `Excel.Workbook`. Gắn vào `MEnvironment.bindings`
// (kiểm trước thư viện) để "Refresh" nạp lại dữ liệu thật từ tệp nguồn và để truy vấn tắt Enable load xem trước được.
//
// - `File.Contents(path)` trả đường dẫn (text) sau khi kiểm tệp có tồn tại; không có kiểu nhị phân trong M của BI Pro. Tệp mất, đổi chỗ hoặc
//   nằm trên máy khác (đường dẫn Windows của file Desktop) thì báo `DataSource.Error` tiếng Việt kèm đường dẫn.
// - `Csv.Document(path, [Delimiter, Encoding, …])`: mọi cột là text tên `Column1…` (Desktop; bước "Promoted Headers" và "Changed Type" lo phần còn lại).
// - `Excel.Workbook(path, useHeaders, _)`: bảng `Name, Data, Item, Kind, Hidden`; `Data` là bảng lồng của từng trang tính/bảng đặt tên, đọc đủ
//   mọi mục một lần ([SUY ĐOÁN] ô lẫn kiểu thành text vì `TableData` chưa có cột `any`).
// SQLite và JSON chưa nối (báo "Chưa hỗ trợ").

import ColumnStore
import Connectors
import Foundation
import MEngine

enum SourceFunctions {
    /// Hàm nguồn dạng giá trị M, để gộp vào `MEnvironment.bindings`.
    static var bindings: [String: MValue] {
        [fileContents.name: .function(fileContents), csvDocument.name: .function(csvDocument), excelWorkbook.name: .function(excelWorkbook)]
    }

    // MARK: File.Contents

    static let fileContents = MFunction(name: "File.Contents", parameters: [MParameter(name: "path"), MParameter(name: "options", isOptional: true)], observed: false) { args in
        guard case .text(let path) = args[0] else { throw MError.expression("File.Contents: đường dẫn phải là text") }
        guard FileManager.default.fileExists(atPath: path) else {
            throw MError(reason: "DataSource.Error",
                         message: "Không tìm thấy tệp nguồn \"\(path)\". Tệp có thể đã bị xoá, đổi tên hoặc nằm trên máy khác.", detail: path)
        }
        return .text(path)
    }

    // MARK: Csv.Document

    static let csvDocument = MFunction(name: "Csv.Document", parameters: [MParameter(name: "source"), MParameter(name: "options", isOptional: true)], observed: false) { args in
        guard case .text(let path) = args[0] else { throw MError.expression("Csv.Document: nguồn phải là kết quả của File.Contents") }
        var delimiter: Character?
        var encoding: String.Encoding?
        if case .record(let fields) = args[1] {
            for field in fields {
                switch (field.name, field.value) {
                case ("Delimiter", .text(let s)): delimiter = s.first
                case ("Encoding", .number(let n)): encoding = stringEncoding(codePage: Int(n))
                default: break
                }
            }
        }
        let options = CSVSource.Options(delimiter: delimiter, encoding: encoding, promoteHeaders: false, detectTypes: false)
        let table = try blocking {
            let source = CSVSource(url: URL(fileURLWithPath: path), options: options)
            guard let item = try await source.items().first else { throw SourceError.empty }
            return try await item.load(progress: nil)
        }
        return .table(table)
    }

    /// Mã trang → `String.Encoding` (65001 UTF-8, 1200 UTF-16, 1252 Windows-1252, 28591 Latin-1, 20127 ASCII); khác thì tự dò.
    private static func stringEncoding(codePage: Int) -> String.Encoding? {
        switch codePage {
        case 65001: .utf8
        case 1200: .utf16LittleEndian
        case 1201: .utf16BigEndian
        case 1252: .windowsCP1252
        case 28591: .isoLatin1
        case 20127: .ascii
        default: nil
        }
    }

    // MARK: Excel.Workbook

    static let excelWorkbook = MFunction(
        name: "Excel.Workbook", parameters: [MParameter(name: "workbook"), MParameter(name: "useHeaders", isOptional: true), MParameter(name: "delayTypes", isOptional: true)],
        observed: false
    ) { args in
        guard case .text(let path) = args[0] else { throw MError.expression("Excel.Workbook: nguồn phải là kết quả của File.Contents") }
        let useHeaders: Bool
        if case .logical(let flag) = args[1] { useHeaders = flag } else { useHeaders = false }
        let loaded: [(name: String, kind: String, data: TableData)] = try blocking {
            let source = ExcelSource(url: URL(fileURLWithPath: path), options: .init(promoteHeaders: useHeaders, detectTypes: true))
            var out: [(String, String, TableData)] = []
            for item in try await source.items() {
                let data: TableData
                do { data = try await item.load(progress: nil) } catch SourceError.empty { data = try TableData(columns: []) }
                out.append((item.name, item.kind == .namedTable ? "Table" : "Sheet", data))
            }
            return out
        }
        // Cột: Name, Data (bảng lồng), Item, Kind, Hidden (như Desktop).
        let names = loaded.map(\.name)
        let columns = [
            TableColumn(name: "Name", data: ColumnBuilder.strings(names)),
            TableColumn(name: "Data", data: ColumnBuilder.strings(Array(repeating: nil, count: loaded.count))),
            TableColumn(name: "Item", data: ColumnBuilder.strings(names)),
            TableColumn(name: "Kind", data: ColumnBuilder.strings(loaded.map(\.kind))),
            TableColumn(name: "Hidden", data: ColumnBuilder.booleans(Array(repeating: false, count: loaded.count))),
        ]
        return .table(try TableData(columns: columns, nested: [1: loaded.map(\.data)]))
    }

    // MARK: Cầu nối đồng bộ

    private final class Box<T: Sendable>: @unchecked Sendable {
        var result: Result<T, Error>?
    }

    /// Chạy việc bất đồng bộ của Connectors ngay trong hàm M đồng bộ. Hàm M chạy ngoài luồng chính (bộ chạy M là `async` không gắn `MainActor`),
    /// việc đọc tệp ở một Task riêng nên không tự chờ chính nó.
    private static func blocking<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) throws -> T {
        let box = Box<T>()
        let done = DispatchSemaphore(value: 0)
        Task.detached(priority: .userInitiated) {
            do { box.result = .success(try await work()) } catch { box.result = .failure(error) }
            done.signal()
        }
        done.wait()
        do { return try box.result!.get() } catch let error as SourceError {
            throw MError(reason: "DataSource.Error", message: message(for: error))
        }
    }

    private static func message(for error: SourceError) -> String {
        switch error {
        case .unreadable(let text), .encoding(let text), .unsupported(let text): text
        case .empty: "Nguồn không có dữ liệu."
        case .cancelled: "Đã huỷ."
        }
    }
}
