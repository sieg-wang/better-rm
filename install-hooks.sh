#!/bin/bash
#
# coding agent hooks 安裝腳本 / Coding agent hooks installer
#
# 用法 (Usage):
#   ./install-hooks.sh -a claude
#   ./install-hooks.sh -a claude --global
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
SUPPORTED_AGENTS=(claude)

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

# 檢查命令是否存在 (Check if command exists)
command_exists() {
    command -v "$1" >/dev/null 2>&1
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
  -g, --global         Install into the agent's global/user settings
                       安裝到 Agent 的全域／使用者設定
  -h, --help           Show this help message
                       顯示此說明

Examples:
  ./install-hooks.sh -a claude
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
    HOOK_PATH="$SCRIPT_DIR/hooks/protect-important-paths.js"

    if [ ! -f "$HOOK_PATH" ] || [ ! -r "$HOOK_PATH" ]; then
        error "找不到共用 hook：$HOOK_PATH"
        error "Shared hook not found or unreadable: $HOOK_PATH"
        exit 1
    fi
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
        if ! command_exists git; then
            error "找不到 git 命令 / git command not found"
            exit 1
        fi

        local project_root
        if ! project_root=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null); then
            error "目前目錄不在 Git 儲存庫中 / Current directory is not inside a Git repository"
            exit 1
        fi
        SETTINGS_PATH="$project_root/.claude/settings.json"
        SCOPE="project"
    fi
}

# 以 Node.js 安全合併 Claude Code JSON 設定
# Safely merge Claude Code JSON settings with Node.js
merge_claude_settings() {
    node - "$SETTINGS_PATH" "$HOOK_PATH" "$SCOPE" <<'NODE'
'use strict';

const fs = require('fs');
const path = require('path');

const settingsPath = process.argv[2];
const hookPath = process.argv[3];
const scope = process.argv[4];

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

function isOwnedHook(value) {
  return isObject(value)
    && value.type === 'command'
    && typeof value.command === 'string'
    && /(?:^|[\\/])hooks[\\/]protect-important-paths\.js(?:['"\s]|$)/.test(value.command);
}

function sameJson(left, right) {
  return JSON.stringify(left) === JSON.stringify(right);
}

const desiredHook = {
  type: 'command',
  command: `node ${shellQuote(hookPath)}`,
  timeout: 5,
  statusMessage: 'Checking protected directories...'
};

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
if (settings.hooks !== undefined && !isObject(settings.hooks)) {
  fail('Claude settings path "hooks" must be a JSON object');
}
if (settings.hooks?.PreToolUse !== undefined && !Array.isArray(settings.hooks.PreToolUse)) {
  fail('Claude settings path "hooks.PreToolUse" must be a JSON array');
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
let ownedCount = 0;
for (const entry of bashEntries) {
  for (let index = 0; index < entry.hooks.length; index += 1) {
    if (isOwnedHook(entry.hooks[index])) {
      ownedCount += 1;
      if (firstOwned === null) firstOwned = { entry, index };
    }
  }
}

let changed = false;
if (firstOwned !== null) {
  if (!sameJson(firstOwned.entry.hooks[firstOwned.index], desiredHook)) {
    firstOwned.entry.hooks[firstOwned.index] = desiredHook;
    changed = true;
  }

  let keptFirst = false;
  for (const entry of bashEntries) {
    entry.hooks = entry.hooks.filter((hook) => {
      if (!isOwnedHook(hook)) return true;
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

# 安裝 Claude Code hook (Install Claude Code hook)
install_claude_hooks() {
    if ! command_exists node; then
        error "找不到 node 命令，hooks 需要 Node.js"
        error "node command not found; hooks require Node.js"
        exit 1
    fi

    resolve_claude_settings

    info "Claude Code 設定檔：$SETTINGS_PATH"
    info "共用 hook：$HOOK_PATH"

    local result
    result=$(merge_claude_settings)

    local action settings_path backup_path
    IFS=$'\t' read -r action settings_path backup_path <<< "$result"
    case "$action" in
        created)
            success "已建立 Claude Code hook 設定：$settings_path"
            success "Created Claude Code hook settings: $settings_path"
            ;;
        updated)
            success "已更新 Claude Code hook 設定：$settings_path"
            success "Updated Claude Code hook settings: $settings_path"
            info "備份檔案 / Backup: $backup_path"
            ;;
        unchanged)
            info "Claude Code hook 已是最新狀態 / Claude Code hook is already up to date"
            ;;
        *)
            error "無法辨識安裝結果 / Unknown installation result: $result"
            exit 1
            ;;
    esac

    if [ "$GLOBAL_INSTALL" = true ] && [[ "$SCRIPT_DIR" != "$HOME/.better-rm"* ]]; then
        warning "全域 hook 會參照目前 checkout；移動或刪除它將使 hook 失效"
        warning "The global hook references this checkout; moving or deleting it will break the hook"
    fi
}

main() {
    parse_arguments "$@"
    resolve_source_paths

    case "$AGENT" in
        claude)
            install_claude_hooks
            ;;
        *)
            local supported_agents
            supported_agents="$(supported_agents_str)"
            error "尚未支援此 Coding Agent：$AGENT（可用：${supported_agents}）"
            error "Unsupported coding agent: $AGENT (supported: ${supported_agents})"
            exit 2
            ;;
    esac
}

main "$@"
