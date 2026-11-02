import PBIXKit

/// Visual types, their gallery icons and field wells. Role keys are the PBIR `queryState` role names
/// observed in the user's reports (`Category`, `Y`, `Y2`, `Series`, `Values`, `Rows`, …).
enum VisualCatalog {
    struct Entry { let type: String; let name: String; let symbol: String }
    struct Well { let role: String; let label: String }

    static let gallery: [Entry] = [
        Entry(type: "stackedBarChart", name: "Biểu đồ thanh xếp chồng", symbol: "chart.bar.xaxis"),
        Entry(type: "stackedColumnChart", name: "Biểu đồ cột xếp chồng", symbol: "chart.bar.fill"),
        Entry(type: "clusteredBarChart", name: "Biểu đồ thanh nhóm", symbol: "text.alignleft"),
        Entry(type: "clusteredColumnChart", name: "Biểu đồ cột nhóm", symbol: "chart.bar"),
        Entry(type: "hundredPercentStackedBarChart", name: "Thanh xếp chồng 100%", symbol: "rectangle.split.3x1"),
        Entry(type: "hundredPercentStackedColumnChart", name: "Cột xếp chồng 100%", symbol: "rectangle.split.1x2"),
        Entry(type: "lineChart", name: "Biểu đồ đường", symbol: "chart.xyaxis.line"),
        Entry(type: "areaChart", name: "Biểu đồ vùng", symbol: "chart.line.uptrend.xyaxis"),
        Entry(type: "stackedAreaChart", name: "Vùng xếp chồng", symbol: "square.stack.3d.up"),
        Entry(type: "lineStackedColumnComboChart", name: "Đường và cột xếp chồng", symbol: "chart.bar.doc.horizontal"),
        Entry(type: "lineClusteredColumnComboChart", name: "Đường và cột nhóm", symbol: "chart.bar.xaxis.ascending"),
        Entry(type: "ribbonChart", name: "Biểu đồ ruy băng", symbol: "waveform.path"),
        Entry(type: "waterfallChart", name: "Biểu đồ thác nước", symbol: "chart.bar.xaxis.ascending.badge.clock"),
        Entry(type: "funnel", name: "Biểu đồ phễu", symbol: "line.3.horizontal.decrease"),
        Entry(type: "scatterChart", name: "Biểu đồ phân tán", symbol: "chart.dots.scatter"),
        Entry(type: "pieChart", name: "Biểu đồ tròn", symbol: "chart.pie.fill"),
        Entry(type: "donutChart", name: "Biểu đồ vành khuyên", symbol: "chart.pie"),
        Entry(type: "treemap", name: "Treemap", symbol: "square.grid.3x3.square"),
        Entry(type: "map", name: "Bản đồ", symbol: "map"),
        Entry(type: "filledMap", name: "Bản đồ tô màu", symbol: "map.fill"),
        Entry(type: "shapeMap", name: "Bản đồ hình", symbol: "globe.americas"),
        Entry(type: "gauge", name: "Đồng hồ đo", symbol: "gauge.with.dots.needle.33percent"),
        Entry(type: "cardVisual", name: "Thẻ", symbol: "rectangle.on.rectangle"),
        Entry(type: "card", name: "Thẻ (cũ)", symbol: "123.rectangle"),
        Entry(type: "multiRowCard", name: "Thẻ nhiều hàng", symbol: "list.bullet.rectangle"),
        Entry(type: "kpi", name: "KPI", symbol: "arrow.up.right.square"),
        Entry(type: "slicer", name: "Slicer", symbol: "slider.horizontal.below.rectangle"),
        Entry(type: "tableEx", name: "Bảng", symbol: "tablecells"),
        Entry(type: "pivotTable", name: "Ma trận", symbol: "square.grid.4x3.fill"),
        Entry(type: "textbox", name: "Hộp văn bản", symbol: "textformat"),
        Entry(type: "image", name: "Ảnh", symbol: "photo"),
        Entry(type: "actionButton", name: "Nút", symbol: "rectangle.and.hand.point.up.left"),
        Entry(type: "pageNavigator", name: "Điều hướng trang", symbol: "rectangle.split.3x1.fill"),
        Entry(type: "shape", name: "Hình", symbol: "square.on.circle"),
        Entry(type: "basicShape", name: "Hình", symbol: "square.on.circle"),
    ]

    static func entry(_ type: String) -> Entry? { gallery.first { $0.type == type } }
    static func name(_ type: String) -> String { entry(type)?.name ?? type }
    static func symbol(_ type: String) -> String { entry(type)?.symbol ?? "square.dashed" }

    /// `shape`/`basicShape` and `card`/`cardVisual` share a gallery slot.
    static func matches(_ visualType: String, _ galleryType: String) -> Bool {
        visualType == galleryType || (visualType == "basicShape" && galleryType == "shape")
    }

    static func displayTitle(_ visual: ReportVisual) -> String {
        if let title = visual.containerObjects.string("title", "text"), !title.isEmpty { return title }
        if let text = visual.objects.raw("general", "paragraphs")?.array.first?["textRuns"]?.array.first?["value"]?.string, !text.isEmpty {
            return text
        }
        if !visual.fields.isEmpty { return visual.fields.prefix(2).map(\.label).joined(separator: ", ") }
        return name(visual.type)
    }

    static func wells(for visual: ReportVisual) -> [Well] {
        let t = visual.type
        var wells: [Well]
        switch t {
        case _ where t.contains("Combo"):
            wells = [Well(role: "Category", label: "Trục X"), Well(role: "Y", label: "Trục Y (cột)"),
                     Well(role: "Y2", label: "Trục Y (đường)"), Well(role: "Series", label: "Chú giải cột")]
        case _ where t.hasSuffix("BarChart"):
            wells = [Well(role: "Category", label: "Trục Y"), Well(role: "Y", label: "Trục X"), Well(role: "Series", label: "Chú giải")]
        case _ where t.hasSuffix("ColumnChart") || t == "ribbonChart" || t == "waterfallChart":
            wells = [Well(role: "Category", label: "Trục X"), Well(role: "Y", label: "Trục Y"), Well(role: "Series", label: "Chú giải")]
        case "lineChart", "areaChart", "stackedAreaChart":
            wells = [Well(role: "Category", label: "Trục X"), Well(role: "Y", label: "Trục Y"),
                     Well(role: "Y2", label: "Trục Y phụ"), Well(role: "Series", label: "Chú giải")]
        case "donutChart", "pieChart", "funnel":
            wells = [Well(role: "Category", label: "Chú giải"), Well(role: "Y", label: "Giá trị"), Well(role: "Series", label: "Chi tiết")]
        case "treemap":
            wells = [Well(role: "Group", label: "Danh mục"), Well(role: "Details", label: "Chi tiết"), Well(role: "Values", label: "Giá trị")]
        case "card", "cardVisual", "multiRowCard":
            wells = [Well(role: visual.fields.first?.role ?? "Values", label: "Field")]
        case "slicer", "advancedSlicerVisual":
            wells = [Well(role: "Values", label: "Field")]
        case "tableEx":
            wells = [Well(role: "Values", label: "Cột")]
        case "pivotTable":
            wells = [Well(role: "Rows", label: "Hàng"), Well(role: "Columns", label: "Cột"), Well(role: "Values", label: "Giá trị")]
        case "shapeMap", "filledMap", "map", "azureMap":
            wells = [Well(role: "Category", label: "Vị trí"), Well(role: "Series", label: "Chú giải"), Well(role: "Y", label: "Độ bão hoà màu")]
        case "scatterChart":
            wells = [Well(role: "Category", label: "Giá trị"), Well(role: "Series", label: "Chú giải"),
                     Well(role: "X", label: "Trục X"), Well(role: "Y", label: "Trục Y"), Well(role: "Size", label: "Kích thước")]
        case "kpi":
            wells = [Well(role: "Indicator", label: "Giá trị"), Well(role: "TrendLine", label: "Trục"), Well(role: "Goal", label: "Mục tiêu")]
        case "gauge":
            wells = [Well(role: "Y", label: "Giá trị"), Well(role: "MinValue", label: "Nhỏ nhất"),
                     Well(role: "MaxValue", label: "Lớn nhất"), Well(role: "TargetValue", label: "Mục tiêu")]
        default:
            wells = []
        }
        // Roles present on the visual but unknown to the table still get a well.
        for role in visual.fields.map(\.role) where role != "Tooltips" && !wells.contains(where: { $0.role == role }) {
            wells.append(Well(role: role, label: role))
        }
        if !wells.isEmpty { wells.append(Well(role: "Tooltips", label: "Chú thích công cụ")) }
        return wells
    }
}

/// Display names for formatting objects and properties.
enum FormatNames {
    static func object(_ key: String) -> String {
        let names = [
            "categoryAxis": "Trục X", "valueAxis": "Trục Y", "legend": "Chú giải", "dataPoint": "Màu dữ liệu",
            "labels": "Nhãn dữ liệu", "categoryLabels": "Nhãn danh mục", "title": "Tiêu đề", "subTitle": "Tiêu đề phụ",
            "background": "Nền", "border": "Viền", "padding": "Khoảng đệm", "dropShadow": "Đổ bóng",
            "visualHeader": "Biểu tượng tiêu đề", "visualLink": "Hành động", "general": "Chung", "data": "Dữ liệu",
            "header": "Tiêu đề slicer", "items": "Mục", "fill": "Tô màu", "outline": "Viền ngoài", "text": "Văn bản",
            "icon": "Biểu tượng", "shape": "Hình dạng", "imageScaling": "Co giãn ảnh", "lineStyles": "Kiểu đường",
            "plotArea": "Vùng vẽ", "gridlines": "Đường lưới", "columnHeaders": "Tiêu đề cột", "values": "Giá trị",
            "total": "Tổng", "grid": "Lưới", "stylePreset": "Kiểu mẫu", "visualTooltip": "Chú thích công cụ",
            "selection": "Lựa chọn", "slider": "Thanh trượt", "date": "Ngày", "numericInputStyle": "Ô nhập số",
            "zoom": "Thanh thu phóng", "ySecondaryAxis": "Trục Y phụ", "lineStyle": "Kiểu đường", "markers": "Điểm đánh dấu",
        ]
        return names[key] ?? humanize(key)
    }

    static func property(_ key: String) -> String {
        let names = [
            "fontSize": "Cỡ chữ", "fontFamily": "Phông chữ", "fontColor": "Màu chữ", "color": "Màu", "bold": "Đậm",
            "italic": "Nghiêng", "transparency": "Độ trong suốt", "text": "Nội dung", "alignment": "Căn lề",
            "labelDisplayUnits": "Đơn vị hiển thị", "labelPrecision": "Số chữ số thập phân", "position": "Vị trí",
            "radius": "Bo góc", "width": "Độ dày", "top": "Trên", "bottom": "Dưới", "left": "Trái", "right": "Phải",
            "fill": "Màu tô", "fillColor": "Màu tô", "lineColor": "Màu đường", "weight": "Độ dày", "mode": "Kiểu",
            "type": "Loại", "bookmark": "Bookmark", "imageUrl": "Ảnh", "imageScalingType": "Co giãn",
            "verticalAlignment": "Căn dọc", "horizontalAlignment": "Căn ngang", "textSize": "Cỡ chữ",
            "showAxisTitle": "Tiêu đề trục", "labelColor": "Màu nhãn", "titleText": "Tiêu đề", "start": "Bắt đầu", "end": "Kết thúc",
        ]
        return names[key] ?? humanize(key)
    }

    static func humanize(_ key: String) -> String {
        var out = ""
        for ch in key {
            if ch.isUppercase, !out.isEmpty { out += " " }
            out.append(ch)
        }
        return out.prefix(1).uppercased() + out.dropFirst().lowercased()
    }
}
