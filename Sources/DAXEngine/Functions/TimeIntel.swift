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
import PBIXKit
import ColumnStore

public enum TimeIntelligenceFunctions: FunctionFamily {
    public static let functions: [FunctionSpec] = [
        FunctionSpec(name: "SAMEPERIODLASTYEAR", params: [.table("dates")],
                     impl: .table(TimeIntelligenceFunctions.samePeriodLastYearBody)),
        FunctionSpec(name: "DATEADD",
                     params: [.table("dates"), .scalar("number_of_intervals"),
                              .keyword("interval", ["DAY", "MONTH", "QUARTER", "YEAR"])],
                     impl: .table(TimeIntelligenceFunctions.dateAddBody)),
        // Wave 3 (v1.1b — đối chiếu 100% VM-V11B dax-golden.json)
        FunctionSpec(name: "DATESYTD", params: [.table("dates"), .scalar("year_end_date", optional: true)],
                     impl: .table(TimeIntelligenceFunctions.datesYTDBody)),
        FunctionSpec(name: "DATESQTD", params: [.table("dates")],
                     impl: .table(TimeIntelligenceFunctions.datesQTDBody)),
        FunctionSpec(name: "DATESMTD", params: [.table("dates")],
                     impl: .table(TimeIntelligenceFunctions.datesMTDBody)),
        FunctionSpec(name: "TOTALYTD", params: [.lazy("expression"), .table("dates"), .filter("filter", optional: true, repeats: true)],
                     impl: .scalar(TimeIntelligenceFunctions.totalYTDBody)),
        FunctionSpec(name: "TOTALQTD", params: [.lazy("expression"), .table("dates"), .filter("filter", optional: true, repeats: true)],
                     impl: .scalar(TimeIntelligenceFunctions.totalQTDBody)),
        FunctionSpec(name: "TOTALMTD", params: [.lazy("expression"), .table("dates"), .filter("filter", optional: true, repeats: true)],
                     impl: .scalar(TimeIntelligenceFunctions.totalMTDBody)),
        FunctionSpec(name: "DATESBETWEEN", params: [.table("dates"), .scalar("start_date"), .scalar("end_date")],
                     impl: .table(TimeIntelligenceFunctions.datesBetweenBody)),
        FunctionSpec(name: "DATESINPERIOD",
                     params: [.table("dates"), .scalar("start_date"), .scalar("number_of_intervals"),
                              .keyword("interval", ["DAY", "MONTH", "QUARTER", "YEAR"])],
                     impl: .table(TimeIntelligenceFunctions.datesInPeriodBody)),
        FunctionSpec(name: "PREVIOUSDAY", params: [.table("dates")], impl: .table(TimeIntelligenceFunctions.periodShiftBody(prev: true, unit: "DAY"))),
        FunctionSpec(name: "PREVIOUSMONTH", params: [.table("dates")], impl: .table(TimeIntelligenceFunctions.periodShiftBody(prev: true, unit: "MONTH"))),
        FunctionSpec(name: "PREVIOUSQUARTER", params: [.table("dates")], impl: .table(TimeIntelligenceFunctions.periodShiftBody(prev: true, unit: "QUARTER"))),
        FunctionSpec(name: "PREVIOUSYEAR", params: [.table("dates"), .scalar("year_end_date", optional: true)], impl: .table(TimeIntelligenceFunctions.periodShiftBody(prev: true, unit: "YEAR"))),
        FunctionSpec(name: "NEXTDAY", params: [.table("dates")], impl: .table(TimeIntelligenceFunctions.periodShiftBody(prev: false, unit: "DAY"))),
        FunctionSpec(name: "NEXTMONTH", params: [.table("dates")], impl: .table(TimeIntelligenceFunctions.periodShiftBody(prev: false, unit: "MONTH"))),
        FunctionSpec(name: "NEXTQUARTER", params: [.table("dates")], impl: .table(TimeIntelligenceFunctions.periodShiftBody(prev: false, unit: "QUARTER"))),
        FunctionSpec(name: "NEXTYEAR", params: [.table("dates"), .scalar("year_end_date", optional: true)], impl: .table(TimeIntelligenceFunctions.periodShiftBody(prev: false, unit: "YEAR"))),
        FunctionSpec(name: "PARALLELPERIOD",
                     params: [.table("dates"), .scalar("number_of_intervals"),
                              .keyword("interval", ["MONTH", "QUARTER", "YEAR"])],
                     impl: .table(TimeIntelligenceFunctions.parallelPeriodBody)),
        FunctionSpec(name: "STARTOFMONTH", params: [.table("dates")], impl: .table(TimeIntelligenceFunctions.boundaryBody(start: true, unit: "MONTH"))),
        FunctionSpec(name: "ENDOFMONTH", params: [.table("dates")], impl: .table(TimeIntelligenceFunctions.boundaryBody(start: false, unit: "MONTH"))),
        FunctionSpec(name: "STARTOFQUARTER", params: [.table("dates")], impl: .table(TimeIntelligenceFunctions.boundaryBody(start: true, unit: "QUARTER"))),
        FunctionSpec(name: "ENDOFQUARTER", params: [.table("dates")], impl: .table(TimeIntelligenceFunctions.boundaryBody(start: false, unit: "QUARTER"))),
        FunctionSpec(name: "STARTOFYEAR", params: [.table("dates"), .scalar("year_end_date", optional: true)], impl: .table(TimeIntelligenceFunctions.boundaryBody(start: true, unit: "YEAR"))),
        FunctionSpec(name: "ENDOFYEAR", params: [.table("dates"), .scalar("year_end_date", optional: true)], impl: .table(TimeIntelligenceFunctions.boundaryBody(start: false, unit: "YEAR"))),
    ]

    // MARK: - Thân hàm

    static func samePeriodLastYearBody(_ frame: CallFrame) throws(DAXError) -> TableValue {
        try shiftedDates(frame, count: -1, unit: "YEAR")
    }

    static func dateAddBody(_ frame: CallFrame) throws(DAXError) -> TableValue {
        guard let unit = frame.keyword(2) else {
            throw DAXError(.typeMismatch, lt("DATEADD: đối số 3 phải là DAY, MONTH, QUARTER hoặc YEAR", "DATEADD: argument 3 must be DAY, MONTH, QUARTER or YEAR"))
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
            throw DAXError(.runtime, lt("hàm này cần Evaluator của CORE", "this function needs the CORE evaluator"))
        }
        guard let expr = frame.args.first ?? nil else {
            throw DAXError(.arity, lt("DATEADD và SAMEPERIODLASTYEAR cần đối số ngày", "DATEADD and SAMEPERIODLASTYEAR need a date argument"))
        }
        switch expr {
        case .column(let id):
            let column = try dateColumn(id, store: evaluator.store)
            return DateSource(column: id, name: column.name,
                              serials: try serialsOfColumn(id, evaluator, frame.ctx))
        case .table(let id):
            let name = evaluator.store.schema.table(id)?.name ?? "\(id)"
            throw DAXError(.runtime, lt("đối số ngày của DATEADD phải là một cột ngày, không phải cả bảng \(name)", "the date argument of DATEADD must be a date column, not the whole table \(name)"))
        case .variable(let slot):
            switch try evaluator.lookupVariable(slot) {
            case .table(let value):
                return try dateSource(of: value, store: evaluator.store)
            case .rows:
                throw DAXError(.runtime, lt("đối số ngày của DATEADD phải là một cột ngày, không phải cả bảng", "the date argument of DATEADD must be a date column, not a whole table"))
            case .scalar:
                throw DAXError(.typeMismatch, lt("đối số ngày của DATEADD không phải bảng hay cột", "the date argument of DATEADD is neither a table nor a column"))
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
                throw DAXError(.runtime, lt("bảng đối số của DATEADD có \(candidates.count) cột ngày, cần đúng một", "the table argument of DATEADD has \(candidates.count) date columns; exactly one is required"))
            }
            pick = only
        }
        guard let column = table.lineage[pick] else {
            throw DAXError(.runtime, lt("bảng đối số của DATEADD không có lineage về cột ngày", "the table argument of DATEADD has no lineage to a date column"))
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
        default: throw DAXError(.typeMismatch, lt("cột \(column) có giá trị không phải ngày", "column \(column) has values that aren't dates"))
        }
    }

    /// Kiểm tra cột ngày: kiểu dateTime, thuộc bảng được đánh dấu bảng ngày.
    private static func dateColumn(_ id: ColumnID, store: ColumnStore) throws(DAXError) -> ModelSchema.Column {
        guard let table = store.schema.table(id.table), let column = store.schema.column(id) else {
            throw DAXError(.runtime, lt("không có cột \(id) trong model", "there is no column \(id) in the model"))
        }
        guard column.type == .dateTime else {
            throw DAXError(.runtime, lt("\(table.name)[\(column.name)] không phải cột ngày, DATEADD cần cột ngày của bảng ngày", "\(table.name)[\(column.name)] isn't a date column; DATEADD needs a date column of a date table"))
        }
        guard table.isDateTable else {
            throw DAXError(.runtime, lt("bảng \(table.name) chưa được đánh dấu bảng ngày (dataCategory = Time), DATEADD không dùng được", "table \(table.name) isn't marked as a date table (dataCategory = Time), so DATEADD can't be used"))
        }
        return column
    }

    /// Số khoảng dịch: số nguyên (BLANK là 0). Số lẻ thì báo lỗi, không làm tròn ngầm.
    private static func intervalCount(_ value: Value) throws(DAXError) -> Int {
        let d = try value.asDouble()
        guard d.isFinite, d == d.rounded(.towardZero), abs(d) <= 1_000_000 else {
            throw DAXError(.typeMismatch, lt("DATEADD: number_of_intervals phải là số nguyên", "DATEADD: number_of_intervals must be an integer"))
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
                throw DAXError(.runtime, lt("ngày ngoài phạm vi hỗ trợ", "the date is outside the supported range"))
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
            throw DAXError(.runtime, lt("ngày ngoài phạm vi hỗ trợ", "the date is outside the supported range"))
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
            default: throw DAXError(.typeMismatch, lt("DATEADD: khoảng \(unit) không được hỗ trợ", "DATEADD: the interval \(unit) isn't supported"))
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
            throw DAXError(.runtime, lt("DATEADD: ngày kết quả nằm ngoài 1900–9999", "DATEADD: the resulting date is outside 1900–9999"))
        }
        return Double(resultDays) + fraction
    }

    // MARK: - Wave 3 (v1.1b) Time Intelligence

    /// Đọc toàn bộ các ngày (đã lọc bỏ BLANK, làm tròn ngày) của cột ngày trong store (bỏ qua bộ lọc hiện tại).
    private static func allColumnSerials(_ column: ColumnID, evaluator: Evaluator) throws(DAXError) -> [Double] {
        let data = try evaluator.columnData(column)
        var seen = Set<Int>()
        var out: [Double] = []
        out.reserveCapacity(data.rowCount)
        for r in 0..<data.rowCount {
            if case .dateTime(let d) = data.value(at: r), d.isFinite {
                let day = Int(d.rounded(.down))
                if seen.insert(day).inserted { out.append(Double(day)) }
            }
        }
        out.sort()
        return out
    }

    /// Phân tích chuỗi `year_end_date` kiểu `"6/30"`, `"06-30"`, `"31/12"` → (month, day). Mặc định (12, 31).
    private static func parseYearEndDate(_ value: Value?) throws(DAXError) -> (month: Int, day: Int) {
        guard let value, !value.isBlank else { return (12, 31) }
        func trimWS(_ s: Substring) -> String {
            var lo = s.startIndex, hi = s.endIndex
            while lo < hi && (s[lo] == " " || s[lo] == "\t" || s[lo] == "\n" || s[lo] == "\r") { lo = s.index(after: lo) }
            while hi > lo {
                let prev = s.index(before: hi)
                if s[prev] == " " || s[prev] == "\t" || s[prev] == "\n" || s[prev] == "\r" { hi = prev } else { break }
            }
            return String(s[lo..<hi])
        }
        let raw = trimWS(value.asText()[...])
        guard !raw.isEmpty else { return (12, 31) }
        var parts: [Int] = []
        for piece in raw.split(whereSeparator: { $0 == "/" || $0 == "-" || $0 == "." }) {
            if let num = Int(trimWS(piece)) { parts.append(num) }
        }
        guard parts.count >= 2 else {
            throw DAXError(.runtime, lt("year_end_date '\(raw)' không hợp lệ (cần dạng M/D như \"6/30\")", "year_end_date '\(raw)' isn't valid (expected the form M/D, such as \"6/30\")"))
        }
        let a = parts[0], b = parts[1]
        if (1...12).contains(a) && (1...31).contains(b) { return (a, b) }
        if (1...12).contains(b) && (1...31).contains(a) { return (b, a) }
        throw DAXError(.runtime, lt("year_end_date '\(raw)' không hợp lệ", "year_end_date '\(raw)' isn't valid"))
    }

    /// Trả bảng 1 cột có lineage chứa các ngày của cột nằm trong `[loDay, hiDay]` (serial OLE nguyên).
    private static func datesInRange(_ source: DateSource, loDay: Int, hiDay: Int, evaluator: Evaluator) throws(DAXError) -> TableValue {
        let all = try allColumnSerials(source.column, evaluator: evaluator)
        var picked: [Value] = []
        for s in all {
            let day = Int(s)
            if day >= loDay && day <= hiDay { picked.append(.dateTime(s)) }
        }
        return TableValue.values(of: source.column, name: source.name, values: picked)
    }

    private static func dateRangeTable(source: DateSource, kind: String, yearEnd: (month: Int, day: Int), evaluator: Evaluator) throws(DAXError) -> TableValue {
        guard let maxSerial = source.serials.max() else {
            return TableValue.values(of: source.column, name: source.name, values: [])
        }
        let maxDay = Int(maxSerial.rounded(.down))
        let (y, m, _) = tiCivilFromDays(maxDay - tiOLEToUnixDays)
        let loDay: Int
        switch kind {
        case "MTD":
            loDay = tiDaysFromCivil(y, m, 1) + tiOLEToUnixDays
        case "QTD":
            let qStartMonth = ((m - 1) / 3) * 3 + 1
            loDay = tiDaysFromCivil(y, qStartMonth, 1) + tiOLEToUnixDays
        case "YTD":
            let fyEndDay = min(yearEnd.day, tiDaysInMonth(y, yearEnd.month))
            let fyEndThisYear = tiDaysFromCivil(y, yearEnd.month, fyEndDay) + tiOLEToUnixDays
            if maxDay > fyEndThisYear {
                loDay = fyEndThisYear + 1
            } else {
                let prevEndDay = min(yearEnd.day, tiDaysInMonth(y - 1, yearEnd.month))
                loDay = tiDaysFromCivil(y - 1, yearEnd.month, prevEndDay) + tiOLEToUnixDays + 1
            }
        default:
            loDay = maxDay
        }
        return try datesInRange(source, loDay: loDay, hiDay: maxDay, evaluator: evaluator)
    }

    static func datesYTDBody(_ frame: CallFrame) throws(DAXError) -> TableValue {
        let evaluator = try fkEvaluator(frame)
        let source = try dateSource(frame)
        let ye = frame.isBlankArgument(1) ? (12, 31) : try parseYearEndDate(try frame.scalar(1))
        return try dateRangeTable(source: source, kind: "YTD", yearEnd: ye, evaluator: evaluator)
    }

    static func datesQTDBody(_ frame: CallFrame) throws(DAXError) -> TableValue {
        let evaluator = try fkEvaluator(frame)
        return try dateRangeTable(source: try dateSource(frame), kind: "QTD", yearEnd: (12, 31), evaluator: evaluator)
    }

    static func datesMTDBody(_ frame: CallFrame) throws(DAXError) -> TableValue {
        let evaluator = try fkEvaluator(frame)
        return try dateRangeTable(source: try dateSource(frame), kind: "MTD", yearEnd: (12, 31), evaluator: evaluator)
    }

    private static func totalToDateBody(_ frame: CallFrame, kind: String) throws(DAXError) -> Value {
        let evaluator = try fkEvaluator(frame)
        guard let expr = frame.args[0], let datesExpr = frame.args[1] else {
            throw DAXError(.arity, lt("TOTAL\(kind) cần biểu thức và cột ngày", "TOTAL\(kind) needs an expression and a date column"))
        }
        var extraFilters: [BoundExpr?] = []
        var yearEnd: (month: Int, day: Int) = (12, 31)
        let tail = Array(frame.args.dropFirst(2))
        if kind == "YTD", let last = tail.last ?? nil, case .literal(.string) = last {
            yearEnd = try parseYearEndDate(try evaluator.scalar(last, in: frame.ctx))
            extraFilters = Array(tail.dropLast())
        } else {
            extraFilters = tail
        }
        // Tính ngữ cảnh bộ lọc phụ trước (nếu có) rồi tính tập ngày to-date trong ngữ cảnh đó
        let preCtx = extraFilters.isEmpty ? frame.ctx : try evaluator.calculatedContext(extraFilters, frame.ctx)
        let datesFrame = CallFrame(args: [datesExpr], ctx: preCtx, eval: evaluator)
        let dateTable = try dateRangeTable(source: try dateSource(datesFrame), kind: kind, yearEnd: yearEnd, evaluator: evaluator)
        let col = dateTable.lineage[0]!
        let values = dateTable.rows.map { $0[0] }
        var filter = preCtx.filter
        if preCtx.row != nil { filter = try evaluator.transitioned(filter) }
        filter = filter.clearingTable(col.table).applying(FilterItem(column: col, values: values), keep: true)
        return try evaluator.scalar(expr, in: EvalContext(filter: filter, row: preCtx.row))
    }

    static func totalYTDBody(_ frame: CallFrame) throws(DAXError) -> Value { try totalToDateBody(frame, kind: "YTD") }
    static func totalQTDBody(_ frame: CallFrame) throws(DAXError) -> Value { try totalToDateBody(frame, kind: "QTD") }
    static func totalMTDBody(_ frame: CallFrame) throws(DAXError) -> Value { try totalToDateBody(frame, kind: "MTD") }

    static func datesBetweenBody(_ frame: CallFrame) throws(DAXError) -> TableValue {
        let evaluator = try fkEvaluator(frame)
        let source = try dateSource(frame)
        let all = try allColumnSerials(source.column, evaluator: evaluator)
        guard let minAll = all.first, let maxAll = all.last else {
            return TableValue.values(of: source.column, name: source.name, values: [])
        }
        let startVal = try frame.scalar(1)
        let endVal = try frame.scalar(2)
        let lo = startVal.isBlank ? Int(minAll) : Int((try startVal.asDouble()).rounded(.down))
        let hi = endVal.isBlank ? Int(maxAll) : Int((try endVal.asDouble()).rounded(.down))
        return try datesInRange(source, loDay: lo, hiDay: hi, evaluator: evaluator)
    }

    static func datesInPeriodBody(_ frame: CallFrame) throws(DAXError) -> TableValue {
        let evaluator = try fkEvaluator(frame)
        let source = try dateSource(frame)
        let startVal = try frame.scalar(1)
        if startVal.isBlank { return TableValue.values(of: source.column, name: source.name, values: []) }
        let startSerial = (try startVal.asDouble()).rounded(.down)
        let n = try intervalCount(try frame.scalar(2))
        guard let unit = frame.keyword(3)?.uppercased() else {
            throw DAXError(.typeMismatch, lt("DATESINPERIOD: interval phải là DAY, MONTH, QUARTER hoặc YEAR", "DATESINPERIOD: interval must be DAY, MONTH, QUARTER or YEAR"))
        }
        if n == 0 { return TableValue.values(of: source.column, name: source.name, values: []) }
        let startDay = Int(startSerial)
        let loDay: Int
        let hiDay: Int
        if n > 0 {
            let shifted = Int((try shiftSerial(startSerial, count: n, unit: unit)).rounded(.down))
            loDay = startDay
            hiDay = shifted - 1
        } else {
            let (sy, sm, sd) = tiCivilFromDays(startDay - tiOLEToUnixDays)
            let isEndOfMonth = (sd == tiDaysInMonth(sy, sm))
            if unit != "DAY" && isEndOfMonth {
                // Nếu start là ngày cuối tháng (vd 2018-03-31, -3 MONTH → 2018-01-01..2018-03-31, VM-V11B)
                let months = n * (unit == "MONTH" ? 1 : unit == "QUARTER" ? 3 : 12)
                let total = sy * 12 + (sm - 1) + months + 1
                let ty = tiFloorDiv(total, 12)
                let tm = total - ty * 12 + 1
                loDay = tiDaysFromCivil(ty, tm, 1) + tiOLEToUnixDays
            } else {
                let shifted = Int((try shiftSerial(startSerial, count: n, unit: unit)).rounded(.down))
                loDay = shifted + 1
            }
            hiDay = startDay
        }
        return try datesInRange(source, loDay: loDay, hiDay: hiDay, evaluator: evaluator)
    }

    private static func periodShiftBody(prev: Bool, unit: String) -> FunctionSpec.TableBody {
        return { (frame: CallFrame) throws(DAXError) -> TableValue in
            let evaluator = try fkEvaluator(frame)
            let source = try dateSource(frame)
            guard let anchor = prev ? source.serials.min() : source.serials.max() else {
                return TableValue.values(of: source.column, name: source.name, values: [])
            }
            let day = Int(anchor.rounded(.down))
            let (y, m, _) = tiCivilFromDays(day - tiOLEToUnixDays)
            let loDay: Int
            let hiDay: Int
            switch unit {
            case "DAY":
                let target = day + (prev ? -1 : 1)
                loDay = target; hiDay = target
            case "MONTH":
                let total = y * 12 + (m - 1) + (prev ? -1 : 1)
                let ty = tiFloorDiv(total, 12), tm = total - ty * 12 + 1
                loDay = tiDaysFromCivil(ty, tm, 1) + tiOLEToUnixDays
                hiDay = tiDaysFromCivil(ty, tm, tiDaysInMonth(ty, tm)) + tiOLEToUnixDays
            case "QUARTER":
                let q = (m - 1) / 3 + (prev ? -1 : 1)
                let totalQ = y * 4 + q
                let ty = tiFloorDiv(totalQ, 4), tq = totalQ - ty * 4
                let m1 = tq * 3 + 1, m3 = m1 + 2
                loDay = tiDaysFromCivil(ty, m1, 1) + tiOLEToUnixDays
                hiDay = tiDaysFromCivil(ty, m3, tiDaysInMonth(ty, m3)) + tiOLEToUnixDays
            case "YEAR":
                let ty = y + (prev ? -1 : 1)
                loDay = tiDaysFromCivil(ty, 1, 1) + tiOLEToUnixDays
                hiDay = tiDaysFromCivil(ty, 12, 31) + tiOLEToUnixDays
            default:
                loDay = day; hiDay = day
            }
            return try datesInRange(source, loDay: loDay, hiDay: hiDay, evaluator: evaluator)
        }
    }

    static func parallelPeriodBody(_ frame: CallFrame) throws(DAXError) -> TableValue {
        let evaluator = try fkEvaluator(frame)
        let source = try dateSource(frame)
        guard let minS = source.serials.min(), let maxS = source.serials.max() else {
            return TableValue.values(of: source.column, name: source.name, values: [])
        }
        let n = try intervalCount(try frame.scalar(1))
        guard let unit = frame.keyword(2)?.uppercased() else {
            throw DAXError(.typeMismatch, lt("PARALLELPERIOD: interval phải là MONTH, QUARTER hoặc YEAR", "PARALLELPERIOD: interval must be MONTH, QUARTER or YEAR"))
        }
        let (y1, m1, _) = tiCivilFromDays(Int(minS.rounded(.down)) - tiOLEToUnixDays)
        let (y2, m2, _) = tiCivilFromDays(Int(maxS.rounded(.down)) - tiOLEToUnixDays)
        let loDay: Int
        let hiDay: Int
        switch unit {
        case "MONTH":
            let t1 = y1 * 12 + (m1 - 1) + n
            let t2 = y2 * 12 + (m2 - 1) + n
            let ty1 = tiFloorDiv(t1, 12), tm1 = t1 - ty1 * 12 + 1
            let ty2 = tiFloorDiv(t2, 12), tm2 = t2 - ty2 * 12 + 1
            loDay = tiDaysFromCivil(ty1, tm1, 1) + tiOLEToUnixDays
            hiDay = tiDaysFromCivil(ty2, tm2, tiDaysInMonth(ty2, tm2)) + tiOLEToUnixDays
        case "QUARTER":
            let q1 = y1 * 4 + (m1 - 1) / 3 + n
            let q2 = y2 * 4 + (m2 - 1) / 3 + n
            let ty1 = tiFloorDiv(q1, 4), tm1 = (q1 - ty1 * 4) * 3 + 1
            let ty2 = tiFloorDiv(q2, 4), tm2 = (q2 - ty2 * 4) * 3 + 3
            loDay = tiDaysFromCivil(ty1, tm1, 1) + tiOLEToUnixDays
            hiDay = tiDaysFromCivil(ty2, tm2, tiDaysInMonth(ty2, tm2)) + tiOLEToUnixDays
        case "YEAR":
            loDay = tiDaysFromCivil(y1 + n, 1, 1) + tiOLEToUnixDays
            hiDay = tiDaysFromCivil(y2 + n, 12, 31) + tiOLEToUnixDays
        default:
            throw DAXError(.typeMismatch, lt("PARALLELPERIOD: interval \(unit) không hỗ trợ", "PARALLELPERIOD: the interval \(unit) isn't supported"))
        }
        return try datesInRange(source, loDay: loDay, hiDay: hiDay, evaluator: evaluator)
    }

    /// STARTOF* / ENDOF*: mở rộng ra đầu/cuối kỳ lịch (tháng/quý/năm) tương ứng rồi chọn ngày nhỏ nhất / lớn nhất có trong cột ngày (VM-V11B).
    private static func boundaryBody(start: Bool, unit: String) -> FunctionSpec.TableBody {
        return { (frame: CallFrame) throws(DAXError) -> TableValue in
            let evaluator = try fkEvaluator(frame)
            let source = try dateSource(frame)
            guard let anchor = start ? source.serials.min() : source.serials.max() else {
                return TableValue.values(of: source.column, name: source.name, values: [])
            }
            let (y, m, _) = tiCivilFromDays(Int(anchor.rounded(.down)) - tiOLEToUnixDays)
            let loDay: Int
            let hiDay: Int
            switch unit {
            case "MONTH":
                loDay = tiDaysFromCivil(y, m, 1) + tiOLEToUnixDays
                hiDay = tiDaysFromCivil(y, m, tiDaysInMonth(y, m)) + tiOLEToUnixDays
            case "QUARTER":
                let qm = ((m - 1) / 3) * 3 + 1
                loDay = tiDaysFromCivil(y, qm, 1) + tiOLEToUnixDays
                hiDay = tiDaysFromCivil(y, qm + 2, tiDaysInMonth(y, qm + 2)) + tiOLEToUnixDays
            case "YEAR":
                loDay = tiDaysFromCivil(y, 1, 1) + tiOLEToUnixDays
                hiDay = tiDaysFromCivil(y, 12, 31) + tiOLEToUnixDays
            default:
                loDay = Int(anchor.rounded(.down)); hiDay = loDay
            }
            let inPeriod = try datesInRange(source, loDay: loDay, hiDay: hiDay, evaluator: evaluator)
            guard let chosen = start ? inPeriod.rows.first : inPeriod.rows.last else {
                return TableValue.values(of: source.column, name: source.name, values: [])
            }
            return TableValue.values(of: source.column, name: source.name, values: [chosen[0]])
        }
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
