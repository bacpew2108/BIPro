import SwiftUI

extension RibbonCatalog {
    /// Chuỗi phiên bản hiển thị trong hộp About (sẽ xác nhận nâng 1.3.0 ở T084).
    static let aboutVersionString = "1.3.0"

    /// Tab **View** ở Report view — đúng 4 nhóm theo `contracts/ribbon-catalog.md` và `rb_view-2x.png`.
    /// Không còn nút bật/tắt Data hay Visualizations (đóng/mở bằng `»` / dải dọc thu gọn).
    static let reportView = RibbonTabSpec(
        id: .view,
        title: RibbonTabID.view.title,
        contextual: false,
        groups: [
            // 1. Scale to fit
            RibbonGroupSpec(
                id: "scaleToFit",
                title: Bilingual(vi: "Co giãn vừa khung", en: "Scale to fit"),
                items: [
                    RibbonItemSpec(
                        id: .pageView,
                        title: Bilingual(vi: "Chế độ xem trang", en: "Page view"),
                        symbol: "rectangle.and.arrow.up.right.and.arrow.down.left",
                        tint: .neutral,
                        kind: .large,
                        hasMenu: true,
                        availability: .always
                    ),
                ]
            ),

            // 2. Mobile
            RibbonGroupSpec(
                id: "mobile",
                title: Bilingual(vi: "Di động", en: "Mobile"),
                items: [
                    RibbonItemSpec(
                        id: .mobileLayout,
                        title: Bilingual(vi: "Bố cục di động", en: "Mobile layout"),
                        symbol: "iphone",
                        tint: .neutral,
                        kind: .large,
                        availability: .unsupported(Bilingual(
                            vi: "BI Pro chưa hỗ trợ bố cục di động (Mobile layout)",
                            en: "BI Pro doesn't support Mobile layout"
                        )),
                        // [SUY ĐOÁN] Giao diện Mobile layout chưa quan sát trên VM.
                        observed: false,
                        note: "[SUY ĐOÁN] Chế độ Mobile layout chưa quan sát; ngoài phạm vi Phase H nên đặt unsupported."
                    ),
                ]
            ),

            // 3. Page options
            RibbonGroupSpec(
                id: "pageOptions",
                title: Bilingual(vi: "Tuỳ chọn trang", en: "Page options"),
                items: [
                    RibbonItemSpec(
                        id: .gridlines,
                        title: Bilingual(vi: "Đường lưới", en: "Gridlines"),
                        symbol: "grid",
                        tint: .neutral,
                        kind: .checkbox,
                        availability: .pending(Bilingual(
                            vi: "BI Pro chưa hỗ trợ hiển thị đường lưới trên trang",
                            en: "Gridlines display is not yet implemented in BI Pro"
                        ))
                    ),
                    RibbonItemSpec(
                        id: .snapToGrid,
                        title: Bilingual(vi: "Bám lưới", en: "Snap to grid"),
                        symbol: "square.grid.3x3",
                        tint: .brand,
                        kind: .checkbox,
                        availability: .always
                    ),
                    RibbonItemSpec(
                        id: .lockObjects,
                        title: Bilingual(vi: "Khoá đối tượng", en: "Lock objects"),
                        symbol: "lock",
                        tint: .neutral,
                        kind: .checkbox,
                        availability: .pending(Bilingual(
                            vi: "BI Pro chưa hỗ trợ khoá vị trí đối tượng",
                            en: "Lock objects is not yet implemented in BI Pro"
                        ))
                    ),
                ]
            ),

            // 4. Show panes
            RibbonGroupSpec(
                id: "showPanes",
                title: Bilingual(vi: "Hiện ngăn", en: "Show panes"),
                items: [
                    RibbonItemSpec(
                        id: .showFilters,
                        title: Bilingual(vi: "Bộ lọc", en: "Filters"),
                        symbol: "line.3.horizontal.decrease",
                        tint: .neutral,
                        kind: .toggle,
                        availability: .always
                    ),
                    RibbonItemSpec(
                        id: .showBookmarks,
                        title: Bilingual(vi: "Dấu trang", en: "Bookmarks"),
                        symbol: "bookmark",
                        tint: .neutral,
                        kind: .toggle,
                        availability: .always
                    ),
                    RibbonItemSpec(
                        id: .showSelection,
                        title: Bilingual(vi: "Lựa chọn", en: "Selection"),
                        symbol: "square.3.layers.3d",
                        tint: .warning,
                        kind: .toggle,
                        availability: .always
                    ),
                    RibbonItemSpec(
                        id: .performanceAnalyzer,
                        title: Bilingual(vi: "Phân tích hiệu năng", en: "Performance analyzer"),
                        symbol: "gauge.with.dots.needle.67percent",
                        tint: .info,
                        kind: .toggle,
                        availability: .pending(Bilingual(
                            vi: "BI Pro chưa hỗ trợ ngăn Performance analyzer",
                            en: "Performance analyzer pane is not yet implemented in BI Pro"
                        ))
                    ),
                    RibbonItemSpec(
                        id: .syncSlicers,
                        title: Bilingual(vi: "Đồng bộ slicer", en: "Sync slicers"),
                        symbol: "arrow.triangle.2.circlepath",
                        tint: .brand,
                        kind: .large,
                        availability: .pending(Bilingual(
                            vi: "BI Pro chưa hỗ trợ ngăn Sync slicers",
                            en: "Sync slicers pane is not yet implemented in BI Pro"
                        ))
                    ),
                ]
            ),
        ]
    )

    /// Tab **Optimize** ở Report view — đúng 4 nhóm, 5 nút theo `contracts/ribbon-catalog.md` và `rb_optimize-2x.png`.
    static let reportOptimize = RibbonTabSpec(
        id: .optimize,
        title: RibbonTabID.optimize.title,
        contextual: false,
        groups: [
            // 1. Queries
            RibbonGroupSpec(
                id: "queries",
                title: Bilingual(vi: "Truy vấn", en: "Queries"),
                items: [
                    RibbonItemSpec(
                        id: .pauseVisuals,
                        title: Bilingual(vi: "Tạm dừng visual", en: "Pause visuals"),
                        symbol: "pause.rectangle",
                        tint: .info,
                        kind: .large,
                        availability: .pending(Bilingual(
                            vi: "BI Pro chưa hỗ trợ tạm dừng truy vấn visual",
                            en: "Pause visuals is not yet implemented in BI Pro"
                        ))
                    ),
                    RibbonItemSpec(
                        id: .refreshVisuals,
                        title: Bilingual(vi: "Làm mới visual", en: "Refresh visuals"),
                        symbol: "arrow.clockwise.circle",
                        tint: .brand,
                        kind: .large,
                        availability: .always
                    ),
                ]
            ),

            // 2. Report
            RibbonGroupSpec(
                id: "report",
                title: Bilingual(vi: "Báo cáo", en: "Report"),
                items: [
                    RibbonItemSpec(
                        id: .optimizationPresets,
                        title: Bilingual(vi: "Cấu hình tối ưu", en: "Optimization presets"),
                        symbol: "wand.and.stars",
                        tint: .info,
                        kind: .large,
                        hasMenu: true,
                        availability: .pending(Bilingual(
                            vi: "BI Pro chưa hỗ trợ bộ cấu hình tối ưu sẵn",
                            en: "Optimization presets are not yet implemented in BI Pro"
                        )),
                        // [SUY ĐOÁN] Menu thả xuống Optimization presets chưa quan sát trên VM.
                        observed: false,
                        note: "[SUY ĐOÁN] Menu Optimization presets chưa quan sát trên VM; đặt vô hiệu có tooltip."
                    ),
                ]
            ),

            // 3. Review
            RibbonGroupSpec(
                id: "review",
                title: Bilingual(vi: "Đánh giá", en: "Review"),
                items: [
                    RibbonItemSpec(
                        id: .performanceAnalyzer,
                        title: Bilingual(vi: "Phân tích hiệu năng", en: "Performance analyzer"),
                        symbol: "gauge.with.dots.needle.67percent",
                        tint: .info,
                        kind: .large,
                        availability: .pending(Bilingual(
                            vi: "BI Pro chưa hỗ trợ ngăn Performance analyzer",
                            en: "Performance analyzer is not yet implemented in BI Pro"
                        ))
                    ),
                ]
            ),

            // 4. Apply
            RibbonGroupSpec(
                id: "apply",
                title: Bilingual(vi: "Áp dụng", en: "Apply"),
                items: [
                    RibbonItemSpec(
                        id: .applyAllSlicers,
                        title: Bilingual(vi: "Nút áp dụng mọi slicer", en: "Apply all slicers button"),
                        symbol: "rectangle.and.hand.point.up.left",
                        tint: .info,
                        kind: .large,
                        availability: .pending(Bilingual(
                            vi: "BI Pro chưa hỗ trợ chèn nút Apply all slicers",
                            en: "Apply all slicers button is not yet implemented in BI Pro"
                        ))
                    ),
                ]
            ),
        ]
    )

    /// Tab **Help** (dùng chung cho mọi view) — đúng 4 nhóm theo `contracts/ribbon-catalog.md` và `rb_help-2x.png`.
    static let reportHelp = RibbonTabSpec(
        id: .help,
        title: RibbonTabID.help.title,
        contextual: false,
        groups: [
            // 1. Info
            RibbonGroupSpec(
                id: "info",
                title: Bilingual(vi: "Thông tin", en: "Info"),
                items: [
                    RibbonItemSpec(
                        id: .about,
                        title: Bilingual(vi: "Giới thiệu", en: "About"),
                        symbol: "info.circle",
                        tint: .info,
                        kind: .large,
                        availability: .always
                    ),
                ]
            ),

            // 2. Help
            RibbonGroupSpec(
                id: "help",
                title: Bilingual(vi: "Trợ giúp", en: "Help"),
                items: [
                    RibbonItemSpec(
                        id: .guidedLearning,
                        title: Bilingual(vi: "Hướng dẫn học", en: "Guided learning"),
                        symbol: "graduationcap",
                        tint: .indigo,
                        kind: .large,
                        availability: .always
                    ),
                    RibbonItemSpec(
                        id: .trainingVideos,
                        title: Bilingual(vi: "Video đào tạo", en: "Training videos"),
                        symbol: "play.rectangle",
                        tint: .info,
                        kind: .large,
                        availability: .unsupported(Bilingual(
                            vi: "BI Pro hoạt động ngoại tuyến và không mở video trực tuyến",
                            en: "BI Pro works offline and doesn't open online training videos"
                        ))
                    ),
                    RibbonItemSpec(
                        id: .documentation,
                        title: Bilingual(vi: "Tài liệu", en: "Documentation"),
                        symbol: "book.pages",
                        tint: .indigo,
                        kind: .large,
                        availability: .unsupported(Bilingual(
                            vi: "BI Pro hoạt động ngoại tuyến và không mở tài liệu trực tuyến",
                            en: "BI Pro works offline and doesn't open external documentation"
                        ))
                    ),
                    RibbonItemSpec(
                        id: .support,
                        title: Bilingual(vi: "Hỗ trợ", en: "Support"),
                        symbol: "questionmark.circle",
                        tint: .info,
                        kind: .large,
                        availability: .unsupported(Bilingual(
                            vi: "BI Pro hoạt động ngoại tuyến và không mở cổng hỗ trợ Microsoft",
                            en: "BI Pro works offline and doesn't open Microsoft Support"
                        ))
                    ),
                ]
            ),

            // 3. Community
            RibbonGroupSpec(
                id: "community",
                title: Bilingual(vi: "Cộng đồng", en: "Community"),
                items: [
                    RibbonItemSpec(
                        id: .powerBIBlog,
                        title: Bilingual(vi: "Blog Power BI", en: "Power BI blog"),
                        symbol: "newspaper",
                        tint: .neutral,
                        kind: .large,
                        availability: .unsupported(Bilingual(
                            vi: "BI Pro hoạt động ngoại tuyến và không mở liên kết ngoài",
                            en: "BI Pro works offline and doesn't open external links"
                        ))
                    ),
                    RibbonItemSpec(
                        id: .community,
                        title: Bilingual(vi: "Cộng đồng", en: "Community"),
                        symbol: "person.3",
                        tint: .neutral,
                        kind: .large,
                        availability: .unsupported(Bilingual(
                            vi: "BI Pro hoạt động ngoại tuyến và không mở diễn đàn trực tuyến",
                            en: "BI Pro works offline and doesn't open external community forums"
                        ))
                    ),
                    RibbonItemSpec(
                        id: .powerBIForDevelopers,
                        title: Bilingual(vi: "Dành cho lập trình viên", en: "Power BI for developers"),
                        symbol: "chevron.left.forwardslash.chevron.right",
                        tint: .neutral,
                        kind: .large,
                        availability: .unsupported(Bilingual(
                            vi: "BI Pro hoạt động ngoại tuyến và không mở cổng lập trình viên Microsoft",
                            en: "BI Pro works offline and doesn't open the Microsoft developer portal"
                        ))
                    ),
                    RibbonItemSpec(
                        id: .submitAnIdea,
                        title: Bilingual(vi: "Gửi ý tưởng", en: "Submit an idea"),
                        symbol: "lightbulb",
                        tint: .neutral,
                        kind: .large,
                        availability: .unsupported(Bilingual(
                            vi: "BI Pro hoạt động ngoại tuyến và không gửi phản hồi trực tuyến",
                            en: "BI Pro works offline and doesn't submit online ideas"
                        ))
                    ),
                    RibbonItemSpec(
                        id: .externalTools,
                        title: Bilingual(vi: "Công cụ ngoài", en: "External tools"),
                        symbol: "wrench.and.screwdriver",
                        tint: .info,
                        kind: .large,
                        availability: .unsupported(Bilingual(
                            vi: "BI Pro chưa hỗ trợ tích hợp công cụ ngoài của Windows",
                            en: "BI Pro doesn't support Windows External tools integration"
                        ))
                    ),
                ]
            ),

            // 4. Resources
            RibbonGroupSpec(
                id: "resources",
                title: Bilingual(vi: "Tài nguyên", en: "Resources"),
                items: [
                    RibbonItemSpec(
                        id: .examples,
                        title: Bilingual(vi: "Ví dụ mẫu", en: "Examples"),
                        symbol: "doc.text.magnifyingglass",
                        tint: .info,
                        kind: .large,
                        hasMenu: true,
                        availability: .unsupported(Bilingual(
                            vi: "BI Pro hoạt động ngoại tuyến và không tải tệp mẫu trực tuyến",
                            en: "BI Pro works offline and doesn't download online examples"
                        ))
                    ),
                    RibbonItemSpec(
                        id: .consultingServices,
                        title: Bilingual(vi: "Dịch vụ tư vấn", en: "Consulting services"),
                        symbol: "person.2",
                        tint: .info,
                        kind: .large,
                        availability: .unsupported(Bilingual(
                            vi: "BI Pro hoạt động ngoại tuyến và không mở danh mục dịch vụ tư vấn",
                            en: "BI Pro works offline and doesn't open consulting services"
                        ))
                    ),
                ]
            ),
        ]
    )
}

/// Nội dung Popover Giới thiệu BI Pro (dùng ở tab Help ▸ About và File ▸ About).
struct RibbonAboutPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("BI Pro")
                .font(DS.Typeface.headlineLarge)
                .foregroundStyle(DS.Palette.label)
            Text(bi("Phiên bản \(RibbonCatalog.aboutVersionString) · macOS Native",
                    "Version \(RibbonCatalog.aboutVersionString) · macOS Native"))
                .font(DS.Typeface.body)
                .foregroundStyle(DS.Palette.secondaryLabel)
            Text(bi("Mở, chỉnh sửa và lưu .pbix (PBIR & Layout cũ), chạy DAX và Power Query native trên Apple Silicon.",
                    "Open, author, and save .pbix (PBIR & legacy Layout) with native VertiPaq, DAX, and Power Query on Apple Silicon."))
                .font(DS.Typeface.bodySmall)
                .foregroundStyle(DS.Palette.label)
        }
        .padding(16)
        .frame(maxWidth: 320)
    }
}
