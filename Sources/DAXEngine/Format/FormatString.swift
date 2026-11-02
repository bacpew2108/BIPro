// FORMAT và định dạng số (VAL, đợt 1b). Quy tắc: docs/phase-b-research/architecture.md §5.6.
// Phạm vi đợt 1b: mẫu số tùy biến (0 # . , %, literal, tối đa 3 phần), đủ cho mọi mẫu FORMAT và
// mẫu định dạng của measure Nhom6 (xem danh sách trong FormatStringTests).
// Chưa hỗ trợ, báo DAXError .runtime rõ ràng và không trả chuỗi sai: mẫu ngày, E+0, định dạng đặt tên
// ("General Number", "Fixed", "Percent"…), culture khác en-US.
// [SUY ĐOÁN, chờ O15] Làm tròn nửa xa số 0 trên 15 chữ số có nghĩa (kiểu Excel), không làm tròn theo nhị phân.
import Foundation

/// Mẫu số đầy đủ, dùng cho FORMAT và (sau này) ô kết quả, nhãn visual.
public enum FormatString {
    /// FORMAT(value, pattern, culture). BLANK cho "" (architecture.md §5.6).
    public static func format(_ value: Value, pattern: String, culture: String) throws(DAXError) -> String {
        guard ["en-us", "en"].contains(culture.lowercased()) else {
            throw DAXError(.runtime, "FORMAT: culture \"\(culture)\" chưa được hỗ trợ (đợt 1b chỉ có en-US)")
        }
        if pattern.isEmpty {
            // [SUY ĐOÁN] Mẫu rỗng: trả dạng chuỗi mặc định của giá trị.
            return value.asText()
        }
        if let named = NamedDateFormat(rawValue: pattern.lowercased()) {
            return try named.render(value)
        }
        let spec = try FormatSpec(pattern: pattern)
        switch value {
        case .blank: return ""
        case .boolean(let b): return b ? "TRUE" : "FALSE"          // [SUY ĐOÁN] boolean không áp mẫu số
        case .string(let s):
            // [SUY ĐOÁN] Chuỗi được ép sang số trước khi áp mẫu; không đọc được thì báo lỗi kiểu.
            guard let n = parseDAXNumber(s) else {
                throw DAXError(.typeMismatch, "Cannot convert value '\(s)' of type Text to type Number.")
            }
            return render(n, spec)
        case .integer(let v): return render(.integer(v), spec)
        case .double(let d): return render(.double(d), spec)
        case .currency(let c): return render(.currency(c), spec)
        case .dateTime(let d): return render(.dateTime(d), spec)   // [SUY ĐOÁN] ngày áp mẫu số dưới dạng số serial
        }
    }
}

// MARK: - Định dạng ngày đặt tên (en-US)

/// "General Date" và "Short Date" theo en-US. Quan sát O15 (buổi 2): FORMAT(DATE(2018,12,31), "General Date") = "12/31/2018",
/// tức nửa đêm thì không in giờ. [SUY ĐOÁN] Có giờ thì in "M/d/yyyy h:mm:ss AM/PM" như lưới kết quả (O1);
/// serial trong [0, 1) có giờ thì chỉ in giờ (quy ước VB). Mẫu ngày tuỳ biến (dd/MM/yyyy…) vẫn chưa hỗ trợ.
private enum NamedDateFormat: String {
    case generalDate = "general date"
    case shortDate = "short date"

    func render(_ value: Value) throws(DAXError) -> String {
        let serial: Double
        switch value {
        case .blank: return ""
        case .dateTime(let d), .double(let d): serial = d
        case .integer(let i): serial = Double(i)
        case .currency(let c): serial = Double(c) / 10_000
        case .boolean, .string:
            throw DAXError(.typeMismatch, "FORMAT: định dạng ngày cần giá trị ngày hoặc số")
        }
        guard serial.isFinite, abs(serial) < 3_000_000 else {
            throw DAXError(.runtime, "FORMAT: ngày ngoài phạm vi hỗ trợ")
        }
        var day = Int(serial.rounded(.down))
        var seconds = Int(((serial - Double(day)) * 86_400).rounded())
        if seconds >= 86_400 { day += 1; seconds -= 86_400 }
        let date = Self.dateText(day)
        guard self == .generalDate, seconds > 0 else { return date }
        let hour24 = seconds / 3600
        let hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12
        let time = String(format: "%d:%02d:%02d %@", hour12, (seconds / 60) % 60, seconds % 60, hour24 < 12 ? "AM" : "PM")
        return day == 0 ? time : "\(date) \(time)"
    }

    /// M/d/yyyy của serial OLE (ngày 0 là 30/12/1899).
    private static func dateText(_ serialDay: Int) -> String {
        // Thuật toán civil_from_days (H. Hinnant), từ số ngày tính từ 01/01/1970.
        let z = serialDay - 25_569 + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        let y = yoe + era * 400 + (m <= 2 ? 1 : 0)
        return "\(m)/\(d)/\(y)"
    }
}

// MARK: - Biểu diễn thập phân

/// Độ lớn của một số thập phân: giá trị = 0.d₁d₂…dₙ × 10^exp10. Không có số 0 ở cuối `digits`; rỗng nghĩa là 0.
/// Dấu không nằm ở đây; người gọi giữ dấu riêng.
struct DecimalText: Sendable, Equatable {
    private(set) var digits: [UInt8]
    private(set) var exp10: Int

    init(digits: [UInt8], exp10: Int) {
        var d = digits
        while let last = d.last, last == 0 { d.removeLast() }
        self.digits = d
        self.exp10 = d.isEmpty ? 0 : exp10
    }

    /// Độ lớn của số nguyên không dấu, chính xác.
    init(magnitudeOf n: UInt64) {
        let s = Array(String(n).utf8).map { $0 - 48 }
        self.init(digits: s, exp10: s.count)
    }

    /// Độ lớn của currency (đã nhân 10⁴), chính xác.
    init(currencyRaw raw: Int64) {
        let s = Array(String(raw.magnitude).utf8).map { $0 - 48 }
        self.init(digits: s, exp10: s.count - 4)
    }

    /// Độ lớn của số thực, lấy `significant` chữ số có nghĩa (mặc định 15) để bỏ nhiễu nhị phân.
    /// [SUY ĐOÁN, chờ O15] 15 chữ số như Excel.
    init(magnitudeOf d: Double, significant: Int = 15) {
        if d == 0 || !d.isFinite {
            self.init(digits: [], exp10: 0)
            return
        }
        let text = String(format: "%.\(significant - 1)e", abs(d))
        let parts = text.split(separator: "e")
        let mantissa = Array(parts[0].utf8).filter { $0 != 46 }.map { $0 - 48 }   // bỏ dấu chấm
        let exponent = Int(parts[1]) ?? 0
        self.init(digits: mantissa, exp10: exponent + 1)
    }

    var isZero: Bool { digits.isEmpty }

    /// Nhân với 10^n bằng cách đổi vị trí dấu chấm, không sai số nhị phân.
    func scaledByPowerOfTen(_ n: Int) -> DecimalText {
        DecimalText(digits: digits, exp10: exp10 + n)
    }

    /// Làm tròn nửa xa số 0 (theo độ lớn) tới `decimals` chữ số sau dấu chấm.
    func rounded(decimals k: Int) -> DecimalText {
        let keep = exp10 + k
        if keep >= digits.count { return self }
        if keep < 0 { return DecimalText(digits: [], exp10: 0) }
        var kept = Array(digits[0..<keep])
        var e = exp10
        if digits[keep] >= 5 {
            var i = kept.count - 1
            var carry = true
            while carry && i >= 0 {
                if kept[i] == 9 {
                    kept[i] = 0
                    i -= 1
                } else {
                    kept[i] += 1
                    carry = false
                }
            }
            if carry {
                kept.insert(1, at: 0)
                e += 1
            }
        }
        return DecimalText(digits: kept, exp10: e)
    }

    private func digit(at j: Int) -> UInt8 {
        j >= 0 && j < digits.count ? digits[j] : 0
    }

    /// Phần nguyên (không có số 0 đầu, rỗng khi bằng 0) và đúng `k` chữ số thập phân.
    /// Giả định số đã được làm tròn tới `k` chữ số.
    func plainParts(decimals k: Int) -> (integer: String, fraction: String) {
        var intDigits: [UInt8] = []
        if exp10 > 0 {
            for j in 0..<exp10 { intDigits.append(digit(at: j)) }
        }
        while let first = intDigits.first, first == 0 { intDigits.removeFirst() }
        var frac = ""
        if k > 0 {
            for p in 0..<k { frac += String(digit(at: exp10 + p)) }
        }
        let intText = intDigits.map { String($0) }.joined()
        return (intText, frac)
    }

    /// Chuỗi thập phân không ký hiệu mũ, không số 0 thừa ở phần thập phân. Số 0 cho "0".
    var plainString: String {
        let k = max(0, digits.count - exp10)
        let parts = plainParts(decimals: k)
        var s = parts.integer.isEmpty ? "0" : parts.integer
        if !parts.fraction.isEmpty { s += "." + parts.fraction }
        return s
    }
}

// MARK: - Phân tích mẫu

private let numberSymbols: Set<Character> = ["0", "#", ".", ","]

private func unsupported(_ pattern: String, _ reason: String) -> DAXError {
    DAXError(.runtime, "FORMAT: mẫu \"\(pattern)\" chưa được hỗ trợ: \(reason)")
}

/// Tách mẫu thành tối đa 3 phần theo `;`, bỏ qua `;` nằm trong dấu nháy kép hoặc sau `\`.
private func splitSections(_ pattern: String) throws(DAXError) -> [[Character]] {
    var parts: [[Character]] = [[]]
    var inQuote = false
    let chars = Array(pattern)
    var i = 0
    while i < chars.count {
        let c = chars[i]
        if inQuote {
            parts[parts.count - 1].append(c)
            if c == "\"" { inQuote = false }
        } else if c == "\\" {
            parts[parts.count - 1].append(c)
            if i + 1 < chars.count {
                parts[parts.count - 1].append(chars[i + 1])
                i += 1
            }
        } else if c == "\"" {
            inQuote = true
            parts[parts.count - 1].append(c)
        } else if c == ";" {
            parts.append([])
        } else {
            parts[parts.count - 1].append(c)
        }
        i += 1
    }
    guard !inQuote else { throw unsupported(pattern, "thiếu dấu nháy kép đóng") }
    return parts
}

/// Chỗ số của một phần: `0 # . ,`. Phần nguyên có `0` (tối thiểu chữ số), `#`, dấu phẩy phân nhóm,
/// và dấu phẩy cuối để chia 1000 mỗi dấu. Phần thập phân chỉ có `0` và `#`.
private struct NumberBlock {
    let minInteger: Int
    let grouping: Bool
    let scaleCommas: Int
    let fractionPattern: [Character]

    init(_ run: [Character], pattern: String) throws(DAXError) {
        guard run.filter({ $0 == "." }).count <= 1 else {
            throw unsupported(pattern, "nhiều dấu thập phân trong một chỗ số")
        }
        var integerPart = run
        var fraction: [Character] = []
        if let dot = run.firstIndex(of: ".") {
            integerPart = Array(run[..<dot])
            fraction = Array(run[(dot + 1)...])
        }
        guard !fraction.contains(",") else { throw unsupported(pattern, "dấu phẩy trong phần thập phân") }
        var scale = 0
        while integerPart.last == "," {
            integerPart.removeLast()
            scale += 1
        }
        guard integerPart.first != "," else { throw unsupported(pattern, "dấu phẩy đứng đầu chỗ số") }
        guard !(integerPart.isEmpty && fraction.isEmpty) else { throw unsupported(pattern, "chỗ số rỗng") }
        minInteger = integerPart.filter { $0 == "0" }.count
        grouping = integerPart.contains(",")
        scaleCommas = scale
        fractionPattern = fraction
    }

    /// Bỏ số 0 thừa ở cuối phần thập phân. Giữ mọi vị trí `0` trong mẫu và mọi chữ số khác 0.
    func trimFraction(_ digits: String) -> String {
        let chars = Array(digits)
        var keep = 0
        for (idx, pat) in fractionPattern.enumerated() where pat == "0" {
            keep = idx + 1
        }
        for (idx, ch) in chars.enumerated() where ch != "0" {
            keep = max(keep, idx + 1)
        }
        return String(chars[0..<min(keep, chars.count)])
    }
}

/// Một phần của mẫu: chữ cố định xen với đúng một chỗ số.
private struct FormatSection {
    enum Piece {
        case text(String)
        case number
    }

    let pieces: [Piece]
    let block: NumberBlock
    let percentCount: Int

    init(chars: [Character], pattern: String) throws(DAXError) {
        var pieces: [Piece] = []
        var block: NumberBlock?
        var percents = 0
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if numberSymbols.contains(c) {
                var run: [Character] = []
                while i < chars.count && numberSymbols.contains(chars[i]) {
                    run.append(chars[i])
                    i += 1
                }
                if block != nil { throw unsupported(pattern, "nhiều hơn một chỗ số trong một phần") }
                block = try NumberBlock(run, pattern: pattern)
                pieces.append(.number)
                continue
            }
            switch c {
            case "\"":
                var j = i + 1
                var text = ""
                while j < chars.count && chars[j] != "\"" {
                    text.append(chars[j])
                    j += 1
                }
                guard j < chars.count else { throw unsupported(pattern, "thiếu dấu nháy kép đóng") }
                pieces.append(.text(text))
                i = j + 1
                continue
            case "\\":
                guard i + 1 < chars.count else { throw unsupported(pattern, "dấu \\ ở cuối mẫu") }
                pieces.append(.text(String(chars[i + 1])))
                i += 2
                continue
            case "%":
                percents += 1                       // nhân 100 và thêm dấu %
                pieces.append(.text("%"))
            case "$", "+", "-", "(", ")", " ", "/", ":":
                pieces.append(.text(String(c)))     // ký tự literal không cần escape
            default:
                throw unsupported(pattern, "ký tự \"\(c)\" chưa được hỗ trợ (đặt trong dấu nháy kép hoặc sau \\)")
            }
            i += 1
        }
        guard let found = block else { throw unsupported(pattern, "phần không có chỗ số 0 hoặc #") }
        self.pieces = pieces
        self.block = found
        self.percentCount = percents
    }

    func render(_ magnitude: DecimalText) -> String {
        let shift = 2 * percentCount - 3 * block.scaleCommas
        let k = block.fractionPattern.count
        let rounded = magnitude.scaledByPowerOfTen(shift).rounded(decimals: k)
        let parts = rounded.plainParts(decimals: k)
        let fraction = block.trimFraction(parts.fraction)
        var integer = parts.integer
        if integer.count < block.minInteger {
            integer = String(repeating: "0", count: block.minInteger - integer.count) + integer
        }
        if block.grouping { integer = groupThousands(integer) }
        let number = fraction.isEmpty ? integer : integer + "." + fraction
        var out = ""
        for piece in pieces {
            switch piece {
            case .text(let t): out += t
            case .number: out += number
            }
        }
        return out
    }
}

/// Mẫu đầy đủ: 1 đến 3 phần (dương; âm; 0).
private struct FormatSpec {
    let sections: [FormatSection]

    init(pattern: String) throws(DAXError) {
        let parts = try splitSections(pattern)
        guard parts.count <= 3 else { throw unsupported(pattern, "tối đa 3 phần ngăn bởi ';'") }
        var built: [FormatSection] = []
        for part in parts {
            built.append(try FormatSection(chars: part, pattern: pattern))
        }
        sections = built
    }
}

/// Thêm dấu phân nhóm hàng nghìn kiểu en-US: 1234567 thành 1,234,567.
private func groupThousands(_ s: String) -> String {
    let chars = Array(s)
    var out: [Character] = []
    for (idx, ch) in chars.enumerated() {
        let remaining = chars.count - idx
        if idx > 0 && remaining % 3 == 0 { out.append(",") }
        out.append(ch)
    }
    return String(out)
}

/// Áp mẫu cho một số đã kiểm tra hợp lệ. Chọn phần theo dấu của giá trị gốc.
private func render(_ n: NumOperand, _ spec: FormatSpec) -> String {
    let magnitude: DecimalText
    let negative: Bool
    switch n {
    case .integer(let v):
        magnitude = DecimalText(magnitudeOf: v.magnitude)
        negative = v < 0
    case .currency(let c):
        magnitude = DecimalText(currencyRaw: c)
        negative = c < 0
    case .double(let d), .dateTime(let d):
        if !d.isFinite { return nonFiniteText(d) }
        magnitude = DecimalText(magnitudeOf: abs(d))
        negative = d < 0
    }
    let isZero = magnitude.isZero
    let section: FormatSection
    var minus = false
    switch spec.sections.count {
    case 1:
        section = spec.sections[0]
        minus = negative                                  // [SUY ĐOÁN] một phần: âm thêm dấu "-"
    case 2:
        section = negative ? spec.sections[1] : spec.sections[0]
    default:
        if isZero {
            section = spec.sections[2]
        } else if negative {
            section = spec.sections[1]
        } else {
            section = spec.sections[0]
        }
    }
    let body = section.render(magnitude)
    return minus ? "-" + body : body
}
