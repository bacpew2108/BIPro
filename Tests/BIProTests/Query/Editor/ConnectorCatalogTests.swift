import Testing
import Foundation
import Connectors
@testable import BIPro

@Suite struct ConnectorCatalogTests {

    @Test func initialCountsByCategory() {
        #expect(ConnectorCatalog.count(for: .all, query: "") == 6)
        #expect(ConnectorCatalog.count(for: .file, query: "") == 4)
        #expect(ConnectorCatalog.count(for: .database, query: "") == 2)
    }

    @Test func searchFiltering() {
        let sqliteResults = ConnectorCatalog.visible(category: .all, query: "sqlite")
        #expect(sqliteResults.count == 1)
        #expect(sqliteResults.first?.kind == .sqlite)

        let excelByName = ConnectorCatalog.visible(category: .all, query: "excel")
        #expect(excelByName.contains(where: { $0.kind == .excel }))

        let excelByExt = ConnectorCatalog.visible(category: .all, query: ".xlsx")
        #expect(excelByExt.contains(where: { $0.kind == .excel }))

        // Case and diacritic insensitivity (Vietnamese)
        let excelByVietnameseNoAccent = ConnectorCatalog.visible(category: .all, query: "so lam viec")
        #expect(excelByVietnameseNoAccent.contains(where: { $0.kind == .excel }))

        let excelByVietnameseWithAccent = ConnectorCatalog.visible(category: .all, query: "SỔ")
        #expect(excelByVietnameseWithAccent.contains(where: { $0.kind == .excel }))

        let csvByVietnamese = ConnectorCatalog.visible(category: .all, query: "van ban")
        #expect(csvByVietnamese.contains(where: { $0.kind == .csv }))
    }

    @Test func connectorDescriptions() {
        let excel = ConnectorCatalog.entries.first(where: { $0.kind == .excel })
        #expect(excel?.detail == "Bảng tính Microsoft Excel (.xlsx)")

        let postgres = ConnectorCatalog.entries.first(where: { $0.kind == .postgres })
        #expect(postgres?.detail == "Hệ quản trị cơ sở dữ liệu quan hệ mã nguồn mở")

        let csv = ConnectorCatalog.entries.first(where: { $0.kind == .csv })
        #expect(csv?.detail == "Tệp văn bản phân cách bằng dấu phẩy hoặc tab (.csv, .tsv, .txt)")
    }

    @Test func availabilityAndDefaults() {
        let excel = ConnectorCatalog.entries.first(where: { $0.kind == .excel })
        #expect(excel?.isDefault == true)
        #expect(excel?.isAvailable == true)

        let csv = ConnectorCatalog.entries.first(where: { $0.kind == .csv })
        #expect(csv?.isDefault == false)
        #expect(csv?.isAvailable == true)

        // US7 (T088, T089): JSON và Parquet đã nối.
        let json = ConnectorCatalog.entries.first(where: { $0.kind == .json })
        #expect(json?.isAvailable == true)

        let parquet = ConnectorCatalog.entries.first(where: { $0.kind == .parquet })
        #expect(parquet?.isAvailable == true)

        let sqlite = ConnectorCatalog.entries.first(where: { $0.kind == .sqlite })
        #expect(sqlite?.isAvailable == true)

        // US8 (T093): SQLite (tệp, M kiểu ODBC như Desktop) và PostgreSQL (hộp kết nối máy chủ) đã nối.
        let postgres = ConnectorCatalog.entries.first(where: { $0.kind == .postgres })
        #expect(postgres?.isAvailable == true)
    }

    @Test func categoryPartition() {
        let fileEntries = ConnectorCatalog.visible(category: .file, query: "")
        #expect(fileEntries.map(\.kind) == [.excel, .csv, .json, .parquet])

        let dbEntries = ConnectorCatalog.visible(category: .database, query: "")
        #expect(dbEntries.map(\.kind) == [.sqlite, .postgres])
    }
}
