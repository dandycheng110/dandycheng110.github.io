#!/usr/bin/env bash
# collect_smart.sh — 硬碟健康資料（SMART）唯讀收集腳本
# 2026 全國 AI 專題創意競賽：HDD 健康監測與故障預測 專題
#
# 這支腳本只做「讀取」：
#   - 用 smartctl 讀每顆硬碟內建的健康數值（不會啟動自我檢測、不寫入硬碟）
#   - 序號用 HMAC-SHA256 雜湊，金鑰存在你們自己的機器上，永遠不要交給我們
#   - 不收主機名稱、IP、帳號、檔案內容
#
# 用法（需要 root 權限才能讀 SMART）：
#   sudo ./collect_smart.sh [--site 代號] [--out 輸出資料夾]   每天跑一次
#   ./collect_smart.sh --hash 序號                            把換碟紀錄上的序號換成同一套雜湊
#   ./collect_smart.sh --help
#
# 需要：smartmontools 7.0 以上（有 JSON 輸出）、openssl。有 python3 會做完整去識別化；
#       沒有的話改用 smartctl 內建的 noserial 模式。

set -u

SITE="SITE_A"
OUT_DIR="./smart_output"
SMARTCTL="${SMARTCTL:-smartctl}"   # 測試時可以指向假的 smartctl
WAKE_STANDBY="${WAKE_STANDBY:-0}"  # 預設不吵醒休眠中的硬碟；設 1 則照讀
HASH_ONLY=""

usage() {
  sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --site) SITE="$2"; shift 2 ;;
    --out)  OUT_DIR="$2"; shift 2 ;;
    --hash) HASH_ONLY="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "不認得的參數：$1（用 --help 看說明）" >&2; exit 64 ;;
  esac
done

case "$SITE" in
  *[!A-Za-z0-9_-]*) echo "--site 只能用英數字、底線、減號（不要放公司或主機名稱）" >&2; exit 64 ;;
esac

command -v openssl >/dev/null 2>&1 || { echo "找不到 openssl" >&2; exit 69; }

mkdir -p "$OUT_DIR"
KEY_FILE="$OUT_DIR/.hmac_key"
if [ ! -s "$KEY_FILE" ]; then
  umask 077
  openssl rand -hex 32 > "$KEY_FILE"
  echo "已建立雜湊金鑰：$KEY_FILE（請保留在貴單位，不要交給任何人；弄丟就無法把報告對回實體硬碟）" >&2
fi
KEY="$(cat "$KEY_FILE")"

hmac() {
  printf '%s' "$1" | openssl dgst -sha256 -hmac "$KEY" | awk '{print $NF}'
}

if [ -n "$HASH_ONLY" ]; then
  hmac "$HASH_ONLY"; echo
  exit 0
fi

command -v "$SMARTCTL" >/dev/null 2>&1 || { echo "找不到 smartctl，請先安裝 smartmontools 7.0 以上" >&2; exit 69; }

ver="$("$SMARTCTL" --version 2>/dev/null | awk 'NR==1{print $2}')"
case "$ver" in
  [0-6].*) echo "smartctl 版本 $ver 太舊，需要 7.0 以上（才有 JSON 輸出）" >&2; exit 69 ;;
esac

HAVE_PY=0
command -v python3 >/dev/null 2>&1 && HAVE_PY=1
[ "${NO_PYTHON:-0}" = 1 ] && HAVE_PY=0   # python3 壞掉時可強制改用 noserial 模式

TODAY="$(TZ=Asia/Taipei date '+%Y-%m-%d')"
NOW="$(TZ=Asia/Taipei date '+%Y-%m-%dT%H:%M:%S+08:00')"
OUT_FILE="$OUT_DIR/smart_${TODAY}_${SITE}.jsonl"
: > "$OUT_FILE"

# 移除可以追到實體硬碟或機器的欄位；序號改成 disk_id（HMAC）
sanitize() {
  python3 -c '
import json, sys
DROP = {"serial_number", "wwn", "logical_unit_id", "eui64", "nguid"}
def scrub(x):
    if isinstance(x, dict):
        return {k: scrub(v) for k, v in x.items() if k not in DROP}
    if isinstance(x, list):
        return [scrub(v) for v in x]
    return x
rec = json.load(sys.stdin)
rec["smartctl"] = scrub(rec["smartctl"])
print(json.dumps(rec, ensure_ascii=False, separators=(",", ":")))
'
}

n_ok=0; n_skip=0
standby_opt=""
[ "$WAKE_STANDBY" = "1" ] || standby_opt="-n standby"

# --scan-open 每行像：/dev/sda -d sat # /dev/sda [SAT], ATA device
while IFS= read -r line; do
  args="${line%%#*}"
  [ -z "${args// }" ] && continue
  # shellcheck disable=SC2086
  set -- $args
  dev="$1"; shift
  dtype="$*"

  # shellcheck disable=SC2086
  serial="$("$SMARTCTL" -i $dtype "$dev" 2>/dev/null | awk -F': *' 'tolower($1) ~ /^serial number$/ {print $2; exit}')"
  disk_id="unknown"
  [ -n "$serial" ] && disk_id="$(hmac "$serial")"
  serial=""

  if [ "$HAVE_PY" = 1 ]; then
    # shellcheck disable=SC2086
    body="$("$SMARTCTL" -a --json=c $standby_opt $dtype "$dev" 2>/dev/null)"
  else
    # shellcheck disable=SC2086
    body="$("$SMARTCTL" -a --json=c -q noserial $standby_opt $dtype "$dev" 2>/dev/null)"
  fi
  if [ -z "$body" ]; then
    n_skip=$((n_skip + 1)); continue
  fi

  rec="{\"schema\":\"hdd-smart-v1\",\"collected_at\":\"$NOW\",\"site\":\"$SITE\",\"disk_id\":\"$disk_id\",\"smartctl\":$body}"
  if [ "$HAVE_PY" = 1 ]; then
    printf '%s' "$rec" | sanitize >> "$OUT_FILE" || { n_skip=$((n_skip + 1)); continue; }
  else
    # 沒有 python3：用 sed 刪掉 noserial 沒處理到的識別碼（compact JSON，一顆碟一行）
    printf '%s\n' "$rec" | sed -E \
      -e 's/,"(eui64|wwn)":\{[^}]*\}//g' -e 's/"(eui64|wwn)":\{[^}]*\},?//g' \
      -e 's/,"(serial_number|nguid|logical_unit_id)":"[^"]*"//g' -e 's/"(serial_number|nguid|logical_unit_id)":"[^"]*",?//g' \
      >> "$OUT_FILE"
  fi
  n_ok=$((n_ok + 1))
done < <("$SMARTCTL" --scan-open 2>/dev/null)

echo "完成：$n_ok 顆硬碟寫入 $OUT_FILE；略過 $n_skip 顆（休眠中或讀不到）" >&2
[ "$HAVE_PY" = 1 ] || echo "提醒：這台沒有 python3，改用 smartctl noserial＋sed 去識別化；交出前請用文字編輯器打開抽查一行" >&2
