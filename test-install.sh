#!/bin/bash
# install.sh source-provenance tests / install.sh 來源信任邊界測試

set -u

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
INSTALLER="$SCRIPT_DIR/install.sh"
TRUSTED_REPO_URL="https://github.com/sieg-wang/better-rm.git"
REAL_GIT=$(command -v git) || exit 1
# 真實 Git fixtures 不繼承現場 repository/config context。
# Keep real Git fixtures independent of inherited repository/config context.
git_local_vars=$("$REAL_GIT" rev-parse --local-env-vars) || exit 1
for git_local_var in $git_local_vars; do
    unset "$git_local_var"
done
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/better-rm-install.XXXXXX") || exit 1
# Git discovery in the real-Git fixtures stops here (BR1-1): a TMPDIR inside an
# enclosing work tree must not turn "not a repository" into "parent repository".
# The physical path, because macOS /var is a symlink to /private/var and Git
# compares against the directory it is really in. Fixtures that ARE meant to sit
# inside a repository (parent-home) live below this, so they still do.
# real-Git fixture 的 Git 探索停在這裡（BR1-1）：TMPDIR 在某個工作樹裡時，「不是 repository」不能
# 變成「上層 repository」。用實體路徑，因為 macOS 的 /var 是指向 /private/var 的 symlink。刻意放在
# repository 裡的 fixture（parent-home）都在這底下，照樣測得到。
TMP_ROOT_PHYSICAL=$(cd "$TMP_ROOT" && pwd -P) || exit 1
TMP_PATH_ROOT=''

cleanup() {
    rm -rf -- "$TMP_ROOT"
    [ -z "$TMP_PATH_ROOT" ] || rm -rf -- "$TMP_PATH_ROOT"
}
trap cleanup EXIT
TMP_PATH_ROOT=$(mktemp -d /tmp/better-rm-install-path.XXXXXX) || exit 1
FAKE_BIN="$TMP_ROOT/bin"
REAL_BIN="$TMP_ROOT/real-bin"
PASSED=0
FAILED=0

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

assert_file_contains() {
    local name="$1"
    local expected="$2"
    local file="$3"
    if grep -Fq -- "$expected" "$file"; then
        pass "$name"
    else
        fail "$name (missing: $expected)"
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
    rev-parse)
        [ "${2:-}" = --show-toplevel ] || exit 1
        pwd -P
        exit 0
        ;;
    clone)
        destination="${@: -1}"
        mkdir -p "$destination"
        printf '#!/bin/bash\n' > "$destination/better-rm"
        exit 0
        ;;
    symbolic-ref)
        if [ "${BETTER_RM_TEST_GIT_SCENARIO:-trusted}" = "detached" ]; then
            exit 1
        fi
        printf 'main\n'
        exit 0
        ;;
    config)
        case "${3:-}" in
            branch.main.remote)
                case "${BETTER_RM_TEST_GIT_SCENARIO:-trusted}" in
                    missing-upstream) exit 1 ;;
                    empty-remote) printf '\n' ;;
                    remote-dot) printf '.\n' ;;
                    *) printf 'origin\n' ;;
                esac
                ;;
            branch.main.merge)
                [ "${BETTER_RM_TEST_GIT_SCENARIO:-trusted}" != "missing-upstream" ] || exit 1
                if [ "${BETTER_RM_TEST_GIT_SCENARIO:-trusted}" = "empty-merge" ]; then
                    printf '\n'
                else
                    printf 'refs/heads/main\n'
                fi
                ;;
            # These are unreachable in production. They make the detached-HEAD
            # fixture continue all the way to pull if that specific refusal is
            # deleted, instead of being accidentally saved by a later guard.
            branch..remote) printf 'origin\n' ;;
            branch..merge) printf 'refs/heads/main\n' ;;
            *) exit 1 ;;
        esac
        exit 0
        ;;
    remote)
        if [ "${2:-}" = "get-url" ]; then
            [ "${BETTER_RM_TEST_GIT_SCENARIO:-trusted}" != "get-url-fails" ] || exit 1
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
    local scenario="${4:-trusted}"
    local output_file="${5:-/dev/null}"
    env PATH="$FAKE_BIN:$PATH" \
        HOME="$home" SHELL=/bin/fish \
        BETTER_RM_TEST_GIT_LOG="$log" \
        BETTER_RM_TEST_GIT_REMOTE_URL="$remote_url" \
        BETTER_RM_TEST_GIT_SCENARIO="$scenario" \
        "$INSTALLER" >"$output_file" 2>&1
}

make_existing_install() {
    local home="$1"
    mkdir -p "$home/.better-rm"
    printf '#!/bin/bash\n' > "$home/.better-rm/better-rm"
}

printf 'install.sh tests\n'

OLD_OPERATOR_SOURCE_RE='(github\.com(:[0-9]+)?[/:]|githubusercontent\.com(:[0-9]+)?/)doggy8088/better-rm'
# Match actual GitHub source URLs independently of HTTPS/SSH/raw host spelling,
# while allowing ordinary prose to acknowledge the original upstream.
if grep -En "$OLD_OPERATOR_SOURCE_RE" \
    "$SCRIPT_DIR/README.md" "$SCRIPT_DIR/install.sh" "$SCRIPT_DIR/install-hooks.sh" \
    >/dev/null; then
    fail "operator-facing install sources do not reference the old upstream"
else
    pass "operator-facing install sources do not reference the old upstream"
fi
printf 'Based on work by doggy8088/better-rm.\n' > "$TMP_ROOT/upstream-credit.txt"
if grep -Eq "$OLD_OPERATOR_SOURCE_RE" "$TMP_ROOT/upstream-credit.txt"; then
    fail "plain-text upstream credit is not misclassified as an install source"
else
    pass "plain-text upstream credit is not misclassified as an install source"
fi
printf 'curl https://raw.githubusercontent.com/doggy8088/better-rm/main/install.sh\n' \
    > "$TMP_ROOT/old-install-source.txt"
if grep -Eq "$OLD_OPERATOR_SOURCE_RE" "$TMP_ROOT/old-install-source.txt"; then
    pass "the narrowed gate still recognizes an old operator-facing source"
else
    fail "the narrowed gate still recognizes an old operator-facing source"
fi
printf 'curl https://raw.githubusercontent.com:443/doggy8088/better-rm/main/install.sh\n' \
    > "$TMP_ROOT/old-install-source-with-port.txt"
if grep -Eq "$OLD_OPERATOR_SOURCE_RE" "$TMP_ROOT/old-install-source-with-port.txt"; then
    pass "the narrowed gate recognizes an old source with an explicit port"
else
    fail "the narrowed gate recognizes an old source with an explicit port"
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
make_existing_install "$TRUSTED_HOME"
if run_installer "$TRUSTED_HOME" "$TRUSTED_REPO_URL" "$TRUSTED_LOG"; then
    pass "an existing checkout with a trusted upstream updates"
else
    fail "an existing checkout with a trusted upstream updates"
fi
assert_log_line "a trusted update is fast-forward only" \
    "pull --ff-only --quiet" "$TRUSTED_LOG"

UNTRUSTED_HOME="$TMP_ROOT/untrusted-home"
UNTRUSTED_LOG="$TMP_ROOT/untrusted.log"
make_existing_install "$UNTRUSTED_HOME"
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

for scenario in \
    detached missing-upstream empty-remote empty-merge get-url-fails remote-dot; do
    BRANCH_HOME="$TMP_ROOT/$scenario-home"
    BRANCH_LOG="$TMP_ROOT/$scenario.log"
    BRANCH_OUTPUT="$TMP_ROOT/$scenario.output"
    make_existing_install "$BRANCH_HOME"
    BRANCH_STATUS=0
    run_installer "$BRANCH_HOME" "$TRUSTED_REPO_URL" "$BRANCH_LOG" \
        "$scenario" "$BRANCH_OUTPUT" || BRANCH_STATUS=$?
    if [ "$BRANCH_STATUS" -ne 0 ]; then
        pass "an existing checkout fails closed for $scenario"
    else
        fail "an existing checkout fails closed for $scenario"
    fi
    assert_no_log_prefix "$scenario never reaches pull" "pull " "$BRANCH_LOG"
    case "$scenario" in
        detached)
            EXPECTED_ERROR="existing installation is on a detached HEAD"
            ;;
        get-url-fails)
            EXPECTED_ERROR="cannot resolve upstream remote 'origin'"
            ;;
        *)
            EXPECTED_ERROR="current branch has no verifiable remote upstream"
            ;;
    esac
    assert_file_contains "$scenario reports its exact trust failure" \
        "$EXPECTED_ERROR" "$BRANCH_OUTPUT"
done

# 真正 Git discovery/config；只有網路邊界由 shim 攔截。
# Use real Git discovery/config; intercept every network operation.
mkdir -p "$REAL_BIN"
cat > "$REAL_BIN/git" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$BETTER_RM_TEST_GIT_LOG"
case "$1" in
    pull) exit 0 ;;
    clone|fetch|push) exit 97 ;;
    rev-parse)
        if [ "${2:-}" = --show-toplevel ]; then
            case "${BETTER_RM_TEST_GIT_SCENARIO:-trusted}" in
                root-fails) exit 1 ;;
                root-missing) printf '%s/missing-root\n' "$HOME"; exit 0 ;;
            esac
        fi
        ;;
    status|symbolic-ref|config|remote) ;;
    *) exit 97 ;;
esac
exec "$BETTER_RM_TEST_REAL_GIT" "$@"
EOF
cat > "$REAL_BIN/chmod" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$BETTER_RM_TEST_WRITE_LOG"
exec /bin/chmod "$@"
EOF
chmod +x "$REAL_BIN/git" "$REAL_BIN/chmod"

make_real_repo() {
    local repo="$1"
    mkdir -p "$repo"
    "$REAL_GIT" init --quiet --template= "$repo" || return 1
    "$REAL_GIT" -C "$repo" symbolic-ref HEAD refs/heads/main || return 1
    printf '#!/bin/bash\n# fixture payload\n' > "$repo/better-rm"
    "$REAL_GIT" -C "$repo" add better-rm || return 1
    "$REAL_GIT" -C "$repo" -c user.name=Fixture -c user.email=fixture@example.invalid \
        -c commit.gpgsign=false commit --quiet -m fixture || return 1
    "$REAL_GIT" -C "$repo" remote add origin "$TRUSTED_REPO_URL" || return 1
    "$REAL_GIT" -C "$repo" config branch.main.remote origin || return 1
    "$REAL_GIT" -C "$repo" config branch.main.merge refs/heads/main || return 1
}

run_real_installer() {
    local home="$1" scenario="${2:-trusted}"
    env PATH="$REAL_BIN:$PATH" HOME="$home" SHELL=/bin/bash \
        GIT_CEILING_DIRECTORIES="$TMP_ROOT_PHYSICAL" \
        BETTER_RM_TEST_GIT_LOG="$home/git.log" \
        BETTER_RM_TEST_WRITE_LOG="$home/write.log" \
        BETTER_RM_TEST_REAL_GIT="$REAL_GIT" \
        BETTER_RM_TEST_GIT_SCENARIO="$scenario" \
        "$INSTALLER" >"$home/installer.output" 2>&1
}

assert_real_refusal() {
    local home="$1" label="$2" expected="$3" scenario="${4:-trusted}" status=0 mode
    cp "$home/.better-rm/better-rm" "$home/payload.before"
    mode=$(stat -c '%a' "$home/.better-rm/better-rm" 2>/dev/null || \
        stat -f '%Lp' "$home/.better-rm/better-rm")
    cp "$home/.bashrc" "$home/shell.before"
    : > "$home/write.log"
    : > "$home/git.log"
    run_real_installer "$home" "$scenario" || status=$?
    if [ "$status" -ne 0 ]; then pass "$label refuses"; else fail "$label refuses"; fi
    assert_file_contains "$label names the refusal" "$expected" "$home/installer.output"
    assert_no_log_prefix "$label never pulls" 'pull ' "$home/git.log"
    if [ ! -s "$home/write.log" ] && \
       [ "$mode" = "$(stat -c '%a' "$home/.better-rm/better-rm" 2>/dev/null || \
           stat -f '%Lp' "$home/.better-rm/better-rm")" ] && \
       cmp -s "$home/payload.before" "$home/.better-rm/better-rm" && \
       cmp -s "$home/shell.before" "$home/.bashrc"; then
        pass "$label preserves payload/mode/shell config without chmod"
    else
        fail "$label preserves payload/mode/shell config without chmod"
    fi
}

PARENT_HOME="$TMP_ROOT/parent-home"
make_real_repo "$PARENT_HOME" || exit 1
make_existing_install "$PARENT_HOME"
printf '# parent shell fixture\n' > "$PARENT_HOME/.bashrc"
chmod 640 "$PARENT_HOME/.better-rm/better-rm"
"$REAL_GIT" -C "$PARENT_HOME" add .better-rm .bashrc
"$REAL_GIT" -C "$PARENT_HOME" -c user.name=Fixture -c user.email=fixture@example.invalid \
    -c commit.gpgsign=false commit --quiet -m child
PARENT_HEAD=$("$REAL_GIT" -C "$PARENT_HOME" rev-parse HEAD)
cp "$PARENT_HOME/.git/config" "$TMP_ROOT/parent.config.before"
cp "$PARENT_HOME/.git/index" "$TMP_ROOT/parent.index.before"
# 未追蹤的 harness logs 排除；tracked worktree/index 必須原樣。
# Harness logs are untracked; preserve every tracked worktree/index byte.
assert_real_refusal "$PARENT_HOME" 'a real parent-repo child' \
    'existing installation is a child of another Git repository'
if [ "$PARENT_HEAD" = "$("$REAL_GIT" -C "$PARENT_HOME" rev-parse HEAD)" ] && \
   cmp -s "$TMP_ROOT/parent.config.before" "$PARENT_HOME/.git/config" && \
   cmp -s "$TMP_ROOT/parent.index.before" "$PARENT_HOME/.git/index" && \
   "$REAL_GIT" -C "$PARENT_HOME" diff --quiet HEAD --; then
    pass 'parent HEAD/config/index/tracked worktree remain unchanged'
else
    fail 'parent HEAD/config/index/tracked worktree remain unchanged'
fi
assert_no_log_prefix 'root mismatch refuses before branch/upstream trust checks' \
    'symbolic-ref ' "$PARENT_HOME/git.log"
assert_no_log_prefix 'root mismatch refuses before even scanning parent status' \
    'status' "$PARENT_HOME/git.log"

OWN_HOME="$TMP_ROOT/own-home"
SPACE_HOME="$TMP_ROOT/home with spaces"
LINKED_HOME="$TMP_ROOT/linked-home"
PHYSICAL_HOME="$TMP_PATH_ROOT/physical-home"
for real_home in "$OWN_HOME" "$SPACE_HOME" "$PHYSICAL_HOME"; do
    make_real_repo "$real_home/.better-rm" || exit 1
done
make_real_repo "$TMP_ROOT/worktree-source" || exit 1
"$REAL_GIT" -C "$TMP_ROOT/worktree-source" worktree add --quiet -b linked \
    "$LINKED_HOME/.better-rm" || exit 1
"$REAL_GIT" -C "$LINKED_HOME/.better-rm" config branch.linked.remote origin
"$REAL_GIT" -C "$LINKED_HOME/.better-rm" config branch.linked.merge refs/heads/main
[ -f "$LINKED_HOME/.better-rm/.git" ] || exit 1
ln -s "$SPACE_HOME" "$TMP_ROOT/symlink-home"
for real_home in "$OWN_HOME" "$LINKED_HOME" "$TMP_ROOT/symlink-home" "$PHYSICAL_HOME"; do
    printf '# shell fixture\n' > "$real_home/.bashrc"
    : > "$real_home/git.log"
    if run_real_installer "$real_home"; then
        pass "own-root update accepts ${real_home##*/}"
    else
        fail "own-root update accepts ${real_home##*/}"
    fi
    assert_log_line 'own-root update retains fast-forward-only intercepted pull' \
        'pull --ff-only --quiet' "$real_home/git.log"
    assert_log_line 'own-root update still resolves the trusted real remote' \
        'remote get-url origin' "$real_home/git.log"
    assert_file_contains 'own-root install retains alias configuration' \
        "alias rm='$real_home/.better-rm/better-rm'" "$real_home/.bashrc"
done

for scenario in root-fails root-missing not-a-repo bare; do
    FAILURE_HOME="$TMP_ROOT/real-$scenario"
    if [ "$scenario" = bare ]; then
        mkdir -p "$FAILURE_HOME"
        "$REAL_GIT" init --bare --quiet --template= "$FAILURE_HOME/.better-rm" || exit 1
        printf '#!/bin/bash\n' > "$FAILURE_HOME/.better-rm/better-rm"
    elif [ "$scenario" = not-a-repo ]; then
        make_existing_install "$FAILURE_HOME"
    else
        make_real_repo "$FAILURE_HOME/.better-rm" || exit 1
    fi
    printf '# shell fixture\n' > "$FAILURE_HOME/.bashrc"
    EXPECTED_ERROR="cannot verify the existing installation's Git root"
    assert_real_refusal "$FAILURE_HOME" "$scenario" "$EXPECTED_ERROR" "$scenario"
done

# BR1-1 (2026-10-17): these fixtures must not depend on where TMPDIR is. With
# TMPDIR inside any Git work tree, real `git rev-parse --show-toplevel` in the
# not-a-repo fixture walked up into that enclosing repository, the installer
# correctly refused it as a parent repository, and the row expecting "cannot
# verify ..." went red (measured 67/1 in the review; 68/0 elsewhere): a loud
# false red that says nothing about install.sh. So this file runs itself once
# more with TMPDIR inside a fresh repository and requires a clean pass. The
# nested run sets BETTER_RM_TEST_INSTALL_NESTED and does not recurse.
# BR1-1：這些 fixture 不能取決於 TMPDIR 在哪裡。TMPDIR 在任何 Git 工作樹裡時，not-a-repo fixture
# 的 `git rev-parse --show-toplevel` 會往上走進那個 repository，安裝程式正確地以「上層
# repository」拒絕，期待「cannot verify ...」的那一列就紅了——一個跟 install.sh 無關的假紅。所以這
# 個檔案在一個全新 repository 裡的 TMPDIR 下再跑自己一次，要求全部通過；內層執行不會再遞迴。
if [ -z "${BETTER_RM_TEST_INSTALL_NESTED:-}" ]; then
    ENCLOSING_REPO="$TMP_ROOT/enclosing-repo"
    "$REAL_GIT" init --quiet --template= "$ENCLOSING_REPO" || exit 1
    mkdir -p "$ENCLOSING_REPO/tmp"
    NESTED_STATUS=0
    BETTER_RM_TEST_INSTALL_NESTED=1 TMPDIR="$ENCLOSING_REPO/tmp" \
        "$SCRIPT_DIR/test-install.sh" > "$TMP_ROOT/nested-in-repo.out" 2>&1 || NESTED_STATUS=$?
    if [ "$NESTED_STATUS" -eq 0 ] && grep -q '^Failed: 0$' "$TMP_ROOT/nested-in-repo.out"; then
        pass 'the suite passes with TMPDIR inside an enclosing Git repository'
    else
        fail "the suite passes with TMPDIR inside an enclosing Git repository (status $NESTED_STATUS: $(grep '^✗' "$TMP_ROOT/nested-in-repo.out" | head -n 3 | tr '\n' ';'))"
    fi
fi

printf 'Passed: %s\nFailed: %s\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
