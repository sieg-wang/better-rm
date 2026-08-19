#!/bin/bash
# probe-run-bounded.sh — 沒有控制終端時 run_bounded 還正確嗎（模擬 ubuntu CI runner）
#
# 驗什麼：`test-better-rm.sh` 用 `run_bounded` 圍住會 hang 的情況。它靠 `set -m` 把
# 背景工作放進自己的 process group，逾時就 `kill -9 -$pid` 整組殺掉。**這在有 tty 的
# 互動 shell 上一定成立，在 CI 上不見得**——這支腳本量的就是「無控制終端」那一側：
#   A 快速命令：狀態碼要正確傳回來（rc=0、RUN_BOUNDED_STATUS=7）
#   B 孫代行程卡在 FIFO 的 open()：要在上限秒數逾時（rc=1），而且**不留孤兒**
#   C 群組殺不可能打到 suite 自己的 pgroup（子行程 pid 永遠不等於 shell 的 pgid）
#   D 逾時之後 shell 的 job table 仍然乾淨
#
# 這裡的 run_bounded 是**執行期從 repo 現行的 test-better-rm.sh 抽出來的**，不是複製
# 一份會走味的舊碼。抽不到就整支失敗，不會偷偷驗一段不存在的東西。
#
# What it verifies: run_bounded's behaviour with NO controlling terminal, modelling
# the ubuntu CI runner — status propagation, timeout, no orphans left blocked in
# open(), and that the group kill can never target the suite's own process group.
# The function is EXTRACTED AT RUN TIME from the repo's current test-better-rm.sh,
# so this cannot drift into verifying a stale copy.
#
# 對應 / maps to: 不對應 R1–R3；這是 ca02eca 的可攜性證據
# 來源 / ported from: KEEP-better-rm/acceptance-evidence/portability_run_bounded.sh
#                     （合併 implementation-evidence/proto-bounded.sh 的 job-table 檢查；
#                      proto/hang.sh 是那支用 heredoc 產生的，不是獨立來源檔）
set -u

HS_SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
HS_REPO="$(cd -- "$HS_SELF_DIR/../.." && pwd -P)"
. "$HS_SELF_DIR/lib/harness.sh"

hs_require_repo
hs_workspace probe-run-bounded

SUITE="$HS_REPO/test-better-rm.sh"
EXTRACT="$HS_WORK/run_bounded.extracted.sh"

matches=$(grep -c '^run_bounded() {' "$SUITE")
[ "$matches" = "1" ] ||
    hs_die "expected exactly one 'run_bounded() {' in test-better-rm.sh, found $matches"

{
    printf 'RUN_BOUNDED_STATUS=""\n'
    awk '/^run_bounded\(\) \{/, /^\}/' "$SUITE"
} > "$EXTRACT"
grep -q '^}' "$EXTRACT" || hs_die "extraction of run_bounded did not terminate at a closing brace"
bash -n "$EXTRACT" || hs_die "the extracted run_bounded does not parse"

printf 'extracted run_bounded from %s (%s lines)\n\n' \
    "$SUITE" "$(wc -l < "$EXTRACT" | tr -d '[:space:]')"

# 順序是安全關鍵，別調換：`run_bounded` 的每一次寫入都落在 `$TEST_WORK_DIR` 底下
# （`$TEST_WORK_DIR/.run-bounded-done` 的 rm/mv/重導），而它是被 source 進**這支腳本
# 自己的 shell**、不經過 hs_isolated。所以 TEST_WORK_DIR 必須在 source 之前就指進
# 工作區；反過來寫，那些寫入會落到未定義的位置。
# Ordering is the safety property, do not reorder: run_bounded is sourced into THIS
# shell (not run through hs_isolated) and every write it makes targets
# "$TEST_WORK_DIR/.run-bounded-done", so TEST_WORK_DIR must already point into the
# workspace before the source.
TEST_WORK_DIR="$HS_WORK/bounded"
mkdir -p "$TEST_WORK_DIR"
# shellcheck source=/dev/null
. "$EXTRACT"

FAILED=0
check() {
    if [ "$2" = "$3" ]; then
        printf '   %-46s OK   (%s)\n' "$1" "$2"
    else
        printf '   %-46s MISS (got %s, want %s)\n' "$1" "$2" "$3"
        FAILED=$((FAILED + 1))
    fi
}

printf 'bash          : %s\n' "$BASH_VERSION"
printf 'tty on stdin  : %s\n' "$([ -t 0 ] && echo yes || echo no)"
printf 'tty on stdout : %s\n' "$([ -t 1 ] && echo yes || echo no)"
printf 'shell pid=%s pgid=%s\n\n' "$$" "$(ps -o pgid= -p $$ | tr -d ' ')"

printf -- '--- case A: fast command, exit code 7\n'
rc=0
run_bounded 10 bash -c 'exit 7' || rc=$?
check 'run_bounded returns 0 (completed)' "$rc" 0
check 'RUN_BOUNDED_STATUS propagates the exit code' "$RUN_BOUNDED_STATUS" 7

printf -- '\n--- case B: grandchild blocked in open() on a FIFO (the real shape)\n'
mkfifo "$TEST_WORK_DIR/blocker.fifo"
cat > "$TEST_WORK_DIR/hang.sh" <<'HANG'
#!/bin/bash
# The parent forks a subshell that blocks in open() for write on a reader-less FIFO.
( : > "$1" ) 2>/dev/null
HANG
chmod +x "$TEST_WORK_DIR/hang.sh"
t0=$(hs_now)
rc=0
run_bounded 4 "$TEST_WORK_DIR/hang.sh" "$TEST_WORK_DIR/blocker.fifo" || rc=$?
el=$(hs_elapsed "$t0" "$(hs_now)")
check 'run_bounded returns 1 (timed out)' "$rc" 1
printf '   %-46s %ss (want ~4s)\n' 'elapsed' "$el"
sleep 1
strays=$(ps -eo pid,ppid,command | grep -F "$TEST_WORK_DIR" |
    grep -v grep | grep -v 'probe-run-bounded' | wc -l | tr -d '[:space:]')
check 'orphans left blocked in open()' "$strays" 0
[ "$strays" -ne 0 ] && ps -eo pid,ppid,command | grep -F "$TEST_WORK_DIR" | grep -v grep

printf -- '\n--- case C: can the group kill ever hit the suite own pgroup?\n'
printf '   shell pgid=%s; a child pid can never equal it, so `kill -9 -$child`\n' \
    "$(ps -o pgid= -p $$ | tr -d ' ')"
printf '   cannot target the suite. This is structural, not measured.\n'

printf -- '\n--- case D: shell still sane after the timeout\n'
jobtable=$(jobs)
check 'job table is empty' "${jobtable:-<empty>}" '<empty>'

printf '\n'
if [ "$FAILED" -eq 0 ]; then
    printf 'RESULT: run_bounded behaves correctly with no controlling terminal.\n'
    exit 0
fi
printf 'RESULT: %s check(s) failed — run_bounded is not safe on a tty-less runner.\n' "$FAILED"
exit 1
