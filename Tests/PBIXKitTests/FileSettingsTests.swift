import Foundation
import Testing
@testable import PBIXKit

/// T033/T037: tuỳ chọn "Autodetect new relationships after data is loaded" của file nằm ở part `Settings`,
/// khoá `ReportSettings.IsRelationshipAutodetectionEnabled` (gate VM-F11: Desktop tắt thì ghi `false`, bật lại thì xoá khoá).
struct FileSettingsTests {
    static func utf16(_ text: String) -> Data { NewDocument.utf16LE(text) }
    static func text(_ data: Data) -> String { FileSettings.decode(data) }

    /// `desk-b.pbix` (bật) và `desk-a.pbix` (tắt), Desktop 2.159 lưu ở gate T037.
    static let on = #"{"Version":4,"ReportSettings":{},"QueriesSettings":{"TypeDetectionEnabled":true,"RelationshipImportEnabled":true,"Version":"2.159.1206.0"}}"#
    static let off = #"{"Version":4,"ReportSettings":{"IsRelationshipAutodetectionEnabled":false},"QueriesSettings":{"TypeDetectionEnabled":true,"RelationshipImportEnabled":true,"Version":"2.159.1206.0"}}"#
    /// `f11-desktop.pbix`: `RunBackgroundAnalysis` là ô "Allow data previews to download in the background", không liên quan.
    static let f11 = #"{"Version":4,"ReportSettings":{},"QueriesSettings":{"TypeDetectionEnabled":true,"RelationshipImportEnabled":true,"RunBackgroundAnalysis":true,"Version":"2.159.1206.0"}}"#

    @Test func docTuyChonTuPhatHienQuanHe() throws {
        #expect(FileSettings.autodetectRelationships(in: Self.utf16(Self.on)))
        #expect(!FileSettings.autodetectRelationships(in: Self.utf16(Self.off)))
        #expect(FileSettings.autodetectRelationships(in: Self.utf16(Self.f11)))
        #expect(FileSettings.autodetectRelationships(in: Self.utf16(Self.f11.replacingOccurrences(of: "\"RunBackgroundAnalysis\":true", with: "\"RunBackgroundAnalysis\":false"))))
        if let f11 = F2Fixtures.desktop("vm-f11", "f11-desktop.pbix") {
            #expect(FileSettings.autodetectRelationships(in: try ZipArchive(url: f11).read("Settings")))
        }
    }

    @Test func ghiNhuDesktop() throws {
        #expect(Self.text(try FileSettings.setting(autodetectRelationships: false, in: Self.utf16(Self.on))) == Self.off)
        #expect(Self.text(try FileSettings.setting(autodetectRelationships: true, in: Self.utf16(Self.off))) == Self.on)
        // Không đổi thì giữ nguyên; phần còn lại (kể cả RunBackgroundAnalysis) giữ từng byte.
        #expect(Self.text(try FileSettings.setting(autodetectRelationships: true, in: Self.utf16(Self.f11))) == Self.f11)
        let f11Off = try FileSettings.setting(autodetectRelationships: false, in: Self.utf16(Self.f11))
        #expect(Self.text(f11Off) == Self.f11.replacingOccurrences(of: "\"ReportSettings\":{}", with: "\"ReportSettings\":{\"IsRelationshipAutodetectionEnabled\":false}"))
        // ReportSettings có khoá khác: chèn đầu đối tượng [SUY ĐOÁN], gỡ cả dấu phẩy khi bật lại.
        let other = #"{"Version":4,"ReportSettings":{"X":1},"QueriesSettings":{}}"#
        let otherOff = try FileSettings.setting(autodetectRelationships: false, in: Self.utf16(other))
        #expect(Self.text(otherOff) == #"{"Version":4,"ReportSettings":{"IsRelationshipAutodetectionEnabled":false,"X":1},"QueriesSettings":{}}"#)
        #expect(Self.text(try FileSettings.setting(autodetectRelationships: true, in: otherOff)) == other)
        let trailing = #"{"Version":4,"ReportSettings":{"X":1,"IsRelationshipAutodetectionEnabled":false},"QueriesSettings":{}}"#
        #expect(Self.text(try FileSettings.setting(autodetectRelationships: true, in: Self.utf16(trailing))) == other)
        #expect(throws: WriteError.self) { try FileSettings.setting(autodetectRelationships: false, in: Self.utf16(#"{"Version":4}"#)) }
    }
}
