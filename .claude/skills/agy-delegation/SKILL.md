---
name: agy-delegation
description: Giao việc cho agy (Antigravity) qua Orca. Dùng khi viết brief docs/tasks/, khởi động worker agy, chờ worker, hoặc review kết quả worker.
---

Điều kiện giao và các điều cấm nằm ở `CLAUDE.md` (mục "Tự động giao việc cho Antigravity (agy) qua Orca"); đây là các bước thao tác.

## Cách giao

- Dùng skill orca-cli và orchestration. Mỗi việc một worktree con riêng, chạy `agy` trong đó.
- Ghi mô tả việc ra file `docs/tasks/<tên>.md`: mục tiêu, file được sửa, "không sửa gì ngoài danh sách", lệnh build/test của project, tiêu chí xong việc (build qua, test liên quan qua).
- Worker phải tự test đạt trước khi bàn giao (ghi vào brief, kèm lệnh cụ thể):
  - `swift build` không lỗi; `swift test` toàn bộ (không chỉ test mới) đều qua, trừ known issue đã ghi trong brief.
  - Viết test cho mọi tiêu chí xong việc trong brief, dùng dữ liệu mẫu hoặc golden thật; không hard-code kết quả, không sửa hay tắt test có sẵn để cho qua.
  - Việc đụng engine hoặc truy vấn: chạy thêm golden nặng (lệnh trong `CLAUDE.md`) và phải giữ nguyên số golden khớp.
  - Việc vẽ giao diện: xuất ảnh PNG vào `build/<phase>-out/` và tự mở xem ảnh không trống, không lỗi.
  - `git status` chỉ có file trong danh sách được sửa.
  - Chưa đạt thì tự sửa tiếp; không sửa được thì ghi rõ lý do trong báo cáo, không bàn giao như đã xong.
- Yêu cầu worker khi xong ghi báo cáo ngắn vào `docs/tasks/<tên>-report.md`: file đã sửa, tóm tắt thay đổi, lệnh test đã chạy kèm số test qua/trượt (chép dòng kết quả cuối), việc còn tồn đọng.
- Ghi vào brief: worker không được commit, push, cài package hay tải từ mạng.
- `agy` chạy không tương tác: cấp danh sách lệnh được phép (build, test, lệnh chỉ đọc) ngay lúc khởi động, vì một lệnh bị từ chối sẽ dừng cả phiên.

## Khi worker chạy

- Khởi động worker, rồi đặt MỘT lệnh nền (`run_in_background`) tự chờ trong shell đến khi jsonl của mọi worker có `"event":"result"`.
- Cập nhật `docs/STATE.md` (worker, nhánh, đường dẫn jsonl, việc review cần làm), báo tôi, nhắc tôi gõ `/compact`, rồi KẾT THÚC lượt. Claude không tự compact được; compact để lượt review không phải đọc lại context dài.
- Khi lệnh nền báo xong, review ngay trong phiên đó, dựa trên `docs/STATE.md` và `docs/tasks/`. Nếu phiên bị đóng, tôi mở phiên mới và review theo cùng các file đó.

## Khi review

- `git diff --stat` kiểm tra chỉ file được giao bị sửa; file ngoài phạm vi thì báo tôi.
- Đọc báo cáo của worker, đọc `git diff`, chạy build/test. Nếu chưa đạt, giao lại MỘT lần với phản hồi cụ thể; vẫn chưa đạt thì dừng và báo tôi.
- Báo tôi: kết quả từng worker, file đã đổi, việc còn tồn đọng.
