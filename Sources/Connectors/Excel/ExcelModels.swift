import Foundation
import ColumnStore

enum ExcelCellType {
    case integer(Int64)
    case double(Double)
    case dateTime(Double)
    case boolean(Bool)
    case string(String)
    case error(String)
}

struct ExcelCell {
    let row: Int
    let col: Int
    let value: ExcelCellType
}

struct ExcelTableInfo: Sendable {
    let name: String
    let displayName: String
    let ref: String
    let columnNames: [String]
    let sheetPath: String
}

struct ExcelSheetInfo: Sendable {
    let name: String
    let sheetId: String
    let rId: String
    let targetPath: String
}

enum ExcelRefParser {
    static func parseCellRef(_ ref: String) -> (col: Int, row: Int)? {
        var colStr = ""
        var rowStr = ""
        for c in ref {
            if c.isLetter {
                colStr.append(c)
            } else if c.isNumber {
                rowStr.append(c)
            }
        }
        guard !colStr.isEmpty, let rowNum = Int(rowStr) else { return nil }
        var col = 0
        for c in colStr.uppercased() {
            guard let ascii = c.asciiValue, c >= "A" && c <= "Z" else { return nil }
            col = col * 26 + Int(ascii - Character("A").asciiValue! + 1)
        }
        return (col - 1, rowNum - 1)
    }

    static func parseRangeRef(_ ref: String) -> (minCol: Int, minRow: Int, maxCol: Int, maxRow: Int)? {
        let parts = ref.split(separator: ":")
        guard parts.count == 2 else {
            if let single = parseCellRef(ref) {
                return (single.col, single.row, single.col, single.row)
            }
            return nil
        }
        guard let start = parseCellRef(String(parts[0])),
              let end = parseCellRef(String(parts[1])) else { return nil }
        return (min(start.col, end.col), min(start.row, end.row), max(start.col, end.col), max(start.row, end.row))
    }
}
