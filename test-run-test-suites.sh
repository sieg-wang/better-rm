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

cat > "$FIXTURE/test-install.sh" <<'EOF'
#!/bin/bash
printf 'source-installer\n' >> "$BETTER_RM_RUNNER_LOG"
exit "${BETTER_RM_SOURCE_INSTALLER_STATUS:-0}"
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
    "$FIXTURE/test-install.sh" "$FIXTURE/test-install-hooks.sh" "$FAKE_BIN/node"

# The contract itself is part of the public manifest. The workflow executes it
# independently too, so either path catches omission of the other.
CONTRACT_FAIL_LOG="$TMP_ROOT/contract-fail.log"
CONTRACT_FAIL_STATUS=0
PATH="$FAKE_BIN:$PATH" BETTER_RM_RUNNER_LOG="$CONTRACT_FAIL_LOG" \
    BETTER_RM_CONTRACT_STATUS=13 \
    "$FIXTURE/run-test-suites.sh" >/dev/null 2>&1 || CONTRACT_FAIL_STATUS=$?
assert_equal "runner reports an aggregation-contract-only failure" "1" "$CONTRACT_FAIL_STATUS"
assert_equal "runner completes the manifest after an aggregation-contract failure" \
    "$(printf 'contract\ncore\nhooks\nparity\nsource-installer\ninstaller')" \
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
    "$(printf 'contract\ncore\nhooks\nparity\nsource-installer\ninstaller')" "$(cat "$FAIL_LOG" 2>/dev/null)"

# Each later suite gets its own failing leg. Otherwise a runner that aggregates
# only the first command's status still satisfies the continuation test above.
HOOK_FAIL_LOG="$TMP_ROOT/hook-fail.log"
HOOK_FAIL_STATUS=0
PATH="$FAKE_BIN:$PATH" BETTER_RM_RUNNER_LOG="$HOOK_FAIL_LOG" BETTER_RM_HOOK_STATUS=23 \
    "$FIXTURE/run-test-suites.sh" >/dev/null 2>&1 || HOOK_FAIL_STATUS=$?
assert_equal "runner reports a runtime-hook-only failure" "1" "$HOOK_FAIL_STATUS"
assert_equal "runner completes the manifest after a runtime-hook failure" \
    "$(printf 'contract\ncore\nhooks\nparity\nsource-installer\ninstaller')" "$(cat "$HOOK_FAIL_LOG" 2>/dev/null)"

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
    "$(printf 'contract\ncore\nhooks\nparity\nsource-installer\ninstaller')" "$(cat "$PARITY_FAIL_LOG" 2>/dev/null)"

SOURCE_INSTALLER_FAIL_LOG="$TMP_ROOT/source-installer-fail.log"
SOURCE_INSTALLER_FAIL_STATUS=0
PATH="$FAKE_BIN:$PATH" BETTER_RM_RUNNER_LOG="$SOURCE_INSTALLER_FAIL_LOG" \
    BETTER_RM_SOURCE_INSTALLER_STATUS=27 \
    "$FIXTURE/run-test-suites.sh" >/dev/null 2>&1 || SOURCE_INSTALLER_FAIL_STATUS=$?
assert_equal "runner reports a source-installer-only failure" "1" "$SOURCE_INSTALLER_FAIL_STATUS"
assert_equal "runner records the complete manifest on a source-installer failure" \
    "$(printf 'contract\ncore\nhooks\nparity\nsource-installer\ninstaller')" \
    "$(cat "$SOURCE_INSTALLER_FAIL_LOG" 2>/dev/null)"

INSTALLER_FAIL_LOG="$TMP_ROOT/installer-fail.log"
INSTALLER_FAIL_STATUS=0
PATH="$FAKE_BIN:$PATH" BETTER_RM_RUNNER_LOG="$INSTALLER_FAIL_LOG" \
    BETTER_RM_INSTALLER_STATUS=29 \
    "$FIXTURE/run-test-suites.sh" >/dev/null 2>&1 || INSTALLER_FAIL_STATUS=$?
assert_equal "runner reports an installer-only failure" "1" "$INSTALLER_FAIL_STATUS"
assert_equal "runner records the complete manifest on an installer failure" \
    "$(printf 'contract\ncore\nhooks\nparity\nsource-installer\ninstaller')" "$(cat "$INSTALLER_FAIL_LOG" 2>/dev/null)"

PASS_LOG="$TMP_ROOT/pass.log"
PASS_STATUS=0
PATH="$FAKE_BIN:$PATH" BETTER_RM_RUNNER_LOG="$PASS_LOG" \
    "$FIXTURE/run-test-suites.sh" >/dev/null 2>&1 || PASS_STATUS=$?
assert_equal "runner succeeds when every suite succeeds" "0" "$PASS_STATUS"
assert_equal "successful runner invokes each suite exactly once" \
    "$(printf 'contract\ncore\nhooks\nparity\nsource-installer\ninstaller')" "$(cat "$PASS_LOG" 2>/dev/null)"

# ---------------------------------------------------------------------------
# 解析檢查掃描：每一個追蹤中的 shell 與 JS 檔（含 better-rm 自己）都必須解析得過。
# 這道掃描補的是一個「執行覆蓋率」的洞，不是「行為」的洞：run-test-suites.sh 的
# 清單有六套，而 test/residual-harness 下的 13 個追蹤檔與 593 行的
# bump-and-release.sh 不在任何一套裡——沒有任何 gate 會執行它們，也就沒有任何
# gate 會發現它們連解析都過不了。實測：在 git archive 出來的副本裡把一個未閉合的
# `if true; then` 附加到 test/residual-harness/repeat-core.sh，六套測試全綠。
# bump-and-release.sh 的第一次真正執行是一次「發佈」，那不是適合發現語法錯誤的時機。
# A parse-only sweep over every tracked shell and JS file, better-rm included.
# It closes an EXECUTION-COVERAGE gap rather than a behavioural one: the runner's
# manifest names six suites, and the 13 tracked files under test/residual-harness
# plus the 593-line bump-and-release.sh are in none of them -- no gate runs them,
# so no gate notices when they stop parsing. Measured: appending an unterminated
# `if true; then` to test/residual-harness/repeat-core.sh in a git-archive copy
# leaves all six suites GREEN. bump-and-release.sh's first real run is a
# publication, which is not the moment to discover a syntax error.
#
# 刻意用 /bin/bash 而不是 PATH 上的 bash：這台機器的 /bin/bash 是 3.2.57，而這些腳本
# 真正跑在哪個直譯器下就是它（launchd 與 shebang 都指向它），PATH 上的 bash 是 5.3。
# ubuntu runner 的 /bin/bash 是 5.x，所以 3.2 那一半只在本機真的會動——不要為了讓兩台
# 主機一致就改成裸 bash -n，那等於把本機這一半關掉。
# /bin/bash deliberately, not `bash` from PATH: /bin/bash here is 3.2.57 and that
# is the interpreter half of these scripts really run under, while `bash` on PATH
# is 5.3. The ubuntu runner's /bin/bash is 5.x, so the 3.2 half only really fires
# locally -- do NOT weaken this to a bare `bash -n` to make the two hosts agree.
#
# git ls-files 是首選,因為那就是 CI 檢出的清單;git archive 解出來的樹沒有 .git,所以
# 有 find 作為後備。兩者都空代表這道掃描自己壞了,必須大聲失敗而不是靜靜通過——
# 「什麼都沒檢查卻是綠的」正是它要防的那個形狀。
# git ls-files first, because that is the list CI checks out; a git-archive tree
# has no .git, so find is the fallback. An empty list from both means this sweep
# is itself broken and must fail loudly rather than pass in silence -- "checked
# nothing and stayed green" is the exact shape it exists to catch.
PARSE_SWEEP_SH_LIST="$TMP_ROOT/parse-sweep-sh.txt"
PARSE_SWEEP_JS_LIST="$TMP_ROOT/parse-sweep-js.txt"
( cd "$SCRIPT_DIR" && git ls-files '*.sh' 2>/dev/null ) > "$PARSE_SWEEP_SH_LIST"
if [ ! -s "$PARSE_SWEEP_SH_LIST" ]; then
    ( cd "$SCRIPT_DIR" && find . -type f -name '*.sh' | sed 's|^\./||' | sort ) > "$PARSE_SWEEP_SH_LIST"
fi
printf '%s\n' 'better-rm' >> "$PARSE_SWEEP_SH_LIST"
( cd "$SCRIPT_DIR" && git ls-files '*.js' 2>/dev/null ) > "$PARSE_SWEEP_JS_LIST"
if [ ! -s "$PARSE_SWEEP_JS_LIST" ]; then
    ( cd "$SCRIPT_DIR" && find . -type f -name '*.js' | sed 's|^\./||' | sort ) > "$PARSE_SWEEP_JS_LIST"
fi

PARSE_SWEEP_PROBLEMS=""
PARSE_SWEEP_SH_COUNT=0
# 從「檔案」而不是 pipe 讀進來：pipe 會讓迴圈跑在 subshell 裡，計數與問題清單都會在
# 迴圈結束時消失，這道掃描就會永遠回報 0 個問題。
# Read from a FILE, not a pipe: a pipe puts the loop in a subshell and both the
# counter and the problem list vanish when it ends, which would make this sweep
# report zero problems for ever.
while IFS= read -r parse_sweep_file; do
    [ -n "$parse_sweep_file" ] || continue
    [ -f "$SCRIPT_DIR/$parse_sweep_file" ] || continue
    PARSE_SWEEP_SH_COUNT=$((PARSE_SWEEP_SH_COUNT + 1))
    /bin/bash -n "$SCRIPT_DIR/$parse_sweep_file" 2>/dev/null ||
        PARSE_SWEEP_PROBLEMS="$PARSE_SWEEP_PROBLEMS $parse_sweep_file(bash -n)"
done < "$PARSE_SWEEP_SH_LIST"

PARSE_SWEEP_JS_COUNT=0
while IFS= read -r parse_sweep_file; do
    [ -n "$parse_sweep_file" ] || continue
    [ -f "$SCRIPT_DIR/$parse_sweep_file" ] || continue
    PARSE_SWEEP_JS_COUNT=$((PARSE_SWEEP_JS_COUNT + 1))
    node --check "$SCRIPT_DIR/$parse_sweep_file" >/dev/null 2>&1 ||
        PARSE_SWEEP_PROBLEMS="$PARSE_SWEEP_PROBLEMS $parse_sweep_file(node --check)"
done < "$PARSE_SWEEP_JS_LIST"

if [ "$PARSE_SWEEP_SH_COUNT" -ge 2 ] && [ "$PARSE_SWEEP_JS_COUNT" -ge 1 ]; then
    pass "the parse sweep found files to check (shell=$PARSE_SWEEP_SH_COUNT, js=$PARSE_SWEEP_JS_COUNT)"
else
    fail "the parse sweep found nothing to check (shell=$PARSE_SWEEP_SH_COUNT, js=$PARSE_SWEEP_JS_COUNT)"
fi
if [ -z "$PARSE_SWEEP_PROBLEMS" ]; then
    pass "every tracked shell and JS file parses, including the ones no suite runs"
else
    fail "files that do not parse:$PARSE_SWEEP_PROBLEMS"
fi

printf 'Passed: %s\nFailed: %s\n' "$PASSED" "$FAILED"
if [ "$FAILED" -ne 0 ]; then
    exit 1
fi
