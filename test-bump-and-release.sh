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
        # No release tag exists yet, unless a row says it does.
        [ "${BETTER_RM_TEST_LOCAL_TAG:-0}" = 1 ] && exit 0
        exit 1
        ;;
    tag)
        case "$2" in
            --sort=-creatordate) exit 0 ;;   # no tags -> empty stdout
            --merged) exit 0 ;;              # no tag reachable from HEAD -> empty stdout
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

# The push must never overwrite anything on the remote. The checks above read
# only which remote it names, so a trailing --force kept every row green; split
# the logged argv into words and refuse every overwriting spelling.
# 推播絕不能覆寫遠端的任何東西。上面幾列只看指向哪個遠端，結尾多一個 --force 時全部仍綠；
# 把記錄下來的 argv 拆成字，任何覆寫的寫法都不接受。
PUSH_OVERWRITE_WORDS=""
for push_word in $PUSH_LINE; do
    case "$push_word" in
        --force|--force=*|-f|--force-with-lease|--force-with-lease=*|--force-if-includes|--mirror|--delete|-d|--prune|+*)
            PUSH_OVERWRITE_WORDS="$PUSH_OVERWRITE_WORDS $push_word"
            ;;
    esac
done
if [ -n "$PUSH_LINE" ] && [ -z "$PUSH_OVERWRITE_WORDS" ]; then
    pass "git push carries no force, delete or '+' refspec"
else
    fail "git push carries no force, delete or '+' refspec (logged: $PUSH_LINE; found:$PUSH_OVERWRITE_WORDS)"
fi

# The local tag refusal, the one the real-git rows cannot reach because their
# clones never hold the next tag: with the tag present the release must stop
# with status 2 before it commits, tags or pushes. A refusal that came after
# the push would still exit 2, so the git log is read as well.
# 本機標籤的拒絕（真 git 那幾列碰不到它，因為它們的 clone 從來沒有下一個標籤）：標籤已在時，
# release 必須以狀態 2 停下，而且在提交、打標籤、推播之前。推播之後才拒絕的版本也會回 2，
# 所以也讀 git 記錄。
TAGGED_GIT_LOG="$TMP_ROOT/git-tagged.log"
: > "$TAGGED_GIT_LOG"
TAGGED_STATUS=0
PATH="$FAKE_BIN:$PATH" BETTER_RM_TEST_GIT_LOG="$TAGGED_GIT_LOG" \
    BETTER_RM_TEST_GH_LOG="$TMP_ROOT/gh-tagged.log" BETTER_RM_TEST_LOCAL_TAG=1 \
    "$SCRIPT" release --repo "$PROJECT" --auto >"$TMP_ROOT/tagged.out" 2>"$TMP_ROOT/tagged.err" \
    || TAGGED_STATUS=$?
assert_status "a release whose tag already exists locally stops with status 2" "2" "$TAGGED_STATUS"
if grep -Eq -- ' (commit|push)( |$)| tag -a( |$)' "$TAGGED_GIT_LOG"; then
    fail "nothing is committed, tagged or pushed when the tag exists locally ($(grep -E -- ' (commit|push)( |$)| tag -a( |$)' "$TAGGED_GIT_LOG" | head -n 1))"
else
    pass "nothing is committed, tagged or pushed when the tag exists locally"
fi

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
# answers `run list` by running the script's own --json/--jq over a fixture list.
# 真 git 的 fixture：上面的假 git 只回一個固定的 HEAD 與乾淨的狀態，看不到 release
# 提交、打標籤、等 CI 的是哪一個 commit。這幾列用真的 git，`mine` 換成 TMP_ROOT 裡的
# 本機 bare repository；gh 仍是替身，拿腳本自己的 --json／--jq 去跑一份固定的執行清單來回答 run list。
RG_ROOT="$TMP_ROOT/real-git"
RG_BIN="$RG_ROOT/bin"
mkdir -p "$RG_BIN"

# The stub evaluates the script's selection program with jq (gh itself runs it
# with its embedded gojq), so the suite needs a jq on PATH. Without one the stub
# answers each `run list` with a failed run, the rows below that expect a
# release to complete fail, and this row names the cause.
# 替身用 jq 執行腳本的篩選程式（gh 本身用內建的 gojq），所以這套測試需要 PATH 上有 jq。沒有的話替身對每個
# run list 都回一次失敗的執行，下面預期 release 完成的列會失敗，而這一列說出原因。
if command -v jq >/dev/null 2>&1; then
    pass "jq is available to evaluate the script's own --jq program"
else
    fail "jq is available to evaluate the script's own --jq program (none on PATH)"
fi

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
        # BR-B-5: run the script's OWN --json and --jq over a fixture list, as gh
        # does, instead of pulling the commit out of the --jq text. The atomic push
        # of main plus the tag starts two ci-release.yml runs of the SAME commit,
        # and only the tag run has the release job; here the main-branch run is the
        # newer of the two and its verdict differs from the tag run's whenever a
        # row sets BETTER_RM_TEST_MAIN_CI. The newest run of that commit is a
        # workflow_dispatch run on the tag ref (a manual re-run, whose release job
        # fails once the release exists), so a selection that drops
        # `event == "push"` takes its failure for the tag push's verdict. Fields
        # the script did not ask for are dropped, as gh drops them. A program that
        # selects nothing (or does not compile) gets a failed run, so it ends the
        # release at once instead of polling for 30 minutes.
        # BR-B-5：照 gh 的做法，拿腳本自己的 --json 與 --jq 去跑一份固定清單，而不是從 --jq 文字裡抽出
        # commit。atomic push（main 加標籤）會對「同一個」commit 啟動兩次 ci-release.yml，只有標籤那次有
        # release job；這裡 main 那次比較新，列設了 BETTER_RM_TEST_MAIN_CI 時兩者結果不同。那個 commit 最新的一次
        # 是在標籤 ref 上的 workflow_dispatch（手動重跑，release 已存在時它的 release job 會失敗），所以拿掉
        # `event == "push"` 的篩選會把它的失敗當成標籤推播的結果。腳本沒要的欄位照 gh 的方式丟掉。什麼都沒選到
        # （或編譯不過）的程式拿到一次失敗的執行，立刻結束，不輪詢 30 分鐘。
        fields=""
        program=""
        while [ $# -gt 0 ]; do
            case "$1" in
                --json) fields="$2"; shift 2 ;;
                --jq) program="$2"; shift 2 ;;
                *) shift ;;
            esac
        done
        tag_commit=$(git -C "$BETTER_RM_TEST_PROJECT" rev-parse -q --verify \
            "refs/tags/$BETTER_RM_TEST_TAG^{commit}" 2>/dev/null)
        selected=$(jq -n \
            --arg fields "$fields" \
            --arg tag "$BETTER_RM_TEST_TAG" \
            --arg tag_commit "$tag_commit" \
            --arg previous "$BETTER_RM_TEST_PREVIOUS" \
            --arg tag_ci "$BETTER_RM_TEST_TAG_CI" \
            --arg main_ci "${BETTER_RM_TEST_MAIN_CI:-success}" '
            [
              {status: "completed", conclusion: "failure", url: "https://example.test/runs/tag-dispatch",
               headSha: $tag_commit, headBranch: $tag, event: "workflow_dispatch", createdAt: "2026-10-22T00:00:02Z"},
              {status: "completed", conclusion: $main_ci, url: "https://example.test/runs/main-branch",
               headSha: $tag_commit, headBranch: "main", event: "push", createdAt: "2026-10-22T00:00:01Z"},
              {status: "completed", conclusion: $tag_ci, url: "https://example.test/runs/tag-commit",
               headSha: $tag_commit, headBranch: $tag, event: "push", createdAt: "2026-10-22T00:00:00Z"},
              {status: "completed", conclusion: "success", url: "https://example.test/runs/previous-commit",
               headSha: $previous, headBranch: "main", event: "push", createdAt: "2026-10-21T00:00:00Z"}
            ]
            | ($fields | split(",")) as $keep
            | map(with_entries(select(.key as $key | $keep | any(.[]; . == $key))))' |
            jq -r "$program" 2>/dev/null) || selected=""
        if [ -n "$selected" ]; then
            printf '%s\n' "$selected"
        else
            printf 'completed\tfailure\thttps://example.test/runs/none-selected\n'
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
# project root, stubbed gh first on PATH, real git. Sets RG_STATUS. The
# main-branch run of the same commit concludes with RG_MAIN_CI (default success).
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
        BETTER_RM_TEST_MAIN_CI="${RG_MAIN_CI:-success}" \
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
assert_log_lacks "the main-branch run of the same commit is not reported as the release CI" \
    "https://example.test/runs/main-branch" "$RG_ROOT/ci-success.out"
assert_log_lacks "a workflow_dispatch run of the tag is not reported as the tag push's CI" \
    "https://example.test/runs/tag-dispatch" "$RG_ROOT/ci-success.out"
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
assert_log_lacks "a passing main-branch run of the same commit is not taken for the tag's CI" \
    "https://example.test/runs/main-branch" "$RG_ROOT/ci-failure.out"

# BR-B-5, the other direction: the main-branch run of the same commit fails while
# the tag run -- the one with the release job -- succeeds and publishes the
# release. Following the main run reported "CI 結束但未成功" for a release that
# exists, so the notes were never written and the advised retry hit the
# local-tag refusal.
# BR-B-5 的另一個方向：同一個 commit 的 main 那次失敗，而標籤那次（有 release job 的那次）成功並發佈了
# release。跟著 main 那次走會對一個已存在的 release 回報「CI 結束但未成功」，說明從沒寫上，建議的重試又撞上
# 本機標籤的拒絕。
RG_PROJECT=$(make_release_fixture main-run-fails)
RG_PREVIOUS=$(rg_git -C "$RG_PROJECT" rev-parse HEAD)
( cd "$RG_PROJECT" && "$SCRIPT" bump patch ) > "$RG_ROOT/main-run-fails.bump.out" 2>&1
RG_MAIN_CI=failure
run_release_fixture "$RG_PROJECT" success main-run-fails
RG_MAIN_CI=success
assert_status "a release completes when its tag CI succeeds and the main-branch run of that commit fails" \
    "0" "$RG_STATUS"
assert_log_contains "the tag run is the CI result reported when the main-branch run fails" \
    "https://example.test/runs/tag-commit" "$RG_ROOT/main-run-fails.out"
assert_log_contains "the notes are written when only the main-branch run failed" \
    "release edit" "$RG_ROOT/main-run-fails.gh.log"

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

# What --no-push does, as the help and SKILL.md now say. Alone it is a release
# run without --auto: checks, then printed suggestions, nothing committed or
# tagged. With --auto it commits and tags and pushes nothing.
# --no-push 做什麼（help 與 SKILL.md 現在的寫法）：單獨使用時是不帶 --auto 的 release：跑檢查、
# 列出建議指令，不提交也不打標籤；加上 --auto 則提交、打標籤，什麼都不推。
RG_PROJECT=$(make_release_fixture no-push-alone)
RG_PREVIOUS=$(rg_git -C "$RG_PROJECT" rev-parse HEAD)
( cd "$RG_PROJECT" && "$SCRIPT" bump patch ) > "$RG_ROOT/no-push-alone.bump.out" 2>&1
run_release_fixture "$RG_PROJECT" success no-push-alone --no-push
assert_status "--no-push alone completes" "0" "$RG_STATUS"
assert_log_contains "--no-push alone runs the release checks" \
    "./test-better-rm.sh" "$RG_ROOT/no-push-alone.out"
assert_log_contains "--no-push alone prints the suggested commands" \
    "版本檢查通過，建議後續指令：" "$RG_ROOT/no-push-alone.out"
assert_status "--no-push alone makes no commit" "$RG_PREVIOUS" "$(rg_git -C "$RG_PROJECT" rev-parse HEAD)"
if rg_git -C "$RG_PROJECT" rev-parse -q --verify refs/tags/v1.0.1 >/dev/null; then
    fail "--no-push alone creates no tag"
else
    pass "--no-push alone creates no tag"
fi

RG_PROJECT=$(make_release_fixture auto-no-push)
RG_PREVIOUS=$(rg_git -C "$RG_PROJECT" rev-parse HEAD)
( cd "$RG_PROJECT" && "$SCRIPT" bump patch ) > "$RG_ROOT/auto-no-push.bump.out" 2>&1
run_release_fixture "$RG_PROJECT" success auto-no-push --auto --no-push
assert_status "--auto --no-push completes" "0" "$RG_STATUS"
assert_status "--auto --no-push commits the bump" "chore(release): bump to 1.0.1" \
    "$(rg_git -C "$RG_PROJECT" log -1 --format=%s)"
assert_status "--auto --no-push tags the release commit" "$(rg_git -C "$RG_PROJECT" rev-parse HEAD)" \
    "$(rg_git -C "$RG_PROJECT" rev-parse -q --verify 'refs/tags/v1.0.1^{commit}')"
assert_status "--auto --no-push pushes nothing" "$RG_PREVIOUS" \
    "$(rg_git --git-dir="$RG_ROOT/auto-no-push/mine.git" rev-parse refs/heads/main)"

# BR-B-6: the notes' base is the previous release in the fork's own history. The
# fork's checkout carries the upstream's tags, and the newest of them by creation
# date (v1.6.0) is one the fork never merged; the notes then counted commits and
# listed "changed files" against a non-ancestor, which put upstream-only files
# into the fork's release. The foreign tag here sits on a side commit, created
# later than v1.0.0.
# BR-B-6：說明的比較基準是 fork 自己歷史裡的上一個 release。fork 的 checkout 帶著上游的標籤，依建立時間最新的
# 那個（v1.6.0）fork 從沒合併過；說明於是對一個非祖先計算 commit 數、列出「變更檔案」，把只有上游才有的檔案
# 放進 fork 的 release。這裡的外來標籤放在一個側支 commit 上，建立時間晚於 v1.0.0。
RG_PROJECT=$(make_release_fixture foreign-tag)
RG_PREVIOUS=$(rg_git -C "$RG_PROJECT" rev-parse HEAD)
RG_FOREIGN_BLOB=$(printf 'upstream only\n' | rg_git -C "$RG_PROJECT" hash-object -w --stdin)
RG_FOREIGN_TREE=$( { rg_git -C "$RG_PROJECT" ls-tree HEAD; printf '100644 blob %s\tupstream-only.txt\n' "$RG_FOREIGN_BLOB"; } |
    rg_git -C "$RG_PROJECT" mktree)
RG_FOREIGN_COMMIT=$(rg_git -C "$RG_PROJECT" commit-tree "$RG_FOREIGN_TREE" -p HEAD -m 'upstream release')
# Tagged 2100-01-01 in git's epoch spelling (it rejects `2100-01-01T00:00:00 +0000`),
# so the foreign tag is the newest by creation date whenever this suite runs.
# 以 git 的 epoch 寫法標成 2100-01-01（它不接受 `2100-01-01T00:00:00 +0000`），所以不論何時跑，外來標籤都是建立時間最新的。
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid \
    GIT_COMMITTER_DATE='@4102444800 +0000' \
    git -C "$RG_PROJECT" tag -a v1.6.0 -m 'upstream release' "$RG_FOREIGN_COMMIT"
if [ "$(rg_git -C "$RG_PROJECT" tag --sort=-creatordate | head -n 1)" = "v1.6.0" ] &&
   ! rg_git -C "$RG_PROJECT" merge-base --is-ancestor v1.6.0 HEAD; then
    pass "the foreign tag is the newest tag and is not in the fork's history"
else
    fail "the foreign tag is the newest tag and is not in the fork's history"
fi
( cd "$RG_PROJECT" && "$SCRIPT" bump patch ) > "$RG_ROOT/foreign-tag.bump.out" 2>&1
run_release_fixture "$RG_PROJECT" success foreign-tag
assert_status "a release with a newer foreign tag in the clone completes" "0" "$RG_STATUS"
assert_log_contains "the notes count the commits since the previous fork release" \
    "- Commit 數：2" "$RG_ROOT/foreign-tag.notes"
assert_log_contains "the notes list the files changed since the previous fork release" \
    "- hooks/x.js" "$RG_ROOT/foreign-tag.notes"
assert_log_lacks "the notes never list a file only the foreign tag has" \
    "- upstream-only.txt" "$RG_ROOT/foreign-tag.notes"

# The order among tags that ARE in the fork's history: the base is the highest
# x.y.z version. v0.10.0 sits on the later commit, tagged 2099: newer by creation
# date and first in plain refname order, but a lower version than v1.0.0. An
# ascending, unsorted or creation-date order picks it and the notes then start
# one commit too late (no hooks/x.js, one commit).
# fork 歷史「裡面」的標籤之間的順序：基準是 x.y.z 版本最高的那個。v0.10.0 在較晚的 commit 上、標成 2099：
# 建立時間較新、在一般 refname 順序裡排第一，版本卻比 v1.0.0 低。遞增、不排序或依建立時間的順序都會選到它，
# 說明就少算一個 commit（沒有 hooks/x.js、commit 數 1）。
RG_PROJECT=$(make_release_fixture tag-order)
RG_PREVIOUS=$(rg_git -C "$RG_PROJECT" rev-parse HEAD)
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid \
    GIT_COMMITTER_DATE='@4070908800 +0000' \
    git -C "$RG_PROJECT" tag -a v0.10.0 -m 'an older release line' HEAD
if [ "$(rg_git -C "$RG_PROJECT" tag --merged HEAD --sort=-creatordate | head -n 1)" = "v0.10.0" ] &&
   [ "$(rg_git -C "$RG_PROJECT" tag --merged HEAD | head -n 1)" = "v0.10.0" ]; then
    pass "the lower reachable tag is the newest by creation date and first in refname order"
else
    fail "the lower reachable tag is the newest by creation date and first in refname order"
fi
( cd "$RG_PROJECT" && "$SCRIPT" bump patch ) > "$RG_ROOT/tag-order.bump.out" 2>&1
run_release_fixture "$RG_PROJECT" success tag-order
assert_status "a release with two reachable x.y.z tags completes" "0" "$RG_STATUS"
assert_log_contains "the notes count from the highest reachable version" \
    "- Commit 數：2" "$RG_ROOT/tag-order.notes"
assert_log_contains "the notes list the files changed since the highest reachable version" \
    "- hooks/x.js" "$RG_ROOT/tag-order.notes"

# BR-B-11: a release that will push needs gh, and it has to say so before it
# commits or tags. The check sat after both, so without gh the release left a
# local release commit and an unpushed tag, and its own re-run then refused the
# version as already tagged. These rows run on a PATH holding git and node but
# no gh, built from named tools rather than by dropping a directory, since gh
# can share a directory with git and node.
# --auto --no-push is documented to commit and tag without gh, so it still must.
# BR-B-11：會推播的 release 需要 gh，而且必須在提交或打標籤之前說出來。檢查原本在兩者之後，所以沒有 gh 時
# release 留下本機 release commit 與沒推出去的標籤，自己的重跑又以「已有標籤」拒絕這個版本。這幾列跑在有 git、
# node 而沒有 gh 的 PATH 上；PATH 用具名工具組成而不是拿掉某個目錄，因為 gh 可能與 git、node 在同一個目錄。
# --auto --no-push 依文件不需要 gh 就能提交與打標籤，所以仍然必須做得到。
NOGH_BIN="$RG_ROOT/no-gh-bin"
mkdir -p "$NOGH_BIN"
for nogh_tool in bash env git node grep sed awk cat date mktemp rm mv sleep tr wc head dirname basename perl uname; do
    nogh_path=$(command -v "$nogh_tool" 2>/dev/null) || continue
    case "$nogh_path" in
        /*) ln -s "$nogh_path" "$NOGH_BIN/$nogh_tool" ;;
    esac
done
if ( PATH="$NOGH_BIN"; command -v gh ) >/dev/null 2>&1; then
    fail "the no-gh PATH really holds no gh"
else
    pass "the no-gh PATH really holds no gh"
fi
run_release_without_gh() { # PROJECT LABEL [args...]: like run_release_fixture, with no gh at all
    local project="$1"
    local label="$2"
    shift 2
    RG_STATUS=0
    ( cd "$project" && PATH="$NOGH_BIN" \
        GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
        GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid \
        GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid \
        "$SCRIPT" "$@" ) > "$RG_ROOT/$label.out" 2>&1 < /dev/null || RG_STATUS=$?
}

RG_PROJECT=$(make_release_fixture no-gh)
RG_PREVIOUS=$(rg_git -C "$RG_PROJECT" rev-parse HEAD)
( cd "$RG_PROJECT" && "$SCRIPT" bump patch ) > "$RG_ROOT/no-gh.bump.out" 2>&1
run_release_without_gh "$RG_PROJECT" no-gh
assert_status "the no-argument release without gh stops with status 2" "2" "$RG_STATUS"
assert_log_contains "the release without gh names the missing gh" "缺少指令：gh" "$RG_ROOT/no-gh.out"
assert_status "the release without gh makes no release commit" \
    "$RG_PREVIOUS" "$(rg_git -C "$RG_PROJECT" rev-parse HEAD)"
if rg_git -C "$RG_PROJECT" rev-parse -q --verify refs/tags/v1.0.1 >/dev/null; then
    fail "the release without gh creates no local tag"
else
    pass "the release without gh creates no local tag"
fi

RG_PROJECT=$(make_release_fixture no-gh-no-push)
RG_PREVIOUS=$(rg_git -C "$RG_PROJECT" rev-parse HEAD)
( cd "$RG_PROJECT" && "$SCRIPT" bump patch ) > "$RG_ROOT/no-gh-no-push.bump.out" 2>&1
run_release_without_gh "$RG_PROJECT" no-gh-no-push --auto --no-push
assert_status "--auto --no-push completes without gh" "0" "$RG_STATUS"
assert_status "--auto --no-push without gh still commits the bump" "chore(release): bump to 1.0.1" \
    "$(rg_git -C "$RG_PROJECT" log -1 --format=%s)"
assert_status "--auto --no-push without gh still tags the release commit" \
    "$(rg_git -C "$RG_PROJECT" rev-parse HEAD)" \
    "$(rg_git -C "$RG_PROJECT" rev-parse -q --verify 'refs/tags/v1.0.1^{commit}')"

HELP_OUT="$TMP_ROOT/help.out"
"$SCRIPT" --help > "$HELP_OUT" 2>&1
if grep -E -- '^[[:space:]]*bump-and-release\.sh --no-push[[:space:]]' "$HELP_OUT" | grep -Fq '一鍵走完'; then
    fail "the help does not say --no-push alone runs the whole flow"
else
    pass "the help does not say --no-push alone runs the whole flow"
fi
assert_log_contains "the help shows --auto --no-push for a commit and tag without a push" \
    "bump-and-release.sh --auto --no-push" "$HELP_OUT"

printf 'Passed: %s\nFailed: %s\n' "$PASSED" "$FAILED"
if [ "$FAILED" -ne 0 ]; then
    exit 1
fi
