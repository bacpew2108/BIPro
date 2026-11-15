# Chạy thử Phase E

Điều kiện: `~/Downloads/bipro-golden/Nhom6_work.pbix` (chỉ đọc; thử trên bản sao ở `build/e-out/`). Lệnh theo `CLAUDE.md`.

## Tự động

```sh
swift build
swift test --filter "ModelEdit|MetadataWriterUpdate|TMDLParser|Model"     # nhanh
BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --no-parallel --filter "Nhom6|ORA|VIS|Batched|E1"
```

Kỳ vọng: 30 golden Phase B và 72 truy vấn visual giữ nguyên khớp; test E1 (measure mới `= SUM(…)` cho số bằng DAX viết tay, quan hệ tạo lại cho số cũ).

## Trong app (`zsh scripts/build-app.sh`)

1. Mở bản sao Nhom6, Table View, chọn bảng, "Measure mới", nhập `Tổng = SUM(Fact_Loan[loan_amount])`, áp dụng: có trong ngăn Dữ liệu, kéo vào card ra số đúng; ⌘Z hai lần quay về.
2. Model View, chọn quan hệ `Fact_Loan[client_key] → Dim_Client[client_key]`, đổi hướng lọc sang hai chiều: visual dùng nó vẽ lại.
3. ⌘S, mở lại: giữ nguyên. `pbix-dump measures`/`relationships` thấy đúng.
4. Thử xoá measure đang được card dùng và đổi tên cột đang dùng: bị chặn kèm danh sách.

## Desktop (VM, cần bạn cho phép lần đó)

Mở file BI Pro lưu: không báo hỏng; measure đúng tên, biểu thức, thư mục; quan hệ đúng; card cùng số. Ghi vào `docs/phase-e-evidence/vm-e*/CHECKLIST-KET-QUA.md`; `.pbix` bằng chứng để ngoài git.
