**BI Pro (PowerBINative)**

**Về dự án** Đây là dự án xây dựng ứng dụng BI Pro, có các tính năng tương tự Power BI, viết bằng Swift/SwiftUI, chạy native trên macOS Apple Silicon.

**Cách làm**

- Dùng skill REA (reverse-engineer-anything) để quan sát cách các chức năng của Power BI hoạt động, rồi tự xây dựng chức năng tương tự trong BI Pro.

- Ưu tiên SwiftUI và API native của Apple (Swift Charts, Metal khi cần hiệu năng). Không thêm thư viện bên ngoài nếu chưa hỏi tôi.
- Lệnh build/test của dự án: `swift build`; `swift test` (test thường); `BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --filter "Nhom6|ORA|VIS"` (golden Power BI trên Nhom6, gồm truy vấn visual); `zsh scripts/[build-app.sh](http://build-app.sh)` (đóng gói `build/BI [Pro.app](http://Pro.app)`). Nếu test sập SIGBUS sau khi đổi struct dùng chung giữa module thì xoá `.build` rồi build lại.
- Mỗi tính năng mới: ghi lại phần đã quan sát được từ Power BI (hành vi, đầu vào/đầu ra) ngắn gọn trước khi viết code để review.

**Trạng thái làm việc**

- Giữ `docs/[STATE.md](http://STATE.md)` ngắn gọn: mục tiêu và tiến độ, quyết định thiết kế đã chốt, lệnh build/test, việc tiếp theo.
- Cập nhật `docs/[STATE.md](http://STATE.md)` sau mỗi lần hoàn thành hoặc review xong. Không chép log dài vào đó.
- Đầu phiên mới, đọc `docs/[STATE.md](http://STATE.md)` trước khi làm gì khác.

**Spec Kit**

- Hướng dẫn: `docs/speckit_[guide.md](http://guide.md)`. Nguyên tắc: `.specify/memory/[constitution.md](http://constitution.md)` (tóm tắt từ file này; mâu thuẫn thì file này thắng và sửa constitution).
- Tự dùng Spec Kit, không cần tôi nhắc, khi bắt đầu một phase hoặc tính năng mới (việc nhỏ, sửa lỗi nhanh thì không). Không viết spec ngược cho phần đã xong. Chạy từng bước và dừng cho tôi duyệt ở 3 chỗ: sau specify + clarify ([`spec.md`](http://spec.md)), sau plan ([`plan.md`](http://plan.md)), sau tasks + analyze ([`tasks.md`](http://tasks.md)); chỉ implement khi tôi đã duyệt [`tasks.md`](http://tasks.md). Phase đã chi tiết tới mức task trong `docs/` (như Phase C) thì làm tiếp theo quy trình cũ; `/speckit-analyze` và `/speckit-converge` chỉ chạy được khi đã có `specs/NNN-…/` (spec, plan, tasks).
- `docs/` là cấp trên, `specs/` là cấp dưới. Mâu thuẫn thì sửa `docs/` trước. Viết spec, plan, tasks bằng tiếng Việt. Spec phải có mục "Quan sát Power BI" và tiêu chí khớp golden.
- Chạy specify → clarify → plan → tasks → analyze, sau đó dùng `/speckit-implement` để triển khai. Khi review, chạy thêm `/speckit-converge`.
- Không dùng `specify workflow run`, vì nó chạy `claude -p` qua cả bước implement mà không có cổng review.

**Skill mattpocock (dùng kèm Spec Kit)** Spec Kit là quy trình chính. Chỉ dùng 3 skill mattpocock, tự gọi khi gặp đúng tình huống:

- Sửa [`CLAUDE.md`](http://CLAUDE.md): `/writing-for-agents`.
- Khi viết code: `/tdd`.
- Lỗi khó hoặc chậm (như hiệu năng engine): `/diagnosing-bugs`.

Review dùng `/code-review` có sẵn của Claude Code, cộng `/speckit-converge` khi đã có `specs/`. Không dùng skill mattpocock nào khác (trạng thái nằm ở `docs/[STATE.md](http://STATE.md)`, không dùng `/handoff`). `/retro` và `/wait-what` do tôi tự gõ khi cần.

**Compact Instructions** Khi compact, giữ: mục tiêu, quyết định thiết kế, lệnh build, đường dẫn `docs/[STATE.md](http://STATE.md)`. Bỏ log dài, kết quả lệnh cũ.
