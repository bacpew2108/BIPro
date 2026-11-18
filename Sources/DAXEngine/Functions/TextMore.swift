// Thân hàm cho gói F2-DAXTEXT (họ hàm Text).
// Khớp quy tắc Desktop 2.159 quan sát trong VM-F12 (QUAN-SAT.md) và golden.tsv.

import Foundation

extension TextFunctions {

    @usableFromInline
    static func roundDAXInt(_ d: Double) -> Int {
        guard d.isFinite else { return 0 }
        let rounded = d.rounded(.toNearestOrAwayFromZero)
        if rounded > Double(Int.max) { return Int.max }
        if rounded < Double(Int.min) { return Int.min }
        return Int(rounded)
    }

    @usableFromInline
    static func invalidArgumentError(_ functionName: String) -> DAXError {
        DAXError(.runtime, "An argument of function '\(functionName)' has the wrong data type or has an invalid value.")
    }

    @usableFromInline
    static func daxUpperString(_ text: String) -> String {
        if text.contains("ß") {
            let parts = text.split(separator: "ß", omittingEmptySubsequences: false)
            let upperParts = parts.map { $0.uppercased(with: Locale(identifier: "en_US")) }
            return upperParts.joined(separator: "ß")
        }
        return text.uppercased(with: Locale(identifier: "en_US"))
    }

    // MARK: - LEN

    /// LEN(text): độ dài theo UTF-16 code units. BLANK -> BLANK; "" -> 0.
    public static func lenBody(_ frame: CallFrame) throws(DAXError) -> Value {
        let arg = try frame.scalar(0)
        if arg.isBlank { return .blank }
        let text = arg.asText()
        return .integer(Int64(Array(text.utf16).count))
    }

    // MARK: - UPPER / LOWER

    /// UPPER(text): BLANK -> BLANK. Chữ Việt hoa đúng. "ß" giữ nguyên là "ß".
    public static func upperBody(_ frame: CallFrame) throws(DAXError) -> Value {
        let arg = try frame.scalar(0)
        if arg.isBlank { return .blank }
        let text = arg.asText()
        return .string(daxUpperString(text))
    }

    /// LOWER(text): BLANK -> BLANK. Chữ Việt thường đúng. "İ" (U+0130) -> "i" (U+0069).
    public static func lowerBody(_ frame: CallFrame) throws(DAXError) -> Value {
        let arg = try frame.scalar(0)
        if arg.isBlank { return .blank }
        let text = arg.asText()
        if text.contains("\u{0130}") {
            let replaced = text.replacingOccurrences(of: "\u{0130}", with: "i")
            return .string(replaced.lowercased(with: Locale(identifier: "en_US")))
        }
        return .string(text.lowercased(with: Locale(identifier: "en_US")))
    }

    // MARK: - RIGHT

    /// RIGHT(text[, num_chars]): UTF-16 code units. n mặc định 1; n < 0 lỗi; n = 0 hoặc BLANK -> ""; n vượt độ dài -> cả chuỗi. text BLANK -> BLANK.
    public static func rightBody(_ frame: CallFrame) throws(DAXError) -> Value {
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
                    throw invalidArgumentError("RIGHT")
                }
                count = n
            }
        }
        if count == 0 { return .string("") }
        let units = Array(text.utf16)
        let take = min(count, units.count)
        let start = units.count - take
        return .string(String(decoding: units[start..<units.count], as: UTF16.self))
    }

    // MARK: - MID

    /// MID(text, start_num, num_chars): start < 1 hoặc BLANK -> lỗi. length < 0 -> lỗi; length 0 hoặc BLANK -> "". start vượt độ dài -> "". text BLANK -> BLANK.
    public static func midBody(_ frame: CallFrame) throws(DAXError) -> Value {
        let arg = try frame.scalar(0)
        if arg.isBlank { return .blank }
        let text = arg.asText()

        let startArg = try frame.scalar(1)
        if startArg.isBlank {
            throw invalidArgumentError("MID")
        }
        let startD = try startArg.asDouble()
        let start = roundDAXInt(startD)
        if start < 1 {
            throw invalidArgumentError("MID")
        }

        let lenArg = try frame.scalar(2)
        var length = 0
        if !lenArg.isBlank {
            let lenD = try lenArg.asDouble()
            let len = roundDAXInt(lenD)
            if len < 0 {
                throw invalidArgumentError("MID")
            }
            length = len
        }
        if length == 0 { return .string("") }

        let units = Array(text.utf16)
        if start > units.count { return .string("") }
        let startIndex = start - 1
        let take = min(length, units.count - startIndex)
        return .string(String(decoding: units[startIndex..<(startIndex + take)], as: UTF16.self))
    }

    // MARK: - TRIM

    /// TRIM(text): Chỉ bỏ dấu cách ASCII (U+0020) ở hai đầu và gộp chuỗi dấu cách giữa các từ thành một. BLANK -> BLANK; chuỗi toàn dấu cách -> "".
    public static func trimBody(_ frame: CallFrame) throws(DAXError) -> Value {
        let arg = try frame.scalar(0)
        if arg.isBlank { return .blank }
        let text = arg.asText()
        let units = Array(text.utf16)
        let space: UInt16 = 0x0020
        var start = 0
        while start < units.count && units[start] == space {
            start += 1
        }
        if start == units.count { return .string("") }
        var end = units.count - 1
        while end >= start && units[end] == space {
            end -= 1
        }
        var result: [UInt16] = []
        result.reserveCapacity(end - start + 1)
        var lastWasSpace = false
        for i in start...end {
            let u = units[i]
            if u == space {
                if !lastWasSpace {
                    result.append(space)
                    lastWasSpace = true
                }
            } else {
                result.append(u)
                lastWasSpace = false
            }
        }
        return .string(String(decoding: result, as: UTF16.self))
    }

    // MARK: - SUBSTITUTE

    /// SUBSTITUTE(text, old_text, new_text[, instance_num]): Phân biệt hoa thường, không chồng lấn. instance 0 hoặc âm -> lỗi. instance vượt số lần xuất hiện -> giữ nguyên. old "" hoặc BLANK -> giữ nguyên. new BLANK -> xoá. text BLANK -> BLANK.
    public static func substituteBody(_ frame: CallFrame) throws(DAXError) -> Value {
        let textArg = try frame.scalar(0)
        if textArg.isBlank { return .blank }
        let text = textArg.asText()

        let oldArg = try frame.scalar(1)
        if oldArg.isBlank { return .string(text) }
        let oldText = oldArg.asText()
        if oldText.isEmpty { return .string(text) }

        let newArg = try frame.scalar(2)
        let newText = newArg.isBlank ? "" : newArg.asText()

        var instanceNum: Int? = nil
        if !frame.isBlankArgument(3) {
            let instArg = try frame.scalar(3)
            if !instArg.isBlank {
                let instD = try instArg.asDouble()
                let inst = roundDAXInt(instD)
                if inst <= 0 {
                    throw invalidArgumentError("SUBSTITUTE")
                }
                instanceNum = inst
            }
        }

        let hay = Array(text.utf16)
        let needle = Array(oldText.utf16)
        let replacement = Array(newText.utf16)

        var occurrences: [Int] = []
        var i = 0
        while i <= hay.count - needle.count {
            var match = true
            for j in 0..<needle.count {
                if hay[i + j] != needle[j] {
                    match = false
                    break
                }
            }
            if match {
                occurrences.append(i)
                i += needle.count
            } else {
                i += 1
            }
        }

        if occurrences.isEmpty { return .string(text) }

        if let inst = instanceNum {
            // Khi tìm lần xuất hiện thứ k, DAX đếm mọi lần xuất hiện (có thể chồng lấn)
            var allOccurrences: [Int] = []
            var j = 0
            while j <= hay.count - needle.count {
                var match = true
                for k in 0..<needle.count {
                    if hay[j + k] != needle[k] {
                        match = false
                        break
                    }
                }
                if match {
                    allOccurrences.append(j)
                }
                j += 1
            }
            guard inst <= allOccurrences.count else { return .string(text) }
            let targetPos = allOccurrences[inst - 1]
            var result: [UInt16] = []
            result.append(contentsOf: hay[0..<targetPos])
            result.append(contentsOf: replacement)
            result.append(contentsOf: hay[(targetPos + needle.count)...])
            return .string(String(decoding: result, as: UTF16.self))
        } else {
            var result: [UInt16] = []
            var lastEnd = 0
            for pos in occurrences {
                result.append(contentsOf: hay[lastEnd..<pos])
                result.append(contentsOf: replacement)
                lastEnd = pos + needle.count
            }
            result.append(contentsOf: hay[lastEnd...])
            return .string(String(decoding: result, as: UTF16.self))
        }
    }

    // MARK: - REPLACE

    /// REPLACE(old_text, start_num, num_chars, new_text): start < 1 -> lỗi; length < 0 -> lỗi. start vượt độ dài -> nối vào cuối. text BLANK -> coi là "". new BLANK -> xoá.
    public static func replaceBody(_ frame: CallFrame) throws(DAXError) -> Value {
        let textArg = try frame.scalar(0)
        let text = textArg.isBlank ? "" : textArg.asText()

        let startArg = try frame.scalar(1)
        if startArg.isBlank { throw invalidArgumentError("REPLACE") }
        let startD = try startArg.asDouble()
        let start = roundDAXInt(startD)
        if start < 1 { throw invalidArgumentError("REPLACE") }

        let lenArg = try frame.scalar(2)
        var length = 0
        if !lenArg.isBlank {
            let lenD = try lenArg.asDouble()
            let len = roundDAXInt(lenD)
            if len < 0 { throw invalidArgumentError("REPLACE") }
            length = len
        }

        let newArg = try frame.scalar(3)
        let newText = newArg.isBlank ? "" : newArg.asText()

        let hay = Array(text.utf16)
        let rep = Array(newText.utf16)

        if start > hay.count {
            return .string(String(decoding: hay + rep, as: UTF16.self))
        }
        let startIndex = start - 1
        let removeCount = min(length, hay.count - startIndex)
        var result: [UInt16] = []
        result.append(contentsOf: hay[0..<startIndex])
        result.append(contentsOf: rep)
        result.append(contentsOf: hay[(startIndex + removeCount)...])
        return .string(String(decoding: result, as: UTF16.self))
    }

    // MARK: - CONCATENATE

    /// CONCATENATE(text1, text2): như &; BLANK & BLANK = BLANK.
    public static func concatenateBody(_ frame: CallFrame) throws(DAXError) -> Value {
        let lhs = try frame.scalar(0)
        let rhs = try frame.scalar(1)
        return Value.concatenate(lhs, rhs)
    }

    // MARK: - FIND

    /// FIND(find_text, within_text[, start_num[, not_found_value]]): So nhị phân phân biệt hoa thường, không có ký tự đại diện. find "" hoặc BLANK -> 1. start 0 -> lỗi.
    public static func findBody(_ frame: CallFrame) throws(DAXError) -> Value {
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
            throw invalidArgumentError("FIND")
        }

        let hasFallback = !frame.isBlankArgument(3)
        let fallback: Value = hasFallback ? try frame.scalar(3) : .blank

        func notFound() throws(DAXError) -> Value {
            if hasFallback { return fallback }
            throw DAXError(.runtime, "The search Text provided to function 'FIND' could not be found in the given text.")
        }

        if withinArg.isBlank {
            return try notFound()
        }
        let withinText = withinArg.asText()
        let withinUnits = Array(withinText.utf16)

        let findText = findArg.asText()
        if findArg.isBlank || findText.isEmpty {
            return .integer(1)
        }

        if start > withinUnits.count {
            return try notFound()
        }

        let findUnits = Array(findText.utf16)
        let startIdx = start - 1
        if startIdx + findUnits.count <= withinUnits.count {
            for i in startIdx...(withinUnits.count - findUnits.count) {
                var match = true
                for j in 0..<findUnits.count {
                    if withinUnits[i + j] != findUnits[j] {
                        match = false
                        break
                    }
                }
                if match {
                    return .integer(Int64(i + 1))
                }
            }
        }
        return try notFound()
    }

    // MARK: - REPT

    /// REPT(text, number_times): n < 0 -> lỗi; n = 0 hoặc BLANK -> "". text BLANK -> BLANK.
    public static func reptBody(_ frame: CallFrame) throws(DAXError) -> Value {
        let textArg = try frame.scalar(0)
        if textArg.isBlank { return .blank }
        let text = textArg.asText()

        let numArg = try frame.scalar(1)
        if numArg.isBlank { return .string("") }
        let numD = try numArg.asDouble()
        let times = roundDAXInt(numD)
        if times < 0 {
            throw invalidArgumentError("REPT")
        }
        if times == 0 || text.isEmpty { return .string("") }
        return .string(String(repeating: text, count: times))
    }

    // MARK: - EXACT

    /// EXACT(text1, text2): So nhị phân theo UTF-16 code units. BLANK = "" = BLANK.
    public static func exactBody(_ frame: CallFrame) throws(DAXError) -> Value {
        let aArg = try frame.scalar(0)
        let bArg = try frame.scalar(1)
        let aStr = aArg.isBlank ? "" : aArg.asText()
        let bStr = bArg.isBlank ? "" : bArg.asText()
        return .boolean(Array(aStr.utf16) == Array(bStr.utf16))
    }

    // MARK: - UNICHAR

    /// UNICHAR(number): code point hợp lệ. 0, âm, surrogate, noncharacter -> lỗi. BLANK -> BLANK.
    public static func unicharBody(_ frame: CallFrame) throws(DAXError) -> Value {
        let arg = try frame.scalar(0)
        if arg.isBlank { return .blank }
        let d = try arg.asDouble()
        let code = roundDAXInt(d)

        if code <= 0 || code > 0x10FFFF {
            throw DAXError(.runtime, "An argument of function 'UNICHAR' has the wrong data type or the result is too large or too small.")
        }
        if (code >= 0xD800 && code <= 0xDFFF)
            || (code < 32 && code != 9 && code != 10 && code != 13)
            || (code >= 0xFDD0 && code <= 0xFDEF)
            || (code & 0xFFFF) >= 0xFFFE {
            throw DAXError(.runtime, "The code point does not correspond to a valid character.")
        }

        guard let scalar = UnicodeScalar(code) else {
            throw DAXError(.runtime, "The code point does not correspond to a valid character.")
        }
        return .string(String(scalar))
    }

    // MARK: - UNICODE

    /// UNICODE(text): Mã của ký tự đầu. Surrogate lẻ -> lỗi. "" và BLANK -> BLANK.
    public static func unicodeBody(_ frame: CallFrame) throws(DAXError) -> Value {
        let arg = try frame.scalar(0)
        if arg.isBlank { return .blank }
        let text = arg.asText()
        if text.isEmpty { return .blank }

        let units = Array(text.utf16)
        guard !units.isEmpty else { return .blank }
        let first = units[0]

        if first >= 0xD800 && first <= 0xDBFF {
            if units.count >= 2 && units[1] >= 0xDC00 && units[1] <= 0xDFFF {
                let code = 0x10000 + ((Int(first) - 0xD800) << 10) + (Int(units[1]) - 0xDC00)
                return .integer(Int64(code))
            } else {
                throw invalidArgumentError("UNICODE")
            }
        } else if first >= 0xDC00 && first <= 0xDFFF {
            throw invalidArgumentError("UNICODE")
        } else {
            return .integer(Int64(first))
        }
    }

    // MARK: - COMBINEVALUES

    /// COMBINEVALUES(delimiter, expression1, expression2, ...): Nối bằng delimiter. Delimiter phải là hằng chuỗi khác rỗng.
    public static func combinevaluesBody(_ frame: CallFrame) throws(DAXError) -> Value {
        guard !frame.isBlankArgument(0) else {
            throw DAXError(.runtime, "The delimiter value in the 'COMBINEVALUES' function can only be a constant non empty string.")
        }
        let delimVal = try frame.scalar(0)
        if delimVal.isBlank {
            throw DAXError(.runtime, "The delimiter value in the 'COMBINEVALUES' function can only be a constant non empty string.")
        }
        let delimiter = delimVal.asText()
        if delimiter.isEmpty {
            throw DAXError(.runtime, "The delimiter value in the 'COMBINEVALUES' function can only be a constant non empty string.")
        }

        var parts: [String] = []
        for i in 1..<frame.args.count {
            if frame.isBlankArgument(i) {
                parts.append("")
            } else {
                let val = try frame.scalar(i)
                parts.append(val.isBlank ? "" : val.asText())
            }
        }
        return .string(parts.joined(separator: delimiter))
    }

    // MARK: - FIXED

    /// FIXED(number, [decimals], [no_commas]): Làm tròn nửa xa 0. Mặc định 2 chữ số và có phân cách nghìn. BLANK -> "0.00".
    public static func fixedBody(_ frame: CallFrame) throws(DAXError) -> Value {
        let numArg = try frame.scalar(0)
        let d: Double
        if numArg.isBlank {
            d = 0.0
        } else {
            d = try numArg.asDouble()
        }

        var decimals = 2
        if !frame.isBlankArgument(1) {
            let decArg = try frame.scalar(1)
            if decArg.isBlank {
                decimals = 0
            } else {
                let decD = try decArg.asDouble()
                decimals = roundDAXInt(decD)
            }
        }
        if decimals > 127 {
            throw invalidArgumentError("FIXED")
        }

        var noCommas = false
        if !frame.isBlankArgument(2) {
            let ncArg = try frame.scalar(2)
            if !ncArg.isBlank {
                noCommas = try ncArg.asLogical()
            }
        }

        guard d.isFinite else { return .string(nonFiniteText(d)) }

        let safeDecimals = max(decimals, -350)
        let dt = DecimalText(magnitudeOf: abs(d)).rounded(decimals: safeDecimals)
        let parts = dt.plainParts(decimals: max(0, safeDecimals))

        let isNeg = (d < 0) && !dt.isZero
        let intPart = parts.integer.isEmpty ? "0" : parts.integer

        var formattedInt = intPart
        if !noCommas {
            let chars = Array(intPart)
            var grouped: [Character] = []
            grouped.reserveCapacity(chars.count + chars.count / 3)
            for (idx, ch) in chars.reversed().enumerated() {
                if idx > 0 && idx % 3 == 0 {
                    grouped.append(",")
                }
                grouped.append(ch)
            }
            formattedInt = String(grouped.reversed())
        }

        var result = (isNeg ? "-" : "") + formattedInt
        if decimals > 0 {
            result += "." + parts.fraction
        }

        return .string(result)
    }

    // MARK: - VALUE

    /// VALUE(text): Chuyển chuỗi sang số theo en-US. Dấu phẩy ngăn nghìn, $, (5) -> -5, 1e3, "2026-01-02" -> số ngày, "12:00" -> 0.5.
    public static func valueBody(_ frame: CallFrame) throws(DAXError) -> Value {
        let arg = try frame.scalar(0)
        if arg.isBlank { return .blank }
        switch arg {
        case .integer, .double, .currency, .dateTime:
            return arg
        default:
            break
        }
        let raw = arg.asText()
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty || s.contains("%") {
            throw DAXError(.typeMismatch, "Cannot convert value '\(raw)' of type Text to type Number.")
        }

        var isNegative = false
        if s.hasPrefix("(") && s.hasSuffix(")") {
            isNegative = true
            s = String(s.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if s.hasPrefix("+") {
            s = String(s.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if s.hasPrefix("-") {
            isNegative = true
            s = String(s.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if s.hasPrefix("$") {
            s = String(s.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Date: YYYY-MM-DD
        let dateParts = s.split(separator: "-")
        if dateParts.count == 3,
           let y = Int(dateParts[0]), let m = Int(dateParts[1]), let d = Int(dateParts[2]),
           dateParts[0].count == 4 {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "UTC")!
            if let date = cal.date(from: DateComponents(year: y, month: m, day: d)) {
                let daysSince1970 = date.timeIntervalSince1970 / 86400.0
                let serial = (daysSince1970 + 25569.0).rounded()
                let intVal = Int64(serial)
                return .integer(isNegative ? -intVal : intVal)
            }
        }

        // Time: HH:MM or HH:MM:SS
        let timeParts = s.split(separator: ":")
        if (timeParts.count == 2 || timeParts.count == 3),
           let h = Double(timeParts[0]), let min = Double(timeParts[1]) {
            let sec = timeParts.count == 3 ? (Double(timeParts[2]) ?? 0.0) : 0.0
            let fraction = (h * 3600.0 + min * 60.0 + sec) / 86400.0
            return .double(isNegative ? -fraction : fraction)
        }

        let noCommas = s.replacingOccurrences(of: ",", with: "")
        if noCommas.isEmpty {
            throw DAXError(.typeMismatch, "Cannot convert value '\(raw)' of type Text to type Number.")
        }

        if !s.contains(".") && !s.contains("e") && !s.contains("E"), let intVal = Int64(noCommas) {
            return .integer(isNegative ? -intVal : intVal)
        }

        guard let d = Double(noCommas) else {
            throw DAXError(.typeMismatch, "Cannot convert value '\(raw)' of type Text to type Number.")
        }
        return .double(isNegative ? -d : d)
    }
}
