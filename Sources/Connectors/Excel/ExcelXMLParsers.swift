import Foundation

// MARK: - SharedStringsParser

final class SharedStringsParser: NSObject, XMLParserDelegate {
    private(set) var strings: [String] = []
    private var currentText: String = ""
    private var inTTag = false
    /// Trong `<rPh>` (chữ phiên âm): bỏ qua `<t>` của nó, không thuộc nội dung ô (T105).
    private var phoneticDepth = 0

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        if elementName == "si" {
            currentText = ""
        } else if elementName == "rPh" {
            phoneticDepth += 1
        } else if elementName == "t" {
            inTTag = phoneticDepth == 0
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "si" {
            strings.append(currentText)
        } else if elementName == "rPh" {
            phoneticDepth -= 1
        } else if elementName == "t" {
            inTTag = false
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inTTag {
            currentText.append(string)
        }
    }
}

// MARK: - StylesParser

final class StylesParser: NSObject, XMLParserDelegate {
    private var customFormats: [Int: String] = [:]
    private(set) var isDateStyle: [Int: Bool] = [:]
    private var cellXfIndex = 0
    private var inCellXfs = false

    // [SUY ĐOÁN] Nhận diện định dạng ngày giờ: numFmtId 14–22, 45–47 hoặc tuỳ chỉnh chứa y, d, h, s ngoài ngoặc/chuỗi
    static func isDateNumFmt(id: Int, customCode: String?) -> Bool {
        if (14...22).contains(id) || (45...47).contains(id) {
            return true
        }
        guard let code = customCode else { return false }
        var outside = ""
        var inQuotes = false
        var inBrackets = false
        for c in code {
            if c == "\"" {
                inQuotes.toggle()
            } else if !inQuotes && c == "[" {
                inBrackets = true
            } else if !inQuotes && c == "]" {
                inBrackets = false
            } else if !inQuotes && !inBrackets {
                outside.append(c)
            }
        }
        let lower = outside.lowercased()
        return lower.contains("y") || lower.contains("d") || lower.contains("h") || lower.contains("s")
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        if elementName == "cellXfs" {
            inCellXfs = true
            cellXfIndex = 0
        } else if elementName == "numFmt" {
            if let idStr = attributeDict["numFmtId"], let id = Int(idStr),
               let formatCode = attributeDict["formatCode"] {
                customFormats[id] = formatCode
            }
        } else if elementName == "xf" && inCellXfs {
            if let idStr = attributeDict["numFmtId"], let id = Int(idStr) {
                let isDate = Self.isDateNumFmt(id: id, customCode: customFormats[id])
                isDateStyle[cellXfIndex] = isDate
            }
            cellXfIndex += 1
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "cellXfs" {
            inCellXfs = false
        }
    }
}

// MARK: - WorkbookParser

final class WorkbookParser: NSObject, XMLParserDelegate {
    private(set) var date1904 = false
    private(set) var sheets: [(name: String, sheetId: String, rId: String)] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        if elementName == "workbookPr" {
            if let val = attributeDict["date1904"], val == "1" || val.lowercased() == "true" {
                date1904 = true
            }
        } else if elementName == "sheet" {
            if let name = attributeDict["name"],
               let sheetId = attributeDict["sheetId"] {
                let rId = attributeDict["r:id"] ?? attributeDict["id"] ?? ""
                sheets.append((name, sheetId, rId))
            }
        }
    }
}

// MARK: - RelsParser

final class RelsParser: NSObject, XMLParserDelegate {
    private(set) var rels: [String: String] = [:]

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        if elementName == "Relationship" {
            if let id = attributeDict["Id"], let target = attributeDict["Target"] {
                rels[id] = target
            }
        }
    }
}

// MARK: - TableXMLParser

final class TableXMLParser: NSObject, XMLParserDelegate {
    private(set) var name: String = ""
    private(set) var displayName: String = ""
    private(set) var ref: String = ""
    private(set) var columns: [String] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        if elementName == "table" {
            name = attributeDict["name"] ?? ""
            displayName = attributeDict["displayName"] ?? name
            ref = attributeDict["ref"] ?? ""
        } else if elementName == "tableColumn" {
            if let colName = attributeDict["name"] {
                columns.append(colName)
            }
        }
    }
}

// MARK: - SheetParser

final class SheetParser: NSObject, XMLParserDelegate {
    private let sharedStrings: [String]
    private let isDateStyle: [Int: Bool]
    private let date1904: Bool

    private(set) var dimensionRef: String?
    private(set) var cells: [ExcelCell] = []

    private var currentCellRef: String = ""
    private var currentCellType: String?
    private var currentCellStyle: Int?
    private var currentValText: String = ""
    private var inVTag = false
    private var inInlineStrTTag = false
    /// Vị trí khi ô hoặc dòng không có thuộc tính `r` (ECMA-376 cho phép bỏ): dòng kế tiếp, cột sau ô trước (T105).
    private var currentRow = -1
    private var lastCol = -1
    private var phoneticDepth = 0

    init(sharedStrings: [String], isDateStyle: [Int: Bool], date1904: Bool) {
        self.sharedStrings = sharedStrings
        self.isDateStyle = isDateStyle
        self.date1904 = date1904
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        if elementName == "dimension" {
            dimensionRef = attributeDict["ref"]
        } else if elementName == "row" {
            currentRow = attributeDict["r"].flatMap(Int.init).map { $0 - 1 } ?? currentRow + 1
            lastCol = -1
        } else if elementName == "c" {
            currentCellRef = attributeDict["r"] ?? ""
            currentCellType = attributeDict["t"]
            currentCellStyle = attributeDict["s"].flatMap(Int.init)
            currentValText = ""
        } else if elementName == "v" {
            inVTag = true
            currentValText = ""
        } else if elementName == "rPh" {
            phoneticDepth += 1
        } else if elementName == "t" {
            // Inline string có thể có nhiều đoạn `<r><t>`: gom tất cả, không xoá chữ đã gom (T105).
            inInlineStrTTag = phoneticDepth == 0
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "v" {
            inVTag = false
        } else if elementName == "t" {
            inInlineStrTTag = false
        } else if elementName == "rPh" {
            phoneticDepth -= 1
        } else if elementName == "c" {
            let explicit = currentCellRef.isEmpty ? nil : ExcelRefParser.parseCellRef(currentCellRef)
            if !currentCellRef.isEmpty && explicit == nil { return }
            let pos = explicit ?? (col: lastCol + 1, row: max(currentRow, 0))
            lastCol = pos.col
            if explicit != nil { currentRow = pos.row }
            // Chữ giữ nguyên khoảng trắng (Excel lưu đúng nội dung ô); số, logic, chỉ số shared string thì bỏ khoảng trắng thừa.
            let raw = currentValText
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

            let cellValue: ExcelCellType?
            switch currentCellType {
            case "s":
                if let idx = Int(text), idx >= 0, idx < sharedStrings.count {
                    cellValue = .string(sharedStrings[idx])
                } else {
                    cellValue = nil
                }
            case "b":
                cellValue = .boolean(text == "1" || text.lowercased() == "true")
            case "e":
                cellValue = .error(text)
            case "str", "inlineStr":
                cellValue = .string(raw)
            default:
                // Số hoặc ngày
                if let num = Double(text) {
                    let isDate = currentCellStyle.flatMap { isDateStyle[$0] } ?? false
                    if isDate {
                        let serial = date1904 ? (num + 1462) : num
                        cellValue = .dateTime(serial)
                    } else if floor(num) == num && num >= Double(Int64.min) && num <= Double(Int64.max) {
                        cellValue = .integer(Int64(num))
                    } else {
                        cellValue = .double(num)
                    }
                } else if !text.isEmpty {
                    cellValue = .string(text)
                } else {
                    cellValue = nil
                }
            }

            if let cellValue = cellValue {
                cells.append(ExcelCell(row: pos.row, col: pos.col, value: cellValue))
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inVTag || inInlineStrTTag {
            currentValText.append(string)
        }
    }
}
