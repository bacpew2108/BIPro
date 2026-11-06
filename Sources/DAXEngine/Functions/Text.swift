// Hàm chuỗi (F-KIT, đợt 2). FORMAT theo culture của model (en-US cho Nhom6).
// Mẫu cần có: 0.0%, 0%, 0.0, #,0.0, $#,0.0 và 19 dynamic format string.
// FORMAT dùng FormatString.format của VAL; mẫu ngày chưa được VAL hỗ trợ nên báo lỗi .runtime của VAL.

import Foundation

public enum TextFunctions: FunctionFamily {
    public static let functions: [FunctionSpec] = [
        FunctionSpec(name: "FORMAT",
                     params: [.scalar("value"), .scalar("format_string", optional: true),
                              .scalar("locale", optional: true)],
                     impl: .scalar(TextFunctions.formatBody)),
        FunctionSpec(name: "CONTAINSSTRING", params: [.scalar("within_text"), .scalar("find_text")],
                     impl: .scalar(TextFunctions.containsStringBody)),
        FunctionSpec(name: "CONTAINSSTRINGEXACT", params: [.scalar("within_text"), .scalar("find_text")],
                     impl: .scalar(TextFunctions.containsStringExactBody)),
        FunctionSpec(name: "LEFT", params: [.scalar("text"), .scalar("num_chars", optional: true)],
                     impl: .scalar(TextFunctions.leftBody)),
    ]

    /// CONTAINSSTRING(within, find): không phân biệt hoa thường; `find` rỗng thì TRUE; BLANK coi là "".
    /// [SUY ĐOÁN] So khớp theo en-US như `=`; chưa đối chiếu Power BI với dấu thanh.
    static func containsStringBody(_ frame: CallFrame) throws(DAXError) -> Value {
        let within = try frame.scalar(0).asText(), find = try frame.scalar(1).asText()
        return .boolean(find.isEmpty || within.range(of: find, options: [.caseInsensitive], locale: Locale(identifier: "en_US")) != nil)
    }

    static func containsStringExactBody(_ frame: CallFrame) throws(DAXError) -> Value {
        let within = try frame.scalar(0).asText(), find = try frame.scalar(1).asText()
        return .boolean(find.isEmpty || within.contains(find))
    }

    /// LEFT(text[, n]): n mặc định 1; n < 0 là lỗi.
    static func leftBody(_ frame: CallFrame) throws(DAXError) -> Value {
        let text = try frame.scalar(0).asText()
        var count = 1
        if !frame.isBlankArgument(1) {
            let n = try frame.scalar(1).asDouble()
            if n < 0 { throw DAXError(.runtime, "LEFT: num_chars phải lớn hơn hoặc bằng 0") }
            count = Int(n)
        }
        return .string(String(text.prefix(count)))
    }

    /// FORMAT(value[, format_string[, locale]]). Thiếu mẫu thì dùng dạng chuỗi mặc định của giá trị.
    /// Thiếu locale thì dùng en-US, culture của model Nhom6 [FACT].
    static func formatBody(_ frame: CallFrame) throws(DAXError) -> Value {
        let giaTri = try frame.scalar(0)
        var mau = ""
        if !frame.isBlankArgument(1) {
            mau = try frame.scalar(1).asText()
        }
        var culture = "en-US"
        if !frame.isBlankArgument(2) {
            culture = try frame.scalar(2).asText()
        }
        return .string(try FormatString.format(giaTri, pattern: mau, culture: culture))
    }
}
