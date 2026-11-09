# Hợp đồng: tương đương giữa đường gộp và đường từng dòng

Engine không có giao diện ngoài mới. Hợp đồng này là cam kết nội bộ mà test kiểm.

## C1. Công tắc

- Biến môi trường `BIPRO_BATCH`: `0` tắt đường gộp (mọi vòng lặp chạy như trước E3-cấu-trúc); không đặt hoặc `1` bật.
- Test trong cùng một tiến trình không đổi biến môi trường: `BatchedIteration` có biến ghi đè (`overrideEnabled`, `nil` = theo biến môi trường) để test bật/tắt từng lần chạy.
- Mặc định bật. Công tắc tồn tại cho test và để chẩn đoán, không là cấu hình người dùng.

## C2. Tương đương

Với mọi truy vấn Q, mọi model M và mọi ngữ cảnh lọc: `kết quả(Q, M, BATCH=1)` bằng `kết quả(Q, M, BATCH=0)` từng byte (cùng giá trị, cùng BLANK, cùng thứ tự dòng, cùng lỗi).

## C3. Nhận mẫu bảo thủ

Đường gộp chỉ chạy khi `BatchedShape` hợp lệ (xem `data-model.md` và R2 trong `research.md`). Mọi nghi ngờ rơi về đường cũ. Không có nhánh cho "gần đúng".

## C4. Huỷ và lỗi

- Kiểm tra `checkCancelled` định kỳ trong vòng quét (mỗi vài nghìn dòng như `computeTransitionRows`).
- Lỗi trong đường gộp (bất kỳ) phải ra cùng lỗi như đường cũ, hoặc đường gộp bỏ cuộc và chạy đường cũ để sinh lỗi đó.

## C5. Đa luồng

`SUMMARIZECOLUMNS` chạy ô song song, mỗi luồng một `Evaluator` dùng chung cache. Đường gộp không giữ trạng thái chia sẻ có thể ghi (ngoài cache đã an toàn luồng).

## Kiểm thử hợp đồng

| Hợp đồng | Kiểm bằng |
|---|---|
| C1, C2 | `BatchedIterationTests`: chạy hai chế độ trên Nhom6 (3 truy vấn đo, 72 truy vấn visual) và trên dữ liệu nhỏ có nhóm rỗng, `t` BLANK, trùng giá trị |
| C3 | test nhận mẫu: mẫu đúng được nhận, 6–8 biến thể gần giống (KEEPFILTERS, phụ thuộc dòng, hàm khác) bị từ chối |
| C4 | `huyTruyVanNangDungNhanh` vẫn qua khi chạy một mình |
| C5 | chạy song song 8 luồng 20 lần, so byte |
