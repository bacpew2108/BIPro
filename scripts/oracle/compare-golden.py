#!/usr/bin/env python3
"""So khớp kết quả engine (dax-run query, ô dạng KIỂU:giá-trị) với golden copy từ Power BI Desktop.

Dùng: compare-golden.py <golden-dir> <engine-dir> [tên ...]
  - golden-dir: các file <tên>.tsv copy từ DAX Query View (định dạng quan sát ở O2).
  - engine-dir: các file <tên>.engine.tsv (hoặc <tên>.engine.error.txt) của dax-run query.
  - Không ghi tên thì so mọi <tên>.tsv có trong golden-dir (trừ manifest.tsv).

Quy tắc (docs/PHASE_B_PLAN.md §5.3, định dạng Copy theo O2):
  - Golden: dòng đầu là tên cột (cột measure trong ngoặc vuông), xuống dòng CRLF, số dùng ".", không phân nhóm.
  - BLANK và chuỗi rỗng đều là ô rỗng trong golden; phân biệt bằng cột thăm dò "<tên> · ISBLANK".
  - Số nguyên khớp tuyệt đối; số thực sai số tương đối 1e-9; currency so tới 4 chữ số thập phân.
  - Ngày dạng "Mon, 31 Dec 2018 16:03:36", sai lệch tối đa 3,34 ms. Boolean "true"/"false" (không phân biệt hoa thường).
  - "Infinity", "-Infinity", "NaN" theo O1/O2. Chuỗi so nguyên văn sau khi chuẩn hoá CRLF.
  - Cột so theo tên; dòng so theo thứ tự (các truy vấn golden đều có ORDER BY hoặc một dòng).
Thoát 0 khi mọi ô khớp, 1 khi có lệch, 2 khi lỗi cách dùng.
"""
import math
import os
import sys
from datetime import datetime

OLE_EPOCH = datetime(1899, 12, 30)
PROBE = " · ISBLANK"


def read_golden(path):
    text = open(path, encoding="utf-8-sig").read().replace("\r\n", "\n").rstrip("\n")
    lines = text.split("\n")
    header = lines[0].split("\t")
    rows = [line.split("\t") for line in lines[1:]]
    return header, rows


def unescape(text):
    out, i = [], 0
    while i < len(text):
        c = text[i]
        if c == "\\" and i + 1 < len(text):
            out.append({"t": "\t", "n": "\n", "r": "\r", "\\": "\\"}.get(text[i + 1], text[i + 1]))
            i += 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


def read_engine(path):
    lines = open(path, encoding="utf-8").read().rstrip("\n").split("\n")
    lines = [l for l in lines if not l.startswith("#RESULT")]
    header = [unescape(h) for h in lines[0].split("\t")]
    rows = []
    for line in lines[1:]:
        cells = []
        for cell in line.split("\t"):
            kind, _, value = cell.partition(":")
            cells.append((kind, unescape(value) if kind == "STR" else value))
        rows.append(cells)
    return header, rows


def golden_number(text):
    if text == "Infinity":
        return math.inf
    if text == "-Infinity":
        return -math.inf
    if text == "NaN":
        return math.nan
    return float(text)


def golden_date(text):
    return (datetime.strptime(text, "%a, %d %b %Y %H:%M:%S") - OLE_EPOCH).total_seconds() / 86400.0


def same_float(a, b):
    if math.isnan(a) or math.isnan(b):
        return math.isnan(a) and math.isnan(b)
    if math.isinf(a) or math.isinf(b):
        return a == b
    return abs(a - b) <= 1e-9 * max(1.0, abs(a), abs(b))


def compare_cell(golden, engine, golden_is_blank):
    """Trả None nếu khớp, hoặc chuỗi mô tả lệch."""
    kind, value = engine
    try:
        if kind == "BLANK":
            if golden != "":
                return f"engine BLANK, golden {golden!r}"
            if golden_is_blank is False:
                return "engine BLANK, golden là chuỗi rỗng (ISBLANK = false)"
            return None
        if golden == "" and golden_is_blank is True:
            return f"golden BLANK, engine {kind}:{value}"
        if kind == "STR":
            return None if golden == value.replace("\r\n", "\n") else f"chuỗi khác: golden {golden!r}, engine {value!r}"
        if kind == "BOOL":
            return None if golden.lower() == value else f"golden {golden!r}, engine {value}"
        if kind == "INT":
            g = golden_number(golden)
            return None if g == int(value) else f"golden {golden}, engine {value}"
        if kind == "DBL":
            return None if same_float(golden_number(golden), float(value)) else f"golden {golden}, engine {value}"
        if kind == "CUR":
            g = golden_number(golden)
            return None if round(g * 10000) == int(value) else f"golden {golden}, engine {int(value) / 10000}"
        if kind == "DT":
            return None if abs(golden_date(golden) - float(value)) * 86400000 <= 3.34 else f"golden {golden}, engine {value}"
    except ValueError as error:
        return f"không đọc được golden {golden!r} cho kiểu {kind}: {error}"
    return f"kiểu engine lạ {kind}"


def compare(name, golden_dir, engine_dir):
    golden_path = os.path.join(golden_dir, name + ".tsv")
    engine_path = os.path.join(engine_dir, name + ".engine.tsv")
    error_path = os.path.join(engine_dir, name + ".engine.error.txt")
    if not os.path.exists(engine_path):
        reason = open(error_path, encoding="utf-8").read().strip() if os.path.exists(error_path) else "không có kết quả"
        return {"name": name, "status": "ENGINE_ERROR", "detail": reason, "mismatches": []}
    g_header, g_rows = read_golden(golden_path)
    e_header, e_rows = read_engine(engine_path)
    mismatches = []
    missing = [h for h in g_header if h not in e_header]
    if missing:
        mismatches.append(("(cột)", "-", f"engine thiếu cột: {missing}"))
    if len(g_rows) != len(e_rows):
        mismatches.append(("(dòng)", "-", f"số dòng golden {len(g_rows)}, engine {len(e_rows)}"))
    e_index = {h: i for i, h in enumerate(e_header)}
    for r, g_row in enumerate(g_rows[: len(e_rows)]):
        e_row = e_rows[r]
        for c, column in enumerate(g_header):
            if column not in e_index or column.endswith(PROBE + "]"):
                continue
            probe_name = column[:-1] + PROBE + "]" if column.endswith("]") else None
            blank = None
            if probe_name in g_header:
                probe = g_row[g_header.index(probe_name)].lower()
                blank = True if probe == "true" else False if probe == "false" else None
            problem = compare_cell(g_row[c], e_row[e_index[column]], blank)
            if problem:
                mismatches.append((column, r + 1, problem))
        # Cột thăm dò cũng phải khớp (engine tính ISBLANK như golden).
        for c, column in enumerate(g_header):
            if column.endswith(PROBE + "]") and column in e_index:
                problem = compare_cell(g_row[c], e_row[e_index[column]], None)
                if problem:
                    mismatches.append((column, r + 1, problem))
    return {"name": name, "status": "OK" if not mismatches else "DIFF", "detail": "", "mismatches": mismatches}


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    golden_dir, engine_dir = argv[0], argv[1]
    names = argv[2:] or sorted(f[:-4] for f in os.listdir(golden_dir) if f.endswith(".tsv") and f != "manifest.tsv")
    failed = 0
    measure_issues = {}
    for name in names:
        result = compare(name, golden_dir, engine_dir)
        if result["status"] == "ENGINE_ERROR":
            failed += 1
            print(f"ENGINE_ERROR  {name}: {result['detail']}")
            continue
        count = len(result["mismatches"])
        print(f"{result['status']:5s}  {name}: {count} ô lệch")
        if count:
            failed += 1
        for column, row, problem in result["mismatches"]:
            key = column.replace(PROBE, "")
            measure_issues.setdefault(key, []).append(f"{name} dòng {row}: {problem}")
    if measure_issues:
        print(f"\nmeasure có lệch: {len(measure_issues)}")
        for column in sorted(measure_issues):
            issues = measure_issues[column]
            print(f"  {column} ({len(issues)} ô)")
            for issue in issues[:3]:
                print(f"      {issue}")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
