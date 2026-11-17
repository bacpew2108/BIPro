#!/usr/bin/env python3
"""VM-F12 (T018): ghép kết quả Desktop đã lưu trong `f12-desktop.pbix` (bảng HCol, HLit1..3) với `cases.tsv` thành golden.

Chạy sau `swift build --product pbix-dump`:
  python3 scripts/f2-samples/vm_f12_golden.py build/f2-out/f12/f12-desktop.pbix docs/phase-f2-evidence/vm-f12/golden.tsv

golden.tsv (UTF-8, cột cách nhau bằng tab, giá trị đã thoát `\\\\`, `\\t`, `\\n`, `\\r`):
  Case, Table, ID (rỗng ở bảng HLit), Expr, Result
Result: "E" lỗi, "B" BLANK, "T:<chuỗi>", "L:<TRUE|FALSE>", "N:<số đổi sang chuỗi bằng &>". Surrogate lẻ ghi U+FFFD.
"""
import os
import subprocess
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")


def dump(pbix, table):
    exe = os.path.join(ROOT, ".build", "debug", "pbix-dump")
    out = subprocess.run([exe, "rows", pbix, table, "100000", "--escape"], check=True, capture_output=True, text=True).stdout
    lines = out.rstrip("\n").split("\n")
    header = lines[0].split("\t")
    return [dict(zip(header, line.split("\t"))) for line in lines[1:]]


def main():
    pbix, out = sys.argv[1], sys.argv[2]
    cases = {}
    with open(os.path.join(ROOT, "build", "f2-out", "f12", "cases.tsv"), encoding="utf-8") as f:
        next(f)
        for line in f:
            case, expr, table = line.rstrip("\n").split("\t")
            cases[case] = (expr, table)
    rows, seen = [], set()
    for table in ("HCol", "HLit1", "HLit2", "HLit3"):
        for r in dump(pbix, table):
            prefix, result = r["R"].split("|", 1)
            case = prefix.split("#")[0]
            assert case == r["Case"], (case, r["Case"])
            expr, expected_table = cases[case]
            assert expected_table == table, (case, table)
            rows.append((case, table, r.get("ID", ""), expr, result))
            seen.add(case)
    missing = set(cases) - seen
    assert not missing, f"thiếu ca: {sorted(missing)}"
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        f.write("Case\tTable\tID\tExpr\tResult\n")
        for row in rows:
            f.write("\t".join(row) + "\n")
    print(len(rows), "dòng,", len(seen), "ca →", out)


if __name__ == "__main__":
    main()
