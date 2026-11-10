# Quan sát VM-D5 (2026-11-10, Claude điều khiển VM theo lời cho phép của người dùng)

Làm trên bản chép của `Nhom6_work.pbix` trong VM (Power BI Desktop 2.159.x). Mỗi bước Lưu thành một file; các file nối tiếp nhau (a1 → a2 → b → c → d → e). File: `R-D5-*.pbix` (không đưa vào git).

| Thao tác | Desktop ghi | File |
|---|---|---|
| Thêm trang (nút "+") | Thư mục `pages/<mã 20 hex>/` với `page.json` gồm `$schema` 2.1.0, `name`, `displayName` "Page 1", `displayOption` "FitToPage", `height` 1080, `width` 1920 (không có `objects`); mã vào **cuối** `pageOrder` dù trang đang mở là D3; `activePageName` = trang mới | `R-D5-a1` |
| Thêm trang lần hai | "Page 2" (đặt tên theo "Page " + số), cuối `pageOrder`, thành `activePageName` | `R-D5-a2` |
| Đổi tên (bấm đúp tab, gõ, Enter) | Chỉ `displayName` trong `page.json`; `activePageName` = trang đang mở khi lưu | `R-D5-b` |
| Đổi thứ tự (kéo tab) | Chỉ `pageOrder` đổi | `R-D5-c` |
| Nhân bản (menu chuột phải → Duplicate page) | Trang mới tên **"Duplicate of <tên>"**, mã mới, đặt ở **cuối** `pageOrder` (không ngay sau trang gốc), thành trang đang mở; `page.json` bằng trang gốc trừ `name` và `displayName`; **cả 36 visual có mã mới 20 hex**, cùng loại, vị trí, `z`; nút `Bookmark` vẫn trỏ cùng bookmark | `R-D5-d` |
| Xoá trang (menu chuột phải → Delete, có hộp thoại "If you save the report later, Power BI will permanently delete it") | Thư mục trang và mọi visual biến mất, mã bị bỏ khỏi `pageOrder`. **Bookmark không bị sửa**: hai bookmark vẫn có `activeSection` = trang đã xoá, `bookmarks.json` không đổi. Trong phiên, bấm bookmark mồ côi: không làm gì, không báo lỗi | `R-D5-e` |

Menu chuột phải tab: Set as landing page, Duplicate page, Rename, Delete, Hide, Move to. Không có Sang trái/Sang phải.

## Chưa quan sát

- Xoá trang có nút `PageNavigation` trỏ tới (Nhom6 không có; chưa tạo nút thử).
- Mở lại file sau khi xoá trang (bookmark mồ côi) trong Desktop; trong phiên không lỗi.
- Tên mặc định khi đã có "Page 1" bị xoá hoặc đổi tên; Set as landing page ghi vào đâu (có thể `activePageName`).

## Bổ sung (2026-11-10, sau khi làm xong code D5)

| Quan sát | Kết quả | File |
|---|---|---|
| Mở lại file Desktop đã lưu sau khi xoá trang (bookmark mồ côi) | Mở được, không lỗi; vào trang cuối (`activePageName`) | `R-D5-e-xoa-trang.pbix` |
| Nhân bản trang drillthrough (`d4_chinhanh`) | Desktop **sao cả `pageBinding`** (đổi `pageBinding.name`), `filterConfig` và `visibility` (vẫn ẩn), tên "Duplicate of …", 34 visual; BI Pro bỏ `pageBinding` có chủ ý (không tạo trang drillthrough thứ hai) và báo | `R-D5-f-nhan-ban-drill.pbix` |
| "Set as landing page" (trang D2) | Ghi khoá mới `landingPageName` vào `pages.json` (cạnh `activePageName`); không đổi trang nào khác | `R-D5-g-landing.pbix` |
| `Nhom6_d5.pbix` do BI Pro lưu | Mở được trong Desktop; đủ 5 tab đúng thứ tự, trang nhân bản vẽ như D1 (giữ bộ lọc cấp visual của matrix), Bookmarks pane trống, Save không lỗi | `CHECKLIST-KET-QUA.md` |

Còn chưa quan sát: xoá trang mà một nút `PageNavigation` trỏ tới (chưa tạo nút thử); BI Pro vẫn chặn trường hợp đó.
