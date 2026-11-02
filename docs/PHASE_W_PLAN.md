# Phase W: plan chi tiết

## Trạng thái (cập nhật 2026-10-31)

**Kết luận của người dùng:** Phase W ổn. Chi tiết gate W2–W4 chưa có báo cáo riêng trong phiên này (xem bảng).

| Mục | Kết quả | Ghi chú |
|---|---|---|
| W0 quan sát (ABF, ZIP, metadata) | ✅ | `docs/formats/` và notes; dựng lại ABF khớp **từng byte** trên 3 file mẫu |
| Hợp đồng + stub | ✅ | `Writing/Contracts.swift`, bảng quyền `docs/phase-w-ownership.tsv`, kiểm tra `scripts/check-ownership.sh` |
| Pilot WP1 + WP2 | ✅ | 0 vi phạm quyền sở hữu, build xanh ngay khi gộp |
| Wave 1b WP3 + WP4 | ✅ | 0 vi phạm, build xanh ngay khi gộp |
| WP5 VertiPaq (timebox) | ✅ offline, ⏳ Power BI | BiProTest 100/100 dòng giải mã đúng; chờ test VM |
| Lắp ghép `PBIXWriter` + CLI | ✅ | `roundtrip`, `set-title`, `add-measure`; ghi tạm → đọc lại → thay file |
| Gate W1 (ghi lại không đổi) | ✅ người dùng xác nhận: mở được, dữ liệu nạp đủ | `tuan6.2` không có visual nên dashboard trống là đúng như file gốc |
| Gate W2 (sửa tiêu đề, T1) | ⏳ test tay trên VM | `build/w-out/W2/` |
| Gate W3 (thêm measure, T2) | ⏳ test tay trên VM | `build/w-out/W3/` |
| Gate W4 (bảng mới, T3) | ⏳ test tay trên VM | `build/w-out/W4/`, rủi ro cao nhất |

Tổng test: **62/62 pass**, build không lỗi.

### Thay đổi so với kế hoạch gốc
- **Không `git init`.** Thay bằng sandbox sao chép (`cp -R`), mỗi agent làm việc riêng, lead gộp file theo quyền sở hữu. Không cần git, và vẫn có kiểm tra vi phạm.
- **Encoder XPress9 cần nhiều file hơn "2 file":** thêm `Xpress9Lz77EncInsert.i`, `Pass1.i`, `Pass2.i`, `Xpress9ZobristTable.h`. Đã ghi trong `Sources/CXPress9/VENDORED.md`.
- **Chế độ encoder:** dùng **một session** cho cả luồng. Encoder mới cho mỗi chunk bị decoder hiện có từ chối (`BlockIndex` lệch), nên không dùng.
- **Kích thước khác Power BI:** tuan6.2 +2.4%, Nhom6 −0.45%. Payload không khớp byte, nhưng decoder đọc đúng.
- **Bảng quyền sở hữu** được bổ sung `TableMetadataWriter.swift` (WP5) sau khi phát hiện lỗi kiểm tra.
- **`ZipWriter` không chép 28 byte extra** ở local header. Nếu Power BI từ chối W2, đây là chỗ đầu tiên phải kiểm tra.
- **Ghi ABF:** timestamp (`LastWriteTime`) của VD và LOG đặt thành thời điểm hiện tại khi nội dung đổi.

### Điểm chưa biết cần Power BI xác nhận
1. Chấp nhận ABF có `LastWriteTime` mới và file mới đặt trước LOG (W1, W3).
2. Chấp nhận luồng XPress9 một session khác byte với Power BI (W1).
3. `DataType` mặc định của measure là 8 (double). `COUNTROWS` có thể cần 6 (int64). Kiểm tra trong W3.
4. Bảng mới không có H$, hidx, bảng hệ thống, và partition không có truy vấn M (W4). Đừng bấm Refresh trước khi báo cáo.
5. Có cần cập nhật `Table.ModifiedTime`, `DBPROPERTIES.LASTCOMMITTED` khi thêm measure (`MetadataWriter.updateTimestamps` mặc định tắt). Cần file R2 do bạn làm trong Power BI để so sánh.
6. Mapping `Measure.DataType` (2 = string, 6 = int64, 8 = double) là suy đoán từ measure có sẵn.

### Cách bạn test
Xem `CHECKLIST.md` trong từng thư mục `build/w-out/W1..W4`. Thứ tự: **W1 tuan6.2 → W2 → W3 → W4**. Nhom6 W1 là file lớn, test sau. Ảnh chụp bỏ vào `docs/phase-w-evidence/<W>/`.

---

 (ghi `.pbix`) và cách chia việc cho agent chạy song song

> **Test trên VM Windows 11 do bạn tự làm tay.** Mình chuẩn bị file cần test và checklist (§6); bạn mở trong Power BI Desktop rồi báo lại đạt hay trượt.

## Bối cảnh

BI Pro đã chọn `.pbix` làm định dạng tài liệu, nên phải **ghi** được `.pbix`. Hiện PBIXKit mới chỉ đọc. Phase W là spike để biết Power BI Desktop có chấp nhận file do BI Pro ghi hay không, ở cả ba tầng: T1 (chỉ report), T2 (metadata), T3 (dữ liệu VertiPaq). Kết quả quyết định cách lưu cho Phase D, E, F.

Bạn còn muốn **thử nhiều cách chia việc** cho các agent chạy song song, rồi chọn cách tốt nhất dựa trên số liệu chứ không đoán.

## Những gì đã có và vừa kiểm tra (chỉ đọc)

- Bộ đọc: `ZipArchive.swift` (chỉ đọc; `payloadRange` đã public), `DataModelStream.swift` (giải nén single/multi‑thread), `ABFBackup.swift` (header XML ở byte 72..0x1000, virtual directory, backup log, trailer 4 byte khi `ErrorCode`), `ModelMetadata.swift` (`sqlite3_deserialize`), `VertiPaq.swift` (dictionary, IDF, idfmeta, Huffman).
- Encoder XPress9 (MIT, Microsoft) có sẵn ở `scratchpad/dl/gh-xpress9/src/Xpress9EncLz77.c`, `Xpress9EncHuffman.c`. Cách gọi mẫu nằm trong `Xpress9Wrapper.c` (`Xpress9EncoderCreate` → `StartSession` → `Attach` → `Compress` → `FetchCompressedData`). Mức nén 9, `m_uWindowSizeLog2` = 16 + (level − 6) × 2.
- **Cả ba file mẫu đều nén XPress9 một luồng (single‑threaded).** Writer chỉ cần ghi dạng này, không cần multithreaded.
- File nhỏ nhất `~/Downloads/tuan6.2.pbix` (160 KB, ABF 936 KB, 207 file) dùng để lặp nhanh. Nhom6 (90 MB) dùng cho test tải lớn.
- ABF có những file "lạ" phải giữ đúng: `<guid>.0.db.xml` (đường dẫn tuyệt đối tới `AnalysisServicesWorkspace`), `0.CryptKey.bin` (144 byte), các bảng `H$…` (POS_TO_ID / ID_TO_POS), `.hidx`.
- VM Parallels "Windows 11" đang tắt, điều khiển được bằng `prlctl` (`start`, `exec`, `capture`).
- Dự án **không phải git repo**, và `Package.swift` là file dùng chung. Đây là hai rủi ro chính khi chạy agent song song.

## 1. Gói việc (WP), có file riêng cho từng WP

Nguyên tắc: **mỗi file chỉ có một WP được sửa**. `Package.swift` và các API dùng chung do lead (mình) viết ở W0, nên các WP sau không đụng vào.

| WP | Nội dung | File sở hữu (mới hoặc sửa) | Tự kiểm tra (không cần VM) |
|---|---|---|---|
| **W0 Quan sát + hợp đồng** (lead, chạy tuần tự) | Dùng REA quan sát các file mẫu: kích thước chunk XPress9 thật (đọc u32 ở byte 102), toàn văn header XML, virtual directory, backup log (trường nào chứa size/thời gian/checksum?), `db.xml`, `CryptKey.bin`, `SecurityBindings`, thứ tự member ZIP, method, flag, thời gian, `[Content_Types].xml`. Viết stub API công khai cho mọi writer (thân hàm `throw .notImplemented`). Sửa `Package.swift` (thêm file encoder, link `z` cho CRC32). | `docs/formats/pbix-write-notes.md`, `Sources/PBIXKit/Writing/Contracts.swift`, `Package.swift` | `swift build` xanh với stub |
| **WP1 Encoder XPress9** | Vendor 2 file encoder. Thêm `cxpress9_encoder_create/encode_chunk/destroy`, dùng **một session cho cả stream** vì decoder dùng chung history window. Viết `DataModelStream.compress(abf, chunkSize:)` theo kích thước chunk quan sát ở W0. | `Sources/CXPress9/**`, `Sources/PBIXKit/Writing/DataModelStream+Write.swift` | compress → decompress khớp từng byte trên 3 fixture; Nhom6 dưới 5 s |
| **WP2 ZIP + PBIR (T1)** | `ZipWriter`: STORED + DEFLATE, CRC32, ZIP64 khi cần. **Chép nguyên byte nén** của member không đổi. Giữ nguyên thứ tự member. `PBIRPatch`: sửa tiêu đề một visual trong `visual.json`. | `Writing/ZipWriter.swift`, `Writing/PBIRPatch.swift`, `ZipArchive.swift` (thêm `rawPayload(of:)`) | ghi lại file khi không đổi gì → mọi member khớp byte, `unzip -t` OK, `PBIXFile` đọc được |
| **WP3 ABFWriter** | Dựng lại ABF từ `ABFBackup` cộng map `[path: Data]` thay thế/thêm: chữ ký 72 byte, trang header (cập nhật `m_cbOffsetHeader`, `DataSize`, `Files`), payload (căn lề như quan sát), virtual directory, backup log (size mới), trailer `ErrorCode`. | `Writing/ABFWriter.swift`, `ABFBackup.swift` (giữ lại XML gốc) | **identity: không đổi gì → ABF ra trùng từng byte với ABF gốc** trên 5 fixture; khi thay 1 file thì `ABFBackup` đọc lại đúng |
| **WP4 MetadataWriter (T2)** | Mở `metadata.sqlitedb` dạng ghi được (deserialize), `addMeasure(table:name:expression:formatString:displayFolder:)`. Đặt ID, `LineageTag`, `ModifiedTime` / `StructureModifiedTime` (FILETIME) đúng như Power BI làm (xem bản tham chiếu R2 ở §3). Serialize ra lại. | `Writing/MetadataWriter.swift` | `PRAGMA integrity_check` = ok; `ModelMetadata` đọc lại thấy measure; diff với R2 chỉ khác giá trị thời gian/GUID |
| **WP5 VertiPaqWriter (T3, nghiên cứu, timebox 3 ngày)** | Bảng mới 3 cột (int, double, string) khoảng 100 dòng: dictionary, IDF (bit‑pack, chưa RLE), idfmeta, `H$` POS_TO_ID/ID_TO_POS, RowNumber, cùng các dòng metadata (Table, Column, ColumnStorage, DictionaryStorage, Partition, Segment…). Làm theo đúng danh sách file trong bản tham chiếu R3. Dự phòng **WP5b**: bảng "Enter Data" (dữ liệu nằm trong biểu thức M). | `Writing/VertiPaqWriter.swift`, `Writing/EnterDataTable.swift` | `VertiPaq.decodeTable` của chính mình đọc lại ra đúng 100 dòng |
| **WP6 Ghép + CLI + test** (lead) | `PBIXWriter`: chọn tầng T1/T2/T3, ghi ra file tạm → đọc lại → so khớp → mới thay. `pbix-dump roundtrip | set-title | add-measure | add-table`. Test tích hợp tái dùng logic của `verify`. | `Writing/PBIXWriter.swift`, `Sources/pbix-dump/main.swift`, `Tests/PBIXKitTests/WriteTests.swift` | `swift test` xanh; `roundtrip` khớp distinct count trên 5 file |
| **WP7 Gói test tay** (lead) | Không tự động hoá VM. Mỗi gate, mình đưa vào `build/w-out/<gate>/` các file `.pbix` cần mở, kèm `CHECKLIST.md` (mở file nào, nhìn gì, chụp gì) | `build/w-out/**`, `docs/phase-w-evidence/` | — (bạn test) |

**Bản tham chiếu do chính Power BI tạo** (đúng quy tắc "quan sát Power BI trước rồi làm theo"). **Bạn làm tay** trong VM trên bản sao `tuan6.2.pbix`, khoảng 10 phút, mình đưa từng bước. Sau đó mình diff bằng REA (`inspect_sqlite_database`, `pbix-dump files`):
- **R1:** đổi tiêu đề 1 visual → Lưu thành `tuan6.2-R1.pbix`.
- **R2:** thêm measure `Test = COUNTROWS('Marketing')` → Lưu thành `-R2`.
- **R3:** Enter Data, bảng 3 cột × 100 dòng → Lưu thành `-R3`.

Bạn chép ba file này vào `~/Downloads/phase-w-ref/` (qua thư mục chia sẻ của Parallels).

## 2. Đồ thị phụ thuộc

```
W0 ──┬─ WP1 encoder ──┐
     ├─ WP2 ZIP+PBIR ─┼─────────────► gate W2 (T1: chỉ cần WP2)  ← tín hiệu sớm nhất
     ├─ WP3 ABFWriter ┼─► gate W1 (WP1+2+3+6) ─┬► gate W3 (+WP4, R2)
     ├─ WP4 metadata ─┘                         └► gate W4 (+WP5, R3)
     ├─ R1/R2/R3 (bạn làm tay trong VM, song song với wave 1)
     └─ WP5 (bắt đầu sau khi có R3)
   Mỗi gate: mình chuẩn bị file + checklist → bạn test tay trên VM → báo kết quả
```

Đường găng: W0 → WP3 (identity khớp byte là phần khó nhất của W1) → gate W1 → WP4 → gate W3.

## 3. So sánh các cách chia việc

Chấm điểm 1–5 (5 là tốt nhất). Số ngày là ước lượng thời gian thực tới khi W1–W3 đạt.

| Cách chia | Mô tả | Đường găng | Xung đột file | Rủi ro ghép | Chi phí context | Hợp quy tắc REA | Kết luận |
|---|---|---|---|---|---|---|---|
| **A. Theo tầng sản phẩm** | 3 agent: T1, T2, T3 | ~6 ngày (cả ba cùng cần ZIP/ABF/XPress9, nên hoặc chờ nhau hoặc viết trùng) | 1 | 2 | 3 | 3 | Loại: phụ thuộc chéo |
| **B. Theo thành phần, có hợp đồng trước** | 1 agent/WP, API chốt ở W0 | ~3 ngày | 5 | 3 (test identity bắt lỗi ghép sớm) | 2 (5 agent khởi động từ đầu) | 3 | Tốt |
| **C. Tuần tự theo mốc** | 1 agent đi W1 → W4 | ~8 ngày | 5 | 5 | 5 | 4 | Phương án dự phòng |
| **D. Theo vai trò** | Quan sát (REA) / Viết code / Kiểm thử (VM) | ~5 ngày (người viết code phải chờ người quan sát) | 4 | 3 | 3 | 5 | Giữ ý: quan sát đi trước |
| **E. Lai B + D theo đợt** ✅ | W0 lead quan sát + hợp đồng; wave 1 có 4 agent (WP1–WP4); lead giữ VM + ghép; WP5 chạy sau R3 | ~3,5 ngày | 5 | 4 | 3 | 5 | **Chọn** |

Lý do chọn E: song song tối đa ở các phần lá (encoder, ZIP, ABF, metadata), và quan sát luôn đi trước code. Không agent nào chạm vào VM; test trên VM là việc bạn làm tay ở các gate. Tối đa 4 agent cùng lúc (giới hạn workflow "small", dưới 5).

## 4. Thử cách chia trước khi làm thật

Hai lớp kiểm tra, chạy trước khi tăng số agent.

**4.1 Kiểm tra tĩnh (chạy ngay sau W0, tốn vài giây):** `scripts/check-ownership.sh` đọc bảng sở hữu (`docs/phase-w-ownership.tsv`: WP → glob file), rồi báo lỗi nếu (a) một file thuộc hai WP, hoặc (b) một WP sửa file ngoài phần của mình. Cách so: snapshot `shasum` trước và sau mỗi wave, hoặc `git diff --name-only` nếu bật git.

**4.2 Pilot thực nghiệm (wave 1a):** chạy trước **2 WP rủi ro thấp là WP1 + WP2** song song, mỗi agent ở một worktree riêng. Đo:

| Chỉ số | Ngưỡng đạt |
|---|---|
| Sửa file ngoài phần sở hữu | 0 |
| Build/test sau khi ghép | xanh ngay lần đầu |
| Phải sửa API đã chốt | ≤ 1 lần |
| Thời gian thực so với ước lượng | ≤ 1,5 lần |
| Câu hỏi agent hỏi lại lead | ≤ 2 |

- **Đạt** → wave 1b thêm WP3 + WP4 (4 agent), giữ nguyên cách E.
- **Trượt vì xung đột hoặc build vỡ** → chuyển các WP còn lại sang cách C (tuần tự). Ghi số liệu vào `docs/PHASE_W_PLAN.md` mục "Kết quả thử cách chia".
- **Trượt vì API sai** → lead sửa `Contracts.swift`, rồi chạy lại pilot một lần.

**Điều kiện để chạy song song an toàn** (đưa vào bước đầu sau khi duyệt):
- `git init` cục bộ cùng một commit gốc. Không push đi đâu, chỉ để mỗi agent có worktree riêng (`isolation: "worktree"`) và có diff.
- Lý do: các lệnh `swift build` chạy cùng lúc trong một thư mục sẽ khoá `.build` của nhau, và không có git thì không ghép được an toàn.
- Nếu bạn không muốn git: mỗi agent dùng `swift build --scratch-path .build-<wp>` và kiểm tra quyền sở hữu bằng snapshot `shasum`.

## 5. Lịch chạy

| Đợt | Việc | Song song | Ước lượng |
|---|---|---|---|
| 0 | `git init`; W0 quan sát + hợp đồng + bảng sở hữu; kiểm tra tĩnh 4.1 | lead | 0,5–1 ngày |
| 1a (pilot) | WP1, WP2 · bạn làm R1–R3 trong VM | 2 agent | 1 ngày |
| 1b | WP3, WP4 (cùng WP1/WP2 nếu chưa xong) | ≤ 4 agent | 1–2 ngày |
| Gate | Mình chuẩn bị file + checklist cho **W2** → **W1** → **W3**; **bạn test tay trên VM** và báo lại | tuần tự | tuỳ lịch của bạn |
| 2 | WP5 VertiPaqWriter (timebox 3 ngày) → **W4**; nếu trượt thì WP5b Enter Data | 1 agent | ≤ 3 ngày |
| Chốt | cập nhật `BIPRO_BUILD_PLAN.md` (tầng nào khả thi, cách lưu cho D/E/F), memory | lead | 0,5 ngày |

Mỗi prompt giao cho agent gồm: WP, danh sách file được phép sửa, chữ ký API trong `Contracts.swift`, đường dẫn fixture (chỉ đọc), lệnh test tự kiểm, các ràng buộc: không decompile Power BI, chỉ dùng REA trên file của bạn, không đụng `SecurityBindings` ngoài việc chép nguyên byte, xuất file ra `build/w-out/`.

## 6. Checklist test tay trên VM (W1–W4, bạn làm)

Mình để file trong `build/w-out/<gate>/`; bạn mở trong Power BI Desktop trên VM. Với mỗi file:
1. Mở file → không có hộp thoại lỗi, trang report hiện ra, không yêu cầu Refresh. Chụp màn hình bỏ vào `docs/phase-w-evidence/`, hoặc gửi cho mình.
2. W1/W2: report giống file gốc; W2 thấy tiêu đề mới.
3. W3: một card dùng measure mới (sửa kết hợp T1 + T2) hiện đúng giá trị, khớp `COUNTROWS` đã biết của bảng `Marketing`.
4. W4: Data view có bảng mới, đủ 100 dòng.
5. **Bằng chứng mạnh nhất:** trong Power BI chọn Save As, rồi BI Pro đọc lại file Power BI vừa lưu. Điều này cho thấy Power BI đã chấp nhận và giữ nguyên nội dung.

Thử thêm hai biến thể `SecurityBindings`: giữ nguyên và bỏ đi, ghi lại kết quả cho trường hợp tạo file mới. Fixture gốc của bạn không bao giờ bị ghi đè; mọi file ra nằm trong `build/w-out/`.

## 7. Kiểm tra cuối

- `swift test`: test cũ 15/15 cộng `WriteTests` (identity ABF khớp byte, compress → decompress, ZIP raw copy, add‑measure đọc lại) trên 5 fixture.
- `pbix-dump roundtrip` trên 5 file: distinct count 308/308 cột khớp, metadata khớp.
- Ảnh chụp VM cho W1–W4 lưu ở `docs/phase-w-evidence/`, có bảng đạt/trượt trong `docs/PHASE_W_PLAN.md`.
- Phase W **xong khi** W1–W3 đạt. W4 trượt thì T3 dùng WP5b, và nghiên cứu VertiPaqWriter tiếp song song với Phase B–E.

## Cần bạn

- Cài Power BI Desktop trong VM Windows 11 (nếu chưa có).
- Làm tay R1–R3 trong VM (mình sẽ đưa từng bước), và test tay các gate W2, W1, W3, W4 theo checklist §6.
- Đồng ý `git init` cục bộ (khuyến nghị) hoặc chọn cách `--scratch-path`.
