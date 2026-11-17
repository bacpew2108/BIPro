#!/usr/bin/env python3
"""VM-F12 (T018): sinh biểu thức bảng tính toán quan sát 19 hàm văn bản DAX trong Power BI Desktop.

Mỗi ca là một biểu thức DAX; kết quả mã hoá thành chuỗi để một cột chữ giữ được mọi kiểu:
  "E" lỗi (ISERROR), "B" BLANK, "T:<chuỗi>", "L:<TRUE|FALSE>", "N:<số đổi sang chuỗi bằng &>".
Bảng `HCol`: SELECTCOLUMNS trên `text_cases` (Case, ID, R). Bảng `HLit1..3`: UNION của ROW (Case, R).
Ký tự đặc biệt viết bằng UNICHAR để biểu thức chỉ có ASCII. Lỗi phải bắt bằng ISERROR(<biểu thức>) viết thẳng:
ISERROR(v) với VAR v = <biểu thức lỗi> không bắt được (Desktop báo lỗi cả bảng).

Chạy: python3 scripts/f2-samples/vm_f12_queries.py  → build/f2-out/f12/{hcol,hlit1,hlit2,hlit3}.dax (UTF-16LE có BOM, để
`clip <` rồi dán vào New table) và cases.tsv (Case, Expr, bảng).
"""
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "build", "f2-out", "f12")

EMOJI = "UNICHAR(128512)"
NFD_O = 'UNICHAR(111)&UNICHAR(803)&UNICHAR(770)'      # o + dấu nặng + dấu mũ (NFD của "ộ")
NFC_O = "UNICHAR(7897)"                                 # "ộ"


def enc(e: str) -> str:
    return (f'IF(ISERROR({e}), "E", VAR v = {e} RETURN IF(ISBLANK(v), "B", IF(ISTEXT(v), "T:" & v, '
            f'IF(ISLOGICAL(v), "L:" & v, "N:" & v))))')


def q(s: str) -> str:
    return '"' + s.replace('"', '""') + '"'


# Ca trên cột: biểu thức dùng [ID], [Txt], [Nfd], [Num] của text_cases.
COL = [
    ("IN-Txt", "[Txt]"), ("IN-Nfd", "[Nfd]"), ("IN-Num", "[Num]"),
    ("LEN-Txt", "LEN([Txt])"), ("LEN-Nfd", "LEN([Nfd])"), ("LEN-Num", "LEN([Num])"),
    ("UPPER-Txt", "UPPER([Txt])"), ("UPPER-Nfd", "UPPER([Nfd])"),
    ("LOWER-Txt", "LOWER([Txt])"), ("LOWER-Nfd", "LOWER([Nfd])"),
    ("MID-2-3", "MID([Txt], 2, 3)"), ("MID-ID", "MID([Txt], [ID] - 5, 4)"),
    ("RIGHT-3", "RIGHT([Txt], 3)"), ("RIGHT-def", "RIGHT([Txt])"), ("RIGHT-ID", "RIGHT([Txt], [ID] - 10)"),
    ("LEFT-2", "LEFT([Txt], 2)"),
    ("TRIM-Txt", "TRIM([Txt])"),
    ("SUBST-a", 'SUBSTITUTE([Txt], "a", "X")'), ("SUBST-a-2", 'SUBSTITUTE([Txt], "a", "X", 2)'),
    ("SUBST-nfc", f'SUBSTITUTE([Txt], {NFC_O}, "#")'), ("SUBST-nfd", f'SUBSTITUTE([Nfd], {NFC_O}, "#")'),
    ("REPLACE-2-3", 'REPLACE([Txt], 2, 3, "__")'),
    ("CONCAT-Txt-Num", "CONCATENATE([Txt], [Num])"), ("CONCAT-ID-Txt", "CONCATENATE([ID], [Txt])"),
    ("CONCATX-ID", 'VAR i = [ID] RETURN CONCATENATEX(FILTER(text_cases, text_cases[ID] <= i), text_cases[ID], ",", text_cases[ID], DESC)'),
    ("SEARCH-a", 'SEARCH("a", [Txt], 1, -1)'), ("SEARCH-A?C", 'SEARCH("A?C", [Txt], 1, -1)'),
    ("SEARCH-*b", 'SEARCH("*b", [Txt], 1, -1)'), ("SEARCH-~*", 'SEARCH("~*", [Txt], 1, -1)'),
    ("SEARCH-n-nodef", 'SEARCH("n", [Txt])'), ("SEARCH-nfc", f'SEARCH({NFC_O}, [Nfd], 1, -1)'),
    ("FIND-a", 'FIND("a", [Txt], 1, -1)'), ("FIND-Aup", 'FIND("A", [Txt], 1, -1)'), ("FIND-a-nodef", 'FIND("a", [Txt])'),
    ("REPT-2", "REPT([Txt], 2)"), ("REPT-ID", 'REPT("ab", [ID] - 10)'),
    ("VALUE-Txt", "VALUE([Txt])"),
    ("EXACT-Txt-Nfd", "EXACT([Txt], [Nfd])"), ("EXACT-Txt-UP", "EXACT([Txt], UPPER([Txt]))"),
    ("UNICODE-Txt", "UNICODE([Txt])"), ("UNICODE-Nfd", "UNICODE([Nfd])"), ("UNICHAR-ID", "UNICHAR([ID] + 64)"),
    ("FIXED-Num", "FIXED([Num])"), ("FIXED-Num-1", "FIXED([Num], 1)"), ("FIXED-Num--2", "FIXED([Num], -2)"),
    ("FIXED-Num-2-T", "FIXED([Num], 2, TRUE())"),
    ("COMBINE-Txt-Num", 'COMBINEVALUES("|", [Txt], [Num])'), ("COMBINE-ID-Txt", 'COMBINEVALUES(",", [ID], [Txt])'),
]

LIT1 = [
    ("LEN-blank", "LEN(BLANK())"), ("LEN-empty", 'LEN("")'), ("LEN-emoji", f"LEN({EMOJI})"), ("LEN-nfdlit", f"LEN({NFD_O})"),
    ("LEN-numlit", "LEN(123.45)"), ("LEN-bool", "LEN(TRUE())"), ("LEN-int", "LEN(-120)"),
    ("UPPER-blank", "UPPER(BLANK())"), ("UPPER-ss", "UPPER(UNICHAR(223))"), ("UPPER-num", "UPPER(1.5)"),
    ("UPPER-d", "UPPER(UNICHAR(273))"), ("LOWER-blank", "LOWER(BLANK())"), ("LOWER-I", "LOWER(UNICHAR(304))"),
    ("LOWER-bool", "LOWER(TRUE())"), ("UPPER-emoji", f'UPPER("a" & {EMOJI})'),
    ("MID-0", 'MID("abcdef", 0, 2)'), ("MID-neg", 'MID("abcdef", -1, 2)'), ("MID-past", 'MID("abcdef", 10, 2)'),
    ("MID-len0", 'MID("abcdef", 2, 0)'), ("MID-lenneg", 'MID("abcdef", 2, -1)'), ("MID-long", 'MID("abcdef", 2, 100)'),
    ("MID-blank", "MID(BLANK(), 1, 2)"), ("MID-frac", 'MID("abcdef", 1.7, 2.6)'), ("MID-emoji", f'MID("x" & {EMOJI} & "y", 2, 1)'),
    ("MID-emoji2", f'MID("x" & {EMOJI} & "y", 2, 2)'), ("MID-num", "MID(12345, 2, 2)"),
    ("MID-emoji-u", f'UNICODE(MID("x" & {EMOJI} & "y", 2, 1))'), ("MID-emoji-len", f'LEN(MID("x" & {EMOJI} & "y", 2, 1))'),
    ("MID-emoji-u3", f'UNICODE(MID("x" & {EMOJI} & "y", 3, 1))'), ("RIGHT-emoji-u", f'UNICODE(RIGHT("x" & {EMOJI}, 1))'),
    ("LEFT-emoji-u", f'UNICODE(LEFT({EMOJI} & "x", 1))'), ("MID-6", 'MID("abcdef", 6, 1)'),
    ("MID-7", 'MID("abcdef", 7, 1)'), ("MID-blanklen", 'MID("abcdef", 2, BLANK())'), ("MID-blankstart", 'MID("abcdef", BLANK(), 2)'),
    ("RIGHT-0", 'RIGHT("abc", 0)'), ("RIGHT-neg", 'RIGHT("abc", -1)'), ("RIGHT-past", 'RIGHT("abc", 10)'),
    ("RIGHT-blank", "RIGHT(BLANK(), 2)"), ("RIGHT-def1", 'RIGHT("abc")'), ("RIGHT-num", "RIGHT(12345, 2)"),
    ("RIGHT-frac", 'RIGHT("abcdef", 2.9)'), ("RIGHT-emoji", f'RIGHT("x" & {EMOJI}, 1)'), ("RIGHT-blanklen", 'RIGHT("abc", BLANK())'),
    ("LEFT-0", 'LEFT("abc", 0)'), ("LEFT-neg", 'LEFT("abc", -1)'), ("LEFT-emoji", f'LEFT({EMOJI} & "x", 1)'),
    ("TRIM-sp", 'TRIM("  a   b  ")'), ("TRIM-blank", "TRIM(BLANK())"), ("TRIM-tab", 'TRIM(" a" & UNICHAR(9) & " b ")'),
    ("TRIM-nbsp", 'TRIM(UNICHAR(160) & "a" & UNICHAR(160))'), ("TRIM-num", "TRIM(12)"), ("TRIM-empty", 'TRIM("   ")'),
    ("TRIM-nl", 'TRIM(" a " & UNICHAR(10) & " b ")'), ("TRIM-ideo", 'TRIM(UNICHAR(12288) & "a")'),
    ("SUBST-0", 'SUBSTITUTE("aaa", "a", "b", 0)'), ("SUBST-neg", 'SUBSTITUTE("aaa", "a", "b", -1)'),
    ("SUBST-4", 'SUBSTITUTE("aaa", "a", "b", 4)'), ("SUBST-3", 'SUBSTITUTE("aaa", "a", "b", 3)'),
    ("SUBST-emptyold", 'SUBSTITUTE("aaa", "", "x")'), ("SUBST-blank", 'SUBSTITUTE(BLANK(), "a", "b")'),
    ("SUBST-newblank", 'SUBSTITUTE("aaa", "a", BLANK())'), ("SUBST-case", 'SUBSTITUTE("aAa", "a", "x")'),
    ("SUBST-overlap", 'SUBSTITUTE("aaaa", "aa", "x")'), ("SUBST-overlap-2", 'SUBSTITUTE("aaaa", "aa", "x", 2)'),
    ("SUBST-num", "SUBSTITUTE(1000, 0, 9)"), ("SUBST-frac", 'SUBSTITUTE("aaa", "a", "b", 1.9)'),
    ("SUBST-oldblank", 'SUBSTITUTE("aaa", BLANK(), "x")'),
]

LIT2 = [
    ("REPLACE-0", 'REPLACE("abcdef", 0, 2, "X")'), ("REPLACE-neg", 'REPLACE("abcdef", -1, 2, "X")'),
    ("REPLACE-past", 'REPLACE("abcdef", 10, 2, "X")'), ("REPLACE-len0", 'REPLACE("abcdef", 2, 0, "X")'),
    ("REPLACE-lenneg", 'REPLACE("abcdef", 2, -1, "X")'), ("REPLACE-long", 'REPLACE("abcdef", 2, 100, "X")'),
    ("REPLACE-blank", 'REPLACE(BLANK(), 1, 1, "X")'), ("REPLACE-newblank", 'REPLACE("abc", 1, 1, BLANK())'),
    ("REPLACE-7", 'REPLACE("abcdef", 7, 1, "X")'), ("REPLACE-num", 'REPLACE(12345, 2, 2, "-")'),
    ("REPLACE-frac", 'REPLACE("abcdef", 2.8, 1.9, "X")'), ("REPLACE-emoji", f'REPLACE("x" & {EMOJI} & "y", 2, 1, "-")'),
    ("CONCAT-bb", "CONCATENATE(BLANK(), BLANK())"), ("CONCAT-ab", 'CONCATENATE("a", BLANK())'),
    ("CONCAT-nums", "CONCATENATE(1, 2)"), ("CONCAT-bool", 'CONCATENATE(TRUE(), "x")'), ("CONCAT-dec", 'CONCATENATE(1.5, "")'),
    ("CONCAT-big", 'CONCATENATE(1234567890123, "")'), ("CONCAT-small", 'CONCATENATE(0.000001, "")'),
    ("CONCAT-third", 'CONCATENATE(1/3, "")'), ("CONCAT-neg", 'CONCATENATE(-2.50, "x")'), ("CONCAT-1e20", 'CONCATENATE(1E+20, "")'),
    ("CONCAT-date", 'CONCATENATE(DATE(2026, 1, 2), "")'), ("AMP-bb", "BLANK() & BLANK()"),
    ("CONCATX-1", 'CONCATENATEX({1, 2, 3}, [Value], ",")'), ("CONCATX-nodelim", "CONCATENATEX({1, 2, 3}, [Value])"),
    ("CONCATX-asc", 'CONCATENATEX({"b", "a", "c"}, [Value], "-", [Value], ASC)'),
    ("CONCATX-desc", 'CONCATENATEX({"b", "a", "c"}, [Value], "-", [Value], DESC)'),
    ("CONCATX-empty", 'CONCATENATEX(FILTER({1}, FALSE()), [Value], ",")'),
    ("CONCATX-blankitem", 'CONCATENATEX({"a", BLANK(), "c"}, [Value], ",")'),
    ("CONCATX-dec", 'CONCATENATEX({1.5, 2.25}, [Value], ";")'),
    ("CONCATX-bool", 'CONCATENATEX({TRUE(), FALSE()}, [Value], ",")'),
    ("CONCATX-expr", 'CONCATENATEX({1, 2}, [Value] * 10, "+")'),
    ("CONCATX-two", 'CONCATENATEX({("b", 2), ("a", 1)}, [Value1], ",", [Value2], ASC)'),
    ("CONCATX-defsort", 'CONCATENATEX({"b", "a", "c"}, [Value], "-", [Value])'),
    ("SEARCH-b", 'SEARCH("b", "abc")'), ("SEARCH-Bup", 'SEARCH("B", "abc")'), ("SEARCH-q", 'SEARCH("a?c", "abc")'),
    ("SEARCH-star", 'SEARCH("a*c", "abxyc")'), ("SEARCH-staronly", 'SEARCH("*", "abc")'), ("SEARCH-qempty", 'SEARCH("?", "", 1, -1)'),
    ("SEARCH-esc*", 'SEARCH("~*", "a*b")'), ("SEARCH-esc?", 'SEARCH("~?", "a?b")'), ("SEARCH-esc~", 'SEARCH("~~", "a~b")'),
    ("SEARCH-tilde", 'SEARCH("~", "a~b")'), ("SEARCH-empty", 'SEARCH("", "abc")'), ("SEARCH-nf", 'SEARCH("x", "abc")'),
    ("SEARCH-nf-def", 'SEARCH("x", "abc", 1, -1)'), ("SEARCH-nf-blank", 'SEARCH("x", "abc", 1, BLANK())'),
    ("SEARCH-start3", 'SEARCH("b", "abcb", 3)'), ("SEARCH-start0", 'SEARCH("b", "abc", 0)'),
    ("SEARCH-start10", 'SEARCH("b", "abc", 10)'), ("SEARCH-start10-def", 'SEARCH("b", "abc", 10, -1)'),
    ("SEARCH-blankfind", 'SEARCH(BLANK(), "abc")'), ("SEARCH-blankwithin", 'SEARCH("a", BLANK(), 1, -1)'),
    ("SEARCH-empty-start4", 'SEARCH("", "abc", 4)'), ("SEARCH-empty-start5", 'SEARCH("", "abc", 5, -1)'),
    ("SEARCH-accent", f'SEARCH("o", {NFC_O}, 1, -1)'), ("SEARCH-dd", 'SEARCH("d", UNICHAR(273), 1, -1)'),
    ("SEARCH-emoji", f'SEARCH("y", "x" & {EMOJI} & "y")'), ("SEARCH-num", "SEARCH(3, 12345)"),
    ("SEARCH-q2", 'SEARCH("b?", "abc")'), ("SEARCH-star2", 'SEARCH("b*", "abc")'),
]

LIT3 = [
    ("FIND-b", 'FIND("b", "abc")'), ("FIND-Bup", 'FIND("B", "abc")'), ("FIND-B-def", 'FIND("B", "abc", 1, -1)'),
    ("FIND-empty", 'FIND("", "abc")'), ("FIND-empty3", 'FIND("", "abc", 3)'), ("FIND-q", 'FIND("?", "a?b")'),
    ("FIND-star", 'FIND("*", "abc", 1, -1)'), ("FIND-start3", 'FIND("b", "abcb", 3)'), ("FIND-start0", 'FIND("b", "abc", 0, -1)'),
    ("FIND-start4", 'FIND("b", "abc", 4, -1)'), ("FIND-start5", 'FIND("b", "abc", 5, -1)'), ("FIND-blankwithin", 'FIND("a", BLANK(), 1, -1)'),
    ("FIND-blankfind", 'FIND(BLANK(), "abc")'), ("FIND-nf-blank", 'FIND("x", "abc", 1, BLANK())'), ("FIND-emoji", f'FIND("y", {EMOJI} & "y")'),
    ("FIND-accent", f'FIND("o", {NFC_O}, 1, -1)'), ("FIND-num", "FIND(4, 12345)"),
    ("REPT-3", 'REPT("ab", 3)'), ("REPT-0", 'REPT("ab", 0)'), ("REPT-neg", 'REPT("ab", -1)'), ("REPT-frac", 'REPT("ab", 2.9)'),
    ("REPT-blank", "REPT(BLANK(), 3)"), ("REPT-empty", 'REPT("", 5)'), ("REPT-num", "REPT(12, 2)"), ("REPT-blankn", 'REPT("ab", BLANK())'),
    ("REPT-emoji", f"REPT({EMOJI}, 2)"),
    ("VALUE-comma", 'VALUE("1,5")'), ("VALUE-dot", 'VALUE("1.5")'), ("VALUE-sp", 'VALUE(" 12 ")'), ("VALUE-neg", 'VALUE("-3.75")'),
    ("VALUE-exp", 'VALUE("1e3")'), ("VALUE-dollar", 'VALUE("$5")'), ("VALUE-pct", 'VALUE("10%")'), ("VALUE-empty", 'VALUE("")'),
    ("VALUE-blank", "VALUE(BLANK())"), ("VALUE-abc", 'VALUE("abc")'), ("VALUE-paren", 'VALUE("(5)")'),
    ("VALUE-thou", 'VALUE("1,234.5")'), ("VALUE-true", 'VALUE("TRUE")'), ("VALUE-num", "VALUE(12)"),
    ("VALUE-date", 'VALUE("2026-01-02")'), ("VALUE-time", 'VALUE("12:00")'), ("VALUE-plus", 'VALUE("+7")'),
    ("VALUE-int", 'VALUE("42")'), ("VALUE-lead0", 'VALUE("007")'), ("VALUE-tab", 'VALUE(UNICHAR(9) & "5")'),
    ("EXACT-case", 'EXACT("a", "A")'), ("EXACT-same", 'EXACT("a", "a")'), ("EXACT-blank-empty", 'EXACT(BLANK(), "")'),
    ("EXACT-bb", "EXACT(BLANK(), BLANK())"), ("EXACT-num", 'EXACT(1, "1")'), ("EXACT-nfd", f"EXACT({NFC_O}, {NFD_O})"),
    ("EXACT-sp", 'EXACT("a", "a ")'), ("EXACT-dec", 'EXACT(1.5, "1.5")'), ("EXACT-bool", 'EXACT(TRUE(), "TRUE")'),
    ("EXACT-dd", 'EXACT(UNICHAR(273), UNICHAR(272))'),
    ("UNICHAR-65", "UNICHAR(65)"), ("UNICHAR-0", "UNICHAR(0)"), ("UNICHAR-neg", "UNICHAR(-1)"), ("UNICHAR-emoji", "UNICHAR(128512)"),
    ("UNICHAR-surr", "UNICHAR(55357)"), ("UNICHAR-max", "UNICHAR(1114111)"), ("UNICHAR-over", "UNICHAR(1114112)"),
    ("UNICHAR-frac", "UNICHAR(65.7)"), ("UNICHAR-blank", "UNICHAR(BLANK())"), ("UNICHAR-text", 'UNICHAR("66")'),
    ("UNICHAR-len", "LEN(UNICHAR(128512))"), ("UNICHAR-1", "UNICODE(UNICHAR(1))"),
    ("UNICODE-A", 'UNICODE("A")'), ("UNICODE-empty", 'UNICODE("")'), ("UNICODE-emoji", f"UNICODE({EMOJI})"),
    ("UNICODE-blank", "UNICODE(BLANK())"), ("UNICODE-nfdlit", f"UNICODE({NFD_O})"), ("UNICODE-num", "UNICODE(123)"),
    ("UNICODE-ab", 'UNICODE("ab")'), ("UNICODE-dd", "UNICODE(UNICHAR(273))"), ("UNICODE-emoji2", f'UNICODE({EMOJI} & "a")'),
    ("UNICODE-bool", "UNICODE(TRUE())"),
    ("FIXED-def", "FIXED(1234.567)"), ("FIXED-1", "FIXED(1234.567, 1)"), ("FIXED-0", "FIXED(1234.567, 0)"),
    ("FIXED--2", "FIXED(1234.567, -2)"), ("FIXED-negnum", "FIXED(-1234.567, 2)"), ("FIXED-nocomma", "FIXED(1234.567, 2, TRUE())"),
    ("FIXED-half0", "FIXED(0.5, 0)"), ("FIXED-half1", "FIXED(1.5, 0)"), ("FIXED-half2", "FIXED(2.5, 0)"), ("FIXED-halfneg", "FIXED(-2.5, 0)"),
    ("FIXED-blank", "FIXED(BLANK())"), ("FIXED-text", 'FIXED("12.3", 1)'), ("FIXED-big", "FIXED(1E+15, 2)"),
    ("FIXED-128", "FIXED(1.5, 128)"), ("FIXED-neg5", "FIXED(123456, -5)"), ("FIXED-neg7", "FIXED(123456, -7)"),
    ("FIXED-frac", "FIXED(1.23456, 2.9)"), ("FIXED-false", "FIXED(1234.5, 1, FALSE())"), ("FIXED-small", "FIXED(0.000123, 5)"),
    ("FIXED-0n", "FIXED(0, 2)"), ("FIXED-negsmall", "FIXED(-0.001, 2)"), ("FIXED-blankdec", "FIXED(1.25, BLANK())"),
    ("COMBINE-ab", 'COMBINEVALUES("|", "a", "b")'), ("COMBINE-blank", 'COMBINEVALUES("|", "a", BLANK())'),
    ("COMBINE-nums", 'COMBINEVALUES("|", 1, 2.5)'),
    ("COMBINE-three", 'COMBINEVALUES("|", "a", "b", "c")'), ("COMBINE-bool", 'COMBINEVALUES(", ", TRUE(), "x")'),
    ("COMBINE-bb", 'COMBINEVALUES("|", BLANK(), BLANK())'), ("COMBINE-date", 'COMBINEVALUES("|", DATE(2026, 1, 2), 1)'),
]

# Lỗi lúc dịch (Desktop từ chối cả biểu thức, ISERROR không bắt được): quan sát riêng trong DAX query view.
STATIC = [
    ("COMBINE-emptydelim", 'COMBINEVALUES("", "a", "b")'),
    ("COMBINE-blankdelim", 'COMBINEVALUES(BLANK(), "a", "b")'), ("COMBINE-numdelim", 'COMBINEVALUES(0, "a", "b")'),
]


# Bảng tính toán lưu chuỗi theo từ điển không phân biệt hoa thường ("ABC" và "abc" thành một giá trị, giữ cách viết gặp
# trước), nên R mang tiền tố riêng từng dòng (tên ca, thêm "#ID" ở bảng cột) để không hai giá trị nào trùng nhau.
def lit_table(rows):
    parts = [f'ROW("Case", {q(c)}, "R", {q(c + "|")} & {enc(e)})' for c, e in rows]
    return "UNION(\n" + ",\n".join(parts) + "\n)"


def col_table(rows):
    parts = [f'SELECTCOLUMNS(text_cases, "Case", {q(c)}, "ID", [ID], "R", {q(c + "#")} & [ID] & "|" & {enc(e)})'
             for c, e in rows]
    return "UNION(\n" + ",\n".join(parts) + "\n)"


def write(name, text):
    with open(os.path.join(OUT, name), "wb") as f:
        f.write(b"\xff\xfe" + text.encode("utf-16-le"))


def main():
    os.makedirs(OUT, exist_ok=True)
    # Kết quả lấy từ bảng tính toán đã lưu (đọc .pbix), không từ lưới DAX query view: lưới báo
    # "Unable to translate Unicode character \uD83D …" khi kết quả có surrogate lẻ (MID cắt giữa emoji).
    tables = {"HCol": col_table(COL), "HLit1": lit_table(LIT1), "HLit2": lit_table(LIT2), "HLit3": lit_table(LIT3)}
    for name, text in tables.items():
        assert text.isascii(), name
        write(name.lower() + ".dax", name + " = " + text)
    names = [c for c, _ in COL + LIT1 + LIT2 + LIT3]
    assert len({n.lower() for n in names}) == len(names), "trùng tên ca (không phân biệt hoa thường)"
    with open(os.path.join(OUT, "cases.tsv"), "w", encoding="utf-8") as f:
        f.write("Case\tExpr\tTable\n")
        for table, rows in (("HCol", COL), ("HLit1", LIT1), ("HLit2", LIT2), ("HLit3", LIT3)):
            for c, e in rows:
                f.write(f"{c}\t{e}\t{table}\n")
    print({k: len(v) for k, v in tables.items()}, len(names), "ca")


if __name__ == "__main__":
    main()
