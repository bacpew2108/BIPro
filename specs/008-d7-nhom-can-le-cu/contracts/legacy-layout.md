# Hợp đồng: ghép byte `Report/Layout` (định dạng cũ)

Vào: bytes `Report/Layout` (UTF-16LE), danh sách sửa `{section, containerName, x?, y?, width?, height?, z?}`, danh sách xoá, danh sách thêm (bản sao của một container với tên mới và vị trí mới). Ra: bytes mới.

1. Giải mã UTF-16LE (không BOM); giữ cách mã hoá nếu có BOM.
2. Với mỗi container sửa: thay số của `x,y,z,width,height` ở cấp container và số tương ứng trong `config.layouts[0].position` (trong chuỗi `config` đã giải thoát, thoát lại); `tabOrder` đặt = `z` ở cả hai chỗ khi `z` đổi.
3. Xoá: bỏ nguyên phần tử khỏi mảng `visualContainers`. Thêm: chèn bản sao ở cuối mảng của section, `config.name` mới (20 hex).
4. Kiểm: parse lại; `escape(unescape(config))` của mọi `config` chưa sửa bằng nguyên văn; số container và toạ độ khớp ý định; phần ngoài vùng sửa khớp byte; không khớp → ném lỗi, không ghi.
