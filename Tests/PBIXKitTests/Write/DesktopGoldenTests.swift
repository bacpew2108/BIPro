// Phase F, T013/T014: the T3 encoders against files that Power BI Desktop wrote itself (Marketing of `tuan6.2.pbix`, a Desktop file).
// A table written by BI Pro opens in Desktop only when these bytes agree (gate F-T3, 2026-11-15: `docs/phase-f-evidence/vm-f0/`).
// Expected bytes come from Desktop's files, not from the encoder.
import Foundation
import Testing
@testable import PBIXKit

@Suite(.enabled(if: FileManager.default.fileExists(atPath: DesktopGolden.path.path))) struct DesktopGoldenTests {
    private let abf: ABFBackup
    private let metadata: ModelMetadata

    init() throws {
        abf = try PBIXFile(url: DesktopGolden.path).loadDataModel().0
        metadata = try ModelMetadata(sqlite: try abf.contents(of: #require(abf.file(named: "metadata.sqlitedb"))))
    }

    private func decoded(_ name: String) throws -> (DecodedColumn, ModelMetadata.Column)? {
        guard let column = metadata.columns.first(where: { $0.tableName == "Marketing" && $0.name == name }),
              let storage = metadata.storage(table: "Marketing", column: name) else { return nil }
        return (try VertiPaq.decodeColumn(storage, abf: abf), column)
    }

    private func file(_ path: String, suffix: String) -> Data? {
        abf.files.first { $0.path.contains(path) && $0.path.hasSuffix(suffix) }.flatMap { try? Data(abf.contents(of: $0)) }
    }

    private func values(_ column: DecodedColumn, type: ModelMetadata.DataType) -> VertiPaqWriter.Values? {
        guard case .dictionary(_, let dictionary) = column.storage else { return nil }
        switch type {
        case .string: return .string(dictionary.compactMap { if case .string(let s) = $0 { s } else { nil } }.map { Optional($0) })
        case .int64: return .int64(dictionary.compactMap { if case .int(let i) = $0 { i } else { nil } })
        case .double: return .double(dictionary.compactMap { if case .double(let d) = $0 { d } else { nil } })
        case .dateTime: return .dateTime(dictionary.compactMap { if case .dateTime(let d) = $0 { d } else { nil } })
        default: return nil
        }
    }

    /// `POS_TO_ID` and `ID_TO_POS` of every dictionary column of Marketing (strings with accents, doubles, whole numbers, with NULLs,
    /// 4 to 1250 entries) match Desktop's `.idf` and `.idfmeta` byte for byte.
    @Test func bangHeThongHashKhopFileDesktop() throws {
        var checked = 0
        for column in metadata.columns where column.tableName == "Marketing" && column.kind != .rowNumber {
            guard let (decodedColumn, info) = try decoded(column.name), let values = values(decodedColumn, type: info.dataType),
                  case .dictionary(let codes, _) = decodedColumn.storage else { continue }
            let dictionary = try VertiPaqWriter.encodeDictionary(values)
            let hasNulls = codes.contains(-1)
            let sorted = hasNulls ? [Int64(VertiPaqWriter.nullDataID)] + dictionary.sortedIDs : dictionary.sortedIDs
            let h = try VertiPaqWriter.encodeHierarchy(sortedIDs: sorted, dictionaryCount: dictionary.count, hasNulls: hasNulls)
            let stem = "H$Marketing (12)$\(column.name) (\(column.id))$"
            for (kind, blob) in [("POS_TO_ID", h.positionToID), ("ID_TO_POS", h.idToPosition)] {
                #expect(file(stem, suffix: "\(kind).0.idf") == blob.idf, Comment(rawValue: "\(column.name) \(kind) idf"))
                #expect(file(stem, suffix: "\(kind).0.idfmeta") == blob.idfmeta, Comment(rawValue: "\(column.name) \(kind) idfmeta"))
            }
            checked += 1
        }
        #expect(checked >= 10)   // gồm cột ngày `Ngày `
    }

    /// Segments that Desktop stores as one bit-packed run (no RLE): `.idf` and `.idfmeta` match byte for byte.
    @Test func doanDuLieuBitPackedKhopFileDesktop() throws {
        var checked = 0
        for column in metadata.columns where column.tableName == "Marketing" && column.kind != .rowNumber {
            guard let (decodedColumn, _) = try decoded(column.name), case .dictionary(let codes, let dictionary) = decodedColumn.storage,
                  let idf = file("Marketing (12).\(column.name) (\(column.id)).0", suffix: ".idf"),
                  let meta = file("Marketing (12).\(column.name) (\(column.id)).0", suffix: ".idfmeta") else { continue }
            // The second run of Desktop's run table is empty exactly when the segment is one bit-packed run.
            let secondRun = idf.subdata(in: 16..<24)
            guard secondRun == Data(count: 8) else { continue }
            let ids = codes.map { $0 < 0 ? Int64(VertiPaqWriter.nullDataID) : Int64($0) + Int64(VertiPaqWriter.firstDataID) }
            let segment = try VertiPaqWriter.encodeSegment(ids: ids, dictionaryCount: dictionary.count)
            #expect(segment.idf == idf, Comment(rawValue: "\(column.name) idf"))
            #expect(segment.idfmeta == meta, Comment(rawValue: "\(column.name) idfmeta"))
            checked += 1
        }
        #expect(checked >= 5)
    }

    /// Dictionary files (`.dictionary`) of the same columns, for strings, doubles and whole numbers.
    @Test func tuDienKhopFileDesktop() throws {
        var checked = 0
        for column in metadata.columns where column.tableName == "Marketing" && column.kind != .rowNumber {
            guard let (decodedColumn, info) = try decoded(column.name), let values = values(decodedColumn, type: info.dataType),
                  let desktop = file("Marketing (12).tbl", suffix: "\(column.name) (\(column.id)).dictionary") else { continue }
            #expect(try VertiPaqWriter.encodeDictionary(values).data == desktop, Comment(rawValue: column.name))
            checked += 1
        }
        #expect(checked >= 10)
    }

    /// `AttributeHierarchyStorage.MinValue/MaxValue` of the date column `Ngày ` (M/d/yyyy) and of a whole-number column.
    @Test func vanBanThongKeKhopDesktop() throws {
        let date = try #require(try decoded("Ngày "))
        let dates = try #require(values(date.0, type: .dateTime))
        let (minText, maxText, _) = VertiPaqWriter.textStatistics(dates)
        #expect(minText == "3/9/2019" && maxText == "11/29/2022")
        let number = try #require(try decoded("Conversion"))
        let ints = try #require(values(number.0, type: .int64))
        let (lo, hi, _) = VertiPaqWriter.textStatistics(ints)
        #expect(lo == "6" && hi == "13")
        // Chuỗi: Desktop ghi min/max theo so sánh văn hoá (đ sắp cùng nhóm d, nên "điện thoại" đứng trước "Thiết bị văn phòng").
        for (name, minimum, maximum) in [("Nguồn traffic", "Facebook ads", "SEO"), ("Marketer", "Hoa", "Tuấn"),
                                         ("Dòng sản phẩm", "điện thoại", "Thiết bị văn phòng"), ("Sản phẩm", "Acer Aspire 7", "Webcam Logitech C615")] {
            let column = try #require(try decoded(name))
            let strings = try #require(values(column.0, type: .string))
            let (lo, hi, _) = VertiPaqWriter.textStatistics(strings)
            #expect(lo == minimum && hi == maximum, Comment(rawValue: name))
        }
    }
}

enum DesktopGolden {
    static let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/tuan6.2.pbix")
}