#!/bin/zsh
# Vòng đo E3: build release dax-run, chạy hai truy vấn chậm trên Nhom6, so byte với bản chuẩn trong build/e3-base.
# Dùng: zsh scripts/e3-loop.sh   (cần ~/Downloads/Nhom6_Dashboard.pbix và build/e3-base/*.engine.tsv)
set -e
cd "${0:A:h}/.."
swift build -c release --product dax-run --scratch-path .build-1a-rel 2>&1 | grep -E "error|warning: unre" || true
mkdir -p build/e3-out
for q in D1-combo-thauchi D1-matrix-gio-thu D3-combo-kenh; do
  .build-1a-rel/release/dax-run query ~/Downloads/Nhom6_Dashboard.pbix build/e3-out docs/phase-c-evidence/observe-c1/pa/$q.dax 2>&1 | grep -E "^(OK|ERR|LỖI)"
  if [[ -f build/e3-base/$q.engine.tsv ]]; then cmp -s build/e3-out/$q.engine.tsv build/e3-base/$q.engine.tsv && echo "  khớp byte với bản chuẩn" || echo "  KHÁC bản chuẩn!"; fi
done
