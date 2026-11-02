// Test binder và catalog (LANG, đợt 1a): bind đủ 119 measure của Nhom6, lỗi có vị trí,
// các cấu trúc đặc biệt (RANKX với đối số trống, 1e6, [@c], VAR lồng, TOPN, DEFINE MEASURE).
import Foundation
import Testing
import ColumnStore
import PBIXKit
import DAXTestSupport
@testable import DAXEngine

/// Catalog của MiniBank, dùng cho test không cần file .pbix.
private func miniCatalog() -> Catalog {
    Catalog(schema: MiniBank.schema,
            measures: MiniBank.measures.map {
                ModelMeasureInput(table: $0.table, name: $0.name, expression: $0.expression)
            })
}

/// Từ khoá của một đối số đã bind (nil nếu không phải từ khoá).
private func keywordWord(_ arg: BoundExpr?) -> String? {
    guard let arg, case .keyword(let word) = arg else { return nil }
    return word
}

/// Bind một biểu thức và trả về lỗi (nil nếu thành công).
private func bindError(_ text: String, catalog: Catalog) -> DAXError? {
    do {
        _ = try Binder.bind(try parseExpression(text), catalog: catalog)
        return nil
    } catch {
        return error
    }
}

@Suite struct LANGBinderTests {
    // MARK: - MiniBank

    @Test func measureMiniBankBindDuoc() throws {
        let catalog = miniCatalog()
        for measure in MiniBank.measures {
            let expr = try parseExpression(measure.expression)
            _ = try Binder.bind(expr, catalog: catalog)
        }
        #expect(catalog.measures.count == MiniBank.measures.count)
    }

    @Test func tenSaiCotCoViTri() throws {
        // Tên cột sai nằm ở dòng 2 cột 21, vị trí của dấu nháy đơn mở tên bảng.
        let query = try parseQuery("DEFINE\n\tMEASURE 'x'[y] = 1\nEVALUATE\n\tFILTER ( Dim_Date, 'Dim_Date'[yearx] = 1 )")
        do {
            _ = try Binder.bindQuery(query, catalog: miniCatalog())
            Issue.record("cột sai phải báo lỗi")
        } catch {
            #expect(error.kind == .unknownName)
            #expect(error.range?.line == 4)
            #expect(error.range?.column == 21)
        }
    }

    @Test func tenHamSai() {
        let error = bindError("FOO(1)", catalog: miniCatalog())
        #expect(error?.kind == .unknownName)
        #expect(error?.range?.column == 1)
    }

    @Test func soDoiSoSai() {
        #expect(bindError("DIVIDE(1)", catalog: miniCatalog())?.kind == .arity)
        #expect(bindError("IF(1, 2, 3, 4)", catalog: miniCatalog())?.kind == .arity)
        #expect(bindError("DIVIDE(1, 2)", catalog: miniCatalog()) == nil)
        #expect(bindError("DIVIDE(1, 2, 0)", catalog: miniCatalog()) == nil)
    }

    @Test func bangKhongCoTenBao() {
        #expect(bindError("Foo[x]", catalog: miniCatalog())?.kind == .unknownName)
        #expect(bindError("[KhongCo]", catalog: miniCatalog())?.kind == .unknownName)
        #expect(bindError("Dim_Date[KhongCo]", catalog: miniCatalog())?.kind == .unknownName)
    }

    @Test func tenBangVaCotKhongPhanBietHoaThuong() {
        #expect(bindError("dim_date[YEAR]", catalog: miniCatalog()) == nil)
        #expect(bindError("'DIM_DATE'[Year]", catalog: miniCatalog()) == nil)
    }

    @Test func rankXDoiSoTrongVaTuKhoa() throws {
        let expr = try parseExpression("RANKX(ALL(Dim_Account), Dim_Account[branch_city], , DESC, DENSE)")
        let bound = try Binder.bind(expr, catalog: miniCatalog())
        guard case .call(let fid, let args) = bound else {
            Issue.record("RANKX phải bind thành lời gọi hàm")
            return
        }
        #expect(FunctionRegistry.all[Int(fid.raw)].name == "RANKX")
        #expect(args.count == 5)
        #expect(args[2] == nil)
        #expect(keywordWord(args[3]) == "DESC")
        #expect(keywordWord(args[4]) == "DENSE")
    }

    @Test func datediffNhanTuKhoaNgay() throws {
        let bound = try Binder.bind(try parseExpression("DATEDIFF(DATE(2020, 1, 1), DATE(2020, 1, 2), DAY)"),
                                    catalog: miniCatalog())
        guard case .call(_, let args) = bound else {
            Issue.record("phải là lời gọi hàm")
            return
        }
        guard let last = args[2], case .keyword(let word) = last else {
            Issue.record("đối số thứ ba phải là từ khoá")
            return
        }
        #expect(word == "DAY")
    }

    @Test func soThapPhanVaSoMuThanhLiteral() throws {
        let bound = try Binder.bind(try parseExpression("1e6 + 2"), catalog: miniCatalog())
        guard case .binary(.add, .literal(let lhs), .literal(let rhs)) = bound else {
            Issue.record("phải là phép cộng hai literal")
            return
        }
        #expect(lhs == .double(1_000_000))
        #expect(rhs == .integer(2))
    }

    @Test func cotAoVaVarLong() throws {
        // [@c] là cột ảo; VAR trong đối số của SUMX lấy slot riêng và tham chiếu đúng slot.
        let catalog = miniCatalog()
        let virtual = try Binder.bind(try parseExpression("[@c] > 0"), catalog: catalog)
        guard case .binary(.greater, .virtualColumn(let name), _) = virtual else {
            Issue.record("[@c] phải là cột ảo")
            return
        }
        #expect(name == "@c")

        let nested = try Binder.bind(try parseExpression("SUMX(Fact_Trans, VAR a = 1 RETURN a)"), catalog: catalog)
        guard case .call(_, let args) = nested, let body = args[1],
              case .varBlock(let slots, let values, let inner) = body else {
            Issue.record("VAR phải nằm trong đối số của SUMX")
            return
        }
        #expect(slots == [0])
        #expect(values.count == 1)
        if case .literal(let v) = values[0] { #expect(v == .integer(1)) } else { Issue.record("giá trị VAR phải là literal") }
        if case .variable(let s) = inner { #expect(s == 0) } else { Issue.record("thân phải tham chiếu slot 0") }
    }

    @Test func rowScopeTuBangCuaIterator() throws {
        // FILTER(Dim_Account, [branch_city] = "x"): [branch_city] là cột của Dim_Account trong phạm vi row.
        let bound = try Binder.bind(try parseExpression("FILTER(Dim_Account, [branch_city] = \"x\")"),
                                    catalog: miniCatalog())
        guard case .call(_, let args) = bound, let filter = args[1],
              case .binary(.equal, .column(let column), _) = filter else {
            Issue.record("[branch_city] phải bind thành cột")
            return
        }
        #expect(column == MiniBank.Columns.DimAccount.branchCity)
    }

    @Test func measureDuocUuTienHonCot() throws {
        let bound = try Binder.bind(try parseExpression("[Trans Amount]"), catalog: miniCatalog())
        guard case .measure(let id) = bound else {
            Issue.record("[Trans Amount] phải là measure")
            return
        }
        #expect(miniCatalog().measure(id)?.name == "Trans Amount")
    }

    @Test func hamChuaCaiVanBind() throws {
        // SUM là stub của đợt 0: bind được, lỗi chỉ xuất hiện lúc chạy.
        let bound = try Binder.bind(try parseExpression("SUM(Fact_Trans[amount])"), catalog: miniCatalog())
        guard case .call = bound else {
            Issue.record("SUM phải bind thành lời gọi")
            return
        }
    }

    // MARK: - Truy vấn và DEFINE

    @Test func defineMeasureChe() throws {
        let query = try parseQuery("DEFINE MEASURE 'Fact_Trans'[Trans Amount] = 1 EVALUATE FILTER(Fact_Trans, [Trans Amount] > 0)")
        let bound = try Binder.bindQuery(query, catalog: miniCatalog())
        guard case .call(_, let args) = bound.statements[0].table, let filter = args[1],
              case .binary(.greater, .measure(let id), _) = filter else {
            Issue.record("[Trans Amount] phải trỏ tới measure DEFINE")
            return
        }
        let defined = bound.catalog.measure(id)
        #expect(defined?.origin == .define)
        #expect(id.raw >= Int32(MiniBank.measures.count))
    }

    @Test func defineVariableVaTable() throws {
        let query = try parseQuery("DEFINE VAR v = 1 TABLE t = Dim_Date EVALUATE t")
        let bound = try Binder.bindQuery(query, catalog: miniCatalog())
        #expect(bound.definitions.count == 2)
        #expect(bound.definitions[0].kind == .variable)
        if case .literal(let v) = bound.definitions[0].value { #expect(v == .integer(1)) } else { Issue.record("VAR phải là literal") }
        #expect(bound.definitions[1].kind == .table)
        if case .variable(let s) = bound.statements[0].table {
            #expect(s == bound.definitions[1].slot)
        } else {
            Issue.record("EVALUATE t phải tham chiếu slot của TABLE")
        }
    }

    @Test func topNVoiThuTuGiamDan() throws {
        let bound = try Binder.bind(try parseExpression("TOPN(3, Dim_Account, Dim_Account[account_key], DESC)"),
                                    catalog: miniCatalog())
        guard case .call(let fid, let args) = bound else {
            Issue.record("TOPN phải là lời gọi")
            return
        }
        #expect(FunctionRegistry.all[Int(fid.raw)].name == "TOPN")
        #expect(args.count == 4)
        #expect(keywordWord(args[3]) == "DESC")
    }

    @Test func bindMeasureTheoID() throws {
        let catalog = miniCatalog()
        guard let index = catalog.measures.firstIndex(where: { $0.name == "Trans Amount" }) else {
            Issue.record("thiếu measure Trans Amount")
            return
        }
        let bound = try Binder.bindMeasure(MeasureID(raw: Int32(index)), catalog: catalog)
        guard case .call = bound else {
            Issue.record("thân measure phải là lời gọi SUM")
            return
        }
    }

    // MARK: - Nhom6 (bỏ qua khi thiếu file .pbix)

    /// Bind 119 measure của Nhom6 với ModelSchema và chữ ký hàm đợt 0.
    /// File TSV cắt biểu thức ở 300 ký tự (xem báo cáo), nên thân đầy đủ lấy từ metadata của model;
    /// TSV được đối chiếu theo tiền tố (sau khi gộp khoảng trắng), và các dòng không bị cắt được bind trực tiếp.
    @Test(.enabled(if: DAXFixtures.exists(DAXFixtures.nhom6)))
    func nhom6Bind119Measure() throws {
        let pbix = try PBIXFile(url: DAXFixtures.nhom6)
        let (abf, _) = try pbix.loadDataModel()
        let metadata = try ModelMetadata(sqlite: try abf.contents(named: "metadata.sqlitedb"))
        let catalog = Catalog(metadata: metadata)
        // 168 measure của model + 1 measure ẩn `_<M> FormatString` cho mỗi measure có định dạng động (E2, Phase C).
        let dynamicFormats = metadata.measures.filter { !($0.formatStringDefinition ?? "").isEmpty }.count
        #expect(catalog.measures.count == 168 + dynamicFormats)
        #expect(dynamicFormats == 19)

        let rows = try measures119()
        #expect(rows.count == 119)
        var failures: [String] = []
        var mismatched: [String] = []
        for row in rows {
            guard let measure = catalog.measure(named: row.name, table: row.table), measure.origin == .model else {
                failures.append("thiếu measure \(row.table)[\(row.name)]")
                continue
            }
            if !normalized(measure.text).hasPrefix(normalized(row.expression)) {
                mismatched.append("\(row.table)[\(row.name)]")
            }
            guard let body = measure.body else {
                failures.append("\(row.name): \(measure.parseError?.message ?? "không parse")")
                continue
            }
            do {
                _ = try Binder.bind(body, catalog: catalog)
            } catch {
                failures.append("\(row.table)[\(row.name)]: \(error.message)")
            }
        }
        #expect(failures.isEmpty, "bind lỗi: \(failures.prefix(5).joined(separator: " | "))")
        #expect(mismatched.isEmpty, "TSV không khớp tiền tố của model: \(mismatched.prefix(5))")

        // Các dòng TSV không bị cắt (dưới 300 ký tự) còn được bind trực tiếp từ văn bản TSV.
        var direct = 0
        var directFailures: [String] = []
        for row in rows where row.expression.count < 300 {
            do {
                _ = try Binder.bind(try parseExpression(row.expression), catalog: catalog)
                direct += 1
            } catch {
                directFailures.append("\(row.name): \(error.message)")
            }
        }
        #expect(directFailures.isEmpty, "bind trực tiếp lỗi: \(directFailures.prefix(5))")
        #expect(direct > 0)
    }

    /// Gộp khoảng trắng để so khớp TSV (đã gộp dòng) với văn bản gốc.
    private func normalized(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private struct Row {
        let table: String
        let name: String
        let expression: String
    }

    /// 119 measure từ docs/phase-b-oracle/measures-119.tsv (đã chép vào fixtures/). Cột 3, 4, 5 là bảng, tên, biểu thức.
    private func measures119() throws -> [Row] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("fixtures")
            .appendingPathComponent("measures-119.tsv")
        let text = try String(contentsOf: url, encoding: .utf8)
        var rows: [Row] = []
        for line in text.components(separatedBy: "\n").dropFirst() where !line.isEmpty {
            let cols = line.components(separatedBy: "\t")
            guard cols.count == 5 else { continue }
            rows.append(Row(table: cols[2], name: cols[3], expression: cols[4]))
        }
        return rows
    }
}
