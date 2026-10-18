#!/bin/bash
# test-hooks.js 的檔尾結束碼，從外面驗 / The runtime-hook suite's end-of-file exit, checked from outside
#
# test-hooks.js RECORDS a missed wall-clock budget instead of throwing it, runs
# to the end, prints its pass count and then exits 1, naming each miss
# (timingBudget). Nothing checked that last step: with the exit-1 branch at the
# end of the file deleted, every suite stayed green, so a missed budget would
# have been printed and passed. This runs the real file with
# BETTER_RM_HOOK_TEST_FORCE_TIMING_MISS=1, which makes every timing row miss,
# and requires exit 1, the pass count, the forced misses on stderr and a
# summary that counts exactly those misses.
# test-hooks.js 遇到牆鐘預算沒達到時是「記下來」而不是丟例外，跑到底、印出通過數，最後以 1 結束並逐一
# 指名。最後那一步沒有任何測試在驗：把檔尾那段「以 1 結束」刪掉，每一套都還是綠的，於是沒達到的預算只會
# 被印出來、然後算通過。這裡用 BETTER_RM_HOOK_TEST_FORCE_TIMING_MISS=1（讓每個計時列都算沒達到）執行
# 真的檔案，要求結束碼 1、通過數、stderr 上被強制的未達列，以及剛好數到那些列的總結。

set -u

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/better-rm-timing-miss.XXXXXX")
PASSED=0
FAILED=0

cleanup() {
    rm -rf -- "$TMP_ROOT"
}
trap cleanup EXIT

pass() {
    PASSED=$((PASSED + 1))
    printf '✓ %s\n' "$1"
}

fail() {
    FAILED=$((FAILED + 1))
    printf '✗ %s\n' "$1" >&2
}

STATUS=0
BETTER_RM_HOOK_TEST_FORCE_TIMING_MISS=1 node "$SCRIPT_DIR/test-hooks.js" \
    > "$TMP_ROOT/out" 2> "$TMP_ROOT/err" || STATUS=$?

if [ "$STATUS" -eq 1 ]; then
    pass "a run with every timing row missed exits 1"
else
    fail "a run with every timing row missed exits 1 (status $STATUS)"
fi

if grep -q 'Hook tests passed: [0-9][0-9]*' "$TMP_ROOT/out"; then
    pass "a run with every timing row missed still reaches its pass count"
else
    fail "a run with every timing row missed still reaches its pass count"
fi

FORCED_MISSES=$(grep -c 'TIMING BUDGET MISSED: .*\[forced\]' "$TMP_ROOT/err")
SUMMARY_COUNT=$(sed -n 's/^\([0-9][0-9]*\) wall-clock budget(s) missed; every other assertion in this file ran.*/\1/p' "$TMP_ROOT/err")
if [ "$FORCED_MISSES" -gt 0 ] && [ "$SUMMARY_COUNT" = "$FORCED_MISSES" ]; then
    pass "each forced miss is named and the summary counts them ($FORCED_MISSES)"
else
    fail "each forced miss is named and the summary counts them (named: $FORCED_MISSES, summary: ${SUMMARY_COUNT:-none})"
fi

if grep -q 'AssertionError' "$TMP_ROOT/err"; then
    fail "no ordinary assertion fails in a run with every timing row missed"
else
    pass "no ordinary assertion fails in a run with every timing row missed"
fi

printf 'Passed: %s\nFailed: %s\n' "$PASSED" "$FAILED"
if [ "$FAILED" -ne 0 ]; then
    exit 1
fi
