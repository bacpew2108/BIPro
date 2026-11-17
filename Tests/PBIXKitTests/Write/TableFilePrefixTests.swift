import Testing
@testable import PBIXKit

/// T104 (lỗi T096): kiểm sau ghi nhận tệp của bảng bằng tiền tố gồm cả mã bảng; tiền tố chỉ theo tên ("Sales (") trúng cả bảng "Sales (2)".
@Suite struct TableFilePrefixTests {
    private func matches(_ path: String, _ prefixes: [String]) -> Bool {
        let flat = PBIXWriter.flatFileName(path)
        return prefixes.contains { flat.hasPrefix($0) }
    }

    @Test func prefixIncludesTableID() {
        let prefixes = PBIXWriter.tableFilePrefixes([("Sales", 12)])
        #expect(matches(#"Sales (12).tbl\61.prt\0.Sales (12).OrderID (40).0.idf"#, prefixes))
        #expect(matches(#"H$Sales (12)$OrderID (40)$(98).tbl\101.prt\0.H$Sales (12)$OrderID (40).POS_TO_ID.0.idf"#, prefixes))
        #expect(!matches(#"Sales (2) (13).tbl\61.prt\0.Sales (2) (13).OrderID (41).0.idf"#, prefixes))
        #expect(!matches(#"H$Sales (2) (13)$OrderID (41)$(99).tbl\0.x.idf"#, prefixes))
        #expect(!matches(#"Sales (120).tbl\0.x.idf"#, prefixes))
    }
}
