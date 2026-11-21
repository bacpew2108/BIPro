import Foundation
import PBIXKit
import SwiftUI

/// Thư viện 6 chủ đề dựng sẵn chuẩn Power BI JSON (nhúng 100% ngoại tuyến, lưu vào `RegisteredResources/<fileName>`).
struct ThemePreset: Identifiable, Hashable, Sendable {
    let id: String
    let fileName: String
    let titleVI: String
    let titleEN: String
    let swatches: [String]
    let background: String
    let foreground: String
    let tableAccent: String
    let good: String
    let neutral: String
    let bad: String

    @MainActor
    var localizedTitle: String { bi(titleVI, titleEN) }

    var jsonData: Data {
        let obj: [String: Any] = [
            "name": id,
            "dataColors": swatches,
            "background": background,
            "foreground": foreground,
            "tableAccent": tableAccent,
            "good": good,
            "neutral": neutral,
            "bad": bad,
        ]
        return (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])) ?? Data()
    }
}

enum ThemeCatalog {
    static let presets: [ThemePreset] = [
        ThemePreset(
            id: "BIPro_Default", fileName: "BIPro_Default.json",
            titleVI: "Mặc định Power BI", titleEN: "Power BI Default",
            swatches: ["#118DFF", "#12239E", "#E66C37", "#6B007B", "#E044A7", "#744EC2", "#D9B300", "#D64550"],
            background: "#FFFFFF", foreground: "#252423", tableAccent: "#118DFF",
            good: "#1AAB40", neutral: "#D9B300", bad: "#D64554"
        ),
        ThemePreset(
            id: "BIPro_Executive", fileName: "BIPro_Executive.json",
            titleVI: "Điều hành (Executive)", titleEN: "Executive",
            swatches: ["#3B5998", "#2B947E", "#D97724", "#7D4E9F", "#C24641", "#5E7E9C", "#A0A832", "#4B5563"],
            background: "#FFFFFF", foreground: "#1F2937", tableAccent: "#3B5998",
            good: "#2B947E", neutral: "#D97724", bad: "#C24641"
        ),
        ThemePreset(
            id: "BIPro_CityPark", fileName: "BIPro_CityPark.json",
            titleVI: "Công viên xanh (City Park)", titleEN: "City Park",
            swatches: ["#2F6F4E", "#6CA965", "#E2B144", "#3E7CB1", "#D96B43", "#7F9C8D", "#9B6B9E", "#4A5568"],
            background: "#FAF9F5", foreground: "#1D2D24", tableAccent: "#2F6F4E",
            good: "#2F6F4E", neutral: "#E2B144", bad: "#D96B43"
        ),
        ThemePreset(
            id: "BIPro_Classic", fileName: "BIPro_Classic.json",
            titleVI: "Cổ điển (Classic)", titleEN: "Classic",
            swatches: ["#01B8AA", "#374649", "#FD625E", "#F2C80F", "#5F6B6D", "#8AD4EB", "#FE9666", "#A66999"],
            background: "#FFFFFF", foreground: "#252423", tableAccent: "#01B8AA",
            good: "#01B8AA", neutral: "#F2C80F", bad: "#FD625E"
        ),
        ThemePreset(
            id: "BIPro_HighContrast", fileName: "BIPro_HighContrast.json",
            titleVI: "Tương phản cao", titleEN: "High Contrast",
            swatches: ["#005FCC", "#D62728", "#008744", "#E67E00", "#7B1FA2", "#00838F", "#5D4037", "#111111"],
            background: "#FFFFFF", foreground: "#000000", tableAccent: "#005FCC",
            good: "#008744", neutral: "#E67E00", bad: "#D62728"
        ),
        ThemePreset(
            id: "BIPro_Native", fileName: "BIPro_Native.json",
            titleVI: "BI Pro macOS", titleEN: "BI Pro macOS",
            swatches: ["#0A84FF", "#30D158", "#FF9F0A", "#BF5AF2", "#FF453A", "#64D2FF", "#FFD60A", "#AC8E68"],
            background: "#FFFFFF", foreground: "#1C1C1E", tableAccent: "#0A84FF",
            good: "#30D158", neutral: "#FF9F0A", bad: "#FF453A"
        ),
    ]

    /// Kiểm tra tệp JSON chủ đề Power BI có hợp lệ không (phải là JSON object chứa `name` hoặc `dataColors`).
    @MainActor
    static func validateThemeJSON(_ data: Data) -> String? {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return bi("Tệp không phải JSON hợp lệ.", "File is not valid JSON.")
        }
        let hasColors = (obj["dataColors"] as? [String])?.isEmpty == false
        let hasName = (obj["name"] as? String)?.isEmpty == false
        guard hasColors || hasName else {
            return bi("Tệp JSON chủ đề cần có ít nhất 'name' hoặc 'dataColors'.", "Theme JSON must contain at least 'name' or 'dataColors'.")
        }
        return nil
    }
}
