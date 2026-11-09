#!/bin/zsh
# Vòng đo E3: build release dax-run, chạy ba truy vấn chậm trên Nhom6 nhiều lần, in thời gian trung vị
# và so byte với bản chuẩn trong build/e3-base.
# Dùng: zsh scripts/e3-loop.sh
#   BIPRO_NHOM6=<đường dẫn .pbix>  file Nhom6 (mặc định ~/Downloads/Nhom6_Dashboard.pbix, nếu thiếu thì ~/Downloads/bipro-golden/Nhom6_work.pbix)
#   E3_RUNS=<số lần>               số lần chạy mỗi truy vấn (mặc định 5)
#   BIPRO_BATCH=0                  tắt đường tính gộp (E3-cấu-trúc), để so với đường cũ
# Cần build/e3-base/*.engine.tsv (bản chuẩn).
set -e
cd "${0:A:h}/.."
PBIX=${BIPRO_NHOM6:-$HOME/Downloads/Nhom6_Dashboard.pbix}
[[ -f $PBIX ]] || PBIX="$HOME/Downloads/bipro-golden/Nhom6_work.pbix"
[[ -f $PBIX ]] || { echo "Không tìm thấy file Nhom6 (đặt BIPRO_NHOM6=<đường dẫn>)"; exit 1; }
RUNS=${E3_RUNS:-5}
QUERIES=(D1-combo-thauchi D1-matrix-gio-thu D3-combo-kenh)

swift build -c release --product dax-run --scratch-path .build-1a-rel 2>&1 | grep -E "error|warning: unre" || true
mkdir -p build/e3-out

typeset -A times
for r in {1..$RUNS}; do
  args=()
  for q in $QUERIES; do args+=(docs/phase-c-evidence/observe-c1/pa/$q.dax); done
  out=$(.build-1a-rel/release/dax-run query "$PBIX" build/e3-out $args 2>&1)
  if echo "$out" | grep -qE "^(ERR|lỗi)"; then echo "$out" | grep -E "^(ERR|lỗi)"; exit 1; fi
  for q in $QUERIES; do
    t=$(echo "$out" | awk -v n="$q" '$1=="OK" && $2==n {print $3}')
    [[ -n $t ]] || { echo "Thiếu kết quả của $q"; echo "$out"; exit 1; }
    times[$q]="${times[$q]} $t"
  done
done

echo "file: $PBIX | $RUNS lần | BIPRO_BATCH=${BIPRO_BATCH:-(mặc định)}"
for q in $QUERIES; do
  sorted=(${(on)=times[$q]})
  med=${sorted[$(( (${#sorted} + 1) / 2 ))]}
  line="$q: trung vị ${med} s (min ${sorted[1]}, max ${sorted[-1]})"
  if [[ -f build/e3-base/$q.engine.tsv ]]; then
    cmp -s build/e3-out/$q.engine.tsv build/e3-base/$q.engine.tsv && line+=" | khớp byte với bản chuẩn" || line+=" | KHÁC bản chuẩn!"
  fi
  echo $line
done
