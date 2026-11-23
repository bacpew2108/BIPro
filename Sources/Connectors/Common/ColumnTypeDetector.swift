import PBIXKit
import Foundation
import ColumnStore

public enum ColumnTypeDetector {
    public static let sampleRows = 200

    /// [SUY ĐOÁN] Dò số nguyên: -?\d+ và vừa Int64
    private static func isInteger(_ s: String) -> Bool {
        guard !s.isEmpty else { return false }
        var startIndex = s.startIndex
        if s[startIndex] == "-" {
            startIndex = s.index(after: startIndex)
            guard startIndex < s.endIndex else { return false }
        }
        for c in s[startIndex...] {
            guard c >= "0" && c <= "9" else { return false }
        }
        return Int64(s) != nil
    }

    /// [SUY ĐOÁN] Dò số thực: có phần thập phân hoặc mũ, dấu chấm bất kể locale
    private static func isDouble(_ s: String) -> Bool {
        guard !s.isEmpty else { return false }
        guard let v = Double(s), v.isFinite else { return false }
        var hasDigit = false
        for c in s {
            if c >= "0" && c <= "9" {
                hasDigit = true
            } else if c == "-" || c == "+" || c == "." || c == "e" || c == "E" {
                continue
            } else {
                return false
            }
        }
        return hasDigit
    }

    /// [SUY ĐOÁN] Dò boolean: true/false không phân biệt hoa thường
    private static func isBoolean(_ s: String) -> Bool {
        s.caseInsensitiveCompare("true") == .orderedSame || s.caseInsensitiveCompare("false") == .orderedSame
    }

    /// [SUY ĐOÁN] Dò ngày giờ: yyyy-MM-dd hoặc yyyy-MM-dd HH:mm:ss / yyyy-MM-dd'T'HH:mm:ss
    private static func parseDateTime(_ s: String) -> Double? {
        DateHelper.parseDateTime(s)
    }

    /// [SUY ĐOÁN] Dò kiểu dữ liệu từ mẫu tối đa 200 ô không rỗng đầu tiên
    private static func detectType(from sample: [String]) -> DAXType {
        guard !sample.isEmpty else { return .string }

        if sample.allSatisfy(isInteger) {
            return .integer
        }
        if sample.allSatisfy(isDouble) {
            return .double
        }
        if sample.allSatisfy(isBoolean) {
            return .boolean
        }
        if sample.allSatisfy({ parseDateTime($0) != nil }) {
            return .dateTime
        }
        return .string
    }

    /// Dò kiểu từ danh sách chuỗi (CSV) theo quy tắc; trả cột và ô lỗi (nếu có).
    public static func column(from strings: [String?], name: String) -> (data: ColumnData, errors: [Int: String]) {
        // [SUY ĐOÁN] Lấy tối đa sampleRows ô không rỗng đầu tiên (ô "" là nil)
        var sample: [String] = []
        sample.reserveCapacity(sampleRows)
        for s in strings {
            if let s = s, !s.isEmpty {
                sample.append(s)
                if sample.count == sampleRows { break }
            }
        }

        let detected = detectType(from: sample)

        switch detected {
        case .integer:
            var values: [Int64?] = []
            values.reserveCapacity(strings.count)
            var errors: [Int: String] = [:]
            for (i, s) in strings.enumerated() {
                if let s = s, !s.isEmpty {
                    if let val = Int64(s) {
                        values.append(val)
                    } else {
                        values.append(nil)
                        errors[i] = lt("Không thể chuyển '\(s)' sang số nguyên", "Couldn't convert '\(s)' to an integer")
                    }
                } else {
                    values.append(nil)
                }
            }
            return (ColumnBuilder.integers(values), errors)

        case .double:
            var values: [Double?] = []
            values.reserveCapacity(strings.count)
            var errors: [Int: String] = [:]
            for (i, s) in strings.enumerated() {
                if let s = s, !s.isEmpty {
                    if let val = Double(s), val.isFinite {
                        values.append(val)
                    } else {
                        values.append(nil)
                        errors[i] = lt("Không thể chuyển '\(s)' sang số thực", "Couldn't convert '\(s)' to a decimal number")
                    }
                } else {
                    values.append(nil)
                }
            }
            return (ColumnBuilder.doubles(values), errors)

        case .boolean:
            var values: [Bool?] = []
            values.reserveCapacity(strings.count)
            var errors: [Int: String] = [:]
            for (i, s) in strings.enumerated() {
                if let s = s, !s.isEmpty {
                    if s.caseInsensitiveCompare("true") == .orderedSame {
                        values.append(true)
                    } else if s.caseInsensitiveCompare("false") == .orderedSame {
                        values.append(false)
                    } else {
                        values.append(nil)
                        errors[i] = lt("Không thể chuyển '\(s)' sang logic", "Couldn't convert '\(s)' to a logical value")
                    }
                } else {
                    values.append(nil)
                }
            }
            return (ColumnBuilder.booleans(values), errors)

        case .dateTime:
            var values: [Double?] = []
            values.reserveCapacity(strings.count)
            var errors: [Int: String] = [:]
            for (i, s) in strings.enumerated() {
                if let s = s, !s.isEmpty {
                    if let val = parseDateTime(s) {
                        values.append(val)
                    } else {
                        values.append(nil)
                        errors[i] = lt("Không thể chuyển '\(s)' sang ngày giờ", "Couldn't convert '\(s)' to date/time")
                    }
                } else {
                    values.append(nil)
                }
            }
            return (ColumnBuilder.dateTimes(values), errors)

        case .string, .currency:
            // [SUY ĐOÁN] Cột toàn ô rỗng thành string với mọi ô nil.
            // Nếu có dữ liệu thì giữ nguyên giá trị chuỗi (ô nil là nil).
            if sample.isEmpty {
                return (ColumnBuilder.strings(Array(repeating: nil, count: strings.count)), [:])
            }
            let values: [String?] = strings.map { $0 }
            return (ColumnBuilder.strings(values), [:])
        }
    }
}
