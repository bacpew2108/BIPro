// Phase F: Trợ giúp chuyển đổi kiểu cột cho Table.TransformColumnTypes.
import Foundation
import ColumnStore

enum TableColumnsTypesHelper {
    static func transformColumn(
        col: TableColumn,
        colIdx: Int,
        targetType: MType,
        table: TableData,
        newErrorMask: inout [Int: [Int: String]]
    ) throws -> TableColumn {
        let rowCount = table.rowCount
        let existingErrors = table.errorMask[colIdx] ?? [:]
        var colErrors: [Int: String] = existingErrors

        let newColumnData: ColumnData

        switch targetType.kind {
        case .int64, .int32, .int16, .int8:
            var vals: [Int64?] = []
            vals.reserveCapacity(rowCount)
            for r in 0..<rowCount {
                if let _ = existingErrors[r] {
                    vals.append(nil)
                    continue
                }
                let cell = MTables.cell(table, row: r, column: colIdx)
                switch cell {
                case .null:
                    vals.append(nil)
                case .number(let d):
                    if d == d.rounded() && abs(d) < 9.2e18 {
                        vals.append(Int64(d))
                    } else {
                        colErrors[r] = "DataFormat.Error: We couldn't convert to Number. Details: \(d)"
                        vals.append(nil)
                    }
                case .currency(let c):
                    let d = Double(c) / 10_000
                    if d == d.rounded() && abs(d) < 9.2e18 {
                        vals.append(Int64(d))
                    } else {
                        colErrors[r] = "DataFormat.Error: We couldn't convert to Number. Details: \(d)"
                        vals.append(nil)
                    }
                case .logical(let b):
                    vals.append(b ? 1 : 0)
                case .text(let s):
                    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        vals.append(nil)
                    } else {
                        let cleaned = trimmed.replacingOccurrences(of: ",", with: "")
                        if let d = Double(cleaned), d == d.rounded() && abs(d) < 9.2e18 {
                            vals.append(Int64(d))
                        } else {
                            colErrors[r] = "DataFormat.Error: We couldn't convert to Number. Details: \(s)"
                            vals.append(nil)
                        }
                    }
                case .date(let d), .dateTime(let d):
                    vals.append(Int64(d.rounded()))
                default:
                    colErrors[r] = "DataFormat.Error: We couldn't convert to Number. Details: \(cell.kindName)"
                    vals.append(nil)
                }
            }
            newColumnData = ColumnBuilder.integers(vals)

        case .number, .double, .decimal, .percentage:
            var vals: [Double?] = []
            vals.reserveCapacity(rowCount)
            for r in 0..<rowCount {
                if let _ = existingErrors[r] {
                    vals.append(nil)
                    continue
                }
                let cell = MTables.cell(table, row: r, column: colIdx)
                switch cell {
                case .null:
                    vals.append(nil)
                case .number(let d):
                    vals.append(d)
                case .currency(let c):
                    vals.append(Double(c) / 10_000)
                case .logical(let b):
                    vals.append(b ? 1.0 : 0.0)
                case .text(let s):
                    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        vals.append(nil)
                    } else {
                        let cleaned = trimmed.replacingOccurrences(of: ",", with: "")
                        if let d = Double(cleaned) {
                            vals.append(d)
                        } else {
                            colErrors[r] = "DataFormat.Error: We couldn't convert to Number. Details: \(s)"
                            vals.append(nil)
                        }
                    }
                case .date(let d), .dateTime(let d):
                    vals.append(d)
                default:
                    colErrors[r] = "DataFormat.Error: We couldn't convert to Number. Details: \(cell.kindName)"
                    vals.append(nil)
                }
            }
            newColumnData = ColumnBuilder.doubles(vals)

        case .currency:
            var vals: [Int64?] = []
            vals.reserveCapacity(rowCount)
            for r in 0..<rowCount {
                if let _ = existingErrors[r] {
                    vals.append(nil)
                    continue
                }
                let cell = MTables.cell(table, row: r, column: colIdx)
                switch cell {
                case .null:
                    vals.append(nil)
                case .currency(let c):
                    vals.append(c)
                case .number(let d):
                    vals.append(Int64((d * 10_000).rounded()))
                case .text(let s):
                    let cleaned = s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "")
                    if let d = Double(cleaned) {
                        vals.append(Int64((d * 10_000).rounded()))
                    } else {
                        colErrors[r] = "DataFormat.Error: We couldn't convert to Currency. Details: \(s)"
                        vals.append(nil)
                    }
                default:
                    colErrors[r] = "DataFormat.Error: We couldn't convert to Currency. Details: \(cell.kindName)"
                    vals.append(nil)
                }
            }
            newColumnData = ColumnBuilder.currency(vals)

        case .date:
            var vals: [Double?] = []
            vals.reserveCapacity(rowCount)
            for r in 0..<rowCount {
                if let _ = existingErrors[r] {
                    vals.append(nil)
                    continue
                }
                let cell = MTables.cell(table, row: r, column: colIdx)
                switch cell {
                case .null:
                    vals.append(nil)
                case .date(let d):
                    vals.append(floor(d))
                case .dateTime(let d):
                    vals.append(floor(d)) // [SUY ĐOÁN phần giờ]: bỏ phần giờ
                case .text(let s):
                    if let serial = ValueDateHelper.parseDateString(s) {
                        vals.append(floor(serial))
                    } else {
                        colErrors[r] = "DataFormat.Error: We couldn't convert to Date. Details: \(s)"
                        vals.append(nil)
                    }
                default:
                    colErrors[r] = "DataFormat.Error: We couldn't convert to Date. Details: \(cell.kindName)"
                    vals.append(nil)
                }
            }
            newColumnData = ColumnBuilder.dateTimes(vals)

        case .datetime, .datetimezone:
            var vals: [Double?] = []
            vals.reserveCapacity(rowCount)
            for r in 0..<rowCount {
                if let _ = existingErrors[r] {
                    vals.append(nil)
                    continue
                }
                let cell = MTables.cell(table, row: r, column: colIdx)
                switch cell {
                case .null:
                    vals.append(nil)
                case .dateTime(let d), .date(let d):
                    vals.append(d)
                case .text(let s):
                    if let serial = ValueDateHelper.parseDateString(s) {
                        vals.append(serial)
                    } else {
                        colErrors[r] = "DataFormat.Error: We couldn't convert to DateTime. Details: \(s)"
                        vals.append(nil)
                    }
                default:
                    colErrors[r] = "DataFormat.Error: We couldn't convert to DateTime. Details: \(cell.kindName)"
                    vals.append(nil)
                }
            }
            newColumnData = ColumnBuilder.dateTimes(vals)

        case .text:
            var vals: [String?] = []
            vals.reserveCapacity(rowCount)
            for r in 0..<rowCount {
                if let _ = existingErrors[r] {
                    vals.append(nil)
                    continue
                }
                let cell = MTables.cell(table, row: r, column: colIdx)
                switch cell {
                case .null:
                    vals.append(nil)
                case .text(let s):
                    vals.append(s)
                case .number(let d):
                    if d.isNaN { vals.append("NaN") }
                    else if d.isInfinite { vals.append(d > 0 ? "Infinity" : "-Infinity") }
                    else if d == d.rounded() && abs(d) < 9.2e18 {
                        vals.append(String(Int64(d)))
                    } else {
                        vals.append(String(format: "%g", d))
                    }
                case .currency(let c):
                    let d = Double(c) / 10_000
                    if d == d.rounded() && abs(d) < 9.2e18 {
                        vals.append(String(Int64(d)))
                    } else {
                        vals.append(String(format: "%g", d))
                    }
                case .logical(let b):
                    vals.append(b ? "true" : "false")
                case .date(let d):
                    let civil = ValueDateHelper.civilFromSerial(d)
                    vals.append(String(format: "%04d-%02d-%02d", civil.year, civil.month, civil.day))
                case .dateTime(let d):
                    let datePart = floor(d)
                    let timePart = (d - datePart) * 86_400
                    let civil = ValueDateHelper.civilFromSerial(datePart)
                    let secs = Int(timePart.rounded())
                    let h = (secs / 3600) % 24
                    let m = (secs / 60) % 60
                    let s = secs % 60
                    vals.append(String(format: "%04d-%02d-%02d %02d:%02d:%02d", civil.year, civil.month, civil.day, h, m, s))
                default:
                    vals.append(String(describing: cell))
                }
            }
            newColumnData = ColumnBuilder.strings(vals)

        case .logical:
            var vals: [Bool?] = []
            vals.reserveCapacity(rowCount)
            for r in 0..<rowCount {
                if let _ = existingErrors[r] {
                    vals.append(nil)
                    continue
                }
                let cell = MTables.cell(table, row: r, column: colIdx)
                switch cell {
                case .null:
                    vals.append(nil)
                case .logical(let b):
                    vals.append(b)
                case .text(let s):
                    let lower = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if lower == "true" { vals.append(true) }
                    else if lower == "false" { vals.append(false) }
                    else {
                        colErrors[r] = "DataFormat.Error: We couldn't convert to Boolean. Details: \(s)"
                        vals.append(nil)
                    }
                default:
                    colErrors[r] = "DataFormat.Error: We couldn't convert to Boolean. Details: \(cell.kindName)"
                    vals.append(nil)
                }
            }
            newColumnData = ColumnBuilder.booleans(vals)

        default:
            throw MError.unsupported("kiểu cột \(targetType.kind.rawValue)")
        }

        if !colErrors.isEmpty {
            newErrorMask[colIdx] = colErrors
        } else {
            newErrorMask.removeValue(forKey: colIdx)
        }

        return TableColumn(name: col.name, data: newColumnData)
    }
}
