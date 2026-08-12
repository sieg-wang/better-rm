#!/bin/bash
# CI suite aggregator contract / CI 測試套件匯總器契約

set -u

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
RUNNER="$SCRIPT_DIR/run-test-suites.sh"
WORKFLOW="$SCRIPT_DIR/.github/workflows/ci-release.yml"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/better-rm-suite-runner.XXXXXX")
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

assert_equal() {
    local name="$1"
    local expected="$2"
    local actual="$3"
    if [ "$expected" = "$actual" ]; then
        pass "$name"
    else
        fail "$name (expected: $expected, actual: $actual)"
    fi
}

test_job_invokes_public_runner() {
    awk '
        $0 == "  test:" { in_test = 1; next }
        in_test && /^  [[:alnum:]_-]+:/ { in_test = 0 }
        in_test && /^[[:space:]]+run:[[:space:]]+\.\/run-test-suites\.sh[[:space:]]*$/ {
            count += 1
        }
        END { exit(count == 1 ? 0 : 1) }
    ' "$1"
}

test_job_invokes_contract_directly() {
    awk '
        $0 == "  test:" { in_test = 1; next }
        in_test && /^  [[:alnum:]_-]+:/ { in_test = 0 }
        in_test && /^[[:space:]]+run:[[:space:]]+\.\/test-run-test-suites\.sh[[:space:]]*$/ {
            count += 1
        }
        END { exit(count == 1 ? 0 : 1) }
    ' "$1"
}

if [ ! -x "$RUNNER" ]; then
    fail "run-test-suites.sh exists and is executable"
    printf 'Passed: %s\nFailed: %s\n' "$PASSED" "$FAILED"
    exit 1
fi

PULL_REQUEST_TRIGGER_STATUS=0
awk '
    $0 == "on:" { in_on = 1; next }
    in_on && /^[^[:space:]]/ { in_on = 0 }
    in_on && /^  pull_request:/ { found = 1 }
    END { exit(found ? 0 : 1) }
' "$WORKFLOW" || PULL_REQUEST_TRIGGER_STATUS=$?
assert_equal "fork pull requests trigger the read-only test workflow" \
    "0" "$PULL_REQUEST_TRIGGER_STATUS"

WORKFLOW_DISPATCH_TRIGGER_STATUS=0
awk '
    $0 == "on:" { in_on = 1; next }
    in_on && /^[^[:space:]]/ { in_on = 0 }
    in_on && /^  workflow_dispatch:/ { found = 1 }
    END { exit(found ? 0 : 1) }
' "$WORKFLOW" || WORKFLOW_DISPATCH_TRIGGER_STATUS=$?
assert_equal "maintainers can trigger the test workflow manually" \
    "0" "$WORKFLOW_DISPATCH_TRIGGER_STATUS"

WORKFLOW_RUNNER_STATUS=0
test_job_invokes_public_runner "$WORKFLOW" || WORKFLOW_RUNNER_STATUS=$?
assert_equal "CI test job invokes the public aggregate runner exactly once" \
    "0" "$WORKFLOW_RUNNER_STATUS"

WORKFLOW_CONTRACT_STATUS=0
test_job_invokes_contract_directly "$WORKFLOW" || WORKFLOW_CONTRACT_STATUS=$?
assert_equal "CI test job invokes the aggregation contract independently" \
    "0" "$WORKFLOW_CONTRACT_STATUS"

# Prove this contract is sensitive to the regression it is meant to prevent:
# calling one suite directly must not count as wiring the aggregate runner.
# 證明此契約抓得到目標退化：直接執行單一 suite 不算接上公開匯總器。
WORKFLOW_DIRECT_MUTANT="$TMP_ROOT/workflow-direct-suite.yml"
sed 's#run: ./run-test-suites\.sh#run: ./test-better-rm.sh#' \
    "$WORKFLOW" > "$WORKFLOW_DIRECT_MUTANT"
WORKFLOW_MUTANT_STATUS=0
test_job_invokes_public_runner "$WORKFLOW_DIRECT_MUTANT" || WORKFLOW_MUTANT_STATUS=$?
if [ "$WORKFLOW_MUTANT_STATUS" -ne 0 ]; then
    pass "contract rejects a workflow that bypasses the aggregate runner"
else
    fail "contract rejects a workflow that bypasses the aggregate runner"
fi

FIXTURE="$TMP_ROOT/fixture"
FAKE_BIN="$TMP_ROOT/bin"
mkdir -p "$FIXTURE" "$FAKE_BIN"
cp "$RUNNER" "$FIXTURE/run-test-suites.sh"
chmod +x "$FIXTURE/run-test-suites.sh"

cat > "$FIXTURE/test-run-test-suites.sh" <<'EOF'
#!/bin/bash
printf 'contract\n' >> "$BETTER_RM_RUNNER_LOG"
exit "${BETTER_RM_CONTRACT_STATUS:-0}"
EOF

cat > "$FIXTURE/test-better-rm.sh" <<'EOF'
#!/bin/bash
printf 'core\n' >> "$BETTER_RM_RUNNER_LOG"
exit "${BETTER_RM_CORE_STATUS:-0}"
EOF

cat > "$FIXTURE/test-hooks.js" <<'EOF'
// The fake node executable records this suite; the body is intentionally inert.
EOF

cat > "$FIXTURE/test-guard-parity.js" <<'EOF'
// The fake node executable records this suite; the body is intentionally inert.
EOF

cat > "$FIXTURE/test-install-hooks.sh" <<'EOF'
#!/bin/bash
printf 'installer\n' >> "$BETTER_RM_RUNNER_LOG"
exit "${BETTER_RM_INSTALLER_STATUS:-0}"
EOF

# One fake node stands in for both Node suites, so it has to tell them apart by
# the script it was handed. A stub that logged the same name for both would let
# the runner drop either suite while the manifest still looked complete.
# 兩套 Node suite 共用同一個假 node，必須靠傳進來的腳本區分：兩套都記同一個名字
# 的話，runner 少跑其中一套，manifest 看起來仍然是完整的。
cat > "$FAKE_BIN/node" <<'EOF'
#!/bin/bash
case "$1" in
    *test-hooks.js)
        printf 'hooks\n' >> "$BETTER_RM_RUNNER_LOG"
        exit "${BETTER_RM_HOOK_STATUS:-0}"
        ;;
    *test-guard-parity.js)
        printf 'parity\n' >> "$BETTER_RM_RUNNER_LOG"
        exit "${BETTER_RM_PARITY_STATUS:-0}"
        ;;
esac
printf 'unknown-node-suite:%s\n' "$1" >> "$BETTER_RM_RUNNER_LOG"
exit 1
EOF

chmod +x "$FIXTURE/test-run-test-suites.sh" "$FIXTURE/test-better-rm.sh" \
    "$FIXTURE/test-install-hooks.sh" "$FAKE_BIN/node"

# The contract itself is part of the public manifest. The workflow executes it
# independently too, so either path catches omission of the other.
CONTRACT_FAIL_LOG="$TMP_ROOT/contract-fail.log"
CONTRACT_FAIL_STATUS=0
PATH="$FAKE_BIN:$PATH" BETTER_RM_RUNNER_LOG="$CONTRACT_FAIL_LOG" \
    BETTER_RM_CONTRACT_STATUS=13 \
    "$FIXTURE/run-test-suites.sh" >/dev/null 2>&1 || CONTRACT_FAIL_STATUS=$?
assert_equal "runner reports an aggregation-contract-only failure" "1" "$CONTRACT_FAIL_STATUS"
assert_equal "runner completes the manifest after an aggregation-contract failure" \
    "$(printf 'contract\ncore\nhooks\nparity\ninstaller')" \
    "$(cat "$CONTRACT_FAIL_LOG" 2>/dev/null)"

# The earliest suite fails. The public runner must still invoke both later suites,
# then return failure only after every result has been observed.
# 第一套故意失敗；公開 runner 仍須執行後兩套，最後才匯總成失敗。
FAIL_LOG="$TMP_ROOT/fail.log"
FAIL_STATUS=0
PATH="$FAKE_BIN:$PATH" BETTER_RM_RUNNER_LOG="$FAIL_LOG" BETTER_RM_CORE_STATUS=17 \
    "$FIXTURE/run-test-suites.sh" >/dev/null 2>&1 || FAIL_STATUS=$?
assert_equal "runner reports aggregate failure" "1" "$FAIL_STATUS"
assert_equal "runner continues through all suites after the first failure" \
    "$(printf 'contract\ncore\nhooks\nparity\ninstaller')" "$(cat "$FAIL_LOG" 2>/dev/null)"

# Each later suite gets its own failing leg. Otherwise a runner that aggregates
# only the first command's status still satisfies the continuation test above.
HOOK_FAIL_LOG="$TMP_ROOT/hook-fail.log"
HOOK_FAIL_STATUS=0
PATH="$FAKE_BIN:$PATH" BETTER_RM_RUNNER_LOG="$HOOK_FAIL_LOG" BETTER_RM_HOOK_STATUS=23 \
    "$FIXTURE/run-test-suites.sh" >/dev/null 2>&1 || HOOK_FAIL_STATUS=$?
assert_equal "runner reports a runtime-hook-only failure" "1" "$HOOK_FAIL_STATUS"
assert_equal "runner completes the manifest after a runtime-hook failure" \
    "$(printf 'contract\ncore\nhooks\nparity\ninstaller')" "$(cat "$HOOK_FAIL_LOG" 2>/dev/null)"

# The guard-parity suite reserves a distinct exit code (99) for "the probe itself
# is broken". The aggregator must treat that as a failure like any other, or a
# harness that stopped measuring anything would be reported as a passing suite.
# guard-parity 用 99 代表「探針壞了」；匯總器必須照樣當成失敗，否則量不到東西的
# 探針會被回報成通過。
PARITY_FAIL_LOG="$TMP_ROOT/parity-fail.log"
PARITY_FAIL_STATUS=0
PATH="$FAKE_BIN:$PATH" BETTER_RM_RUNNER_LOG="$PARITY_FAIL_LOG" BETTER_RM_PARITY_STATUS=99 \
    "$FIXTURE/run-test-suites.sh" >/dev/null 2>&1 || PARITY_FAIL_STATUS=$?
assert_equal "runner reports a guard-parity-only failure" "1" "$PARITY_FAIL_STATUS"
assert_equal "runner completes the manifest after a guard-parity failure" \
    "$(printf 'contract\ncore\nhooks\nparity\ninstaller')" "$(cat "$PARITY_FAIL_LOG" 2>/dev/null)"

INSTALLER_FAIL_LOG="$TMP_ROOT/installer-fail.log"
INSTALLER_FAIL_STATUS=0
PATH="$FAKE_BIN:$PATH" BETTER_RM_RUNNER_LOG="$INSTALLER_FAIL_LOG" \
    BETTER_RM_INSTALLER_STATUS=29 \
    "$FIXTURE/run-test-suites.sh" >/dev/null 2>&1 || INSTALLER_FAIL_STATUS=$?
assert_equal "runner reports an installer-only failure" "1" "$INSTALLER_FAIL_STATUS"
assert_equal "runner records the complete manifest on an installer failure" \
    "$(printf 'contract\ncore\nhooks\nparity\ninstaller')" "$(cat "$INSTALLER_FAIL_LOG" 2>/dev/null)"

PASS_LOG="$TMP_ROOT/pass.log"
PASS_STATUS=0
PATH="$FAKE_BIN:$PATH" BETTER_RM_RUNNER_LOG="$PASS_LOG" \
    "$FIXTURE/run-test-suites.sh" >/dev/null 2>&1 || PASS_STATUS=$?
assert_equal "runner succeeds when every suite succeeds" "0" "$PASS_STATUS"
assert_equal "successful runner invokes each suite exactly once" \
    "$(printf 'contract\ncore\nhooks\nparity\ninstaller')" "$(cat "$PASS_LOG" 2>/dev/null)"

printf 'Passed: %s\nFailed: %s\n' "$PASSED" "$FAILED"
if [ "$FAILED" -ne 0 ]; then
    exit 1
fi
