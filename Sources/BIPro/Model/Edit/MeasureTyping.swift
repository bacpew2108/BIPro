import DAXEngine
import Foundation
import PBIXKit

struct MeasureTypeInfo: Equatable {
    var dataType: ModelMetadata.DataType
    var formatString: String?
    /// Giá trị của biểu thức ngoài mọi bộ lọc, để hiện xem thử.
    var value: Value
}

struct MeasureProblem: Equatable {
    var message: String
    /// Vị trí trong biểu thức (dòng, cột đếm từ 1), nếu biết.
    var line: Int?
    var column: Int?
}

enum MeasureCheck: Equatable {
    case ok(MeasureTypeInfo)
    case failed(MeasureProblem)
}

/// Phase E (R3): kiểm và suy kiểu measure bằng cách chạy `EVALUATE ROW("x", biểu thức)` qua engine.
enum MeasureTyping {
    private static let prefix = "EVALUATE ROW(\"x\", "

    /// Kiểu và định dạng mặc định theo kết quả, như Desktop ghi (VM-E1, VM-E2): số nguyên → Int64 `'0'`; chuỗi → String không
    /// định dạng; logic → Boolean `"TRUE";"TRUE";"FALSE"`; ngày giờ → DateTime `General Date`; số thực → Double không định dạng; `BLANK()` → Int64 `'0'`. Kiểu chưa quan sát để trống định dạng thay
    /// vì đoán.
    static func info(for value: Value) -> (dataType: ModelMetadata.DataType, formatString: String?) {
        switch value {
        case .integer: (.int64, "0")
        case .double: (.double, nil)
        case .currency: (.decimal, nil)
        case .string: (.string, nil)
        case .boolean: (.boolean, "\"TRUE\";\"TRUE\";\"FALSE\"")
        case .dateTime: (.dateTime, "General Date")
        case .blank: (.int64, "0")   // VM-E2: Desktop ghi DataType 6, FormatString '0' cho BLANK()
        }
    }

    static func check(_ expression: String, using engine: DAXEngine) async -> MeasureCheck {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failed(MeasureProblem(message: "Biểu thức đang trống")) }
        do {
            let result = try await engine.execute("\(prefix)\(trimmed))")
            guard let value = result.tables.first?.rows.first?.first else {
                return .failed(MeasureProblem(message: "Biểu thức không trả về giá trị"))
            }
            let info = info(for: value)
            return .ok(MeasureTypeInfo(dataType: info.dataType, formatString: info.formatString, value: value))
        } catch let error as DAXError {
            return .failed(problem(from: error, expression: expression, trimmed: trimmed))
        } catch {
            return .failed(MeasureProblem(message: "\(error)"))
        }
    }

    /// Vị trí lỗi nằm trong văn bản đã ghép tiền tố một dòng; trừ tiền tố và khoảng trắng đầu để về vị trí trong biểu thức gốc.
    private static func problem(from error: DAXError, expression: String, trimmed: String) -> MeasureProblem {
        guard let range = error.range else { return MeasureProblem(message: error.message) }
        let leading = expression.count - expression.drop(while: { $0.isWhitespace || $0.isNewline }).count
        let line = range.line
        var column = range.column
        if line == 1 { column = max(1, column - prefix.count) }
        if leading > 0, line == 1 { column += leading }
        _ = trimmed
        return MeasureProblem(message: error.message, line: line, column: column)
    }
}
