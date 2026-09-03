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
