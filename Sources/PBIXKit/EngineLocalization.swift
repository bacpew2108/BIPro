import Foundation

/// Ngôn ngữ của thông báo do các engine (DAX, M, Connectors, ColumnStore, PBIXKit) sinh ra.
/// Mặc định là tiếng Việt để test engine và công cụ dòng lệnh giữ nguyên văn bản; ứng dụng BI Pro đặt lại theo cài đặt ngôn ngữ.
public enum EngineLanguage {
    nonisolated(unsafe) public static var isEnglish: @Sendable () -> Bool = { false }
}

/// Thông báo song ngữ cho engine: tiếng Anh khi ứng dụng đặt `EngineLanguage.isEnglish`, ngược lại tiếng Việt.
public func lt(_ vi: String, _ en: String) -> String {
    EngineLanguage.isEnglish() ? en : vi
}
