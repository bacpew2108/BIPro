import Foundation

/// Mã định danh ổn định cho mọi lệnh xuất hiện trong `contracts/ribbon-catalog.md`.
/// Lệnh xuất hiện ở nhiều tab dùng chung một ID.
enum RibbonCommandID: String, CaseIterable, Hashable, Sendable {
    // MARK: - Stack containers (không phải nút trực tiếp)
    case clipboardStack
    case themeActionsStack
    case drillActionsStackLeft
    case drillActionsStackRight
    case formattingQuickRow

    // MARK: - Clipboard
    case paste
    case cut
    case copy
    case formatPainter

    // MARK: - Data & Queries
    case getData
    case excelWorkbook
    case oneLakeCatalog
    case sqlServer
    case enterData
    case dataverse
    case recentSources
    case transformData
    case refresh

    // MARK: - Insert
    case newPage
    case newVisual
    case textBox
    case moreVisuals
    case keyInfluencers
    case decompositionTree
    case narrative
    case paginatedReport
    case powerApps
    case powerAutomate
    case buttons
    case shapes
    case image
    case addSparkline

    // MARK: - Calculations, Relationships, Calendars, Parameters, Security, Q&A
    case manageRelationships
    case newVisualCalculation
    case newMeasure
    case quickMeasure
    case newColumn
    case newTable
    case calculationGroup
    case markAsDateTable
    case changeDetection
    case newParameter
    case manageRoles
    case viewAs
    case qnaSetup
    case language
    case linguisticSchema

    // MARK: - Sensitivity, Share, Copilot
    case sensitivity
    case publish
    case prepDataForAI
    case copilot

    // MARK: - Design
    case themeGallery6
    case themeGallery
    case customizeTheme
    case downloadTheme
    case importTheme
    case pageSize
    case pageBackground
    case wallpaper
    case howToCreateTheme

    // MARK: - View
    case pageView
    case mobileLayout
    case gridlines
    case snapToGrid
    case lockObjects
    case showFilters
    case showBookmarks
    case showSelection
    case performanceAnalyzer
    case syncSlicers

    // MARK: - Optimize
    case pauseVisuals
    case refreshVisuals
    case optimizationPresets
    case applyAllSlicers

    // MARK: - Help
    case about
    case guidedLearning
    case trainingVideos
    case documentation
    case support
    case powerBIBlog
    case community
    case powerBIForDevelopers
    case submitAnIdea
    case externalTools
    case examples
    case consultingServices

    // MARK: - Contextual: Format & Data / Drill
    case editInteractions
    case applyDrillFiltersTo
    case bringForward
    case sendBackward
    case selectionPane
    case align
    case group
    case visualTable
    case dataPointTable
    case switchToNextLevel
    case expandNextLevel
    case drillUp
    case drillDown
    case drillThrough
    case groups
    case findAnomalies

    // MARK: - Table tools & Column tools
    case tableName
    case columnName
    case dataType
    case format
    case currencyFormat
    case percentFormat
    case thousandsFormat
    case decimalFormat
    case decimalPlaces
    case summarization
    case dataCategory
    case sortByColumn
    case dataGroups

    // MARK: - DAX & TMDL Editing
    case daxFormat
    case tmdlFormat
    case comment
    case uncomment
    case find
    case replace
    case commandPalette
}
