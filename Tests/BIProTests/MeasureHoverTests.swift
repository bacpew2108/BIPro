import Foundation
import Testing
@testable import PBIXKit
@testable import BIPro

@Suite struct MeasureHoverTests {
    private static func makeMeasure(table: String, name: String, expression: String = "") -> ModelMetadata.Measure {
        ModelMetadata.Measure(
            tableName: table,
            name: name,
            expression: expression,
            formatString: nil,
            displayFolder: nil,
            isHidden: false,
            description: nil,
            lineageTag: nil,
            dataType: .int64,
            state: 1,
            formatStringDefinition: nil
        )
    }

    private let sampleMeasures = [
        makeMeasure(
            table: "Fact_CRM_Complaint",
            name: "Complaints",
            expression: "SUM ( Fact_CRM_Complaint[complaint_count] )"
        ),
        makeMeasure(
            table: "Fact_Sales",
            name: "Total Sales",
            expression: "SUM ( Fact_Sales[amount] )"
        ),
    ]

    @Test func tokenComplaintsTrungTen() {
        let text = "EVALUATE [Complaints]"
        let openBracketOffset = (text as NSString).range(of: "[").location
        let insideOffset = openBracketOffset + 2
        let closeBracketOffset = (text as NSString).range(of: "]").location

        // Rê chuột tại [, bên trong tên, và tại ]
        let m1 = MeasureHover.lookup(text: text, utf16Offset: openBracketOffset, measures: sampleMeasures)
        #expect(m1?.name == "Complaints")
        #expect(m1?.expression == "SUM ( Fact_CRM_Complaint[complaint_count] )")

        let m2 = MeasureHover.lookup(text: text, utf16Offset: insideOffset, measures: sampleMeasures)
        #expect(m2?.name == "Complaints")

        let m3 = MeasureHover.lookup(text: text, utf16Offset: closeBracketOffset, measures: sampleMeasures)
        #expect(m3?.name == "Complaints")

        // Không phân biệt hoa thường
        let lowerText = "EVALUATE [complaints]"
        let mLower = MeasureHover.lookup(text: lowerText, utf16Offset: 12, measures: sampleMeasures)
        #expect(mLower?.name == "Complaints")
    }

    @Test func dungBangVaSaiBang() {
        // Trường hợp đúng bảng có nháy đơn
        let textQuoted = "EVALUATE 'Fact_CRM_Complaint'[Complaints]"
        let offsetQuoted = (textQuoted as NSString).range(of: "Complaints").location
        let matchQuoted = MeasureHover.lookup(text: textQuoted, utf16Offset: offsetQuoted, measures: sampleMeasures)
        #expect(matchQuoted?.name == "Complaints")
        #expect(matchQuoted?.tableName == "Fact_CRM_Complaint")

        // Trường hợp đúng bảng không có nháy đơn
        let textUnquoted = "EVALUATE Fact_CRM_Complaint[Complaints]"
        let offsetUnquoted = (textUnquoted as NSString).range(of: "Complaints").location
        let matchUnquoted = MeasureHover.lookup(text: textUnquoted, utf16Offset: offsetUnquoted, measures: sampleMeasures)
        #expect(matchUnquoted?.name == "Complaints")

        // Đúng bảng không phân biệt hoa thường
        let textCase = "EVALUATE 'fact_crm_complaint'[complaints]"
        let offsetCase = (textCase as NSString).range(of: "complaints").location
        let matchCase = MeasureHover.lookup(text: textCase, utf16Offset: offsetCase, measures: sampleMeasures)
        #expect(matchCase?.name == "Complaints")

        // Trường hợp sai bảng
        let textWrong = "EVALUATE 'OtherTable'[Complaints]"
        let offsetWrong = (textWrong as NSString).range(of: "Complaints").location
        let matchWrong = MeasureHover.lookup(text: textWrong, utf16Offset: offsetWrong, measures: sampleMeasures)
        #expect(matchWrong == nil)

        let textWrong2 = "EVALUATE Fact_Sales[Complaints]"
        let offsetWrong2 = (textWrong2 as NSString).range(of: "Complaints").location
        let matchWrong2 = MeasureHover.lookup(text: textWrong2, utf16Offset: offsetWrong2, measures: sampleMeasures)
        #expect(matchWrong2 == nil)
    }

    @Test func tokenLaCotTraVeNil() {
        // complaint_count là cột, không nằm trong measures
        let text = "EVALUATE 'Fact_CRM_Complaint'[complaint_count]"
        let offset = (text as NSString).range(of: "complaint_count").location
        let result = MeasureHover.lookup(text: text, utf16Offset: offset, measures: sampleMeasures)
        #expect(result == nil)

        let text2 = "EVALUATE [UnknownColumn]"
        let offset2 = (text2 as NSString).range(of: "UnknownColumn").location
        let result2 = MeasureHover.lookup(text: text2, utf16Offset: offset2, measures: sampleMeasures)
        #expect(result2 == nil)
    }

    @Test func tokenNamTrongChuoiHoacCommentTraVeNil() {
        // Trong chuỗi ""
        let inString = "VAR msg = \"Day la [Complaints] trong chuoi\""
        let offsetString = (inString as NSString).range(of: "Complaints").location
        #expect(MeasureHover.lookup(text: inString, utf16Offset: offsetString, measures: sampleMeasures) == nil)

        // Trong chuỗi có escape quote ""
        let inEscapedString = "VAR msg = \"Day la \"\"escaped\"\" [Complaints] trong chuoi\""
        let offsetEscaped = (inEscapedString as NSString).range(of: "Complaints").location
        #expect(MeasureHover.lookup(text: inEscapedString, utf16Offset: offsetEscaped, measures: sampleMeasures) == nil)

        // Trong comment //
        let inComment = "// EVALUATE [Complaints]"
        let offsetComment = (inComment as NSString).range(of: "Complaints").location
        #expect(MeasureHover.lookup(text: inComment, utf16Offset: offsetComment, measures: sampleMeasures) == nil)

        // Token hợp lệ nằm sau comment ở dòng khác
        let multiline = "// Comment o dong 1 [Complaints]\nEVALUATE [Complaints]"
        let secondLineOffset = (multiline as NSString).range(of: "EVALUATE").location + 10
        let matchMulti = MeasureHover.lookup(text: multiline, utf16Offset: secondLineOffset, measures: sampleMeasures)
        #expect(matchMulti?.name == "Complaints")
    }

    @Test func conTroNamNgoaiMoiTokenTraVeNil() {
        let text = "EVALUATE [Complaints]"

        // Ở từ khoá EVALUATE
        #expect(MeasureHover.lookup(text: text, utf16Offset: 0, measures: sampleMeasures) == nil)
        #expect(MeasureHover.lookup(text: text, utf16Offset: 4, measures: sampleMeasures) == nil)

        // Ở khoảng trắng trước [
        let spaceOffset = (text as NSString).range(of: " ").location
        #expect(MeasureHover.lookup(text: text, utf16Offset: spaceOffset, measures: sampleMeasures) == nil)

        // Ở ngoài sau ]
        let closeBracket = (text as NSString).range(of: "]").location
        #expect(MeasureHover.lookup(text: text, utf16Offset: closeBracket + 1, measures: sampleMeasures) == nil)

        // Offset âm hoặc vượt quá chiều dài
        #expect(MeasureHover.lookup(text: text, utf16Offset: -1, measures: sampleMeasures) == nil)
        #expect(MeasureHover.lookup(text: text, utf16Offset: 100, measures: sampleMeasures) == nil)

        // Chuỗi rỗng
        #expect(MeasureHover.lookup(text: "", utf16Offset: 0, measures: sampleMeasures) == nil)
    }
}
