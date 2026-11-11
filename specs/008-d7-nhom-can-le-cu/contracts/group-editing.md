# Hợp đồng: nhóm visual (PBIR)

**Nhóm (⌘G)** — vào: ≥ 2 mã visual cùng trang, không ai trong nhóm; ra: một `visual.json` nhóm và `parentGroupName` của con.

```
<new>/visual.json  = {"$schema": ".../visualContainer/2.14.0/schema.json", "name": "<20 hex>",
  "position": {"x": X, "y": Y, "z": Z, "height": H, "width": W, "tabOrder": Z},
  "visualGroup": {"displayName": "Group N", "groupMode": "ScaleMode"}}
con.visual.json: position.x -= X; position.y -= Y; thêm ,"parentGroupName":"<20 hex>" ngay trước dấu } cuối của đối tượng gốc
```
Khung (X, Y, W, H) = hộp bao các con; `Z` = max `z` con + 1. Số nguyên khi toạ độ nguyên, giữ số thập phân khi nguồn có.

**Bỏ nhóm** — nhóm bị xoá; con: `position.x += X`, `position.y += Y`, bỏ `parentGroupName` (và dấu phẩy trước nó).

**Di chuyển nhóm** — chỉ `position.x`, `position.y` của nhóm.

**Đổi cỡ nhóm** — `position.width`/`height` của nhóm đổi; mỗi con: `x, y, width, height` (tương đối) nhân `W'/W` (ngang) và `H'/H` (dọc).

**Từ chối** (không ghi): nhóm lồng, vùng chọn khác trang, vùng chọn có phần tử đã trong nhóm khác, nhóm của trang có `parentGroupName` trỏ không có thật.
