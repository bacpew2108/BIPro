import DAXEngine
import Foundation
import PBIXKit
import Testing
@testable import BIPro

@Suite struct TooltipTests {

    // MARK: - 10. VisualTooltip.rows: đúng thứ tự Category -> Y -> Tooltips cho donutPurpose và treemapProducts
    @Test func tooltipRowsOrderingAndFormatting() {
        // 1. Mẫu donutPurpose
        guard case .categorical(let donutData) = DataViewSamples.donutPurpose else {
            Issue.record("donutPurpose không phải categorical")
            return
        }

        let donutPt = DataPointID(["Dim_Loan_Profile.purpose": .string("Mua nhà")])
        let donutRows = VisualTooltip.rows(for: donutPt, in: donutData)

        // Thứ tự: Category ("purpose") -> Y ("Giá trị") -> Tooltips ("Kỳ hạn BQ")
        #expect(donutRows.count == 3)
        #expect(donutRows[0].name == "purpose")
        #expect(donutRows[0].value == "Mua nhà")

        #expect(donutRows[1].name == "Giá trị")
        #expect(donutRows[1].value == "$41,000,000") // formatString "\\$#,0"

        #expect(donutRows[2].name == "Kỳ hạn BQ")
        #expect(donutRows[2].value == "36.2") // formatString "0.0"

        // 2. Mẫu treemapProducts (2 cấp Group)
        guard case .categorical(let treemapData) = DataViewSamples.treemapProducts else {
            Issue.record("treemapProducts không phải categorical")
            return
        }

        let treemapPt = DataPointID([
            "Dim_CRM_Issue.product": .string("Bank account or service"),
            "Dim_CRM_Issue.sub_product": .string("Checking account")
        ])
        let treemapRows = VisualTooltip.rows(for: treemapPt, in: treemapData)

        // Thứ tự: Category cấp 0 ("Sản phẩm") -> Category cấp 1 ("Sản phẩm con") -> Values ("Số khiếu nại") -> Tooltips ("% đúng hạn")
        #expect(treemapRows.count == 4)
        #expect(treemapRows[0].name == "Sản phẩm")
        #expect(treemapRows[0].value == "Bank account or service")

        #expect(treemapRows[1].name == "Sản phẩm con")
        #expect(treemapRows[1].value == "Checking account")

        #expect(treemapRows[2].name == "Số khiếu nại")
        #expect(treemapRows[2].value == "9,120") // formatString "#,0"

        #expect(treemapRows[3].name == "% đúng hạn")
        #expect(treemapRows[3].value == "99%") // formatString "0%" (0.99 -> 99%)

        // 3. Mẫu barNPLByAge (như ảnh tooltip-bar.png)
        guard case .categorical(let barData) = DataViewSamples.barNPLByAge else {
            Issue.record("barNPLByAge không phải categorical")
            return
        }

        let barPt = DataPointID(["Fact_Loan.age_group_at_loan": .string("35-49")])
        let barRows = VisualTooltip.rows(for: barPt, in: barData)

        #expect(barRows.count == 5)
        #expect(barRows[0].name == "Nhóm tuổi lúc vay" && barRows[0].value == "35-49")
        #expect(barRows[1].name == "NPL% (số HĐ)" && barRows[1].value == "11%")
        #expect(barRows[2].name == "NPL% (giá trị)" && barRows[2].value == "14%")
        #expect(barRows[3].name == "Số HĐ nợ xấu" && barRows[3].value == "26")
        #expect(barRows[4].name == "Số HĐ" && barRows[4].value == "227")
    }
}
