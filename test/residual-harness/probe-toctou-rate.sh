#!/bin/bash
# probe-toctou-rate.sh — R1：日誌綁定檢查的 TOCTOU 窗口，實測命中率
#
# 驗什麼：`log_file_is_bound()` 驗的是**路徑**（`[ -L ]` / `[ -f ]` / `[ -O ]` / link 數
# 都對路徑做），通過之後 `log_deletion` 才用同一個路徑 append。兩者之間有窗口。
# 這支腳本開一個同 UID 的 racer 不停把日誌路徑在「正常檔」與「指向 target 的 symlink」
# 之間翻面，然後跑 N 次刪除，數有幾次 append 跟著連結走過去。
#
# ⚠️ **命中率隨 harness 的積極程度大幅變動，這是 TOCTOU 的正常現象。**
#    2026-08-18/19 三組獨立 harness 量到的範圍是 3.3% ~ 96.7%（皆同 UID racer）。
#    **這支腳本印出來的任何單一數字都只描述這一次的 harness 與這一台機器的負載，
#    不描述這個洞的難度。** 別把它當上限，也別當下限。要判斷風險請看前提條件
#    （state dir 0700、需先有同 UID 執行能力），不是看比率。
#
# What it verifies: R1. The binding check validates a PATH, then the append uses the
# same path; a same-UID racer can swap a symlink into the window. The HIT RATE IS
# WILDLY HARNESS-DEPENDENT — independent harnesses measured 3.3% through 96.7% on
# byte-identical code. Any single number here describes this run, not the defect.
#
# 對應 / maps to: R1
# 來源 / ported from: KEEP-better-rm/acceptance-evidence/probe_toctou.sh
#                     （racer.sh 是它用 heredoc 產生的，不是獨立來源檔）
#
# usage: probe-toctou-rate.sh [--brm <path>] [iterations]     預設 150 次
set -u

HS_SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
HS_REPO="$(cd -- "$HS_SELF_DIR/../.." && pwd -P)"
. "$HS_SELF_DIR/lib/harness.sh"

hs_require_repo
hs_require_timeout

BRM="$HS_REPO/better-rm"
N=150
while [ $# -gt 0 ]; do
    case "$1" in
        --brm) BRM="$2"; shift 2 ;;
        -h|--help) sed -n '1,32p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) N="$1"; shift ;;
    esac
done
case "$N" in
    ''|*[!0-9]*) hs_die "iterations must be a positive integer, got '$N'" ;;
esac
[ -x "$BRM" ] || hs_die "'$BRM' is not executable"

hs_workspace probe-toctou
printf 'under test : %s\niterations : %s\n\n' "$BRM" "$N"

P="$HS_WORK/toctou"
mkdir -p "$P/home" "$P/trash" "$P/state" "$P/cwd"
LOG="$P/state/deletion.log"
TARGET="$P/planted-target.rc"
STOP="$P/stop"
printf '# legit log\n' > "$LOG"

# racer：同 UID，把日誌路徑在「正常檔」與「指向 target 的 symlink」之間翻面。
# 只碰工作區內的路徑，而且只由本腳本啟動、只由本腳本停止。
cat > "$P/racer.sh" <<'RACER'
#!/bin/bash
# RM 由呼叫端傳入真正的 rm 執行檔。這個迴圈一秒會跑幾百次，要是它打到 better-rm，
# 就會往使用者真正的垃圾桶與刪除日誌灌幾百筆記錄。
LOG="$1"; TARGET="$2"; STOP="$3"; RM="$4"; WORKDIR="$5"; PARENT="$6"
# Three independent stop conditions, because the stop FILE alone is not one.
# If the parent is SIGKILLed it never writes the file and its traps never run,
# and this loop -- a few hundred iterations a second -- would busy-loop on a
# core until the machine is rebooted. The workspace check and the parent check
# each end it without cooperation from the parent, and the iteration cap ends it
# even if both of those are somehow satisfied. None of them can shorten a real
# measurement: the cap is far above the ~150 attempts the caller makes.
# 三個彼此獨立的停止條件,因為「stop 檔案」本身不算一個:父程序若被 SIGKILL,它永遠不會
#寫出那個檔案、traps 也不會跑,而這個一秒數百次的迴圈會霸著一顆核心直到重開機。
MAX=2000000
n=0
while [ ! -f "$STOP" ] && [ -d "$WORKDIR" ] && kill -0 "$PARENT" 2>/dev/null; do
    n=$((n + 1))
    [ "$n" -ge "$MAX" ] && break
    "$RM" -f "$LOG"; ln -s "$TARGET" "$LOG"
    "$RM" -f "$LOG"; printf '# legit log\n' > "$LOG"
done
RACER
chmod +x "$P/racer.sh"

# racer 自己的 `ln: File exists` 是這場競賽的正常噪音，收進工作區的檔案而不是洗版。
"$P/racer.sh" "$LOG" "$TARGET" "$STOP" "$HS_RM" "$P" "$$" 2>"$P/racer.stderr" &
RACER_PID=$!
hs_track_bg "$RACER_PID"

HS_HOME="$P/home"; HS_TRASH="$P/trash"; HS_STATE="$P/state"

hits=0
i=1
while [ "$i" -le "$N" ]; do
    echo "v$i" > "$P/cwd/victim$i.txt"
    hs_isolated "$P/cwd" "$HS_TIMEOUT_BIN" -s KILL 10 "$BRM" "victim$i.txt" >/dev/null 2>&1
    if [ -e "$TARGET" ]; then
        hits=$((hits + 1))
        printf 'TOCTOU HIT on iteration %s: target created, %s bytes\n' \
            "$i" "$(wc -c < "$TARGET" | tr -d '[:space:]')"
        head -c 160 "$TARGET" | sed 's/^/  | /'
        printf '\n'
        "$HS_RM" -f "$TARGET"
    fi
    i=$((i + 1))
done

touch "$STOP"
wait "$RACER_PID" 2>/dev/null
HS_BG_PIDS=""

printf '\niterations=%s  toctou_hits=%s  rate=%s%%\n' "$N" "$hits" \
    "$(perl -e 'printf "%.1f", $ARGV[0] ? 100 * $ARGV[1] / $ARGV[0] : 0' "$N" "$hits")"
printf '\n'
printf 'REMINDER: 這個比率是這一次 harness 的性質，不是這個洞的難度。\n'
printf '          Independent harnesses measured 3.3%%-96.7%% on byte-identical code,\n'
printf '          and THIS script alone measured 11.3%% / 14.0%% / 16.7%% on three\n'
printf '          consecutive runs of 150 on one idle machine (2026-08-20).\n'
if [ "$hits" -eq 0 ]; then
    printf '\n0 hits 不等於「已修好」——它最可能代表這次的 racer 沒搶贏。\n'
    printf 'Zero hits is NOT evidence the race is closed; re-run, and check whether\n'
    printf 'log_file_is_bound still validates a PATH (R1 is only fixed when the check\n'
    printf 'moves to a file descriptor).\n'
fi
exit 0
