Bạn là một lập trình viên Swift làm việc trong repo "BI Pro" (ứng dụng macOS native giống Power BI Desktop, SwiftUI + AppKit, macOS 15, Apple Silicon), trong một git worktree riêng. Việc của bạn là **thực thi toàn bộ Phase H (v1.3): đưa giao diện BI Pro về giống Power BI Desktop 2.159**, trọng tâm là thanh Ribbon. Mọi thiết kế, quan sát, danh sách tác vụ đã có sẵn trong repo; bạn **chỉ cài đặt theo đó**, không tự thiết kế lại. Chữ hiển thị trong app có cả tiếng Việt và tiếng Anh (hàm `bi("vi","en")` và `L10n`). Không thêm package, không tải gì từ mạng, không dùng phông chữ ngoài.

## 0. Bạn không được làm gì (vi phạm là dừng)

- Không `git commit`, `git push`, `git checkout`, `git reset`, `git stash`, không tạo/xoá nhánh. Chỉ để thay đổi ở working tree; lead sẽ commit.
- Không cài package, không chạy `pip`/`npm`/`brew`, không `curl`, không gọi mạng. Không sửa `Package.swift`.
- Không dùng `&&`, `;`, `|`, `>`, `$(…)` trong lệnh shell; không dùng `rm`, `cp`, `mv`, `mkdir`, `python`, `cd`, `sed`, `awk`, `touch`. Mỗi lệnh là MỘT lệnh đơn trong danh sách được phép ở mục 3. Lệnh không có trong danh sách sẽ bị từ chối và **một lần từ chối làm cả phiên dừng**. Cần tạo tệp/thư mục thì dùng công cụ ghi tệp (tạo thư mục sẽ tự có khi ghi tệp vào), hoặc để test tự tạo bằng `FileManager`.
- Không sửa, không xoá, không tắt, không đổi kỳ vọng của bất kỳ test **đã có** để cho qua. Chỉ được sửa test đã có khi tác vụ trong `tasks.md` nói rõ (T021, T037) và chỉ phần liên quan đến Ribbon/tab; mọi kiểm hành vi phải giữ nguyên.
- Không hard-code kết quả để test qua. Dữ liệu chuẩn trong test (`RibbonReference.swift`) phải viết tay từ `contracts/ribbon-catalog.md`, KHÔNG sinh từ catalog đang test.
- **Cấm sửa** (xem `docs/phase-h-ownership.tsv`, dòng OFF-LIMITS): `Sources/PBIXKit/**`, `Sources/ColumnStore/**`, `Sources/DAXEngine/**`, `Sources/Connectors/**`, `Sources/MEngine/**`, `Package.swift`, mọi test của các module đó, mọi tệp `.pbix`, `build/d-out/**`. Mở rồi lưu `.pbix` phải không đổi byte.
- Không sao chép các chi tiết trang trí trong ảnh mà không có tính năng thật (thẻ "DirectLake", nút "Certified", ô sắp xếp chết…). Nút Power BI mà BI Pro chưa có tính năng thì hiện **vô hiệu có tooltip**, đúng như `contracts/ribbon-catalog.md`, tuyệt đối không hiện như đang bật.
- Không điều khiển máy ảo Windows, không chụp Power BI Desktop. Phần đó là việc của con người (T086).

## 1. Đọc trước, theo thứ tự (đã có, đọc kỹ rồi mới viết mã)

1. `CLAUDE.md` và `.specify/memory/constitution.md` (v1.2.0): quy tắc dự án. Ngôn ngữ spec/plan/tasks là tiếng Việt.
2. `specs/016-h-giao-dien-giong-powerbi/spec.md`: 8 user story, FR-001…FR-028, SC-001…SC-007, mục "Clarifications".
3. `specs/016-h-giao-dien-giong-powerbi/plan.md`: kiến trúc, cấu trúc tệp, 6 pha, rủi ro (đặc biệt **R-02**).
4. `specs/016-h-giao-dien-giong-powerbi/research.md` và `data-model.md`: quyết định kỹ thuật, kiểu dữ liệu Ribbon (`RibbonTabSpec`, `RibbonGroupSpec`, `RibbonItemSpec`, `Availability`, `RibbonContext`).
5. `specs/016-h-giao-dien-giong-powerbi/contracts/ribbon-catalog.md` **(quan trọng nhất)**: bảng chuẩn từng tab → nhóm → nút (ID, EN, kiểu, khả dụng, hành động hiện có). `contracts/ui-tokens.md` (số đo, màu), `contracts/visual-gallery.md` (lưới biểu tượng visual).
6. `specs/016-h-giao-dien-giong-powerbi/tasks.md`: **danh sách việc của bạn, 87 tác vụ T001…T087**.
7. `docs/PHASE_H_UI_PARITY.md`: quan sát chi tiết Power BI Desktop (mục 3.x là chuẩn "giống").
8. **Ảnh chuẩn** (mở xem, không sửa) trong `docs/phase-ui-evidence/vm-ui/`: `rb_home-2x.png`, `rb_insert-2x.png`, `rb_modeling-2x.png`, `rb_design-2x.png`, `rb_view-2x.png`, `rb_optimize-2x.png`, `rb_help-2x.png`, `rb_vformat-2x.png`, `rb_vdata-2x.png`, `rb_tv_home-2x.png`, `rb_tv_table-2x.png`, `rb_tv_column-2x.png`, `rb_tv_help-2x.png`, `o_now.png`, `r_visual_sel.png`, `p_format.png`, `v_dax_1.png`, `v_tmdl_2.png`, `v_model_1.png`, `t_colsel.png`, `f_file.png`, `dd_*.png`, `pn_perfanalyzer.png`. Ảnh BI Pro hiện tại: `docs/phase-ui-evidence/bipro-truoc/b_home.png`.
9. Mã hiện có cần hiểu: `Sources/BIPro/Shell/Ribbon.swift` (892 dòng, sẽ bị thay), `Shell/ShellView.swift`, `DocumentState.swift` (+ `DocumentState+*.swift`), `DesignSystem/Tokens.swift`, `DesignSystem/Components.swift`, `Settings/L10n.swift`, `Settings/AppPreferences.swift`, `Panes/*`, `Report/ReportWorkspace.swift`, `Query/QueryWorkspaces.swift`, `Model/ModelWorkspace.swift`, `Table/TableWorkspace.swift`. Test mẫu: `Tests/BIProTests/Edit/SyntheticReport.swift`, `Tests/BIProTests/Model/ColumnToolsRibbonTests.swift`, `Tests/BIProTests/Edit/AppLaunchPolicyTests.swift`.

Target `BIPro` chạy chế độ Swift 5; kiểu mới để mặc định `internal` (test dùng `@testable import BIPro`).

## 2. Cách làm việc

**`specs/016-h-giao-dien-giong-powerbi/tasks.md` là sổ theo dõi trạng thái.** Làm lần lượt từ T001 đến T087, theo thứ tự phase; sau MỖI tác vụ xong, đổi `- [ ]` thành `- [x]` của tác vụ đó trong `tasks.md` (chỉ đổi dấu tích, không sửa chữ). Nếu phiên bị dừng và chạy lại, **bắt đầu từ tác vụ `[ ]` đầu tiên**, không làm lại việc đã tích.

Với mỗi tác vụ có logic: **viết test đỏ trước** (thấy nó thất bại vì đúng lý do), rồi cài đặt cho xanh, rồi dọn. Tác vụ thuần giao diện thì xuất ảnh và tự xem.

Cuối **mỗi phase** (mỗi mục "Checkpoint" trong `tasks.md`) bạn PHẢI:
1. `swift build` không lỗi, không cảnh báo mới do bạn gây ra.
2. `swift test --no-parallel` **toàn bộ** xanh (không chỉ test mới). Hết phase US3, US4, US8 và ở T085 chạy thêm golden nặng (lệnh ở mục 3), số golden khớp phải giữ nguyên.
3. Với phase có giao diện: chạy `BIPRO_H_RENDER=1 swift test --no-parallel --filter ParityRenderTests` để xuất ảnh vào `build/h-out/<phase>/`, rồi **mở từng ảnh xem**: không trống, không có biểu tượng "cấm" vàng/đỏ, không bị cắt, không chữ chồng, kích thước byte không giống hệt nhau giữa các ảnh khác nội dung (giống hệt = vẽ hỏng). So bằng mắt với ảnh chuẩn ở mục 1.8.
4. Ghi báo cáo ngắn `docs/tasks/h-phase<N>-report.md` (N = số Phase trong `tasks.md`): tác vụ đã làm, tệp đã sửa/tạo, dòng kết quả cuối của `swift test` (số test qua/trượt), ảnh đã xuất, việc còn tồn đọng, mọi chỗ bạn phải đoán (kèm lý do).
5. `git status` chỉ có tệp thuộc `docs/phase-h-ownership.tsv`. Có tệp ngoài danh sách thì hoàn tác phần đó bằng cách sửa lại (không dùng `git checkout`), hoặc ghi rõ lý do trong báo cáo nếu bắt buộc.

Chưa đạt thì **tự sửa tiếp**; không sửa được thì ghi rõ lý do trong báo cáo phase và **dừng hẳn** (đừng bàn giao như đã xong, đừng sang phase sau).

## 3. Lệnh được phép (mỗi lệnh là một lệnh đơn, đúng chính tả)

- `swift build`
- `swift test --no-parallel` ; `swift test --no-parallel --filter UIParity` ; `swift test --no-parallel --filter <TênTest>`
- `BIPRO_H_RENDER=1 swift test --no-parallel --filter ParityRenderTests`
- Golden nặng: `BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --no-parallel --filter "Nhom6|ORA|VIS|ExportCSVTests|ExportRenderTests|QuickLookSummaryTests|V11BDAXGoldenTests"`
- `zsh scripts/build-app.sh release` (chỉ ở T085) và `codesign --verify --deep --strict "build/BI Pro.app"`
- Chỉ đọc: `git status`, `git diff`, `git diff --stat`, `git log`, `git grep <mẫu>`, `git ls-files`, `ls <đường dẫn>`, `grep <mẫu> <tệp>`, `cmp <a> <b>`, `wc -l <tệp>`, `sips -g pixelWidth <png>`.

Nếu SIGBUS sau khi đổi struct dùng chung giữa module: ghi vào báo cáo và dừng (bạn không có quyền xoá `.build`; lead sẽ xử lý). Nếu một test cũ đỏ vì thay đổi của bạn, sửa mã của bạn, không sửa test (trừ T021, T037).

## 4. Quy tắc mã (rút từ các lần review trước; vi phạm sẽ bị trả lại)

- Hành vi cũ phải giữ nguyên: mọi nút đang chạy ở v1.2 vẫn chạy y như cũ, kể cả hoàn tác `⌘Z`, lưu T2, phím tắt (`⌘Z`, `⌘E`, `⇧⌘R`, `⌘,`, `⌘K`…). `RibbonActions` chỉ **gọi lại** hàm `DocumentState` hiện có, không viết lại logic.
- Mọi nhãn mới có cả `vi` và `en` không rỗng; `en` đúng chữ trong cột EN của `contracts/ribbon-catalog.md`. Nhãn nhóm viết **thường**, không `.uppercased()`.
- Dark Mode: dùng `DS.Palette` và token trong `contracts/ui-tokens.md`, không viết màu cứng trong view (trừ nhãn trên giấy báo cáo dùng token `paper*` sẵn có). Giấy trang báo cáo giữ nguyên.
- VoiceOver: mọi nút/tab/mục rail có `accessibilityLabel`; tab chọn có `.isSelected`; nút bật/tắt báo đúng trạng thái.
- Nút vô hiệu: mờ đồng nhất + `.help(lý do song ngữ)`. Mục `observed == false` PHẢI có `note` không rỗng và bình luận mã bắt đầu bằng `[SUY ĐOÁN]`.
- `NSObject` xử lý sự kiện: nhớ `@objc(tên:)`. `NSPanel` tự tạo: `isReleasedWhenClosed = false`. Popover/menu: đặt `appearance` theo giao diện ứng dụng (cả sáng/tối).
- Xuất ảnh bằng `ImageRenderer`: `NSViewRepresentable` bị vẽ thành biểu tượng "cấm", nội dung `ScrollView`/`LazyVStack` bị vẽ **trống**. View có vùng cuộn nhận tham số `scrollable: Bool = true`; khi `false` (chỉ test xuất ảnh dùng) vẽ bằng `VStack`/`HStack` thường, cắt theo khung. Mẫu: `Tests/BIProTests/Charts/NewChartsImageTests.swift` (`ImageRenderer`, `scale = 2`). Ảnh phải ghi vào `build/h-out/<phase>/` bằng `FileManager` trong test, chỉ khi `BIPRO_H_RENDER=1`.
- Không để mã chết sau khi xoá `Ribbon.swift` (T043): `swift build` sạch.
- Tệp mới đặt đúng chỗ theo `plan.md`; kiểu và hàm đặt tên theo `data-model.md`/`contracts/`. Không đổi tên/chữ ký hợp đồng H0 (T004–T008) sau khi xong Phase 2; nếu thật sự cần, ghi đề xuất vào báo cáo thay vì tự đổi.

## 5. Quyết định đã chốt (đừng hỏi lại)

- Màu nhấn **teal `#117865`** (Dark `#3FB59B`); canvas quanh trang `#E6E6E6`; chrome `#F5F5F5`. Nút Windows/cloud (Copilot, Publish, Share, Dataverse, OneLake, Power Apps/Automate, Q&A, Sensitivity, Prep data for AI) **hiện đúng vị trí, vô hiệu có tooltip**, không ẩn. Giữ traffic lights macOS. Biểu tượng là SF Symbols hai màu (`symbolRenderingMode(.palette)`), không vẽ bộ Fluent.
- **Chế độ Sửa mặc định (T052, R-02):** chỉ đặt `editMode = true` mặc định nếu cú bấm không kéo ở chế độ Sửa vẫn lọc chéo (test T046 xanh) VÀ toàn bộ test `Interaction`, `D*Nhom6Tests` xanh. Nếu không đạt thì **hoàn lại mọi thay đổi của spike**, giữ mặc định cũ (Xem), chỉ chuyển công tắc Xem/Sửa vào menu View, ghi lý do vào `docs/tasks/h4-r02.md` và báo cáo phase, rồi tiếp tục các tác vụ khác (không dừng).
- Pane Visualizations và Data thu gọn thành dải dọc ≈ 31 pt có chữ xoay và mở lại được (vì tab View không còn nút bật/tắt hai pane này).
- Nút Model view "Sắp xếp lại"/"Vừa màn hình" chuyển thành nút trên thanh trạng thái Model view; "Xuất TMDL" chuyển vào File ▸ Export; "Sao chép" TMDL thành nút Copy ở Clipboard. Không được mất tính năng nào.
- Lưới biểu tượng visual theo `contracts/visual-gallery.md` ([SUY ĐOÁN] nếu chưa đối chiếu được ảnh; ảnh là chuẩn cuối cùng, sửa bảng nếu lệch và ghi báo cáo).
- Phần chưa quan sát được ở `docs/PHASE_H_UI_PARITY.md` (menu Recent sources, Transform data, More visuals, Sensitivity, Optimization presets, Language, Linguistic schema, Groups, Align, Group; hộp Customize theme; hover/pressed; Mobile layout): làm theo suy luận hợp lý, ghi `[SUY ĐOÁN]`.
- Chuyển view khi tab hiện tại không còn: về Home. Cửa sổ hẹp: Ribbon cuộn ngang, không gom nhóm vào menu.

## 6. Việc bạn sẽ gặp mà không tự làm (ghi vào báo cáo, đừng đoán)

- T086 (cổng Desktop trên máy ảo) và SC-004/SC-005 cần con người: bạn chỉ **chuẩn bị** `build/h-out/gate/CHECKLIST.md` và bộ ảnh BI Pro; ghi rõ đó là việc còn lại.
- Commit/push: không phải việc của bạn.

## 7. Hoàn tất (T085–T087)

Khi `tasks.md` chỉ còn các việc cần con người: chạy toàn bộ kiểm ở T085, cập nhật `docs/STATE.md` (mục "Việc tiếp theo": Phase H xong phần mã, chờ cổng Desktop và commit), `docs/BIPRO_BUILD_PLAN.md`, rồi viết `docs/tasks/h-final-report.md` gồm: bảng 15 Ribbon + 6 view đã đối chiếu (đạt/lệch/`[SUY ĐOÁN]`), số test (cũ + mới) qua/trượt, số golden nặng, danh sách `git status`, quyết định R-02 (Sửa mặc định hay không), mọi điểm bạn lệch khỏi tài liệu kèm lý do, danh sách ảnh trong `build/h-out/`. Chỉ báo "xong" khi `swift test --no-parallel` toàn bộ xanh, golden nặng xanh, `zsh scripts/build-app.sh release` + `codesign` đạt, và `git status` chỉ có tệp được phép.
