// Kiểm thử toàn bộ ~56 hàm DAX mới của Wave 3 (v1.1b — specs/014, T001–T006).
// Mọi giá trị mong đợi đối chiếu trực tiếp Power BI Desktop 2.159 (`docs/phase-v11-evidence/vm-v11b/dax-golden.json`).

import Foundation
import Testing
import ColumnStore
import DAXTestSupport
@testable import DAXEngine

@Suite("Wave 3 (v1.1b) — DAX Engine Expansion & Desktop 2.159 Golden")
struct V11BDAXGoldenTests {
    private func makeEngine() -> DAXEngine {
        ftEngine(FTEncodedDateSource(base: MiniBank.makeSource()))
    }

    private func evalRow(_ dax: String, on engine: DAXEngine? = nil) async throws -> [Value] {
        let eng = engine ?? makeEngine()
        let result = try await eng.execute(dax)
        #expect(result.tables[0].rows.count == 1)
        return result.tables[0].rows[0]
    }

    private func serial(_ y: Int, _ m: Int, _ d: Int) -> Double {
        var c = DateComponents()
        c.calendar = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)
        c.year = y; c.month = m; c.day = d
        let unixDays = Int((c.date!.timeIntervalSince1970 / 86_400.0).rounded())
        return Double(unixDays + 25_569)
    }

    // MARK: - T001: DateTime functions

    @Test("WEEKDAY, WEEKNUM (1/2/21 ISO), EOMONTH, EDATE, TIME, MINUTE, SECOND, YEARFRAC khớp Desktop 2.159")
    func dateTimeScalarsMatchDesktop2159() async throws {
        let eng = makeEngine()
        // weekday_1_2_3: [1, 2, 1, 7, 0, 6, 1]
        let wd = try await evalRow("""
            EVALUATE ROW(
              "sun_t1", WEEKDAY(DATE(2024,1,7), 1),
              "mon_t1", WEEKDAY(DATE(2024,1,8), 1),
              "mon_t2", WEEKDAY(DATE(2024,1,8), 2),
              "sun_t2", WEEKDAY(DATE(2024,1,7), 2),
              "mon_t3", WEEKDAY(DATE(2024,1,8), 3),
              "sun_t3", WEEKDAY(DATE(2024,1,7), 3),
              "default", WEEKDAY(DATE(2024,1,7))
            )
            """, on: eng)
        #expect(wd == [.integer(1), .integer(2), .integer(1), .integer(7), .integer(0), .integer(6), .integer(1)])

        // weeknum_1_2: [1, 2, 1, 1, 52]
        let wn = try await evalRow("""
            EVALUATE ROW(
              "jan1_2024_t1", WEEKNUM(DATE(2024,1,1), 1),
              "jan7_2024_t1", WEEKNUM(DATE(2024,1,7), 1),
              "jan7_2024_t2", WEEKNUM(DATE(2024,1,7), 2),
              "dec31_2024_t21", WEEKNUM(DATE(2024,12,31), 21),
              "jan1_2023_t21", WEEKNUM(DATE(2023,1,1), 21)
            )
            """, on: eng)
        #expect(wn == [.integer(1), .integer(2), .integer(1), .integer(1), .integer(52)])

        // eomonth
        let eom = try await evalRow("""
            EVALUATE ROW(
              "a", EOMONTH(DATE(2024,1,15), 0),
              "b", EOMONTH(DATE(2024,1,15), 1),
              "c", EOMONTH(DATE(2024,1,15), -1),
              "d", EOMONTH(DATE(2023,2,10), 0)
            )
            """, on: eng)
        #expect(eom == [.dateTime(serial(2024, 1, 31)), .dateTime(serial(2024, 2, 29)),
                        .dateTime(serial(2023, 12, 31)), .dateTime(serial(2023, 2, 28))])

        // edate
        let ed = try await evalRow("""
            EVALUATE ROW(
              "a", EDATE(DATE(2024,1,31), 1),
              "b", EDATE(DATE(2023,1,31), 1),
              "c", EDATE(DATE(2024,3,31), -1),
              "d", EDATE(DATE(2024,2,29), 12)
            )
            """, on: eng)
        #expect(ed == [.dateTime(serial(2024, 2, 29)), .dateTime(serial(2023, 2, 28)),
                       .dateTime(serial(2024, 2, 29)), .dateTime(serial(2025, 2, 28))])

        // time_min_sec (including mod 24h wrap: TIME(25,70,80) = 02:11:20)
        let tm = try await evalRow("""
            EVALUATE ROW(
              "h", HOUR(TIME(14, 30, 45)),
              "m", MINUTE(TIME(14, 30, 45)),
              "s", SECOND(TIME(14, 30, 45)),
              "oh", HOUR(TIME(25, 70, 80)),
              "om", MINUTE(TIME(25, 70, 80)),
              "os", SECOND(TIME(25, 70, 80))
            )
            """, on: eng)
        #expect(tm == [.integer(14), .integer(30), .integer(45), .integer(2), .integer(11), .integer(20)])

        // yearfrac: [0.5, 0.49726775956284153, 0.49863013698630138, 0.49589041095890413]
        let yf = try await evalRow("""
            EVALUATE ROW(
              "b0", YEARFRAC(DATE(2024,1,1), DATE(2024,7,1), 0),
              "b1", YEARFRAC(DATE(2024,1,1), DATE(2024,7,1), 1),
              "b3", YEARFRAC(DATE(2024,1,1), DATE(2024,7,1), 3),
              "b1_2023", YEARFRAC(DATE(2023,1,1), DATE(2023,7,1), 1)
            )
            """, on: eng)
        let expectedYF = [0.5, 0.49726775956284153, 0.49863013698630138, 0.49589041095890413]
        for (got, exp) in zip(yf, expectedYF) {
            #expect(abs((try got.asDouble()) - exp) < 1e-12)
        }

        // TODAY / NOW return valid DateTime serials
        let tn = try await evalRow(#"EVALUATE ROW("t", TODAY(), "n", NOW(), "ok", NOW() >= TODAY())"#, on: eng)
        #expect(tn[2] == .boolean(true))
    }

    @Test("CALENDARAUTO và CALENDARAUTO(3) tạo đúng khoảng năm tài chính")
    func calendarAutoMatchesDesktop() async throws {
        let eng = makeEngine()
        let r = try await evalRow("""
            EVALUATE
            VAR t1 = CALENDARAUTO()
            VAR t2 = CALENDARAUTO(3)
            RETURN ROW("min1", MINX(t1, [Date]), "max1", MAXX(t1, [Date]), "c1", COUNTROWS(t1),
                       "min2", MINX(t2, [Date]), "max2", MAXX(t2, [Date]), "c2", COUNTROWS(t2))
            """, on: eng)
        #expect(r[0] == .dateTime(serial(2023, 1, 1)))
        #expect(r[1] == .dateTime(serial(2024, 12, 31)))
        #expect(r[2] == .integer(731))
        #expect(r[3] == .dateTime(serial(2022, 4, 1)))
        #expect(r[4] == .dateTime(serial(2025, 3, 31)))
    }

    // MARK: - T002: Time Intelligence (23 functions)

    @Test("DATESYTD/QTD/MTD, TOTALYTD/QTD/MTD, DATESBETWEEN, DATESINPERIOD, PREVIOUS*, NEXT*, PARALLELPERIOD, STARTOF*/ENDOF*")
    func timeIntelligenceAll23Functions() async throws {
        let eng = makeEngine()
        let dc = "Dim_Date[full_date]"

        // DATESYTD/QTD/MTD on 2024-05-15 (2024 is leap year: Jan 31 + Feb 29 + Mar 31 + Apr 30 + May 15 = 136)
        let dtd = try await evalRow("""
            EVALUATE ROW(
              "ytd", CALCULATE(COUNTROWS(DATESYTD(\(dc))), \(dc) = DATE(2024,5,15)),
              "qtd", CALCULATE(COUNTROWS(DATESQTD(\(dc))), \(dc) = DATE(2024,5,15)),
              "mtd", CALCULATE(COUNTROWS(DATESMTD(\(dc))), \(dc) = DATE(2024,5,15)),
              "ytd_fy6", CALCULATE(COUNTROWS(DATESYTD(\(dc), "6/30")), \(dc) = DATE(2024,8,15))
            )
            """, on: eng)
        #expect(dtd == [.integer(136), .integer(45), .integer(15), .integer(46)])

        // DATESBETWEEN (incl. BLANK start) & DATESINPERIOD
        let db = try await evalRow("""
            EVALUATE ROW(
              "feb24", COUNTROWS(DATESBETWEEN(\(dc), DATE(2024,2,1), DATE(2024,2,29))),
              "blank_start", COUNTROWS(DATESBETWEEN(\(dc), BLANK(), DATE(2023,1,10))),
              "inperiod_m3", COUNTROWS(DATESINPERIOD(\(dc), DATE(2024,3,31), -3, MONTH)),
              "inperiod_d10", COUNTROWS(DATESINPERIOD(\(dc), DATE(2024,3,15), 10, DAY))
            )
            """, on: eng)
        #expect(db == [.integer(29), .integer(10), .integer(91), .integer(10)])

        // PREVIOUS* / NEXT* / PARALLELPERIOD / STARTOF* / ENDOF*
        let pn = try await evalRow("""
            EVALUATE ROW(
              "pday", CALCULATE(MINX(PREVIOUSDAY(\(dc)), \(dc)), \(dc) = DATE(2024,3,1)),
              "nday", CALCULATE(MINX(NEXTDAY(\(dc)), \(dc)), \(dc) = DATE(2024,2,28)),
              "pmonth", CALCULATE(COUNTROWS(PREVIOUSMONTH(\(dc))), Dim_Date[year] = 2024, Dim_Date[month] = 3),
              "pqtr", CALCULATE(COUNTROWS(PREVIOUSQUARTER(\(dc))), Dim_Date[year] = 2024, Dim_Date[month] = 5),
              "pyr", CALCULATE(COUNTROWS(PREVIOUSYEAR(\(dc))), Dim_Date[year] = 2024),
              "nmonth", CALCULATE(COUNTROWS(NEXTMONTH(\(dc))), Dim_Date[year] = 2024, Dim_Date[month] = 1),
              "nqtr", CALCULATE(COUNTROWS(NEXTQUARTER(\(dc))), Dim_Date[year] = 2024, Dim_Date[month] = 2),
              "nyr", CALCULATE(COUNTROWS(NEXTYEAR(\(dc))), Dim_Date[year] = 2023),
              "par_m2", CALCULATE(COUNTROWS(PARALLELPERIOD(\(dc), -2, MONTH)), Dim_Date[year] = 2024, Dim_Date[month] = 5)
            )
            """, on: eng)
        #expect(pn[0] == .dateTime(serial(2024, 2, 29)))
        #expect(pn[1] == .dateTime(serial(2024, 2, 29)))
        #expect(pn[2] == .integer(29))
        #expect(pn[3] == .integer(91))
        #expect(pn[4] == .integer(365))
        #expect(pn[5] == .integer(29))
        #expect(pn[6] == .integer(91))
        #expect(pn[7] == .integer(366))
        #expect(pn[8] == .integer(31))

        let se = try await evalRow("""
            EVALUATE ROW(
              "som", CALCULATE(MINX(STARTOFMONTH(\(dc)), \(dc)), Dim_Date[year] = 2024, Dim_Date[month] = 2),
              "eom", CALCULATE(MINX(ENDOFMONTH(\(dc)), \(dc)), Dim_Date[year] = 2024, Dim_Date[month] = 2),
              "soq", CALCULATE(MINX(STARTOFQUARTER(\(dc)), \(dc)), Dim_Date[year] = 2024, Dim_Date[month] = 5),
              "eoq", CALCULATE(MINX(ENDOFQUARTER(\(dc)), \(dc)), Dim_Date[year] = 2024, Dim_Date[month] = 5),
              "soy", CALCULATE(MINX(STARTOFYEAR(\(dc)), \(dc)), Dim_Date[year] = 2024),
              "eoy", CALCULATE(MINX(ENDOFYEAR(\(dc)), \(dc)), Dim_Date[year] = 2024)
            )
            """, on: eng)
        #expect(se == [
            .dateTime(serial(2024, 2, 1)), .dateTime(serial(2024, 2, 29)),
            .dateTime(serial(2024, 4, 1)), .dateTime(serial(2024, 6, 30)),
            .dateTime(serial(2024, 1, 1)), .dateTime(serial(2024, 12, 31)),
        ])

        // TOTALYTD / TOTALQTD / TOTALMTD agree with CALCULATE(..., DATES*(...))
        let tot = try await evalRow("""
            EVALUATE ROW(
              "tytd", CALCULATE(TOTALYTD(COUNTROWS(Fact_Trans), \(dc)), Dim_Date[year] = 2024, Dim_Date[month] = 5),
              "cytd", CALCULATE(COUNTROWS(Fact_Trans), DATESBETWEEN(\(dc), DATE(2024,1,1), DATE(2024,5,31))),
              "tqtd", CALCULATE(TOTALQTD(COUNTROWS(Fact_Trans), \(dc)), Dim_Date[year] = 2024, Dim_Date[month] = 5),
              "cqtd", CALCULATE(COUNTROWS(Fact_Trans), DATESBETWEEN(\(dc), DATE(2024,4,1), DATE(2024,5,31))),
              "tmtd", CALCULATE(TOTALMTD(COUNTROWS(Fact_Trans), \(dc)), \(dc) = DATE(2024,5,15)),
              "cmtd", CALCULATE(COUNTROWS(Fact_Trans), DATESBETWEEN(\(dc), DATE(2024,5,1), DATE(2024,5,15)))
            )
            """, on: eng)
        #expect(tot[0] == tot[1])
        #expect(tot[2] == tot[3])
        #expect(tot[4] == tot[5])
    }

    // MARK: - T003: Error & Type Info

    @Test("IFERROR, ISERROR, ERROR, ISNUMBER, ISTEXT, ISLOGICAL khớp Desktop 2.159")
    func errorAndTypeInfoMatchDesktop() async throws {
        let r = try await evalRow("""
            EVALUATE ROW(
              "iferr_ok", IFERROR(10/2, -1),
              "iferr_err", IFERROR(ERROR("boom"), -1),
              "iserr_ok", ISERROR(42),
              "iserr_err", ISERROR(ERROR("x")),
              "isnum_int", ISNUMBER(42),
              "isnum_str", ISNUMBER("42"),
              "isnum_blank", ISNUMBER(BLANK()),
              "istxt_str", ISTEXT("abc"),
              "istxt_num", ISTEXT(42),
              "istxt_blank", ISTEXT(BLANK()),
              "islog_t", ISLOGICAL(TRUE()),
              "islog_1", ISLOGICAL(1)
            )
            """)
        #expect(r == [
            .double(5), .integer(-1), .boolean(false), .boolean(true),
            .boolean(true), .boolean(false), .boolean(false),
            .boolean(true), .boolean(false), .boolean(false),
            .boolean(true), .boolean(false),
        ])
    }

    // MARK: - T004: Lookup, Table, Set, Stats

    @Test("LOOKUPVALUE, SELECTCOLUMNS, UNION/INTERSECT/EXCEPT (multiset), GENERATESERIES, DATATABLE, COUNTBLANK/X, PRODUCTX, STDEV.S/VAR.S")
    func tableSetLookupStatsMatchDesktop() async throws {
        let eng = makeEngine()

        // LOOKUPVALUE
        let lv = try await evalRow("""
            EVALUATE ROW(
              "found", LOOKUPVALUE(Dim_Date[year], Dim_Date[full_date], DATE(2024,5,15)),
              "miss_b", LOOKUPVALUE(Dim_Date[year], Dim_Date[full_date], DATE(1999,1,1)),
              "miss_a", LOOKUPVALUE(Dim_Date[year], Dim_Date[full_date], DATE(1999,1,1), -1)
            )
            """, on: eng)
        #expect(lv == [.integer(2024), .blank, .integer(-1)])

        // UNION / INTERSECT / EXCEPT multiset semantics (VM-V11B: 7, 17, 3, 7, 1, 1)
        let sets = try await evalRow("""
            EVALUATE
            VAR A = {1, 2, 3, 2}
            VAR B = {2, 3, 4}
            RETURN ROW(
              "uc", COUNTROWS(UNION(A, B)), "us", SUMX(UNION(A, B), [Value]),
              "ic", COUNTROWS(INTERSECT(A, B)), "is", SUMX(INTERSECT(A, B), [Value]),
              "ec", COUNTROWS(EXCEPT(A, B)), "es", SUMX(EXCEPT(A, B), [Value])
            )
            """, on: eng)
        #expect(sets == [.integer(7), .integer(17), .integer(3), .integer(7), .integer(1), .integer(1)])

        // GENERATESERIES (VM-V11B: 5, 25, 4, 5)
        let gs = try await evalRow("""
            EVALUATE
            VAR s = GENERATESERIES(1, 10, 2)
            VAR f = GENERATESERIES(0.5, 2.0, 0.5)
            RETURN ROW("c", COUNTROWS(s), "s", SUMX(s, [Value]), "fc", COUNTROWS(f), "fs", SUMX(f, [Value]))
            """, on: eng)
        #expect(gs[0] == .integer(5))
        #expect(gs[1] == .integer(25))
        #expect(gs[2] == .integer(4))
        #expect(abs((try gs[3].asDouble()) - 5.0) < 1e-12)

        // DATATABLE + COUNTX + COUNTAX + PRODUCTX + COUNTBLANK (returns BLANK when 0 blanks!) + SELECTCOLUMNS
        let dt = try await evalRow("""
            EVALUATE
            VAR t = DATATABLE("K", STRING, "V", DOUBLE, {{"a", 2}, {"b", 3}, {"c", 4}, {"d", BLANK()}})
            VAR sc = SELECTCOLUMNS(t, "Key", [K], "Two", [V] * 2)
            RETURN ROW(
              "cnt", COUNTROWS(t),
              "cx", COUNTX(t, [V]),
              "cax", COUNTAX(t, [K]),
              "px", PRODUCTX(t, [V]),
              "sc_sum", SUMX(sc, [Two]),
              "cb_zero", COUNTBLANK(Dim_Date[year])
            )
            """, on: eng)
        #expect(dt[0] == .integer(4))
        #expect(dt[1] == .integer(3))
        #expect(dt[2] == .integer(4))
        #expect(abs((try dt[3].asDouble()) - 24.0) < 1e-12)
        #expect(abs((try dt[4].asDouble()) - 18.0) < 1e-12)
        #expect(dt[5] == .blank)

        // STDEV.S & VAR.S on Dim_Date[year]
        let st = try await evalRow(#"EVALUATE ROW("s", STDEV.S(Dim_Date[year]), "v", VAR.S(Dim_Date[year]))"#, on: eng)
        let sVal = try st[0].asDouble()
        let vVal = try st[1].asDouble()
        #expect(abs(sVal * sVal - vVal) < 1e-12)
        #expect(vVal > 0.24 && vVal < 0.26)
    }

    // MARK: - T005: Window functions (OFFSET, INDEX, WINDOW)

    @Test("OFFSET, INDEX, WINDOW với ORDERBY và PARTITIONBY khớp Desktop 2.159")
    func windowFunctionsMatchDesktop() async throws {
        let eng = makeEngine()
        let res = try await eng.execute("""
            EVALUATE
            VAR Base = DATATABLE("R", STRING, "C", INTEGER, {
              {"Midwest", 546},
              {"Northeast", 2804},
              {"South", 1086},
              {"Unknown", 1},
              {"West", 933}
            })
            RETURN ADDCOLUMNS(
              Base,
              "PrevC", MAXX(OFFSET(-1, Base, ORDERBY([R], ASC)), [C]),
              "FirstR", MAXX(INDEX(1, Base, ORDERBY([R], ASC)), [R]),
              "LastR", MAXX(INDEX(-1, Base, ORDERBY([R], ASC)), [R]),
              "RunSum", SUMX(WINDOW(1, ABS, 0, REL, Base, ORDERBY([R], ASC)), [C])
            )
            ORDER BY [R] ASC
            """).tables[0]
        #expect(res.rows.count == 5)
        // Exact Desktop 2.159 golden rows from dax-golden.json!
        let expectedPrev: [Value] = [.blank, .integer(546), .integer(2804), .integer(1086), .integer(1)]
        let expectedRun: [Int64] = [546, 3350, 4436, 4437, 5370]
        for i in 0..<5 {
            #expect(res.rows[i][2] == expectedPrev[i])
            #expect(res.rows[i][3] == .string("Midwest"))
            #expect(res.rows[i][4] == .string("West"))
            #expect(res.rows[i][5] == .integer(expectedRun[i]))
        }

        // PARTITIONBY test
        let partRes = try await eng.execute("""
            EVALUATE
            VAR T = DATATABLE("G", STRING, "Seq", INTEGER, "V", INTEGER, {
              {"A", 1, 10}, {"A", 2, 20}, {"B", 1, 100}, {"B", 2, 200}
            })
            RETURN ADDCOLUMNS(T, "RunG", SUMX(WINDOW(1, ABS, 0, REL, T, ORDERBY([Seq], ASC), , PARTITIONBY([G])), [V]))
            ORDER BY [G] ASC, [Seq] ASC
            """).tables[0]
        #expect(partRes.rows.map { $0[3] } == [.integer(10), .integer(30), .integer(100), .integer(300)])
    }

    // MARK: - FunctionRegistry integrity

    @Test("Toàn bộ hàm mới đăng ký không trùng tên và có mặt trong FunctionRegistry cho Autocomplete")
    func registryUniqueAndComplete() {
        let names = FunctionRegistry.all.map(\.name)
        #expect(Set(names).count == names.count)
        for required in [
            "TODAY", "NOW", "WEEKDAY", "WEEKNUM", "EOMONTH", "EDATE", "MINUTE", "SECOND", "TIME", "YEARFRAC", "CALENDARAUTO",
            "DATESYTD", "DATESQTD", "DATESMTD", "TOTALYTD", "TOTALQTD", "TOTALMTD", "DATESBETWEEN", "DATESINPERIOD",
            "PREVIOUSDAY", "PREVIOUSMONTH", "PREVIOUSQUARTER", "PREVIOUSYEAR",
            "NEXTDAY", "NEXTMONTH", "NEXTQUARTER", "NEXTYEAR", "PARALLELPERIOD",
            "STARTOFMONTH", "ENDOFMONTH", "STARTOFQUARTER", "ENDOFQUARTER", "STARTOFYEAR", "ENDOFYEAR",
            "ERROR", "IFERROR", "ISERROR", "ISNUMBER", "ISTEXT", "ISLOGICAL",
            "LOOKUPVALUE", "SELECTCOLUMNS", "UNION", "INTERSECT", "EXCEPT", "GENERATESERIES", "DATATABLE",
            "COUNTBLANK", "COUNTX", "COUNTAX", "PRODUCTX", "STDEV.S", "VAR.S",
            "OFFSET", "INDEX", "WINDOW", "ORDERBY", "PARTITIONBY",
        ] {
            #expect(FunctionRegistry.byName[required] != nil, "Missing function \(required)")
        }
    }
}
