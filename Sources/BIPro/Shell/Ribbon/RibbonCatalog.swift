import Foundation

/// Nguồn sự thật duy nhất cho danh sách tab và nội dung Ribbon theo từng `WorkspaceMode`.
enum RibbonCatalog {
    /// Trả về danh sách tab theo đúng bảng `contracts/ribbon-catalog.md` mục "Quy ước".
    /// Tab ngữ cảnh luôn đứng cuối cùng.
    static func tabs(mode: WorkspaceMode, visualSelected: Bool) -> [RibbonTabID] {
        switch mode {
        case .report:
            var list: [RibbonTabID] = [.file, .home, .insert, .modeling, .design, .view, .optimize, .help]
            if visualSelected {
                list.append(contentsOf: [.format, .dataDrill])
            }
            return list
        case .table:
            return [.file, .home, .help, .tableTools, .columnTools]
        case .model, .daxQuery, .tmdl:
            return [.file, .home, .help]
        }
    }

    /// Nếu tab hiện tại không còn thuộc `tabs(mode:visualSelected:)` (hoặc là `.file`), tự trả về `.home`.
    static func resolvedTab(_ current: RibbonTabID, mode: WorkspaceMode, visualSelected: Bool) -> RibbonTabID {
        let allowed = tabs(mode: mode, visualSelected: visualSelected)
        if current == .file || !allowed.contains(current) {
            return .home
        }
        return current
    }

    /// Trả về đặc tả dữ liệu cho cặp `(tab, mode)`. Đầy đủ toàn bộ 15 Ribbon của Power BI Desktop 2.159.
    static func spec(for tab: RibbonTabID, mode: WorkspaceMode) -> RibbonTabSpec? {
        guard tab != .file else { return nil }
        switch (mode, tab) {
        case (.report, .home): return reportHome
        case (.report, .insert): return reportInsert
        case (.report, .modeling): return reportModeling
        case (.report, .design): return reportDesign
        case (.report, .view): return reportView
        case (.report, .optimize): return reportOptimize
        case (.report, .format): return reportFormat
        case (.report, .dataDrill): return reportDataDrill
        case (.table, .home): return tableHome
        case (.table, .tableTools): return tableTools
        case (.table, .columnTools): return columnTools
        case (.model, .home): return modelHome
        case (.daxQuery, .home): return daxHome
        case (.tmdl, .home): return tmdlHome
        case (_, .help): return reportHelp
        default:
            return nil
        }
    }

    /// Trả về toàn bộ các `RibbonTabSpec` đã đăng ký trong catalog (phục vụ kiểm thử song ngữ và ràng buộc hợp đồng).
    static func allRegisteredSpecs() -> [RibbonTabSpec] {
        var result: [RibbonTabSpec] = []
        let modes: [WorkspaceMode] = [.report, .table, .model, .daxQuery, .tmdl]
        for mode in modes {
            for tab in tabs(mode: mode, visualSelected: mode == .report) {
                if let tabSpec = spec(for: tab, mode: mode) {
                    result.append(tabSpec)
                }
            }
        }
        return result
    }
}
