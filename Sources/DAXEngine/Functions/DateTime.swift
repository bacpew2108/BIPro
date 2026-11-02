// Hàm ngày giờ (F-KIT, đợt 2). DATE tràn tháng và ngày (DATE(2018, 13, 1) = 2019-01-01).
// Ngày là số serial OLE, ngày 0 là 1899-12-30, cùng quy ước với VAL (Value+Ops.swift).
// [SUY ĐOÁN] BLANK được coi là serial 0 (1899-12-30), nên YEAR(BLANK) là 1899. Chờ oracle.
// [DOC date-function-dax] DATE với năm từ 0 đến 1899 thì cộng 1900.
// [SUY ĐOÁN] DATEDIFF: SECOND, MINUTE, HOUR, DAY, WEEK đếm đơn vị đã đủ (cắt về 0). MONTH, QUARTER, YEAR đếm tháng đủ:
// tháng chỉ tính khi ngày và giờ trong ngày đã vượt mốc (31/01 tới 29/02 là 0 tháng). Chờ oracle.

import Foundation

public enum DateTimeFunctions: FunctionFamily {
    public static let functions: [FunctionSpec] = [
        FunctionSpec(name: "DATE", params: [.scalar("year"), .scalar("month"), .scalar("day")],
                     impl: .scalar(DateTimeFunctions.dateBody)),
        FunctionSpec(name: "YEAR", params: [.scalar("date")], impl: .scalar(DateTimeFunctions.yearBody)),
        FunctionSpec(name: "MONTH", params: [.scalar("date")], impl: .scalar(DateTimeFunctions.monthBody)),
        FunctionSpec(name: "DAY", params: [.scalar("date")], impl: .scalar(DateTimeFunctions.dayBody)),
        FunctionSpec(name: "QUARTER", params: [.scalar("date")], impl: .scalar(DateTimeFunctions.quarterBody)),
        FunctionSpec(name: "HOUR", params: [.scalar("datetime")], impl: .scalar(DateTimeFunctions.hourBody)),
        FunctionSpec(name: "DATEDIFF",
                     params: [.scalar("start_date"), .scalar("end_date"),
                              .keyword("interval", ["SECOND", "MINUTE", "HOUR", "DAY", "WEEK", "MONTH", "QUARTER", "YEAR"])],
                     impl: .scalar(DateTimeFunctions.dateDiffBody)),
    ]

    // MARK: - Thân hàm

    /// DATE(năm, tháng, ngày): tháng và ngày tràn được chuẩn hoá (tháng 0 là tháng 12 năm trước, ngày 0 là ngày cuối tháng trước).
    static func dateBody(_ frame: CallFrame) throws(DAXError) -> Value {
        var nam = try soNguyenCua(try frame.scalar(0))
        let thang = try soNguyenCua(try frame.scalar(1))
        let ngay = try soNguyenCua(try frame.scalar(2))
        if (0...1899).contains(nam) { nam += 1900 }
        let tongThang = nam * 12 + (thang - 1)
        let namChuan = chiLam(tongThang, 12)
        let thangChuan = duLam(tongThang, 12) + 1
        let serial = ngayTuNam(namChuan, thangChuan, 1) + (ngay - 1) + soNgayTuEpochOLE
        return .dateTime(Double(serial))
    }

    static func yearBody(_ frame: CallFrame) throws(DAXError) -> Value {
        let lich = try lichCua(try frame.scalar(0))
        return .integer(Int64(lich.year))
    }

    static func monthBody(_ frame: CallFrame) throws(DAXError) -> Value {
        let lich = try lichCua(try frame.scalar(0))
        return .integer(Int64(lich.month))
    }

    static func dayBody(_ frame: CallFrame) throws(DAXError) -> Value {
        let lich = try lichCua(try frame.scalar(0))
        return .integer(Int64(lich.day))
    }

    static func quarterBody(_ frame: CallFrame) throws(DAXError) -> Value {
        let lich = try lichCua(try frame.scalar(0))
        return .integer(Int64((lich.month - 1) / 3 + 1))
    }

    /// HOUR: giờ trong ngày, 0 đến 23.
    static func hourBody(_ frame: CallFrame) throws(DAXError) -> Value {
        let ms = try milliGiay(try serialCua(try frame.scalar(0)))
        return .integer(Int64(duLam(ms, mocMotNgayMs) / 3_600_000))
    }

    /// DATEDIFF(đầu, cuối, đơn vị). Kết quả cắt về 0: DATEDIFF(cuối, đầu) là số âm tương ứng.
    static func dateDiffBody(_ frame: CallFrame) throws(DAXError) -> Value {
        let msDau = try milliGiay(try serialCua(try frame.scalar(0)))
        let msCuoi = try milliGiay(try serialCua(try frame.scalar(1)))
        guard let donVi = frame.keyword(2)?.uppercased() else {
            throw DAXError(.typeMismatch, "DATEDIFF: đối số 3 phải là SECOND, MINUTE, HOUR, DAY, WEEK, MONTH, QUARTER hoặc YEAR")
        }
        let chenh = msCuoi - msDau
        switch donVi {
        case "SECOND": return .integer(Int64(chenh / 1_000))
        case "MINUTE": return .integer(Int64(chenh / 60_000))
        case "HOUR": return .integer(Int64(chenh / 3_600_000))
        case "DAY": return .integer(Int64(chenh / mocMotNgayMs))
        case "WEEK": return .integer(Int64(chenh / (7 * mocMotNgayMs)))
        case "MONTH": return .integer(Int64(soThangDu(msDau, msCuoi)))
        case "QUARTER": return .integer(Int64(soThangDu(msDau, msCuoi) / 3))
        case "YEAR": return .integer(Int64(soThangDu(msDau, msCuoi) / 12))
        default:
            throw DAXError(.typeMismatch, "DATEDIFF: đơn vị \(donVi) không được hỗ trợ")
        }
    }
}

// MARK: - Tiện ích lịch và serial (private, chỉ dùng trong file này)

private let mocMotNgayMs = 86_400_000
/// Số ngày từ 1899-12-30 đến 1970-01-01.
private let soNgayTuEpochOLE = 25_569

/// Chia lấy sàn cho số nguyên dương.
private func chiLam(_ a: Int, _ b: Int) -> Int {
    let q = a / b
    return (a % b < 0) ? q - 1 : q
}

/// Phần dư không âm khi chia cho số nguyên dương.
private func duLam(_ a: Int, _ b: Int) -> Int {
    let r = a % b
    return r < 0 ? r + b : r
}

/// Mili giây kể từ 1899-12-30, đã làm tròn tới mili giây. Serial ngoài ±10⁹ ngày thì báo lỗi.
private func milliGiay(_ serial: Double) throws(DAXError) -> Int {
    guard serial.isFinite, abs(serial) < 1.0e9 else {
        throw DAXError(.runtime, "ngày ngoài phạm vi hỗ trợ")
    }
    return Int((serial * 86_400_000).rounded())
}

/// Serial của một giá trị dùng như ngày. Ngày giữ nguyên; số và chuỗi số đọc như serial; BLANK là 0.
private func serialCua(_ v: Value) throws(DAXError) -> Double {
    if case .dateTime(let d) = v { return d }
    return try v.asDouble()
}

/// Số ngày từ 1970-01-01 tới ngày (năm, tháng, ngày) của lịch Gregorian (thuật toán của H. Hinnant).
private func ngayTuNam(_ nam0: Int, _ thang: Int, _ ngay: Int) -> Int {
    let nam = thang <= 2 ? nam0 - 1 : nam0
    let ky = chiLam(nam, 400)
    let namTrongKy = nam - ky * 400
    let thangTrongNam = (thang + 9) % 12                // tháng 3 là 0
    let ngayTrongNam = (153 * thangTrongNam + 2) / 5 + ngay - 1
    let ngayTrongKy = namTrongKy * 365 + namTrongKy / 4 - namTrongKy / 100 + ngayTrongNam
    return ky * 146_097 + ngayTrongKy - 719_468
}

/// Ngày (năm, tháng, ngày) từ số ngày kể từ 1970-01-01 (nghịch đảo của ngayTuNam).
private func lichTuNgay(_ soNgay: Int) -> (year: Int, month: Int, day: Int) {
    let z = soNgay + 719_468
    let ky = chiLam(z, 146_097)
    let ngayTrongKy = z - ky * 146_097
    let namTrongKy = (ngayTrongKy - ngayTrongKy / 1460 + ngayTrongKy / 36_524 - ngayTrongKy / 146_096) / 365
    let dayOfYear = ngayTrongKy - (365 * namTrongKy + namTrongKy / 4 - namTrongKy / 100)
    let mp = (5 * dayOfYear + 2) / 153
    let ngay = dayOfYear - (153 * mp + 2) / 5 + 1
    let thang = mp < 10 ? mp + 3 : mp - 9
    let nam = namTrongKy + ky * 400
    return (thang <= 2 ? nam + 1 : nam, thang, ngay)
}

/// Năm, tháng, ngày của một giá trị dùng như ngày.
private func lichCua(_ v: Value) throws(DAXError) -> (year: Int, month: Int, day: Int) {
    let ms = try milliGiay(try serialCua(v))
    return lichTuNgay(chiLam(ms, mocMotNgayMs) - soNgayTuEpochOLE)
}

/// Số tháng đủ từ thời điểm đầu tới thời điểm cuối (cắt về 0). Tháng chỉ tính khi (ngày, giờ trong ngày) đã vượt mốc.
private func soThangDu(_ dau: Int, _ cuoi: Int) -> Int {
    let lichDau = lichTuNgay(chiLam(dau, mocMotNgayMs) - soNgayTuEpochOLE)
    let lichCuoi = lichTuNgay(chiLam(cuoi, mocMotNgayMs) - soNgayTuEpochOLE)
    var thang = (lichCuoi.year * 12 + lichCuoi.month) - (lichDau.year * 12 + lichDau.month)
    let mocDau = (lichDau.day, duLam(dau, mocMotNgayMs))
    let mocCuoi = (lichCuoi.day, duLam(cuoi, mocMotNgayMs))
    if thang > 0 && mocCuoi < mocDau { thang -= 1 }
    if thang < 0 && mocCuoi > mocDau { thang += 1 }
    return thang
}
