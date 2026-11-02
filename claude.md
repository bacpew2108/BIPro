# BI Pro (PowerBINative)

## Về dự án

Đây là dự án xây dựng ứng dụng BI Pro, có các tính năng tương tự Power BI, viết bằng Swift/SwiftUI, chạy native trên macOS Apple Silicon.

## Cách làm

- Dùng skill REA (reverse-engineer-anything) để quan sát cách các chức năng của Power BI hoạt động, rồi tự xây dựng chức năng tương tự trong BI Pro.

- Ưu tiên SwiftUI và API native của Apple (Swift Charts, Metal khi cần hiệu năng). Không thêm thư viện bên ngoài nếu chưa hỏi tôi.
- Lệnh build/test của dự án: `swift build`; `swift test` (test thường); `BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --filter "Nhom6|ORA"` (golden Power BI trên Nhom6); `zsh scripts/build-app.sh` (đóng gói `build/BI Pro.app`). Nếu test sập SIGBUS sau khi đổi struct dùng chung giữa module thì xoá `.build` rồi build lại.
- Mỗi tính năng mới: ghi lại phần đã quan sát được từ Power BI (hành vi, đầu vào/đầu ra) ngắn gọn trước khi viết code, để review và để giao việc cho worker có mô tả rõ.

## Tự động giao việc cho Antigravity (agy) qua Orca

Tự giao việc cho agy khi việc thỏa TẤT CẢ:

- Tách được thành phần độc lập, chỉ đụng một nhóm file/thư mục riêng, không chung file với việc bạn đang làm hoặc worker khác.
- Đủ lớn: sửa từ 3 file trở lên, hoặc nhiều code lặp (giao diện, test, chuyển đổi hàng loạt).
- Yêu cầu đủ rõ để viết mô tả việc cụ thể.

Không giao khi: việc nhỏ, sửa lỗi nhanh, việc cần hiểu sâu ngữ cảnh, hoặc đụng file cấu hình, file bảo mật, `.env`.

Trước khi giao:

- `git status` phải sạch. Nếu có thay đổi dở thì hỏi tôi commit trước, vì worktree con chỉ có phần đã commit.
- Các worker phải sửa tập file KHÔNG giao nhau. Nếu không tách được thì làm tuần tự, đừng chạy song song.

Cách giao:

- Dùng skill orca-cli và orchestration. Mỗi việc một worktree con riêng, chạy `agy` trong đó.
- Tối đa 3 worker cùng lúc.
- Mô tả việc phải ghi: mục tiêu, file được sửa, "không sửa gì ngoài danh sách", lệnh build/test của project, tiêu chí xong việc (build qua, test liên quan qua, báo lại danh sách file đã sửa kèm tóm tắt ngắn).
- Worker không được commit, push, cài package hay tải từ mạng.
- `agy` chạy không tương tác: KHÔNG dùng `--dangerously-skip-permissions`. Cấp danh sách lệnh được phép (build, test, lệnh chỉ đọc) ngay lúc khởi động, vì một lệnh bị từ chối sẽ dừng cả phiên.

Khi worker chạy:

- Không kiểm tra lặp đi lặp lại. Chờ nền và đợi tất cả worker xong rồi review một lượt.

Khi worker xong:

- `git diff --stat` kiểm tra chỉ file được giao bị sửa; file ngoài phạm vi thì báo tôi.
- Đọc `git diff`, chạy build/test. Nếu chưa đạt, giao lại MỘT lần với phản hồi cụ thể; vẫn chưa đạt thì dừng và báo tôi.
- Báo tôi: kết quả từng worker, file đã đổi, việc còn tồn đọng. Không tự merge, không tự xóa worktree.

Dừng và báo tôi ngay (không tự thử lại nhiều lần, không tự đổi tài khoản) nếu worker lỗi, hết hạn mức, hoặc bị từ chối quyền lặp lại.