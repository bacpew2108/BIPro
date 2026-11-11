# Mô hình dữ liệu D7

- **`ReportVisual.parentGroup: String?`** (PBIXKit, mới): mã nhóm chứa nó. Với PBIR, `x`, `y` là **toạ độ tuyệt đối** (file tương đối + `x,y` nhóm).
- **`ReportGroup`** hoặc `ReportVisual(type: "visualGroup")`: mã, `displayName`, khung, `z`. Nằm trong danh sách visual của trang, không vẽ, không có truy vấn.
- **`PageEdit`** (BIPro): thêm tập mã nhóm mới chưa có trong file và `visual.json` nhóm sinh ra (qua `added`); `extraParts` (D5) vẫn dành cho nhóm của trang nhân bản.
- **`AlignCommand`** (BIPro): `left, centerH, right, top, middleV, bottom, distributeH, distributeV`.
- **Bộ nhớ chép**: như D1 (`clipboard`), thêm cờ "đã dán lần thứ n" để lệch +10n.
- **Định dạng cũ**: `LegacyLayout` (PBIXKit): văn bản đã giải mã, danh sách vị trí của từng container (khoảng byte của `x,y,z,width,height`, của chuỗi `config`, của `layouts[0].position` trong chuỗi), để ghép byte.
- **`PBIXChanges`**: không đổi; `reportParts["Report/Layout"]` giữ byte mới.
