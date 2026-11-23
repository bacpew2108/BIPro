// Hàm ngày giờ (F-KIT, đợt 2). DATE tràn tháng và ngày (DATE(2018, 13, 1) = 2019-01-01).
// Ngày là số serial OLE, ngày 0 là 1899-12-30, cùng quy ước với VAL (Value+Ops.swift).
// [SUY ĐOÁN] BLANK được coi là serial 0 (1899-12-30), nên YEAR(BLANK) là 1899. Chờ oracle.
// [DOC date-function-dax] DATE với năm từ 0 đến 1899 thì cộng 1900.
// [SUY ĐOÁN] DATEDIFF: SECOND, MINUTE, HOUR, DAY, WEEK đếm đơn vị đã đủ (cắt về 0). MONTH, QUARTER, YEAR đếm tháng đủ:
// tháng chỉ tính khi ngày và giờ trong ngày đã vượt mốc (31/01 tới 29/02 là 0 tháng). Chờ oracle.

import PBIXKit
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
        FunctionSpec(name: "CALENDAR", params: [.scalar("start_date"), .scalar("end_date")],
                     impl: .table(DateTimeFunctions.calendarBody)),
        // Wave 3 (v1.1b — đối chiếu VM-V11B dax-golden.json)
        FunctionSpec(name: "TODAY", params: [], impl: .scalar(DateTimeFunctions.todayBody)),
        FunctionSpec(name: "NOW", params: [], impl: .scalar(DateTimeFunctions.nowBody)),
        FunctionSpec(name: "WEEKDAY", params: [.scalar("date"), .scalar("return_type", optional: true)],
                     impl: .scalar(DateTimeFunctions.weekdayBody)),
        FunctionSpec(name: "WEEKNUM", params: [.scalar("date"), .scalar("return_type", optional: true)],
                     impl: .scalar(DateTimeFunctions.weeknumBody)),
        FunctionSpec(name: "EOMONTH", params: [.scalar("start_date"), .scalar("months")],
                     impl: .scalar(DateTimeFunctions.eomonthBody)),
        FunctionSpec(name: "EDATE", params: [.scalar("start_date"), .scalar("months")],
                     impl: .scalar(DateTimeFunctions.edateBody)),
        FunctionSpec(name: "MINUTE", params: [.scalar("datetime")], impl: .scalar(DateTimeFunctions.minuteBody)),
        FunctionSpec(name: "SECOND", params: [.scalar("datetime")], impl: .scalar(DateTimeFunctions.secondBody)),
        FunctionSpec(name: "TIME", params: [.scalar("hour"), .scalar("minute"), .scalar("second")],
                     impl: .scalar(DateTimeFunctions.timeBody)),
        FunctionSpec(name: "YEARFRAC", params: [.scalar("start_date"), .scalar("end_date"), .scalar("basis", optional: true)],
                     impl: .scalar(DateTimeFunctions.yearfracBody)),
        FunctionSpec(name: "CALENDARAUTO", params: [.scalar("fiscal_year_end_month", optional: true)],
                     impl: .table(DateTimeFunctions.calendarAutoBody)),
    ]

    /// CALENDAR(đầu, cuối): bảng một cột `[Date]`, mỗi ngày một dòng từ ngày đầu tới ngày cuối (cắt phần giờ), tăng dần
    /// (golden: bảng `Ngày` của w8.3 do Desktop tính, Phase F T081). [DOC calendar-function-dax] đầu sau cuối là lỗi.
    static let calendarBody: FunctionSpec.TableBody = { (frame: CallFrame) throws(DAXError) -> TableValue in
        let start = try frame.scalar(0), end = try frame.scalar(1)
        if start == .blank || end == .blank { throw DAXError(.runtime, lt("CALENDAR: ngày đầu và ngày cuối không được để trống", "CALENDAR: the start and end dates can't be blank")) }
        let first = (try start.asDouble()).rounded(.down), last = (try end.asDouble()).rounded(.down)
        guard first <= last else { throw DAXError(.runtime, lt("CALENDAR: ngày đầu sau ngày cuối", "CALENDAR: the start date is after the end date")) }
        guard last - first < 10_000_000 else { throw DAXError(.runtime, lt("CALENDAR: khoảng ngày quá lớn", "CALENDAR: the date range is too large")) }
        let rows = stride(from: first, through: last, by: 1).map { [Value.dateTime($0)] }
        return TableValue(columns: ["[Date]"], rows: rows)
    }

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
            throw DAXError(.typeMismatch, lt("DATEDIFF: đối số 3 phải là SECOND, MINUTE, HOUR, DAY, WEEK, MONTH, QUARTER hoặc YEAR", "DATEDIFF: argument 3 must be SECOND, MINUTE, HOUR, DAY, WEEK, MONTH, QUARTER or YEAR"))
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
            throw DAXError(.typeMismatch, lt("DATEDIFF: đơn vị \(donVi) không được hỗ trợ", "DATEDIFF: the unit \(donVi) isn't supported"))
        }
    }

    // MARK: - Wave 3 (v1.1b) DateTime functions

    static func todayBody(_ frame: CallFrame) throws(DAXError) -> Value {
        let comps = Calendar(identifier: .gregorian).dateComponents(in: TimeZone.current, from: Date())
        let serial = ngayTuNam(comps.year ?? 2000, comps.month ?? 1, comps.day ?? 1) + soNgayTuEpochOLE
        return .dateTime(Double(serial))
    }

    static func nowBody(_ frame: CallFrame) throws(DAXError) -> Value {
        let comps = Calendar(identifier: .gregorian).dateComponents(in: TimeZone.current, from: Date())
        let daySerial = ngayTuNam(comps.year ?? 2000, comps.month ?? 1, comps.day ?? 1) + soNgayTuEpochOLE
        let sec = (comps.hour ?? 0) * 3600 + (comps.minute ?? 0) * 60 + (comps.second ?? 0)
        return .dateTime(Double(daySerial) + Double(sec) / 86_400.0)
    }

    /// WEEKDAY(date, [return_type = 1]): 1 = CN(1)..T7(7); 2 = T2(1)..CN(7); 3 = T2(0)..CN(6).
    static func weekdayBody(_ frame: CallFrame) throws(DAXError) -> Value {
        let ms = try milliGiay(try serialCua(try frame.scalar(0)))
        let unixDays = chiLam(ms, mocMotNgayMs) - soNgayTuEpochOLE
        // 1970-01-01 là Thứ Năm (weekday 0=CN, 1=T2, 2=T3, 3=T4, 4=T5, 5=T6, 6=T7)
        let dowSun0 = duLam(unixDays + 4, 7)
        let rtype = frame.isBlankArgument(1) ? 1 : try soNguyenCua(try frame.scalar(1))
        switch rtype {
        case 1: return .integer(Int64(dowSun0 + 1))
        case 2: return .integer(Int64(dowSun0 == 0 ? 7 : dowSun0))
        case 3: return .integer(Int64(dowSun0 == 0 ? 6 : dowSun0 - 1))
        default: throw DAXError(.runtime, lt("WEEKDAY: return_type phải là 1, 2 hoặc 3", "WEEKDAY: return_type must be 1, 2 or 3"))
        }
    }

    /// WEEKNUM(date, [return_type = 1]): 1 = tuần bắt đầu CN; 2 = T2; 21 = ISO 8601 (VM-V11B).
    static func weeknumBody(_ frame: CallFrame) throws(DAXError) -> Value {
        let ms = try milliGiay(try serialCua(try frame.scalar(0)))
        let unixDays = chiLam(ms, mocMotNgayMs) - soNgayTuEpochOLE
        let rtype = frame.isBlankArgument(1) ? 1 : try soNguyenCua(try frame.scalar(1))
        if rtype == 21 {
            // ISO 8601: tuần 1 là tuần Thứ Hai..CN chứa Thứ Năm đầu tiên của năm.
            let dowMon0 = duLam(unixDays + 3, 7) // 0=T2..6=CN
            let thursdayUnix = unixDays - dowMon0 + 3
            let thursCal = lichTuNgay(thursdayUnix)
            let jan4Unix = ngayTuNam(thursCal.year, 1, 4)
            let jan4DowMon0 = duLam(jan4Unix + 3, 7)
            let week1Monday = jan4Unix - jan4DowMon0
            return .integer(Int64((unixDays - week1Monday) / 7 + 1))
        }
        let cal = lichTuNgay(unixDays)
        let jan1Unix = ngayTuNam(cal.year, 1, 1)
        let doy0 = unixDays - jan1Unix
        let jan1Dow: Int
        switch rtype {
        case 1: jan1Dow = duLam(jan1Unix + 4, 7)          // CN = 0
        case 2: jan1Dow = duLam(jan1Unix + 3, 7)          // T2 = 0
        default: throw DAXError(.runtime, lt("WEEKNUM: return_type \(rtype) không được hỗ trợ", "WEEKNUM: return_type \(rtype) isn't supported"))
        }
        return .integer(Int64((doy0 + jan1Dow) / 7 + 1))
    }

    static func eomonthBody(_ frame: CallFrame) throws(DAXError) -> Value {
        let cal = try lichCua(try frame.scalar(0))
        let offset = try soNguyenCua(try frame.scalar(1))
        let total = cal.year * 12 + (cal.month - 1) + offset
        let y = chiLam(total, 12)
        let m = duLam(total, 12) + 1
        let lastDay = soNgayTrongThang(y, m)
        return .dateTime(Double(ngayTuNam(y, m, lastDay) + soNgayTuEpochOLE))
    }

    static func edateBody(_ frame: CallFrame) throws(DAXError) -> Value {
        let cal = try lichCua(try frame.scalar(0))
        let offset = try soNguyenCua(try frame.scalar(1))
        let total = cal.year * 12 + (cal.month - 1) + offset
        let y = chiLam(total, 12)
        let m = duLam(total, 12) + 1
        let d = min(cal.day, soNgayTrongThang(y, m))
        return .dateTime(Double(ngayTuNam(y, m, d) + soNgayTuEpochOLE))
    }

    static func minuteBody(_ frame: CallFrame) throws(DAXError) -> Value {
        let ms = try milliGiay(try serialCua(try frame.scalar(0)))
        return .integer(Int64((duLam(ms, mocMotNgayMs) % 3_600_000) / 60_000))
    }

    static func secondBody(_ frame: CallFrame) throws(DAXError) -> Value {
        let ms = try milliGiay(try serialCua(try frame.scalar(0)))
        return .integer(Int64((duLam(ms, mocMotNgayMs) % 60_000) / 1_000))
    }

    /// TIME(h, m, s): trả phần thời gian trên ngày 0 (1899-12-30), tràn modulo 86400s (VM-V11B).
    static func timeBody(_ frame: CallFrame) throws(DAXError) -> Value {
        let h = try soNguyenCua(try frame.scalar(0))
        let m = try soNguyenCua(try frame.scalar(1))
        let s = try soNguyenCua(try frame.scalar(2))
        let totalSec = duLam(h * 3600 + m * 60 + s, 86_400)
        return .dateTime(Double(totalSec) / 86_400.0)
    }

    /// YEARFRAC(start_date, end_date, [basis = 0]): khớp công thức Excel/DAX basis 0..4 (VM-V11B).
    static func yearfracBody(_ frame: CallFrame) throws(DAXError) -> Value {
        let s0 = (try serialCua(try frame.scalar(0))).rounded(.down)
        let s1 = (try serialCua(try frame.scalar(1))).rounded(.down)
        let (a, b) = s0 <= s1 ? (s0, s1) : (s1, s0)
        let basis = frame.isBlankArgument(2) ? 0 : try soNguyenCua(try frame.scalar(2))
        let uA = Int(a) - soNgayTuEpochOLE
        let uB = Int(b) - soNgayTuEpochOLE
        let cA = lichTuNgay(uA)
        let cB = lichTuNgay(uB)
        let days = Double(uB - uA)
        switch basis {
        case 0: // US (NASD) 30/360
            var d1 = cA.day, d2 = cB.day
            let febEndA = (cA.month == 2 && d1 == soNgayTrongThang(cA.year, 2))
            let febEndB = (cB.month == 2 && d2 == soNgayTrongThang(cB.year, 2))
            if febEndA && febEndB { d2 = 30 }
            if d1 == 31 || febEndA { d1 = 30 }
            if d2 == 31 && d1 == 30 { d2 = 30 }
            let n30 = (cB.year - cA.year) * 360 + (cB.month - cA.month) * 30 + (d2 - d1)
            return .double(Double(n30) / 360.0)
        case 1: // Actual/Actual (Excel/DAX quy ước)
            let denom: Double
            let spansMoreThanYear = (cB.year > cA.year + 1)
                || (cB.year == cA.year + 1 && (cB.month > cA.month || (cB.month == cA.month && cB.day > cA.day)))
            if spansMoreThanYear {
                var totalDays = 0.0
                for yr in cA.year...cB.year { totalDays += namNhuan(yr) ? 366.0 : 365.0 }
                denom = totalDays / Double(cB.year - cA.year + 1)
            } else {
                var hasFeb29 = false
                if namNhuan(cA.year) {
                    let feb29 = ngayTuNam(cA.year, 2, 29)
                    if feb29 >= uA && feb29 <= uB { hasFeb29 = true }
                }
                if !hasFeb29 && cB.year != cA.year && namNhuan(cB.year) {
                    let feb29 = ngayTuNam(cB.year, 2, 29)
                    if feb29 >= uA && feb29 <= uB { hasFeb29 = true }
                }
                denom = hasFeb29 ? 366.0 : 365.0
            }
            return .double(days / denom)
        case 2: // Actual/360
            return .double(days / 360.0)
        case 3: // Actual/365
            return .double(days / 365.0)
        case 4: // European 30/360
            let d1 = min(cA.day, 30)
            let d2 = min(cB.day, 30)
            let n30 = (cB.year - cA.year) * 360 + (cB.month - cA.month) * 30 + (d2 - d1)
            return .double(Double(n30) / 360.0)
        default:
            throw DAXError(.runtime, lt("YEARFRAC: basis phải từ 0 đến 4", "YEARFRAC: basis must be from 0 to 4"))
        }
    }

    /// CALENDARAUTO([fiscal_year_end_month = 12]): quét toàn bộ cột ngày của model (VM-V11B).
    static let calendarAutoBody: FunctionSpec.TableBody = { (frame: CallFrame) throws(DAXError) -> TableValue in
        let fyEnd = frame.isBlankArgument(0) ? 12 : try soNguyenCua(try frame.scalar(0))
        guard (1...12).contains(fyEnd) else {
            throw DAXError(.runtime, lt("CALENDARAUTO: tháng kết thúc năm tài chính phải từ 1 đến 12", "CALENDARAUTO: the fiscal year end month must be from 1 to 12"))
        }
        let evaluator = try fkEvaluator(frame)
        let store = evaluator.store
        var minDay: Int?
        var maxDay: Int?
        for table in store.schema.tables {
            for col in table.columns where col.type == .dateTime {
                guard let data = try? store.column(col.id) else { continue }
                for r in 0..<data.rowCount {
                    if case .dateTime(let d) = data.value(at: r), d.isFinite {
                        let day = Int(d.rounded(.down))
                        if minDay == nil || day < minDay! { minDay = day }
                        if maxDay == nil || day > maxDay! { maxDay = day }
                    }
                }
            }
        }
        guard let lo = minDay, let hi = maxDay else {
            throw DAXError(.runtime, lt("CALENDARAUTO: không tìm thấy cột ngày có dữ liệu trong mô hình", "CALENDARAUTO: no date column with data found in the model"))
        }
        let cLo = lichTuNgay(lo - soNgayTuEpochOLE)
        let cHi = lichTuNgay(hi - soNgayTuEpochOLE)
        let startMonth = (fyEnd % 12) + 1
        let startYear = (fyEnd == 12) ? cLo.year : (cLo.month >= startMonth ? cLo.year : cLo.year - 1)
        let endYear = (fyEnd == 12) ? cHi.year : (cHi.month <= fyEnd ? cHi.year : cHi.year + 1)
        let firstSerial = ngayTuNam(startYear, startMonth, 1) + soNgayTuEpochOLE
        let lastSerial = ngayTuNam(endYear, fyEnd, soNgayTrongThang(endYear, fyEnd)) + soNgayTuEpochOLE
        guard firstSerial <= lastSerial, lastSerial - firstSerial < 10_000_000 else {
            throw DAXError(.runtime, lt("CALENDARAUTO: khoảng ngày không hợp lệ", "CALENDARAUTO: invalid date range"))
        }
        let rows = (firstSerial...lastSerial).map { [Value.dateTime(Double($0))] }
        return TableValue(columns: ["[Date]"], rows: rows)
    }
}

private func namNhuan(_ year: Int) -> Bool {
    (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
}

private func soNgayTrongThang(_ year: Int, _ month: Int) -> Int {
    switch month {
    case 2: return namNhuan(year) ? 29 : 28
    case 4, 6, 9, 11: return 30
    default: return 31
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
        throw DAXError(.runtime, lt("ngày ngoài phạm vi hỗ trợ", "the date is outside the supported range"))
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
