# Hợp đồng: nguồn và M (US2 Enter Data, US6)

Chủ: lead cho `ColumnStore/TableData.swift`, `MEngine`, `BIPro/Query`; agy F2-CONN cho `Connectors/Postgres/**`, `Connectors/Parquet/**`.

```swift
public enum MSourceType: String, Sendable { case time, duration, dateTimeZone, binary, list, record }
public struct TableColumn { /* thêm */ public var sourceType: MSourceType? }   // lead, Đợt 0
```

- PostgreSQL (`PostgresSource`): timestamptz, time, interval, bytea, mảng → giá trị và `sourceType` theo VM-F15; không còn lỗi "chưa hỗ trợ" cho 5 kiểu này.
- Parquet (`ParquetSource`): struct → ô `record`, list → ô `list` qua `TableData.structured` (giữ hợp đồng Phase F `data-source.md`); độ sâu ≤ 3.
- MEngine (lead): `Binary.FromText(text, BinaryEncoding.Base64)`, `Binary.Decompress(binary, Compression.Deflate)`, `Json.Document(binary)`, `Table.FromRows(rows, type)`, `type nullable text meta [...]`, `type table [...]`.
- SQLite: `SourceQuery.sqlite(path:driver:)` lấy tên driver; `NavigatorState` đọc/ghi `UserDefaults["bipro.sqlite.odbcDriver"]`.
