#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Sinh gói oracle DAX (golden) cho Nhóm 6, để người dùng chạy trong DAX Query View.

Đầu vào:  docs/phase-b-oracle/measures-119.tsv
          (có header: tier, kind, table, measure, expression; phân cách bằng tab)
Đầu ra:   docs/phase-b-oracle/queries/<nhóm>__<phần>.dax   (4 nhóm x 4 phần = 16 file)
          docs/phase-b-oracle/manifest.template.tsv

Cách chạy:
  python3 scripts/oracle/gen-oracle-pack.py
      Sinh lại gói, tự kiểm tra, in thống kê. Chạy lại cho cùng kết quả (idempotent).
  python3 scripts/oracle/gen-oracle-pack.py --check FILE.dax [FILE.dax ...]
      Chỉ kiểm cân bằng ngoặc của các file .dax bất kỳ (ví dụ thư mục observe/).

Chỉ dùng thư viện chuẩn của Python 3. Không đọc và không ghi ngoài thư mục docs/phase-b-oracle/.
"""
import argparse
import collections
import hashlib
import os
import re
import sys

EXPECTED_MEASURES = 119
TIERS = {"T0", "T1", "T2", "TXT"}
KINDS = {"D", "dep"}
HEADER = ["tier", "kind", "table", "measure", "expression"]
MANIFEST_HEADER = ["file", "sha1_dax", "ngày", "phiên bản Power BI (Help → About)",
                   "Windows regional format", "số dòng", "ghi chú lỗi"]
PROBE_SUFFIX = " · ISBLANK"
PARTS = ["FT", "LN", "CR", "DIM"]
PART_OF_TABLE = {"Fact_Transaction": "FT", "Fact_Loan": "LN", "Fact_CRM_Complaint": "CR"}

# (tên nhóm, cột nhóm-theo hoặc None cho ROW, filter cấp report, ORDER BY)
GROUPS = [
    ("G0-total", None, [], None),
    ("G1-year", "'Dim_Date'[year]", [], "'Dim_Date'[year]"),
    ("G2-region", "'Dim_Client'[client_region]", [], "'Dim_Client'[client_region]"),
    ("G3-rf-year", "'Dim_Date'[year]", [
        "KEEPFILTERS ( FILTER ( ALL ( 'Dim_Date'[year] ), NOT ( 'Dim_Date'[year] IN { 9999 } ) ) )",
        "KEEPFILTERS ( FILTER ( ALL ( 'Dim_Client'[client_region] ), "
        "NOT ( 'Dim_Client'[client_region] IN { \"Unknown\" } ) ) )",
    ], "'Dim_Date'[year]"),
]

GENERATED_NAME = re.compile(r"^G\d-[a-z-]+__(FT|LN|CR|DIM)\.dax$")
REF_RE = re.compile(r"^'((?:[^']|'')*)'\[((?:[^\]]|\]\])*)\]$")
MEASURE_LINE = re.compile(r"^\t\"((?:[^\"]|\"\")*)\", ('(?:[^']|'')*'\[(?:[^\]]|\]\])*\])(,?)$")
PROBE_LINE = re.compile(r"^\t\"((?:[^\"]|\"\")*)\", ISBLANK \( ('(?:[^']|'')*'\[(?:[^\]]|\]\])*\]) \)(,?)$")


def part_of(table):
    if table in PART_OF_TABLE:
        return PART_OF_TABLE[table]
    if table.startswith("Dim_"):
        return "DIM"
    raise ValueError("bảng không thuộc FT/LN/CR/DIM: " + table)


def quote_table(name):
    return "'" + name.replace("'", "''") + "'"


def measure_ref(table, measure):
    return quote_table(table) + "[" + measure.replace("]", "]]") + "]"


def quote_alias(text):
    return '"' + text.replace('"', '""') + '"'


def unquote_alias(text):
    return text.replace('""', '"')


def read_measures(path):
    """Đọc TSV, kiểm header và từng dòng. Trả về danh sách dict theo đúng thứ tự file."""
    with open(path, encoding="utf-8", newline="") as f:
        text = f.read()
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    lines = [ln[:-1] if ln.endswith("\r") else ln for ln in lines]
    if not lines or lines[0].split("\t") != HEADER:
        raise SystemExit("LỖI: header TSV phải là: " + "\\t".join(HEADER))
    rows = []
    for no, line in enumerate(lines[1:], start=2):
        fields = line.split("\t", 4)
        if len(fields) != 5:
            raise SystemExit("LỖI dòng %d: có %d cột, cần 5" % (no, len(fields)))
        tier, kind, table, measure, expression = fields
        if tier not in TIERS:
            raise SystemExit("LỖI dòng %d: tier lạ '%s'" % (no, tier))
        if kind not in KINDS:
            raise SystemExit("LỖI dòng %d: kind lạ '%s'" % (no, kind))
        if not table or not measure or not expression.strip():
            raise SystemExit("LỖI dòng %d: thiếu table, measure hoặc expression" % no)
        rows.append({"tier": tier, "kind": kind, "table": table,
                     "measure": measure, "expression": expression})
    validate_measures(rows)
    return rows


def validate_measures(rows):
    if len(rows) != EXPECTED_MEASURES:
        raise SystemExit("LỖI: có %d measure, cần %d" % (len(rows), EXPECTED_MEASURES))
    keys = [(r["table"], r["measure"]) for r in rows]
    dups = [k for k, c in collections.Counter(keys).items() if c > 1]
    if dups:
        raise SystemExit("LỖI: trùng (bảng, measure): " + repr(dups[:5]))
    aliases = [r["measure"] for r in rows] + [r["measure"] + PROBE_SUFFIX for r in rows]
    alias_dups = [a for a, c in collections.Counter(aliases).items() if c > 1]
    if alias_dups:
        raise SystemExit("LỖI: alias trùng nhau: " + repr(alias_dups[:5]))
    for r in rows:
        part_of(r["table"])  # ném lỗi nếu bảng lạ


def build_query(group_name, group_col, filters, order, measures, part):
    items = []
    for m in measures:
        ref = measure_ref(m["table"], m["measure"])
        items.append("\t" + quote_alias(m["measure"]) + ", " + ref)
        items.append("\t" + quote_alias(m["measure"] + PROBE_SUFFIX) + ", ISBLANK ( " + ref + " )")
    fname = "%s__%s.dax" % (group_name, part)
    header = ("// %s | %d measure, mỗi measure kèm 1 cột ISBLANK | "
              "Chạy, Copy kết quả, dán vào %s__%s.tsv\n") % (fname, len(measures), group_name, part)
    if group_col is None:
        body = "EVALUATE\nROW (\n" + ",\n".join(items) + "\n)\n"
    else:
        head = ["\t" + group_col] + ["\t" + f for f in filters]
        body = ("EVALUATE\nSUMMARIZECOLUMNS (\n" + ",\n".join(head + items) +
                "\n)\nORDER BY " + order + "\n")
    return header + body


def build_all(measures):
    """Trả về {tên file: nội dung} cho cả 16 file."""
    out = collections.OrderedDict()
    for group_name, group_col, filters, order in GROUPS:
        for part in PARTS:
            part_measures = [m for m in measures if part_of(m["table"]) == part]
            if not part_measures:
                raise SystemExit("LỖI: phần %s trống" % part)
            fname = "%s__%s.dax" % (group_name, part)
            out[fname] = build_query(group_name, group_col, filters, order, part_measures, part)
    return out


def parse_ref(ref):
    m = REF_RE.match(ref)
    if not m:
        raise ValueError("tham chiếu không đúng dạng: " + ref)
    return m.group(1).replace("''", "'"), m.group(2).replace("]]", "]")


def verify_outputs(files, measures):
    """Đọc lại file đã sinh. Mỗi measure phải xuất hiện đúng một lần trong mỗi nhóm, kèm cột ISBLANK."""
    expected = set((m["table"], m["measure"]) for m in measures)
    for group_name, _, _, _ in GROUPS:
        seen = collections.Counter()
        for part in PARTS:
            fname = "%s__%s.dax" % (group_name, part)
            lines = files[fname].split("\n")
            for i, line in enumerate(lines):
                mm = MEASURE_LINE.match(line)
                if not mm:
                    continue
                alias = unquote_alias(mm.group(1))
                table, measure = parse_ref(mm.group(2))
                assert alias == measure, "%s: alias khác tên measure: %s" % (fname, alias)
                assert part_of(table) == part, "%s: measure %s nằm sai phần" % (fname, measure)
                pm = PROBE_LINE.match(lines[i + 1]) if i + 1 < len(lines) else None
                assert pm is not None, "%s: thiếu cột ISBLANK sau %s" % (fname, measure)
                assert unquote_alias(pm.group(1)) == measure + PROBE_SUFFIX, \
                    "%s: cột ISBLANK sai alias sau %s" % (fname, measure)
                assert pm.group(2) == mm.group(2), "%s: cột ISBLANK trỏ sai measure" % fname
                seen[(table, measure)] += 1
        counts = set(seen.values())
        assert set(seen.keys()) == expected, "%s: thiếu hoặc thừa measure" % group_name
        assert counts == {1}, "%s: có measure xuất hiện không đúng 1 lần" % group_name
        assert sum(seen.values()) == EXPECTED_MEASURES


def scan_balance(text):
    """Kiểm ( ) { } cân bằng, bỏ qua chuỗi "...", tên bảng '...', [...] và comment.
    Trả về None nếu ổn, hoặc chuỗi mô tả lỗi kèm số dòng."""
    closers = {")": "(", "}": "{"}
    stack = []
    i, n, line = 0, len(text), 1
    while i < n:
        c = text[i]
        if c == "\n":
            line += 1
            i += 1
            continue
        if text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j == -1 else j
            continue
        if text.startswith("/*", i):
            j = text.find("*/", i + 2)
            if j == -1:
                return "dòng %d: comment /* chưa đóng" % line
            line += text.count("\n", i, j)
            i = j + 2
            continue
        if c in ('"', "'"):
            k = i + 1
            while True:
                k = text.find(c, k)
                if k == -1:
                    return "dòng %d: %s chưa đóng" % (line, c)
                if text.startswith(c * 2, k):
                    k += 2
                    continue
                break
            line += text.count("\n", i, k)
            i = k + 1
            continue
        if c == "[":
            k = i + 1
            while True:
                k = text.find("]", k)
                if k == -1:
                    return "dòng %d: [ chưa đóng" % line
                if text.startswith("]]", k):
                    k += 2
                    continue
                break
            i = k + 1
            continue
        if c in "({":
            stack.append((c, line))
        elif c in ")}":
            if not stack or stack[-1][0] != closers[c]:
                return "dòng %d: '%s' thừa hoặc không khớp" % (line, c)
            stack.pop()
        i += 1
    if stack:
        return "dòng %d: '%s' chưa đóng" % (stack[-1][1], stack[-1][0])
    return None


def run_check(paths):
    bad = 0
    for p in paths:
        with open(p, encoding="utf-8") as f:
            msg = scan_balance(f.read())
        if msg is None:
            print("OK    " + p)
        else:
            bad += 1
            print("LỖI   %s: %s" % (p, msg))
    return 1 if bad else 0


def main(argv):
    ap = argparse.ArgumentParser(description="Sinh gói oracle DAX cho Nhóm 6")
    ap.add_argument("--check", nargs="+", metavar="FILE.dax",
                    help="chỉ kiểm cân bằng ngoặc của các file đã cho")
    args = ap.parse_args(argv)
    if args.check:
        return run_check(args.check)

    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    base = os.path.join(root, "docs", "phase-b-oracle")
    src = os.path.join(base, "measures-119.tsv")
    qdir = os.path.join(base, "queries")
    manifest = os.path.join(base, "manifest.template.tsv")

    measures = read_measures(src)
    files = build_all(measures)

    # Kiểm: đúng một lần mỗi measure trong mỗi nhóm, cân bằng ngoặc, số dòng dưới 100.
    verify_outputs(files, measures)
    for fname, content in files.items():
        msg = scan_balance(content)
        assert msg is None, "%s: %s" % (fname, msg)
        assert content.count("\n") < 100, "%s: quá 100 dòng" % fname

    os.makedirs(qdir, exist_ok=True)
    for stale in sorted(os.listdir(qdir)):
        if GENERATED_NAME.match(stale) and stale not in files:
            os.remove(os.path.join(qdir, stale))
    for fname, content in files.items():
        with open(os.path.join(qdir, fname), "w", encoding="utf-8", newline="\n") as f:
            f.write(content)

    rows = [MANIFEST_HEADER]
    for fname in files:
        with open(os.path.join(qdir, fname), "rb") as f:
            sha = hashlib.sha1(f.read()).hexdigest()
        rows.append([fname, sha] + [""] * 5)
    with open(manifest, "w", encoding="utf-8", newline="\n") as f:
        for r in rows:
            f.write("\t".join(r) + "\n")

    print("%-22s %8s %6s %6s" % ("file", "measure", "cột", "dòng"))
    for fname, content in files.items():
        nmeas = sum(1 for ln in content.split("\n") if MEASURE_LINE.match(ln))
        group_cols = 0 if fname.startswith("G0-") else 1  # ROW không có cột nhóm-theo
        print("%-22s %8d %6d %6d" % (fname, nmeas, nmeas * 2 + group_cols, content.count("\n")))
    print("tổng: %d file, mỗi nhóm %d measure (kiểm tra OK), manifest: %s" %
          (len(files), EXPECTED_MEASURES, manifest))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
