// Hàm chuỗi (F-KIT, đợt 2). FORMAT theo culture của model (en-US cho Nhom6).
// Mẫu cần có: 0.0%, 0%, 0.0, #,0.0, $#,0.0 và 19 dynamic format string.
// FORMAT dùng FormatString.format của VAL; mẫu ngày chưa được VAL hỗ trợ nên báo lỗi .runtime của VAL.

public enum TextFunctions: FunctionFamily {
    public static let functions: [FunctionSpec] = [
        FunctionSpec(name: "FORMAT",
                     params: [.scalar("value"), .scalar("format_string", optional: true),
                              .scalar("locale", optional: true)],
                     impl: .scalar(TextFunctions.formatBody)),
    ]

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
