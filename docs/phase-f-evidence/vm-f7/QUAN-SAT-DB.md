# VM-F7b (T091): Desktop nạp PostgreSQL (và SQLite)

Ngày 2026-11-17, Power BI Desktop 2.159 trong VM, Claude lái VM (người dùng cho phép). Máy chủ: `postgres:16-alpine` (Docker trên Mac, người dùng tải sẵn), cổng 55432, cơ sở dữ liệu `sales`, xác thực SCRAM-SHA-256, **không bật SSL**. VM gọi máy Mac qua `10.211.55.2:55432`. Dữ liệu: `public.sales` (1 000 dòng chép từ `sales_2026.sqlite`), `public.customers` (50), khung nhìn `public.north_sales` (region = 'North', 201), `kho.ton_kho` (3 dòng, đủ kiểu: bigint, text, boolean, integer, numeric(12,4), timestamp, varchar, uuid, jsonb, có null). Desktop lưu `f7db-desktop.pbix` (ngoài git, cùng thư mục). Mật khẩu không ghi ở đây.

## Hộp thoại và xác thực

- Get Data ▸ Database ▸ **PostgreSQL database** (ảnh `d1-pg-hop-thoai.png`): ô Server, Database, chế độ Import/DirectQuery, "Advanced options" mở ra: Command timeout (phút), **SQL statement (optional, requires database)**, "Include relationship columns" (bật), "Navigate using full hierarchy" (tắt).
- Server nhập dạng `máy:cổng` (`10.211.55.2:55432`).
- Bước xác thực (ảnh `d2-pg-xac-thuc.png`): hai thẻ **Database** (User name, Password) và Microsoft account; "Select which level to apply these settings to" mặc định là máy chủ `10.211.55.2:55432`. Nút Back / Connect / Cancel.
- Máy chủ không có SSL: Desktop thử kết nối mã hoá trước rồi hỏi (ảnh `d3-pg-ma-hoa.png`): **"Encryption Support: We were unable to connect to the data source using an encrypted connection. To access this data source using an unencrypted connection, click OK."** OK / Cancel.
- Sai mật khẩu: quay lại bước xác thực với dải cảnh báo **"We couldn't authenticate with the credentials provided. Please try again."** (ảnh `d4-pg-sai-mat-khau.png`), giữ tên đăng nhập.
- Thông tin đăng nhập không nằm trong `.pbix`: bảng `DataSource` của `metadata.sqlitedb` rỗng; M chỉ có máy chủ và tên cơ sở dữ liệu.

## Navigator

- Ảnh `d5-pg-navigator.png`. Gốc `10.211.55.2:55432: sales [4]`, dưới là **danh sách phẳng `lược_đồ.bảng`** (không có cấp lược đồ khi "Navigate using full hierarchy" tắt): `public.north_sales` (biểu tượng khung nhìn), `kho.ton_kho`, `public.customers`, `public.sales`. Thứ tự quan sát được: khung nhìn trước, rồi bảng theo lược đồ và tên ([SUY ĐOÁN] từ một mẫu). Lược đồ hệ thống không hiện.
- Xem trước (ảnh `d6-pg-xem-truoc-1.png`, `d7-pg-xem-truoc-2.png`): null hiện `null`, boolean `TRUE/FALSE`, timestamp `3/2/2026 5:45:13` (phần lẻ giây không hiện), uuid và jsonb hiện như chữ (`{"mau": "do"}`, `[1, 2]`). Khung nhìn giữ thứ tự dòng máy chủ trả (không sắp).
- Có nút "Select Related Tables".

## M Desktop sinh

Mỗi mục một truy vấn, **tên truy vấn = `lược_đồ bảng`** (dấu chấm thành dấu cách: `kho ton_kho`, `public sales`, `public north_sales`), hai bước "Source" và "Navigation", không có "Changed Type" (ảnh `d8-pg-power-query.png`, `d9-pg-m.png`):

```
let
    Source = PostgreSQL.Database("10.211.55.2:55432", "sales"),
    public_north_sales = Source{[Schema="public",Item="north_sales"]}[Data]
in
    public_north_sales
```

Tên bước điều hướng = tên truy vấn với dấu cách thành `_` (`kho_ton_kho`), Applied Steps hiện "Navigation".

Có câu SQL (ảnh `d10-pg-sql-xem-truoc.png`, `d11-pg-native-query.png`): bỏ qua Navigator, hiện cửa sổ xem trước tiêu đề `10.211.55.2:55432: sales` (OK/Cancel), truy vấn tên **`Query1`**, một bước "Source":

```
let
    Source = Value.NativeQuery(PostgreSQL.Database("10.211.55.2:55432", "sales"), "select region, count(*) as so_don, sum(amount) as doanh_thu from sales group by region order by region", null, [EnableFolding=true])
in
    Source
```

Bảng `Query1` có chú thích `PBI_NavigationStepName = Navigation`.

## Kiểu (đọc từ `metadata.sqlitedb`)

| PostgreSQL | Kiểu mô hình Desktop | FormatString / chú thích |
|---|---|---|
| smallint, integer, bigint, count(*) | Int64 (6) | `0` |
| numeric(10,2), numeric(12,4), double precision, sum(double) | Double (8) | `PBI_FormatHint {"isGeneralNumber":true}` |
| boolean | Boolean (11) | `"TRUE";"TRUE";"FALSE"` |
| date | DateTime (9) | `Long Date`, `UnderlyingDateTimeDataType = Date` |
| timestamp | DateTime (9) | `General Date` |
| text, varchar(n), **uuid, jsonb** | String (2) | jsonb theo dạng chữ của máy chủ (`{"mau": "do"}`) |

Số dòng khớp truy vấn trực tiếp: `public sales` 1 000, `public north_sales` 201, `kho ton_kho` 3, `Query1` 5 (East 205 / 65 475,68; North 201 / 73 226,4; South 184; Trung tâm 193; West 217).

Phụ (giống VM-F7a): Auto date/time bật nên có `LocalDateTable` cho mỗi cột ngày; Desktop **tự phát hiện quan hệ** `public sales[region] → Query1[region]` và `public north_sales[region] → Query1[region]`. BI Pro không làm hai việc này.

## SQLite (qua ODBC, người dùng cài "Devart ODBC Driver for SQLite" 5.1.0, 64-bit)

- Desktop không có connector SQLite (danh mục Database không có). Get Data ▸ **ODBC** ▸ hộp "From ODBC" (ảnh `s1-odbc-hop-thoai.png`): "Data source name (DSN)" mặc định chọn DSN đầu danh sách (dBASE Files), có mục "(None)"; Advanced options: "Connection string (non-credential properties)", "SQL statement", "Supported row reduction clauses" (ảnh `s2-odbc-nang-cao.png`). Buổi này dùng DSN (None) + chuỗi `Driver={Devart ODBC Driver for SQLite};Database=C:\Users\bacpew\f7db\sales_2026.sqlite`.
- Bước xác thực "ODBC driver" (ảnh `s3-odbc-xac-thuc.png`): ba thẻ Default or Custom / Windows / Database (mặc định đứng ở Database: User name, Password). Chọn Default or Custom (không mật khẩu) rồi Connect.
- Navigator (ảnh `s4-odbc-navigator.png`): gốc `ODBC (Driver={Devart ODBC Driver for SQLite}...)` → thư mục `main [3]` → **NorthSales (khung nhìn), Customers, Sales**: khung nhìn trước, rồi bảng theo tên (giống PostgreSQL).
- Xem trước (ảnh `s5-odbc-xem-truoc.png`): driver Devart mặc định đổi chữ sang mã ANSI nên **chữ tiếng Việt hỏng** ("Đồng hồ" → "Ð?ng h?", "Mũ" → "Mu"; "Trung tâm", "Túi xách" giữ được vì có trong Windows-1252). Lỗi của driver, không phải của Desktop.
- M (ảnh `s6-odbc-m.png`, golden `f7sqlite-desktop.pbix`, ngoài git). Truy vấn tên đúng tên bảng (`Sales`, `Customers`, `NorthSales`), ba bước, Applied Steps "Source", "Navigation":

```
let
    Source = Odbc.DataSource("Driver={Devart ODBC Driver for SQLite};Database=C:\Users\bacpew\f7db\sales_2026.sqlite", [HierarchicalNavigation=true]),
    main_Database = Source{[Name="main",Kind="Database"]}[Data],
    Sales_Table = main_Database{[Name="Sales",Kind="Table"]}[Data]
in
    Sales_Table
```

  Khung nhìn: `NorthSales_View = main_Database{[Name="NorthSales",Kind="View"]}[Data]`.
- Kiểu theo kiểu khai báo của cột: INTEGER → Int64 (`0`), REAL → Double, **TEXT → String (kể cả `OrderDate` dạng "2026-03-02")**. Không có "Changed Type". Số dòng: Sales 1 000, Customers 50, NorthSales 201.
- Desktop tự phát hiện quan hệ `Sales[CustomerID] → Customers[CustomerID]`, `NorthSales[CustomerID] → Customers[CustomerID]` (BI Pro không).

## Áp vào BI Pro

- Get Data ▸ PostgreSQL: hộp Server (`máy:cổng`, cổng mặc định 5432), Database, Advanced: SQL statement. Bước xác thực tên/mật khẩu; mật khẩu lưu Keychain theo máy chủ, không vào `.pbix`.
- Thử SSL trước; máy chủ trả "không SSL" thì hỏi như Desktop rồi mới kết nối không mã hoá.
- Navigator danh sách phẳng `lược_đồ.bảng`, khung nhìn trước; nạp ra truy vấn tên `lược_đồ bảng`, M hai bước đúng dạng trên. Có SQL: truy vấn `Query1`, `Value.NativeQuery(..., null, [EnableFolding=true])`.
- Kiểu theo bảng trên; uuid, json, jsonb thành chữ.
- SQLite: Get Data ▸ SQLite chọn tệp (BI Pro đọc thẳng bằng `sqlite3`, không cần ODBC, chữ UTF-8 giữ đúng); Navigator khung nhìn trước; M ghi dạng ODBC như Desktop với driver Devart (`SQLiteODBC.driver`) để Desktop có driver này Refresh được khi đường dẫn tệp hợp lệ; `Odbc.DataSource` với driver SQLite chạy được trong BI Pro, driver khác báo chưa hỗ trợ.
