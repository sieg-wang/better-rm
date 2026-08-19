# shellcheck shell=bash
# 殘留驗證 harness 的共用底座 / shared plumbing for test/residual-harness/*.sh
#
# 這些腳本會驅動一支「刪除工具」，而且會對整個 repo 做可寫的副本。所以底座只有
# 兩個真正的職責：**把工作區釘在 repo 之外**，以及**把 better-rm 會讀的每一個
# 環境變數都指進那個工作區**。其餘都是方便。
#
# These scripts drive a deletion tool and take writable copies of the whole repo.
# So this file has exactly two real jobs: pin the workspace OUTSIDE the repo, and
# point every environment variable better-rm reads INTO that workspace. The rest
# is convenience.
#
# 為什麼「拒絕寫進 repo」不是潔癖：2026-08-18 有一支 repo 工具的輸出路徑是從
# **腳本自己的位置**推導的，被拿去對活的工作樹跑，毀掉了真實使用者資料。這裡的
# 工作區一律 mktemp，而且會在建立後主動驗證它不在 repo 底下。
# Why the refusal is not paranoia: on 2026-08-18 a repo tool whose output path was
# derived from the SCRIPT's location was run against the live tree and destroyed
# real user data. Workspaces here are always mktemp, and are re-checked afterwards.
#
# 呼叫端契約 / caller contract:
#   HS_SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
#   HS_REPO="$(cd -- "$HS_SELF_DIR/../.." && pwd -P)"
#   . "$HS_SELF_DIR/lib/harness.sh"
#   hs_require_repo
#   hs_workspace <short-name>
#
# 相容性：stock /bin/bash 3.2.57。不用 {fd}>>、不用 GNU-only 的 stat 旗標、
# 不用 `sed -i ''`（BSD-only）——一律走 perl -i。
# Portability: stock /bin/bash 3.2.57. No {fd}>>, no GNU-only stat flags, and no
# BSD-only `sed -i ''` — text edits go through perl -i, which behaves the same on
# macOS and Linux.

# 一律用真正的 rm 執行檔，不要交給 shell 去解析那個字。
# 這個 repo 的 better-rm 是以 shell alias 安裝的，而非互動 shell 不展開 alias，所以
# 裸的 `rm` 目前本來就會打到 /bin/rm。但那是「安裝方式」的性質，不是這份 harness 的
# 性質：哪天改成 PATH shim，下面每一次 rm 都會把工作區丟進使用者**真正的**垃圾桶，
# 而 TOCTOU racer 那個熱迴圈一秒會丟進去幾百筆。所以這裡不靠那個巧合。
# Always call the real rm binary rather than letting the shell resolve the word.
# better-rm installs as a shell alias and non-interactive bash does not expand
# aliases, so a bare `rm` happens to reach /bin/rm today — but that is a property of
# the install method, not of this harness. Under a PATH shim every rm below would
# dump the workspace into the user's REAL trash, hundreds of entries per second from
# the TOCTOU racer's hot loop. Do not depend on the coincidence.
HS_RM=/bin/rm
[ -x "$HS_RM" ] || HS_RM=rm

HS_WORK=""
HS_BG_PIDS=""
HS_TIMEOUT_BIN=""
HS_SNAP_DIR=""
HS_SNAP_WD=""
HS_SNAP_FILES=""
HS_PIN_TOTAL=""
HS_PIN_PASSED=""
HS_PIN_FAILED=""
HS_PIN_REASON=""
HS_FAILURES=0

# ---------------------------------------------------------------------------
# 基本工具 / basics
# ---------------------------------------------------------------------------

hs_die() {
    printf 'residual-harness: FATAL: %s\n' "$*" >&2
    exit 90
}

hs_note() {
    printf 'residual-harness: %s\n' "$*"
}

# 解析成絕對、去 symlink 的目錄路徑。刻意不用 `readlink -f`（macOS 沒有）也不用
# `stat`（GNU 的 `stat -f` 印的是檔案系統狀態並以 1 結束，那個 fallback 慣用法是壞的）。
# Absolute, symlink-free directory path. Deliberately avoids `readlink -f` (absent
# on macOS) and `stat` (GNU `stat -f` prints FILESYSTEM status and exits 1, so the
# usual `stat -f … || stat -c …` fallback idiom is broken).
hs_abs_dir() {
    ( cd -- "$1" 2>/dev/null && pwd -P ) || return 1
}

# 對還不存在的路徑也要能判斷：往上找到第一個存在的祖先再解析。
# Works for paths that do not exist yet: resolve the deepest existing ancestor.
hs_abs_maybe() {
    local p="$1" parent
    parent="$p"
    while [ ! -d "$parent" ]; do
        case "$parent" in
            /|.|"") return 1 ;;
        esac
        parent=$(dirname -- "$parent")
    done
    hs_abs_dir "$parent"
}

# ---------------------------------------------------------------------------
# repo 定位與寫入拒絕 / repo location and the write refusal
# ---------------------------------------------------------------------------

hs_require_repo() {
    local f
    [ -n "${HS_REPO:-}" ] || hs_die "HS_REPO is unset; the caller must set it from its own \${BASH_SOURCE[0]}"
    HS_REPO=$(hs_abs_dir "$HS_REPO") ||
        hs_die "HS_REPO '$HS_REPO' is not a directory"
    for f in better-rm test-better-rm.sh test-hooks.js KNOWN-RESIDUALS.md run-test-suites.sh; do
        [ -e "$HS_REPO/$f" ] ||
            hs_die "'$HS_REPO' does not look like the better-rm repo (missing $f)"
    done
}

# 唯一一道真正的安全閘：任何工作路徑落在 repo 內就整支拒跑並說明原因。
# The one real safety gate: refuse to run at all if a work path lands in the repo.
hs_refuse_inside_repo() {
    local p="$1" resolved
    resolved=$(hs_abs_maybe "$p") ||
        hs_die "cannot resolve '$p' to decide whether it is inside the repo; refusing to continue"
    case "$resolved/" in
        "$HS_REPO"/*)
            hs_die "REFUSING TO RUN: work path '$p' resolves to '$resolved', which is inside the repo ($HS_REPO).
  這些腳本會刪東西。工作區必須在 repo 之外（\${TMPDIR:-/tmp} 底下的 mktemp -d）。
  These scripts delete things. The workspace must live outside the repo, under
  \${TMPDIR:-/tmp} via mktemp -d. Check TMPDIR."
            ;;
    esac
    case "$HS_REPO/" in
        "$resolved"/*)
            hs_die "REFUSING TO RUN: work path '$resolved' CONTAINS the repo ($HS_REPO)."
            ;;
    esac
}

# ---------------------------------------------------------------------------
# 工作區 / workspace
# ---------------------------------------------------------------------------

hs_workspace() {
    local name="$1" base
    base=${TMPDIR:-/tmp}
    base=${base%/}
    [ -d "$base" ] || hs_die "TMPDIR '$base' is not a directory"
    hs_refuse_inside_repo "$base"

    HS_WORK=$(mktemp -d "$base/better-rm-residual-$name.XXXXXX") ||
        hs_die "mktemp -d under '$base' failed"
    HS_WORK=$(hs_abs_dir "$HS_WORK") || hs_die "cannot resolve the new workspace"
    # mktemp 之後再驗一次：TMPDIR 可能是 repo 內的 symlink。
    # Re-check after mktemp: TMPDIR could be a symlink into the repo.
    hs_refuse_inside_repo "$HS_WORK"

    trap 'hs_cleanup' EXIT
    trap 'hs_cleanup; exit 130' INT
    trap 'hs_cleanup; exit 143' TERM

    mkdir -p "$HS_WORK/home" "$HS_WORK/trash" "$HS_WORK/state" \
             "$HS_WORK/xdg-state" "$HS_WORK/cwd" "$HS_WORK/tmp" ||
        hs_die "cannot populate the workspace"
    HS_SNAP_DIR="$HS_WORK/pristine"

    hs_note "repo      : $HS_REPO"
    hs_note "workspace : $HS_WORK  (removed on exit)"
    if [ -n "${BETTER_RM_PROTECTED_DIRS:-}" ]; then
        hs_note "NOTE      : BETTER_RM_PROTECTED_DIRS is set and is inherited on purpose:"
        hs_note "            $BETTER_RM_PROTECTED_DIRS"
        hs_note "            它只會多擋不會少擋，但若涵蓋到工作區就會改變探針輸出。"
        hs_note "            It can only ADD refusals, but if it covers the workspace it"
        hs_note "            will change what these probes print. Unset it to compare."
    fi
}

# 只殺自己啟動的背景行程；只刪自己用 mktemp 建、名字帶得出 harness 前綴的目錄。
# Kills only PIDs this harness started; removes only a mktemp dir carrying the
# harness prefix.
hs_cleanup() {
    local status=$? pid
    trap - EXIT INT TERM
    for pid in $HS_BG_PIDS; do
        kill "$pid" 2>/dev/null
    done
    for pid in $HS_BG_PIDS; do
        wait "$pid" 2>/dev/null
    done
    HS_BG_PIDS=""
    if [ -n "$HS_WORK" ] && [ -d "$HS_WORK" ]; then
        case "$HS_WORK" in
            */better-rm-residual-*.??????)
                "$HS_RM" -rf -- "$HS_WORK"
                ;;
            *)
                printf 'residual-harness: refusing to remove unexpected workspace %s\n' \
                    "$HS_WORK" >&2
                ;;
        esac
    fi
    return $status
}

hs_track_bg() {
    HS_BG_PIDS="$HS_BG_PIDS $1"
}

# ---------------------------------------------------------------------------
# timeout（macOS 沒有內建）/ timeout (not shipped by stock macOS)
# ---------------------------------------------------------------------------

hs_detect_timeout() {
    if command -v timeout >/dev/null 2>&1; then
        HS_TIMEOUT_BIN=timeout
    elif command -v gtimeout >/dev/null 2>&1; then
        HS_TIMEOUT_BIN=gtimeout
    else
        HS_TIMEOUT_BIN=""
    fi
}

# 會 hang 的探針一定要有 timeout，沒有就直說並退出，不要偽裝成量到了。
# A hang probe without a bound measures nothing; say so instead of pretending.
hs_require_timeout() {
    hs_detect_timeout
    [ -n "$HS_TIMEOUT_BIN" ] ||
        hs_die "this probe plants objects that make better-rm block forever and needs
  coreutils 'timeout' (or 'gtimeout'). Stock macOS ships neither: brew install coreutils."
}

# ---------------------------------------------------------------------------
# 隔離執行 / isolated execution
#
# better-rm 會讀**五個**環境變數：HOME / TRASH_DIR / BETTER_RM_STATE_DIR /
# XDG_STATE_HOME / BETTER_RM_PROTECTED_DIRS（TRASH_DIR 預設 $HOME/.Trash，state dir
# 沒設就走 XDG_STATE_HOME）。前四個全部指進工作區，再加上 TMPDIR 與一個工作區內的
# cwd，真實使用者檔案就碰不到。
#
# 第五個**刻意不動**：`BETTER_RM_PROTECTED_DIRS` 是使用者「新增保護」的唯一介面，
# 只會多擋、不會少擋（better-rm:523-560），所以繼承它不可能讓真實檔案被碰到。
# 但它會改變探針的輸出——例如指到 $TMPDIR 底下就會讓工作區裡的 victim 被拒絕刪除。
# 把它清空反而是在一支「刪東西的腳本」裡靜默拿掉一道保護，所以這裡選擇：繼承，
# 但在 workspace 建立時把值印出來，讓奇怪的結果解釋得掉。
# better-rm reads FIVE variables. The first four are pointed into the workspace.
# The fifth, BETTER_RM_PROTECTED_DIRS, is deliberately left alone: it is the user's
# only interface for ADDING protection and can never remove any, so inheriting it
# cannot expose real files — but it can change what a probe prints. Clearing it
# would mean silently disabling a guard inside a script that deletes things, so it
# is inherited and REPORTED instead.
# ---------------------------------------------------------------------------

HS_HOME=""
HS_TRASH=""
HS_STATE=""

hs_env_defaults() {
    [ -n "$HS_HOME" ]  || HS_HOME="$HS_WORK/home"
    [ -n "$HS_TRASH" ] || HS_TRASH="$HS_WORK/trash"
    [ -n "$HS_STATE" ] || HS_STATE="$HS_WORK/state"
}

# usage: hs_isolated <cwd> <cmd> [args...]
hs_isolated() {
    local wd="$1"
    shift
    hs_env_defaults
    hs_refuse_inside_repo "$wd"
    (
        cd -- "$wd" || exit 99
        HOME="$HS_HOME" \
        TRASH_DIR="$HS_TRASH" \
        BETTER_RM_STATE_DIR="$HS_STATE" \
        XDG_STATE_HOME="$HS_WORK/xdg-state" \
        TMPDIR="$HS_WORK/tmp" \
        "$@"
    )
}

# ---------------------------------------------------------------------------
# repo 副本與快照 / repo copies and snapshots
# ---------------------------------------------------------------------------

hs_copy_repo() {
    local dest="$1"
    hs_refuse_inside_repo "$dest"
    mkdir -p "$dest" || hs_die "cannot create '$dest'"
    cp -R "$HS_REPO/." "$dest/" || hs_die "copying the repo into '$dest' failed"
    chmod +x "$dest/better-rm" "$dest/test-better-rm.sh" 2>/dev/null
}

# usage: hs_snapshot <workdir> <file>...
hs_snapshot() {
    local wd="$1" f
    shift
    HS_SNAP_WD="$wd"
    HS_SNAP_FILES="$*"
    mkdir -p "$HS_SNAP_DIR" || hs_die "cannot create the snapshot dir"
    for f in "$@"; do
        cp -p "$wd/$f" "$HS_SNAP_DIR/$f" || hs_die "cannot snapshot '$f'"
    done
}

hs_restore() {
    local f
    for f in $HS_SNAP_FILES; do
        cp -f "$HS_SNAP_DIR/$f" "$HS_SNAP_WD/$f" || hs_die "cannot restore '$f'"
    done
    [ -e "$HS_SNAP_WD/better-rm" ] && chmod +x "$HS_SNAP_WD/better-rm"
    return 0
}

hs_verify_snapshot() {
    local f rc=0
    printf 'byte-identity vs pristine:\n'
    for f in $HS_SNAP_FILES; do
        if cmp -s "$HS_SNAP_WD/$f" "$HS_SNAP_DIR/$f"; then
            printf '  %-24s OK\n' "$f"
        else
            printf '  %-24s *** DIFFERS ***\n' "$f"
            rc=1
        fi
    done
    return $rc
}

# 突變必須真的改到東西。少了這道，一個打空的 perl 取代會讓探針印出「GREEN＝洞還開著」，
# 而其實它什麼都沒做。
# A mutation that silently no-ops would make a probe print "GREEN = hole open" while
# having changed nothing. Assert the edit landed.
hs_assert_changed() {
    local f="$1"
    if cmp -s "$HS_SNAP_WD/$f" "$HS_SNAP_DIR/$f"; then
        printf 'MUTATION-NO-OP (%s unchanged) ' "$f"
        HS_FAILURES=$((HS_FAILURES + 1))
        return 1
    fi
    return 0
}

# 突變後語法還要是合法的，否則「pin 還是綠的」可能只是因為檔案已經壞掉。
# The mutant must still parse, or "the pin stayed green" may just mean the file broke.
hs_assert_parses() {
    local f="$1"
    case "$f" in
        *.js)
            if command -v node >/dev/null 2>&1; then
                node --check "$HS_SNAP_WD/$f" >/dev/null 2>&1 && return 0
                printf 'MUTANT-DOES-NOT-PARSE(node) '
                HS_FAILURES=$((HS_FAILURES + 1))
                return 1
            fi
            ;;
        *)
            bash -n "$HS_SNAP_WD/$f" >/dev/null 2>&1 && return 0
            printf 'MUTANT-DOES-NOT-PARSE(bash) '
            HS_FAILURES=$((HS_FAILURES + 1))
            return 1
            ;;
    esac
    return 0
}

# ---------------------------------------------------------------------------
# 文字突變（perl -i，兩個平台行為相同）/ text mutations
# ---------------------------------------------------------------------------

# usage: hs_sub_str <file> <literal-from> <literal-to>   （全部出現處）
hs_sub_str() {
    HS_FROM="$2" HS_TO="$3" perl -pi -e \
        'BEGIN { $f = quotemeta($ENV{HS_FROM}); $t = $ENV{HS_TO} } s/$f/$t/ge;' "$1"
}

# usage: hs_sub_line <file> <exact-line-without-newline> <replacement-without-newline>
hs_sub_line() {
    HS_FROM="$2" HS_TO="$3" perl -pi -e \
        'BEGIN { $f = $ENV{HS_FROM}; $t = $ENV{HS_TO} } $_ = $t . "\n" if $_ eq $f . "\n";' "$1"
}

# usage: hs_del_line <file> <exact-line-without-newline>
hs_del_line() {
    HS_FROM="$2" perl -ni -e \
        'BEGIN { $f = $ENV{HS_FROM} } print unless $_ eq $f . "\n";' "$1"
}

# ---------------------------------------------------------------------------
# 跑核心 suite 並讀出「雙向釘」的判定 / run the core suite and read the two-way pin
# ---------------------------------------------------------------------------

hs_strip_ansi() {
    LC_ALL=C sed "s/$(printf '\033')\\[[0-9;]*m//g"
}

# usage: hs_pin <workdir> [extra env assignments handled by caller]
# 產出：HS_PIN_STATUS=GREEN|RED、HS_PIN_TOTAL / HS_PIN_PASSED / HS_PIN_FAILED、HS_PIN_REASON
HS_PIN_STATUS=""
# 呼叫端可設 HS_LC_ALL 讓整套 suite 在指定 locale 下跑（極限 4 的 NUL 繞法需要）。
# Callers may set HS_LC_ALL to run the whole suite under a chosen locale (limit 4).
HS_LC_ALL=""
hs_pin() {
    local wd="$1" out log
    log="$HS_WORK/last-core.log"
    hs_detect_timeout
    set -- ./test-better-rm.sh
    [ -n "$HS_LC_ALL" ] && set -- env "LC_ALL=$HS_LC_ALL" "$@"
    [ -n "$HS_TIMEOUT_BIN" ] && set -- "$HS_TIMEOUT_BIN" 900 "$@"
    hs_isolated "$wd" "$@" > "$log" 2>&1
    out=$(hs_strip_ansi < "$log")
    HS_PIN_TOTAL=$(printf '%s\n' "$out" | sed -n 's/.*總測試數 (Total Tests): *\([0-9][0-9]*\).*/\1/p' | tail -1)
    # shellcheck disable=SC2034  # read by the sourcing scripts, not here
    HS_PIN_PASSED=$(printf '%s\n' "$out" | sed -n 's/.*通過測試 (Passed): *\([0-9][0-9]*\).*/\1/p' | tail -1)
    HS_PIN_FAILED=$(printf '%s\n' "$out" | sed -n 's/.*失敗測試 (Failed): *\([0-9][0-9]*\).*/\1/p' | tail -1)
    HS_PIN_REASON=""
    if printf '%s\n' "$out" | grep -q '殘留的理由與其程式碼事實一致'; then
        HS_PIN_STATUS=GREEN
    else
        HS_PIN_STATUS=RED
        HS_PIN_REASON=$(printf '%s\n' "$out" | grep '與程式碼不同步' |
            sed 's/.*不同步://; s/(修好了.*//' | head -1 | cut -c1-110)
        [ -n "$HS_PIN_REASON" ] || HS_PIN_REASON='(pin line absent — suite did not reach it)'
    fi
}

# usage: hs_pin_report <workdir> <expected GREEN|RED>
hs_pin_report() {
    local wd="$1" want="$2"
    hs_pin "$wd"
    if [ "$HS_PIN_STATUS" = "$want" ]; then
        printf '%-5s [want %-5s OK   ] total=%s failed=%s' \
            "$HS_PIN_STATUS" "$want" "${HS_PIN_TOTAL:-?}" "${HS_PIN_FAILED:-?}"
    else
        printf '%-5s [want %-5s MISS!] total=%s failed=%s' \
            "$HS_PIN_STATUS" "$want" "${HS_PIN_TOTAL:-?}" "${HS_PIN_FAILED:-?}"
        HS_FAILURES=$((HS_FAILURES + 1))
    fi
    [ -n "$HS_PIN_REASON" ] && printf ' :: %s' "$HS_PIN_REASON"
    printf '\n'
}

hs_case() {
    printf '%-56s ' "$1"
}

hs_summary() {
    printf '\n'
    if [ "$HS_FAILURES" -eq 0 ]; then
        printf 'RESULT: every case matched its documented expectation.\n'
        return 0
    fi
    printf 'RESULT: %s case(s) did NOT match the documented expectation.\n' "$HS_FAILURES"
    printf '        這是有意義的訊號，不是雜訊——先讀 README.md 的「今天應該印什麼」。\n'
    printf '        That is a signal, not noise. Read README.md ("expected output today") first.\n'
    return 1
}

# 高解析度時間（BSD date 沒有 %N；perl 的 Time::HiRes 是 core module，兩平台都在）。
# High-resolution clock: BSD date has no %N; perl's Time::HiRes is core on both.
hs_now() {
    perl -MTime::HiRes=time -e 'printf "%.3f\n", time'
}

hs_elapsed() {
    perl -e 'printf "%.3f\n", $ARGV[1] - $ARGV[0]' "$1" "$2"
}
