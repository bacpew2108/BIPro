# Quan sát Power BI Desktop — VM-V11B: Tương tác, Matrix theo hàng, Định dạng có điều kiện, Analytics, Theme & DAX Oracle (2026-11-21)

**Môi trường:** Power BI Desktop 2.159 trên VM Windows 11 (Parallels), không suy đoán.
**Dữ liệu nguồn:** Bản sao chỉ-đọc `Nhom6_Dashboard_chiase.pbix` tại `C:\Temp\vm-v11b\obs.pbix` (đã đóng Power BI Desktop và xoá sạch sau buổi quan sát).
**Lược đồ PBIR (`$schema`):** `page/2.1.0`, `visualContainer/2.14.0`, `report/3.3.0`.
**Bằng chứng:**
- `dax-golden.json`: 21/21 truy vấn DAX golden chạy trực tiếp trên `msmdsrv` của Power BI Desktop 2.159 (`Microsoft.PowerBI.AdomdClient.dll`).
- `json/`: 18 tệp PBIR JSON nguyên văn (`b1-*`..`b4-*`).
- Ảnh cắt chỉ giữ vùng canvas (không chứa email tài khoản): `desktop-edit-interactions.png`, `desktop-matrix-rows-databars.png`.

---

## 1. Edit Interactions (`visualInteractions` trong `page.json`)

Khi bật **Format → Edit interactions** (`b1-d1.page.json`, `b2-d1.page.json`), Power BI Desktop hiển thị các biểu tượng nhỏ phía trên góc phải từng visual đích (`Filter`, `Highlight` nếu visual đích hỗ trợ highlight, và `None` ⊘), và ghi mảng `visualInteractions` ở cấp gốc của `page.json`:

```json
"visualInteractions": [
  {"source": "b1106ee1bf9281ad7b51", "target": "c36625920078b7e0c75a", "type": "NoFilter"},
  {"source": "b1106ee1bf9281ad7b51", "target": "bd7c2a2d8369e704295f", "type": "HighlightFilter"}
]
```

- Các giá trị `type` chuẩn PBIR:
  - `"NoFilter"` — Không tương tác (`None` ⊘).
  - `"HighlightFilter"` — Tô sáng chéo (`Highlight`).
  - `"DataFilter"` — Lọc chéo dữ liệu (`Filter`) *(khớp với trường `visualInteractions` đã đọc trong `PBIRPagePatch` và bảng quy tắc tương tác Power BI)*.
- Khi visual đích dùng hành vi mặc định (chưa sửa), Desktop không cần ghi mục trong `visualInteractions`; chỉ các cặp đã cấu hình mới được lưu.

---

## 2. Mở/đóng phân cấp hàng Matrix (`expansionStates` với `roles: ["Rows"]`)

Tạo `pivotTable` với 2 trường trong ô `Rows` (`Dim_Client.client_region`, `Dim_Client.age_group_current`) và 1 measure trong `Values` (`Dim_Client.Total_Clients`), bấm nút `+` bên cạnh `Midwest` (`b3-13521b0905b7e054e5a8-928f08c931d640590cd0.visual.json`):

```json
"expansionStates": [{
  "roles": ["Rows"],
  "levels": [
    {
      "queryRefs": ["Dim_Client.client_region"],
      "isCollapsed": true,
      "identityKeys": [{"Column": {"Expression": {"SourceRef": {"Entity": "Dim_Client"}}, "Property": "client_region"}}],
      "isPinned": true
    },
    {
      "queryRefs": ["Dim_Client.age_group_current"],
      "isCollapsed": true,
      "isPinned": true
    }
  ],
  "root": {
    "children": [
      {"identityValues": [{"Literal": {"Value": "'Midwest'"}}], "isToggled": true}
    ]
  }
}]
```

- Khi mở `Midwest`, các dòng con (`<25: 80`, `25-34: 79`, `35-49: 142`, `50-64: 138`, `65+: 107`) hiện ngay dưới dòng `Midwest (546)` thụt lề, các vùng khác (`Northeast`, `South`, `West`) vẫn đóng (`+`).
- Cấu trúc giống hệt `expansionStates` của slicer phân cấp (`roles: ["Values"]`), chỉ đổi `roles` thành `["Rows"]`.

---

## 3. Định dạng có điều kiện (Conditional Formatting) trên Matrix & Table

Quan sát trực tiếp từ `b3-13521b0905b7e054e5a8-928f08c931d640590cd0.visual.json` và mẫu `FillRule` có sẵn trong `Nhom6` (`2132ddc1caa56c2879e6/visual.json`):

1. **Data Bars — nằm trong `objects.columnFormatting` (KHÔNG phải `objects.values`!):**
   ```json
   "columnFormatting": [{
     "properties": {
       "dataBars": {
         "positiveColor": {"solid": {"color": {"expr": {"Literal": {"Value": "'maxColor'"}}}}},
         "negativeColor": {"solid": {"color": {"expr": {"Literal": {"Value": "'minColor'"}}}}},
         "axisColor": {"solid": {"color": {"expr": {"Literal": {"Value": "'foreground'"}}}}},
         "reverseDirection": {"expr": {"Literal": {"Value": "false"}}},
         "hideText": {"expr": {"Literal": {"Value": "false"}}},
         "totalMatchingOption": {"expr": {"Literal": {"Value": "1L"}}}
       }
     },
     "selector": {"metadata": "Dim_Client.Total_Clients"}
   }]
   ```
   *(Màu có thể là tên token theme như `'maxColor'`/`'minColor'`/`'foreground'` hoặc mã hex `'#...'`.)*

2. **Rules (`Conditional`) — nằm trong `objects.values` (`backColor` / `fontColor`):**
   ```json
   "values": [{
     "properties": {
       "backColor": {
         "solid": {
           "color": {
             "expr": {
               "Conditional": {
                 "Cases": [{
                   "Condition": {
                     "Comparison": {
                       "ComparisonKind": 3,
                       "Left": {"Measure": {"Expression": {"SourceRef": {"Entity": "Dim_Client"}}, "Property": "Total_Clients"}},
                       "Right": {"Literal": {"Value": "500D"}}
                     }
                   },
                   "Value": {"Literal": {"Value": "'#FCE4D6'"}}
                 }]
               }
             }
           }
         }
       }
     },
     "selector": {
       "data": [{"dataViewWildcard": {"matchingOption": 1}}],
       "metadata": "Dim_Client.Total_Clients"
     }
   }]
   ```
   - `ComparisonKind`: `0` (`=`), `1` (`>`), `2` (`>=`), `3` (`<`), `4` (`<=`); kết hợp khoảng dùng `And: {Left, Right}`.
   - `matchingOption: 1` = chỉ áp dụng cho ô dữ liệu (*Values only*, không tô dòng Total).

3. **Gradient (`FillRule`) — nằm trong `objects.values` (`backColor` / `fontColor`):**
   - Dùng `expr.FillRule` với `Input` (Measure/Column) và `FillRule.linearGradient2` (`min`, `max`) hoặc `linearGradient3` (`min`, `mid`, `max`, `nullColoringStrategy`).
4. **Field Value (Measure màu) — nằm trong `objects.values`:**
   - Dùng `expr.Measure` (trả về chuỗi mã màu hex như `'#2E7D32'`).

---

## 4. Ngăn Analytics (`objects` trên `lineChart` / biểu đồ trục)

Quan sát trực tiếp trên `Q1.1` (`b2-q11.visual.json`) khi thêm Y-Axis Constant Line, Min line, Max line và Average line:

1. **Y-Axis Constant Line — nằm trong `objects.y1AxisReferenceLine`:**
   ```json
   "y1AxisReferenceLine": [{
     "properties": {
       "show": {"expr": {"Literal": {"Value": "true"}}},
       "displayName": {"expr": {"Literal": {"Value": "'Y-Axis Constant Line 1'"}}},
       "value": {"expr": {"Literal": {"Value": "100000000D"}}}
     },
     "selector": {"id": "1"}
   }]
   ```
2. **Min / Max / Average Line — đều nằm chung trong `objects.referenceLine` với `Aggregation.Function`:**
   - **Average line:** `Function: 1`
   - **Min line:** `Function: 3`
   - **Max line:** `Function: 4`
   ```json
   "referenceLine": [{
     "properties": {
       "show": {"expr": {"Literal": {"Value": "true"}}},
       "displayName": {"expr": {"Literal": {"Value": "'Average line 1'"}}},
       "value": {
         "expr": {
           "Aggregation": {
             "Expression": {"SelectRef": {"ExpressionName": "Fact_Transaction.Trans Amount"}},
             "Function": 1
           }
         }
       }
     },
     "selector": {"metadata": "Fact_Transaction.Trans Amount", "id": "3"}
   }]
   ```
3. **Trend line (`objects.trend`)** & **Forecast (`objects.forecast`)**: đã có sẵn trong `Nhom6` (`b1-q11.visual.json`): `trend[0].properties.show`, `forecast[0].properties.{show, displayName, transform}`.

---

## 5. Chuyển Theme (`report.json` & `Report/StaticResources/`)

So sánh `b1-report.json` (dùng custom theme `Nhom6Theme.json`) với `b4-report.json` (sau khi chọn theme dựng sẵn `Divergent` từ tab **Design → Themes**):

- **Custom theme (`.json` nhập từ ngoài hoặc gói sẵn của BI Pro):**
  - `themeCollection.customTheme`: `{"name": "<Tên>.json", "reportVersionAtImport": {"visual":"2.13.0","report":"3.4.0","page":"2.3.1"}, "type": "RegisteredResources"}`.
  - Ghi tệp JSON vào `Report/StaticResources/RegisteredResources/<Tên>.json` và đăng ký `{"name": "<Tên>.json", "path": "<Tên>.json", "type": "CustomTheme"}` trong `resourcePackages` (`RegisteredResources`).
- **Built-in theme của Desktop:**
  - `themeCollection.customTheme`: `{"name": "Divergent", ..., "type": "SharedResources"}`, lưu tệp tại `Report/StaticResources/SharedResources/BuiltInThemes/Divergent.json` với `type: "CustomTheme"` trong `SharedResources`.
- **Thiết kế cho BI Pro:** Nhúng mọi preset theme và theme `.json` người dùng nhập vào `RegisteredResources` với `type: "CustomTheme"` (cùng định dạng y hệt `Nhom6Theme.json`) để tệp `.pbix` 100% tự chứa và mở không lỗi trên mọi phiên bản Power BI Desktop.

---

## 6. Bộ lọc nâng cao cột Ngày (`filterConfig`)

Quan sát tại `b3-13521b0905b7e054e5a8.page.json` khi kéo `Dim_Client[birth_date]` vào `Filters on this page` và chọn `Advanced filtering`:
- Thẻ bộ lọc mới ghi `"type": "Advanced"`, `"howCreated": "User"`.
- Biểu thức điều kiện ngày dùng `Comparison` (`ComparisonKind`: `0` =, `1` >, `2` >=, `3` <, `4` <=) kết hợp `And`/`Or` với literal `{"Literal": {"Value": "datetime'1970-01-01T00:00:00'"}}` *(tương thích trực tiếp với `PBIRFilterPatch` & `FilterTranslator` đã có)*.

---

## 7. Kết quả DAX Golden Oracle trực tiếp trên Desktop 2.159 (`dax-golden.json`)

Toàn bộ **21/21** truy vấn chạy thành công trên `Dim_Date[full_date]` (`2011-01-01`..`2018-12-31`, 2 922 dòng) và `Fact_Transaction` / `Dim_Client` của `Nhom6`:

| Nhóm hàm | Hành vi chính xác quan sát được từ Desktop 2.159 |
|---|---|
| `WEEKDAY(d, t)` | `2024-01-07` (CN): `t=1`→`1`, `t=2`→`7`, `t=3`→`6`, mặc định→`1`; `2024-01-08` (T2): `t=1`→`2`, `t=2`→`1`, `t=3`→`0`. |
| `WEEKNUM(d, t)` | `2024-01-07`: `t=1`→`2`, `t=2`→`1`; **`t=21` (ISO 8601):** `2024-12-31`→`1`, `2023-01-01`→`52`. |
| `EOMONTH`, `EDATE` | `EOMONTH(2024-01-15, 1)`=`2024-02-29`; `EDATE(2024-01-31, 1)`=`2024-02-29`, `EDATE(2024-02-29, 12)`=`2025-02-28`. |
| `TIME`, `MINUTE`, `SECOND` | `TIME(14,30,45)`=`1899-12-30T14:30:45`; **tràn modulo 24h:** `TIME(25,70,80)`=`1899-12-30T02:11:20`. |
| `YEARFRAC(d1, d2, basis)` | `2024-01-01..2024-07-01`: `b0`=`0.5`, `b1`=`0.49726775956284153`, `b3`=`0.49863013698630138`; `2023` `b1`=`0.49589041095890413`. |
| `CALENDARAUTO([fyEndMonth])` | Quét toàn bộ cột ngày của model (`1931..2018`): mặc định `1931-01-01..2018-12-31` (`32,142` dòng); `CALENDARAUTO(3)` → `1931-04-01..2019-03-31` (`32,142` dòng). |
| `IFERROR`, `ISERROR`, `ERROR`, `ISNUMBER`, `ISTEXT`, `ISLOGICAL` | `IFERROR(ERROR("boom"), -1)`=`-1`; `ISNUMBER("42")`=`false`, `ISNUMBER(BLANK())`=`false`, `ISTEXT(BLANK())`=`false`, `ISLOGICAL(1)`=`false`. |
| `TOTALYTD`/`QTD`/`MTD` & `DATESYTD`/`QTD`/`MTD` | Tháng 5/2018: `TOTALYTD`=`143,207`, `TOTALQTD`=`50,931`; ngày 15/5/2018: `TOTALMTD`=`12,930`, `DATESYTD`=`135` ngày, `DATESQTD`=`45` ngày, `DATESMTD`=`15` ngày; năm tài chính `"6/30"` ngày 15/8/2018: `DATESYTD`=`46` ngày, tháng 8/2018 `TOTALYTD`=`51,204`. |
| `DATESBETWEEN`, `DATESINPERIOD` | `DATESBETWEEN(BLANK(), 2013-01-10)` = `741` ngày (từ min ngày của cột); `DATESINPERIOD(2018-03-31, -3, MONTH)` = `90` ngày; `(2018-03-15, +10, DAY)` = `10` ngày. |
| `PREVIOUS*`, `NEXT*`, `PARALLELPERIOD`, `STARTOF*`, `ENDOF*` | `PREVIOUSMONTH` của 3/2018=`28` ngày; `PREVIOUSQUARTER` của 5/2018=`90`; `PREVIOUSYEAR`=`365`; `NEXTQUARTER` của 2/2018=`91`; `PARALLELPERIOD(5/2018, -2, MONTH)`=`31`; `STARTOFMONTH`/`ENDOFMONTH` 2/2018 = `2018-02-01` / `2018-02-28`; `STARTOFQUARTER`/`ENDOFQUARTER` 5/2018 = `2018-04-01` / `2018-06-30`. |
| `LOOKUPVALUE` | Khớp trả giá trị (`2018`); không khớp trả `BLANK()` (hoặc đối số `alternateResult` `-1`). |
| `UNION`, `INTERSECT`, `EXCEPT` | **Giữ bản sao (multiset):** `A={1,2,3,2}`, `B={2,3,4}` → `UNION(A,B)`=`7` dòng (`sum=17`), `INTERSECT(A,B)`=`3` dòng (`{2,3,2}`, `sum=7`), `EXCEPT(A,B)`=`1` dòng (`{1}`, `sum=1`). |
| `GENERATESERIES`, `DATATABLE`, `SELECTCOLUMNS` | `GENERATESERIES(1,10,2)`=`5` dòng (`sum=25`); `(0.5,2.0,0.5)`=`4` dòng (`sum=5`); `DATATABLE("Name",STRING,"Val",INTEGER,...)`=`3` dòng (`sum=40`). |
| `COUNTBLANK`, `COUNTX`, `COUNTAX`, `PRODUCTX`, `STDEV.S`, `VAR.S` | **`COUNTBLANK` trả `BLANK()` khi không có ô trống (KHÔNG trả `0`!)**; `COUNTX` bỏ `BLANK` (`3`), `COUNTAX` đếm chuỗi (`4`), `PRODUCTX({2,3,4,BLANK})`=`24`, `STDEV.S(Dim_Date[year])`=`2.291530605463735`, `VAR.S`=`5.2511125157769927`. |
| `OFFSET`, `INDEX`, `WINDOW` | Trên 5 vùng `Dim_Client[client_region]` (`Midwest:546, Northeast:2804, South:1086, Unknown:1, West:933`): `OFFSET(-1)` cho `[BLANK, 546, 2804, 1086, 1]`; `INDEX(1)`=`Midwest`, `INDEX(-1)`=`West`; `WINDOW(1, ABS, 0, REL)` cho tổng luỹ kế `[546, 3350, 4436, 4437, 5370]`. |
