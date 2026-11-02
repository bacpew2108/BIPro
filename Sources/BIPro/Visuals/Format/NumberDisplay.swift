// Hợp đồng Phase C (đợt 0, lead): hiển thị số trên visual (nhãn dữ liệu, trục, card, tooltip).
//
// Dùng chung cho mọi renderer, để card, trục và nhãn ra cùng một kiểu chữ số.
// Định dạng của ô (`DataCell.formatString`) đi qua `FormatString` của engine (đã khớp Power BI ở Phase B).
// Đơn vị hiển thị (K/M/bn/T) và quy tắc "Tự động" là của visual, KHÔNG phải của DAX:
//   [SUY ĐOÁN, chờ ảnh O-C8] Tự động chọn đơn vị theo `reference` (card: chính giá trị; trục/nhãn: giá trị tuyệt đối
//   lớn nhất của visual); độ chính xác mặc định 2 chữ số sau dấu chấm, bỏ số 0 thừa ở cuối.
import DAXEngine
import Foundation

enum NumberDisplay {
    static let culture = "en-US"

    /// Đơn vị dùng cho `reference` khi `units == .auto`.
    static func resolve(_ units: DisplayUnits, reference: Double) -> DisplayUnits {
        guard units == .auto else { return units }
        let r = abs(reference)
        if r >= 1e12 { return .trillions }
        if r >= 1e9 { return .billions }
        if r >= 1e6 { return .millions }
        if r >= 1e3 { return .thousands }
        return .none
    }

    static func divisor(_ units: DisplayUnits) -> Double {
        switch units {
        case .auto, .none: 1
        case .thousands: 1e3
        case .millions: 1e6
        case .billions: 1e9
        case .trillions: 1e12
        }
    }

    static func suffix(_ units: DisplayUnits) -> String {
        switch units {
        case .auto, .none: ""
        case .thousands: "K"
        case .millions: "M"
        case .billions: "bn"
        case .trillions: "T"
        }
    }

    /// Văn bản hiển thị của một ô.
    /// - `units`, `precision`: theo `VisualFormat` (nhãn, trục hoặc card).
    /// - `reference`: giá trị dùng để chọn đơn vị khi `units == .auto`; nil = dùng chính giá trị.
    static func text(_ cell: DataCell, units: DisplayUnits = .auto, precision: Int? = nil, reference: Double? = nil) -> String {
        guard let number = numericValue(cell.value) else {
            return plain(cell)
        }
        let pattern = cell.formatString ?? ""
        // Phần trăm và định dạng không phải số: giữ nguyên định dạng của ô, không đổi đơn vị.
        if pattern.contains("%") { return plain(cell) }
        let unit = resolve(units, reference: reference ?? number)
        if unit == .none {
            guard let precision else { return plain(cell) }
            return affixes(of: pattern).prefix + decimal(number, precision: precision) + affixes(of: pattern).suffix
        }
        let scaled = number / divisor(unit)
        let (prefix, suffixText) = affixes(of: pattern)
        // [C1, page-D1.png] Độ chính xác "tự động" = số chữ số thập phân của định dạng measure:
        // "$#,0" → $3bn, $197M, $44K; precision đặt sẵn thì giữ số 0 cuối ($33.0M). Không có định dạng: tối đa 2, bỏ số 0 cuối [SUY ĐOÁN].
        if let precision {
            return prefix + decimal(scaled, precision: precision) + suffix(unit) + suffixText
        }
        if let places = decimalPlaces(of: pattern) {
            return prefix + decimal(scaled, precision: places) + suffix(unit) + suffixText
        }
        return prefix + decimal(scaled, precision: 2, trimZeros: true) + suffix(unit) + suffixText
    }

    /// Số chữ số sau dấu chấm trong phần đầu của mẫu số ("$#,0.00" → 2, "#,0" → 0). nil khi mẫu rỗng hoặc không phải mẫu số.
    static func decimalPlaces(of pattern: String) -> Int? {
        let section = pattern.split(separator: ";", omittingEmptySubsequences: false).first.map(String.init) ?? ""
        guard section.contains(where: { $0 == "0" || $0 == "#" }) else { return nil }
        guard let dot = section.firstIndex(of: ".") else { return 0 }
        return section[section.index(after: dot)...].prefix { $0 == "0" || $0 == "#" }.count
    }

    /// Định dạng theo `formatString` của ô, không đổi đơn vị (bảng, tooltip).
    static func plain(_ cell: DataCell) -> String {
        if case .blank = cell.value { return "" }
        if let pattern = cell.formatString, !pattern.isEmpty,
           let text = try? FormatString.format(cell.value, pattern: pattern, culture: culture) {
            return text
        }
        switch cell.value {
        case .double(let d):
            return decimal(d, precision: 2, trimZeros: true)
        default:
            return cell.value.asText()
        }
    }

    static func numericValue(_ value: Value) -> Double? {
        switch value {
        case .integer(let i): Double(i)
        case .double(let d): d.isFinite ? d : nil
        case .currency(let c): Double(c) / 10_000
        default: nil
        }
    }

    /// Ký tự đứng trước/sau phần số của mẫu (ví dụ "$" trong "$#,0.00", " ngày" trong "0.0 \" ngày\"").
    /// [SUY ĐOÁN] Power BI giữ ký hiệu tiền tệ khi đổi đơn vị.
    static func affixes(of pattern: String) -> (prefix: String, suffix: String) {
        let section = pattern.split(separator: ";", omittingEmptySubsequences: false).first.map(String.init) ?? ""
        let digits = Set("0#.,")
        guard let first = section.firstIndex(where: { digits.contains($0) }),
              let last = section.lastIndex(where: { digits.contains($0) }) else { return ("", "") }
        func clean(_ s: Substring) -> String { s.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "\\", with: "") }
        return (clean(section[..<first]), clean(section[section.index(after: last)...]))
    }

    /// Số thập phân kiểu en-US có dấu phẩy ngăn nghìn.
    static func decimal(_ number: Double, precision: Int, trimZeros: Bool = false) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.roundingMode = .halfUp
        f.maximumFractionDigits = max(0, precision)
        f.minimumFractionDigits = trimZeros ? 0 : max(0, precision)
        return f.string(from: NSNumber(value: number)) ?? String(number)
    }
}
