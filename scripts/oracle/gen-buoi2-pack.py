#!/usr/bin/env python3
"""Sinh gói truy vấn buổi 2 (Phase B): G4, G5, G6a–f và bộ ca nhỏ T1–T4 trên Nhom6.

Dùng: python3 scripts/oracle/gen-buoi2-pack.py
Đầu ra: docs/phase-b-oracle/queries-buoi2/*.dax và docs/phase-b-oracle/manifest-buoi2.template.tsv.
G2-region đã có trong docs/phase-b-oracle/queries/ (sinh từ gen-oracle-pack.py).

Quy ước giống buổi 1 (gen-oracle-pack.py):
  - Cột kết quả của measure có alias = tên measure; ngay sau là cột thăm dò "<tên> · ISBLANK".
  - Truy vấn nhiều dòng luôn có ORDER BY để so theo thứ tự dòng.
  - Mỗi file chỉ một EVALUATE (O5: một EVALUATE lỗi thì không có kết quả nào).
Idempotent: chạy lại cho cùng nội dung và cùng sha1.
"""
import hashlib
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "docs", "phase-b-oracle", "queries-buoi2")
MANIFEST = os.path.join(ROOT, "docs", "phase-b-oracle", "manifest-buoi2.template.tsv")
PROBE = " · ISBLANK"


def alias(name):
    return '"' + name.replace('"', '""') + '"'


def mref(table, name):
    return "'" + table.replace("'", "''") + "'[" + name.replace("]", "]]") + "]"


def measure_args(pairs):
    """pairs: [(nhãn, biểu thức DAX)] → các dòng "nhãn", expr, "nhãn · ISBLANK", ISBLANK(expr)."""
    lines = []
    for label, expr in pairs:
        lines.append(f"\t{alias(label)}, {expr}")
        lines.append(f"\t{alias(label + PROBE)}, ISBLANK ( {expr} )")
    return lines


def summarize(group_cols, pairs, filters=(), defines=(), order=None):
    head = ""
    if defines:
        head = "DEFINE\n" + "\n".join(f"\t{d}" for d in defines) + "\n"
    args = [f"\t{c}" for c in group_cols] + [f"\t{f}" for f in filters] + measure_args(pairs)
    order_by = order if order is not None else group_cols
    tail = ("\nORDER BY " + ", ".join(order_by)) if order_by else ""
    return head + "EVALUATE\nSUMMARIZECOLUMNS (\n" + ",\n".join(args) + "\n)" + tail + "\n"


def row(pairs, defines=()):
    head = ""
    if defines:
        head = "DEFINE\n" + "\n".join(f"\t{d}" for d in defines) + "\n"
    return head + "EVALUATE\nROW (\n" + ",\n".join(measure_args(pairs)) + "\n)\n"


FT, LN, CR, DD = "Fact_Transaction", "Fact_Loan", "Fact_CRM_Complaint", "Dim_District"
YEAR = "'Dim_Date'[year]"
REL_SENT = "USERELATIONSHIP ( 'Fact_CRM_Complaint'[sent_date_key], 'Dim_Date'[date_key] )"

QUERIES = {}

# G4: quan hệ inactive (sent_date_key). So số theo ngày nhận (quan hệ active) với số theo ngày gửi.
g4_base = ["Complaints", "Avg_Days_To_Company", "Dispute_Rate", "SLA_Timely_Rate"]
g4_defines = [f"MEASURE 'Fact_CRM_Complaint'[{m} (gửi)] = CALCULATE ( {mref(CR, m)}, {REL_SENT} )" for m in g4_base]
g4_pairs = []
for m in g4_base:
    g4_pairs.append((m, mref(CR, m)))
    g4_pairs.append((f"{m} (gửi)", mref(CR, f"{m} (gửi)")))
QUERIES["G4-inactive"] = ("Quan hệ inactive sent_date_key qua USERELATIONSHIP, theo năm",
                          summarize([YEAR], g4_pairs, defines=g4_defines))

# G5: theo tháng (HASONEVALUE, cửa sổ MonthIndex của Complaints MA3 và Neg Trans PM).
QUERIES["G5-month"] = ("Theo tháng: MonthIndex và year_month", summarize(
    ["'Dim_Date'[MonthIndex]", "'Dim_Date'[year_month]"],
    [("Complaints", mref(CR, "Complaints")), ("Complaints MA3", mref(CR, "Complaints MA3")),
     ("Trans Count", mref(FT, "Trans Count")), ("Neg Balance Trans", mref(FT, "Neg Balance Trans")),
     ("Neg Trans PM", mref(FT, "Neg Trans PM")), ("Loan Amount", mref(LN, "Loan Amount"))]))

# G6: ngữ cảnh kiểu visual.
QUERIES["G6a-issue-pareto"] = ("Pareto theo vấn đề khiếu nại", summarize(
    ["'Dim_CRM_Issue'[issue]"],
    [("Complaints", mref(CR, "Complaints")), ("Pareto Cum %", mref(CR, "Pareto Cum %")),
     ("Pareto Color", mref(CR, "Pareto Color")), ("Pareto 80% Line", mref(CR, "Pareto 80% Line"))]))
QUERIES["G6b-channel"] = ("Tỷ trọng theo kênh gửi", summarize(
    ["'Dim_CRM_Channel_Response'[submitted_via]"],
    [("Complaints", mref(CR, "Complaints")), ("Channel Share %", mref(CR, "Channel Share %"))]))
QUERIES["G6c-channel-response"] = ("Tỷ trọng phản hồi trong từng kênh", summarize(
    ["'Dim_CRM_Channel_Response'[submitted_via]", "'Dim_CRM_Channel_Response'[company_response]"],
    [("Complaints", mref(CR, "Complaints")),
     ("Response Share in Channel %", mref(CR, "Response Share in Channel %"))]))
QUERIES["G6d-trans-type"] = ("Tỷ trọng số tiền theo loại giao dịch", summarize(
    ["'Dim_Trans_Type'[trans_type]", "'Dim_Trans_Type'[operation]"],
    [("Trans Amount", mref(FT, "Trans Amount")), ("% Trans Amount", mref(FT, "% Trans Amount"))]))
QUERIES["G6e-heatmap"] = ("Heatmap giờ × thứ", summarize(
    ["'Fact_Transaction'[trans_hour]", "'Dim_Date'[day_name]"],
    [("Trans Count (k)", mref(FT, "Trans Count (k)")), ("Peak Hour Font Color", mref(FT, "Peak Hour Font Color")),
     ("Peak Hour Top10 Icon", mref(FT, "Peak Hour Top10 Icon"))]))
d4 = ["D4 Trans Count", "D4 Trans Amount", "D4 Active Accounts", "D4 Overdraft Rate", "D4 Complaints",
      "D4 SLA_Timely_Rate", "D4 Dispute_Rate", "D4 Avg_Days_To_Company", "D4 Timely Color"]
branch = [("NPL Avg (Selected)", mref(LN, "NPL Avg (Selected)")), ("Branch NPL Color", mref(LN, "Branch NPL Color")),
          ("Branch NPL Label", mref(DD, "Branch NPL Label")), ("Branch Title", mref(DD, "Branch Title")),
          ("Branch Subtitle", mref(DD, "Branch Subtitle")), ("Top Branches Text", mref(LN, "Top Branches Text"))]
QUERIES["G6f1-district"] = ("Trang D4 theo thành phố và bang (Dim_District)", summarize(
    ["'Dim_District'[city]", "'Dim_District'[state_name]"], [(m, mref(DD, m)) for m in d4] + branch))
QUERIES["G6f2-account-branch"] = ("Trang D4 theo chi nhánh của tài khoản (Dim_Account)", summarize(
    ["'Dim_Account'[branch_city]"], [(m, mref(DD, m)) for m in d4] + branch))

# T1–T4: bộ ca nhỏ trên Nhom6 (thay cho mô hình tí hon riêng). Mỗi ca một cột.
QUERIES["T1-blank-arith"] = ("BLANK, chia 0, ép kiểu và hàm toán", row([
    ("blank+5", "BLANK () + 5"), ("blank-5", "BLANK () - 5"), ("blank*5", "BLANK () * 5"),
    ("blank/5", "BLANK () / 5"), ("5/blank", "5 / BLANK ()"), ("0/blank", "0 / BLANK ()"),
    ("blank/blank", "BLANK () / BLANK ()"), ("blank&x", 'BLANK () & "x"'), ("blank=0", "BLANK () = 0"),
    ("blank=empty", 'BLANK () = ""'), ("isblank(0)", "ISBLANK ( 0 )"), ("blank&&true", "BLANK () && TRUE ()"),
    ("blank||true", "BLANK () || TRUE ()"), ("divide(1,0)", "DIVIDE ( 1, 0 )"), ("divide(1,0,-1)", "DIVIDE ( 1, 0, -1 )"),
    ("int(-2.5)", "INT ( -2.5 )"), ("mod(-7,3)", "MOD ( -7, 3 )"), ("mod(7,-3)", "MOD ( 7, -3 )"),
    ("round(2.675,2)", "ROUND ( 2.675, 2 )"), ("date(2018,13,1)", "DATE ( 2018, 13, 1 )"),
    ("\"1\"+1", '"1" + 1')]))
QUERIES["T2-time-edges"] = ("SAMEPERIODLASTYEAR và DATEADD ở cuối tháng và năm nhuận", row([
    (f"{label} {fn}", f"{fn}X ( {expr}, 'Dim_Date'[full_date] )" if fn in ("MIN", "MAX") else f"COUNTROWS ( {expr} )")
    for label, expr in [
        ("spl(01-29/02/2016)", "SAMEPERIODLASTYEAR ( FILTER ( VALUES ( 'Dim_Date'[full_date] ), 'Dim_Date'[full_date] >= DATE ( 2016, 2, 1 ) && 'Dim_Date'[full_date] <= DATE ( 2016, 2, 29 ) ) )"),
        ("spl(01-28/02/2017)", "SAMEPERIODLASTYEAR ( FILTER ( VALUES ( 'Dim_Date'[full_date] ), 'Dim_Date'[full_date] >= DATE ( 2017, 2, 1 ) && 'Dim_Date'[full_date] <= DATE ( 2017, 2, 28 ) ) )"),
        ("spl(28/02/2017)", "SAMEPERIODLASTYEAR ( FILTER ( VALUES ( 'Dim_Date'[full_date] ), 'Dim_Date'[full_date] = DATE ( 2017, 2, 28 ) ) )"),
        ("dateadd(31/01/2017,+1M)", "DATEADD ( FILTER ( VALUES ( 'Dim_Date'[full_date] ), 'Dim_Date'[full_date] = DATE ( 2017, 1, 31 ) ), 1, MONTH )"),
        ("dateadd(30/04/2017,-1M)", "DATEADD ( FILTER ( VALUES ( 'Dim_Date'[full_date] ), 'Dim_Date'[full_date] = DATE ( 2017, 4, 30 ) ), -1, MONTH )"),
        ("dateadd(15/03/2017,-1Q)", "DATEADD ( FILTER ( VALUES ( 'Dim_Date'[full_date] ), 'Dim_Date'[full_date] = DATE ( 2017, 3, 15 ) ), -1, QUARTER )"),
    ]
    for fn in ("COUNT", "MIN", "MAX")]))
QUERIES["T3-context"] = ("ALLSELECTED, ISFILTERED, HASONEVALUE, SELECTEDVALUE dưới bộ lọc năm {2016, 2017}", summarize(
    [YEAR],
    [("Trans Count", mref(FT, "Trans Count")),
     ("allselected", f"CALCULATE ( {mref(FT, 'Trans Count')}, ALLSELECTED ( 'Dim_Date'[year] ) )"),
     ("all", f"CALCULATE ( {mref(FT, 'Trans Count')}, ALL ( 'Dim_Date'[year] ) )"),
     ("isfiltered year", "ISFILTERED ( 'Dim_Date'[year] )"),
     ("isfiltered month", "ISFILTERED ( 'Dim_Date'[month_num] )"),
     ("hasonevalue year", "HASONEVALUE ( 'Dim_Date'[year] )"),
     ("selectedvalue year", "SELECTEDVALUE ( 'Dim_Date'[year], -1 )"),
     ("keepfilters 2017", f"CALCULATE ( {mref(FT, 'Trans Count')}, KEEPFILTERS ( 'Dim_Date'[year] = 2017 ) )"),
     ("override 2017", f"CALCULATE ( {mref(FT, 'Trans Count')}, 'Dim_Date'[year] = 2017 )")],
    filters=["TREATAS ( { 2016, 2017 }, 'Dim_Date'[year] )"]))
QUERIES["T4-count-empty"] = ("Đếm trên tập rỗng và DISTINCTCOUNT có BLANK", row([
    ("countrows(empty)", "COUNTROWS ( FILTER ( 'Dim_Date', FALSE () ) )"),
    ("distinctcount 2011", f"CALCULATE ( DISTINCTCOUNT ( 'Fact_Transaction'[account_key] ), 'Dim_Date'[year] = 2011 )"),
    ("count 2011", "CALCULATE ( COUNT ( 'Fact_Transaction'[amount] ), 'Dim_Date'[year] = 2011 )"),
    ("countrows 2011", "CALCULATE ( COUNTROWS ( 'Fact_Transaction' ), 'Dim_Date'[year] = 2011 )"),
    ("sum 2011", "CALCULATE ( SUM ( 'Fact_Transaction'[amount] ), 'Dim_Date'[year] = 2011 )"),
    ("distinctcount client_region", "DISTINCTCOUNT ( 'Dim_Client'[client_region] )"),
    ("countrows Dim_Client", "COUNTROWS ( 'Dim_Client' )")]))


def main():
    os.makedirs(OUT, exist_ok=True)
    manifest = [["file", "sha1_dax", "ngày", "phiên bản Power BI (Help → About)", "Windows regional format",
                 "số dòng", "ghi chú lỗi"]]
    for name, (title, body) in QUERIES.items():
        text = f"// {name} | {title}. Chạy, Copy kết quả, dán vào {name}.tsv\n" + body
        path = os.path.join(OUT, name + ".dax")
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        manifest.append([name + ".dax", hashlib.sha1(text.encode("utf-8")).hexdigest(), "", "", "", "", ""])
        print(f"{name}.dax  {text.count(chr(10))} dòng")
    for part in ("FT", "LN", "CR", "DIM"):
        path = os.path.join(ROOT, "docs", "phase-b-oracle", "queries", f"G2-region__{part}.dax")
        sha = hashlib.sha1(open(path, encoding="utf-8").read().encode("utf-8")).hexdigest()
        manifest.append([f"G2-region__{part}.dax", sha, "", "", "", "", ""])
    with open(MANIFEST, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join("\t".join(r) for r in manifest) + "\n")
    print(f"tổng: {len(QUERIES)} file mới + 4 file G2; manifest: {MANIFEST}")


if __name__ == "__main__":
    main()
