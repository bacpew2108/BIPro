// Hàm chuỗi (F-KIT, đợt 2; F2-DAXTEXT). FORMAT theo culture của model (en-US cho Nhom6).
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
        FunctionSpec(name: "SEARCH", params: [.scalar("find_text"), .scalar("within_text"), .scalar("start_num", optional: true),
                                              .scalar("not_found_value", optional: true)],
                     impl: .scalar(TextFunctions.searchBody)),
        FunctionSpec(name: "LEFT", params: [.scalar("text"), .scalar("num_chars", optional: true)],
                     impl: .scalar(TextFunctions.leftBody)),
        FunctionSpec(name: "LEN", params: [.scalar("text")],
                     impl: .scalar(TextFunctions.lenBody)),
        FunctionSpec(name: "UPPER", params: [.scalar("text")],
                     impl: .scalar(TextFunctions.upperBody)),
        FunctionSpec(name: "LOWER", params: [.scalar("text")],
                     impl: .scalar(TextFunctions.lowerBody)),
        FunctionSpec(name: "RIGHT", params: [.scalar("text"), .scalar("num_chars", optional: true)],
                     impl: .scalar(TextFunctions.rightBody)),
        FunctionSpec(name: "MID", params: [.scalar("text"), .scalar("start_num"), .scalar("num_chars")],
                     impl: .scalar(TextFunctions.midBody)),
        FunctionSpec(name: "TRIM", params: [.scalar("text")],
                     impl: .scalar(TextFunctions.trimBody)),
        FunctionSpec(name: "SUBSTITUTE", params: [.scalar("text"), .scalar("old_text"), .scalar("new_text"),
                                                  .scalar("instance_num", optional: true)],
                     impl: .scalar(TextFunctions.substituteBody)),
        FunctionSpec(name: "REPLACE", params: [.scalar("old_text"), .scalar("start_num"), .scalar("num_chars"),
                                               .scalar("new_text")],
                     impl: .scalar(TextFunctions.replaceBody)),
        FunctionSpec(name: "CONCATENATE", params: [.scalar("text1"), .scalar("text2")],
                     impl: .scalar(TextFunctions.concatenateBody)),
        FunctionSpec(name: "FIND", params: [.scalar("find_text"), .scalar("within_text"),
                                            .scalar("start_num", optional: true),
                                            .scalar("not_found_value", optional: true)],
                     impl: .scalar(TextFunctions.findBody)),
        FunctionSpec(name: "REPT", params: [.scalar("text"), .scalar("number_times")],
                     impl: .scalar(TextFunctions.reptBody)),
        FunctionSpec(name: "VALUE", params: [.scalar("text")],
                     impl: .scalar(TextFunctions.valueBody)),
        FunctionSpec(name: "EXACT", params: [.scalar("text1"), .scalar("text2")],
                     impl: .scalar(TextFunctions.exactBody)),
        FunctionSpec(name: "UNICHAR", params: [.scalar("number")],
                     impl: .scalar(TextFunctions.unicharBody)),
        FunctionSpec(name: "UNICODE", params: [.scalar("text")],
                     impl: .scalar(TextFunctions.unicodeBody)),
        FunctionSpec(name: "FIXED", params: [.scalar("number"), .scalar("decimals", optional: true),
                                             .scalar("no_commas", optional: true)],
                     impl: .scalar(TextFunctions.fixedBody)),
        FunctionSpec(name: "COMBINEVALUES", params: [.scalar("delimiter"), .scalar("expression", repeats: true)],
                     impl: .scalar(TextFunctions.combinevaluesBody)),
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

    /// SEARCH(find, within[, start[, notFound]]): không phân biệt hoa thường, hiểu `?`, `*` và `~`.
    /// Power BI sinh `SEARCH("x", col, 1, 0) >= 1` cho Advanced filter "contains" (VM C2, A1). Không thấy thì trả `notFound`, thiếu `notFound` là lỗi.
    static func searchBody(_ frame: CallFrame) throws(DAXError) -> Value {
        let findArg = try frame.scalar(0)
        let withinArg = try frame.scalar(1)

        var start = 1
        if !frame.isBlankArgument(2) {
            let sArg = try frame.scalar(2)
            if !sArg.isBlank {
                let sD = try sArg.asDouble()
                start = roundDAXInt(sD)
            }
        }
        if start <= 0 {
            throw invalidArgumentError("SEARCH")
        }

        let hasFallback = !frame.isBlankArgument(3)
        let fallback: Value = hasFallback ? try frame.scalar(3) : .blank

        func notFound() throws(DAXError) -> Value {
            if hasFallback { return fallback }
            throw DAXError(.runtime, "The search Text provided to function 'SEARCH' could not be found in the given text.")
        }

        if withinArg.isBlank {
            return try notFound()
        }
        let withinText = withinArg.asText()
        let withinUnits = Array(withinText.utf16)

        let findText = findArg.asText()
        if findArg.isBlank || findText.isEmpty {
            if start > withinUnits.count {
                return try notFound()
            }
            return .integer(Int64(start))
        }

        if findText == "~" {
            return .integer(Int64(start))
        }

        if start > withinUnits.count {
            return try notFound()
        }

        let haySlice = Array(withinUnits[(start - 1)...])
        let hayString = String(decoding: haySlice, as: UTF16.self)

        // Uppercase cả hai để so không phân biệt hoa thường nhưng không chuẩn hoá Unicode (NFC ≠ NFD)
        let hayUpper = daxUpperString(hayString)
        let findUpper = daxUpperString(findText)

        var pattern = ""
        var wildcard = false
        var hasEscape = false
        var it = findUpper.makeIterator()
        while let ch = it.next() {
            switch ch {
            case "?":
                pattern += "."
                wildcard = true
            case "*":
                pattern += ".*?"
                wildcard = true
            case "~":
                hasEscape = true
                if let next = it.next() {
                    pattern += NSRegularExpression.escapedPattern(for: String(next))
                }
            default:
                pattern += NSRegularExpression.escapedPattern(for: String(ch))
            }
        }

        var offsetInHayUnits: Int? = nil

        if !wildcard && !hasEscape {
            if let range = hayUpper.range(of: findUpper, options: [.literal]) {
                let prefix = hayUpper[..<range.lowerBound]
                offsetInHayUnits = Array(prefix.utf16).count
            }
        } else {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
               let match = regex.firstMatch(in: hayUpper, range: NSRange(location: 0, length: (hayUpper as NSString).length)) {
                offsetInHayUnits = match.range.location
            }
        }

        if let offset = offsetInHayUnits {
            return .integer(Int64(start + offset))
        }

        return try notFound()
    }

    /// LEFT(text[, n]): n mặc định 1; n < 0 là lỗi. UTF-16 code units.
    static func leftBody(_ frame: CallFrame) throws(DAXError) -> Value {
        let arg = try frame.scalar(0)
        if arg.isBlank { return .blank }
        let text = arg.asText()
        var count = 1
        if !frame.isBlankArgument(1) {
            let nArg = try frame.scalar(1)
            if nArg.isBlank {
                count = 0
            } else {
                let d = try nArg.asDouble()
                let n = roundDAXInt(d)
                if n < 0 {
                    throw invalidArgumentError("LEFT")
                }
                count = n
            }
        }
        if count == 0 { return .string("") }
        let units = Array(text.utf16)
        let take = min(count, units.count)
        return .string(String(decoding: units[0..<take], as: UTF16.self))
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
