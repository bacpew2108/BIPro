#!/bin/bash
# check-ownership.sh: kiểm quyền sở hữu file của một agent trong sandbox,
# và kiểm TSV phân quyền theo đợt (Phase B).
#
# Cách dùng:
#   check-ownership.sh <base> <sandbox> <WP>
#       Phase W: đọc docs/phase-w-ownership.tsv (hành vi cũ, không đổi).
#   check-ownership.sh [-t <tsv>] [-w <đợt>] <base> <sandbox> <WP>
#       Chọn TSV khác. Với TSV có cột đợt thì bắt buộc -w <đợt>.
#   check-ownership.sh --lint <tsv> <đợt>
#       Kiểm mọi file của repo (Sources, Tests, scripts, docs, Package.swift).
#       Báo VIOLATION nếu một file khớp glob của từ hai WP trở lên trong đợt đó.
#       Báo UNOWNED nếu không WP nào khớp (thông tin cho lead, không tính là lỗi).
#
# Quy ước TSV:
#   - Dòng đầu bắt đầu bằng '#' là header. Số cột của header quyết định định dạng:
#       2 cột (WP, glob)        -> Phase W, không có cột đợt.
#       3 cột (đợt, WP, glob)   -> Phase B.
#   - Dòng trống và dòng bắt đầu bằng '#' bị bỏ qua.
#   - Glob theo bash case, tương đối với gốc repo. '*' khớp cả '/', nên
#     Sources/A/* cũng khớp thư mục con. Khi hai WP chia một thư mục, dùng
#     glob hẹp hơn (ví dụ Sources/dax-run/[!B]* và Sources/dax-run/Bench*.swift).
#
# Thoát: 0 = đạt; 1 = có vi phạm; 2 = lỗi cách dùng hoặc TSV sai.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEFAULT_TSV="$ROOT/docs/phase-w-ownership.tsv"

die() { echo "$*" >&2; exit 2; }

usage() {
  cat >&2 <<'USAGE'
Cách dùng:
  check-ownership.sh <base> <sandbox> <WP>
  check-ownership.sh [-t <tsv>] [-w <đợt>] <base> <sandbox> <WP>
  check-ownership.sh --lint <tsv> <đợt>
USAGE
}

# Đường dẫn tuyệt đối, tính theo thư mục hiện tại (gọi trước khi cd).
abspath() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s/%s\n' "$PWD" "$1" ;;
  esac
}

# Kiểm TSV và gán ncol (2 hoặc 3) theo header.
ncol=0
check_tsv() {
  [ -r "$1" ] || die "không đọc được TSV: $1"
  case "$(head -n 1 "$1")" in
    \#*) ;;
    *) die "TSV phải có dòng header bắt đầu bằng '#': $1" ;;
  esac
  ncol=$(head -n 1 "$1" | awk -F'\t' '{print NF}')
  case "$ncol" in
    2|3) ;;
    *) die "header TSV phải có 2 hoặc 3 cột, đang có $ncol: $1" ;;
  esac
}

# Liệt kê file tương đối của một thư mục. Bỏ .build, .build-* và build/ (đầu ra sinh ra,
# không phải mã nguồn; rsync của sandbox cũng không chép build/, nên phải bỏ ở cả hai phía).
list() {
  (cd "$1" && find . -type f -not -path './.build/*' -not -path './.build-*/*' \
    -not -path './build/*' | sed 's|^\./||' | sort)
}

MODE=check; TSV=""; WAVE=""
while [ $# -gt 0 ]; do
  case "$1" in
    -t) [ $# -ge 2 ] || die "thiếu giá trị cho -t"; TSV="$2"; shift 2 ;;
    -w) [ $# -ge 2 ] || die "thiếu giá trị cho -w"; WAVE="$2"; shift 2 ;;
    --lint) MODE=lint; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) usage; die "tuỳ chọn không rõ: $1" ;;
    *) break ;;
  esac
done

# ---------- Chế độ lint: kiểm TSV theo đợt trên toàn repo ----------
if [ "$MODE" = lint ]; then
  [ $# -eq 2 ] || { usage; die "--lint cần đúng 2 tham số: <tsv> <đợt>"; }
  TSV=$(abspath "$1"); WAVE="$2"
  check_tsv "$TSV"
  [ "$ncol" = 3 ] || die "--lint cần TSV có cột đợt (header 3 cột): $TSV"
  rows=$(awk -F'\t' -v w="$WAVE" '/^#/ || NF == 0 { next } $1 == w { print $2 "\t" $3 }' "$TSV")
  [ -n "$rows" ] || die "không có dòng nào cho đợt $WAVE trong $TSV"
  tmp=$(mktemp -d) || die "không tạo được thư mục tạm"
  trap 'rm -rf "$tmp"' EXIT
  cd "$ROOT" || die "không vào được $ROOT"
  find Sources Tests scripts docs Package.swift -type f -not -path '*/.build*' \
    -not -name '.DS_Store' | sed 's|^\./||' | sort > "$tmp/files"
  violations=0; unowned=0; count=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    count=$((count+1)); owners=""; n=0
    while IFS=$'\t' read -r wp pat; do
      case "$f" in
        $pat)
          case " $owners " in
            *" $wp "*) ;;
            *) owners="$owners $wp"; n=$((n+1)) ;;
          esac ;;
      esac
    done <<< "$rows"
    if [ "$n" -ge 2 ]; then
      echo "VIOLATION (đợt $WAVE): $f ->$owners"; violations=$((violations+1))
    elif [ "$n" -eq 0 ]; then
      echo "UNOWNED (đợt $WAVE): $f"; unowned=$((unowned+1))
    fi
  done < "$tmp/files"
  echo "lint đợt $WAVE: $count file(s), $violations violation(s), $unowned unowned"
  [ $violations -eq 0 ]
  exit $?
fi

# ---------- Chế độ kiểm sandbox ----------
[ $# -eq 3 ] || { usage; die "cần đúng 3 tham số: <base> <sandbox> <WP>"; }
BASE="${1%/}"; SBX="${2%/}"; WP="$3"
if [ -n "$TSV" ]; then TSV=$(abspath "$TSV"); else TSV="$DEFAULT_TSV"; fi
check_tsv "$TSV"
if [ "$ncol" = 3 ]; then
  [ -n "$WAVE" ] || die "TSV có cột đợt: cần -w <đợt>"
  LABEL="$WP (đợt $WAVE)"
else
  [ -z "$WAVE" ] || die "TSV không có cột đợt: bỏ -w"
  LABEL="$WP"
fi

patterns=$(awk -F'\t' -v w="$WAVE" -v wp="$WP" -v three="$ncol" '
  /^#/ || NF == 0 { next }
  three == 3 { if ($1 == w && $2 == wp) print $3; next }
  $1 == wp { print $2 }' "$TSV")
[ -n "$patterns" ] || { echo "no owned patterns for $LABEL" >&2; exit 2; }

tmp=$(mktemp -d) || die "không tạo được thư mục tạm"
trap 'rm -rf "$tmp"' EXIT
list "$BASE" > "$tmp/base"; list "$SBX" > "$tmp/sbx"
{
  comm -3 "$tmp/base" "$tmp/sbx" | tr -d '\t'
  comm -12 "$tmp/base" "$tmp/sbx" | while IFS= read -r f; do
    cmp -s "$BASE/$f" "$SBX/$f" || printf '%s\n' "$f"
  done
} | sed '/^$/d' | sort -u > "$tmp/changed"

violations=0; count=0
while IFS= read -r path; do
  [ -n "$path" ] || continue
  count=$((count+1)); ok=0
  while IFS= read -r pat; do
    case "$path" in $pat) ok=1; break ;; esac
  done <<< "$patterns"
  if [ $ok -eq 0 ]; then echo "VIOLATION ($LABEL): $path"; violations=$((violations+1)); fi
done < "$tmp/changed"
echo "$LABEL: $count changed file(s), $violations violation(s)"
[ $violations -eq 0 ]
