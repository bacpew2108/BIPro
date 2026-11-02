// Time intelligence (F-TIME, đợt 3), architecture.md §5.5 và §8.2; PHASE_B_PLAN §3.4 và §6.
//
// Thiết kế:
// - DATEADD(dates, n, khoảng) và SAMEPERIODLASTYEAR(dates) dùng chung một lõi `shiftedDates`.
//   SAMEPERIODLASTYEAR(d) = DATEADD(d, -1, YEAR), đúng như plan §6.
// - Đối số `dates` có ba dạng:
//   (a) cột ngày `T[c]`: nếu row context gần nhất có dòng của cột này (cùng cách đọc cột trong CORE) thì lấy
//       ngày của dòng đó; nếu không thì lấy mọi ngày thấy được của cột trong ngữ cảnh (`visibleRows`);
//   (b) bảng ảo có lineage về cột ngày (VALUES(T[c]), FILTER(VALUES(T[c]), …), biến giữ bảng ảo);
//   (c) cả bảng vật lý T hoặc biến giữ RowSet: báo lỗi, vì DAX chỉ nhận một cột ngày.
//       Không materialize bảng vật lý.
// - Cột ngày phải có kiểu dateTime và thuộc bảng được đánh dấu `isDateTable` (dataCategory = Time).
//   Thiếu một trong hai, hoặc đối số không có cột ngày, thì báo DAXError(.runtime). Không trả số sai.
// - Kết quả là bảng ảo một cột, lineage = cột ngày gốc, khử trùng. CALCULATE đọc như bộ lọc theo cột.
// - Ngày là serial OLE (ngày 0 là 1899-12-30). Phần lẻ của serial (giờ trong ngày) được giữ nguyên.
//
// Quy tắc dịch. Không có oracle cho các điểm đánh dấu [SUY ĐOÁN]; đáp án test tính bằng Python độc lập.
// - DAY: cộng n ngày. MONTH: cộng n tháng. QUARTER: cộng 3n tháng. YEAR: cộng 12n tháng.
// - Mỗi ngày dịch riêng và kẹp về cuối tháng đích: 28/02/2017 −1 năm = 28/02/2016; 30/04/2017 −1 tháng = 30/03/2017;
//   29/02/2024 −1 năm = 28/02/2023. Tháng nguồn có từ hai ngày được chọn trở lên và có ngày cuối tháng thì thêm phần
//   còn lại của tháng đích: 15–28/02/2017 −1 năm = 15–29/02/2016. Đã đối chiếu golden Power BI (buổi 1 G1/G3,
//   buổi 2 T2-time-edges, buổi 3 T5-edges). Chi tiết ở `shiftSerials`.
// - [SUY ĐOÁN] Khoảng dịch qua năm đếm theo lịch thường: 01/01/2024 −1 tháng = 01/12/2023.
// - [SUY ĐOÁN] Tập ngày không liên tục: mỗi ngày được dịch độc lập. DAX có thể xử lý khác; chưa đối chiếu.
import ColumnStore

public enum TimeIntelligenceFunctions: FunctionFamily {
    public static let functions: [FunctionSpec] = [
        FunctionSpec(name: "SAMEPERIODLASTYEAR", params: [.table("dates")],
                     impl: .table(TimeIntelligenceFunctions.samePeriodLastYearBody)),
        FunctionSpec(name: "DATEADD",
                     params: [.table("dates"), .scalar("number_of_intervals"),
                              .keyword("interval", ["DAY", "MONTH", "QUARTER", "YEAR"])],
                     impl: .table(TimeIntelligenceFunctions.dateAddBody)),
    ]

    // MARK: - Thân hàm

    static func samePeriodLastYearBody(_ frame: CallFrame) throws(DAXError) -> TableValue {
        try shiftedDates(frame, count: -1, unit: "YEAR")
    }

    static func dateAddBody(_ frame: CallFrame) throws(DAXError) -> TableValue {
        guard let unit = frame.keyword(2) else {
            throw DAXError(.typeMismatch, "DATEADD: đối số 3 phải là DAY, MONTH, QUARTER hoặc YEAR")
        }
        let count = try intervalCount(try frame.scalar(1))
        return try shiftedDates(frame, count: count, unit: unit.uppercased())
    }

    // MARK: - Lõi dùng chung

    /// Dịch mọi ngày của đối số `dates` và trả bảng ảo một cột có lineage là cột ngày gốc.
    private static func shiftedDates(_ frame: CallFrame, count: Int, unit: String) throws(DAXError) -> TableValue {
        let source = try dateSource(frame)
        var shifted: [Value] = []
        shifted.reserveCapacity(source.serials.count)
        for day in try shiftSerials(source.serials, count: count, unit: unit) {
            shifted.append(.dateTime(day))
        }
        return TableValue.values(of: source.column, name: source.name, values: shifted)
    }

    /// Nguồn ngày: cột gốc, tên cột và các serial (đã bỏ BLANK, chưa khử trùng).
    private struct DateSource {
        let column: ColumnID
        let name: String
        let serials: [Double]
    }

    private static func dateSource(_ frame: CallFrame) throws(DAXError) -> DateSource {
        guard let evaluator = frame.eval as? Evaluator else {
            throw DAXError(.runtime, "hàm này cần Evaluator của CORE")
        }
        guard let expr = frame.args.first ?? nil else {
            throw DAXError(.arity, "DATEADD và SAMEPERIODLASTYEAR cần đối số ngày")
        }
        switch expr {
        case .column(let id):
            let column = try dateColumn(id, store: evaluator.store)
            return DateSource(column: id, name: column.name,
                              serials: try serialsOfColumn(id, evaluator, frame.ctx))
        case .table(let id):
            let name = evaluator.store.schema.table(id)?.name ?? "\(id)"
            throw DAXError(.runtime, "đối số ngày của DATEADD phải là một cột ngày, không phải cả bảng \(name)")
        case .variable(let slot):
            switch try evaluator.lookupVariable(slot) {
            case .table(let value):
                return try dateSource(of: value, store: evaluator.store)
            case .rows:
                throw DAXError(.runtime, "đối số ngày của DATEADD phải là một cột ngày, không phải cả bảng")
            case .scalar:
                throw DAXError(.typeMismatch, "đối số ngày của DATEADD không phải bảng hay cột")
            }
        default:
            return try dateSource(of: try frame.table(0), store: evaluator.store)
        }
    }

    /// Bảng ảo làm đối số: cột ngày là cột có lineage về cột kiểu dateTime. Bảng một cột thì lấy cột đó.
    private static func dateSource(of table: TableValue, store: ColumnStore) throws(DAXError) -> DateSource {
        let pick: Int
        if table.columns.count == 1 {
            pick = 0
        } else {
            var candidates: [Int] = []
            for (i, lineage) in table.lineage.enumerated() {
                if let lineage, store.schema.column(lineage)?.type == .dateTime {
                    candidates.append(i)
                }
            }
            guard candidates.count == 1, let only = candidates.first else {
                throw DAXError(.runtime, "bảng đối số của DATEADD có \(candidates.count) cột ngày, cần đúng một")
            }
            pick = only
        }
        guard let column = table.lineage[pick] else {
            throw DAXError(.runtime, "bảng đối số của DATEADD không có lineage về cột ngày")
        }
        let meta = try dateColumn(column, store: store)
        var serials: [Double] = []
        serials.reserveCapacity(table.rows.count)
        for row in table.rows {
            serials += try serialList(row[pick], column: meta.name)
        }
        return DateSource(column: column, name: meta.name, serials: serials)
    }

    /// Ngày của cột: dòng đang lặp (nếu row context có dòng của cột) hoặc mọi ngày thấy được trong ngữ cảnh.
    private static func serialsOfColumn(_ id: ColumnID, _ evaluator: Evaluator,
                                        _ ctx: EvalContext) throws(DAXError) -> [Double] {
        if ctx.row != nil {
            for frame in evaluator.rowStack.reversed() {
                switch frame {
                case .base(let table, let row) where table == id.table:
                    let data = try evaluator.columnData(id)
                    return try serialList(Value(stored: data.value(at: row)), column: "\(id)")
                case .virtual(let value, let row):
                    if let index = value.lineageIndex(of: id) {
                        return try serialList(value.rows[row][index], column: "\(id)")
                    }
                default:
                    continue
                }
            }
        }
        let rows = try evaluator.visibleRows(of: id.table, in: ctx)
        let data = try evaluator.columnData(id)
        var out: [Double] = []
        rows.forEach { row in
            if case .dateTime(let d) = data.value(at: row) {
                out.append(d)
            }
        }
        return out
    }

    /// Một giá trị ngày thành mảng serial: BLANK là rỗng, kiểu khác ngày là lỗi.
    private static func serialList(_ value: Value, column: String) throws(DAXError) -> [Double] {
        switch value {
        case .dateTime(let d): return [d]
        case .blank: return []
        default: throw DAXError(.typeMismatch, "cột \(column) có giá trị không phải ngày")
        }
    }

    /// Kiểm tra cột ngày: kiểu dateTime, thuộc bảng được đánh dấu bảng ngày.
    private static func dateColumn(_ id: ColumnID, store: ColumnStore) throws(DAXError) -> ModelSchema.Column {
        guard let table = store.schema.table(id.table), let column = store.schema.column(id) else {
            throw DAXError(.runtime, "không có cột \(id) trong model")
        }
        guard column.type == .dateTime else {
            throw DAXError(.runtime, "\(table.name)[\(column.name)] không phải cột ngày, DATEADD cần cột ngày của bảng ngày")
        }
        guard table.isDateTable else {
            throw DAXError(.runtime, "bảng \(table.name) chưa được đánh dấu bảng ngày (dataCategory = Time), DATEADD không dùng được")
        }
        return column
    }

    /// Số khoảng dịch: số nguyên (BLANK là 0). Số lẻ thì báo lỗi, không làm tròn ngầm.
    private static func intervalCount(_ value: Value) throws(DAXError) -> Int {
        let d = try value.asDouble()
        guard d.isFinite, d == d.rounded(.towardZero), abs(d) <= 1_000_000 else {
            throw DAXError(.typeMismatch, "DATEADD: number_of_intervals phải là số nguyên")
        }
        return Int(d)
    }

    // MARK: - Dịch một ngày

    /// Dịch cả tập ngày cho DATEADD và SAMEPERIODLASTYEAR. Đối chiếu golden Power BI: buổi 1 G1/G3,
    /// buổi 2 T2-time-edges, buổi 3 T5-edges.
    /// - Mỗi ngày dịch riêng, kẹp về cuối tháng đích: 28/02/2017 −1 năm = 28/02/2016; 30/04/2017 −1 tháng = 30/03/2017;
    ///   31/01/2017 +1 tháng = 28/02/2017.
    /// - Tháng nguồn có TỪ HAI ngày được chọn trở lên VÀ có ngày cuối tháng thì thêm mọi ngày còn lại tới hết tháng đích:
    ///   15–28/02/2017 −1 năm = 15–29/02/2016 (15 ngày); 01–28/02/2017 −1 năm = 01–29/02/2016;
    ///   01/03–30/04/2017 −1 tháng = 01/02–31/03/2017 (59 ngày).
    /// - Một ngày cuối tháng đứng một mình thì KHÔNG mở rộng (28/02/2017 −1 năm chỉ cho 28/02/2016).
    /// DAY luôn dịch từng ngày. Kết quả có thể trùng; người gọi khử trùng.
    static func shiftSerials(_ serials: [Double], count: Int, unit: String) throws(DAXError) -> [Double] {
        guard unit != "DAY" else { return try serials.map { s throws(DAXError) in try shiftSerial(s, count: count, unit: unit) } }
        // Số ngày phân biệt đã chọn của từng tháng nguồn (khoá y*12+m-1).
        var daysPerMonth: [Int: Set<Int>] = [:]
        for serial in serials where serial.isFinite && abs(serial) < 1.0e9 {
            let day = Int(serial.rounded(.down))
            let (y, m, _) = tiCivilFromDays(day - tiOLEToUnixDays)
            daysPerMonth[y * 12 + m - 1, default: []].insert(day)
        }
        var out: [Double] = []
        out.reserveCapacity(serials.count)
        for serial in serials {
            guard serial.isFinite, abs(serial) < 1.0e9 else {
                throw DAXError(.runtime, "ngày ngoài phạm vi hỗ trợ")
            }
            let shifted = try shiftSerial(serial, count: count, unit: unit)
            out.append(shifted)
            let day = serial.rounded(.down)
            let (y, m, d) = tiCivilFromDays(Int(day) - tiOLEToUnixDays)
            guard d == tiDaysInMonth(y, m), (daysPerMonth[y * 12 + m - 1]?.count ?? 0) > 1 else { continue }
            // Ngày cuối tháng trong một khoảng nhiều ngày: thêm phần còn lại của tháng đích.
            let fraction = serial - day
            let (ty, tm, td) = tiCivilFromDays(Int(shifted.rounded(.down)) - tiOLEToUnixDays)
            let lastTarget = tiDaysInMonth(ty, tm)
            if td < lastTarget {
                for extra in (td + 1)...lastTarget {
                    out.append(Double(tiDaysFromCivil(ty, tm, extra) + tiOLEToUnixDays) + fraction)
                }
            }
        }
        return out
    }

    /// Dịch một serial OLE theo khoảng, trả một ngày; tháng đích ngắn hơn thì kẹp về ngày cuối tháng đích.
    /// DATEADD và SAMEPERIODLASTYEAR dùng `shiftSerials` (xử lý tháng chọn trọn); hàm này là bước con của nó.
    /// Phần lẻ (giờ trong ngày) giữ nguyên.
    /// Kết quả ngoài 01/01/1900 – 31/12/9999 thì báo lỗi.
    static func shiftSerial(_ serial: Double, count: Int, unit: String) throws(DAXError) -> Double {
        guard serial.isFinite, abs(serial) < 1.0e9 else {
            throw DAXError(.runtime, "ngày ngoài phạm vi hỗ trợ")
        }
        let day = serial.rounded(.down)
        let fraction = serial - day
        let days = Int(day)
        let resultDays: Int
        if unit == "DAY" {
            resultDays = days + count
        } else {
            let monthsPerStep: Int
            switch unit {
            case "MONTH": monthsPerStep = 1
            case "QUARTER": monthsPerStep = 3
            case "YEAR": monthsPerStep = 12
            default: throw DAXError(.typeMismatch, "DATEADD: khoảng \(unit) không được hỗ trợ")
            }
            let (y, m, d) = tiCivilFromDays(days - tiOLEToUnixDays)
            let total = y * 12 + (m - 1) + count * monthsPerStep
            let targetYear = tiFloorDiv(total, 12)
            let targetMonth = total - targetYear * 12 + 1
            let lastTarget = tiDaysInMonth(targetYear, targetMonth)
            let targetDay = min(d, lastTarget)
            resultDays = tiDaysFromCivil(targetYear, targetMonth, targetDay) + tiOLEToUnixDays
        }
        guard resultDays >= 1, resultDays <= tiMaxOLEDay else {
            throw DAXError(.runtime, "DATEADD: ngày kết quả nằm ngoài 1900–9999")
        }
        return Double(resultDays) + fraction
    }
}

// MARK: - Lịch (private, chỉ dùng trong file này)

/// Serial OLE của 1970-01-01 (ngày 0 là 1899-12-30).
private let tiOLEToUnixDays = 25_569
/// Serial OLE của 31/12/9999.
private let tiMaxOLEDay = 2_958_465

/// Chia lấy sàn cho số nguyên dương.
private func tiFloorDiv(_ a: Int, _ b: Int) -> Int {
    let q = a / b
    return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
}

private func tiIsLeap(_ year: Int) -> Bool {
    (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
}

private func tiDaysInMonth(_ year: Int, _ month: Int) -> Int {
    switch month {
    case 2: return tiIsLeap(year) ? 29 : 28
    case 4, 6, 9, 11: return 30
    default: return 31
    }
}

/// Năm, tháng, ngày từ số ngày kể từ 1970-01-01 (lịch Gregorian, thuật toán của H. Hinnant).
private func tiCivilFromDays(_ unixDays: Int) -> (Int, Int, Int) {
    let z = unixDays + 719_468
    let era = (z >= 0 ? z : z - 146_096) / 146_097
    let doe = z - era * 146_097
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
    let mp = (5 * doy + 2) / 153
    let d = doy - (153 * mp + 2) / 5 + 1
    let m = mp < 10 ? mp + 3 : mp - 9
    let y = yoe + era * 400 + (m <= 2 ? 1 : 0)
    return (y, m, d)
}

/// Số ngày kể từ 1970-01-01 tới (năm, tháng, ngày) (nghịch đảo của `tiCivilFromDays`).
private func tiDaysFromCivil(_ year: Int, _ month: Int, _ day: Int) -> Int {
    let y = month <= 2 ? year - 1 : year
    let era = (y >= 0 ? y : y - 399) / 400
    let yoe = y - era * 400
    let mp = month > 2 ? month - 3 : month + 9
    let doy = (153 * mp + 2) / 5 + day - 1
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
    return era * 146_097 + doe - 719_468
}
