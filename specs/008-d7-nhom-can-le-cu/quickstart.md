# Kiểm D7 từ đầu đến cuối

1. `swift build`; `swift test` (thường). Golden nặng: `BIPRO_HEAVY=1 swift test -c release -Xswiftc -enable-testing --scratch-path .build-1a-rel --filter "Nhom6|ORA|VIS|D2Nhom6|D3Nhom6|D4Nhom6|D5Nhom6|D6Nhom6|D7Nhom6|EditNhom6|BatchedSerial"`.
2. Test nặng `D7Nhom6Tests` ghi `build/d-out/D7/Nhom6_d7.pbix`, `Nhom6_d7_pre.pbix`, `Nhom2_d7.pbix` (bản sao của `Nhóm 2 - Financial Service .pbix`; bỏ qua nếu file không có), `CHECKLIST.md`.
3. `zsh scripts/build-app.sh`, mở bản sao Nhom6, ⌘E: chọn 3 thẻ, Căn trái, Phân bố ngang, ⌘Z; chép một visual, chuyển trang, ⌘V; chọn 3 visual, ⌘G, kéo nhóm, ⌘S.
4. Buổi VM vòng 2 (Claude điều khiển VM khi được cho phép): mở ba file ở bước 2 trong Power BI Desktop, kiểm theo `CHECKLIST.md`.
