#!/bin/bash
# Run every repository suite and report failure only after all have finished.
# 執行所有 repository suite，全部結束後才匯總失敗。

set -u

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
FAILED=0

run_suite() {
    local label="$1"
    shift

    printf '\n==> %s\n' "$label"
    local status=0
    "$@" || status=$?
    if [ "$status" -eq 0 ]; then
        printf '<== PASS: %s\n' "$label"
    else
        printf '<== FAIL: %s (status=%s)\n' "$label" "$status" >&2
        FAILED=1
    fi
}

# The workflow also runs this contract directly. Keeping it in the public
# runner creates a mutual guard: removing either CI step still leaves the other
# path able to detect that the workflow bypassed or the runner omitted it.
run_suite "CI suite aggregation contract" "$SCRIPT_DIR/test-run-test-suites.sh"
run_suite "better-rm core" "$SCRIPT_DIR/test-better-rm.sh"
run_suite "runtime hooks" node "$SCRIPT_DIR/test-hooks.js"
# The exec-wrapper table's guarantee, and the reason it can be a PINNED LIST at
# all. The platform sweep that used to discover those names read man-page sources
# and was removed for not converging; this suite replaces it by comparing the
# pinned names against the hook's table in BOTH directions -- a deletion goes red,
# and so does an addition nobody wrote down -- and exercising every row with shapes
# generated from the row's own fields. It is named in the hook's own comment as the
# thing that replaced the sweep, so it has to be in this manifest: a suite the
# runner never invokes provides zero protection however green it is on its own.
# What it deliberately does NOT promise is anything about names that are not in the
# table; KNOWN-RESIDUALS.md R6-a names the unmodelled ones.
# exec-wrapper 表的保證，也是它能是一份「固定清單」的原因。原本找出那些名字的平台掃描要讀
# man page 原始碼，因為不收斂而被移除；這一套取而代之：雙向比對固定清單與 hook 的表（少一
# 列會紅，多一列沒人寫下來也會紅），並用每一列自己的欄位產生形狀走訪它。hook 自己的註解點
# 名它是掃描的替代品，所以它必須在這份清單裡——runner 從不呼叫的 suite，自己跑得再綠也是
# 零保護。它刻意不承諾任何關於表外名字的事，已知未建模的寫在 KNOWN-RESIDUALS.md R6-a。
run_suite "exec-wrapper model" node "$SCRIPT_DIR/test-wrapper-model.js"
# The two guards' verdicts, diffed over one shared corpus. The suites above test
# each guard against its own expectations; only this one can see a rule that
# exists in one guard and not the other.
# 兩道守衛對同一份語料的判定差分。上面各套只驗各自的期望，唯有這套看得見「規則只
# 存在於其中一邊」。
run_suite "guard parity" node "$SCRIPT_DIR/test-guard-parity.js"
run_suite "install/update provenance" "$SCRIPT_DIR/test-install.sh"
run_suite "hook installer" "$SCRIPT_DIR/test-install-hooks.sh"
run_suite "release script remote targeting" "$SCRIPT_DIR/test-bump-and-release.sh"

if [ "$FAILED" -ne 0 ]; then
    printf '\nOne or more repository test suites failed.\n' >&2
    exit 1
fi

printf '\nAll repository test suites passed.\n'
