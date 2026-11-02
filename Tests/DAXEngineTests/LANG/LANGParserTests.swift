// Test parser của DAX (LANG, đợt 1a): ưu tiên toán tử, đối số trống, VAR lồng, bảng hằng, truy vấn, lỗi.
import Testing
import ColumnStore
@testable import DAXEngine

/// Dạng rút gọn của AST để so sánh, bỏ qua SourceRange.
private func langShape(_ e: Expr) -> String {
    switch e {
    case .number(let v, let isInteger, _):
        return isInteger ? String(Int64(v)) : String(v)
    case .string(let s, _):
        return "\"\(s)\""
    case .boolean(let b, _):
        return b ? "TRUE" : "FALSE"
    case .columnRef(let table, let column, _):
        return "\(table ?? "")[\(column)]"
    case .bracketRef(let name, _):
        return "[\(name)]"
    case .tableRef(let name, _):
        return "'\(name)'"
    case .identifier(let name, _):
        return name
    case .call(let name, let args, _):
        let inside = args.map { $0.map(langShape) ?? "_" }.joined(separator: " ; ")
        return "\(name)(\(inside))"
    case .unary(let op, let operand, _):
        return "(\(op.rawValue) \(langShape(operand)))"
    case .binary(let op, let left, let right, _):
        return "(\(op.rawValue) \(langShape(left)) \(langShape(right)))"
    case .varBlock(let vars, let body, _):
        let bindings = vars.map { "\($0.name)=\(langShape($0.value))" }.joined(separator: ", ")
        return "(VAR \(bindings) RETURN \(langShape(body)))"
    case .tableConstructor(let rows, _):
        let inside = rows.map { "[" + $0.map(langShape).joined(separator: ",") + "]" }.joined(separator: ",")
        return "{\(inside)}"
    }
}

@Suite struct LANGParserTests {
    private func shape(_ text: String) throws -> String {
        langShape(try parseExpression(text))
    }

    @Test func thuTuUuTienCoBan() throws {
        #expect(try shape("1 + 2 * 3") == "(+ 1 (* 2 3))")
        #expect(try shape("1 - 2 - 3") == "(- (- 1 2) 3)")
        #expect(try shape("a & b = c") == "(= (& a b) c)")
        #expect(try shape("a = b && c <> d") == "(&& (= a b) (<> c d))")
        #expect(try shape("a || b && c") == "(|| a (&& b c))")
    }

    @Test func luyThuaVaDauMotNgoi() throws {
        // Dấu một ngôi có ưu tiên thấp hơn ^: -2^2 là -(2^2).
        #expect(try shape("-2^2") == "(- (^ 2 2))")
        // Lũy thừa kết hợp trái và vế phải của ^ cho phép dấu một ngôi.
        #expect(try shape("2 ^ 3 ^ 2") == "(^ (^ 2 3) 2)")
        #expect(try shape("2 ^ -1") == "(^ 2 (- 1))")
    }

    @Test func notCoMucUuTienThapHonSoSanh() throws {
        #expect(try shape("NOT a = b") == "(NOT (= a b))")
        // NOT(...) có ngoặc là lời gọi hàm, nên chỉ vế trái bị gói.
        #expect(try shape("NOT(a) = b") == "(= NOT(a) b)")
        #expect(try shape("!a") == "(NOT a)")
    }

    @Test func inVoiBangHang() throws {
        #expect(try shape("x IN {1, 2}") == "(IN x {[1],[2]})")
    }

    @Test func cotVaMeasureVaCotAo() throws {
        #expect(try shape("Dim_Account[card_type] <> \"No Card\"") == "(<> Dim_Account[card_type] \"No Card\")")
        #expect(try shape("'Dim_Date'[year]") == "Dim_Date[year]")
        #expect(try shape("[@c] > cur") == "(> [@c] cur)")
        #expect(try shape("[Total Accounts]") == "[Total Accounts]")
    }

    @Test func soThapPhanVaSoMu() throws {
        let e = try parseExpression("1e6")
        guard case .number(let v, let isInteger, _) = e else {
            Issue.record("1e6 phải là số")
            return
        }
        #expect(v == 1_000_000)
        #expect(isInteger == false)
    }

    @Test func doiSoTrongRankXCoDoiSoTrong() throws {
        // RANKX(…, , DESC, DENSE): đối số thứ ba bỏ trống, cho nil.
        #expect(try shape("RANKX(ALL(Dim[s]), [Loan Amount], , DESC, DENSE)")
                == "RANKX(ALL(Dim[s]) ; [Loan Amount] ; _ ; DESC ; DENSE)")
        #expect(try shape("f()") == "f()")
        #expect(try shape("f(a,)") == "f(a ; _)")
    }

    @Test func varLongNhauTrongDoiSo() throws {
        #expect(try shape("IF(x, VAR a = 1 RETURN a + 1, 0)")
                == "IF(x ; (VAR a=1 RETURN (+ a 1)) ; 0)")
        #expect(try shape("VAR a = 1 VAR b = a RETURN b")
                == "(VAR a=1, b=a RETURN b)")
    }

    @Test func bangHangCoTuple() throws {
        #expect(try shape("{(1, \"a\"), (2, \"b\")}") == "{[1,\"a\"],[2,\"b\"]}")
        // Mục bắt đầu bằng '(' nhưng không phải bộ giá trị vẫn đọc được như biểu thức.
        #expect(try shape("{(1) + 2}") == "{[(+ 1 2)]}")
        #expect(try shape("{1, 2}") == "{[1],[2]}")
    }

    @Test func tuKhoaTrueFalse() throws {
        #expect(try shape("TRUE") == "TRUE")
        #expect(try shape("FALSE") == "FALSE")
        #expect(try shape("TRUE()") == "TRUE()")
    }

    @Test func truyVanDayDu() throws {
        let text = """
        DEFINE
            MEASURE 'T'[m] = 1 + 1
            VAR v = 2
            TABLE t = {1}
            COLUMN 'T'[c] = 3
        EVALUATE ROW("x", [m])
        ORDER BY 'T'[c] DESC, [m]
        START AT 1, 2
        """
        let query = try parseQuery(text)
        #expect(query.defines.count == 4)
        guard case .measure(let table, let name, let body) = query.defines[0] else {
            Issue.record("định nghĩa đầu phải là MEASURE")
            return
        }
        #expect(table == "T")
        #expect(name == "m")
        #expect(langShape(body) == "(+ 1 1)")
        if case .variable(let vname, _) = query.defines[1] {
            #expect(vname == "v")
        } else {
            Issue.record("định nghĩa thứ hai phải là VAR")
        }
        if case .table(let tname, _) = query.defines[2] {
            #expect(tname == "t")
        } else {
            Issue.record("định nghĩa thứ ba phải là TABLE")
        }
        if case .column(let ctable, let cname, _) = query.defines[3] {
            #expect(ctable == "T")
            #expect(cname == "c")
        } else {
            Issue.record("định nghĩa thứ tư phải là COLUMN")
        }
        #expect(query.statements.count == 1)
        let statement = query.statements[0]
        #expect(statement.orderBy.count == 2)
        #expect(statement.orderBy[0].ascending == false)
        #expect(statement.orderBy[1].ascending == true)
        #expect(statement.startAt.count == 2)
    }

    @Test func measureKhongCoBang() throws {
        let query = try parseQuery("DEFINE MEASURE [m] = 1 EVALUATE {1}")
        guard case .measure(let table, _, _) = query.defines[0] else {
            Issue.record("phải là MEASURE")
            return
        }
        #expect(table == "")
    }

    @Test func nhieuEvaluate() throws {
        let query = try parseQuery("EVALUATE 'A' EVALUATE 'B'")
        #expect(query.statements.count == 2)
    }

    // MARK: - Lỗi cú pháp và vị trí

    @Test func thieuNgoacDongBaoDongCuoiToken() {
        // Lỗi ở cuối văn bản trỏ về cuối token thật gần nhất: dòng 2, cột 17 (sau số 2).
        do {
            _ = try parseQuery("EVALUATE\nROW ( \"a\", 1 + 2")
            Issue.record("phải báo thiếu ')'")
        } catch {
            #expect(error.kind == .syntax)
            #expect(error.range?.line == 2)
            #expect(error.range?.column == 17)
            #expect(error.message.contains("thiếu"))
        }
    }

    @Test func toanHangThieuBaoLoiCuoiVanBan() {
        do {
            _ = try parseExpression("1 +")
            Issue.record("phải báo lỗi")
        } catch {
            #expect(error.kind == .syntax)
            #expect(error.range?.line == 1)
            #expect(error.range?.column == 4)
        }
    }

    @Test func toanHangThieuKhiCoTab() {
        // Tab đầu dòng là một cột. ')' thừa nằm ở cột 17 của dòng 2 (kiểu O3d).
        do {
            _ = try parseQuery("EVALUATE\n\tROW ( \"x\", 1 + )")
            Issue.record("phải báo lỗi")
        } catch {
            #expect(error.kind == .syntax)
            #expect(error.range?.line == 2)
            #expect(error.range?.column == 17)
        }
    }

    @Test func varThieuReturnBaoLoi() {
        do {
            _ = try parseExpression("VAR a = 1 a")
            Issue.record("phải báo thiếu RETURN")
        } catch {
            #expect(error.kind == .syntax)
            #expect(error.range?.column == 11)
        }
    }

    @Test func bieuThucTrongBaoLoi() {
        do {
            _ = try parseExpression("   ")
            Issue.record("biểu thức trống phải báo lỗi")
        } catch {
            #expect(error.kind == .syntax)
        }
    }

    @Test func thieuEvaluateBaoLoi() {
        do {
            _ = try parseQuery("DEFINE VAR x = 1")
            Issue.record("truy vấn không có EVALUATE phải báo lỗi")
        } catch {
            #expect(error.kind == .syntax)
        }
    }
}
