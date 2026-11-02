// FCExpected.swift: đáp án của test FC trên MiniBank.
// SINH TỰ ĐỘNG bởi fc_oracle.py (Python 3 stdlib, đọc MiniBankData.swift). Không sửa tay.
// Mọi con số đều tính bằng Python từ dữ liệu thô, không dùng Swift để tính đáp án.

enum FCExpected {
    static let allSelectedAllYear2024Trans = 20
    static let allSelectedCardTrans = 31
    static let allSelectedNoShadowTrans = 40
    static let blankCityTrans = 1
    static let blankCityTransSum = -2031000
    static let complaintActiveReceivedMatch = 1
    static let complaintSentWithUserRelationship = 0
    static let crossJoinCitiesDistrictCount = 9
    static let dimAccountVisibleBlankCity = 1
    static let dimAccountVisibleNoFilter = 6
    static let expandedAfterRemoveAccountTrans = 20
    static let expandedAfterRemoveFactTrans = 40
    static let expandedBeforeRemoveTrans = 7
    static let filteredDanangYear2024Trans = 7
    static let keepIntersectHanoiTrans = 16
    static let noCardTrans = 8
    static let overwriteHcmTrans = 8
    static let overwriteYear2024Trans = 20
    static let projectRemoveYearDanangTrans = 15
    static let rowsFilterAccount14Trans = 16
    static let rowsFilterFact2024DimDate = 731
    static let rowsFilterFact2024Trans = 20
    static let rowsFilterProjectedDimAccountRows = 2
    static let rowsFilterProjectedFactTrans = 16
    static let summarizeAccountKeysCount = 6
    static let valuesBranchCityNoFilterCount = 4
    static let valuesCardHanoiCount = 1
}
