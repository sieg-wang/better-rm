#!/bin/bash
# probe-fifo-margin.sh — FIFO 那條測試的 15 秒上限還剩多少餘裕
#
# 驗什麼：「日誌路徑是 FIFO 時停止記錄，而且不會卡住」那個測試用 `run_bounded 15`
# 圍住 better-rm。這支腳本直接量綠路徑的實際耗時，算出離 15 秒上限還有多少餘裕。
# 這是為了回答一個具體問題：那個 15 秒是「寬鬆到不會誤報」還是「剛好卡在邊緣、
# 負載一高就變 flaky」。（R3 的教訓就是牆鐘斷言在負載下會翻紅。）
#
# What it verifies: how much headroom the FIFO test's 15s bound actually has. The
# question is whether 15s is comfortably loose or one load spike away from flaky —
# R3 is the standing reminder that wall-clock assertions turn red under load.
#
# 對應 / maps to: R3 的同族風險（牆鐘斷言），不是 R3 本身
# 來源 / ported from: KEEP-better-rm/acceptance-evidence/measure_fifo_margin.sh
#                     （原版用 python3 取時間，這裡改用 perl 的 Time::HiRes——
#                      core module，macOS 與 ubuntu 都一定在）
#
# usage: probe-fifo-margin.sh [--brm <path>] [iterations]     預設 20 次
set -u

HS_SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
HS_REPO="$(cd -- "$HS_SELF_DIR/../.." && pwd -P)"
. "$HS_SELF_DIR/lib/harness.sh"

hs_require_repo
# This is the ONLY probe that runs better-rm against a FIFO deletion log with no
# bound, and a FIFO with no reader is exactly what the regression it measures
# looks like -- so it hung forever on its own subject. Demonstrated 2026-08-29:
# with `--brm` pointed at a build whose `[ -f ]` guard was removed, the probe
# never returned, its EXIT trap never ran, and it left its workspace behind in
# TMPDIR. Same bound and same shape as probe-log-path-variants.sh.
# 這是唯一一支在無界情況下讓 better-rm 對著 FIFO 刪除日誌跑的探測,而「沒有讀者的 FIFO」
# 正是它要量的那個回歸的樣子——於是它被自己的受測對象卡死,連 EXIT trap 都沒跑到。
hs_require_timeout

BRM="$HS_REPO/better-rm"
N=20
CAP=15
while [ $# -gt 0 ]; do
    case "$1" in
        --brm) BRM="$2"; shift 2 ;;
        -h|--help) sed -n '1,26p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) N="$1"; shift ;;
    esac
done
case "$N" in
    ''|*[!0-9]*) hs_die "iterations must be a positive integer, got '$N'" ;;
esac
[ -x "$BRM" ] || hs_die "'$BRM' is not executable"

hs_workspace probe-fifo-margin
printf 'under test : %s\niterations : %s   (test bound = %ss)\n\n' "$BRM" "$N" "$CAP"

P="$HS_WORK/margin"
mkdir -p "$P/home" "$P/trash" "$P/state" "$P/cwd"
mkfifo "$P/state/deletion.log"
HS_HOME="$P/home"; HS_TRASH="$P/trash"; HS_STATE="$P/state"

: > "$P/times.txt"
i=1
while [ "$i" -le "$N" ]; do
    echo "v$i" > "$P/cwd/victim$i.txt"
    t0=$(hs_now)
    if ! hs_isolated "$P/cwd" "$HS_TIMEOUT_BIN" -s KILL 12 "$BRM" "victim$i.txt" >/dev/null 2>&1; then
        # A killed run has no duration to report. Fail loudly rather than
        # folding a 12-second timeout into the median as if it were a
        # measurement -- that would turn the hang into a quiet outlier.
        # 被殺掉的那一次沒有「耗時」可報。要大聲失敗,而不是把 12 秒摺進中位數當成量測值。
        printf 'probe-fifo-margin: iteration %s did not finish within 12s -- the FIFO path is wedged, not slow\n' "$i" >&2
        exit 1
    fi
    t1=$(hs_now)
    hs_elapsed "$t0" "$t1" >> "$P/times.txt"
    i=$((i + 1))
done

printf 'better-rm duration on the FIFO path (seconds, n=%s):\n' "$N"
CAP="$CAP" perl -e '
    my @v = sort { $a <=> $b } map { chomp; $_ + 0 } <STDIN>;
    exit 1 unless @v;
    my $cap = $ENV{CAP};
    printf "  min=%.3f  median=%.3f  max=%.3f\n", $v[0], $v[int(@v/2)], $v[-1];
    if ($v[-1] > 0) {
        printf "  margin at the worst observed run = %.3fs  (%.0fx headroom under the %ss bound)\n",
            $cap - $v[-1], $cap / $v[-1], $cap;
    } else {
        printf "  every run measured 0.000s; the %ss bound is not the binding constraint\n", $cap;
    }
' < "$P/times.txt"

printf '\nNOTE: 這是閒置機器上的數字。R3 已經證明牆鐘斷言在負載下會翻紅，\n'
printf '      所以「餘裕很大」只在同樣的負載條件下成立。\n'
printf 'NOTE: idle-machine figures. R3 already proved wall-clock assertions flip red\n'
printf '      under load, so "plenty of headroom" holds only at this load level.\n'
