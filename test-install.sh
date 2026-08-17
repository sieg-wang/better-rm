#!/bin/bash
# install.sh source-provenance tests / install.sh 來源信任邊界測試

set -u

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
INSTALLER="$SCRIPT_DIR/install.sh"
TRUSTED_REPO_URL="https://github.com/sieg-wang/better-rm.git"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/better-rm-install.XXXXXX")
FAKE_BIN="$TMP_ROOT/bin"
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

assert_log_line() {
    local name="$1"
    local expected="$2"
    local log="$3"
    if grep -Fqx -- "$expected" "$log"; then
        pass "$name"
    else
        fail "$name (missing: $expected)"
    fi
}

assert_no_log_prefix() {
    local name="$1"
    local prefix="$2"
    local log="$3"
    if grep -Fq -- "$prefix" "$log"; then
        fail "$name (unexpected: $prefix)"
    else
        pass "$name"
    fi
}

mkdir -p "$FAKE_BIN"

# Keep every Git interaction local and observable. The installer must decide
# whether an existing checkout is trusted from its configured upstream URL,
# not from a live fetch or from the directory name.
cat > "$FAKE_BIN/git" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$BETTER_RM_TEST_GIT_LOG"
case "$1" in
    status)
        exit 0
        ;;
    clone)
        destination="${@: -1}"
        mkdir -p "$destination"
        printf '#!/bin/bash\n' > "$destination/better-rm"
        exit 0
        ;;
    symbolic-ref)
        printf 'main\n'
        exit 0
        ;;
    config)
        case "${3:-}" in
            branch.main.remote) printf 'origin\n' ;;
            branch.main.merge) printf 'refs/heads/main\n' ;;
            *) exit 1 ;;
        esac
        exit 0
        ;;
    remote)
        if [ "${2:-}" = "get-url" ]; then
            printf '%s\n' "$BETTER_RM_TEST_GIT_REMOTE_URL"
            exit 0
        fi
        ;;
    pull)
        exit 0
        ;;
esac
exit 1
EOF
chmod +x "$FAKE_BIN/git"

run_installer() {
    local home="$1"
    local remote_url="$2"
    local log="$3"
    env PATH="$FAKE_BIN:$PATH" \
        HOME="$home" SHELL=/bin/fish \
        BETTER_RM_TEST_GIT_LOG="$log" \
        BETTER_RM_TEST_GIT_REMOTE_URL="$remote_url" \
        "$INSTALLER" >/dev/null 2>&1
}

printf 'install.sh tests\n'

if grep -n 'github\.com/doggy8088/better-rm' \
    "$SCRIPT_DIR/README.md" "$SCRIPT_DIR/install.sh" "$SCRIPT_DIR/install-hooks.sh" \
    >/dev/null; then
    fail "operator-facing install sources do not reference the old upstream"
else
    pass "operator-facing install sources do not reference the old upstream"
fi
if grep -Fq \
    'https://raw.githubusercontent.com/sieg-wang/better-rm/main/install-hooks.sh' \
    "$SCRIPT_DIR/README.md"; then
    pass "the documented standalone hook installer uses the Sieg-owned HTTPS source"
else
    fail "the documented standalone hook installer uses the Sieg-owned HTTPS source"
fi

FRESH_HOME="$TMP_ROOT/fresh-home"
FRESH_LOG="$TMP_ROOT/fresh.log"
mkdir -p "$FRESH_HOME"
if run_installer "$FRESH_HOME" "$TRUSTED_REPO_URL" "$FRESH_LOG"; then
    pass "a fresh install succeeds through the stubbed Git boundary"
else
    fail "a fresh install succeeds through the stubbed Git boundary"
fi
assert_log_line "a fresh install clones the Sieg-owned repository" \
    "clone --quiet $TRUSTED_REPO_URL $FRESH_HOME/.better-rm" "$FRESH_LOG"

TRUSTED_HOME="$TMP_ROOT/trusted-home"
TRUSTED_LOG="$TMP_ROOT/trusted.log"
mkdir -p "$TRUSTED_HOME/.better-rm"
printf '#!/bin/bash\n' > "$TRUSTED_HOME/.better-rm/better-rm"
if run_installer "$TRUSTED_HOME" "$TRUSTED_REPO_URL" "$TRUSTED_LOG"; then
    pass "an existing checkout with a trusted upstream updates"
else
    fail "an existing checkout with a trusted upstream updates"
fi
assert_log_line "a trusted update is fast-forward only" \
    "pull --ff-only --quiet" "$TRUSTED_LOG"

UNTRUSTED_HOME="$TMP_ROOT/untrusted-home"
UNTRUSTED_LOG="$TMP_ROOT/untrusted.log"
mkdir -p "$UNTRUSTED_HOME/.better-rm"
printf '#!/bin/bash\n' > "$UNTRUSTED_HOME/.better-rm/better-rm"
UNTRUSTED_STATUS=0
run_installer "$UNTRUSTED_HOME" \
    "https://github.com/doggy8088/better-rm.git" "$UNTRUSTED_LOG" || UNTRUSTED_STATUS=$?
if [ "$UNTRUSTED_STATUS" -ne 0 ]; then
    pass "an existing checkout with an untrusted upstream is refused"
else
    fail "an existing checkout with an untrusted upstream is refused"
fi
assert_no_log_prefix "an untrusted checkout is never pulled" \
    "pull " "$UNTRUSTED_LOG"

printf 'Passed: %s\nFailed: %s\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
