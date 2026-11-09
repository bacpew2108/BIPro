# Kế hoạch triển khai: E3-cấu-trúc, truy vấn visual chậm nhất dưới 1 giây

**Nhánh**: `main` (không tạo nhánh riêng) | **Ngày**: 2026-11-09 | **Spec**: [spec.md](spec.md)

**Đầu vào**: `specs/001-e3-cau-truc/spec.md`

## Tóm tắt

Đưa combo "Rủi ro thấu chi" (2,15 s) và matrix "Giờ × Thứ" (1,75 s) xuống dưới 1 s trên Nhom6, 8 nhân, mà kết quả khớp từng byte.

Hướng chọn (chi tiết ở [research.md](research.md)):

1. **Chính: tính gộp theo nhóm cho vòng lặp X** (`AVERAGEX`, `SUMX`, `MINX`, `MAXX`). Khi bảng lặp là các giá trị riêng của một cột (như `VALUES(account_key)`) và thân vòng lặp là mẫu `CALCULATE(agg(cột), bộ lọc không phụ thuộc dòng)`, quét fact một lần, chia dòng theo nhóm, tính `agg` cho mọi nhóm cùng lúc, thay vì dựng ngữ cảnh lọc và quét cho từng nhóm. Với `Avg_Account_Balance`: hai lần quét (MAX theo nhóm, rồi MAX có điều kiện `trans_timestamp = t` theo nhóm) thay cho khoảng 360 nghìn lần CALCULATE.
2. **Dự phòng: `FilterContext` ít cấp phát** ở đường nóng. Chỉ làm nếu hướng 1 chưa đủ hoặc cần cho matrix.
3. **Matrix Giờ × Thứ**: chưa có chẩn đoán sau vòng 2, nên bắt đầu bằng đo (`sample`), rồi chọn sửa. Có thể dùng chung hướng 1 hoặc cần một sửa riêng.

**Bảo đảm nguyên vẹn hành vi**: đường mới chỉ chạy khi nhận ra đúng mẫu hẹp; mọi trường hợp khác rơi về đường cũ. Có công tắc tắt đường mới để test so sánh hai đường trên cùng dữ liệu.

**Cổng dừng**: trước khi làm bản tổng quát, chạy thử nghiệm giới hạn dưới (T004) để chắc rằng dưới 1 s đạt được. Nếu không, dừng và báo bạn (spec, Giả định).

## Bối cảnh kỹ thuật

**Ngôn ngữ/Phiên bản**: Swift 6 (SwiftPM), module `DAXEngine`, `ColumnStore`

**Phụ thuộc chính**: không thêm (Hiến pháp III). Chỉ Foundation/Dispatch của hệ thống

**Lưu trữ**: không áp dụng. Đọc cột từ `ColumnStore` qua `ColumnData` và `ColumnIndex`

**Kiểm thử**: `swift test` (800 test), golden nặng `BIPRO_HEAVY=1 swift test -c release … --filter "Nhom6|ORA|VIS"` (67 test), `zsh scripts/e3-loop.sh` (so byte), `dax-run profile`

**Nền tảng**: macOS Apple Silicon (M1 Pro 8 nhân khi đo)

**Loại dự án**: ứng dụng desktop. Phần đụng tới là thư viện engine

**Mục tiêu hiệu năng**: mỗi truy vấn mục tiêu dưới 1,0 s (trung vị 5 lần, 8 nhân); trang D1 song song không chậm hơn hiện tại (chốt 2026-11-09: không chậm hơn 3,32 s, mục tiêu ≤ 2,5 s)

**Ràng buộc**: kết quả khớp byte; các trang khác không chậm quá 10%; bộ nhớ đỉnh không tăng quá 25%; huỷ truy vấn vẫn nhanh

**Quy mô**: Nhom6, bảng `Fact_Transaction` cỡ triệu dòng; combo có khoảng 180 nghìn ô (tài khoản × tháng)

## Kiểm tra theo Hiến pháp

*Cổng: phải qua trước Phase 0, kiểm lại sau Phase 1.*

| Nguyên tắc | Kết quả | Ghi chú |
|---|---|---|
| I. Quan sát Power BI trước | Qua | Không thêm hành vi mới. Hành vi chuẩn đã quan sát qua golden; đường mới chỉ là cách tính khác cho cùng kết quả |
| II. Power BI là chuẩn (golden) | Qua | Golden 30/30 Phase B, 72 truy vấn visual, 3 truy vấn đo so byte. Thêm test so sánh hai đường trên dữ liệu thật. Không hard-code |
| III. Native, không thư viện ngoài | Qua | Chỉ Swift và thư viện hệ thống |
| IV. Ranh giới dữ liệu và mạng | Qua | Chỉ đọc `~/Downloads/Nhom6_Dashboard.pbix`; đầu ra ở `build/` và `docs/phase-c-evidence/` |
| V. Hợp đồng trước, mỗi file một chủ | Qua | Lead tự làm, không chia worker. File ở bảng dưới thuộc một mình lead. Hợp đồng công tắc và tương đương ở [contracts/](contracts/) |

Sau Phase 1: không có vi phạm. Mục "Theo dõi độ phức tạp" để trống.

## Cấu trúc dự án

### Tài liệu (tính năng này)

```text
specs/001-e3-cau-truc/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── engine-equivalence.md
├── checklists/requirements.md
└── tasks.md            # do /speckit-tasks tạo, chưa có
```

### Mã nguồn

```text
Sources/DAXEngine/
├── Functions/Iterators.swift        # sửa: gọi đường gộp trước khi lặp từng dòng (SUMX, AVERAGEX, MINX, MAXX)
├── Runtime/BatchedIteration.swift   # mới: nhận mẫu, tính gộp theo nhóm, công tắc tắt
├── Runtime/Evaluator.swift          # sửa nhỏ: lộ hàm cần cho đường gộp (visibleRows không có bộ lọc nhóm)
├── Runtime/FilterContext.swift      # chỉ sửa nếu hướng 2 cần (giảm cấp phát)
└── Runtime/Cache.swift              # chỉ sửa nếu cache kết quả gộp theo vân tay ngữ cảnh

Sources/ColumnStore/RelationshipIndex.swift  # sửa (đã duyệt 2026-11-09): manyRows nhánh postings dùng hợp bitset thay sort; hasUnmatched(in:) thoát sớm
Sources/ColumnStore/ColumnData.swift         # sửa (đã duyệt 2026-11-09): thêm ColumnIndex.sortRankTable() (đọc bảng hạng một lần)
Sources/DAXEngine/Functions/Aggregation.swift     # sửa (đã duyệt 2026-11-09): extremeOfColumn đọc bảng hạng một lần, kiểm huỷ theo đợt
Sources/DAXEngine/Runtime/FilterContext.swift     # sửa (đã duyệt 2026-11-09): values(of:among:) dùng mảng cờ theo mã, không băm và không sắp bằng sortRank
Sources/DAXEngine/Query/SummarizeColumns.swift    # sửa (đã duyệt 2026-11-09): distinctEncodedTuples, tổ hợp nhóm theo mã
Sources/DAXTestSupport/Fixtures.swift             # sửa (đã duyệt 2026-11-09): DAXFixtures.nhom6 đọc BIPRO_NHOM6 hoặc bipro-golden/Nhom6_work.pbix
Tests/DAXEngineTests/ORA/ORAGoldenTests.swift     # sửa (đã duyệt 2026-11-09): huyTruyVanNangDungNhanh lặp truy vấn đến khi bị huỷ

Tests/DAXEngineTests/PERF/
├── BatchedIterationTests.swift      # mới: so hai đường (gộp và từng dòng) trên Nhom6 và dữ liệu nhỏ
└── (golden nặng sẵn có, không sửa)

docs/phase-c-evidence/C1.md          # §1.5: ghi số đo trước/sau
docs/STATE.md                        # cập nhật tiến độ
scripts/e3-loop.sh                   # có thể thêm đo matrix và công tắc, nếu cần
```

**Quyết định cấu trúc**: một file mới trong `Runtime/` chứa toàn bộ logic gộp, để phần lõi (`Evaluator`, `Calculate`) chỉ thêm một điểm gọi. Tắt được bằng một biến môi trường nên bản cũ vẫn chạy được để so sánh.

## Theo dõi độ phức tạp

Không có vi phạm Hiến pháp cần giải trình.
