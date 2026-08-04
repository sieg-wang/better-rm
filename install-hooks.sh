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
RELEASE_OPENCODE_PLUGIN_ASSET_NAME="opencode-protect-important-paths.ts"
CLEANUP_DIRS=""

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

cleanup_release_dirs() {
    local directory
    for directory in $CLEANUP_DIRS; do
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
    SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
    HOOK_SOURCE_PATH="$SCRIPT_DIR/hooks/protect-important-paths.js"

    if [ ! -f "$HOOK_SOURCE_PATH" ] || [ ! -r "$HOOK_SOURCE_PATH" ]; then
        local release_dir
        release_dir="$(mktemp -d)"
        CLEANUP_DIRS="$CLEANUP_DIRS $release_dir"
        HOOK_SOURCE_PATH="$release_dir/hooks/protect-important-paths.js"
        info "本機未找到共用 hook，改用最新 Release"
        info "Shared hook not found locally; downloading from latest release"
        download_release_file "$RELEASE_HOOK_ASSET_NAME" "$HOOK_SOURCE_PATH"

        if [ ! -f "$HOOK_SOURCE_PATH" ] || [ ! -r "$HOOK_SOURCE_PATH" ]; then
            error "下載共用 hook 失敗：$HOOK_SOURCE_PATH"
            error "Failed to download shared hook: $HOOK_SOURCE_PATH"
            exit 1
        fi
    fi

    trap cleanup_release_dirs EXIT
}

resolve_shared_hook_for_settings() {
    local settings_dir
    settings_dir="$(dirname -- "$SETTINGS_PATH")"
    HOOK_PATH="$settings_dir/protect-important-paths.js"

    PENDING_HOOK_REFRESH=false

    if [ ! -f "$HOOK_PATH" ] || [ ! -r "$HOOK_PATH" ]; then
        mkdir -p -- "$(dirname -- "$HOOK_PATH")"
        cp "$HOOK_SOURCE_PATH" "$HOOK_PATH"
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

# 取得 OpenCode 外掛檔案位置 (Resolve OpenCode plugin path)
resolve_opencode_plugin() {
    if [ "$GLOBAL_INSTALL" = true ]; then
        error "OpenCode 不支援 --global，請移除該參數 / OpenCode does not support --global; remove this flag"
        exit 2
    fi

    local project_root
    project_root="$(resolve_project_root)"
    PLUGIN_SOURCE_PATH="$SCRIPT_DIR/.opencode/plugins/protect-important-paths.ts"
    if [ ! -f "$PLUGIN_SOURCE_PATH" ] || [ ! -r "$PLUGIN_SOURCE_PATH" ]; then
        local plugin_release_dir
        plugin_release_dir="$(mktemp -d)"
        CLEANUP_DIRS="$CLEANUP_DIRS $plugin_release_dir"
        PLUGIN_SOURCE_PATH="$plugin_release_dir/.opencode/plugins/protect-important-paths.ts"
    fi
    PLUGIN_PATH="$project_root/.opencode/plugins/protect-important-paths.ts"
    OPENCODE_RUNTIME_SOURCE_PATH="$HOOK_SOURCE_PATH"
    OPENCODE_RUNTIME_PATH="$project_root/hooks/protect-important-paths.js"

    if [ ! -f "$PLUGIN_SOURCE_PATH" ] || [ ! -r "$PLUGIN_SOURCE_PATH" ]; then
        download_release_file "$RELEASE_OPENCODE_PLUGIN_ASSET_NAME" "$PLUGIN_SOURCE_PATH"
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
            local plugin_mode
            plugin_mode=$(stat -f '%Lp' "$PLUGIN_PATH" 2>/dev/null || stat -c '%a' "$PLUGIN_PATH")
            cp "$PLUGIN_PATH" "$backup_path"
            cp "$PLUGIN_SOURCE_PATH" "$PLUGIN_PATH"
            chmod "$plugin_mode" "$PLUGIN_PATH"
            success "已更新 OpenCode 插件：$PLUGIN_PATH"
            success "Updated OpenCode plugin: $PLUGIN_PATH"
            info "備份檔案 / Backup: $backup_path"
        fi
    else
        cp "$PLUGIN_SOURCE_PATH" "$PLUGIN_PATH"
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
            local runtime_mode
            runtime_mode=$(stat -f '%Lp' "$OPENCODE_RUNTIME_PATH" 2>/dev/null || stat -c '%a' "$OPENCODE_RUNTIME_PATH")
            cp "$OPENCODE_RUNTIME_PATH" "$runtime_backup_path"
            cp "$OPENCODE_RUNTIME_SOURCE_PATH" "$OPENCODE_RUNTIME_PATH"
            chmod "$runtime_mode" "$OPENCODE_RUNTIME_PATH"
            success "已更新 OpenCode 共享 hook：$OPENCODE_RUNTIME_PATH"
            success "Updated OpenCode runtime hook: $OPENCODE_RUNTIME_PATH"
            info "備份檔案 / Backup: $runtime_backup_path"
        fi
    else
        cp "$OPENCODE_RUNTIME_SOURCE_PATH" "$OPENCODE_RUNTIME_PATH"
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
