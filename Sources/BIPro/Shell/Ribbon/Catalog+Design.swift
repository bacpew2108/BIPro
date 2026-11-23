import Foundation

extension RibbonCatalog {
    /// Tab **Design** ở Report view — đúng 3 nhóm theo `contracts/ribbon-catalog.md` và `rb_design-2x.png`.
    static let reportDesign = RibbonTabSpec(
        id: .design,
        title: RibbonTabID.design.title,
        contextual: false,
        groups: [
            // 1. Themes
            RibbonGroupSpec(
                id: "themes",
                title: Bilingual(vi: "Chủ đề", en: "Themes"),
                items: [
                    RibbonItemSpec(
                        id: .themeGallery6,
                        title: Bilingual(vi: "Chủ đề", en: "Themes"),
                        symbol: "paintpalette",
                        tint: .brand,
                        kind: .gallery(.themes6),
                        hasMenu: true,
                        availability: .always,
                        // [SUY ĐOÁN] Tên từng theme trong 9 ô Power BI ở `dd_themes.png` chưa có nhãn chữ; dùng preset BI Pro.
                        observed: false,
                        note: "[SUY ĐOÁN] Tên cụ thể 9 ô mẫu theme Power BI trong dd_themes.png chưa quan sát; nối vào ThemeCatalog hiện có."
                    ),
                    RibbonItemSpec(
                        id: .themeGallery,
                        title: Bilingual(vi: "Thư viện chủ đề", en: "Theme gallery"),
                        symbol: "square.grid.2x2",
                        tint: .neutral,
                        kind: .large,
                        availability: .pending(Bilingual(
                            vi: "BI Pro chưa hỗ trợ thư viện chủ đề trực tuyến",
                            en: "Online theme gallery is not yet implemented in BI Pro"
                        ))
                    ),
                    RibbonItemSpec(
                        id: .themeActionsStack,
                        title: Bilingual(vi: "Chủ đề", en: "Themes"),
                        symbol: "paintpalette",
                        kind: .smallStack([
                            RibbonItemSpec(
                                id: .customizeTheme,
                                title: Bilingual(vi: "Tuỳ chỉnh chủ đề", en: "Customize theme"),
                                symbol: "slider.horizontal.3",
                                tint: .brand,
                                kind: .large,
                                availability: .pending(Bilingual(
                                    vi: "BI Pro chưa hỗ trợ hộp thoại tuỳ chỉnh chủ đề trực quan",
                                    en: "Customize theme dialog is not yet implemented in BI Pro"
                                )),
                                // [SUY ĐOÁN] Hộp Customize theme chưa quan sát trên VM.
                                observed: false,
                                note: "[SUY ĐOÁN] Hộp thoại Customize theme chưa quan sát trên VM; đặt vô hiệu có tooltip."
                            ),
                            RibbonItemSpec(
                                id: .downloadTheme,
                                title: Bilingual(vi: "Tải chủ đề xuống", en: "Download theme"),
                                symbol: "square.and.arrow.down",
                                tint: .info,
                                kind: .large,
                                availability: .always
                            ),
                            RibbonItemSpec(
                                id: .importTheme,
                                title: Bilingual(vi: "Nhập chủ đề", en: "Import theme"),
                                symbol: "square.and.arrow.up",
                                tint: .brand,
                                kind: .large,
                                availability: .always
                            ),
                        ]),
                        availability: .always
                    ),
                ]
            ),

            // 2. Customize page
            RibbonGroupSpec(
                id: "customizePage",
                title: Bilingual(vi: "Tuỳ chỉnh trang", en: "Customize page"),
                items: [
                    RibbonItemSpec(
                        id: .pageSize,
                        title: Bilingual(vi: "Cỡ trang", en: "Page size"),
                        symbol: "aspectratio",
                        tint: .info,
                        kind: .large,
                        hasMenu: true,
                        availability: .pending(Bilingual(
                            vi: "BI Pro chưa hỗ trợ đổi cỡ trang trực tiếp từ Ribbon",
                            en: "Page size customization from the Ribbon is not yet implemented in BI Pro"
                        ))
                    ),
                    RibbonItemSpec(
                        id: .pageBackground,
                        title: Bilingual(vi: "Nền trang", en: "Page background"),
                        symbol: "doc.fill",
                        tint: .info,
                        kind: .large,
                        availability: .pending(Bilingual(
                            vi: "BI Pro chưa hỗ trợ chỉnh nền trang từ Ribbon",
                            en: "Page background customization is not yet implemented in BI Pro"
                        ))
                    ),
                    RibbonItemSpec(
                        id: .wallpaper,
                        title: Bilingual(vi: "Hình nền", en: "Wallpaper"),
                        symbol: "photo.on.rectangle",
                        tint: .info,
                        kind: .large,
                        availability: .pending(Bilingual(
                            vi: "BI Pro chưa hỗ trợ chỉnh hình nền từ Ribbon",
                            en: "Wallpaper customization is not yet implemented in BI Pro"
                        ))
                    ),
                ]
            ),

            // 3. Help
            RibbonGroupSpec(
                id: "help",
                title: Bilingual(vi: "Trợ giúp", en: "Help"),
                items: [
                    RibbonItemSpec(
                        id: .howToCreateTheme,
                        title: Bilingual(vi: "Cách tạo chủ đề", en: "How to create a theme"),
                        symbol: "book.closed",
                        tint: .info,
                        kind: .large,
                        availability: .unsupported(Bilingual(
                            vi: "BI Pro hoạt động ngoại tuyến và không mở tài liệu trực tuyến của Microsoft",
                            en: "BI Pro works offline and doesn't open external Microsoft documentation"
                        ))
                    ),
                ]
            ),
        ]
    )
}
