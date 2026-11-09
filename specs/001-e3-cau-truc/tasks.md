---
description: "Danh sách việc: E3-cấu-trúc, truy vấn visual chậm nhất dưới 1 giây"
---

# Việc cần làm: E3-cấu-trúc

**Đầu vào**: `specs/001-e3-cau-truc/` (spec.md, plan.md, research.md, data-model.md, contracts/engine-equivalence.md, quickstart.md)

**Kiểm thử**: spec yêu cầu (FR-008): mọi cách tính mới có test so sánh với đường cũ trên dữ liệu thật, không hard-code.

**Người làm**: lead tự làm, tuần tự (đụng chung `Sources/DAXEngine/`), không giao agy. Vì vậy không có việc đánh dấu `[P]` trừ chỗ ghi rõ.

**Quy ước**: `[US1]`, `[US2]`, `[US3]` là câu chuyện trong spec. Lệnh build/test là các lệnh trong `CLAUDE.md`. Không commit trừ khi bạn bảo.

## Giai đoạn 1: Chuẩn bị

- [X] T001 Xác nhận bản chuẩn (`~/Downloads/Nhom6_Dashboard.pbix` không còn; dùng `~/Downloads/bipro-golden/Nhom6_work.pbix`, khớp byte và bố cục; `DAXFixtures.nhom6` và `e3-loop.sh` tự tìm, hoặc đặt `BIPRO_NHOM6`): chạy `zsh scripts/e3-loop.sh` trên mã hiện tại (commit `c8409e9`), phải in `khớp byte với bản chuẩn` cho cả ba truy vấn. Chạy `dax-run profile` cho bốn trang (D1, D2, D3, Chi tiết chi nhánh) và lưu tổng thời gian tuần tự và song song, cùng bộ nhớ đỉnh (`/usr/bin/time -l`), vào `specs/001-e3-cau-truc/measurements.md` (file mới, bảng "Trước khi sửa"). Dựa vào số D1 song song hiện tại, đề xuất lại ngưỡng SC-007 trong `spec.md` (xem T006).
- [X] T002 Sửa `scripts/e3-loop.sh`: chạy mỗi truy vấn 5 lần, in trung vị thời gian, giữ nguyên bước so byte; truyền biến môi trường `BIPRO_BATCH` xuống `dax-run`. Chạy lại để có số đo chuẩn 5 lần (ghi vào `measurements.md`).
- [X] T003 Tạo `Sources/DAXEngine/Runtime/BatchedIteration.swift` rỗng có công tắc: hàm `BatchedIteration.isEnabled` đọc `BIPRO_BATCH` (`0` tắt, còn lại bật, mặc định bật), một biến ghi đè `overrideEnabled` (`nil` = theo biến môi trường; test dùng biến này, `e3-loop.sh` dùng biến môi trường) và một điểm vào `tryRun(...)` luôn trả `nil` (chưa gộp). `swift build` qua, `swift test` vẫn 800 qua (không đổi hành vi).

## Giai đoạn 2: Nền tảng và cổng dừng (chặn mọi câu chuyện)

**Quan trọng**: chưa làm tổng quát trước khi qua T006.

- [X] T004 Thử nghiệm giới hạn dưới combo thấu chi: viết mã tạm bằng tay (không cần nhận mẫu) trong `Tests/DAXEngineTests/PERF/BatchedSpikeTests.swift` tính `Avg_Account_Balance` bằng hai lần quét gộp theo tài khoản trên Nhom6; thử hai cách: (a) gộp theo từng tháng của `SUMMARIZECOLUMNS`, (b) gộp một lần theo (tháng, tài khoản). Kiểm kết quả bằng đúng giá trị của đường cũ (so từng ô). Đo thời gian 5 lần, 8 nhân. Ghi vào `research.md` R3. Mã này là tạm, xoá hoặc đánh dấu ở T025.
- [X] T005 Chẩn đoán matrix Giờ × Thứ: chạy truy vấn `docs/phase-c-evidence/observe-c1/pa/D1-matrix-gio-thu.dax` nhiều lần liên tiếp và lấy mẫu CPU bằng `sample <pid> 10` (cùng cách vòng 2). Gán chi phí cho từng nguyên nhân (lan truyền `ALLSELECTED`, `Trans Count (k)` trên 168 ô lưới, dựng `grid`, cấp phát). Ghi vào `research.md` R4 và chọn cách sửa (nhớ biến bảng theo vân tay, dùng chung đường gộp, hoặc giảm cấp phát).
- [X] T006 Cổng quyết định: đối chiếu kết quả T004 và T005 với ngưỡng ở `research.md` R3 (≤ 0,6 s làm tiếp; 0,6–1,0 s làm tiếp và báo bạn sát ngưỡng; > 1,0 s dừng hỏi bạn). Cập nhật `docs/STATE.md`. Chốt ngưỡng SC-007 theo số đo ở T001 (ví dụ "không chậm hơn hiện tại, mục tiêu X s") và viết lại T015 thành việc cụ thể (file, hàm) theo T005. Báo bạn kết quả cổng cùng hai thay đổi này và chờ bạn đồng ý trước khi sang giai đoạn 3.

**Điểm kiểm tra**: nền tảng xong và cổng đã qua, mới bắt đầu câu chuyện 1.

## Giai đoạn 3: Câu chuyện 1 (P1): Hai visual nặng hiện số dưới 1 giây

**Mục tiêu**: combo thấu chi và matrix Giờ × Thứ dưới 1,0 s (SC-001, SC-002).

**Kiểm thử độc lập**: `zsh scripts/e3-loop.sh` in thời gian trung vị dưới 1 s cho hai truy vấn và `khớp byte` cho cả ba.

### Test trước (viết trước, phải thấy trượt rồi mới viết mã)

- [X] T007 [US1] Tạo `Tests/DAXEngineTests/PERF/BatchedShapeTests.swift`: test nhận mẫu. Chấp nhận: `AVERAGEX(VALUES(g), CALCULATE(MAX(c), REMOVEFILTERS(d)))` và mẫu hai bước `t` rồi `CALCULATE(MAX(b), …, c = t)`. Từ chối (phải trả `nil`): có `KEEPFILTERS`, bộ lọc phụ thuộc dòng khác `t`, `USERELATIONSHIP`, hàm gộp ngoài MAX/MIN/SUM/COUNT, bảng lặp không phải giá trị riêng của một cột, `t` đến từ biểu thức không theo mẫu. Dùng model nhỏ dựng sẵn của `MiniBankFixtureTests` hoặc fixture trong `DAXTestSupport`.
- [X] T008 [US1] Tạo `Tests/DAXEngineTests/PERF/BatchedIterationTests.swift`: test tương đương đường gộp và đường cũ trên model nhỏ, so từng giá trị: nhóm rỗng ra BLANK, `t` BLANK (phải rơi về đường cũ), hai dòng cùng `trans_timestamp`, bộ lọc ngoài đang lọc cột nhóm (phải bị đè như đường cũ), có `ALLSELECTED` bao ngoài. Mỗi trường hợp chạy hai lần, `overrideEnabled = false` rồi `true` (không đổi biến môi trường của tiến trình).

### Cài đặt

- [X] T009 [US1] Trong `Sources/DAXEngine/Runtime/BatchedIteration.swift`: nhận mẫu (`BatchedShape`, trường theo `data-model.md`): kiểm bốn điều kiện ở `research.md` R2; không đủ thì trả `nil`. Cho T007 qua.
- [X] T010 [US1] Trong `Sources/DAXEngine/Runtime/BatchedIteration.swift`: tính gộp một bước. Lấy tập dòng fact hiển thị khi đã bỏ lọc cột nhóm `G` (một lần), chia theo mã `G`, tính MAX/MIN/SUM/COUNT cho mọi nhóm, trả `GroupedResult` (`values` theo mã nhóm, `rowsScanned`). Khớp ngữ nghĩa BLANK của đường cũ.
- [X] T011 [US1] Trong `Sources/DAXEngine/Runtime/BatchedIteration.swift`: tính gộp hai bước tham số (`C2 = t`): bước 1 cho `t` theo nhóm, bước 2 chỉ xét dòng có `C2` bằng `t` của nhóm đó rồi tính `agg`. `t` BLANK ở bất kỳ nhóm nào thì bỏ cuộc và chạy đường cũ cho cả vòng lặp.
- [X] T012 [US1] (không cần sửa: các hàm cần dùng đã internal) Trong `Sources/DAXEngine/Runtime/Evaluator.swift`: lộ hàm tối thiểu cho đường gộp (tập dòng hiển thị của bảng khi đã bỏ lọc một cột, đọc mã nhóm). Không đổi hành vi hiện có.
- [X] T013 [US1] Trong `Sources/DAXEngine/Functions/Iterators.swift`: ở `sumxBody`, `averagexBody` và `extremexBody`, gọi `BatchedIteration.tryRun` trước vòng lặp từng dòng; trả `nil` thì chạy đường cũ nguyên văn. Cho T008 qua.
- [X] T014 [US1] Trong `Sources/DAXEngine/Runtime/BatchedIteration.swift`: gọi `checkCancelled()` định kỳ trong vòng quét (mỗi 4096 dòng như `computeTransitionRows`) và bảo đảm lỗi của đường gộp rơi về đường cũ để sinh đúng lỗi cũ (hợp đồng C4).
- [X] T015 [US1] Sửa matrix Giờ × Thứ (người dùng đã đồng ý 2026-11-09): trong `Sources/ColumnStore/RelationshipIndex.swift`, hàm `manyRows(from:strategy:)` nhánh postings, thay `out.append(contentsOf:)` + `out.sort()` bằng hợp bitset qua `RowSet.union(universe:disjointLists:extra:)` (cùng tập dòng đã sắp, khớp byte); đo lại, nếu matrix còn ≥ 1,0 s thì xử lý tiếp `FilterContext.values(of:among:)` trong `Sources/DAXEngine/Runtime/FilterContext.swift` (bỏ `Set` băm) và pha tuần tự `SummarizeColumns.groupCombinations`. Thêm test trong `BatchedIterationTests.swift` so hai đường cho `Peak Hour Font Color` và `Peak Hour Top10 Icon` trên Nhom6.
- [X] T016 [US1] Chạy `zsh scripts/e3-loop.sh` (5 lần): ghi trung vị vào `measurements.md` bảng "Sau". Nếu combo hoặc matrix còn ≥ 1,0 s: quay lại T005/T004, thử hướng 2 (giảm cấp phát `FilterContext` ở `Runtime/FilterContext.swift`) rồi đo lại; nếu vẫn ≥ 1,0 s thì dừng và báo bạn số đo.

**Điểm kiểm tra**: hai truy vấn dưới 1 s, ba truy vấn khớp byte.

## Giai đoạn 4: Câu chuyện 2 (P1): Mọi kết quả cũ vẫn đúng

**Mục tiêu**: không số nào đổi (FR-003, FR-004, SC-006).

**Kiểm thử độc lập**: `swift test` và golden nặng đều qua; hai chế độ `BIPRO_BATCH` cho cùng kết quả.

- [X] T017 [US2] Thêm vào `Tests/DAXEngineTests/PERF/BatchedIterationTests.swift` (test nặng, dùng `BIPRO_HEAVY=1`): chạy ba truy vấn đo và 72 truy vấn visual (`docs/phase-c-evidence/observe-c1/pa/`) với `overrideEnabled = false` và `true`, so từng byte kết quả.
- [X] T018 [US2] Thêm test song song (hợp đồng C5): chạy combo thấu chi và matrix 20 lần với 8 luồng, mọi lần phải bằng nhau từng byte và bằng đường cũ.
- [X] T019 [US2] Chạy `swift test` (toàn bộ): phải qua toàn bộ (800 cũ + test mới).
- [X] T020 [US2] Chạy golden nặng: `BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --filter "Nhom6|ORA|VIS"`. Phải qua 67 + test mới; riêng `huyTruyVanNangDungNhanh` nếu trượt thì chạy lại một mình với `--filter huyTruyVanNangDungNhanh` và phải qua (FR-005).

**Điểm kiểm tra**: bằng chứng khớp đủ cho cả hai câu chuyện P1.

## Giai đoạn 5: Câu chuyện 3 (P2): Không chậm đi ở chỗ khác

**Mục tiêu**: FR-010, SC-003, SC-004, SC-005, SC-007.

**Kiểm thử độc lập**: `dax-run profile` so với bảng "Trước khi sửa" ở T001.

- [X] T021 [US3] Chạy lại `dax-run profile` bốn trang như T001, ghi vào `measurements.md` bảng "Sau". Kiểm: không trang nào chậm quá 10% (SC-004); D1 song song không chậm hơn số đo ở T001 và đạt ngưỡng đã chốt ở T006 (SC-007).
- [X] T022 [US3] Đo bộ nhớ đỉnh trang D1 bằng `/usr/bin/time -l`, so với T001: không tăng quá 25% (SC-005).
- [X] T023 [US3] Đo hai truy vấn mục tiêu khi có slicer năm lọc một năm (sao `D1-combo-thauchi.dax` và `D1-matrix-gio-thu.dax` vào `build/e3-out/`, thêm vào `__DS0FilterTable` điều kiện `'Dim_Date'[year] IN {2024}` hoặc một năm có dữ liệu, chạy bằng `dax-run query`; so byte giữa `overrideEnabled` tắt và bật), trung vị 5 lần dưới 1,0 s (SC-003).

## Giai đoạn 6: Hoàn thiện

- [X] T024 Cập nhật `docs/phase-c-evidence/C1.md` §1.5: thêm bảng "Sau E3-cấu-trúc" (trước/sau cho combo thấu chi, matrix, matrix mở nút, combo kênh) và chẩn đoán cuối; ghi rõ mục nào còn [SUY ĐOÁN].
- [X] T025 Dọn mã thử nghiệm T004: xoá `BatchedSpikeTests.swift` hoặc chuyển phần còn dùng được thành test thường; `grep` không còn mã tạm.
- [X] T026 Chạy `zsh scripts/build-app.sh`, mở trang D1 trên app (chụp cửa sổ app theo quy tắc `screencapture -l`), kiểm combo và matrix hiện số đúng và nhanh; ghi kết quả vào `measurements.md`.
- [X] T027 Cập nhật `docs/STATE.md` (tiến độ, kết quả đo, việc tiếp theo) và chạy `/speckit-converge` để chắc không còn việc chưa làm. Kiểm FR-006 và FR-007: `git diff --stat` chỉ gồm file trong danh sách của `plan.md`, `Package.swift` và `Package.resolved` không đổi. Báo bạn kết quả; chỉ commit khi bạn bảo.

## Phụ thuộc và thứ tự

- Giai đoạn 1 → Giai đoạn 2 (cổng T006) → Giai đoạn 3 → Giai đoạn 4 → Giai đoạn 5 → Giai đoạn 6.
- T004 và T005 làm độc lập được nhưng cùng một người (lead), nên làm lần lượt.
- Trong giai đoạn 3: T007 và T008 trước T009–T014; T009 → T010 → T011 → T012 → T013 → T014; T015 chỉ bắt đầu khi T005 xong.
- Giai đoạn 4 cần giai đoạn 3 xong; giai đoạn 5 cần giai đoạn 3 xong (có thể xen với giai đoạn 4).

## Chiến lược triển khai

- **MVP**: giai đoạn 1 đến 3 cho combo thấu chi (T015 matrix có thể làm sau nếu T005 cho thấy cần sửa lớn), kèm giai đoạn 4 để chắc khớp.
- **Từng bước**: sau T006 và sau mỗi điểm kiểm tra, báo bạn số đo.
- **Dừng và hỏi bạn** khi: kết quả cổng T006 trên 1,0 s; T016 vẫn ≥ 1,0 s sau hướng 2; test tương đương cho thấy khác biệt không giải thích được.

## Phase 7: Convergence

- [X] T028 Thêm test tương đương trên model nhỏ dựng tay (bộ nhớ, `InMemoryColumnSource`) trong `Tests/DAXEngineTests/PERF/BatchedIterationTests.swift` cho các trường hợp biên của spec: hai dòng cùng giá trị cột lọc `t` trong một nhóm, nhóm có mọi `t` BLANK (đường gộp phải bỏ cuộc và chạy đường cũ: `takenCount` không tăng), nhóm rỗng, `balance_after` BLANK ở dòng thắng per US2 / T008 (partial)
- [X] T029 Thêm vào `Tests/DAXEngineTests/PERF/BatchedIterationTests.swift` một measure bọc `ALLSELECTED` và một measure lặp lồng hai cấp (SUMX ngoài, đường gộp trong), so hai đường ở các ngữ cảnh đã có per US2 / T008 (partial)
- [X] T030 Thêm test hợp đồng C4 trong `Tests/DAXEngineTests/PERF/BatchedIterationTests.swift`: truy vấn bị huỷ ngay (`Task.cancel()` trước khi chạy và giữa chừng) phải ném `.cancelled` khi đường gộp bật; một thân lỗi kiểu (cột chuỗi) phải ra đúng lỗi của đường cũ per Contract C4 (partial)
- [X] T031 Xin bạn duyệt các file ngoài danh sách plan đã sửa: `Sources/ColumnStore/ColumnData.swift` (thêm `ColumnIndex.sortRankTable()` công khai), `Sources/DAXEngine/Functions/Aggregation.swift` (`extremeOfColumn`), `Sources/DAXEngine/Runtime/FilterContext.swift` (`values(of:among:)`), `Sources/DAXEngine/Query/SummarizeColumns.swift` (`distinctEncodedTuples`); sau khi duyệt, ghi vào mục "Mã nguồn" của `plan.md`; nếu không duyệt thì hoàn lại và đo lại per plan: Source Code, FR-006 (unrequested)
- [X] T032 Ghi nhận và xin bạn xác nhận hai thay đổi ngoài phạm vi: test có sẵn `huyTruyVanNangDungNhanh` (`Tests/DAXEngineTests/ORA/ORAGoldenTests.swift`, đổi khối lượng thành lặp truy vấn đến khi bị huỷ, xem `research.md` R9 mục 4) và `Sources/DAXTestSupport/Fixtures.swift` (`DAXFixtures.nhom6` tự tìm `bipro-golden/Nhom6_work.pbix`, đọc `BIPRO_NHOM6`) per FR-006 / Constitution IV (unrequested)
- [X] T033 Đồng bộ `data-model.md` và `research.md` R2 với cài đặt thực: `BatchedShape` có `first`, `second`, `modifiers` (không có `steps` hay `finalStep`), thực thể `GroupedResult` chưa tồn tại (thay bằng mảng `[Value]` theo dòng bảng lặp), chỉ MAX/MIN per plan: data-model (partial)
- [X] T034 Sau T028–T033: chạy lại `swift test` và golden nặng (`BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --filter "Nhom6|ORA|VIS"`), `zsh scripts/e3-loop.sh`, rồi cập nhật `measurements.md` và `docs/STATE.md`; chỉ commit khi bạn bảo per SC-006 / T027 (partial)
