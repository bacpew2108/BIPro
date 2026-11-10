# Kết quả kiểm `Nhom6_d3.pbix` trên VM (2026-11-10)

Làm bởi Claude theo lời cho phép của người dùng cho lần này (ngoại lệ một lần của quy tắc "agent không điều khiển VM"): chép file vào `C:\Users\bacpew\vmd3\` trong VM (không mở trực tiếp trên thư mục Mac), mở bằng Power BI Desktop 2.159.x, chụp màn hình cửa sổ Parallels. Không lưu gì từ Desktop.

| Mục | Kết quả | Ghi chú |
|---|---|---|
| 1. Mở file | Đạt | Không hộp thoại lỗi, không "repair" |
| 2. Đủ 4 trang, dữ liệu nạp | Đạt | D1, D2, D3, "Chi tiết chi nhánh" (ẩn); D2, D3 vẽ bình thường |
| 3. Card mới | Đạt | $197M, nhãn Net_Cashflow; nằm dưới biểu đồ thanh mới (z thứ hai) nên bị che ở giữa trang |
| 4. Thanh nhóm mới | Đạt | Tháng theo Total_Credit_Inflow vẽ được |
| 5. Đường → thanh nhóm | Đạt | Vẽ được, không báo lỗi trường |
| 6. Combo → đường | Đạt | Vẽ được; Y2 đã gộp vào Y |
| 7. Donut → treemap | Đạt | Credit/Debit vẽ được |
| 8. Hộp văn bản | Đạt | "D1 · PHÂN TÍCH GIAO DỊCH (đã sửa chữ)", dòng đầu chữ trắng đậm |
| 9. Bookmark | Đạt | Còn 2 bookmark; bấm cả hai không báo lỗi; D2, D3 vẽ bình thường |
| 10. So số với BI Pro | Chưa làm | Cần mở cùng file trong BI Pro và so |
| 11. Bấm Save trong Desktop | Chưa làm | Cố ý không lưu |

Ảnh: `checklist-d1-mo-file.png` (trang D1 khi mở), `checklist-d1-an-thanh-moi.png` (đã tạm ẩn thanh mới trong Selection pane để thấy card và treemap; chỉ trong phiên, không lưu).
