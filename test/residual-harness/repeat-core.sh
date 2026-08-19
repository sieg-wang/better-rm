#!/bin/bash
# repeat-core.sh — 同一份程式碼連跑 N 次，看哪些測試其實是不穩的
#
# 驗什麼：R3 的教訓是「兩個 commit 都紅、檔案逐位元組相同 ＝ 負載相依，不是回歸」。
# 要能講這句話，得先有「同一份碼重複跑」的資料。這支腳本就是那個資料來源：在一份
# repo 副本上重複跑核心 suite（或整套 run-test-suites.sh），每一次都印出通過／失敗
# 數與失敗清單，最後檢查有沒有留下 better-rm 的孤兒行程。
#
# ⚠️ 把它跟 R3 一起讀：閒置時全綠**不代表**沒有負載敏感的斷言，只代表這台機器現在
#    很閒。要重現 R3 請一邊跑 12 個 spinner 一邊跑 `node test-hooks.js`（那條牆鐘
#    斷言在核心 suite 裡沒有，在 test-hooks.js 裡）。
#
# What it verifies: run-to-run stability of one unchanged tree. R3's conclusion
# ("both commits red, file byte-identical => load-dependent, not a regression")
# is only sayable with repeat data. Idle green does NOT mean no load-sensitive
# assertion exists — R3's wall-clock budget lives in test-hooks.js, not here.
#
# 對應 / maps to: R3 的方法學（不是 R3 本身）
# 來源 / ported from: KEEP-better-rm/acceptance-evidence/repeat_core.sh
#                     （--full 併入了同目錄的 run_full.sh）
#
# usage: repeat-core.sh [-n N] [--full]        預設 N=5，核心 suite
set -u

HS_SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
HS_REPO="$(cd -- "$HS_SELF_DIR/../.." && pwd -P)"
. "$HS_SELF_DIR/lib/harness.sh"

hs_require_repo

N=5
MODE=core
while [ $# -gt 0 ]; do
    case "$1" in
        -n) N="$2"; shift 2 ;;
        --full) MODE=full; shift ;;
        -h|--help) sed -n '1,28p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) hs_die "unknown argument '$1'" ;;
    esac
done
case "$N" in
    ''|*[!0-9]*) hs_die "-n takes a positive integer, got '$N'" ;;
esac

hs_workspace repeat-core
W="$HS_WORK/work"
hs_copy_repo "$W"
hs_detect_timeout

printf 'mode=%s runs=%s\n\n' "$MODE" "$N"

RUNS_FAILED=0
i=1
while [ "$i" -le "$N" ]; do
    log="$HS_WORK/run-$i.log"
    t0=$(hs_now)
    if [ "$MODE" = full ]; then
        set -- ./run-test-suites.sh
    else
        set -- ./test-better-rm.sh
    fi
    [ -n "$HS_TIMEOUT_BIN" ] && set -- "$HS_TIMEOUT_BIN" 1800 "$@"
    rc=0
    hs_isolated "$W" "$@" > "$log" 2>&1 || rc=$?
    el=$(hs_elapsed "$t0" "$(hs_now)")
    summary=$(hs_strip_ansi < "$log" |
        grep -E '總測試數|通過測試|失敗測試|<== (PASS|FAIL)' | tr '\n' ' ')
    printf 'run %-3s exit=%-3s elapsed=%-9s %s\n' "$i" "$rc" "${el}s" "$summary"
    hs_strip_ansi < "$log" | grep '✗ 失敗:' | sed 's/^/        /'
    [ "$rc" -ne 0 ] && RUNS_FAILED=$((RUNS_FAILED + 1))
    i=$((i + 1))
done

printf '\nstray better-rm processes left behind by run_bounded:\n'
# 先收進變數再判斷。原本直接用管線的結束碼是 `sed` 的，永遠是 0，
# 「(none)」那一支永遠跑不到——看起來像有輸出，其實什麼都沒說。
strays=$(ps -eo pid,ppid,etime,command | grep -F "$HS_WORK" |
    grep -v grep | grep -v 'repeat-core')
if [ -n "$strays" ]; then
    printf '%s\n' "$strays" | sed 's/^/  /'
else
    printf '  (none)\n'
fi

printf '\n%s of %s run(s) exited non-zero.\n' "$RUNS_FAILED" "$N"
[ "$RUNS_FAILED" -eq 0 ]
