// validate() cho gạch chân lỗi trong editor: cú pháp, rồi lỗi tên/bind, không đánh giá gì.
import Testing
import ColumnStore
import DAXTestSupport
@testable import DAXEngine

@Suite struct QRYValidateTests {
    private let engine = ftEngine(MiniBank.makeSource())

    @Test func truyVanDungKhongCoLoi() {
        #expect(engine.validate("EVALUATE ROW ( \"n\", COUNTROWS ( Dim_Date ) )").isEmpty)
        #expect(engine.validate("""
        DEFINE MEASURE Fact_Trans[x2] = [Trans Amount] * 2
        VAR v = 3
        EVALUATE SUMMARIZECOLUMNS ( Dim_Date[year], "x2", [x2], "v", v )
        ORDER BY Dim_Date[year]
        """).isEmpty)
    }

    @Test func loiCuPhap() {
        let errors = engine.validate("EVALUATE ROW ( \"n\", 1 + )")
        #expect(errors.count == 1)
        #expect(errors.first?.range != nil)
    }

    @Test func cotKhongTonTaiCoViTri() throws {
        let errors = engine.validate("EVALUATE\nROW ( \"n\", COUNTROWS ( VALUES ( Dim_Date[yearx] ) ) )")
        let error = try #require(errors.first)
        #expect(error.kind == .unknownName)
        let range = try #require(error.range)
        #expect(range.line == 2)
    }

    @Test func loiTrongThanDefineMeasure() throws {
        let errors = engine.validate("""
        DEFINE MEASURE Fact_Trans[bad] = SUM ( Fact_Trans[khong_co] )
        EVALUATE ROW ( "b", [bad] )
        """)
        #expect(errors.first?.kind == .unknownName)
    }

    @Test func hamKhongTonTaiVaMeasureSaiBang() {
        #expect(engine.validate("EVALUATE ROW ( \"n\", KHONGCO ( 1 ) )").first?.kind == .unknownName)
        #expect(engine.validate("EVALUATE ROW ( \"x\", 'Dim_Date'[Trans Amount] )").first?.kind == .unknownName)
    }

    @Test func loiChiLoKhiChayThiKhongBao() {
        // So chuỗi với số là lỗi lúc chạy (O17); validate không đánh giá nên không báo.
        #expect(engine.validate("EVALUATE ROW ( \"x\", IF ( \"12\" > 12, 1, 0 ) )").isEmpty)
    }
}
