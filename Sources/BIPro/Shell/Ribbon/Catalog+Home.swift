import Foundation

extension RibbonCatalog {
    /// Tab **Home** ở Report view — đúng 8 nhóm, 21 dòng mục top-level theo `contracts/ribbon-catalog.md` và ảnh `rb_home-2x.png`.
    static let reportHome = RibbonTabSpec(
        id: .home,
        title: RibbonTabID.home.title,
        contextual: false,
        groups: [
            // 1. Clipboard
            RibbonGroupSpec(
                id: "clipboard",
                title: Bilingual(vi: "Bảng nhớ tạm", en: "Clipboard"),
                items: [
                    RibbonItemSpec(
                        id: .paste,
                        title: Bilingual(vi: "Dán", en: "Paste"),
                        symbol: "doc.on.clipboard",
                        tint: .warning,
                        kind: .large,
                        availability: .when(
                            { $0.canEditCanvasNow && $0.clipboardHasVisual },
                            disabledReason: Bilingual(
                                vi: "Chưa sao chép visual nào hoặc chưa bật chế độ Sửa (⌘E)",
                                en: "Clipboard is empty or Edit mode (⌘E) is off"
                            )
                        )
                    ),
                    RibbonItemSpec(
                        id: .clipboardStack,
                        title: Bilingual(vi: "Bảng nhớ tạm", en: "Clipboard"),
                        symbol: "scissors",
                        kind: .smallStack([
                            RibbonItemSpec(
                                id: .cut,
                                title: Bilingual(vi: "Cắt", en: "Cut"),
                                symbol: "scissors",
                                tint: .neutral,
                                kind: .large,
                                availability: .when(
                                    { $0.canEditCanvasNow && $0.visualSelected },
                                    disabledReason: Bilingual(
                                        vi: "Chọn visual ở chế độ Sửa",
                                        en: "Select a visual in Edit mode"
                                    )
                                )
                            ),
                            RibbonItemSpec(
                                id: .copy,
                                title: Bilingual(vi: "Sao chép", en: "Copy"),
                                symbol: "doc.on.doc",
                                tint: .neutral,
                                kind: .large,
                                availability: .when(
                                    { $0.canEditCanvasNow && $0.visualSelected },
                                    disabledReason: Bilingual(
                                        vi: "Chọn visual ở chế độ Sửa",
                                        en: "Select a visual in Edit mode"
                                    )
                                )
                            ),
                            RibbonItemSpec(
                                id: .formatPainter,
                                title: Bilingual(vi: "Sao định dạng", en: "Format painter"),
                                symbol: "paintbrush",
                                tint: .warning,
                                kind: .toggle,
                                availability: .when(
                                    { ($0.canEditCanvasNow && $0.visualSelected && !$0.multiSelected) || $0.isFormatPainterActive },
                                    disabledReason: Bilingual(
                                        vi: "Chọn 1 visual nguồn ở chế độ Sửa",
                                        en: "Select 1 source visual in Edit mode"
                                    )
                                )
                            ),
                        ]),
                        availability: .always
                    ),
                ]
            ),

            // 2. Data
            RibbonGroupSpec(
                id: "data",
                title: Bilingual(vi: "Dữ liệu", en: "Data"),
                items: [
                    RibbonItemSpec(
                        id: .getData,
                        title: Bilingual(vi: "Lấy dữ liệu", en: "Get data"),
                        symbol: "cylinder.split.1x2",
                        tint: .data,
                        kind: .large,
                        hasMenu: true,
                        availability: .when(
                            { $0.hasModel },
                            disabledReason: Bilingual(
                                vi: "File không có mô hình dữ liệu để nạp bảng",
                                en: "File has no data model to load tables"
                            )
                        )
                    ),
                    RibbonItemSpec(
                        id: .excelWorkbook,
                        title: Bilingual(vi: "Sổ làm việc Excel", en: "Excel workbook"),
                        symbol: "tablecells.badge.ellipsis",
                        tint: .excel,
                        kind: .large,
                        availability: .when(
                            { $0.hasModel },
                            disabledReason: Bilingual(
                                vi: "File không có mô hình dữ liệu để nạp bảng",
                                en: "File has no data model to load tables"
                            )
                        )
                    ),
                    RibbonItemSpec(
                        id: .oneLakeCatalog,
                        title: Bilingual(vi: "Danh mục OneLake", en: "OneLake catalog"),
                        symbol: "externaldrive.connected.to.line.below",
                        tint: .teal,
                        kind: .large,
                        hasMenu: true,
                        availability: .unsupported(Bilingual(
                            vi: "BI Pro chưa hỗ trợ OneLake catalog (dịch vụ đám mây Microsoft Fabric)",
                            en: "BI Pro doesn't support OneLake catalog (Microsoft Fabric cloud service)"
                        ))
                    ),
                    RibbonItemSpec(
                        id: .sqlServer,
                        title: Bilingual(vi: "SQL Server", en: "SQL Server"),
                        symbol: "server.rack",
                        tint: .sql,
                        kind: .large,
                        availability: .when(
                            { $0.hasModel },
                            disabledReason: Bilingual(
                                vi: "File không có mô hình dữ liệu để kết nối CSDL (hỗ trợ PostgreSQL, SQLite)",
                                en: "File has no data model for database connections (supports PostgreSQL, SQLite)"
                            )
                        )
                    ),
                    RibbonItemSpec(
                        id: .enterData,
                        title: Bilingual(vi: "Nhập dữ liệu", en: "Enter data"),
                        symbol: "square.and.pencil",
                        tint: .teal,
                        kind: .large,
                        availability: .when(
                            { $0.hasModel },
                            disabledReason: Bilingual(
                                vi: "File không có mô hình dữ liệu để nhập bảng",
                                en: "File has no data model to enter tables"
                            )
                        )
                    ),
                    RibbonItemSpec(
                        id: .dataverse,
                        title: Bilingual(vi: "Dataverse", en: "Dataverse"),
                        symbol: "infinity.circle",
                        tint: .excel,
                        kind: .large,
                        availability: .unsupported(Bilingual(
                            vi: "BI Pro chưa hỗ trợ Microsoft Dataverse",
                            en: "BI Pro doesn't support Microsoft Dataverse"
                        ))
                    ),
                    RibbonItemSpec(
                        id: .recentSources,
                        title: Bilingual(vi: "Nguồn gần đây", en: "Recent sources"),
                        symbol: "clock.arrow.circlepath",
                        tint: .neutral,
                        kind: .large,
                        hasMenu: true,
                        availability: .pending(Bilingual(
                            vi: "BI Pro chưa hỗ trợ danh sách nguồn dữ liệu gần đây",
                            en: "Recent sources is not yet implemented in BI Pro"
                        ))
                    ),
                ]
            ),

            // 3. Queries
            RibbonGroupSpec(
                id: "queries",
                title: Bilingual(vi: "Truy vấn", en: "Queries"),
                items: [
                    RibbonItemSpec(
                        id: .transformData,
                        title: Bilingual(vi: "Biến đổi dữ liệu", en: "Transform data"),
                        symbol: "slider.horizontal.3",
                        tint: .info,
                        kind: .large,
                        hasMenu: true,
                        availability: .when(
                            { $0.hasModel },
                            disabledReason: Bilingual(
                                vi: "File không có mô hình dữ liệu để biến đổi",
                                en: "File has no data model to transform"
                            )
                        )
                    ),
                    RibbonItemSpec(
                        id: .refresh,
                        title: Bilingual(vi: "Làm mới", en: "Refresh"),
                        symbol: "arrow.clockwise",
                        tint: .teal,
                        kind: .large,
                        hasMenu: true,
                        availability: .when(
                            { $0.hasData && !$0.isRefreshing },
                            disabledReason: Bilingual(
                                vi: "Cần dữ liệu trong mô hình để làm mới",
                                en: "Requires data in the model to refresh"
                            )
                        )
                    ),
                ]
            ),

            // 4. Insert
            RibbonGroupSpec(
                id: "insert",
                title: Bilingual(vi: "Chèn", en: "Insert"),
                items: [
                    RibbonItemSpec(
                        id: .newVisual,
                        title: Bilingual(vi: "Visual mới", en: "New visual"),
                        symbol: "chart.bar.doc.horizontal",
                        tint: .data,
                        kind: .large,
                        availability: .when(
                            { $0.canEditPBIRVisualsNow },
                            disabledReason: Bilingual(
                                vi: "Bật chế độ Sửa (⌘E) trên báo cáo PBIR để thêm visual",
                                en: "Enable Edit mode (⌘E) on a PBIR report to insert visuals"
                            )
                        )
                    ),
                    RibbonItemSpec(
                        id: .textBox,
                        title: Bilingual(vi: "Hộp văn bản", en: "Text box"),
                        symbol: "textformat",
                        tint: .info,
                        kind: .large,
                        availability: .when(
                            { $0.canEditPBIRVisualsNow },
                            disabledReason: Bilingual(
                                vi: "Bật chế độ Sửa (⌘E) trên báo cáo PBIR để thêm hộp văn bản",
                                en: "Enable Edit mode (⌘E) on a PBIR report to insert a text box"
                            )
                        )
                    ),
                    RibbonItemSpec(
                        id: .moreVisuals,
                        title: Bilingual(vi: "Thêm visual", en: "More visuals"),
                        symbol: "chart.bar.xaxis.ascending.badge.clock",
                        tint: .info,
                        kind: .large,
                        hasMenu: true,
                        availability: .when(
                            { $0.canEditPBIRVisualsNow },
                            disabledReason: Bilingual(
                                vi: "Bật chế độ Sửa (⌘E) trên báo cáo PBIR để chọn thêm visual",
                                en: "Enable Edit mode (⌘E) on a PBIR report to browse more visuals"
                            )
                        )
                    ),
                ]
            ),

            // 5. Calculations
            RibbonGroupSpec(
                id: "calculations",
                title: Bilingual(vi: "Tính toán", en: "Calculations"),
                items: [
                    RibbonItemSpec(
                        id: .newVisualCalculation,
                        title: Bilingual(vi: "Phép tính visual mới", en: "New visual calculation"),
                        symbol: "function",
                        tint: .neutral,
                        kind: .large,
                        hasMenu: true,
                        availability: .pending(Bilingual(
                            vi: "BI Pro chưa hỗ trợ phép tính visual (Visual calculation)",
                            en: "Visual calculations are not yet implemented in BI Pro"
                        ))
                    ),
                    RibbonItemSpec(
                        id: .newMeasure,
                        title: Bilingual(vi: "Measure mới", en: "New measure"),
                        symbol: "function",
                        tint: .calculation,
                        kind: .large,
                        availability: .when(
                            { $0.canEditModel && $0.hasData },
                            disabledReason: Bilingual(
                                vi: "Cần mô hình có dữ liệu và chế độ Sửa để tạo measure",
                                en: "Requires data model in Edit mode to create a measure"
                            )
                        )
                    ),
                    RibbonItemSpec(
                        id: .quickMeasure,
                        title: Bilingual(vi: "Measure nhanh", en: "Quick measure"),
                        symbol: "bolt",
                        tint: .calculation,
                        kind: .large,
                        availability: .when(
                            { $0.canEditModel && $0.hasBaseMeasures },
                            disabledReason: Bilingual(
                                vi: "Cần ít nhất 1 measure gốc ở chế độ Sửa",
                                en: "Requires at least 1 base measure in Edit mode"
                            )
                        )
                    ),
                ]
            ),

            // 6. Sensitivity
            RibbonGroupSpec(
                id: "sensitivity",
                title: Bilingual(vi: "Độ nhạy", en: "Sensitivity"),
                items: [
                    RibbonItemSpec(
                        id: .sensitivity,
                        title: Bilingual(vi: "Độ nhạy", en: "Sensitivity"),
                        symbol: "lock.shield",
                        tint: .info,
                        kind: .large,
                        hasMenu: true,
                        availability: .unsupported(Bilingual(
                            vi: "BI Pro chưa hỗ trợ nhãn độ nhạy (Microsoft Purview Sensitivity)",
                            en: "BI Pro doesn't support Microsoft Purview Sensitivity labels"
                        ))
                    ),
                ]
            ),

            // 7. Share
            RibbonGroupSpec(
                id: "share",
                title: Bilingual(vi: "Chia sẻ", en: "Share"),
                items: [
                    RibbonItemSpec(
                        id: .publish,
                        title: Bilingual(vi: "Xuất bản", en: "Publish"),
                        symbol: "square.and.arrow.up.on.square",
                        tint: .info,
                        kind: .large,
                        availability: .unsupported(Bilingual(
                            vi: "BI Pro chạy ngoại tuyến và chưa hỗ trợ xuất bản lên Power BI Service",
                            en: "BI Pro works offline and doesn't support publishing to Power BI Service"
                        ))
                    ),
                ]
            ),

            // 8. Copilot
            RibbonGroupSpec(
                id: "copilot",
                title: Bilingual(vi: "Copilot", en: "Copilot"),
                items: [
                    RibbonItemSpec(
                        id: .prepDataForAI,
                        title: Bilingual(vi: "Chuẩn bị dữ liệu AI", en: "Prep data for AI"),
                        symbol: "sparkles.rectangle.stack",
                        tint: .copilot,
                        kind: .large,
                        availability: .unsupported(Bilingual(
                            vi: "BI Pro chưa hỗ trợ chuẩn bị dữ liệu cho AI (Microsoft Fabric)",
                            en: "BI Pro doesn't support Prep data for AI (Microsoft Fabric)"
                        ))
                    ),
                    RibbonItemSpec(
                        id: .copilot,
                        title: Bilingual(vi: "Copilot", en: "Copilot"),
                        symbol: "sparkles",
                        tint: .copilot,
                        kind: .large,
                        availability: .unsupported(Bilingual(
                            vi: "BI Pro chưa hỗ trợ Copilot",
                            en: "BI Pro doesn't support Copilot"
                        ))
                    ),
                ]
            ),
        ]
    )
}
