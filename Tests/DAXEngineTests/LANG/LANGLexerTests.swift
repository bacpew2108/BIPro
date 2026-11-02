// Test lexer của DAX (LANG, đợt 1a): số, chuỗi, tên trong nháy, cột, chú thích, toán tử, vị trí.
import Testing
import ColumnStore
@testable import DAXEngine

@Suite struct LANGLexerTests {
    /// Các loại token, bỏ token EOF ở cuối.
    private func kinds(_ text: String) throws -> [DAXToken.Kind] {
        let tokens = try DAXLexer.tokenize(text)
        return tokens.dropLast().map(\.kind)
    }

    @Test func soThapPhanVaSoMu() throws {
        let got = try kinds("1e6 0.8 .5 123 2E-3")
        #expect(got == [
            .number(1_000_000, isInteger: false),
            .number(0.8, isInteger: false),
            .number(0.5, isInteger: false),
            .number(123, isInteger: true),
            .number(0.002, isInteger: false),
        ])
    }

    @Test func chuoiCoEscapeNhayKep() throws {
        // "" bên trong chuỗi là một dấu nháy kép.
        #expect(try kinds("\"a\"\"b\"") == [.string("a\"b")])
        #expect(try kinds("\"\"") == [.string("")])
    }

    @Test func tenBangTrongNhayDonVaCot() throws {
        // '' bên trong tên bảng là một dấu nháy đơn; ]] bên trong cột là một dấu ].
        #expect(try kinds("'Dim ''x'''[c]") == [.quoted("Dim 'x'"), .bracket("c")])
        #expect(try kinds("[a]]b]") == [.bracket("a]b")])
    }

    @Test func cotAo() throws {
        #expect(try kinds("[@c]") == [.bracket("@c")])
    }

    @Test func chuThichBoQua() throws {
        // //, -- đến cuối dòng; /* */ có thể nhiều dòng.
        let got = try kinds("1 // a\n+ 2 -- b\n/* c \n d */ 3")
        #expect(got == [.number(1, isInteger: true), .symbol("+"), .number(2, isInteger: true),
                        .number(3, isInteger: true)])
    }

    @Test func toanTuVaDauCau() throws {
        let got = try kinds("<> <= >= == && || ! ^ & = < > + - * / ( ) { } , ;")
        let symbols = got.compactMap { kind -> String? in
            if case .symbol(let s) = kind { return s }
            return nil
        }
        #expect(symbols == ["<>", "<=", ">=", "==", "&&", "||", "!", "^", "&", "=", "<", ">",
                            "+", "-", "*", "/", "(", ")", "{", "}", ",", ";"])
        #expect(got.count == symbols.count)
    }

    @Test func dinhDanhVaTuKhoa() throws {
        // Dấu chấm trong PERCENTILEX.INC là một phần của định danh; NOT và IN là định danh trần.
        let got = try kinds("PERCENTILEX.INC Dim_Date Việt_Nam NOT IN")
        #expect(got == [.identifier("PERCENTILEX.INC"), .identifier("Dim_Date"), .identifier("Việt_Nam"),
                        .identifier("NOT"), .identifier("IN")])
    }

    @Test func viTriDongVaCotDemTabLaMotCot() throws {
        // "EVALUATE\n" dài 9 đơn vị, tab ở offset 9, R ở offset 10. Tab là 1 cột, nên R ở cột 2.
        let tokens = try DAXLexer.tokenize("EVALUATE\n\tROW")
        let row = tokens[1]
        #expect(row.range == SourceRange(start: 10, end: 13, line: 2, column: 2))
        #expect(tokens[0].range.line == 1)
        #expect(tokens[0].range.column == 1)
    }

    @Test func viTriDemTheoUTF16() throws {
        // "🔴" chiếm 2 đơn vị UTF-16, nên x nằm ở offset 7 và cột 8.
        let tokens = try DAXLexer.tokenize("\"🔴\" + x")
        let x = tokens[2]
        #expect(x.kind == .identifier("x"))
        #expect(x.range.start == 7)
        #expect(x.range.column == 8)
    }

    @Test func eofNamSauTokenThatCuoi() throws {
        // Token EOF không trỏ xuống dòng trống cuối văn bản, mà ngay sau token thật cuối cùng.
        let tokens = try DAXLexer.tokenize("ROW(1  \n\n")
        let eof = tokens[tokens.count - 1]
        #expect(eof.kind == .eof)
        #expect(eof.range.line == 1)
        #expect(eof.range.column == 6)
    }

    @Test func chuoiChuaDongBaoLoi() {
        do {
            _ = try DAXLexer.tokenize("x = \"abc")
            Issue.record("phải báo lỗi chuỗi chưa đóng")
        } catch {
            #expect(error.kind == .syntax)
            #expect(error.range?.line == 1)
            #expect(error.range?.column == 5)
        }
    }

    @Test func kyTuLaBaoLoi() {
        do {
            _ = try DAXLexer.tokenize("x | y")
            Issue.record("| đơn lẻ không phải toán tử DAX")
        } catch {
            #expect(error.kind == .syntax)
            #expect(error.range?.column == 3)
        }
    }
}
