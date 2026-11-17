// Phase F: Thư viện hàm M nhóm Date.
import Foundation
import ColumnStore

enum ValueDateHelper {
    static func civilFromSerial(_ serial: Double) -> (year: Int, month: Int, day: Int) {
        // Ngày ngoài phạm vi (vô cực, NaN) không được làm sập app: kẹp về khoảng hợp lệ của M (năm 1–9999).
        let z = Int(floor(serial.isFinite ? min(max(serial, -693_593), 2_958_465) : 0)) + 693_899
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        let year = m <= 2 ? y + 1 : y
        return (year, m, d)
    }

    static func parseDateString(_ s: String) -> Double? {
        // Hỗ trợ YYYY-MM-DD hoặc YYYY/MM/DD
        let parts = s.split(whereSeparator: { $0 == "-" || $0 == "/" })
        guard parts.count >= 3,
              let y = Int(parts[0]),
              let m = Int(parts[1]),
              let d = Int(parts[2].prefix(2)) else {
            return nil
        }
        return MDates.serial(year: y, month: m, day: d)
    }
}

enum ValueDate {
    static let functions: [MFunction] = [
        // [SUY ĐOÁN]
        MFunction(
            name: "Date.Year",
            parameters: [MParameter(name: "dateTime")],
            observed: false
        ) { args in
            switch args[0] {
            case .null: return .null
            case .date(let d), .dateTime(let d):
                let civil = ValueDateHelper.civilFromSerial(d)
                return .number(Double(civil.year))
            default:
                throw MError.expression("Date.Year: đối số 1 phải là date hoặc datetime, nhận \(args[0].kindName)")
            }
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "Date.Month",
            parameters: [MParameter(name: "dateTime")],
            observed: false
        ) { args in
            switch args[0] {
            case .null: return .null
            case .date(let d), .dateTime(let d):
                let civil = ValueDateHelper.civilFromSerial(d)
                return .number(Double(civil.month))
            default:
                throw MError.expression("Date.Month: đối số 1 phải là date hoặc datetime, nhận \(args[0].kindName)")
            }
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "Date.Day",
            parameters: [MParameter(name: "dateTime")],
            observed: false
        ) { args in
            switch args[0] {
            case .null: return .null
            case .date(let d), .dateTime(let d):
                let civil = ValueDateHelper.civilFromSerial(d)
                return .number(Double(civil.day))
            default:
                throw MError.expression("Date.Day: đối số 1 phải là date hoặc datetime, nhận \(args[0].kindName)")
            }
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "Date.From",
            parameters: [MParameter(name: "value"), MParameter(name: "culture", isOptional: true)],
            observed: false
        ) { args in
            switch args[0] {
            case .null: return .null
            case .date(let d): return .date(d)
            case .dateTime(let d): return .date(floor(d))
            case .text(let s):
                guard let serial = ValueDateHelper.parseDateString(s) else {
                    throw MError.expression("DataFormat.Error: Không thể chuyển '\(s)' sang Date")
                }
                return .date(serial)
            default:
                throw MError.expression("Date.From: chưa hỗ trợ chuyển đổi từ kiểu \(args[0].kindName)")
            }
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "Date.AddDays",
            parameters: [MParameter(name: "dateTime"), MParameter(name: "numberOfDays")],
            observed: false
        ) { args in
            if case .null = args[0] { return .null }
            let days = try args.number(1, "Date.AddDays")
            switch args[0] {
            case .date(let d): return .date(d + days)
            case .dateTime(let d): return .dateTime(d + days)
            default:
                throw MError.expression("Date.AddDays: đối số 1 phải là date hoặc datetime, nhận \(args[0].kindName)")
            }
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "Date.AddMonths",
            parameters: [MParameter(name: "dateTime"), MParameter(name: "numberOfMonths")],
            observed: false
        ) { args in
            if case .null = args[0] { return .null }
            let deltaMonths = try MInt.from(args.number(1, "Date.AddMonths"), "Date.AddMonths")
            let d: Double
            let isDateTime: Bool
            let timeFraction: Double
            switch args[0] {
            case .date(let val):
                d = val
                isDateTime = false
                timeFraction = 0
            case .dateTime(let val):
                d = floor(val)
                isDateTime = true
                timeFraction = val - d
            default:
                throw MError.expression("Date.AddMonths: đối số 1 phải là date hoặc datetime, nhận \(args[0].kindName)")
            }

            let civil = ValueDateHelper.civilFromSerial(d)
            let totalMonths = civil.year * 12 + (civil.month - 1) + deltaMonths
            let newYear = totalMonths >= 0 ? totalMonths / 12 : (totalMonths - 11) / 12
            let newMonth = ((totalMonths % 12) + 12) % 12 + 1
            let maxDay = MDates.daysInMonth(year: newYear, month: newMonth)
            let newDay = min(civil.day, maxDay)
            guard let newSerial = MDates.serial(year: newYear, month: newMonth, day: newDay) else {
                throw MError.expression("Date.AddMonths: tính ngày mới không thành công")
            }
            return isDateTime ? .dateTime(newSerial + timeFraction) : .date(newSerial)
        },

        // [SUY ĐOÁN]
        MFunction(
            name: "Date.DayOfWeek",
            parameters: [MParameter(name: "dateTime"), MParameter(name: "firstDayOfWeek", isOptional: true)],
            observed: false
        ) { args in
            if case .null = args[0] { return .null }
            let d: Double
            switch args[0] {
            case .date(let val): d = val
            case .dateTime(let val): d = floor(val)
            default:
                throw MError.expression("Date.DayOfWeek: đối số 1 phải là date hoặc datetime, nhận \(args[0].kindName)")
            }
            // 1899-12-30 (serial 0) là Thứ Bảy (Saturday = 6). Sunday = 0, Monday = 1, ..., Saturday = 6.
            let serialInt = try MInt.from(floor(d), "Date.DayOfWeek")
            let sundayZeroDOW = ((serialInt + 6) % 7 + 7) % 7
            let firstDay = try args.optional(1).map { v -> Int in
                guard let n = MOperators.number(v) else { throw MError.expression("Date.DayOfWeek: firstDayOfWeek phải là số") }
                return try MInt.from(n, "Date.DayOfWeek")
            } ?? 0
            let adjusted = ((sundayZeroDOW - firstDay) % 7 + 7) % 7
            return .number(Double(adjusted))
        }
    ]
}
