#!/bin/bash
# bump-and-release.sh push / gh-release remote-targeting tests
# bump-and-release.sh 推播與 gh release 目標對象測試
#
# bump-and-release.sh runs under no gate at all (see the parse-sweep comment in
# test-run-test-suites.sh: it is parsed for syntax errors only, never executed)
# and had zero behavioural coverage. Its one `git push` and four `gh` calls
# resolved to whichever remote/repo `git`/`gh` picked ambiently rather than the
# sieg-wang fork this project is meant to publish to -- `gh repo view` on this
# checkout resolves to doggy8088/better-rm even though `git push` (no explicit
# remote) already tracks mine/main. This drives the script's real --auto
# release path against a PATH-stubbed git/gh that records every argv, so the
# remote is asserted from the actual command line the script executed, not
# from reading the source.

set -u

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
SCRIPT="$SCRIPT_DIR/.agents/skills/bump-and-release/scripts/bump-and-release.sh"
EXPECTED_GH_REPO="sieg-wang/better-rm"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/better-rm-release.XXXXXX")
FAKE_BIN="$TMP_ROOT/bin"
PROJECT="$TMP_ROOT/project"
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

assert_status() {
    local name="$1"
    local expected="$2"
    local actual="$3"
    if [ "$expected" = "$actual" ]; then
        pass "$name"
    else
        fail "$name (expected status $expected, got $actual)"
    fi
}

assert_log_contains() {
    local name="$1"
    local expected="$2"
    local log="$3"
    if grep -Fq -- "$expected" "$log" 2>/dev/null; then
        pass "$name"
    else
        fail "$name (missing from $log: $expected)"
    fi
}

assert_log_lacks() {
    local name="$1"
    local unexpected="$2"
    local log="$3"
    if grep -Fq -- "$unexpected" "$log" 2>/dev/null; then
        fail "$name (unexpectedly present in $log: $unexpected)"
    else
        pass "$name"
    fi
}

mkdir -p "$FAKE_BIN" "$PROJECT"

# A fixture project the script can "release": a version string to read, a
# CHANGELOG the release-notes step reads unconditionally, and no-op stand-ins
# for the three test scripts run_release_checks shells out to (this repo's
# own test-better-rm.sh / test-hooks.js / test-install-hooks.sh are the real
# thing and would just slow this fixture down without changing what is under
# test here).
cat > "$PROJECT/better-rm" <<'EOF'
#!/bin/bash
# better-rm 0.0.1
echo hi
EOF

cat > "$PROJECT/CHANGELOG.md" <<'EOF'
## [Unreleased]
- fixture entry

## [0.0.1] - 2020-01-01
- initial
EOF

cat > "$PROJECT/test-better-rm.sh" <<'EOF'
#!/bin/bash
exit 0
EOF

cat > "$PROJECT/test-install-hooks.sh" <<'EOF'
#!/bin/bash
exit 0
EOF

printf '// inert fixture, node exits 0 on any file\n' > "$PROJECT/test-hooks.js"

chmod +x "$PROJECT/test-better-rm.sh" "$PROJECT/test-install-hooks.sh"

# Fake git: every real subcommand run_release()/run_release_checks() reaches
# on a clean, tag-free, auto-release run of the fixture above. Unhandled
# subcommands fall through to `exit 1` so a code path this fixture did not
# anticipate fails loudly instead of silently passing.
cat > "$FAKE_BIN/git" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$BETTER_RM_TEST_GIT_LOG"
# Drop the leading `-C <path>` the script always passes.
if [ "$1" = "-C" ]; then
    shift 2
fi
case "$1" in
    rev-parse)
        case "$2" in
            --is-inside-work-tree) printf 'true\n' ;;
            --abbrev-ref) printf 'main\n' ;;
            HEAD) printf 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef\n' ;;
            *) exit 1 ;;
        esac
        exit 0
        ;;
    show-ref)
        # No release tag exists yet.
        exit 1
        ;;
    tag)
        case "$2" in
            --sort=-creatordate) exit 0 ;;   # no tags -> empty stdout
            -a) exit 0 ;;                     # tag creation
            *) exit 1 ;;
        esac
        ;;
    status)
        exit 0   # empty stdout either way -> clean tree
        ;;
    push)
        exit 0
        ;;
    log|rev-list|diff)
        exit 0   # empty stdout; callers all tolerate that
        ;;
    *)
        exit 1
        ;;
esac
EOF
chmod +x "$FAKE_BIN/git"

# Fake gh: the four call sites run_release() reaches when PUSH=1 and the
# waiting loops must resolve on their first poll. Every invocation is logged
# so a call missing --repo, or carrying the wrong one, is visible in the log
# even though this fixture only asserts a subset of behaviour on it.
cat > "$FAKE_BIN/gh" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$BETTER_RM_TEST_GH_LOG"
case "$1 $2" in
    "run list")
        printf 'completed\tsuccess\thttps://example.test/actions/runs/1\n'
        exit 0
        ;;
    "release view")
        case "$*" in
            *"--json id"*) exit 0 ;;
            *"--json url"*)
                printf 'https://github.com/sieg-wang/better-rm/releases/tag/v0.0.1\n'
                exit 0
                ;;
            *) exit 1 ;;
        esac
        ;;
    "release edit")
        exit 0
        ;;
    *)
        exit 1
        ;;
esac
EOF
chmod +x "$FAKE_BIN/gh"

# ---------------------------------------------------------------------------
# Auto-release path: the one place PUSH and every gh call actually execute.
GIT_LOG="$TMP_ROOT/git-auto.log"
GH_LOG="$TMP_ROOT/gh-auto.log"
: > "$GIT_LOG"
: > "$GH_LOG"

AUTO_STATUS=0
PATH="$FAKE_BIN:$PATH" BETTER_RM_TEST_GIT_LOG="$GIT_LOG" BETTER_RM_TEST_GH_LOG="$GH_LOG" \
    "$SCRIPT" release --repo "$PROJECT" --auto >"$TMP_ROOT/auto.out" 2>"$TMP_ROOT/auto.err" \
    || AUTO_STATUS=$?

if [ "$AUTO_STATUS" -ne 0 ]; then
    cat "$TMP_ROOT/auto.out" "$TMP_ROOT/auto.err" >&2
fi
assert_status "auto-release run completes" "0" "$AUTO_STATUS"

PUSH_LINE="$(grep -F ' push ' "$GIT_LOG" | head -n 1)"
if printf '%s' "$PUSH_LINE" | grep -Fq -- ' push mine HEAD'; then
    pass "git push targets the mine remote"
else
    fail "git push targets the mine remote (logged: $PUSH_LINE)"
fi
if printf '%s' "$PUSH_LINE" | grep -Fq -- ' push origin HEAD'; then
    fail "git push never targets origin (logged: $PUSH_LINE)"
else
    pass "git push never targets origin"
fi

GH_CALL_COUNT="$(wc -l < "$GH_LOG" | tr -d ' ')"
assert_status "all four gh calls were made" "4" "$GH_CALL_COUNT"

GH_REPO_COUNT="$(grep -Fc -- "--repo $EXPECTED_GH_REPO" "$GH_LOG")"
assert_status "every gh call carries --repo $EXPECTED_GH_REPO" "$GH_CALL_COUNT" "$GH_REPO_COUNT"

assert_log_lacks "no gh call resolves to the doggy8088 upstream" "doggy8088" "$GH_LOG"

# ---------------------------------------------------------------------------
# Suggestion-only path (no --auto): PUSH stays at its default of 1, so the
# script prints the manual push command instead of running it. Same source
# line, no push/gh execution needed to observe it.
SUGGEST_STATUS=0
PATH="$FAKE_BIN:$PATH" BETTER_RM_TEST_GIT_LOG="$TMP_ROOT/git-suggest.log" \
    BETTER_RM_TEST_GH_LOG="$TMP_ROOT/gh-suggest.log" \
    "$SCRIPT" release --repo "$PROJECT" >"$TMP_ROOT/suggest.out" 2>"$TMP_ROOT/suggest.err" \
    || SUGGEST_STATUS=$?
assert_status "suggestion-only run completes" "0" "$SUGGEST_STATUS"
assert_log_contains "suggested push command names the mine remote" \
    "push mine HEAD" "$TMP_ROOT/suggest.out"
assert_log_lacks "suggested push command does not name origin" \
    "push origin HEAD" "$TMP_ROOT/suggest.out"

printf 'Passed: %s\nFailed: %s\n' "$PASSED" "$FAILED"
if [ "$FAILED" -ne 0 ]; then
    exit 1
fi
