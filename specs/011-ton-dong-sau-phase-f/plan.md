# Kế hoạch triển khai: Tồn đọng sau Phase F

**Nhánh**: `main` | **Ngày**: 2026-11-17 | **Spec**: `specs/011-ton-dong-sau-phase-f/spec.md`

**Đầu vào**: spec đã duyệt 2026-11-17 (6 câu chuyện; Claude lái VM; màn thêm dữ liệu có Enter Data).

## Tóm tắt

Làm sáu câu chuyện, mỗi câu chuyện theo vòng: quan sát Desktop (VM-F10 đến VM-F15) → ghi `QUAN-SAT.md` → test trước → code → gate Desktop. Không thêm thư viện ngoài. Phần lớn là việc của lead vì đụng sâu `PBIXKit/Writing` và đường truy vấn visual. Hai gói tách được giao agy: hàm văn bản DAX (F2-DAXTEXT) và nguồn PostgreSQL/Parquet (F2-CONN), sau khi có quan sát VM tương ứng.

Hướng kỹ thuật chính (chi tiết và lý do ở `research.md`):

- **Gộp ngầm (US1)**: trường của visual có thêm dạng "cột + phép gộp" (`Aggregation` của PBIR/layout cũ). `VisualQuerySpec` nhận thước đo dạng biểu thức; `DAXQueryBuilder` sinh văn bản DAX như Performance Analyzer. `WellRules` chỉ chặn khi mô hình đặt "discourage implicit measures". Menu trường có danh sách phép gộp.
- **Tài liệu mới (US2)**:
  - Màn "Thêm dữ liệu vào báo cáo" là trạng thái trống của khung báo cáo.
  - Enter Data là một bảng nạp qua đường T3 sẵn có. M của bảng giống Desktop, nên MEngine cần thêm `Binary.FromText`, `Binary.Decompress` (dùng framework Compression của Apple), `Table.FromRows` và `type table` có `meta`.
  - Auto date/time dùng `ModelEdit` mới. Mỗi cột ngày có bảng `LocalDateTable_<guid>` (bảng tính toán `Calendar(...)`), phân cấp "Date Hierarchy", quan hệ ẩn kiểu chỉ so phần ngày và dòng `Variation`. Mô hình có thêm một `DateTableTemplate_<guid>`. Golden cấu trúc lấy từ `w8.3.pbix`.
  - Tự phát hiện quan hệ chạy sau mỗi lần nạp, cùng bước hoàn tác.
- **Hàm văn bản DAX (US3)**: thêm vào `DAXEngine/Functions/Text.swift` (gói agy), golden từ DAX query view của Desktop.
- **Cột tính toán còn được dùng (US4)**: mở chặn ở `MetadataWriter.requireNoIndexes`. Quan hệ thì xoá rồi thêm lại với `R$` mới, như đường thay bảng của Phase F. Phân cấp thì cần bộ ghi chỉ mục phân cấp `U$` mới. Cột sắp xếp thì dựng lại `H$` của cột được sắp.
- **Dữ liệu lớn (US5)**:
  - `VertiPaqWriter` ghi nhiều đoạn theo cách chia của Desktop. Nhom6 cho thấy bảng 1 056 320 dòng nằm trong một đoạn, còn bảng `H$` đi kèm thì hai đoạn.
  - Thêm RLE theo bố cục quan sát ở VM-F14.
  - Cột tính toán trên bảng nhiều đoạn.
- **Nguồn (US6)**:
  - PostgreSQL đọc thêm năm kiểu (timestamptz, time, interval, bytea, mảng) theo quan sát.
  - Tên driver ODBC SQLite chọn được và được nhớ (`UserDefaults`).
  - Parquet đọc được cột struct và list, đưa ra ô `TableData.structured` sẵn có.

## Bối cảnh kỹ thuật

**Ngôn ngữ/Phiên bản**: Swift 6 (SwiftPM, như các phase trước), macOS 14+ Apple Silicon

**Phụ thuộc chính**: chỉ framework Apple (SwiftUI, AppKit, Foundation, Compression, Security). Không thêm package.

**Lưu trữ**: tệp `.pbix` (ZIP, ABF, `metadata.sqlitedb`, VertiPaq); `UserDefaults` cho lựa chọn driver ODBC; Keychain giữ nguyên cho mật khẩu PostgreSQL.

**Kiểm thử**: Swift Testing (`swift test`); golden nặng `BIPRO_HEAVY=1 … -c release`; gate Desktop trên VM (Claude lái, `build/vm-tools/`).

**Nền tảng**: macOS native; Desktop 2.159 trong VM Windows 11 (Parallels) để quan sát và gate.

**Loại dự án**: app desktop + thư viện (`PBIXKit`, `DAXEngine`, `MEngine`, `Connectors`, `ColumnStore`).

**Mục tiêu hiệu năng**: SC-005 (10 triệu dòng × 10 cột: lưu dưới 2 phút, dưới 4 GB); SC-008 (Nhom6 T2 dưới 4 giây, golden không đổi); truy vấn visual gộp ngầm cùng bậc thời gian với measure tương đương.

**Ràng buộc**: số liệu khớp Desktop (hiến pháp II); file Desktop mở không lỗi; không mật khẩu trong `.pbix`/docs/log; không ghi đè fixture gốc.

**Quy mô**: 6 câu chuyện, khoảng 60 đến 80 task; 6 buổi VM ngắn.

## Kiểm theo hiến pháp

| Nguyên tắc | Kiểm | Kết quả |
|---|---|---|
| I. Quan sát trước, không dịch ngược | Mỗi câu chuyện mở đầu bằng buổi VM-F10 đến VM-F15, kết quả ghi `docs/phase-f2-evidence/vm-f1x/QUAN-SAT.md` trước task code. Quy tắc chưa quan sát được đánh dấu `[SUY ĐOÁN]` trong code. `w8.3.pbix` và Nhom6 dùng làm nguồn đọc sẵn (chỉ đọc). | ĐẠT |
| II. Power BI là golden | Golden: DAX query view (hàm văn bản, truy vấn gộp ngầm), file Desktop lưu (Auto date/time, quan hệ, bảng lớn, RLE, Enter Data), bảng Desktop nạp (PostgreSQL, SQLite, Parquet). Không hard-code. | ĐẠT |
| III. Native, không thư viện ngoài | Deflate/inflate dùng `Compression.framework`; RLE, Parquet lồng, kiểu PostgreSQL tự viết. | ĐẠT |
| IV. Ranh giới dữ liệu và mạng | Không tải mạng. PostgreSQL là container cục bộ có sẵn. Mẫu dữ liệu sinh bằng Python và pyarrow có sẵn trên máy, đặt ở `build/f2-out/`. File gốc chỉ đọc. | ĐẠT |
| Ràng buộc VM (hiến pháp 1.1.0: agent lái VM khi người dùng cho phép theo đợt) | Bạn cho phép lái VM trong đợt này (Làm rõ 2026-11-17) | ĐẠT |
| V. Hợp đồng trước, mỗi file một chủ | Đợt 0 chốt `docs/phase-f2-ownership.tsv` và hợp đồng ở `contracts/`. Hai gói agy sửa thư mục riêng (`DAXEngine/Functions/Text*.swift`; `Connectors/Postgres/**`, `Connectors/Parquet/**`). | ĐẠT |

Kiểm lại sau thiết kế (Giai đoạn 1): hợp đồng không thêm phụ thuộc ngoài. Gói agy không chung file với lead: lead không sửa `Text.swift` và `Connectors/Postgres|Parquet` trong lúc gói chạy. ĐẠT.

## Cấu trúc dự án

### Tài liệu (tính năng này)

```text
specs/011-ton-dong-sau-phase-f/
├── spec.md
├── plan.md              # tệp này
├── research.md          # Giai đoạn 0
├── data-model.md        # Giai đoạn 1
├── quickstart.md        # Giai đoạn 1
├── contracts/           # Giai đoạn 1 (hợp đồng API nội bộ)
├── checklists/requirements.md
└── tasks.md             # /speckit-tasks
docs/phase-f2-evidence/vm-f10 … vm-f15/   # quan sát và gate từng câu chuyện
docs/phase-f2-ownership.tsv               # Đợt 0
```

### Mã nguồn (điểm chạm chính)

```text
Sources/BIPro/
├── Visuals/Query/{VisualQuerySpec,VisualQuerySpecReader,DAXQueryBuilder,DataViewMapper}.swift   # US1
├── Report/Edit/{WellRules,FieldRef,FieldEditor,FieldReferences,LayoutEditor}.swift             # US1
├── Panes/{DataPane,BuildPane…}.swift          # US1 menu phép gộp; US2 phân cấp ngày trong field list
├── Report/AddDataPanel.swift                   # US2 mới: màn "Thêm dữ liệu vào báo cáo"
├── Query/EnterData{State,View}.swift           # US2 mới: hộp Tạo bảng (Enter Data)
├── Model/Edit/{AutoDateTime,RelationshipDetector}.swift   # US2 mới
├── Model/Edit/{CalculatedEditor,CalculationPlan}.swift    # US4 bỏ chặn, hỏi xoá kèm
└── Query/{NavigatorState,SourceQuery,DatabaseConnectView}.swift   # US6 driver ODBC
Sources/PBIXKit/Writing/
├── ModelEdit.swift                 # US2 (auto date, hierarchy, variation), US4
├── MetadataWriter.swift, TableMetadataWriter.swift   # US2, US4, US5
├── HierarchyIndexWriter.swift      # US4 mới: chỉ mục phân cấp U$
├── VertiPaqWriter.swift            # US5: nhiều đoạn, RLE
├── PBIRQueryPatch.swift, PBIRNewVisual.swift, LegacyLayoutPatch.swift   # US1 trường Aggregation
└── NewDocument.swift               # US2: bật Auto date/time cho tài liệu mới
Sources/PBIXKit/ModelMetadata.swift # US2: Variation, cờ discourage implicit measures (nếu chưa đọc)
Sources/MEngine/Library/{Binary.swift (mới), TableRows.swift, Support.swift}   # US2 Enter Data
Sources/DAXEngine/Functions/Text.swift (+ TextMore.swift)   # US3 (agy F2-DAXTEXT)
Sources/Connectors/Postgres/**, Sources/Connectors/Parquet/**   # US6 (agy F2-CONN)
Tests/… theo từng module (PBIXKitTests/Write, BIProTests/Report, BIProTests/Model, DAXEngineTests, MEngineTests, ConnectorsTests)
```

**Quyết định cấu trúc**: giữ các module SwiftPM hiện có, không thêm module. Tệp mới đặt cạnh tệp cùng chủ đề. Tên thư mục bằng chứng là `phase-f2-evidence`, nối tiếp Phase F. Tên tạm `phase-g0-evidence` trong spec đã bỏ.

## Thứ tự và gói việc

| Đợt | Việc | Người làm | Phụ thuộc |
|---|---|---|---|
| 0 | Hợp đồng (`contracts/`), bảng sở hữu, thư mục bằng chứng, mẫu dữ liệu `build/f2-out/` | lead | |
| 1 | US1: VM-F10 → gộp ngầm → gate | lead | Đợt 0 |
| 1 song song | US3: VM-F12 (lead, ngắn) → brief → gói F2-DAXTEXT | agy | VM-F12 |
| 2 | US2: VM-F11 → màn thêm dữ liệu, Enter Data, Auto date/time, phát hiện quan hệ → gate | lead | US1 (dùng chung field list và visual cho phân cấp ngày) |
| 2 song song | US6: VM-F15 (lead) → brief → gói F2-CONN (PostgreSQL, Parquet); driver ODBC do lead làm | agy + lead | VM-F15 |
| 3 | US4: VM-F13 → bộ ghi `U$`, dựng lại `R$`/`H$` → gate | lead | US2 (dùng chung bộ ghi phân cấp) |
| 4 | US5: VM-F14 → nhiều đoạn, RLE → gate | lead | US4 (chỉ mục trên bảng nhiều đoạn) |
| 5 | Golden nặng, `/code-review`, `/speckit-converge`, gate tổng, tài liệu | lead | tất cả |

Mỗi gói agy dùng một worktree riêng và tối đa 2 gói chạy cùng lúc. `git status` phải sạch trước khi giao, nên bạn commit trước. Review theo skill `agy-delegation`.

## Theo dõi độ phức tạp

| Ngoại lệ | Vì sao cần | Cách đơn giản hơn bị loại vì |
|---|---|---|
| Bộ ghi chỉ mục phân cấp `U$` mới (US2, US4) | Auto date/time cần phân cấp "Date Hierarchy"; sửa cột là cấp phân cấp cần dựng lại `U$` (VM-F9) | Bỏ phân cấp khỏi bảng ngày cục bộ: file khác Desktop, visual theo Năm/Quý không dùng được |
