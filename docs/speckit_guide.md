# Hướng dẫn dùng Spec Kit với Claude Code — dự án PowerBINative

> Spec Kit (github/spec-kit) cung cấp quy trình Spec-Driven Development (SDD) cho coding agent: mô tả **làm gì / vì sao** trước, rồi chuyển thành plan → tasks → code → kiểm chứng. Tài liệu chính thức: [https://github.github.io/spec-kit/](https://github.github.io/spec-kit/)
>
> **Áp dụng cho BI Pro:** quy tắc ràng buộc nằm ở mục "Spec Kit" trong `CLAUDE.md` và ở `.specify/memory/constitution.md`. Nếu chỗ nào trong hướng dẫn này khác với hai file đó, làm theo hai file đó. Đặc biệt: implement của phần lớn thường giao cho agy qua `docs/tasks/`, và dự án không dùng `specify workflow run` (mục 6).

---

## 1. Cài đặt (đã làm)

```bash
uv tool install specify-cli

# Dự án mới
specify init my-project --integration claude

# Dự án có sẵn code (chạy ở thư mục gốc repo) — cách đã dùng cho PowerBINative
specify init --here --force --integration claude

```

- Script type trên macOS: chọn `sh`.
- `--force` cho phép init trong thư mục không rỗng, có thể ghi đè file trùng đường dẫn mà Spec Kit quản lý → **luôn commit/stash và tạo branch trước khi init**, sau đó xem `git diff`.
- Init tạo:
  - `.claude/skills/speckit-*/SKILL.md` — các lệnh dùng trong Claude Code
  - `.specify/` — `memory/` (chứa `constitution.md`), `templates/`, `scripts/`, `workflows/`, `integrations/`
- Commit phần setup riêng:

```bash
git add .claude .specify
git commit -m "chore: add Spec Kit for Claude Code"

```

**Tuỳ chọn:** nếu không muốn Claude tự gọi các skill Spec Kit (chỉ chạy khi mình gõ `/speckit-...`, đỡ tốn context):

```bash
specify init --here --force --integration claude --integration-options="--no-model-invocation"

```

---

## 2. Các lệnh (gõ trong Claude Code, không phải terminal)


| #   | Lệnh                     | Mục đích                                | Bắt buộc?                       |
| --- | ------------------------ | --------------------------------------- | ------------------------------- |
| 0   | `/speckit-constitution`  | Nguyên tắc chung của dự án              | Một lần cho cả dự án            |
| 1   | `/speckit-specify`       | Mô tả tính năng: làm gì, vì sao         | ✅                               |
| 2   | `/speckit-clarify`       | Claude hỏi lại chỗ mơ hồ                | Nên                             |
| 3   | `/speckit-plan`          | Kế hoạch kỹ thuật                       | ✅                               |
| 4   | `/speckit-checklist`     | Checklist chất lượng yêu cầu            | Tuỳ chọn                        |
| 5   | `/speckit-tasks`         | Chia thành task                         | ✅                               |
| 6   | `/speckit-analyze`       | Kiểm tra spec ↔ plan ↔ tasks có khớp    | Nên                             |
| 7   | `/speckit-implement`     | Viết code                               | ✅                               |
| 8   | `/speckit-converge`      | Đối chiếu code với spec, tìm phần thiếu | ✅ — lặp 7↔8 đến khi `Converged` |
| –   | `/speckit-taskstoissues` | Đẩy tasks lên GitHub Issues             | Tuỳ chọn                        |


Quy tắc: **chạy từng lệnh một, đọc file Markdown sinh ra trước khi sang bước tiếp.** Sửa ở spec/plan, đừng đợi sửa ở code.

---

## 3. Khi nào dùng Spec Kit


| Cỡ việc                              | Cách làm                                                      |
| ------------------------------------ | ------------------------------------------------------------- |
| Sửa nhỏ, vài dòng, chỉnh measure DAX | Nhờ Claude trực tiếp, không cần Spec Kit                      |
| Sửa lỗi                              | Extension `bug` (mục 7)                                       |
| Tính năng vừa                        | Vòng tối thiểu: specify → plan → tasks → implement → converge |
| Hạng mục lớn trong một phase         | Vòng đầy đủ, có clarify + analyze                             |


---

## 4. Phân vai: `docs/` và `specs/`

Dự án đã có hệ thống plan riêng (`PORTING_PLAN.md`, `PHASE_*_PLAN.md`, `phase-*-research/oracle/evidence/`, `*-ownership.tsv`, `STATE.md`, `tasks/`). Spec Kit **không thay thế** hệ thống này.


| Nơi                             | Vai trò                                                                           | Cấp                                          |
| ------------------------------- | --------------------------------------------------------------------------------- | -------------------------------------------- |
| `docs/`                         | Roadmap: tầm nhìn, phase, thứ tự, trạng thái tổng (`STATE.md`) | **Cấp trên** — quyết định làm gì, thứ tự nào |
| `specs/NNN-.../` (Spec Kit tạo) | Chi tiết từng lát việc: spec, plan, tasks                                         | **Cấp dưới** — làm thế nào                   |


- Mâu thuẫn giữa hai bên → **sửa plan phase trong** `docs/` **trước**, rồi chạy lại spec.
- Không viết spec ngược cho các phase/hạng mục đã hoàn thành.
- Nếu một phase đã chi tiết tới mức task và Claude làm tốt theo đó, có thể chỉ dùng `/speckit-analyze` + `/speckit-converge` để kiểm chứng thay vì chạy cả vòng.

---

## 5. Quy trình theo phase

### Bước 0 — Constitution (một lần cho dự án)

Rút từ tài liệu có sẵn, không bịa thêm:

```
/speckit-constitution Đọc docs/PORTING_PLAN.md, docs/STATE.md và các docs/PHASE_*_PLAN.md. Chỉ rút ra những nguyên tắc dự án đang thực sự áp dụng (cách port, cách kiểm chứng bằng oracle/evidence, quy ước ownership). Không thêm nguyên tắc mới.

```

Đọc lại `.specify/memory/constitution.md`, sửa tay nếu cần.

### Bước 1 — Chia phase thành lát (một lần cho mỗi phase)

Gõ thường trong Claude, chưa dùng lệnh speckit:

```
Đọc docs/PHASE_C_PLAN.md và docs/STATE.md. Liệt kê các hạng mục CHƯA làm của Phase C, chia thành các lát nhỏ, mỗi lát làm và kiểm chứng độc lập được. Sắp theo thứ tự phụ thuộc. Chưa viết code.

```

Duyệt danh sách, ghi vào `PHASE_C_PLAN.md` hoặc `STATE.md`.

> Phase nhỏ (chỉ vài việc) → bỏ bước này, cả phase là một spec.

### Bước 2 — Mỗi lát một vòng Spec Kit

```
/speckit-specify [Phase C – lát 1] <tên hạng mục>. Nguồn: docs/PHASE_C_PLAN.md mục <X>, research ở docs/phase-c-research/. Tiêu chí xong: khớp oracle trong docs/phase-c-oracle/. Không đụng phần Phase B đã hoàn thành.
/speckit-clarify
/speckit-plan Bám theo docs/PHASE_C_PLAN.md, chỉ chi tiết hoá, không đề xuất kiến trúc khác.
/speckit-tasks
/speckit-analyze
/speckit-implement
/speckit-converge

```

Mẹo khi viết `/speckit-specify`:

- Ghi rõ **phase + lát** để truy vết.
- Ghi rõ **nguồn** (file plan, research) và **tiêu chí xong** (oracle).
- Ghi rõ **cái phải giữ nguyên** (phase cũ, API/data model đang dùng).

### Bước 3 — Đóng lát

```
Cập nhật docs/STATE.md và docs/PHASE_C_PLAN.md: đánh dấu lát 1 hoàn thành, ghi đường dẫn tới specs/<thư mục vừa tạo>, lưu evidence vào docs/phase-c-evidence/.

```

Commit theo lát:

```bash
git add -A
git commit -m "feat(phase-c): lát 1 — <tên hạng mục>"

```

Lặp bước 2–3 cho các lát tiếp theo. Hết phase → sang phase sau, bắt đầu lại từ bước 1.

---

## 6. Chạy tự động bằng workflow (khi đã quen)

> **BI Pro không dùng mục này.** Workflow chạy `claude -p` qua cả bước implement mà không có cổng review, trái với quy tắc giao việc và review trong `CLAUDE.md`. Phần dưới chỉ để tham khảo.

Chạy từ **terminal**:

```bash
specify workflow list                                  # kiểm tra workflow speckit
specify workflow run speckit -i spec="[Phase C – lát 2] <mô tả như ở bước 2>"

```

- Tự chạy: specify → **duyệt spec** → plan → **duyệt plan** → tasks → implement.
- Mỗi bước gọi Claude Code không tương tác (`claude -p`).
- Tại 2 cổng duyệt, workflow dừng chờ approve/reject. Bị ngắt thì:

```bash
specify workflow status            # xem các lần chạy
specify workflow resume <run_id>   # chạy tiếp

```

- Workflow **không** gồm constitution, clarify, analyze, converge → sau khi xong vẫn vào Claude chạy `/speckit-converge`, rồi đóng lát (bước 3).

---

## 7. Sửa lỗi bằng extension `bug`

```bash
specify extension add bug

```

Trong Claude:

```
/speckit-bug-assess "<mô tả lỗi>" slug=<ten-loi>
/speckit-bug-fix slug=<ten-loi>
/speckit-bug-test slug=<ten-loi>

```

Báo cáo nằm ở `.specify/bugs/<ten-loi>/`. Kết quả `verified` / `partial` / `failed` — chỉ `verified` là đã sửa xong.

---

## 8. Checklist nhanh mỗi lát

- [ ] Working tree sạch, đang ở branch phù hợp
- [ ] Lát nằm trong plan phase, chưa có trong `STATE.md` là đã xong
- [ ] `/speckit-specify` có: phase + lát, nguồn, tiêu chí xong, cái giữ nguyên
- [ ] Đã đọc & duyệt `spec.md`, `plan.md`, `tasks.md`
- [ ] `/speckit-converge` báo `Converged`
- [ ] Đã khớp oracle, lưu evidence
- [ ] Cập nhật `STATE.md` + plan phase, commit

---

## 9. Lưu ý

- Không sửa tay các file skill Spec Kit sinh ra trong `.claude/skills/`; muốn tuỳ biến thì dùng preset hoặc project-local override.
- Không dùng Spec Kit cho việc nhỏ — quy trình đầy đủ chỉ đáng khi viết spec trước tiết kiệm công sửa sau.
- Nâng cấp: xem [https://github.github.io/spec-kit/upgrade.html](https://github.github.io/spec-kit/upgrade.html)
