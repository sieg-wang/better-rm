#!/bin/bash
#
# coding agent hooks 安裝腳本 / Coding agent hooks installer
#
# 用法 (Usage):
#   ./install-hooks.sh -a claude
#   ./install-hooks.sh -a codex
#   ./install-hooks.sh -a cursor
#   ./install-hooks.sh -a copilot
#   ./install-hooks.sh -a antigravity
#   ./install-hooks.sh -a qoder
#   ./install-hooks.sh -a pi
#   ./install-hooks.sh -a opencode
#   ./install-hooks.sh -a grok
#   ./install-hooks.sh -a claude --global
#   curl -sSL https://github.com/doggy8088/better-rm/releases/latest/download/install-hooks.sh | bash -s -- -a claude
#

set -e  # 遇到錯誤時立即退出 / Exit on error

# 顏色定義 (Color definitions)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 支援的 Coding Agent 清單（目前）
# Supported coding agents list
SUPPORTED_AGENTS=(claude codex cursor copilot antigravity qoder pi opencode grok)
VERSION="1.5.0"
RELEASE_BASE_URL="https://github.com/doggy8088/better-rm/releases/latest/download"
RELEASE_HOOK_ASSET_NAME="protect-important-paths.js"
# OpenCode 外掛沒有對應的 RELEASE_*_ASSET_NAME：它由 write_bundled_opencode_plugin
# 隨安裝程式一起出貨，不從網路取得（原因見該函式）。Release 仍然發佈
# opencode-protect-important-paths.ts 供其他消費者使用，但這支安裝程式不再讀它。
# The OpenCode plugin has no RELEASE_*_ASSET_NAME: write_bundled_opencode_plugin
# ships it with the installer instead of fetching it (see that function for why).
# The release still publishes opencode-protect-important-paths.ts for other
# consumers; this installer no longer reads it.
CLEANUP_DIRS=()

# 取得可用 Agent 列表字串
# Return supported agents as a comma-separated string.
supported_agents_str() {
    local first=1
    local item
    local output=""
    for item in "${SUPPORTED_AGENTS[@]}"; do
        if [ "$first" -eq 1 ]; then
            output="$item"
            first=0
        else
            output="$output, $item"
        fi
    done
    printf '%s' "$output"
}

# 檢查是否為支援的 Agent
# Check whether an agent is supported.
is_supported_agent() {
    local target="$1"
    local candidate
    for candidate in "${SUPPORTED_AGENTS[@]}"; do
        if [ "$candidate" = "$target" ]; then
            return 0
        fi
    done
    return 1
}

# 輸出函式 (Output functions)
info() {
    echo -e "${BLUE}ℹ ${NC}$1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

show_version() {
    echo "install-hooks.sh ${VERSION}"
}

# 檢查命令是否存在 (Check if command exists)
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 逐一刪除暫存目錄。目標必須逐項保留原樣：舊版把路徑以空白串成字串再用未加引號
# 的迴圈展開，含空白的暫存路徑（GNU 的 mktemp -d 會沿用 TMPDIR）會被切成好幾個
# 詞，rm -rf 於是打在不存在或不相干的目標上。這是 rm 打錯目標，不是清不乾淨而已。
# Remove each temp directory. The targets must survive verbatim: joining them
# into a whitespace-separated string and expanding it unquoted splits a temp path
# containing whitespace (GNU mktemp -d honours TMPDIR) into several words, so
# rm -rf lands on unrelated targets — a wrong-target rm, not merely a missed one.
cleanup_release_dirs() {
    local directory
    for directory in ${CLEANUP_DIRS[@]+"${CLEANUP_DIRS[@]}"}; do
        rm -rf -- "$directory"
    done
}

download_release_file() {
    local asset_name="$1"
    local destination="$2"
    local download_url="${RELEASE_BASE_URL}/${asset_name}"

    mkdir -p -- "$(dirname -- "$destination")"

    if command_exists curl; then
        if ! curl -fsSL "$download_url" -o "$destination"; then
            error "無法從 Release 下載：$download_url"
            error "Failed to download from release: $download_url"
            exit 1
        fi
    elif command_exists wget; then
        if ! wget -qO "$destination" "$download_url"; then
            error "無法從 Release 下載：$download_url"
            error "Failed to download from release: $download_url"
            exit 1
        fi
    else
        error "找不到 curl 或 wget，無法下載最新檔案"
        error "curl or wget is required to download latest release assets"
        exit 1
    fi
}

usage() {
    local supported_agents
    supported_agents="$(supported_agents_str)"
    cat <<EOF
better-rm coding agent hooks installer
better-rm Coding Agent Hooks 安裝程式

Usage:
  ./install-hooks.sh -a <agent> [options]

Options:
  -a, --agent <agent>  Coding agent to configure (supported: ${supported_agents})
                       要設定的 Coding Agent（可用：${supported_agents}）
  -v, --version         Show installer version / 顯示安裝工具版本
  -g, --global         Install into the agent's global/user settings
                       安裝到 Agent 的全域／使用者設定（目前僅 Claude 支援）
  -h, --help           Show this help message
                       顯示此說明

Examples:
  ./install-hooks.sh -a claude
  ./install-hooks.sh --agent codex
  ./install-hooks.sh --agent cursor
  ./install-hooks.sh --agent copilot
  ./install-hooks.sh --agent antigravity
  ./install-hooks.sh --agent qoder
  ./install-hooks.sh --agent pi
  ./install-hooks.sh --agent opencode
  ./install-hooks.sh --agent grok
  ./install-hooks.sh --agent claude --global
EOF
}

# 解析命令列參數 (Parse command-line arguments)
parse_arguments() {
    AGENT=""
    GLOBAL_INSTALL=false

    while [ $# -gt 0 ]; do
        case "$1" in
            -a|--agent)
                if [ -n "$AGENT" ]; then
                    error "請勿重複指定 --agent / Do not specify --agent more than once"
                    exit 2
                fi
                if [ $# -lt 2 ] || [ -z "$2" ] || [[ "$2" == -* ]]; then
                    error "--agent 需要一個值 / --agent requires a value"
                    exit 2
                fi
                AGENT="$2"
                shift 2
                ;;
            -g|--global)
                GLOBAL_INSTALL=true
                shift
                ;;
            -v|--version)
                show_version
                exit 0
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "未知的選項：$1 / Unknown option: $1"
                exit 2
                ;;
        esac
    done

    if [ -z "$AGENT" ]; then
        local supported_agents
        supported_agents="$(supported_agents_str)"
        error "請使用 -a 或 --agent 指定 Coding Agent（可用：${supported_agents}）"
        error "Specify a coding agent with -a or --agent (supported: ${supported_agents})"
        exit 2
    fi
}

# 取得安裝腳本與 hook 的實體路徑
# Resolve physical paths for the installer and shared hook
resolve_source_paths() {
    # trap 必須在任何 mktemp 之前就位，否則後續任何一條中止路徑都會留下暫存目錄。
    # The trap has to be armed before any mktemp, or an abort leaks the temp dir.
    trap cleanup_release_dirs EXIT

    SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
    HOOK_SOURCE_PATH="$SCRIPT_DIR/hooks/protect-important-paths.js"

    if [ ! -f "$HOOK_SOURCE_PATH" ] || [ ! -r "$HOOK_SOURCE_PATH" ]; then
        local release_dir
        release_dir="$(mktemp -d)"
        CLEANUP_DIRS+=("$release_dir")
        HOOK_SOURCE_PATH="$release_dir/hooks/protect-important-paths.js"
        info "本機未找到共用 hook，改用最新 Release"
        info "Shared hook not found locally; downloading from latest release"
        download_release_file "$RELEASE_HOOK_ASSET_NAME" "$HOOK_SOURCE_PATH"

        if [ ! -f "$HOOK_SOURCE_PATH" ] || [ ! -r "$HOOK_SOURCE_PATH" ]; then
            error "下載共用 hook 失敗：$HOOK_SOURCE_PATH"
            error "Failed to download shared hook: $HOOK_SOURCE_PATH"
            exit 1
        fi

        require_verified_downloaded_hook "$HOOK_SOURCE_PATH"
    fi
}

resolve_shared_hook_for_settings() {
    local settings_dir
    settings_dir="$(dirname -- "$SETTINGS_PATH")"
    HOOK_PATH="$settings_dir/protect-important-paths.js"

    PENDING_HOOK_REFRESH=false

    if [ ! -f "$HOOK_PATH" ] || [ ! -r "$HOOK_PATH" ]; then
        mkdir -p -- "$(dirname -- "$HOOK_PATH")"
        cp "$HOOK_SOURCE_PATH" "$HOOK_PATH"
        # 第一次安裝同樣要驗。cp 回報成功不代表寫進去的是完整內容：磁碟滿或檔案
        # 系統錯誤會留下 0 byte／截斷的檔案，而那種 hook 以 exit 0、空輸出結束，
        # 在 Claude Code／Copilot 契約下就是「允許一切」。過去只有 refresh 路徑
        # 走 hook_is_trustworthy，第一次安裝完全沒被驗過，等於整條路徑上最沒有
        # 防護的一步就是「全新安裝」。
        # 這裡沒有前一份可以還原，所以驗不過就寫 fail-closed stub 再中止 —— 留下
        # 空檔或乾脆刪掉都一樣是放行（settings 指向不存在的檔案時，PreToolUse 的
        # 非零結束屬於「非阻擋錯誤」，工具照樣執行）。
        # The first install needs the same verification. cp reporting success does
        # not mean the bytes landed: a full disk or a filesystem error leaves a
        # 0-byte or truncated file, and such a hook exits 0 with no output, which
        # the Claude Code and Copilot contracts read as allow-everything. Only the
        # refresh path went through hook_is_trustworthy, so a brand-new install was
        # the least protected step of all.
        # There is no predecessor to restore here, so a failure writes the
        # fail-closed stub and aborts: leaving an empty file — or deleting it — is
        # equally an allow, because a missing hook makes PreToolUse exit non-zero,
        # which is a NON-blocking error and the tool still runs.
        HOOK_PROBE_UNAVAILABLE=false
        if ! hook_is_trustworthy "$HOOK_PATH"; then
            if write_fail_closed_hook_stub "$HOOK_PATH"; then
                error "第一次安裝的共用 hook 無法通過驗證，已改為 fail-closed（拒絕所有工具呼叫）：$HOOK_PATH"
                error "The freshly installed shared hook could not be verified; it now fails closed (every tool call is denied): $HOOK_PATH"
            else
                error "第一次安裝的共用 hook 無法通過驗證，連 fail-closed stub 也寫不進去：$HOOK_PATH 目前的內容可能會放行所有刪除"
                error "The freshly installed shared hook could not be verified and the stub could not be written either; what is at $HOOK_PATH may allow everything"
            fi
            exit 1
        fi
        # 探測本身跑不起來時，hook_is_trustworthy 會退化成「與來源位元組相同」。那
        # 仍抓得到截斷／0 byte 的複製（正是這段防的失敗模式），但抓不到「來源自己
        # 不擋」。refresh 路徑遇到同一情況會明講，第一次安裝卻沉默 —— 於是一台沒有
        # 可用 node 的機器上，安裝看起來像通過了行為驗證，實際上只跑了 cmp。
        # HOOK_PROBE_UNAVAILABLE 在上面被設為 false 卻從未被讀取，就是這個缺口。
        # When the probe itself cannot run, hook_is_trustworthy degrades to
        # "byte-identical to the source". That still catches the truncated or
        # 0-byte copy this block exists to catch, but not a source that fails to
        # deny. The refresh path says so out loud in exactly this situation while
        # the first install stayed silent, so on a machine with no usable node the
        # install looked behaviourally verified when only a cmp had run.
        # HOOK_PROBE_UNAVAILABLE was set to false above and then never read.
        if [ "$HOOK_PROBE_UNAVAILABLE" = true ]; then
            warning "無法執行 hook 自我檢測，已改以位元組比對確認與來源完全相同"
            warning "Could not run the hook self-check; verified byte-identical to the source instead"
        fi
    elif ! cmp -s "$HOOK_SOURCE_PATH" "$HOOK_PATH"; then
        # 保留可讀但過期的 runtime hook，等於讓 hook 的安全修補停在原始碼樹裡，
        # 永遠到不了 agent 實際執行的檔案，因此內容不同時必須更新。
        # 但替換動作要等設定註冊成功之後才做：先換檔再註冊失敗，會留下
        # 「hook 已被換掉、卻沒有任何註冊」的半套安裝。
        # Keeping a readable but stale runtime hook strands hook security fixes
        # in the source checkout. The replacement is deferred until after the
        # settings merge succeeds: replacing first leaves the install
        # half-applied (new file on disk, nothing registered) if the merge
        # aborts.
        if [ -L "$HOOK_PATH" ]; then
            error "拒絕覆蓋符號連結的共用 hook：$HOOK_PATH"
            error "Refusing to replace symbolic link shared hook: $HOOK_PATH"
            exit 1
        fi
        PENDING_HOOK_REFRESH=true
    fi

    if [ ! -f "$HOOK_PATH" ] || [ ! -r "$HOOK_PATH" ]; then
        error "找不到共用 hook：$HOOK_PATH"
        error "Failed to locate shared hook: $HOOK_PATH"
        exit 1
    fi
}

# 註冊成功後才替換過期的 runtime hook（由 main 在 agent 安裝完成後呼叫）
# 實測一份 hook 是否真的會擋下受保護的刪除。
# 只看寫入指令的回傳值不夠：截斷或 0 byte 的 hook 一樣「寫入成功」，執行起來卻是
# exit 0、無輸出，在 Claude Code／Copilot 契約下就是「允許」。
# 三個必要條件缺一不可：
#  1. 每個 payload 都要 deny。只測一個 payload 只能證明「沒被截斷」，證明不了它
#     真的在保護 —— 只擋該 payload、其餘全放行的 hook 也會通過。
#  2. 結束碼必須為 0。印出 deny 卻以 1 結束，在 Claude Code PreToolUse 屬於
#     「非阻擋錯誤」，工具照樣會執行。
#  3. 必須有逾時。卡住不結束的 hook 會讓安裝程式永遠停在這裡（runtime 註冊本身
#     有 timeout: 5，安裝程式以前完全沒有）。
# 界線講清楚：通過只代表「這幾個目標擋得住」，不等於證明所有保護規則都完好。
# Prove a hook really denies protected deletions. A write's exit status is not
# enough: a truncated or 0-byte file writes "successfully" yet runs as exit 0
# with no output, which the Claude Code and Copilot contracts read as allow.
# All three conditions are necessary: every payload must be denied (one payload
# only proves the file is not truncated, not that it protects anything); the
# exit status must be 0 (printing deny while exiting 1 is a NON-blocking error
# for PreToolUse, so the tool still runs); and there must be a timeout (a hook
# that never terminates would hang the installer forever). Passing means these
# targets are denied — it is not proof that every protection rule is intact.
# The payloads are data for the parser and are never executed.
# 內嵌的 JS 全部縮排，讓函式主體中沒有任何一行以 `}` 起始 —— 測試會用
# `sed -n '/^hook_denies_protected_deletion()/,/^}/p'` 把這個函式原封不動抽出來
# 直接測，行首的 `}` 會讓抽取提早結束。
# The embedded JS is indented so that no line inside the body starts with `}`:
# the tests extract this function verbatim with a sed range ending at /^}/ and
# run it directly, which a column-zero brace would truncate.
hook_denies_protected_deletion() {
    node -e '
    const { spawnSync } = require("child_process");
    const hookPath = process.argv[1];
    const commands = [
      "rm -rf /",
      "rm -rf /etc",
      "rm -rf /usr",
      "rmdir /var",
      "rm -rf /project/.git",
    ];
    for (const command of commands) {
      const result = spawnSync(process.execPath, [hookPath], {
        input: JSON.stringify({
          hook_event_name: "PreToolUse",
          tool_name: "Bash",
          tool_input: { command },
          cwd: "/project",
        }),
        encoding: "utf8",
        timeout: 5000,
      });
      if (result.error || result.status !== 0) process.exit(1);
      if (!/"permissionDecision":"deny"/.test(result.stdout)) process.exit(1);
    }
    process.exit(0);
' "$1" 2>/dev/null
}

# 驗證「剛從網路下載回來的」hook，驗不過就中止安裝。
# 為什麼不能沿用 hook_is_trustworthy：那個函式拿 HOOK_SOURCE_PATH 當正對照，而在
# 這裡待驗的檔案「就是」HOOK_SOURCE_PATH —— 自己驗自己，任何壞檔案都會被判成「探
# 測工具壞了」而放行。所以正對照必須另外造：一份必定 deny 的合成 hook 證明探測跑
# 得起來，再加一份必定放行的空檔當負對照，證明探測不是「什麼都說 OK」。
# 為什麼不是 checksum：checksum 檔會走同一條被汙染的通道（captive portal 兩個請求
# 都回 HTML），而且只擋得住位元組層級的意外。行為驗證擋得住同一批情境（HTML 登入
# 頁、截斷的 body、CDN 錯誤頁全都測不出 deny），還多擋一種 checksum 擋不到的：語法
# 正確、但根本不保護任何東西的檔案。
# 驗不過就 exit：此時什麼都還沒註冊、也沒有前一份可以還原，中止是唯一 fail-closed
# 的結果。把來路不明的網路內容裝成 SAFETY hook，比裝不起來危險得多。
# Verify a hook that just came off the network; abort the install if it fails.
# hook_is_trustworthy cannot be reused here: it uses HOOK_SOURCE_PATH as its
# positive control, and here the file under test IS HOOK_SOURCE_PATH, so a bad
# download would be indistinguishable from a broken probe and get accepted. The
# control therefore has to be synthesised — a known-good hook that always denies
# proves the probe runs, and a known-bad empty file proves the probe is not just
# saying yes to everything.
# Why not a checksum: the checksum asset travels the same poisoned channel (a
# captive portal answers both requests with HTML) and only catches byte-level
# accidents. The behavioural probe catches that same set (login page, truncated
# body, CDN error page all fail to deny) plus one a checksum cannot: a
# syntactically valid file that protects nothing.
# Failing means exiting: nothing is registered yet and there is no predecessor to
# fall back to, so aborting is the only fail-closed outcome. Installing
# unverified network content as the SAFETY hook is far worse than not installing.
require_verified_downloaded_hook() {
    local candidate="$1"

    if hook_denies_protected_deletion "$candidate"; then
        return 0
    fi

    local control_good="${candidate}.better-rm-control-good.js"
    local control_bad="${candidate}.better-rm-control-bad.js"
    printf '%s\n' \
        '#!/usr/bin/env node' \
        'process.stdin.resume();' \
        'process.stdin.on("end", () => {' \
        '    process.stdout.write("{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\"}}");' \
        '});' \
        > "$control_good" 2>/dev/null || true
    : > "$control_bad" 2>/dev/null || true

    if hook_denies_protected_deletion "$control_good" &&
       ! hook_denies_protected_deletion "$control_bad"; then
        error "從 Release 下載的 hook 無法擋下受保護的刪除，已中止安裝：$RELEASE_BASE_URL"
        error "The hook downloaded from the release does not block protected deletions; install aborted: $RELEASE_BASE_URL"
        error "下載內容可能被中途攔截（captive portal、CDN 錯誤頁）或不完整；請檢查網路後重試"
        error "The download may have been intercepted (captive portal, CDN error page) or truncated; check the network and retry"
        exit 1
    fi

    error "無法驗證從 Release 下載的 hook：自我檢測本身跑不起來（需要可執行的 node）"
    error "Cannot verify the hook downloaded from the release: the self-check itself could not run (a working node is required)"
    error "未經驗證的網路內容不會被裝成 SAFETY hook，安裝已中止"
    error "Unverified network content is not installed as the SAFETY hook; install aborted"
    exit 1
}

# 判斷磁碟上這份 hook 能不能信任。
# 行為優先；只有在「探測本身壞掉」時才退回位元組比對，而且只承認與已知良好的來源
# 檔完全相同的檔案，絕不承認任何無法驗證的檔案。
# 正對照是關鍵：如果連 HOOK_SOURCE_PATH（剛複製過來的已知良好來源）都測不出
# deny，那壞掉的是探測工具（node 不可用、sandbox 限制…），而不是候選檔案。此時
# 若還「保險起見」把候選檔換成來歷不明的前任，反而會把剛寫好的正確 hook 換成有
# 問題的舊檔 —— 那正是這個函式存在的理由。
# Decide whether the hook on disk can be trusted. Behaviour first; the byte
# comparison is only a fallback for when the PROBE itself is broken, and it
# accepts nothing except a file identical to the known-good source. The positive
# control is the point: if even HOOK_SOURCE_PATH cannot be shown to deny, the
# probe is broken (node unavailable, sandboxing, ...) rather than the candidate,
# and "restoring" an unknown predecessor over a freshly written correct hook
# would be the actual damage.
# 界線：這個機制偵測的是「寫出來的檔案相對於來源被破壞」。如果來源檔本身就是壞的
# hook，正對照同樣測不出 deny，會被判定成「探測工具壞掉」而接受它 —— 來源的正確性
# 由 test-hooks.js 負責，不是安裝程式的職責。
# Limit: this detects CORRUPTION of the written file relative to the source. If
# the source hook is itself bad, the control fails too and that is indistinguishable
# from a broken probe, so it is accepted — validating the source is test-hooks.js's
# job, not the installer's.
hook_is_trustworthy() {
    local candidate="$1"
    if hook_denies_protected_deletion "$candidate"; then
        return 0
    fi
    if hook_denies_protected_deletion "$HOOK_SOURCE_PATH"; then
        # 探測工具正常，所以是候選檔案真的不擋。
        # The probe works, so the candidate genuinely fails to deny.
        return 1
    fi
    HOOK_PROBE_UNAVAILABLE=true
    cmp -s "$HOOK_SOURCE_PATH" "$candidate"
}

# 寫入一個必定 fail-closed 的 stub：沿用本專案既有約定，exit 2 對 Claude Code
# PreToolUse 是「阻擋」，其餘 agent 也只會看到非零結束碼與空 stdout。
# Write a stub that always fails closed. Exit 2 is this project's existing
# convention for a blocking PreToolUse error; other agents see a non-zero exit
# and empty stdout, which is never an allow.
write_fail_closed_hook_stub() {
    printf '%s\n' \
        '#!/usr/bin/env node' \
        '// better-rm: 這個 runtime hook 更新失敗，內容不可信任，因此保持 fail-closed。' \
        '// better-rm: this runtime hook failed to update; it stays fail-closed until restored.' \
        "console.error('better-rm hook 未正確安裝，已拒絕工具呼叫 / better-rm hook is not installed correctly; tool call denied');" \
        'process.exit(2);' \
        > "$1"
}

# Replace a stale runtime hook only after registration succeeded; main calls
# this once the agent installer returned without error.
apply_pending_hook_refresh() {
    [ "${PENDING_HOOK_REFRESH:-false}" = true ] || return 0
    PENDING_HOOK_REFRESH=false

    local backup_path
    backup_path="$HOOK_PATH.better-rm.bak.$(date -u +%Y%m%dT%H%M%SZ)"
    local suffix=1
    while [ -e "$backup_path" ]; do
        backup_path="$HOOK_PATH.better-rm.bak.$(date -u +%Y%m%dT%H%M%SZ).${suffix}"
        suffix=$((suffix + 1))
    done
    # 備份失敗就不能繼續 —— 沒有備份就沒有復原路徑。但也不能只是讓 set -e 中止：
    # 那樣會在「什麼都還沒做」的狀態下離開，而磁碟上留著的是舊 hook。使用者重跑
    # 安裝程式最常見的原因，正是那份舊 hook 已經壞掉（例如舊版 `|| true` 留下的
    # 0 byte 檔案，而磁碟依然是滿的），於是一個放行一切的 hook 就這樣繼續掛著。
    # 因此先判斷舊 hook 可不可信：可信就原封不動留著（不要無謂降級），不可信才換成
    # fail-closed stub。
    # A failed backup means the refresh cannot proceed: without a backup there is
    # no recovery path. Letting set -e abort here is not enough either — that
    # leaves the OLD hook on disk, and the usual reason to re-run the installer
    # is that the old hook is already broken (the 0-byte file left by the earlier
    # `|| true` bug, with the disk still full), so an allow-everything hook would
    # simply stay registered. The old hook is therefore checked: trustworthy, it
    # is left exactly as it is; untrustworthy, it is replaced with the stub.
    if ! cp "$HOOK_PATH" "$backup_path"; then
        error "無法建立備份，因此不更新共用 hook：$backup_path"
        error "Could not create the backup, so the shared hook was not updated: $backup_path"
        if hook_is_trustworthy "$HOOK_PATH"; then
            error "現有的共用 hook 未被更動，仍會擋下受保護的刪除：$HOOK_PATH"
            error "The existing shared hook is untouched and still denies protected deletions: $HOOK_PATH"
        elif write_fail_closed_hook_stub "$HOOK_PATH"; then
            error "現有的共用 hook 無法通過驗證，已改為 fail-closed（拒絕所有工具呼叫）"
            error "The existing shared hook could not be verified; it now fails closed (every tool call is denied)"
        else
            error "現有的共用 hook 無法通過驗證，連 fail-closed stub 也寫不進去：$HOOK_PATH 目前的內容可能會放行所有刪除"
            error "The existing shared hook could not be verified and the stub could not be written either; what is at $HOOK_PATH may allow everything"
        fi
        exit 1
    fi

    # 就地覆寫內容（不換檔）：inode 不變，權限與擁有者自然保留，所以不需要先讀
    # 原本的 mode，也就完全不必用 stat —— stat 的旗標在 BSD 與 GNU userland 並不
    # 相容（GNU 的 `-f` 是「檔案系統狀態」，會把 '%Lp' 當成另一個檔名：stderr 報
    # 錯、結束碼 1，但仍把該檔案的檔案系統資訊印到 stdout；於是 `||` 後援確實會
    # 執行，命令替換卻把「兩段 stdout」一起收下，chmod 就吃到垃圾而失敗）。
    # 註：未經 alias 的 `cp` 覆寫既有檔案時同樣保留目的地的 mode 與 inode，
    # 因此這裡用 cat 只是為了「不需要 mode」這件事更明顯，並非 cp 不可用。
    # Overwrite the content in place: the inode is kept, so mode and owner
    # survive and the original mode never has to be read — which removes the
    # need for stat, whose flags are not portable (GNU `-f` means FILE SYSTEM
    # status and treats '%Lp' as another operand: it errors on stderr and exits
    # 1 but still prints that file's filesystem info on stdout, so the `||`
    # fallback does run and the command substitution captures BOTH outputs,
    # feeding chmod garbage).
    # Note: an unaliased `cp` onto an existing file preserves the destination's
    # mode and inode just the same. cat is used here only to make "no mode is
    # needed" obvious, not because cp is unusable.
    HOOK_PROBE_UNAVAILABLE=false
    if cat "$HOOK_SOURCE_PATH" > "$HOOK_PATH" && hook_is_trustworthy "$HOOK_PATH"; then
        if [ "$HOOK_PROBE_UNAVAILABLE" = true ]; then
            warning "無法執行 hook 自我檢測，已改以位元組比對確認與來源完全相同"
            warning "Could not run the hook self-check; verified byte-identical to the source instead"
        fi
        success "已更新共用 hook：$HOOK_PATH"
        success "Updated shared hook: $HOOK_PATH"
        info "備份檔案 / Backup: $backup_path"
        return 0
    fi

    # 寫入可能只完成一半。截斷或 0 byte 的 hook 會以 exit 0、空輸出結束，在 Claude
    # Code／Copilot 契約下就是「允許」——防護等於被完全解除，比原本那份過期的
    # hook 還危險。因此「還原」同樣要驗行為，不能只用 cmp：cmp 只證明位元組等於
    # 備份，證明不了那份備份曾經是能用的 hook。舊版 `|| true` 留下 0 byte 檔案後、
    # 使用者再跑一次安裝想修好它，就正是這個情境。
    # The write may have half-completed. A truncated or 0-byte hook exits 0 with
    # no output, which the Claude Code and Copilot contracts read as ALLOW: the
    # guard would be fully disarmed, which is worse than the stale hook it
    # replaced. The restore is therefore verified by BEHAVIOUR, not by cmp alone
    # — cmp only proves the bytes match the backup, never that the backup was a
    # working hook. Re-running the installer to repair the 0-byte file left by
    # the earlier `|| true` bug is exactly that case.
    if cat "$backup_path" > "$HOOK_PATH" 2>/dev/null \
        && cmp -s "$backup_path" "$HOOK_PATH" \
        && hook_is_trustworthy "$HOOK_PATH"; then
        error "更新共用 hook 失敗，已還原並驗證原本的檔案：$HOOK_PATH"
        error "Failed to update shared hook; restored and verified the previous file: $HOOK_PATH"
        exit 1
    fi

    # 走到這裡表示：新檔案不可信，前一份也不可信（或根本還原不了）。磁碟上的東西
    # 可能是截斷的，也就是「全部允許」。寧可留下一個必定阻擋的 stub，也不要留下一
    # 個什麼都不擋的檔案。用 shell 內建的 printf 寫入，才不會再依賴剛失敗的外部
    # 工具。代價要講明白：stub 在位時，claude 的 matcher 是 Bash，所以每個 Bash
    # 呼叫都會被擋（Read/Write/Edit 仍可用）；cursor 的 matcher 是 `.*`，會擋下
    # 所有工具。重跑安裝程式即可復原，但這確實是一個硬停點。
    # Neither the new file nor the predecessor can be trusted (or the restore
    # itself failed). What is on disk may be truncated, i.e. allow-everything.
    # A stub that blocks everything is strictly safer than a file that blocks
    # nothing; printf is a builtin so it does not depend on the tool that just
    # failed. The cost, stated plainly: while the stub is in place every Bash
    # call is refused under the claude matcher (Read/Write/Edit still work), and
    # cursor's matcher is `.*`, so EVERY tool is refused there. Re-running the
    # installer recovers it, but it is a hard stop until then.
    # 訊息必須跟著 stub 是否真的寫成功而分歧：stub 寫失敗時磁碟上留下的是未經驗證
    # 的舊內容（可能放行一切），此時再印「已改為 fail-closed」就是騙人。
    # The message has to branch on whether the stub was actually written: if it
    # was not, what remains on disk is the unverified predecessor, which may
    # allow everything — claiming "it now fails closed" there would be a lie.
    if write_fail_closed_hook_stub "$HOOK_PATH"; then
        error "共用 hook 無法更新，前一份也無法驗證，已改為 fail-closed（拒絕所有工具呼叫）"
        error "The shared hook could not be updated and the previous one could not be verified; it now fails closed (every tool call is denied)"
    else
        error "共用 hook 無法更新，連 fail-closed stub 也寫不進去：$HOOK_PATH 目前的內容未經驗證，可能會放行所有刪除"
        error "The shared hook could not be updated and the fail-closed stub could not be written either; what is at $HOOK_PATH is unverified and may allow everything"
    fi
    error "請從備份還原 / Restore it from the backup: $backup_path"
    exit 1
}

# 取得專案根目錄（所有支援的 JSON 設定預設放在專案 root）
# Resolve project root for JSON-style agent settings
resolve_project_root() {
    if ! command_exists git; then
        error "找不到 git 命令 / git command not found"
        exit 1
    fi

    local project_root
    if ! project_root=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null); then
        error "目前目錄不在 Git 儲存庫中 / Current directory is not inside a Git repository"
        exit 1
    fi
    printf '%s' "$project_root"
}

# 取得 Claude Code 設定檔位置 (Resolve Claude Code settings path)
resolve_claude_settings() {
    if [ "$GLOBAL_INSTALL" = true ]; then
        local config_dir="${CLAUDE_CONFIG_DIR:-}"
        if [ -z "$config_dir" ]; then
            if [ -z "${HOME:-}" ]; then
                error "找不到 HOME 或 CLAUDE_CONFIG_DIR / HOME or CLAUDE_CONFIG_DIR is required"
                exit 1
            fi
            config_dir="$HOME/.claude"
        fi
        SETTINGS_PATH="$config_dir/settings.json"
        SCOPE="global"
    else
        local project_root
        project_root="$(resolve_project_root)"
        SETTINGS_PATH="$project_root/.claude/settings.json"
        SCOPE="project"
    fi
}

# 取得 Codex 設定檔位置 (Resolve Codex settings path)
resolve_codex_settings() {
    if [ "$GLOBAL_INSTALL" = true ]; then
        error "Codex 不支援 --global，請移除該參數 / Codex does not support --global; remove this flag"
        exit 2
    fi

    local project_root
    project_root="$(resolve_project_root)"
    SETTINGS_PATH="$project_root/.codex/hooks.json"
    SCOPE="project"
}

# 取得 Cursor 設定檔位置 (Resolve Cursor settings path)
resolve_cursor_settings() {
    if [ "$GLOBAL_INSTALL" = true ]; then
        error "Cursor 不支援 --global，請移除該參數 / Cursor does not support --global; remove this flag"
        exit 2
    fi

    local project_root
    project_root="$(resolve_project_root)"
    SETTINGS_PATH="$project_root/.cursor/hooks.json"
    SCOPE="project"
}

# 取得 GitHub Copilot 設定檔位置 (Resolve GitHub Copilot settings path)
resolve_copilot_settings() {
    if [ "$GLOBAL_INSTALL" = true ]; then
        error "GitHub Copilot 不支援 --global，請移除該參數 / GitHub Copilot does not support --global; remove this flag"
        exit 2
    fi

    local project_root
    project_root="$(resolve_project_root)"
    SETTINGS_PATH="$project_root/.github/hooks/better-rm.json"
    SCOPE="project"
}

# 取得 Antigravity 設定檔位置 (Resolve Antigravity settings path)
resolve_antigravity_settings() {
    if [ "$GLOBAL_INSTALL" = true ]; then
        error "Antigravity 不支援 --global，請移除該參數 / Antigravity does not support --global; remove this flag"
        exit 2
    fi

    local project_root
    project_root="$(resolve_project_root)"
    SETTINGS_PATH="$project_root/.agents/hooks.json"
    SCOPE="project"
}

# 取得 Qoder 設定檔位置 (Resolve Qoder settings path)
resolve_qoder_settings() {
    if [ "$GLOBAL_INSTALL" = true ]; then
        error "Qoder 不支援 --global，請移除該參數 / Qoder does not support --global; remove this flag"
        exit 2
    fi

    local project_root
    project_root="$(resolve_project_root)"
    SETTINGS_PATH="$project_root/.qoder/settings.json"
    SCOPE="project"
}

# 取得 Pi JSON 設定檔位置 (Resolve Pi settings path)
resolve_pi_settings() {
    if [ "$GLOBAL_INSTALL" = true ]; then
        error "Pi 不支援 --global，請移除該參數 / Pi does not support --global; remove this flag"
        exit 2
    fi

    local project_root
    project_root="$(resolve_project_root)"
    SETTINGS_PATH="$project_root/.pi/hooks.json"
    SCOPE="project"
}

# 取得 Grok Build 設定檔位置 (Resolve Grok settings path)
resolve_grok_settings() {
    if [ "$GLOBAL_INSTALL" = true ]; then
        error "Grok Build 不支援 --global，請移除該參數 / Grok Build does not support --global; remove this flag"
        exit 2
    fi

    local project_root
    project_root="$(resolve_project_root)"
    SETTINGS_PATH="$project_root/.grok/hooks/better-rm.json"
    SCOPE="project"
}

# 寫出隨安裝程式一起出貨的 OpenCode 外掛。
# 為什麼要內嵌，而不是像 runtime hook 那樣「下載完再驗」：外掛是 TypeScript，要驗
# 它「真的會註冊 hook 並擋下刪除」就得有 TypeScript runtime（bun 或 OpenCode 本
# 身），而安裝程式在其他任何路徑上都不需要那種東西；為了驗一個檔案而讓「本來裝得
# 起來的機器」開始裝不起來，是把一個安靜的漏洞換成一個大聲的迴歸。
# 只做字串嗅探（找 "tool.execute.before" 之類）則更糟：它擋得住 HTML 登入頁，卻擋
# 不住「語法正確、export 名稱一樣、就是不註冊 hook」的內容，而那正是最危險的一種
# ——看起來像檢查，實際上不是。
# 所以改成拆掉那條通道本身：外掛與安裝程式屬於同一份可信發佈物。使用者執行這個
# 檔案的時候就已經信任它的內容了，外掛跟著它走，網路上再也沒有東西能變成外掛。
# 代價是這份內嵌副本必須跟 .opencode/plugins/protect-important-paths.ts 保持一致；
# test-install-hooks.sh 用「發佈物裡沒有 .opencode 時裝出來的外掛必須與該檔完全相
# 同」把這件事釘住，不一致就紅。
# Write the OpenCode plugin that ships with this installer.
# Why bundle instead of verifying a download the way the runtime hook does: the
# plugin is TypeScript, and proving it really registers a hook and blocks a
# deletion needs a TypeScript runtime (bun, or OpenCode itself) that no other
# installer path requires. Making machines that could install stop installing, in
# order to check one file, trades a silent hole for a loud regression.
# A string sniff (grep for "tool.execute.before" and friends) would be worse: it
# stops an HTML login page but not syntactically valid TypeScript that exports the
# same names and registers nothing — the most dangerous shape, and the one that
# makes the check look real when it is not.
# So the channel itself is removed: the plugin and the installer are one trusted
# distribution. Running this file already means trusting its contents, the plugin
# rides along, and nothing on the network can become the plugin any more.
# The cost is that this copy has to track
# .opencode/plugins/protect-important-paths.ts; test-install-hooks.sh pins that by
# asserting the plugin installed from a distribution without .opencode is
# byte-identical to that file, so drift turns the suite red.
# 與 write_fail_closed_hook_stub 相同的內嵌寫法：每一行都縮排，函式主體中沒有任何
# 一行以 `}` 起始，測試若以 `sed -n '/^name()/,/^}/p'` 抽取也不會被截斷。
# Same embedding style as write_fail_closed_hook_stub: every line is indented so no
# line in the body starts with `}`, which a sed extraction ending at /^}/ would
# otherwise truncate.
write_bundled_opencode_plugin() {
    local destination="$1"

    mkdir -p -- "$(dirname -- "$destination")" || return 1
    printf '%s\n' \
        'import type { Plugin } from "@opencode-ai/plugin";' \
        '// @ts-ignore' \
        'import { evaluate } from "../../hooks/protect-important-paths";' \
        '' \
        'export const ProtectImportantPathsPlugin: Plugin = async (ctx) => {' \
        '  return {' \
        '    "tool.execute.before": async (input, output) => {' \
        '      if (input.tool === "bash") {' \
        '        const command = output.args.command;' \
        '        const cwd = (ctx as any)?.directory || process.cwd();' \
        '' \
        '        const payload = {' \
        '          tool_input: { command },' \
        '          cwd' \
        '        };' \
        '' \
        '        const result = evaluate(payload);' \
        '        if (result && result.hookSpecificOutput?.permissionDecision === "deny") {' \
        '          throw new Error(result.hookSpecificOutput.permissionDecisionReason);' \
        '        }' \
        '      }' \
        '    },' \
        '  };' \
        '};' \
        '' \
        'export default ProtectImportantPathsPlugin;' \
        > "$destination"
}

# 取得 OpenCode 外掛檔案位置 (Resolve OpenCode plugin path)
resolve_opencode_plugin() {
    if [ "$GLOBAL_INSTALL" = true ]; then
        error "OpenCode 不支援 --global，請移除該參數 / OpenCode does not support --global; remove this flag"
        exit 2
    fi

    local project_root
    project_root="$(resolve_project_root)"
    # 容器的實體根目錄，供 require_opencode_destination_within_root 當錨點。
    # The physical root, used as the containment anchor for the destinations.
    if ! OPENCODE_PROJECT_ROOT="$(cd -- "$project_root" 2>/dev/null && pwd -P)"; then
        error "無法解析專案根目錄的實體路徑：$project_root"
        error "Cannot resolve the physical path of the project root: $project_root"
        exit 1
    fi
    PLUGIN_SOURCE_PATH="$SCRIPT_DIR/.opencode/plugins/protect-important-paths.ts"
    if [ ! -f "$PLUGIN_SOURCE_PATH" ] || [ ! -r "$PLUGIN_SOURCE_PATH" ]; then
        local plugin_bundle_dir
        plugin_bundle_dir="$(mktemp -d)"
        CLEANUP_DIRS+=("$plugin_bundle_dir")
        PLUGIN_SOURCE_PATH="$plugin_bundle_dir/.opencode/plugins/protect-important-paths.ts"
    fi
    PLUGIN_PATH="$project_root/.opencode/plugins/protect-important-paths.ts"
    OPENCODE_RUNTIME_SOURCE_PATH="$HOOK_SOURCE_PATH"
    OPENCODE_RUNTIME_PATH="$project_root/hooks/protect-important-paths.js"

    if [ ! -f "$PLUGIN_SOURCE_PATH" ] || [ ! -r "$PLUGIN_SOURCE_PATH" ]; then
        # `if !` 是刻意的：set -e 會讓寫檔失敗直接中止，什麼訊息都不印，而這條路徑
        # 上使用者需要知道停在哪裡。
        # The `if !` is deliberate: under set -e a failed write would abort with no
        # message at all, and this path is one the user has to be able to act on.
        if ! write_bundled_opencode_plugin "$PLUGIN_SOURCE_PATH"; then
            error "無法寫出隨安裝程式內附的 OpenCode 外掛：$PLUGIN_SOURCE_PATH"
            error "Failed to write the bundled OpenCode plugin: $PLUGIN_SOURCE_PATH"
            exit 1
        fi
    fi

    if [ ! -f "$PLUGIN_SOURCE_PATH" ] || [ ! -r "$PLUGIN_SOURCE_PATH" ]; then
        error "找不到 OpenCode 外掛來源：$PLUGIN_SOURCE_PATH"
        error "OpenCode plugin source not found or unreadable: $PLUGIN_SOURCE_PATH"
        exit 1
    fi

    if [ ! -f "$OPENCODE_RUNTIME_SOURCE_PATH" ] || [ ! -r "$OPENCODE_RUNTIME_SOURCE_PATH" ]; then
        download_release_file "$RELEASE_HOOK_ASSET_NAME" "$OPENCODE_RUNTIME_SOURCE_PATH"
    fi

    if [ ! -f "$OPENCODE_RUNTIME_SOURCE_PATH" ] || [ ! -r "$OPENCODE_RUNTIME_SOURCE_PATH" ]; then
        error "找不到 OpenCode 共享 hook 來源：$OPENCODE_RUNTIME_SOURCE_PATH"
        error "OpenCode runtime hook source not found or unreadable: $OPENCODE_RUNTIME_SOURCE_PATH"
        exit 1
    fi
}

# 確保 OpenCode 安裝目標是一般檔案或不存在（不跟隨符號連結）
# Require an OpenCode installation target to be a regular file or absent.
validate_opencode_destination() {
    local path="$1"
    local name_zh="$2"
    local name_en="$3"

    if [ -L "$path" ]; then
        error "拒絕覆蓋符號連結${name_zh}：$path"
        error "Refusing to replace symbolic link ${name_en}: $path"
        exit 1
    fi

    if [ -e "$path" ] && [ ! -f "$path" ]; then
        error "OpenCode ${name_zh}路徑不是一般檔案：$path"
        error "OpenCode ${name_en} path is not a regular file: $path"
        exit 1
    fi
}

# 解析一條路徑的實體位置（跟隨所有既存祖先目錄的符號連結），但不建立任何目錄。
# 為什麼不用 realpath：BSD 與 GNU 的可用性與旗標不一致，這支安裝程式要能在乾淨的
# macOS 上跑。逐層往上找到第一個存在的祖先，用 `cd -- ... && pwd -P` 取其實體路徑，
# 再把還不存在的層級接回去。
# Resolve a path physically (following symlinks on every existing ancestor)
# without creating anything. realpath is deliberately not used: its
# availability and flags differ between BSD and GNU userland and this
# installer has to run on a stock macOS. Walk up to the first existing
# ancestor, take its physical path, then re-append the missing components.
physical_path() {
    local path="$1"
    local suffix=""
    local base parent

    while [ ! -e "$path" ]; do
        base="$(basename -- "$path")"
        parent="$(dirname -- "$path")"
        if [ "$parent" = "$path" ]; then
            printf '%s' "$path"
            return 0
        fi
        if [ -n "$suffix" ]; then
            suffix="$base/$suffix"
        else
            suffix="$base"
        fi
        path="$parent"
    done

    local resolved
    if [ -d "$path" ]; then
        resolved="$(cd -- "$path" 2>/dev/null && pwd -P)" || return 1
    else
        parent="$(dirname -- "$path")"
        base="$(basename -- "$path")"
        parent="$(cd -- "$parent" 2>/dev/null && pwd -P)" || return 1
        resolved="${parent%/}/$base"
    fi

    if [ -n "$suffix" ]; then
        printf '%s' "${resolved%/}/$suffix"
    else
        printf '%s' "$resolved"
    fi
}

# 確認 OpenCode 安裝目標的實體路徑仍在實體專案根目錄內。
# 為什麼 validate_opencode_destination 不夠：它只看最後一層是不是符號連結，而
# `.opencode/plugins` 或 `hooks` 這種祖先目錄若本身是連結，最後一層根本還不存在，
# 檢查就過了，接著 `mkdir -p` 穿過連結、`cp` 把宣稱 project-scoped 的檔案寫到專案外
# 並以 exit 0 收場（實測會在 root 外產出 plugin 與 runtime 兩個檔案）。
# Require an OpenCode destination to resolve inside the physical project root.
# validate_opencode_destination is not enough on its own: it only inspects the
# final component, and when an ancestor such as `.opencode/plugins` or `hooks`
# is itself a symlink the final component does not exist yet, so the check
# passes, `mkdir -p` then traverses the link and `cp` writes a supposedly
# project-scoped file outside the project -- exiting 0 while doing it.
require_opencode_destination_within_root() {
    local path="$1"
    local root="$2"
    local name_zh="$3"
    local name_en="$4"

    local resolved
    if ! resolved="$(physical_path "$path")"; then
        error "無法解析 OpenCode ${name_zh}的實體路徑：$path"
        error "Cannot resolve the physical path of the OpenCode ${name_en}: $path"
        exit 1
    fi

    case "$resolved" in
        "$root"/*) ;;
        *)
            error "拒絕在專案根目錄外寫入 OpenCode ${name_zh}：$path"
            error "Refusing to write the OpenCode ${name_en} outside the project root: $path"
            error "實體路徑 / physical path: $resolved"
            error "專案根目錄 / project root: $root"
            exit 1
            ;;
    esac
}

# 驗證剛寫到 OpenCode 執行位置的共用 runtime hook。
# 為什麼 opencode 需要自己一份：其他八個 agent 都走 resolve_shared_hook_for_settings，
# 第一次安裝會經過 hook_is_trustworthy，驗不過就寫 fail-closed stub 並中止；
# install_opencode_hooks 不經過那個函式，於是這條路徑上只有一個裸 `cp`。實測（`cp`
# 回報成功卻沒寫入任何內容）：claude／codex／cursor／grok 全部 exit 1 並留下 stub，
# opencode 是 exit 0 加一個 0 位元組的 runtime hook —— 而 0 位元組的 hook 以 exit 0
# 與空輸出結束，在契約上就是「放行一切」。這支工具存在的理由就是防刪，所以那是必須
# 關掉的洞，不是可以只寫進文件的殘留。
# 這裡沒有引入新的執行環境需求：hook_is_trustworthy 在探測跑不起來時會退回
# 「與來源位元組相同」，而 OPENCODE_RUNTIME_SOURCE_PATH 就是 HOOK_SOURCE_PATH，
# 所以沒有 node 的機器照樣裝得起來，只是改用 cmp 驗——正常安裝不會被這道檢查否決。
# Verify the shared runtime hook just written to OpenCode's executing location.
# Why opencode needs its own: the other eight agents go through
# resolve_shared_hook_for_settings, whose first install runs hook_is_trustworthy and
# writes the fail-closed stub before aborting on failure. install_opencode_hooks
# does not call that function, so this path had a bare cp and nothing else.
# Measured with a cp that reports success while writing nothing:
# claude/codex/cursor/grok all exit 1 and leave the stub, opencode exited 0 with a
# 0-byte runtime hook — and a 0-byte hook exits 0 with no output, which the contract
# reads as allow-everything. Blocking deletions is what this tool is for, so that is
# a hole to close, not a residual to write down.
# No new runtime requirement is introduced: when the probe cannot run,
# hook_is_trustworthy degrades to "byte-identical to the source", and
# OPENCODE_RUNTIME_SOURCE_PATH is HOOK_SOURCE_PATH, so a machine without node still
# installs — verified by cmp instead. A healthy install is never denied by this.
require_verified_opencode_runtime() {
    local backup_path="${1:-}"

    # 目的地不存在＝位元組沒落地的直接證據，而且缺席的 hook 在契約上就是「放行一切」
    # （PreToolUse 找不到檔案會以非零結束，那是「非阻擋錯誤」，工具照跑）。這個情況
    # 一定會走到下面的 fail-closed stub 並 exit 1：node 正常時 hook_is_trustworthy
    # 會直接判否；node 不在時則由下面那個 `-f` 條件擋住「無法驗證就放行」那條路。
    # 這裡先把真正的原因說出來，否則使用者只會看到含糊的「無法通過驗證」。
    # A missing destination is direct evidence the bytes did not land, and an absent
    # hook is allow-everything under the contract (PreToolUse exits non-zero when the
    # file is missing, which is a NON-blocking error, so the tool still runs). This
    # case always reaches the fail-closed stub and exit 1 below: with node working
    # hook_is_trustworthy rejects it outright, and with node absent the `-f` conjunct
    # below blocks the "cannot verify, so proceed" path.
    # Naming the real cause here matters — otherwise the user only sees a vague
    # "could not be verified".
    if [ ! -f "$OPENCODE_RUNTIME_PATH" ]; then
        error "OpenCode 共用 hook 沒有出現在執行位置：複製回報成功卻沒有寫出任何東西：$OPENCODE_RUNTIME_PATH"
        error "The OpenCode runtime hook is not at its executing location: the copy reported success but wrote nothing: $OPENCODE_RUNTIME_PATH"
    fi

    HOOK_PROBE_UNAVAILABLE=false
    if hook_is_trustworthy "$OPENCODE_RUNTIME_PATH"; then
        if [ "$HOOK_PROBE_UNAVAILABLE" = true ]; then
            warning "無法執行 hook 自我檢測，已改以位元組比對確認與來源完全相同"
            warning "Could not run the hook self-check; verified byte-identical to the source instead"
        fi
        return 0
    fi

    # 這裡有兩個驗證器：行為探測（需要 node）與位元比對（需要 cmp）。走到這一行代表
    # 兩者合起來沒有給出「可信」，但那有兩種截然不同的原因，必須分開處理：
    #   探測跑得起來、說它不擋            → 有證據，fail-closed。
    #   探測跑不起來，cmp 說位元不同      → 有證據，fail-closed。
    #   探測跑不起來，cmp 也跑不起來      → 沒有任何證據，只是量不到。
    # 第三種若也中止，就是拿「無法測量」當成「測到壞掉」：一台本來裝得起來的機器
    # 變成裝不起來，還留下一個擋掉 OpenCode 每個指令的 stub。opencode 是唯一會走到
    # 這個問題的 agent（其他八個都要用 node 合併 JSON，沒有 node 根本到不了這裡），
    # 所以這不是與誰一致的問題，而是不要製造一個沒有證據的失敗。
    # 只在第三種放行，而且要大聲說出來——這與外掛守衛對 cmp 三態的處理是同一套規則。
    # There are two verifiers here: the behavioural probe (needs node) and the byte
    # comparison (needs cmp). Reaching this line means they did not jointly say
    # "trustworthy", but that has two very different causes and they must be split:
    #   probe ran and says it does not deny        -> evidence, fail closed.
    #   probe unavailable, cmp says bytes differ   -> evidence, fail closed.
    #   probe unavailable and cmp cannot run       -> no evidence, just no measurement.
    # Aborting on the third treats "could not measure" as "measured bad": a machine
    # that used to install stops installing and is left with a stub that blocks every
    # command under OpenCode. opencode is the only agent that gets this far (the
    # other eight need node to merge their JSON settings), so this is not about
    # matching them — it is about not manufacturing an evidence-free failure.
    # Accept only in the third case, and say so out loud. Same rule the plugin guard
    # applies to cmp's tri-state.
    if [ "$HOOK_PROBE_UNAVAILABLE" = true ]; then
        local compare_status=0
        cmp -s "$OPENCODE_RUNTIME_SOURCE_PATH" "$OPENCODE_RUNTIME_PATH" || compare_status=$?
        # `-f` 是關鍵的合取項：cmp 對「不存在的運算元」同樣回 2，少了它，一個什麼都
        # 沒建立的複製會被當成「量不到」而放行。
        # The `-f` conjunct is essential: cmp also returns 2 for a missing operand, and
        # without it a copy that created nothing would be waved through as unmeasurable.
        if [ "$compare_status" -ge 2 ] && [ -f "$OPENCODE_RUNTIME_PATH" ]; then
            warning "無法驗證 OpenCode 共用 hook：自我檢測與位元比對都無法執行，已在未驗證的情況下繼續：$OPENCODE_RUNTIME_PATH"
            warning "Could not verify the OpenCode runtime hook: neither the self-check nor the byte comparison could run; continuing unverified: $OPENCODE_RUNTIME_PATH"
            warning "安裝可用的 node 或 cmp 後重跑安裝程式，即可取得驗證"
            warning "Install a working node or cmp and re-run the installer to get it verified"
            return 0
        fi
    fi

    # 訊息必須跟著 stub 是否真的寫成功而分歧：stub 寫失敗時磁碟上留下的是未經驗證
    # 的內容（可能放行一切），此時再印「已改為 fail-closed」就是騙人。
    # The message branches on whether the stub was actually written: if it was not,
    # what remains on disk is unverified and may allow everything, and claiming "it
    # now fails closed" there would be a lie.
    if write_fail_closed_hook_stub "$OPENCODE_RUNTIME_PATH"; then
        error "OpenCode 共用 hook 無法通過驗證，已改為 fail-closed（拒絕所有工具呼叫）：$OPENCODE_RUNTIME_PATH"
        error "The OpenCode runtime hook could not be verified; it now fails closed (every tool call is denied): $OPENCODE_RUNTIME_PATH"
    else
        error "OpenCode 共用 hook 無法通過驗證，連 fail-closed stub 也寫不進去：$OPENCODE_RUNTIME_PATH 目前的內容可能會放行所有刪除"
        error "The OpenCode runtime hook could not be verified and the fail-closed stub could not be written either; what is at $OPENCODE_RUNTIME_PATH may allow everything"
    fi
    if [ -n "$backup_path" ]; then
        error "請從備份還原 / Restore it from the backup: $backup_path"
    fi
    exit 1
}

# 驗證剛寫到 OpenCode 執行位置的外掛確實與來源相同。
# 外掛是 TypeScript，行為探測需要安裝程式並不要求的 TypeScript runtime，所以這裡驗
# 的是「複製有沒有忠實落地」而不是「它有沒有保護作用」—— 來源本身的正確性由內嵌副本
# 的 byte-identity 測試釘住。`cp` 的結束碼證明不了位元組落地，這一行才證明得了。
# 界線講明白：驗不過就中止，但不會像 runtime hook 那樣留下 fail-closed 的替代品，
# 因為那需要另造一份 TypeScript stub；磁碟上留下的是那份寫壞的外掛，訊息會說出來，
# 使用者重跑安裝程式即可。
# Verify the plugin just written to OpenCode's executing location matches its source.
# The plugin is TypeScript and a behavioural probe would need a TypeScript runtime
# the installer does not require, so what is checked is whether the copy landed
# faithfully, not whether it protects anything — the source's own correctness is
# pinned by the bundled copy's byte-identity test. cp's exit status cannot prove the
# bytes landed; this comparison can.
# Stated limit: a failure aborts but does NOT leave a fail-closed replacement the way
# the runtime hook does, because that would need a separate TypeScript stub. What
# stays on disk is the bad copy, the message says so, and re-running the installer
# repairs it.
require_faithful_opencode_plugin() {
    # cmp 的結束碼是三態，不是布林：0＝相同、1＝內容不同、>=2＝比對本身跑不起來
    # （cmp 不存在、檔案讀不到…）。把 >=2 也當成「不同」，就是拿一個從未發生的診斷
    # 去中止一次完全健康的安裝——實測（PATH 上放一個 exit 127 的 cmp）：外掛位元完美
    # 地落地了，安裝卻中止、runtime hook 從此沒被裝上，訊息還說「可能只寫了一半」。
    # hook_is_trustworthy 用「正向控制」處理同一個問題（分不出候選檔壞掉與探針壞掉
    # 就會誤判）；外掛這側沒有等價機制，所以只能靠 cmp 自己的結束碼把兩者分開。
    # 「跑不起來」時的正確行為是退回未驗證並說實話，而不是宣稱不符：這條路徑上沒有
    # 任何證據指向外掛有問題，中止只會製造一個假的失敗。
    # cmp's exit status is tri-state, not boolean: 0 identical, 1 contents differ,
    # >=2 the comparison itself could not run (no cmp on the machine, unreadable
    # file, ...). Treating >=2 as "different" aborts a perfectly healthy install with
    # a diagnosis that never happened — measured with an `exit 127` cmp on PATH: the
    # plugin landed byte-perfect, the install aborted anyway, the runtime hook was
    # never installed, and the message claimed a partial copy.
    # hook_is_trustworthy solves the same problem with a positive control (failing to
    # separate "the candidate is bad" from "the probe is broken" produces exactly
    # this misdiagnosis); the plugin side has no equivalent, so cmp's own exit status
    # is the only thing that can tell the two apart.
    # When it cannot run, the correct behaviour is to degrade to unverified and say
    # so, not to assert a mismatch: nothing on this path is evidence against the
    # plugin, and aborting would manufacture a failure.
    # 先確認目的地存在，再談比對。cmp 的 exit 2 有兩個成因，其中一個正是這個守衛存在
    # 的理由：運算元不存在。一個回報成功卻什麼都沒建立的 cp，會讓
    # `cmp -s 來源 <不存在>` 回傳 2，若把它讀成「比對工具跑不起來」就會放行 ——
    # 安裝印出「Created OpenCode plugin」、exit 0，磁碟上卻沒有外掛。
    # 這裡不靠窮舉「哪些狀況會讓 cmp 回 2」：目的地不存在本身就是「位元組沒落地」的
    # 直接證據，與任何比對工具是否可用無關。
    # Establish the destination exists before comparing anything. cmp's exit 2 has two
    # causes and one of them is the very thing this guard exists to catch: a missing
    # operand. A cp that reports success while creating nothing makes
    # `cmp -s source <missing>` return 2, and reading that as "the comparison tool
    # could not run" lets it through — the install prints "Created OpenCode plugin",
    # exits 0, and there is no plugin on disk.
    # This does not enumerate what makes cmp return 2: a missing destination is itself
    # direct evidence the bytes did not land, whatever tooling is available.
    if [ ! -f "$PLUGIN_PATH" ]; then
        error "OpenCode 外掛沒有出現在執行位置：複製回報成功卻沒有寫出任何東西：$PLUGIN_PATH"
        error "The OpenCode plugin is not at its executing location: the copy reported success but wrote nothing: $PLUGIN_PATH"
        error "磁碟上沒有外掛，OpenCode 底下就沒有任何保護；請重新執行安裝程式"
        error "With no plugin on disk OpenCode has no protection at all; re-run the installer"
        exit 1
    fi

    local status=0
    cmp -s "$PLUGIN_SOURCE_PATH" "$PLUGIN_PATH" || status=$?

    if [ "$status" -eq 0 ]; then
        return 0
    fi

    if [ "$status" -ge 2 ]; then
        warning "無法驗證 OpenCode 外掛的複製結果（比對工具無法執行），已在未驗證的情況下繼續：$PLUGIN_PATH"
        warning "Could not verify the OpenCode plugin copy (the comparison tool could not run); continuing unverified: $PLUGIN_PATH"
        return 0
    fi

    error "OpenCode 外掛寫入後與來源不符，可能只寫了一半：$PLUGIN_PATH"
    error "The OpenCode plugin does not match its source after the write; it may be a partial copy: $PLUGIN_PATH"
    error "磁碟上的外掛不可信任，且不會自動修復；請重新執行安裝程式"
    error "The plugin on disk is not trustworthy and is not repaired automatically; re-run the installer"
    exit 1
}

# 以 Node.js 安全合併 JSON hook 設定
# Safely merge JSON hook settings with Node.js
merge_json_settings() {
    node - "$SETTINGS_PATH" "$HOOK_PATH" "$SCOPE" <<'NODE'
'use strict';

const fs = require('fs');
const path = require('path');

const settingsPath = process.argv[2];
const hookPath = process.argv[3];
const scope = process.argv[4];
const hookTarget = process.env.HOOK_TARGET || 'claude';

function fail(message) {
  console.error(message);
  process.exit(1);
}

function isObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function shellQuote(value) {
  return `'${value.replace(/'/g, "'\\''")}'`;
}

function powershellQuote(value) {
  return `"${value.replace(/\\/g, '\\\\').replace(/"/g, '\\"') }"`;
}

function sameJson(left, right) {
  return JSON.stringify(left) === JSON.stringify(right);
}

function isOwnedCommandHook(value) {
  return isObject(value)
    && typeof value.command === 'string'
    && /(?:^|[\\/\"'\s])protect-important-paths\.js(?:['"\s]|$)/.test(value.command);
}

function isOwnedCursorHook(value) {
  return isObject(value)
    && typeof value.command === 'string'
    && /(?:^|[\\/\"'\s])protect-important-paths\.js(?:['"\s]|$)/.test(value.command);
}

function isOwnedPreToolHook(value) {
  return isObject(value)
    && value.type === 'command'
    && isOwnedCommandHook(value);
}

function isOwnedCopilotHook(value) {
  return isObject(value)
    && value.matcher === 'bash|powershell'
    && ((typeof value.bash === 'string' && isOwnedCommandHook({ command: value.bash }))
      || (typeof value.powershell === 'string' && isOwnedCommandHook({ command: value.powershell })));
}

const nodeCommand = `node ${shellQuote(hookPath)}`;
const nodePowershellCommand = `node ${powershellQuote(hookPath)}`;
const statusMessage = 'Checking protected directories...';

const cursorDesiredHook = {
  command: nodeCommand,
  matcher: '.*'
};

const claudeDesiredHook = {
  type: 'command',
  command: nodeCommand,
  timeout: 5,
  statusMessage
};

const copilotDesiredHook = {
  type: 'command',
  bash: nodeCommand,
  powershell: nodePowershellCommand,
  matcher: 'bash|powershell',
  timeoutSec: 5
};

const qoderDesiredHook = {
  type: 'command',
  command: nodeCommand
};

const grokDesiredHook = {
  type: 'command',
  command: nodeCommand,
  timeout: 5
};

const antigravityDesiredHook = {
  type: 'command',
  command: nodeCommand,
  timeout: 5
};

function desiredPreToolHook(target) {
  switch (target) {
    case 'codex':
    case 'pi':
    case 'claude':
      return claudeDesiredHook;
    case 'qoder':
      return qoderDesiredHook;
    case 'grok':
      return grokDesiredHook;
    default:
      return claudeDesiredHook;
  }
}

let existed = false;
let original = '';
let originalMode = scope === 'global' ? 0o600 : 0o644;

try {
  const stat = fs.lstatSync(settingsPath);
  existed = true;
  if (stat.isSymbolicLink()) {
    fail(`Refusing to replace symbolic link: ${settingsPath}`);
  }
  if (!stat.isFile()) {
    fail(`Settings path is not a regular file: ${settingsPath}`);
  }
  originalMode = stat.mode & 0o777;
  original = fs.readFileSync(settingsPath, 'utf8');
} catch (error) {
  if (error.code !== 'ENOENT') throw error;
}

let settings = {};
if (original.trim() !== '') {
  try {
    settings = JSON.parse(original);
  } catch (error) {
    fail(`Invalid JSON in ${settingsPath}: ${error.message}`);
  }
}

if (!isObject(settings)) {
  fail(`Settings root must be a JSON object: ${settingsPath}`);
}

let changed = false;
if (hookTarget === 'cursor') {
  if (settings.version === undefined) {
    settings.version = 1;
  }
  if (settings.hooks === undefined) {
    settings.hooks = {};
  }
  if (!isObject(settings.hooks)) {
    fail('Settings path "hooks" must be a JSON object');
  }
  if (settings.hooks.beforeShellExecution !== undefined && !Array.isArray(settings.hooks.beforeShellExecution)) {
    fail('Settings path "hooks.beforeShellExecution" must be an array');
  }
  if (settings.hooks.beforeShellExecution === undefined) {
    settings.hooks.beforeShellExecution = [];
  }

  const entries = settings.hooks.beforeShellExecution;
  const ownedIndexes = [];
  for (let index = 0; index < entries.length; index += 1) {
    if (isOwnedCursorHook(entries[index])) {
      ownedIndexes.push(index);
    }
  }

  if (ownedIndexes.length > 0) {
    const firstIndex = ownedIndexes[0];
    if (!sameJson(entries[firstIndex], cursorDesiredHook)) {
      entries[firstIndex] = cursorDesiredHook;
      changed = true;
    }

    const filtered = [];
    for (let index = 0; index < entries.length; index += 1) {
      if (ownedIndexes.includes(index) && index !== firstIndex) {
        changed = true;
        continue;
      }
      filtered.push(entries[index]);
    }
    settings.hooks.beforeShellExecution = filtered;
  } else {
    entries.push(cursorDesiredHook);
    changed = true;
  }
} else if (hookTarget === 'copilot') {
  if (settings.version === undefined) {
    settings.version = 1;
  }
  if (settings.hooks === undefined) {
    settings.hooks = {};
  }
  if (!isObject(settings.hooks)) {
    fail('Settings path "hooks" must be a JSON object');
  }
  if (settings.hooks.preToolUse !== undefined && !Array.isArray(settings.hooks.preToolUse)) {
    fail('Settings path "hooks.preToolUse" must be an array');
  }
  if (settings.hooks.preToolUse === undefined) {
    settings.hooks.preToolUse = [];
  }

  const preToolUse = settings.hooks.preToolUse;
  const ownedIndexes = [];
  for (let index = 0; index < preToolUse.length; index += 1) {
    if (isOwnedCopilotHook(preToolUse[index])) {
      ownedIndexes.push(index);
    }
  }

  if (ownedIndexes.length > 0) {
    const firstIndex = ownedIndexes[0];
    if (!sameJson(preToolUse[firstIndex], copilotDesiredHook)) {
      preToolUse[firstIndex] = copilotDesiredHook;
      changed = true;
    }

    const filtered = [];
    for (let index = 0; index < preToolUse.length; index += 1) {
      if (ownedIndexes.includes(index) && index !== firstIndex) {
        changed = true;
        continue;
      }
      filtered.push(preToolUse[index]);
    }
    settings.hooks.preToolUse = filtered;
  } else {
    preToolUse.push(copilotDesiredHook);
    changed = true;
  }
} else if (hookTarget === 'antigravity') {
  const workspace = 'better-rm-protection';
  if (settings.hooks === undefined) {
    settings.hooks = {};
  }
  if (!isObject(settings.hooks)) {
    fail('Settings path "hooks" must be a JSON object');
  }

  if (settings.hooks[workspace] === undefined) {
    settings.hooks[workspace] = {};
  }
  if (!isObject(settings.hooks[workspace])) {
    fail(`Settings path "hooks.${workspace}" must be a JSON object`);
  }

  if (settings.hooks[workspace].PreToolUse !== undefined && !Array.isArray(settings.hooks[workspace].PreToolUse)) {
    fail(`Settings path "hooks.${workspace}.PreToolUse" must be an array`);
  }
  if (settings.hooks[workspace].PreToolUse === undefined) {
    settings.hooks[workspace].PreToolUse = [];
  }

  const preToolUse = settings.hooks[workspace].PreToolUse;
  const runEntries = [];
  for (const entry of preToolUse) {
    if (isObject(entry) && entry.matcher === 'run_command') {
      if (entry.hooks !== undefined && !Array.isArray(entry.hooks)) {
        fail('A "hooks.PreToolUse" entry with matcher "run_command" must contain a hooks array');
      }
      if (entry.hooks === undefined) entry.hooks = [];
      runEntries.push(entry);
    }
  }

  let firstOwned = null;
  for (const entry of runEntries) {
    for (let index = 0; index < entry.hooks.length; index += 1) {
      if (isOwnedPreToolHook(entry.hooks[index])) {
        if (firstOwned === null) {
          firstOwned = { entry, index };
        }
      }
    }
  }

  if (firstOwned !== null) {
    if (!sameJson(firstOwned.entry.hooks[firstOwned.index], antigravityDesiredHook)) {
      firstOwned.entry.hooks[firstOwned.index] = antigravityDesiredHook;
      changed = true;
    }

    let keptFirst = false;
    for (const entry of runEntries) {
      entry.hooks = entry.hooks.filter((hook) => {
        if (!isOwnedPreToolHook(hook)) return true;
        if (!keptFirst) {
          keptFirst = true;
          return true;
        }
        changed = true;
        return false;
      });
    }
  } else if (runEntries.length > 0) {
    runEntries[0].hooks.push(antigravityDesiredHook);
    changed = true;
  } else {
    preToolUse.push({ matcher: 'run_command', hooks: [antigravityDesiredHook] });
    changed = true;
  }
} else if (hookTarget === 'claude' || hookTarget === 'codex' || hookTarget === 'qoder' || hookTarget === 'pi' || hookTarget === 'grok') {
  if (settings.hooks !== undefined && !isObject(settings.hooks)) {
    fail('Settings path "hooks" must be a JSON object');
  }

  if (settings.hooks === undefined) settings.hooks = {};
  if (settings.hooks.PreToolUse === undefined) settings.hooks.PreToolUse = [];

  const preToolUse = settings.hooks.PreToolUse;
  const bashEntries = [];
  for (const entry of preToolUse) {
    if (isObject(entry) && entry.matcher === 'Bash') {
      if (entry.hooks !== undefined && !Array.isArray(entry.hooks)) {
        fail('A "hooks.PreToolUse" entry with matcher "Bash" must contain a hooks array');
      }
      if (entry.hooks === undefined) entry.hooks = [];
      bashEntries.push(entry);
    }
  }

  let firstOwned = null;
  for (const entry of bashEntries) {
    for (let index = 0; index < entry.hooks.length; index += 1) {
      if (isOwnedPreToolHook(entry.hooks[index])) {
        if (firstOwned === null) {
          firstOwned = { entry, index };
        }
      }
    }
  }

  const desiredHook = desiredPreToolHook(hookTarget);
  if (firstOwned !== null) {
    if (!sameJson(firstOwned.entry.hooks[firstOwned.index], desiredHook)) {
      firstOwned.entry.hooks[firstOwned.index] = desiredHook;
      changed = true;
    }

    let keptFirst = false;
    for (const entry of bashEntries) {
      entry.hooks = entry.hooks.filter((hook) => {
        if (!isOwnedPreToolHook(hook)) return true;
        if (!keptFirst) {
          keptFirst = true;
          return true;
        }
        changed = true;
        return false;
      });
    }
  } else if (bashEntries.length > 0) {
    bashEntries[0].hooks.push(desiredHook);
    changed = true;
  } else {
    preToolUse.push({ matcher: 'Bash', hooks: [desiredHook] });
    changed = true;
  }
} else {
  fail(`Unsupported hook target: ${hookTarget}`);
}

if (!changed && existed) {
  process.stdout.write(`unchanged\t${settingsPath}`);
  process.exit(0);
}

const directory = path.dirname(settingsPath);
fs.mkdirSync(directory, { recursive: true, mode: scope === 'global' ? 0o700 : 0o755 });

let backupPath = '';
if (existed) {
  const timestamp = new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');
  const base = `${settingsPath}.better-rm.bak.${timestamp}`;
  backupPath = base;
  let suffix = 1;
  while (fs.existsSync(backupPath)) {
    backupPath = `${base}.${suffix}`;
    suffix += 1;
  }
  fs.writeFileSync(backupPath, original, { mode: originalMode, flag: 'wx' });
}

const temporaryPath = path.join(directory, `.${path.basename(settingsPath)}.better-rm.${process.pid}.tmp`);
try {
  fs.writeFileSync(temporaryPath, `${JSON.stringify(settings, null, 2)}\n`, {
    mode: originalMode,
    flag: 'wx'
  });
  fs.chmodSync(temporaryPath, originalMode);
  fs.renameSync(temporaryPath, settingsPath);
} catch (error) {
  try { fs.unlinkSync(temporaryPath); } catch (_) {}
  throw error;
}

if (existed) {
  process.stdout.write(`updated\t${settingsPath}\t${backupPath}`);
} else {
  process.stdout.write(`created\t${settingsPath}`);
}
NODE
}

report_json_result() {
    local agent_name="$1"
    local result="$2"

    local action settings_path backup_path
    IFS=$'\t' read -r action settings_path backup_path <<< "$result"
    case "$action" in
        created)
            success "已建立 ${agent_name} hook 設定：$settings_path"
            success "Created ${agent_name} hook settings: $settings_path"
            ;;
        updated)
            success "已更新 ${agent_name} hook 設定：$settings_path"
            success "Updated ${agent_name} hook settings: $settings_path"
            if [ -n "$backup_path" ]; then
                info "備份檔案 / Backup: $backup_path"
            fi
            ;;
        unchanged)
            info "${agent_name} hook 已是最新狀態 / ${agent_name} hook is already up to date"
            ;;
        *)
            error "無法辨識安裝結果 / Unknown installation result: $result"
            exit 1
            ;;
    esac
}

# 安裝 Claude Code hook (Install Claude Code hook)
install_claude_hooks() {
    if ! command_exists node; then
        error "找不到 node 命令，hooks 需要 Node.js"
        error "node command not found; hooks require Node.js"
        exit 1
    fi

    resolve_claude_settings
    resolve_shared_hook_for_settings

    info "Claude Code 設定檔：$SETTINGS_PATH"
    info "共用 hook：$HOOK_PATH"

    local result
    HOOK_TARGET=claude
    result=$(HOOK_TARGET="$HOOK_TARGET" merge_json_settings)

    report_json_result "Claude Code" "$result"

    if [ "$GLOBAL_INSTALL" = true ]; then
        warning "全域 hook 會使用目前使用者設定目錄中的共用 hook，搬移或刪除該設定目錄將使 hook 失效"
        warning "Global hook uses runtime file under the current user config directory; moving or deleting it will break the hook"
    fi
}

# 安裝 Cursor hook (Install Cursor hook)
install_cursor_hooks() {
    if ! command_exists node; then
        error "找不到 node 命令，hooks 需要 Node.js"
        error "node command not found; hooks require Node.js"
        exit 1
    fi

    resolve_cursor_settings
    resolve_shared_hook_for_settings

    info "Cursor 設定檔：$SETTINGS_PATH"
    info "共用 hook：$HOOK_PATH"

    local result
    HOOK_TARGET=cursor
    result=$(HOOK_TARGET="$HOOK_TARGET" merge_json_settings)

    report_json_result "Cursor" "$result"
}

# 安裝 Codex hook (Install Codex hook)
install_codex_hooks() {
    if ! command_exists node; then
        error "找不到 node 命令，hooks 需要 Node.js"
        error "node command not found; hooks require Node.js"
        exit 1
    fi

    resolve_codex_settings
    resolve_shared_hook_for_settings

    info "Codex 設定檔：$SETTINGS_PATH"
    info "共用 hook：$HOOK_PATH"

    local result
    HOOK_TARGET=codex
    result=$(HOOK_TARGET="$HOOK_TARGET" merge_json_settings)

    report_json_result "Codex" "$result"
}

# 安裝 GitHub Copilot hook (Install GitHub Copilot hook)
install_copilot_hooks() {
    if ! command_exists node; then
        error "找不到 node 命令，hooks 需要 Node.js"
        error "node command not found; hooks require Node.js"
        exit 1
    fi

    resolve_copilot_settings
    resolve_shared_hook_for_settings

    info "GitHub Copilot 設定檔：$SETTINGS_PATH"
    info "共用 hook：$HOOK_PATH"

    local result
    HOOK_TARGET=copilot
    result=$(HOOK_TARGET="$HOOK_TARGET" merge_json_settings)

    report_json_result "GitHub Copilot" "$result"
}

# 安裝 Antigravity hook (Install Antigravity hook)
install_antigravity_hooks() {
    if ! command_exists node; then
        error "找不到 node 命令，hooks 需要 Node.js"
        error "node command not found; hooks require Node.js"
        exit 1
    fi

    resolve_antigravity_settings
    resolve_shared_hook_for_settings

    info "Antigravity 設定檔：$SETTINGS_PATH"
    info "共用 hook：$HOOK_PATH"

    local result
    HOOK_TARGET=antigravity
    result=$(HOOK_TARGET="$HOOK_TARGET" merge_json_settings)

    report_json_result "Antigravity" "$result"
}

# 安裝 Qoder hook (Install Qoder hook)
install_qoder_hooks() {
    if ! command_exists node; then
        error "找不到 node 命令，hooks 需要 Node.js"
        error "node command not found; hooks require Node.js"
        exit 1
    fi

    resolve_qoder_settings
    resolve_shared_hook_for_settings

    info "Qoder 設定檔：$SETTINGS_PATH"
    info "共用 hook：$HOOK_PATH"

    local result
    HOOK_TARGET=qoder
    result=$(HOOK_TARGET="$HOOK_TARGET" merge_json_settings)

    report_json_result "Qoder" "$result"
}

# 安裝 Pi hook (Install Pi hook)
install_pi_hooks() {
    if ! command_exists node; then
        error "找不到 node 命令，hooks 需要 Node.js"
        error "node command not found; hooks require Node.js"
        exit 1
    fi

    resolve_pi_settings
    resolve_shared_hook_for_settings

    info "Pi 設定檔：$SETTINGS_PATH"
    info "共用 hook：$HOOK_PATH"

    local result
    HOOK_TARGET=pi
    result=$(HOOK_TARGET="$HOOK_TARGET" merge_json_settings)

    report_json_result "Pi" "$result"
}

# 安裝 Grok Build hook (Install Grok Build hook)
install_grok_hooks() {
    if ! command_exists node; then
        error "找不到 node 命令，hooks 需要 Node.js"
        error "node command not found; hooks require Node.js"
        exit 1
    fi

    resolve_grok_settings
    resolve_shared_hook_for_settings

    info "Grok Build 設定檔：$SETTINGS_PATH"
    info "共用 hook：$HOOK_PATH"

    local result
    HOOK_TARGET=grok
    result=$(HOOK_TARGET="$HOOK_TARGET" merge_json_settings)

    report_json_result "Grok Build" "$result"
}

# 安裝 OpenCode 插件 (Install OpenCode plugin)
install_opencode_hooks() {
    resolve_opencode_plugin

    info "OpenCode 插件：$PLUGIN_PATH"
    info "OpenCode 共享 hook：$OPENCODE_RUNTIME_PATH"

    # Validate every destination before writing either file, avoiding partial updates.
    validate_opencode_destination "$PLUGIN_PATH" "插件" "plugin"
    validate_opencode_destination "$OPENCODE_RUNTIME_PATH" "runtime" "runtime file"
    require_opencode_destination_within_root \
        "$PLUGIN_PATH" "$OPENCODE_PROJECT_ROOT" "插件" "plugin"
    require_opencode_destination_within_root \
        "$OPENCODE_RUNTIME_PATH" "$OPENCODE_PROJECT_ROOT" "runtime" "runtime file"

    local plugin_dir
    plugin_dir="$(dirname -- "$PLUGIN_PATH")"
    mkdir -p "$plugin_dir"

    local runtime_dir
    runtime_dir="$(dirname -- "$OPENCODE_RUNTIME_PATH")"
    mkdir -p "$runtime_dir"

    if [ -e "$PLUGIN_PATH" ]; then
        if cmp -s "$PLUGIN_SOURCE_PATH" "$PLUGIN_PATH"; then
            info "OpenCode 插件已是最新狀態 / OpenCode plugin is already up to date"
        else
            local backup_path
            backup_path="$PLUGIN_PATH.better-rm.bak.$(date -u +%Y%m%dT%H%M%SZ)"
            local suffix=1
            while [ -e "$backup_path" ]; do
                backup_path="$PLUGIN_PATH.better-rm.bak.$(date -u +%Y%m%dT%H%M%SZ).${suffix}"
                suffix=$((suffix + 1))
            done
            cp "$PLUGIN_PATH" "$backup_path"
            # 不讀原本的 mode，也就完全不必用 stat：`cp` 覆寫既有檔案時保留目的地
            # 的 inode 與 mode，所以那個 chmod 本來就是多餘的。stat 的旗標在 BSD
            # 與 GNU userland 並不相容（GNU 的 `-f` 是「檔案系統狀態」，會把 '%Lp'
            # 當成另一個 operand：stderr 報錯、結束碼 1，但仍把該檔案的檔案系統資訊
            # 印到 stdout；`||` 後援確實會執行，命令替換卻把兩段 stdout 一起收下，
            # chmod 吃到垃圾而失敗，安裝就停在寫到一半的狀態）。共用 hook 的路徑
            # 早已用同樣的理由拿掉 stat。
            # The original mode is never read, so stat is not needed: cp onto an
            # existing file preserves the destination's inode and mode, which made
            # that chmod redundant anyway. stat's flags are not portable between
            # BSD and GNU userland (GNU `-f` means FILE SYSTEM status and treats
            # '%Lp' as another operand: it errors on stderr and exits 1 but still
            # prints that file's filesystem info on stdout, so the `||` fallback
            # runs and the command substitution captures BOTH outputs, feeding
            # chmod garbage and aborting the install midway). The shared-hook path
            # dropped stat for the same reason.
            cp "$PLUGIN_SOURCE_PATH" "$PLUGIN_PATH"
            require_faithful_opencode_plugin
            success "已更新 OpenCode 插件：$PLUGIN_PATH"
            success "Updated OpenCode plugin: $PLUGIN_PATH"
            info "備份檔案 / Backup: $backup_path"
        fi
    else
        cp "$PLUGIN_SOURCE_PATH" "$PLUGIN_PATH"
        require_faithful_opencode_plugin
        success "已建立 OpenCode 插件：$PLUGIN_PATH"
        success "Created OpenCode plugin: $PLUGIN_PATH"
    fi

    if [ -e "$OPENCODE_RUNTIME_PATH" ]; then
        if cmp -s "$OPENCODE_RUNTIME_SOURCE_PATH" "$OPENCODE_RUNTIME_PATH"; then
            success "OpenCode 共享 hook 已是最新狀態 / OpenCode runtime hook is already up to date"
        else
            local runtime_backup_path
            runtime_backup_path="$OPENCODE_RUNTIME_PATH.better-rm.bak.$(date -u +%Y%m%dT%H%M%SZ)"
            local runtime_suffix=1
            while [ -e "$runtime_backup_path" ]; do
                runtime_backup_path="$OPENCODE_RUNTIME_PATH.better-rm.bak.$(date -u +%Y%m%dT%H%M%SZ).${runtime_suffix}"
                runtime_suffix=$((runtime_suffix + 1))
            done
            cp "$OPENCODE_RUNTIME_PATH" "$runtime_backup_path"
            # 同上：cp 覆寫既有檔案會保留 mode 與 inode，因此不需要（也不能）用 stat。
            # As above: cp onto an existing file preserves mode and inode, so no
            # stat is needed — and stat here is not portable.
            cp "$OPENCODE_RUNTIME_SOURCE_PATH" "$OPENCODE_RUNTIME_PATH"
            require_verified_opencode_runtime "$runtime_backup_path"
            success "已更新 OpenCode 共享 hook：$OPENCODE_RUNTIME_PATH"
            success "Updated OpenCode runtime hook: $OPENCODE_RUNTIME_PATH"
            info "備份檔案 / Backup: $runtime_backup_path"
        fi
    else
        cp "$OPENCODE_RUNTIME_SOURCE_PATH" "$OPENCODE_RUNTIME_PATH"
        require_verified_opencode_runtime
        success "已建立 OpenCode 共享 hook：$OPENCODE_RUNTIME_PATH"
        success "Created OpenCode runtime hook: $OPENCODE_RUNTIME_PATH"
    fi
}

main() {
    parse_arguments "$@"
    resolve_source_paths

    case "$AGENT" in
        claude)
            install_claude_hooks
            ;;
        codex)
            install_codex_hooks
            ;;
        cursor)
            install_cursor_hooks
            ;;
        copilot)
            install_copilot_hooks
            ;;
        antigravity)
            install_antigravity_hooks
            ;;
        qoder)
            install_qoder_hooks
            ;;
        pi)
            install_pi_hooks
            ;;
        opencode)
            install_opencode_hooks
            ;;
        grok)
            install_grok_hooks
            ;;
        *)
            local supported_agents
            supported_agents="$(supported_agents_str)"
            error "尚未支援此 Coding Agent：$AGENT（可用：${supported_agents}）"
            error "Unsupported coding agent: $AGENT (supported: ${supported_agents})"
            exit 2
            ;;
    esac

    # 只有在上面的安裝（含設定註冊）成功回來後，才替換過期的 runtime hook。
    # set -e 會讓任何失敗在這之前就中止，因此不會出現「換了 hook 卻沒註冊」。
    # The stale runtime hook is replaced only after the installer above returned
    # successfully, registration included. set -e aborts before this point on any
    # failure, so a replaced-but-unregistered hook cannot happen.
    apply_pending_hook_refresh
}

main "$@"
