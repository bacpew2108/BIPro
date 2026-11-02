# Phase B, buổi 3: checklist ngắn cho người dùng

Chạy trong Power BI Desktop trên VM Windows 11, giống buổi 1 và 2. Bạn làm tay mọi bước.

**Thời lượng:** khoảng 10 phút, gồm 4 file.

**Lý do có buổi này:** ở buổi 2, G6f1 và G6f2 báo lỗi do **lỗi của gói truy vấn**, không phải lỗi thao tác. Script sinh truy vấn ghi `[Branch NPL Label]` thuộc `Fact_Loan`, trong khi measure này nằm ở `Dim_District`. Power BI từ chối là đúng. Gói đã được sửa. Buổi này thêm hai phép thử nhỏ cho hai điểm engine còn đang đoán.

## 0. Chuẩn bị trên Mac (1 phút)

Chạy trong Terminal (hoặc trong Claude Code, gõ tiền tố `!`):

```
mkdir -p ~/Downloads/bipro-golden/{pack3,nhom6,observe3}
cp ~/Desktop/PowerBINative/docs/phase-b-oracle/queries-buoi3/*.dax ~/Downloads/bipro-golden/pack3/
```

- Dùng lại `Nhom6_work.pbix`. Không mở file gốc.
- Xoá hoặc ghi đè hai file lỗi cũ `G6f1-district.error.tsv` và `G6f2-account-branch.error.tsv` trong `nhom6/` (không bắt buộc).

## 1. Cách chạy mỗi file (giống buổi 2)

1. Mở file `.dax` bằng Notepad, Ctrl+A, Ctrl+C.
2. DAX Query View: bấm **+** tạo tab mới, Ctrl+V, rồi **Run**.
3. Nếu thành công: bấm **Copy** ở thanh Results, dán vào Notepad mới, **Save As** `<tên file>.tsv`, Encoding **UTF-8**.
4. Nếu lỗi: copy thông báo lỗi và lưu `<tên file>.error.txt`.

## 2. Các file

| # | File (trong `pack3\`) | Lưu vào | Số dòng dự kiến | Ghi chú |
|---|---|---|---|---|
| 1 | `G6f1-district.dax` | `nhom6/G6f1-district.tsv` | 77 | Đây là truy vấn nặng. |
| 2 | `G6f2-account-branch.dax` | `nhom6/G6f2-account-branch.tsv` | 76 | Đây là truy vấn nặng. |
| 3 | `T5-edges.dax` | `nhom6/T5-edges.tsv` | 1 | Dùng để kiểm DATEADD trên khoảng lẻ kết thúc ở cuối tháng. |
| 4 | `O19-blank-zero-sort.dax` | `observe3/O19-blank-zero-sort.tsv` | 4 | Dùng để kiểm thứ tự giữa BLANK và 0. |

Xong rồi thì báo lại cho mình, kể cả khi có file lỗi.
