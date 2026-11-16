import Foundation

/// Tài liệu `.pbix` trống cho "File → Mới" (Phase F, T076, FR-053).
///
/// Theo file Desktop 2.159 tạo bằng Blank report rồi lưu (VM-F5): 10 phần, không có `DataMashup` (truy vấn M nằm ở
/// `Partition.QueryDefinition`/`Expression` của mô hình), báo cáo PBIR một trang "Page 1" 1920×1080. `DataModel` lấy từ mẫu
/// Desktop (`NewDocumentTemplate`) vì `metadata.sqlitedb` trống có 73 bảng lược đồ; chỉ sửa hai chú thích mô hình:
/// - `__PBI_TimeIntelligenceEnabled = 0` (tắt Auto date/time của file): khi bật, Desktop sinh `DateTableTemplate` và
///   `LocalDateTable` kèm quan hệ và phân cấp cho mỗi cột ngày, mà bộ ghi của BI Pro chưa dựng (giống Nhom6, cũng tắt).
/// - `PBI_QueryOrder = []`: Desktop thêm chú thích này ngay khi có truy vấn đầu tiên; có sẵn thì `addTable` nối tên vào.
/// Bỏ `SecurityBindings` (khoá DPAPI theo máy, BI Pro vẫn bỏ khi lưu báo cáo).
public enum NewDocument {
    /// Tên trang đầu, như Desktop.
    public static let firstPageName = "Page 1"

    /// Bytes `.pbix` của tài liệu trống. Mỗi lần gọi sinh tên trang (20 ký tự hex) mới, như Desktop.
    public static func blank() throws -> Data {
        let page = pageID()
        let theme = NewDocumentTemplate.baseThemeName
        let themePath = "Report/StaticResources/SharedResources/BaseThemes/\(theme).json"
        let members: [(path: String, source: ZipWriter.Source)] = [
            ("Version", .bytes(utf16LE("1.32"), method: 8)),
            ("[Content_Types].xml", .bytes(contentTypes, method: 8)),
            ("Settings", .bytes(utf16LE(#"{"Version":4,"ReportSettings":{},"QueriesSettings":{"TypeDetectionEnabled":true,"RelationshipImportEnabled":true,"Version":"2.159.1206.0"}}"#), method: 8)),
            ("Metadata", .bytes(utf16LE(#"{"Version":5,"AutoCreatedRelationships":[],"CreatedFrom":"Cloud","CreatedFromRelease":"2026.10"}"#), method: 8)),
            (themePath, .bytes(NewDocumentTemplate.baseTheme, method: 8)),
            ("Report/definition/version.json", .bytes(Data(#"{"$schema":"https://developer.microsoft.com/json-schemas/fabric/item/report/definition/versionMetadata/1.0.0/schema.json","version":"2.0.0"}"#.utf8), method: 8)),
            ("Report/definition/report.json", .bytes(Data(reportJSON(theme: theme).utf8), method: 8)),
            ("Report/definition/pages/pages.json", .bytes(Data(#"{"$schema":"https://developer.microsoft.com/json-schemas/fabric/item/report/definition/pagesMetadata/1.1.0/schema.json","pageOrder":["\#(page)"],"activePageName":"\#(page)"}"#.utf8), method: 8)),
            ("Report/definition/pages/\(page)/page.json", .bytes(Data(#"{"$schema":"https://developer.microsoft.com/json-schemas/fabric/item/report/definition/page/2.1.0/schema.json","name":"\#(page)","displayName":"\#(firstPageName)","displayOption":"FitToPage","height":1080,"width":1920}"#.utf8), method: 8)),
            // Desktop lưu DataModel không nén ZIP (luồng đã nén XPress9).
            ("DataModel", .bytes(try dataModel(), method: 0)),
        ]
        return try ZipWriter.write(members, modified: nil)
    }

    /// `DataModel` của mẫu với hai chú thích mô hình đã đặt (xem chú thích kiểu).
    static func dataModel() throws -> Data {
        let (abfBytes, _) = try DataModelStream.decompress(NewDocumentTemplate.dataModel)
        let abf = try ABFBackup(data: abfBytes)
        guard let metadataFile = abf.file(named: PBIXWriter.metadataPath) else {
            throw WriteError.invalid("mẫu tài liệu trống không có \(PBIXWriter.metadataPath)")
        }
        var metadata = try MetadataWriter(sqlite: try abf.contents(of: metadataFile))
        try metadata.setModelAnnotation(name: "__PBI_TimeIntelligenceEnabled", value: "0")
        try metadata.setModelAnnotation(name: "PBI_QueryOrder", value: "[]")
        let rebuilt = try ABFWriter.rebuild(abf, replacing: [ABFPayload(path: metadataFile.path, data: try metadata.serialize())])
        return try DataModelStream.compress(abf: rebuilt)
    }

    /// `[Content_Types].xml` của Desktop (UTF-8 có BOM) trừ dòng `SecurityBindings`.
    static var contentTypes: Data {
        Data([0xEF, 0xBB, 0xBF]) + Data(#"<?xml version="1.0" encoding="utf-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="json" ContentType="" /><Override PartName="/Version" ContentType="" /><Override PartName="/Settings" ContentType="application/json" /><Override PartName="/Metadata" ContentType="application/json" /><Override PartName="/DataModel" ContentType="" /></Types>"#.utf8)
    }

    static func reportJSON(theme: String) -> String {
        #"{"$schema":"https://developer.microsoft.com/json-schemas/fabric/item/report/definition/report/3.3.0/schema.json","themeCollection":{"baseTheme":{"name":"\#(theme)","reportVersionAtImport":{"visual":"2.14.0","report":"3.4.0","page":"2.3.1"},"type":"SharedResources"}},"objects":{"section":[{"properties":{"verticalAlignment":{"expr":{"Literal":{"Value":"'Top'"}}}}}]},"resourcePackages":[{"name":"SharedResources","type":"SharedResources","items":[{"name":"\#(theme)","path":"BaseThemes/\#(theme).json","type":"BaseTheme"}]}],"settings":{"useStylableVisualContainerHeader":true,"exportDataMode":"AllowSummarized","defaultDrillFilterOtherVisuals":true,"allowChangeFilterTypes":true,"useEnhancedTooltips":true,"useDefaultAggregateDisplayName":true}}"#
    }

    /// Tên trang kiểu Desktop: 20 ký tự hex thường.
    static func pageID() -> String {
        String((0..<20).map { _ in "0123456789abcdef".randomElement()! })
    }

    static func utf16LE(_ text: String) -> Data {
        var data = Data()
        for unit in text.utf16 { data.append(UInt8(unit & 0xFF)); data.append(UInt8(unit >> 8)) }
        return data
    }
}
