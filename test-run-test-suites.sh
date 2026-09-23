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

cat > "$FIXTURE/test-wrapper-model.js" <<'EOF'
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

cat > "$FIXTURE/test-bump-and-release.sh" <<'EOF'
#!/bin/bash
printf 'release\n' >> "$BETTER_RM_RUNNER_LOG"
exit "${BETTER_RM_RELEASE_STATUS:-0}"
EOF

# One fake node stands in for all THREE Node suites, so it has to tell them apart
# by the script it was handed. A stub that logged the same name for any two of them
# would let the runner drop one while the manifest still looked complete.
# 三套 Node suite 共用同一個假 node，必須靠傳進來的腳本區分：其中兩套記同一個名字
# 的話，runner 少跑其中一套，manifest 看起來仍然是完整的。
cat > "$FAKE_BIN/node" <<'EOF'
#!/bin/bash
case "$1" in
    *test-hooks.js)
        printf 'hooks\n' >> "$BETTER_RM_RUNNER_LOG"
        exit "${BETTER_RM_HOOK_STATUS:-0}"
        ;;
    *test-wrapper-model.js)
        printf 'wrapper-model\n' >> "$BETTER_RM_RUNNER_LOG"
        exit "${BETTER_RM_WRAPPER_MODEL_STATUS:-0}"
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
    "$FIXTURE/test-install.sh" "$FIXTURE/test-install-hooks.sh" \
    "$FIXTURE/test-bump-and-release.sh" "$FAKE_BIN/node"

# The contract itself is part of the public manifest. The workflow executes it
# independently too, so either path catches omission of the other.
CONTRACT_FAIL_LOG="$TMP_ROOT/contract-fail.log"
CONTRACT_FAIL_STATUS=0
PATH="$FAKE_BIN:$PATH" BETTER_RM_RUNNER_LOG="$CONTRACT_FAIL_LOG" \
    BETTER_RM_CONTRACT_STATUS=13 \
    "$FIXTURE/run-test-suites.sh" >/dev/null 2>&1 || CONTRACT_FAIL_STATUS=$?
assert_equal "runner reports an aggregation-contract-only failure" "1" "$CONTRACT_FAIL_STATUS"
assert_equal "runner completes the manifest after an aggregation-contract failure" \
    "$(printf 'contract\ncore\nhooks\nwrapper-model\nparity\nsource-installer\ninstaller\nrelease')" \
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
    "$(printf 'contract\ncore\nhooks\nwrapper-model\nparity\nsource-installer\ninstaller\nrelease')" "$(cat "$FAIL_LOG" 2>/dev/null)"

# Each later suite gets its own failing leg. Otherwise a runner that aggregates
# only the first command's status still satisfies the continuation test above.
HOOK_FAIL_LOG="$TMP_ROOT/hook-fail.log"
HOOK_FAIL_STATUS=0
PATH="$FAKE_BIN:$PATH" BETTER_RM_RUNNER_LOG="$HOOK_FAIL_LOG" BETTER_RM_HOOK_STATUS=23 \
    "$FIXTURE/run-test-suites.sh" >/dev/null 2>&1 || HOOK_FAIL_STATUS=$?
assert_equal "runner reports a runtime-hook-only failure" "1" "$HOOK_FAIL_STATUS"
assert_equal "runner completes the manifest after a runtime-hook failure" \
    "$(printf 'contract\ncore\nhooks\nwrapper-model\nparity\nsource-installer\ninstaller\nrelease')" "$(cat "$HOOK_FAIL_LOG" 2>/dev/null)"

# The wrapper-model suite is the guarantee that REPLACED the platform sweep deleted
# from test-hooks.js: it is the only thing that goes red when a row is removed from
# the exec-wrapper table, or added to it without being written down. A suite that is
# not in the runner's manifest provides ZERO protection no matter how well it passes
# on its own, so it gets its own failing leg here -- without one, the runner could
# drop the suite entirely and every other assertion in this file would stay green.
# Measured: with the manifest rows below updated and the runner NOT yet wired, this
# leg reported FAIL_STATUS=0 (the runner never ran the suite, so nothing failed).
# wrapper-model 這套是「取代 test-hooks.js 裡被刪掉的平台掃描」的那個保證：exec-wrapper
# 表少一列、或多一列沒人寫下來時，只有它會紅。不在 runner 清單裡的 suite，自己跑得再綠也
# 是零保護，所以它必須有自己的失敗腳；沒有這一腳，runner 整套漏掉它，本檔其他斷言全都還
# 是綠的。實測：下面的清單列改好、runner 還沒接上時，這一腳回報 FAIL_STATUS=0。
WRAPPER_MODEL_FAIL_LOG="$TMP_ROOT/wrapper-model-fail.log"
WRAPPER_MODEL_FAIL_STATUS=0
PATH="$FAKE_BIN:$PATH" BETTER_RM_RUNNER_LOG="$WRAPPER_MODEL_FAIL_LOG" \
    BETTER_RM_WRAPPER_MODEL_STATUS=31 \
    "$FIXTURE/run-test-suites.sh" >/dev/null 2>&1 || WRAPPER_MODEL_FAIL_STATUS=$?
assert_equal "runner reports a wrapper-model-only failure" "1" "$WRAPPER_MODEL_FAIL_STATUS"
assert_equal "runner completes the manifest after a wrapper-model failure" \
    "$(printf 'contract\ncore\nhooks\nwrapper-model\nparity\nsource-installer\ninstaller\nrelease')" \
    "$(cat "$WRAPPER_MODEL_FAIL_LOG" 2>/dev/null)"

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
    "$(printf 'contract\ncore\nhooks\nwrapper-model\nparity\nsource-installer\ninstaller\nrelease')" "$(cat "$PARITY_FAIL_LOG" 2>/dev/null)"

SOURCE_INSTALLER_FAIL_LOG="$TMP_ROOT/source-installer-fail.log"
SOURCE_INSTALLER_FAIL_STATUS=0
PATH="$FAKE_BIN:$PATH" BETTER_RM_RUNNER_LOG="$SOURCE_INSTALLER_FAIL_LOG" \
    BETTER_RM_SOURCE_INSTALLER_STATUS=27 \
    "$FIXTURE/run-test-suites.sh" >/dev/null 2>&1 || SOURCE_INSTALLER_FAIL_STATUS=$?
assert_equal "runner reports a source-installer-only failure" "1" "$SOURCE_INSTALLER_FAIL_STATUS"
assert_equal "runner records the complete manifest on a source-installer failure" \
    "$(printf 'contract\ncore\nhooks\nwrapper-model\nparity\nsource-installer\ninstaller\nrelease')" \
    "$(cat "$SOURCE_INSTALLER_FAIL_LOG" 2>/dev/null)"

INSTALLER_FAIL_LOG="$TMP_ROOT/installer-fail.log"
INSTALLER_FAIL_STATUS=0
PATH="$FAKE_BIN:$PATH" BETTER_RM_RUNNER_LOG="$INSTALLER_FAIL_LOG" \
    BETTER_RM_INSTALLER_STATUS=29 \
    "$FIXTURE/run-test-suites.sh" >/dev/null 2>&1 || INSTALLER_FAIL_STATUS=$?
assert_equal "runner reports an installer-only failure" "1" "$INSTALLER_FAIL_STATUS"
assert_equal "runner records the complete manifest on an installer failure" \
    "$(printf 'contract\ncore\nhooks\nwrapper-model\nparity\nsource-installer\ninstaller\nrelease')" "$(cat "$INSTALLER_FAIL_LOG" 2>/dev/null)"

PASS_LOG="$TMP_ROOT/pass.log"
PASS_STATUS=0
PATH="$FAKE_BIN:$PATH" BETTER_RM_RUNNER_LOG="$PASS_LOG" \
    "$FIXTURE/run-test-suites.sh" >/dev/null 2>&1 || PASS_STATUS=$?
assert_equal "runner succeeds when every suite succeeds" "0" "$PASS_STATUS"
assert_equal "successful runner invokes each suite exactly once" \
    "$(printf 'contract\ncore\nhooks\nwrapper-model\nparity\nsource-installer\ninstaller\nrelease')" "$(cat "$PASS_LOG" 2>/dev/null)"

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

# ---------------------------------------------------------------------------
# GNU-ONLY REGEX CONSTRUCTS IN A BASIC-REGEX sed
# 在基本正則的 sed 裡用了 GNU 專有的寫法
# ---------------------------------------------------------------------------
# `sed 's#/\+#/#g'` stood in better-rm's normalize_path and did not do what it
# said: BSD sed's basic regular expressions have no `\+` quantifier, so on macOS it
# rewrote a LITERAL '/+' to '/'. WHICH STAGE yields which value matters, and this
# note used to merge the two (re-measured 2026-09-23): the sed step alone turned
# '/a//b/+c' into '/a//b/c' -- the slash before the `+` went with the `+`, the
# doubled '//' was untouched -- and it took normalize_path's IFS='/' split, dropping
# the empty component, to reach '/a/b/c'. GNU sed 4.10 got '/a/b/+c' out of the sed
# step itself. The platform divergence is real either way, once normalize_path
# returns: '/a/b/c' on BSD against '/a/b/+c' on GNU. Nothing caught it, and nothing
# could have: CI ran only ubuntu, where the line behaves. The test that was missing is not a row about
# that one regex, it is this sweep -- because the next GNU-ism will be written on a
# machine whose login PATH happens to resolve `sed` to GNU (measured: this one's
# does in a login bash, while the agent's PATH gets BSD sed, so the same script
# behaves differently depending on which shell invoked it).
# Comment lines are skipped on purpose: the two files that EXPLAIN this defect
# quote the offending expression, and a guard that cannot tell an explanation from
# an instruction would have to be deleted the first time someone documented it.
# 兩個階段的值不同，別再併成一句：sed 那一步得到 '/a//b/c'，IFS='/' 分詞丟掉空段之後才是
# '/a/b/c'；GNU sed 4.10 在 sed 那一步就得到 '/a/b/+c'。
# 這道清查掃的是「基本正則的 sed 用了 GNU 專有寫法」。缺的測試不是「那一條 regex 的列」，
# 而是這個清查：下一個 GNU-ism 會寫在「登入 shell 的 PATH 剛好指到 GNU sed」的機器上。
# 註解行刻意跳過：解釋這個缺陷的兩個檔案都引用了那段運算式。
GNU_BRE_PROBLEMS=""
GNU_BRE_SCANNED=0
GNU_BRE_HITS=0
# 豁免格式為 file:line，要寫理由。目前沒有豁免項。
# Exemptions are `file:line` and carry a reason. There are none.
GNU_BRE_EXEMPT=""
# 這兩個樣式刻意各自寫在「不含工具名」與「不含 GNU 寫法」的行上，否則這道清查會抓到
# 自己的樣式行。分開寫比為自己開豁免誠實。
# The two patterns are deliberately written on lines holding, respectively, no
# occurrence of the tool's name and no GNU construct: otherwise this sweep matches
# its OWN pattern line. Splitting them is more honest than exempting itself.
GNU_BRE_CONSTRUCTS='\\\+|\\\?|\\\||\\\{[0-9]'
GNU_BRE_INPLACE='-i([[:space:]]|$)'
while IFS= read -r portability_file; do
    [ -n "$portability_file" ] || continue
    [ -f "$SCRIPT_DIR/$portability_file" ] || continue
    GNU_BRE_SCANNED=$((GNU_BRE_SCANNED + 1))
    while IFS= read -r portability_hit; do
        [ -n "$portability_hit" ] || continue
        portability_where="$portability_file:${portability_hit%%:*}"
        case " $GNU_BRE_EXEMPT " in
            *" $portability_where "*) continue ;;
        esac
        GNU_BRE_HITS=$((GNU_BRE_HITS + 1))
        GNU_BRE_PROBLEMS="$GNU_BRE_PROBLEMS $portability_where"
    done <<PORTABILITY_HITS
$(grep -n 'sed' "$SCRIPT_DIR/$portability_file" |
    grep -vE '^[0-9]+:[[:space:]]*#' |
    grep -E "$GNU_BRE_CONSTRUCTS|sed[[:space:]]+$GNU_BRE_INPLACE" |
    grep -vE 'sed[[:space:]]+-[A-Za-z]*[Er]')
PORTABILITY_HITS
done < "$PARSE_SWEEP_SH_LIST"

if [ "$GNU_BRE_SCANNED" -ge 2 ]; then
    pass "the portability sweep read files to check ($GNU_BRE_SCANNED)"
else
    fail "the portability sweep read $GNU_BRE_SCANNED files; it would pass vacuously"
fi
if [ "$GNU_BRE_HITS" -eq 0 ]; then
    pass "no shell file uses a GNU-only regex construct in a basic-regex sed"
else
    fail "GNU-only sed constructs that behave differently under BSD sed:$GNU_BRE_PROBLEMS"
fi

# ---------------------------------------------------------------------------
# THE PLATFORMS THE GUARD BRANCHES ON, AGAINST THE PLATFORMS CI ACTUALLY RUNS
# 守衛分支涵蓋的平台，對上 CI 真正跑過的平台
# ---------------------------------------------------------------------------
# better-rm branches on `uname -s`, and the Darwin/BSD arm is the one that moves a
# file into the trash without following a symlink (`mv "$1" -h -- "$2" "$3"`); the
# BSD half of every `stat -c ... || stat -f ...` pair is the same kind of arm. The
# workflow had exactly one job on exactly one ubuntu runner and there is no local
# pre-push hook, so every one of those arms shipped through ZERO automated
# verification -- the macOS suite run was a thing a human remembered to do. The
# failure mode is not cosmetic: a trash move that follows a symlink destroys what
# the link points at, on the one path better-rm exists to make recoverable.
# A second runner alone would not keep this true, because the next BSD-only arm
# someone writes is invisible to it. So this test enumerates the platform tokens
# the script itself branches on and requires each one to be either RUN by the
# workflow or exempted here BY NAME with a reason.
# better-rm 會依 `uname -s` 分支，而 Darwin/BSD 那條臂是「搬進垃圾桶時不穿過 symlink」的那
# 一條；每個 `stat -c ... || stat -f ...` 配對的 BSD 半邊也是同一類。workflow 原本只有一個
# job、一台 ubuntu runner，本機也沒有 pre-push hook，於是這些臂全部是「零自動驗證」出貨。
# 光加一台 runner 守不住這件事：下一條 BSD-only 的臂它看不見。所以這個測試列舉腳本自己分支
# 的平台代號，要求每一個要嘛被 workflow 跑到，要嘛在這裡逐一具名豁免並寫出理由。
PLATFORM_TOKENS=$(awk '
    /case "\$\(uname -s\)" in/ { in_case = 1; next }
    in_case && /^[[:space:]]*esac/ { in_case = 0; next }
    in_case && /^[[:space:]]*[A-Za-z][A-Za-z|]*\)/ {
        line = $0
        sub(/^[[:space:]]*/, "", line)
        sub(/\).*$/, "", line)
        n = split(line, arms, "|")
        for (i = 1; i <= n; i += 1) print arms[i]
    }
' "$SCRIPT_DIR/better-rm" | sort -u)

if [ -n "$PLATFORM_TOKENS" ]; then
    pass "the platform sweep found uname arms to check ($(printf '%s' "$PLATFORM_TOKENS" | tr '\n' ' '))"
else
    fail "the platform sweep found no uname arms; this whole check would pass vacuously"
fi

# The BSD half of a `stat` pair is a platform arm with no `uname` beside it, so it
# is counted separately -- a reviewer who deleted the Darwin case arm would
# otherwise leave this test green while those halves still only run on BSD.
# `stat` 配對的 BSD 半邊是「沒有 uname 陪著」的平台臂，所以另外計數。
STAT_PAIR_COUNT=$(grep -c "stat -c" "$SCRIPT_DIR/better-rm" || true)
if [ "$STAT_PAIR_COUNT" -ge 1 ]; then
    pass "the platform sweep found GNU/BSD stat pairs to cover ($STAT_PAIR_COUNT)"
else
    fail "the platform sweep found no stat pairs; the BSD-half coverage claim is vacuous"
fi

WORKFLOW_RUNNERS=$(awk '
    $0 == "  test:" { in_test = 1; next }
    in_test && /^  [[:alnum:]_-]+:/ { in_test = 0 }
    in_test && /(ubuntu|macos|windows)-[[:alnum:].-]+/ {
        line = $0
        match(line, /(ubuntu|macos|windows)-[[:alnum:].-]+/)
        print substr(line, RSTART, RLENGTH)
    }
' "$WORKFLOW" | sort -u)

# Which runner label answers for which `uname -s`. Written out rather than
# pattern-matched so a new platform token cannot be absorbed silently.
# 哪個 runner 標籤回答哪一種 `uname -s`，逐一寫出而不是用樣式吸收。
runner_covers_platform() {
    case "$1" in
        Linux) printf '%s\n' "$WORKFLOW_RUNNERS" | grep -q '^ubuntu-' ;;
        Darwin) printf '%s\n' "$WORKFLOW_RUNNERS" | grep -q '^macos' ;;
        # GitHub-hosted runners do not exist for these, so they can only ever be
        # exempted; the exemption is named so the claim is visible.
        # GitHub 沒有這些平台的 runner，所以只能豁免，而豁免要具名。
        *) return 1 ;;
    esac
}

PLATFORM_EXEMPT="FreeBSD NetBSD OpenBSD DragonFly"
UNCOVERED_PLATFORMS=""
for platform_token in $PLATFORM_TOKENS; do
    if runner_covers_platform "$platform_token"; then
        continue
    fi
    case " $PLATFORM_EXEMPT " in
        *" $platform_token "*) continue ;;
    esac
    UNCOVERED_PLATFORMS="$UNCOVERED_PLATFORMS $platform_token"
done

if [ -z "$UNCOVERED_PLATFORMS" ]; then
    pass "every uname arm better-rm branches on is either run by CI or exempted by name"
else
    fail "better-rm branches on platforms no CI runner exercises and no exemption names:$UNCOVERED_PLATFORMS"
fi

# The Darwin leg specifically, asserted on its own so a matrix that quietly loses
# the macOS entry is named rather than folded into the sweep above.
# Darwin 那一腳單獨斷言，這樣矩陣悄悄掉了 macOS 項目時會被指名。
if printf '%s\n' "$WORKFLOW_RUNNERS" | grep -q '^macos'; then
    pass "the test job runs the suites on a Darwin runner as well as ubuntu"
else
    fail "the test job has no macOS runner, so every Darwin/BSD arm of better-rm ships ungated"
fi

printf 'Passed: %s\nFailed: %s\n' "$PASSED" "$FAILED"
if [ "$FAILED" -ne 0 ]; then
    exit 1
fi
