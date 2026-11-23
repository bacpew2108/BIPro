import Foundation

/// Namespace để `--filter UIParity` khớp mọi bộ test Phase H trong `Tests/BIProTests/UIParity/`.
enum UIParity {}

/// Dữ liệu chuẩn viết tay từ `specs/016-h-giao-dien-giong-powerbi/contracts/ribbon-catalog.md`.
/// KHÔNG sinh từ `RibbonCatalog` đang test (quy tắc mục 0 của `docs/tasks/h-master.md`).
enum RibbonReference {
    enum RefKind: Equatable, Sendable {
        case large
        case smallStack([RefItem])
        case checkbox
        case field
        case gallery
        case toggle
    }

    enum RefAvail: Equatable, Sendable {
        case always
        case contextual   // D, V, V-edit, A-edit, M, M-edit, T, C
        case unsupported  // X (Windows/cloud)
        case pending      // P (chưa làm)
    }

    struct RefItem: Equatable, Sendable {
        let id: String
        let en: String
        let kind: RefKind
        let hasMenu: Bool
        let avail: RefAvail
        let observed: Bool

        init(
            _ id: String,
            en: String,
            kind: RefKind = .large,
            hasMenu: Bool = false,
            avail: RefAvail = .contextual,
            observed: Bool = true
        ) {
            self.id = id
            self.en = en
            self.kind = kind
            self.hasMenu = hasMenu
            self.avail = avail
            self.observed = observed
        }
    }

    struct RefGroup: Equatable, Sendable {
        let en: String
        let items: [RefItem]
    }

    struct RefTab: Equatable, Sendable {
        let tabID: String
        let contextual: Bool
        let groups: [RefGroup]
    }

    // MARK: - Bảng tab theo view (contracts/ribbon-catalog.md mục "Quy ước")

    struct ViewTabExpectation: Equatable, Sendable {
        let modeRaw: String
        let visualSelected: Bool
        let tabs: [String]
    }

    static let tabsByView: [ViewTabExpectation] = [
        ViewTabExpectation(
            modeRaw: "report",
            visualSelected: false,
            tabs: ["file", "home", "insert", "modeling", "design", "view", "optimize", "help"]
        ),
        ViewTabExpectation(
            modeRaw: "report",
            visualSelected: true,
            tabs: ["file", "home", "insert", "modeling", "design", "view", "optimize", "help", "format", "dataDrill"]
        ),
        ViewTabExpectation(
            modeRaw: "table",
            visualSelected: false,
            tabs: ["file", "home", "help", "tableTools", "columnTools"]
        ),
        ViewTabExpectation(
            modeRaw: "model",
            visualSelected: false,
            tabs: ["file", "home", "help"]
        ),
        ViewTabExpectation(
            modeRaw: "daxQuery",
            visualSelected: false,
            tabs: ["file", "home", "help"]
        ),
        ViewTabExpectation(
            modeRaw: "tmdl",
            visualSelected: false,
            tabs: ["file", "home", "help"]
        ),
    ]

    // MARK: - Report — Home (8 nhóm, 21 dòng mục top-level)

    static let reportHome = RefTab(
        tabID: "home",
        contextual: false,
        groups: [
            RefGroup(en: "Clipboard", items: [
                RefItem("paste", en: "Paste", kind: .large, avail: .contextual),
                RefItem("clipboardStack", en: "Clipboard", kind: .smallStack([
                    RefItem("cut", en: "Cut", kind: .large, avail: .contextual),
                    RefItem("copy", en: "Copy", kind: .large, avail: .contextual),
                    RefItem("formatPainter", en: "Format painter", kind: .toggle, avail: .contextual),
                ]), avail: .always),
            ]),
            RefGroup(en: "Data", items: [
                RefItem("getData", en: "Get data", kind: .large, hasMenu: true, avail: .contextual),
                RefItem("excelWorkbook", en: "Excel workbook", kind: .large, avail: .contextual),
                RefItem("oneLakeCatalog", en: "OneLake catalog", kind: .large, hasMenu: true, avail: .unsupported),
                RefItem("sqlServer", en: "SQL Server", kind: .large, avail: .contextual),
                RefItem("enterData", en: "Enter data", kind: .large, avail: .contextual),
                RefItem("dataverse", en: "Dataverse", kind: .large, avail: .unsupported),
                RefItem("recentSources", en: "Recent sources", kind: .large, hasMenu: true, avail: .pending),
            ]),
            RefGroup(en: "Queries", items: [
                RefItem("transformData", en: "Transform data", kind: .large, hasMenu: true, avail: .contextual),
                RefItem("refresh", en: "Refresh", kind: .large, hasMenu: true, avail: .contextual),
            ]),
            RefGroup(en: "Insert", items: [
                RefItem("newVisual", en: "New visual", kind: .large, avail: .contextual),
                RefItem("textBox", en: "Text box", kind: .large, avail: .contextual),
                RefItem("moreVisuals", en: "More visuals", kind: .large, hasMenu: true, avail: .contextual),
            ]),
            RefGroup(en: "Calculations", items: [
                RefItem("newVisualCalculation", en: "New visual calculation", kind: .large, hasMenu: true, avail: .pending),
                RefItem("newMeasure", en: "New measure", kind: .large, avail: .contextual),
                RefItem("quickMeasure", en: "Quick measure", kind: .large, avail: .contextual),
            ]),
            RefGroup(en: "Sensitivity", items: [
                RefItem("sensitivity", en: "Sensitivity", kind: .large, hasMenu: true, avail: .unsupported),
            ]),
            RefGroup(en: "Share", items: [
                RefItem("publish", en: "Publish", kind: .large, avail: .unsupported),
            ]),
            RefGroup(en: "Copilot", items: [
                RefItem("prepDataForAI", en: "Prep data for AI", kind: .large, avail: .unsupported),
                RefItem("copilot", en: "Copilot", kind: .large, avail: .unsupported),
            ]),
        ]
    )

    // MARK: - Report — Insert (6 nhóm)

    static let reportInsert = RefTab(
        tabID: "insert",
        contextual: false,
        groups: [
            RefGroup(en: "Pages", items: [
                RefItem("newPage", en: "New page", kind: .large, hasMenu: true, avail: .contextual),
            ]),
            RefGroup(en: "Visuals", items: [
                RefItem("newVisual", en: "New visual", kind: .large, avail: .contextual),
                RefItem("moreVisuals", en: "More visuals", kind: .large, hasMenu: true, avail: .contextual),
            ]),
            RefGroup(en: "AI visuals", items: [
                RefItem("keyInfluencers", en: "Key influencers", kind: .large, avail: .pending),
                RefItem("decompositionTree", en: "Decomposition tree", kind: .large, avail: .pending),
                RefItem("narrative", en: "Narrative", kind: .large, avail: .pending),
            ]),
            RefGroup(en: "Power Platform", items: [
                RefItem("paginatedReport", en: "Paginated report", kind: .large, avail: .unsupported),
                RefItem("powerApps", en: "Power Apps", kind: .large, avail: .unsupported),
                RefItem("powerAutomate", en: "Power Automate", kind: .large, avail: .unsupported),
            ]),
            RefGroup(en: "Elements", items: [
                RefItem("textBox", en: "Text box", kind: .large, avail: .contextual),
                RefItem("buttons", en: "Buttons", kind: .large, hasMenu: true, avail: .contextual),
                RefItem("shapes", en: "Shapes", kind: .large, hasMenu: true, avail: .contextual),
                RefItem("image", en: "Image", kind: .large, avail: .contextual),
            ]),
            RefGroup(en: "Sparklines", items: [
                RefItem("addSparkline", en: "Add a sparkline", kind: .large, avail: .pending),
            ]),
        ]
    )

    // MARK: - Report — Modeling (7 nhóm)

    static let reportModeling = RefTab(
        tabID: "modeling",
        contextual: false,
        groups: [
            RefGroup(en: "Relationships", items: [
                RefItem("manageRelationships", en: "Manage relationships", kind: .large, avail: .contextual),
            ]),
            RefGroup(en: "Calculations", items: [
                RefItem("newVisualCalculation", en: "New visual calculation", kind: .large, hasMenu: true, avail: .pending),
                RefItem("newMeasure", en: "New measure", kind: .large, avail: .contextual),
                RefItem("quickMeasure", en: "Quick measure", kind: .large, avail: .contextual),
                RefItem("newColumn", en: "New column", kind: .large, avail: .contextual),
                RefItem("newTable", en: "New table", kind: .large, avail: .contextual),
            ]),
            RefGroup(en: "Calendars", items: [
                RefItem("markAsDateTable", en: "Mark as date table", kind: .large, avail: .contextual),
            ]),
            RefGroup(en: "Page refresh", items: [
                RefItem("changeDetection", en: "Change detection", kind: .large, avail: .unsupported),
            ]),
            RefGroup(en: "Parameters", items: [
                RefItem("newParameter", en: "New parameter", kind: .large, hasMenu: true, avail: .pending),
            ]),
            RefGroup(en: "Security", items: [
                RefItem("manageRoles", en: "Manage roles", kind: .large, avail: .contextual),
                RefItem("viewAs", en: "View as", kind: .toggle, avail: .contextual),
            ]),
            RefGroup(en: "Q&A", items: [
                RefItem("qnaSetup", en: "Q&A setup", kind: .large, avail: .unsupported),
                RefItem("language", en: "Language", kind: .large, hasMenu: true, avail: .unsupported),
                RefItem("linguisticSchema", en: "Linguistic schema", kind: .large, hasMenu: true, avail: .unsupported),
            ]),
        ]
    )

    // MARK: - Report — Design (3 nhóm)

    static let reportDesign = RefTab(
        tabID: "design",
        contextual: false,
        groups: [
            RefGroup(en: "Themes", items: [
                RefItem("themeGallery6", en: "Themes", kind: .gallery, hasMenu: true, avail: .always, observed: false),
                RefItem("themeGallery", en: "Theme gallery", kind: .large, avail: .pending),
                RefItem("themeActionsStack", en: "Themes", kind: .smallStack([
                    RefItem("customizeTheme", en: "Customize theme", kind: .large, avail: .pending),
                    RefItem("downloadTheme", en: "Download theme", kind: .large, avail: .always),
                    RefItem("importTheme", en: "Import theme", kind: .large, avail: .always),
                ]), avail: .always),
            ]),
            RefGroup(en: "Customize page", items: [
                RefItem("pageSize", en: "Page size", kind: .large, hasMenu: true, avail: .pending),
                RefItem("pageBackground", en: "Page background", kind: .large, avail: .pending),
                RefItem("wallpaper", en: "Wallpaper", kind: .large, avail: .pending),
            ]),
            RefGroup(en: "Help", items: [
                RefItem("howToCreateTheme", en: "How to create a theme", kind: .large, avail: .unsupported),
            ]),
        ]
    )

    // MARK: - Report — View (4 nhóm; không có nút Data / Visualizations)

    static let reportView = RefTab(
        tabID: "view",
        contextual: false,
        groups: [
            RefGroup(en: "Scale to fit", items: [
                RefItem("pageView", en: "Page view", kind: .large, hasMenu: true, avail: .always),
            ]),
            RefGroup(en: "Mobile", items: [
                RefItem("mobileLayout", en: "Mobile layout", kind: .large, avail: .unsupported),
            ]),
            RefGroup(en: "Page options", items: [
                RefItem("gridlines", en: "Gridlines", kind: .checkbox, avail: .pending),
                RefItem("snapToGrid", en: "Snap to grid", kind: .checkbox, avail: .always),
                RefItem("lockObjects", en: "Lock objects", kind: .checkbox, avail: .pending),
            ]),
            RefGroup(en: "Show panes", items: [
                RefItem("showFilters", en: "Filters", kind: .toggle, avail: .always),
                RefItem("showBookmarks", en: "Bookmarks", kind: .toggle, avail: .always),
                RefItem("showSelection", en: "Selection", kind: .toggle, avail: .always),
                RefItem("performanceAnalyzer", en: "Performance analyzer", kind: .toggle, avail: .contextual),
                RefItem("syncSlicers", en: "Sync slicers", kind: .large, avail: .pending),
            ]),
        ]
    )

    // MARK: - Report — Optimize (4 nhóm)

    static let reportOptimize = RefTab(
        tabID: "optimize",
        contextual: false,
        groups: [
            RefGroup(en: "Queries", items: [
                RefItem("pauseVisuals", en: "Pause visuals", kind: .large, avail: .pending),
                RefItem("refreshVisuals", en: "Refresh visuals", kind: .large, avail: .always),
            ]),
            RefGroup(en: "Report", items: [
                RefItem("optimizationPresets", en: "Optimization presets", kind: .large, hasMenu: true, avail: .pending, observed: false),
            ]),
            RefGroup(en: "Review", items: [
                RefItem("performanceAnalyzer", en: "Performance analyzer", kind: .large, avail: .contextual),
            ]),
            RefGroup(en: "Apply", items: [
                RefItem("applyAllSlicers", en: "Apply all slicers button", kind: .large, avail: .pending),
            ]),
        ]
    )

    // MARK: - Report — Help (4 nhóm)

    static let reportHelp = RefTab(
        tabID: "help",
        contextual: false,
        groups: [
            RefGroup(en: "Info", items: [
                RefItem("about", en: "About", kind: .large, avail: .always),
            ]),
            RefGroup(en: "Help", items: [
                RefItem("guidedLearning", en: "Guided learning", kind: .large, avail: .always),
                RefItem("trainingVideos", en: "Training videos", kind: .large, avail: .unsupported),
                RefItem("documentation", en: "Documentation", kind: .large, avail: .unsupported),
                RefItem("support", en: "Support", kind: .large, avail: .unsupported),
            ]),
            RefGroup(en: "Community", items: [
                RefItem("powerBIBlog", en: "Power BI blog", kind: .large, avail: .unsupported),
                RefItem("community", en: "Community", kind: .large, avail: .unsupported),
                RefItem("powerBIForDevelopers", en: "Power BI for developers", kind: .large, avail: .unsupported),
                RefItem("submitAnIdea", en: "Submit an idea", kind: .large, avail: .unsupported),
                RefItem("externalTools", en: "External tools", kind: .large, avail: .unsupported),
            ]),
            RefGroup(en: "Resources", items: [
                RefItem("examples", en: "Examples", kind: .large, hasMenu: true, avail: .unsupported),
                RefItem("consultingServices", en: "Consulting services", kind: .large, avail: .unsupported),
            ]),
        ]
    )

    // MARK: - Contextual: Format & Data / Drill (US3)

    static let reportFormat = RefTab(
        tabID: "format",
        contextual: true,
        groups: [
            RefGroup(en: "Interactions", items: [
                RefItem("editInteractions", en: "Edit interactions", kind: .toggle, avail: .contextual),
                RefItem("applyDrillFiltersTo", en: "Apply drill down filters to", kind: .field, avail: .contextual),
            ]),
            RefGroup(en: "Arrange", items: [
                RefItem("bringForward", en: "Bring forward", kind: .large, hasMenu: true, avail: .contextual),
                RefItem("sendBackward", en: "Send backward", kind: .large, hasMenu: true, avail: .contextual),
                RefItem("selectionPane", en: "Selection", kind: .toggle, avail: .always),
                RefItem("align", en: "Align", kind: .large, hasMenu: true, avail: .contextual),
                RefItem("group", en: "Group", kind: .large, hasMenu: true, avail: .contextual),
            ]),
        ]
    )

    static let reportDataDrill = RefTab(
        tabID: "dataDrill",
        contextual: true,
        groups: [
            RefGroup(en: "Show", items: [
                RefItem("visualTable", en: "Visual table", kind: .large, avail: .contextual),
                RefItem("dataPointTable", en: "Data point table", kind: .large, avail: .contextual),
            ]),
            RefGroup(en: "Interactions", items: [
                RefItem("applyDrillFiltersTo", en: "Apply drill down filters to", kind: .field, avail: .contextual),
            ]),
            RefGroup(en: "Drill actions", items: [
                RefItem("drillActionsStackLeft", en: "Drill actions", kind: .smallStack([
                    RefItem("switchToNextLevel", en: "Switch to next level", kind: .large, avail: .pending),
                    RefItem("expandNextLevel", en: "Expand next level", kind: .large, avail: .contextual),
                ]), avail: .always),
                RefItem("drillActionsStackRight", en: "Drill actions", kind: .smallStack([
                    RefItem("drillUp", en: "Drill up", kind: .large, avail: .contextual),
                    RefItem("drillDown", en: "Drill down", kind: .toggle, avail: .contextual),
                ]), avail: .always),
                RefItem("drillThrough", en: "Drill through", kind: .large, avail: .pending),
            ]),
            RefGroup(en: "Data groups", items: [
                RefItem("groups", en: "Groups", kind: .large, hasMenu: true, avail: .pending, observed: false),
            ]),
            RefGroup(en: "AI", items: [
                RefItem("findAnomalies", en: "Find anomalies", kind: .large, avail: .unsupported),
            ]),
        ]
    )

    // MARK: - Table View: Home, Table tools, Column tools (US3)

    static let tableHome = RefTab(
        tabID: "home",
        contextual: false,
        groups: [
            RefGroup(en: "Clipboard", items: [
                RefItem("paste", en: "Paste", kind: .large, avail: .pending),
                RefItem("clipboardStack", en: "Clipboard", kind: .smallStack([
                    RefItem("cut", en: "Cut", kind: .large, avail: .pending),
                    RefItem("copy", en: "Copy", kind: .large, avail: .pending),
                ]), avail: .always),
            ]),
            RefGroup(en: "Data", items: [
                RefItem("getData", en: "Get data", kind: .large, hasMenu: true, avail: .contextual),
                RefItem("excelWorkbook", en: "Excel workbook", kind: .large, avail: .contextual),
                RefItem("oneLakeCatalog", en: "OneLake catalog", kind: .large, hasMenu: true, avail: .unsupported),
                RefItem("sqlServer", en: "SQL Server", kind: .large, avail: .contextual),
                RefItem("enterData", en: "Enter data", kind: .large, avail: .contextual),
                RefItem("dataverse", en: "Dataverse", kind: .large, avail: .unsupported),
                RefItem("recentSources", en: "Recent sources", kind: .large, hasMenu: true, avail: .pending),
            ]),
            RefGroup(en: "Queries", items: [
                RefItem("transformData", en: "Transform data", kind: .large, hasMenu: true, avail: .contextual),
                RefItem("refresh", en: "Refresh", kind: .large, hasMenu: true, avail: .contextual),
            ]),
            RefGroup(en: "Relationships", items: [
                RefItem("manageRelationships", en: "Manage relationships", kind: .large, avail: .contextual),
            ]),
            RefGroup(en: "Calculations", items: [
                RefItem("newMeasure", en: "New measure", kind: .large, avail: .contextual),
                RefItem("quickMeasure", en: "Quick measure", kind: .large, avail: .contextual),
                RefItem("newColumn", en: "New column", kind: .large, avail: .contextual),
                RefItem("newTable", en: "New table", kind: .large, avail: .contextual),
            ]),
            RefGroup(en: "Security", items: [
                RefItem("manageRoles", en: "Manage roles", kind: .large, avail: .contextual),
                RefItem("viewAs", en: "View as", kind: .toggle, avail: .contextual),
            ]),
            RefGroup(en: "Sensitivity", items: [
                RefItem("sensitivity", en: "Sensitivity", kind: .large, hasMenu: true, avail: .unsupported),
            ]),
            RefGroup(en: "Share", items: [
                RefItem("publish", en: "Publish", kind: .large, avail: .unsupported),
            ]),
        ]
    )

    static let tableTools = RefTab(
        tabID: "tableTools",
        contextual: true,
        groups: [
            RefGroup(en: "Structure", items: [
                RefItem("tableName", en: "Name", kind: .field, avail: .contextual),
            ]),
            RefGroup(en: "Relationships", items: [
                RefItem("manageRelationships", en: "Manage relationships", kind: .large, avail: .contextual),
            ]),
            RefGroup(en: "Calculations", items: [
                RefItem("newMeasure", en: "New measure", kind: .large, avail: .contextual),
                RefItem("quickMeasure", en: "Quick measure", kind: .large, avail: .contextual),
                RefItem("newColumn", en: "New column", kind: .large, avail: .contextual),
                RefItem("newTable", en: "New table", kind: .large, avail: .contextual),
            ]),
            RefGroup(en: "Calendars", items: [
                RefItem("markAsDateTable", en: "Mark as date table", kind: .large, avail: .contextual),
            ]),
        ]
    )

    static let columnTools = RefTab(
        tabID: "columnTools",
        contextual: true,
        groups: [
            RefGroup(en: "Structure", items: [
                RefItem("columnName", en: "Name", kind: .field, avail: .contextual),
                RefItem("dataType", en: "Data type", kind: .field, avail: .contextual),
            ]),
            RefGroup(en: "Formatting", items: [
                RefItem("format", en: "Format", kind: .field, avail: .contextual),
                RefItem("formattingQuickRow", en: "Formatting", kind: .smallStack([
                    RefItem("currencyFormat", en: "$", kind: .large, hasMenu: true, avail: .contextual),
                    RefItem("percentFormat", en: "%", kind: .large, avail: .contextual),
                    RefItem("thousandsFormat", en: ",", kind: .large, avail: .contextual),
                    RefItem("decimalFormat", en: ".00", kind: .large, avail: .contextual),
                    RefItem("decimalPlaces", en: "Auto", kind: .field, avail: .pending),
                ]), avail: .always),
            ]),
            RefGroup(en: "Properties", items: [
                RefItem("summarization", en: "Summarization", kind: .field, avail: .contextual),
                RefItem("dataCategory", en: "Data category", kind: .field, avail: .contextual),
            ]),
            RefGroup(en: "Sort", items: [
                RefItem("sortByColumn", en: "Sort by column", kind: .large, hasMenu: true, avail: .contextual),
            ]),
            RefGroup(en: "Groups", items: [
                RefItem("dataGroups", en: "Data groups", kind: .large, hasMenu: true, avail: .pending),
            ]),
            RefGroup(en: "Relationships", items: [
                RefItem("manageRelationships", en: "Manage relationships", kind: .large, avail: .contextual),
            ]),
            RefGroup(en: "Calculations", items: [
                RefItem("newColumn", en: "New column", kind: .large, avail: .contextual),
            ]),
        ]
    )

    // MARK: - Model / DAX / TMDL Home (US3)

    static let modelHome = RefTab(
        tabID: "home",
        contextual: false,
        groups: [
            RefGroup(en: "Clipboard", items: [
                RefItem("paste", en: "Paste", kind: .large, avail: .pending),
                RefItem("clipboardStack", en: "Clipboard", kind: .smallStack([
                    RefItem("cut", en: "Cut", kind: .large, avail: .pending),
                    RefItem("copy", en: "Copy", kind: .large, avail: .pending),
                ]), avail: .always),
            ]),
            RefGroup(en: "Data", items: [
                RefItem("getData", en: "Get data", kind: .large, hasMenu: true, avail: .contextual),
                RefItem("excelWorkbook", en: "Excel workbook", kind: .large, avail: .contextual),
                RefItem("oneLakeCatalog", en: "OneLake catalog", kind: .large, hasMenu: true, avail: .unsupported),
                RefItem("sqlServer", en: "SQL Server", kind: .large, avail: .contextual),
                RefItem("enterData", en: "Enter data", kind: .large, avail: .contextual),
                RefItem("dataverse", en: "Dataverse", kind: .large, avail: .unsupported),
                RefItem("recentSources", en: "Recent sources", kind: .large, hasMenu: true, avail: .pending),
            ]),
            RefGroup(en: "Queries", items: [
                RefItem("transformData", en: "Transform data", kind: .large, hasMenu: true, avail: .contextual),
                RefItem("refresh", en: "Refresh", kind: .large, hasMenu: true, avail: .contextual),
            ]),
            RefGroup(en: "Relationships", items: [
                RefItem("manageRelationships", en: "Manage relationships", kind: .large, avail: .contextual),
            ]),
            RefGroup(en: "Calculations", items: [
                RefItem("newMeasure", en: "New measure", kind: .large, avail: .contextual),
                RefItem("newColumn", en: "New column", kind: .large, avail: .contextual),
                RefItem("newTable", en: "New table", kind: .large, avail: .contextual),
                RefItem("calculationGroup", en: "Calculation group", kind: .large, avail: .pending),
            ]),
            RefGroup(en: "Parameters", items: [
                RefItem("newParameter", en: "New parameter", kind: .large, hasMenu: true, avail: .pending),
            ]),
            RefGroup(en: "Security", items: [
                RefItem("manageRoles", en: "Manage roles", kind: .large, avail: .contextual),
                RefItem("viewAs", en: "View as", kind: .toggle, avail: .contextual),
            ]),
            RefGroup(en: "Q&A", items: [
                RefItem("qnaSetup", en: "Q&A setup", kind: .large, avail: .unsupported),
                RefItem("language", en: "Language", kind: .large, hasMenu: true, avail: .unsupported),
                RefItem("linguisticSchema", en: "Linguistic schema", kind: .large, hasMenu: true, avail: .unsupported),
            ]),
            RefGroup(en: "Sensitivity", items: [
                RefItem("sensitivity", en: "Sensitivity", kind: .large, hasMenu: true, avail: .unsupported),
            ]),
            RefGroup(en: "Share", items: [
                RefItem("publish", en: "Publish", kind: .large, avail: .unsupported),
            ]),
        ]
    )

    static let daxHome = RefTab(
        tabID: "home",
        contextual: false,
        groups: [
            RefGroup(en: "Clipboard", items: [
                RefItem("paste", en: "Paste", kind: .large, avail: .pending),
                RefItem("clipboardStack", en: "Clipboard", kind: .smallStack([
                    RefItem("cut", en: "Cut", kind: .large, avail: .pending),
                    RefItem("copy", en: "Copy", kind: .large, avail: .pending),
                ]), avail: .always),
            ]),
            RefGroup(en: "Editing", items: [
                RefItem("daxFormat", en: "Format", kind: .large, avail: .contextual),
                RefItem("comment", en: "Comment", kind: .large, avail: .contextual),
                RefItem("uncomment", en: "Uncomment", kind: .large, avail: .contextual),
                RefItem("find", en: "Find", kind: .large, avail: .pending),
                RefItem("replace", en: "Replace", kind: .large, avail: .pending),
                RefItem("commandPalette", en: "Command palette", kind: .large, avail: .pending),
            ]),
            RefGroup(en: "Copilot", items: [
                RefItem("copilot", en: "Copilot", kind: .large, avail: .unsupported),
            ]),
        ]
    )

    static let tmdlHome = RefTab(
        tabID: "home",
        contextual: false,
        groups: [
            RefGroup(en: "Clipboard", items: [
                RefItem("paste", en: "Paste", kind: .large, avail: .pending),
                RefItem("clipboardStack", en: "Clipboard", kind: .smallStack([
                    RefItem("cut", en: "Cut", kind: .large, avail: .pending),
                    RefItem("copy", en: "Copy", kind: .large, avail: .contextual),
                ]), avail: .always),
            ]),
            RefGroup(en: "Editing", items: [
                RefItem("tmdlFormat", en: "Format", kind: .large, avail: .pending),
                RefItem("find", en: "Find", kind: .large, avail: .pending),
                RefItem("replace", en: "Replace", kind: .large, avail: .pending),
                RefItem("commandPalette", en: "Command palette", kind: .large, avail: .pending),
            ]),
        ]
    )
}
