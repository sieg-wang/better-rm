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
            *'^{commit}') printf 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef\n' ;;
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
    ls-remote)
        exit 2   # --exit-code: the remote has no such tag
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

# The remote a logged `git push` names: the first word after `push` that is
# not an option (the push now starts with --atomic).
# 記錄下來的 `git push` 指向哪個遠端：`push` 之後第一個不是選項的字（推播現在以 --atomic 開頭）。
push_remote_of() {
    local seen_push=0
    local word
    for word in $1; do
        if [ "$seen_push" -eq 0 ]; then
            [ "$word" = "push" ] && seen_push=1
            continue
        fi
        case "$word" in
            -*) continue ;;
        esac
        printf '%s\n' "$word"
        return 0
    done
}

PUSH_LINE="$(grep -F ' push ' "$GIT_LOG" | head -n 1)"
if [ "$(push_remote_of "$PUSH_LINE")" = "mine" ]; then
    pass "git push targets the mine remote"
else
    fail "git push targets the mine remote (logged: $PUSH_LINE)"
fi
if [ "$(push_remote_of "$PUSH_LINE")" = "origin" ]; then
    fail "git push never targets origin (logged: $PUSH_LINE)"
else
    pass "git push never targets origin"
fi
if printf '%s' "$PUSH_LINE" | grep -Fq -- ' refs/tags/v0.0.1'; then
    pass "git push names the release tag explicitly"
else
    fail "git push names the release tag explicitly (logged: $PUSH_LINE)"
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
    "push --atomic mine HEAD refs/tags/v0.0.1" "$TMP_ROOT/suggest.out"
assert_log_lacks "suggested push command does not name origin" \
    "push origin HEAD" "$TMP_ROOT/suggest.out"

# ---------------------------------------------------------------------------
# REAL-GIT FIXTURE. The fake git above answers one fixed HEAD and a clean
# status, so it cannot see which commit the release commits, tags and waits
# for. These rows run the real git against a local bare repository standing in
# for the `mine` remote (nothing leaves TMP_ROOT); gh is still a stub, and it
# answers `run list` from the commit named in the script's own --jq filter.
# 真 git 的 fixture：上面的假 git 只回一個固定的 HEAD 與乾淨的狀態，看不到 release
# 提交、打標籤、等 CI 的是哪一個 commit。這幾列用真的 git，`mine` 換成 TMP_ROOT 裡的
# 本機 bare repository；gh 仍是替身，依腳本自己 --jq 裡寫的 commit 回答 run list。
RG_ROOT="$TMP_ROOT/real-git"
RG_BIN="$RG_ROOT/bin"
mkdir -p "$RG_BIN"

rg_git() {
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
        GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid \
        GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid \
        git "$@"
}

cat > "$RG_BIN/gh" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$BETTER_RM_TEST_GH_LOG"
case "$1 $2" in
    "run list")
        want=$(printf '%s' "$*" | sed -n 's/.*headSha == "\([0-9a-f]*\)".*/\1/p')
        tag_commit=$(git -C "$BETTER_RM_TEST_PROJECT" rev-parse -q --verify \
            "refs/tags/$BETTER_RM_TEST_TAG^{commit}" 2>/dev/null)
        if [ -n "$want" ] && [ "$want" = "$tag_commit" ]; then
            printf 'completed\t%s\thttps://example.test/runs/tag-commit\n' "$BETTER_RM_TEST_TAG_CI"
        elif [ -n "$want" ] && [ "$want" = "$BETTER_RM_TEST_PREVIOUS" ]; then
            printf 'completed\tsuccess\thttps://example.test/runs/previous-commit\n'
        elif [ -n "$want" ]; then
            # Any other id (an annotated tag's own object, say) gets a failed run,
            # so a wrong id ends the release at once instead of polling for 30 min.
            # 其他 id（例如 annotated tag 自己的物件）一律回失敗的執行，錯的 id 會立刻結束，
            # 而不是輪詢 30 分鐘。
            printf 'completed\tfailure\thttps://example.test/runs/unknown-commit\n'
        fi
        exit 0
        ;;
    "release view")
        case "$*" in
            *"--json id"*) exit 0 ;;
            *"--json url"*) printf 'https://example.test/releases/%s\n' "$BETTER_RM_TEST_TAG"; exit 0 ;;
            *) exit 1 ;;
        esac
        ;;
    "release edit")
        while [ $# -gt 0 ]; do
            if [ "$1" = "--notes-file" ]; then cp "$2" "$BETTER_RM_TEST_NOTES"; fi
            shift
        done
        exit 0
        ;;
    *)
        exit 1
        ;;
esac
EOF
chmod +x "$RG_BIN/gh"

# make_release_fixture NAME: a repository at version 1.0.0 (tag v1.0.0) plus a
# later commit, pushed to a bare `mine`. Prints the project path.
make_release_fixture() {
    local dir="$RG_ROOT/$1"
    local project="$dir/project"
    mkdir -p "$project/hooks"
    rg_git init -q --bare "$dir/mine.git"
    rg_git init -q -b main "$project"
    printf '#!/bin/bash\nshow_version() {\n  echo "better-rm 1.0.0"\n}\n' > "$project/better-rm"
    printf '#!/bin/bash\n# expects better-rm 1.0.0\nexit 0\n' > "$project/test-better-rm.sh"
    printf '# better-rm 1.0.0\n' > "$project/install.sh"
    printf 'VERSION="1.0.0"\n' > "$project/install-hooks.sh"
    printf 'better-rm 1.0.0\n' > "$project/README.md"
    printf '## [Unreleased]\n\n## [1.0.0] - 2020-01-01\n- initial\n' > "$project/CHANGELOG.md"
    printf '// inert fixture\n' > "$project/test-hooks.js"
    printf '#!/bin/bash\nexit 0\n' > "$project/test-install-hooks.sh"
    printf '// a tracked file outside the release list\n' > "$project/hooks/x.js"
    chmod +x "$project/better-rm" "$project/test-better-rm.sh" "$project/test-install-hooks.sh"
    rg_git -C "$project" add -A
    rg_git -C "$project" commit -q -m initial
    rg_git -C "$project" tag -a v1.0.0 -m v1.0.0
    printf '// later work\n' >> "$project/hooks/x.js"
    rg_git -C "$project" commit -q -am work
    rg_git -C "$project" remote add mine "$dir/mine.git"
    rg_git -C "$project" push -q mine main refs/tags/v1.0.0
    printf '%s\n' "$project"
}

# run_release_fixture PROJECT TAG_CI LABEL [args...]: the release from the
# project root, stubbed gh first on PATH, real git. Sets RG_STATUS.
run_release_fixture() {
    local project="$1"
    local tag_ci="$2"
    local label="$3"
    shift 3
    RG_STATUS=0
    ( cd "$project" && PATH="$RG_BIN:$PATH" \
        GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
        GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid \
        GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid \
        BETTER_RM_TEST_GH_LOG="$RG_ROOT/$label.gh.log" \
        BETTER_RM_TEST_PROJECT="$project" BETTER_RM_TEST_TAG=v1.0.1 \
        BETTER_RM_TEST_TAG_CI="$tag_ci" BETTER_RM_TEST_PREVIOUS="$RG_PREVIOUS" \
        BETTER_RM_TEST_NOTES="$RG_ROOT/$label.notes" \
        "$SCRIPT" "$@" ) > "$RG_ROOT/$label.out" 2>&1 < /dev/null || RG_STATUS=$?
}

# The CI wait and the published notes must be about the commit the tag names.
# The release commits the bump AFTER reading HEAD, so a HEAD captured before
# that commit is the previous commit: its old CI run was taken for the
# release's and the notes cited it. Two cases, so that both the verdict and
# the notes are tied to the tag: the tag's CI succeeds, then it fails.
# CI 等待與發佈說明必須針對「標籤指向的 commit」。release 在讀 HEAD 之後才提交版本
# 變更，所以提交前讀到的 HEAD 是上一個 commit：它舊的 CI 結果被當成這次的，說明也引用
# 它。兩個情境，讓判定與說明都綁在標籤上：標籤的 CI 成功、以及失敗。
RG_PROJECT=$(make_release_fixture ci-success)
RG_PREVIOUS=$(rg_git -C "$RG_PROJECT" rev-parse HEAD)
( cd "$RG_PROJECT" && "$SCRIPT" bump patch ) > "$RG_ROOT/ci-success.bump.out" 2>&1
run_release_fixture "$RG_PROJECT" success ci-success
RG_TAG_COMMIT=$(rg_git -C "$RG_PROJECT" rev-parse -q --verify 'refs/tags/v1.0.1^{commit}')
assert_status "real-git release completes when the tag's CI succeeds" "0" "$RG_STATUS"
if [ -n "$RG_TAG_COMMIT" ] && [ "$RG_TAG_COMMIT" != "$RG_PREVIOUS" ]; then
    pass "the release commit is a new commit and v1.0.1 names it"
else
    fail "the release commit is a new commit and v1.0.1 names it (tag=$RG_TAG_COMMIT previous=$RG_PREVIOUS)"
fi
if grep -F 'run list' "$RG_ROOT/ci-success.gh.log" | grep -Fq -- "\"$RG_TAG_COMMIT\""; then
    pass "the CI wait asks for the tag's commit"
else
    fail "the CI wait asks for the tag's commit (run list calls: $(grep -F 'run list' "$RG_ROOT/ci-success.gh.log" | head -n 1))"
fi
assert_log_lacks "the CI wait never asks for the commit before the release commit" \
    "\"$RG_PREVIOUS\"" "$RG_ROOT/ci-success.gh.log"
assert_log_contains "the CI result reported is the tag commit's run" \
    "https://example.test/runs/tag-commit" "$RG_ROOT/ci-success.out"
assert_log_lacks "the previous commit's run is not reported as the release CI" \
    "https://example.test/runs/previous-commit" "$RG_ROOT/ci-success.out"
assert_log_contains "the published notes cite the tag's commit" \
    "- Commit：$RG_TAG_COMMIT" "$RG_ROOT/ci-success.notes"
assert_status "the release tag reaches mine and names the release commit" \
    "$RG_TAG_COMMIT" "$(rg_git --git-dir="$RG_ROOT/ci-success/mine.git" rev-parse -q --verify 'refs/tags/v1.0.1^{commit}')"

RG_PROJECT=$(make_release_fixture ci-failure)
RG_PREVIOUS=$(rg_git -C "$RG_PROJECT" rev-parse HEAD)
( cd "$RG_PROJECT" && "$SCRIPT" bump patch ) > "$RG_ROOT/ci-failure.bump.out" 2>&1
run_release_fixture "$RG_PROJECT" failure ci-failure
assert_status "real-git release stops when the tag's CI fails" "2" "$RG_STATUS"
assert_log_contains "the failed tag CI is reported as a failure" \
    "CI 結束但未成功" "$RG_ROOT/ci-failure.out"
assert_log_lacks "a failed tag CI is never announced as complete" \
    "CI 已完成" "$RG_ROOT/ci-failure.out"
assert_log_lacks "no release notes are written after a failed tag CI" \
    "release edit" "$RG_ROOT/ci-failure.gh.log"

# The release commit takes the release files and nothing else. Work already
# staged outside RELEASE_FILES must not be committed, tagged and pushed under a
# "chore(release)" subject, and must still be staged afterwards. The unstaged
# row is the control: a dirty tree is the designed use (--apply is the
# default), so a fix that refuses it is wrong too.
# release commit 只收 release 檔案。清單外已暫存的工作不能被當成 "chore(release)" 提交、
# 打標籤並推播，結束後也必須仍是暫存狀態。未暫存那一列是對照：工作目錄有未提交變更正是
# 設計上的用法（預設 --apply），拒絕它的修法也是錯的。
rg_release_only_lists_release_files() {
    local project="$1"
    local label="$2"
    local name
    local outside=""
    while IFS= read -r name; do
        case " CHANGELOG.md better-rm test-better-rm.sh install.sh install-hooks.sh README.md " in
            *" $name "*) ;;
            *) outside="$outside $name" ;;
        esac
    done < <(rg_git -C "$project" diff-tree --no-commit-id -r --name-only 'v1.0.1^{commit}')
    if [ -z "$outside" ]; then
        pass "$label: the release commit holds release files only"
    else
        fail "$label: the release commit holds release files only (also:$outside)"
    fi
}

RG_PROJECT=$(make_release_fixture staged-outside)
RG_PREVIOUS=$(rg_git -C "$RG_PROJECT" rev-parse HEAD)
( cd "$RG_PROJECT" && "$SCRIPT" bump patch ) > "$RG_ROOT/staged-outside.bump.out" 2>&1
printf '// staged work in progress\n' >> "$RG_PROJECT/hooks/x.js"
rg_git -C "$RG_PROJECT" add hooks/x.js
run_release_fixture "$RG_PROJECT" success staged-outside
assert_status "a release with staged work outside the release files completes" "0" "$RG_STATUS"
rg_release_only_lists_release_files "$RG_PROJECT" "staged work outside the list"
if rg_git -C "$RG_PROJECT" diff --cached --name-only | grep -Fxq hooks/x.js \
    && rg_git -C "$RG_PROJECT" show :hooks/x.js | grep -Fq 'staged work in progress'; then
    pass "the staged change outside the release files is still staged"
else
    fail "the staged change outside the release files is still staged (index: $(rg_git -C "$RG_PROJECT" diff --cached --name-only | tr '\n' ' '))"
fi
if rg_git --git-dir="$RG_ROOT/staged-outside/mine.git" show main:hooks/x.js | grep -Fq 'staged work in progress'; then
    fail "the pushed main does not carry the staged work"
else
    pass "the pushed main does not carry the staged work"
fi

RG_PROJECT=$(make_release_fixture unstaged-outside)
RG_PREVIOUS=$(rg_git -C "$RG_PROJECT" rev-parse HEAD)
( cd "$RG_PROJECT" && "$SCRIPT" bump patch ) > "$RG_ROOT/unstaged-outside.bump.out" 2>&1
printf '// unstaged work in progress\n' >> "$RG_PROJECT/hooks/x.js"
run_release_fixture "$RG_PROJECT" success unstaged-outside
assert_status "a release with unstaged work outside the release files completes" "0" "$RG_STATUS"
rg_release_only_lists_release_files "$RG_PROJECT" "unstaged work outside the list"
if [ "$(rg_git -C "$RG_PROJECT" status --porcelain -- hooks/x.js)" = " M hooks/x.js" ]; then
    pass "the unstaged change outside the release files stays unstaged"
else
    fail "the unstaged change outside the release files stays unstaged (status: $(rg_git -C "$RG_PROJECT" status --porcelain -- hooks/x.js))"
fi

# A tag the remote already has. The refusal used to ask only the local tags,
# and `--follow-tags` skips a tag the remote has under that name without an
# error, so a clone without the tag committed a new bump, pushed main, left
# the remote tag where it was and then edited that existing release's notes.
# The release must stop before it commits, tags or pushes anything.
# 遠端已經有的標籤。拒絕原本只問本機標籤，而 `--follow-tags` 遇到遠端同名標籤會無聲略過，
# 所以沒有那個標籤的 clone 會提交新的 bump、推 main、遠端標籤原地不動，接著改寫那個既有
# release 的說明。release 必須在提交、打標籤、推播任何東西之前就停下。
RG_PROJECT=$(make_release_fixture remote-tag)
RG_PREVIOUS=$(rg_git -C "$RG_PROJECT" rev-parse HEAD)
rg_git --git-dir="$RG_ROOT/remote-tag/mine.git" tag -a v1.0.1 -m 'published elsewhere' "$RG_PREVIOUS"
( cd "$RG_PROJECT" && "$SCRIPT" bump patch ) > "$RG_ROOT/remote-tag.bump.out" 2>&1
run_release_fixture "$RG_PROJECT" success remote-tag
if [ "$RG_STATUS" -ne 0 ]; then
    pass "a release whose tag the remote already has stops (status $RG_STATUS)"
else
    fail "a release whose tag the remote already has stops (status 0)"
fi
assert_status "no release commit is made when the remote has the tag" \
    "$RG_PREVIOUS" "$(rg_git -C "$RG_PROJECT" rev-parse HEAD)"
if rg_git -C "$RG_PROJECT" rev-parse -q --verify refs/tags/v1.0.1 >/dev/null; then
    fail "no local tag is created when the remote has the tag"
else
    pass "no local tag is created when the remote has the tag"
fi
assert_status "the remote main is untouched when the remote has the tag" \
    "$RG_PREVIOUS" "$(rg_git --git-dir="$RG_ROOT/remote-tag/mine.git" rev-parse refs/heads/main)"
assert_log_lacks "no release notes are edited when the remote has the tag" \
    "release edit" "$RG_ROOT/remote-tag.gh.log"

# The same question when the remote cannot answer: the release stops before it
# commits rather than guessing that the tag is free.
# 遠端無法回答時也一樣：release 在提交之前停下，而不是猜標籤沒人用。
RG_PROJECT=$(make_release_fixture remote-unreachable)
RG_PREVIOUS=$(rg_git -C "$RG_PROJECT" rev-parse HEAD)
rg_git -C "$RG_PROJECT" remote set-url mine "$RG_ROOT/remote-unreachable/no-such-repository.git"
( cd "$RG_PROJECT" && "$SCRIPT" bump patch ) > "$RG_ROOT/remote-unreachable.bump.out" 2>&1
run_release_fixture "$RG_PROJECT" success remote-unreachable
assert_status "a release whose remote cannot be asked stops with status 2" "2" "$RG_STATUS"
assert_status "no release commit is made when the remote cannot be asked" \
    "$RG_PREVIOUS" "$(rg_git -C "$RG_PROJECT" rev-parse HEAD)"
if rg_git -C "$RG_PROJECT" rev-parse -q --verify refs/tags/v1.0.1 >/dev/null; then
    fail "no local tag is created when the remote cannot be asked"
else
    pass "no local tag is created when the remote cannot be asked"
fi

printf 'Passed: %s\nFailed: %s\n' "$PASSED" "$FAILED"
if [ "$FAILED" -ne 0 ]; then
    exit 1
fi
