# Hợp đồng: lưới biểu tượng visual (pane Visualizations)

Lưới 6 cột, ô ≈ 24 pt, cách ≈ 24 pt, theo ảnh `docs/phase-ui-evidence/vm-ui/o_now.png` và `p_format.png` (vùng "Build visual"). **Ảnh là chuẩn cuối cùng**; bảng dưới là thứ tự đã công bố của Power BI Desktop và đánh dấu `[SUY ĐOÁN]` vì chưa đối chiếu được từng biểu tượng. Worker mở ảnh, đối chiếu từng hàng, sửa bảng này nếu lệch và ghi vào báo cáo.

Quy tắc hiển thị:
- Visual BI Pro đã hỗ trợ (cột "Loại BI Pro" khác `—`): bấm chèn được như hiện nay (`DocumentState.insertVisual`), biểu tượng SF Symbols hai màu theo `VisualCatalog`.
- Visual BI Pro chưa hỗ trợ (`—`): vẫn vẽ đúng ô, **mờ, không bấm được**, tooltip song ngữ "BI Pro chưa hỗ trợ visual này" / "BI Pro doesn't support this visual yet".
- Hàng cuối (visual nhập/tuỳ chỉnh và nút `…` "Get more visuals"): vẽ mờ có tooltip, không làm tính năng.

| Hàng | Ô 1 | Ô 2 | Ô 3 | Ô 4 | Ô 5 | Ô 6 |
|---|---|---|---|---|---|---|
| 1 | Stacked bar (`barChart`) | Stacked column (`columnChart`) | Clustered bar (`clusteredBarChart`) | Clustered column (`clusteredColumnChart`) | 100% stacked bar (`hundredPercentStackedBarChart`) | 100% stacked column (`hundredPercentStackedColumnChart`) |
| 2 | Line (`lineChart`) | Area (`areaChart`) | Stacked area (`stackedAreaChart`) | Line and stacked column (`lineStackedColumnComboChart`) | Line and clustered column (`lineClusteredColumnComboChart`) | Ribbon (`ribbonChart`) |
| 3 | Waterfall (`waterfallChart`) | Funnel (`funnel`) | Scatter (`scatterChart`) | Pie (`pieChart`) | Donut (`donutChart`) | Treemap (`treemap`) |
| 4 | Map (`map`) | Filled map (`filledMap`) | Azure map (—) | Gauge (`gauge`) | Card (`cardVisual`) | Multi-row card (`multiRowCard`) |
| 5 | KPI (`kpi`) | Slicer (`slicer`) | Table (`tableEx`) | Matrix (`pivotTable`) | R script (—) | Python script (—) |
| 6 | Key influencers (—) | Decomposition tree (—) | Q&A (—) | Smart narrative (—) | Paginated report (—) | Power Apps (—) |
| 7 | Power Automate (—) | ArcGIS Maps (—) | `…` Get more visuals (—) | | | |

Ghi chú:
- Ở bản chụp (`o_now.png`) hàng 7 có thêm một dãy visual nhập/tuỳ chỉnh (≈ 5 ô); vẽ mờ như trên, số ô theo ảnh.
- BI Pro có thêm loại không nằm trong lưới Desktop: `hundredPercentStackedAreaChart`, `shapeMap`, `advancedSlicerVisual`, `listSlicer`, `textSlicer`, `textbox`, `image`, `actionButton`, `pageNavigator`, `bookmarkNavigator`, `shape`/`basicShape`. Chúng **không** đưa vào lưới này; chèn qua Ribbon Insert (Text box, Buttons, Shapes, Image), `More visuals ▾` (popover `VisualCatalog`) và đổi loại ở pane Build hiện có.
- Mọi ô có `accessibilityLabel` = tên EN/VI của visual.

Kiểm thử (`PaneParityTests`): thứ tự loại trong lưới bằng bảng trên (các ô `—` được so bằng nhãn EN); ô `—` có `disabled == true` và tooltip không rỗng; ô có loại BI Pro gọi đúng `insertVisual(type)`.
