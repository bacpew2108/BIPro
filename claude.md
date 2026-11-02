## Tự động giao việc cho Antigravity (agy) qua Orca

Tự giao việc cho agy khi việc thỏa TẤT CẢ các điều kiện sau:

- Có thể tách thành phần độc lập, chỉ đụng một nhóm file hoặc thư mục riêng, không chung file với việc bạn đang làm.

- Đủ lớn: dự kiến sửa từ 3 file trở lên, hoặc cần viết nhiều code lặp (ví dụ giao diện, test, chuyển đổi hàng loạt).

- Đã có yêu cầu đủ rõ để viết mô tả việc cụ thể.

Không giao khi: việc nhỏ, sửa lỗi nhanh, việc cần hiểu sâu ngữ cảnh, hoặc đụng file cấu hình, file bảo mật, `.env`.

Cách giao:

- Dùng skill orca-cli và orchestration. Mỗi việc một worktree con riêng, chạy `agy` trong đó.

- Ghi rõ trong mô tả: được sửa file nào, không được sửa gì ngoài đó.

- Tối đa 2 worker chạy cùng lúc.

- Khi worker xong: đọc `git diff`, review. Nếu đạt thì báo tôi. Không tự merge, không tự xóa worktree.

- Nếu worker lỗi hoặc hết hạn mức: dừng và báo tôi, không tự chuyển tài khoản hay tự làm lại nhiều lần.