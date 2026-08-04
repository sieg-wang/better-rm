#!/bin/bash
#
# install-hooks.sh 測試 / Tests for install-hooks.sh
#

set -e

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
INSTALLER="$SCRIPT_DIR/install-hooks.sh"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/better-rm-hooks.XXXXXX")
PASSED=0
FAILED=0

cleanup() {
    rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

pass() {
    PASSED=$((PASSED + 1))
    echo "✓ $1"
}

fail() {
    FAILED=$((FAILED + 1))
    echo "✗ $1" >&2
}

assert_success() {
    local name="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        pass "$name"
    else
        fail "$name"
    fi
}

assert_contains() {
    local name="$1"
    local haystack="$2"
    local needle="$3"
    if printf '%s\n' "$haystack" | grep -q "$needle"; then
        pass "$name"
    else
        fail "$name"
    fi
}

assert_failure() {
    local name="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        fail "$name"
    else
        pass "$name"
    fi
}

assert_file() {
    local name="$1"
    local file="$2"
    if [ -f "$file" ]; then
        pass "$name"
    else
        fail "$name"
    fi
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

make_repo() {
    local repo="$1"
    mkdir -p "$repo"
    git -C "$repo" init -q
}

hook_count() {
    local agent="${2:-claude}"
    node - "$1" "$agent" <<'NODE'
const fs = require('fs');
const settings = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const agent = process.argv[3] ?? 'claude';
let count = 0;

const hasRuntimePath = (command) => typeof command === 'string' && command.includes('protect-important-paths.js');

if (agent === 'cursor') {
  for (const hook of settings?.hooks?.beforeShellExecution ?? []) {
    if (typeof hook?.command === 'string' && hasRuntimePath(hook.command)) count += 1;
  }
} else if (agent === 'copilot') {
  for (const entry of settings?.hooks?.preToolUse ?? []) {
    if (entry?.type !== 'command' || entry?.matcher !== 'bash|powershell') continue;
    if ((typeof entry?.bash === 'string' && hasRuntimePath(entry.bash))
      || (typeof entry?.powershell === 'string' && hasRuntimePath(entry.powershell))) {
      count += 1;
    }
  }
} else if (agent === 'antigravity') {
  const workspace = settings?.hooks?.['better-rm-protection'];
  for (const entry of workspace?.PreToolUse ?? []) {
    if (entry?.matcher !== 'run_command' || !Array.isArray(entry.hooks)) continue;
    for (const hook of entry.hooks) {
      if (hook?.type === 'command' && hasRuntimePath(hook.command)) count += 1;
    }
  }
} else {
  for (const entry of settings.hooks?.PreToolUse ?? []) {
    if (entry?.matcher !== 'Bash' || !Array.isArray(entry.hooks)) continue;
    for (const hook of entry.hooks) {
      if (hook?.type === 'command' && hasRuntimePath(hook.command)) count += 1;
    }
  }
}
process.stdout.write(String(count));
NODE
}

file_mode() {
    node -e 'process.stdout.write((require("fs").statSync(process.argv[1]).mode & 0o777).toString(8))' "$1"
}

file_mtime() {
    node -e 'process.stdout.write(String(require("fs").statSync(process.argv[1]).mtimeMs))' "$1"
}

file_hash() {
    node -e 'process.stdout.write(require("crypto").createHash("sha256").update(require("fs").readFileSync(process.argv[1])).digest("hex"))' "$1"
}

backup_count() {
    local directory="$1"
    local name="$2"
    find "$directory" -maxdepth 1 -type f -name "$name.better-rm.bak.*" | wc -l | tr -d ' '
}

expected_settings_path() {
    case "$1" in
        claude) echo ".claude/settings.json" ;;
        codex) echo ".codex/hooks.json" ;;
        cursor) echo ".cursor/hooks.json" ;;
        copilot) echo ".github/hooks/better-rm.json" ;;
        antigravity) echo ".agents/hooks.json" ;;
        qoder) echo ".qoder/settings.json" ;;
        pi) echo ".pi/hooks.json" ;;
        grok) echo ".grok/hooks/better-rm.json" ;;
        *) echo "" ;;
    esac
}

echo "========================================"
echo "install-hooks.sh tests"
echo "========================================"

CURRENT_HOOKS_VERSION="$(awk -F'\"' '/^VERSION=/{print $2; exit}' "$SCRIPT_DIR/install-hooks.sh")"

# CLI parsing
assert_success "--version short flag works" bash -c "'$INSTALLER' -v | grep -q \"install-hooks.sh ${CURRENT_HOOKS_VERSION}\""
assert_success "--version long flag works" bash -c "'$INSTALLER' --version | grep -q \"install-hooks.sh ${CURRENT_HOOKS_VERSION}\""
assert_success "--help succeeds" "$INSTALLER" --help
HELP_TEXT=$("$INSTALLER" --help)
assert_contains "help shows supported agents" "$HELP_TEXT" "supported:"
assert_contains "help shows claude as supported agent" "$HELP_TEXT" "claude"
assert_contains "help shows codex as supported agent" "$HELP_TEXT" "codex"
assert_contains "help shows cursor as supported agent" "$HELP_TEXT" "cursor"
assert_failure "missing --agent fails" "$INSTALLER"
assert_failure "missing --agent value fails" "$INSTALLER" --agent
assert_failure "unknown option fails" "$INSTALLER" --wat
assert_failure "unsupported agent fails" "$INSTALLER" --agent unknown
assert_failure "duplicate --agent fails" "$INSTALLER" -a claude --agent claude

# Matrix install in project mode for all supported agents.
for agent in claude codex cursor copilot antigravity qoder pi grok; do
    AGENT_PROJECT="$TMP_ROOT/matrix-${agent}-project"
    make_repo "$AGENT_PROJECT"
    mkdir -p "$AGENT_PROJECT/src/nested"
    (
        cd "$AGENT_PROJECT/src/nested"
        "$INSTALLER" -a "$agent" >/dev/null
    )

    AGENT_SETTINGS="$AGENT_PROJECT/$(expected_settings_path "$agent")"
    AGENT_SETTINGS_DIR="$(dirname "$AGENT_SETTINGS")"
    assert_file "matrix project install creates ${agent} settings" "$AGENT_SETTINGS"
    assert_equal "matrix ${agent} hook count is one" "1" "$(hook_count "$AGENT_SETTINGS" "$agent")"
    assert_equal "matrix ${agent} settings mode is 644" "644" "$(file_mode "$AGENT_SETTINGS")"
    assert_file "matrix ${agent} hook is placed beside settings" "$AGENT_SETTINGS_DIR/protect-important-paths.js"

    AGENT_HASH_BEFORE=$(file_hash "$AGENT_SETTINGS")
    (
        cd "$AGENT_PROJECT/src/nested"
        "$INSTALLER" -a "$agent" >/dev/null
    )
    assert_equal "matrix ${agent} install is idempotent" "$AGENT_HASH_BEFORE" "$(file_hash "$AGENT_SETTINGS")"

    # Non-Claude agents should reject --global
    if [ "$agent" != "claude" ]; then
        assert_failure "matrix ${agent} rejects global" bash -c "cd '$TMP_ROOT' && '$INSTALLER' -a '$agent' --global"
    fi
done

# OpenCode has dedicated runtime + plugin install path checks.
OPENCODE_PROJECT="$TMP_ROOT/opencode-project"
make_repo "$OPENCODE_PROJECT"
mkdir -p "$OPENCODE_PROJECT/src/nested"
(
    cd "$OPENCODE_PROJECT/src/nested"
    "$INSTALLER" -a opencode >/dev/null
)
OPENCODE_PLUGIN="$OPENCODE_PROJECT/.opencode/plugins/protect-important-paths.ts"
OPENCODE_RUNTIME="$OPENCODE_PROJECT/hooks/protect-important-paths.js"
assert_file "opencode plugin is created at project path" "$OPENCODE_PLUGIN"
assert_file "opencode runtime hook is created at project path" "$OPENCODE_RUNTIME"
OPENCODE_PLUGIN_HASH_BEFORE=$(file_hash "$OPENCODE_PLUGIN")
OPENCODE_RUNTIME_HASH_BEFORE=$(file_hash "$OPENCODE_RUNTIME")

assert_contains "opencode plugin references project-local runtime" "$(cat "$OPENCODE_PLUGIN")" "../../hooks/protect-important-paths"

(
    cd "$OPENCODE_PROJECT/src/nested"
    "$INSTALLER" -a opencode >/dev/null
)
assert_equal "opencode plugin hash is idempotent" "$OPENCODE_PLUGIN_HASH_BEFORE" "$(file_hash "$OPENCODE_PLUGIN")"
assert_equal "opencode runtime hash is idempotent" "$OPENCODE_RUNTIME_HASH_BEFORE" "$(file_hash "$OPENCODE_RUNTIME")"

# OpenCode should also reject project-level global install flag.
assert_failure "opencode rejects global" bash -c "cd '$TMP_ROOT' && '$INSTALLER' -a opencode --global"

# OpenCode must reject dangling symbolic links before copying plugin or runtime files.
OPENCODE_PLUGIN_SYMLINK_REPO="$TMP_ROOT/opencode-plugin-symlink-project"
make_repo "$OPENCODE_PLUGIN_SYMLINK_REPO"
mkdir -p "$OPENCODE_PLUGIN_SYMLINK_REPO/.opencode/plugins"
OPENCODE_DANGLING_PLUGIN_TARGET="$TMP_ROOT/missing-opencode-plugin.ts"
ln -s "$OPENCODE_DANGLING_PLUGIN_TARGET" "$OPENCODE_PLUGIN_SYMLINK_REPO/.opencode/plugins/protect-important-paths.ts"
assert_failure "opencode rejects dangling plugin symlink" bash -c "cd '$OPENCODE_PLUGIN_SYMLINK_REPO' && '$INSTALLER' -a opencode"
if [ -L "$OPENCODE_PLUGIN_SYMLINK_REPO/.opencode/plugins/protect-important-paths.ts" ] && [ ! -e "$OPENCODE_DANGLING_PLUGIN_TARGET" ]; then
    pass "opencode dangling plugin symlink is not followed"
else
    fail "opencode dangling plugin symlink is not followed"
fi
if [ ! -e "$OPENCODE_PLUGIN_SYMLINK_REPO/hooks/protect-important-paths.js" ]; then
    pass "opencode plugin symlink failure leaves runtime untouched"
else
    fail "opencode plugin symlink failure leaves runtime untouched"
fi

OPENCODE_RUNTIME_SYMLINK_REPO="$TMP_ROOT/opencode-runtime-symlink-project"
make_repo "$OPENCODE_RUNTIME_SYMLINK_REPO"
mkdir -p "$OPENCODE_RUNTIME_SYMLINK_REPO/.opencode/plugins" "$OPENCODE_RUNTIME_SYMLINK_REPO/hooks"
printf 'existing plugin must remain unchanged\n' > "$OPENCODE_RUNTIME_SYMLINK_REPO/.opencode/plugins/protect-important-paths.ts"
OPENCODE_STALE_PLUGIN_HASH=$(file_hash "$OPENCODE_RUNTIME_SYMLINK_REPO/.opencode/plugins/protect-important-paths.ts")
OPENCODE_DANGLING_RUNTIME_TARGET="$TMP_ROOT/missing-opencode-runtime.js"
ln -s "$OPENCODE_DANGLING_RUNTIME_TARGET" "$OPENCODE_RUNTIME_SYMLINK_REPO/hooks/protect-important-paths.js"
assert_failure "opencode rejects dangling runtime symlink" bash -c "cd '$OPENCODE_RUNTIME_SYMLINK_REPO' && '$INSTALLER' -a opencode"
assert_equal "opencode runtime symlink failure leaves plugin unchanged" "$OPENCODE_STALE_PLUGIN_HASH" "$(file_hash "$OPENCODE_RUNTIME_SYMLINK_REPO/.opencode/plugins/protect-important-paths.ts")"
if [ -L "$OPENCODE_RUNTIME_SYMLINK_REPO/hooks/protect-important-paths.js" ] && [ ! -e "$OPENCODE_DANGLING_RUNTIME_TARGET" ]; then
    pass "opencode dangling runtime symlink is not followed"
else
    fail "opencode dangling runtime symlink is not followed"
fi

# Global mode supports HOME and CLAUDE_CONFIG_DIR without a Git repository.
GLOBAL_HOME="$TMP_ROOT/global-home"
mkdir -p "$GLOBAL_HOME"
(
    cd "$TMP_ROOT"
    CLAUDE_CONFIG_DIR= HOME="$GLOBAL_HOME" "$INSTALLER" --agent claude --global >/dev/null
)
GLOBAL_SETTINGS="$GLOBAL_HOME/.claude/settings.json"
assert_file "global settings use HOME fallback" "$GLOBAL_SETTINGS"
assert_equal "new global settings use mode 600" "600" "$(file_mode "$GLOBAL_SETTINGS")"

CUSTOM_CONFIG="$TMP_ROOT/custom config"
(
    cd "$TMP_ROOT"
    HOME="$GLOBAL_HOME" CLAUDE_CONFIG_DIR="$CUSTOM_CONFIG" "$INSTALLER" -a claude -g >/dev/null
)
assert_file "CLAUDE_CONFIG_DIR overrides HOME" "$CUSTOM_CONFIG/settings.json"

# Merge preservation, legacy replacement, duplicate removal, backup, and mode preservation.
MERGE_REPO="$TMP_ROOT/merge-project"
make_repo "$MERGE_REPO"
mkdir -p "$MERGE_REPO/.claude"
cat > "$MERGE_REPO/.claude/settings.json" <<'JSON'
{
  "permissions": {"allow": ["Read"]},
  "env": {"EXAMPLE": "yes"},
  "hooks": {
    "Stop": [{"hooks": [{"type": "command", "command": "echo stop"}]}],
    "PreToolUse": [
      {
        "matcher": "Read",
        "hooks": [{"type": "command", "command": "node /tmp/hooks/protect-important-paths.js"}]
      },
      {
        "matcher": "Bash",
        "extra": "keep-me",
        "hooks": [
          {"type": "command", "command": "echo unrelated"},
          {"type": "command", "command": "node \"$(git rev-parse --show-toplevel)/hooks/protect-important-paths.js\"", "timeout": 5}
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [{"type": "command", "command": "node '/old/hooks/protect-important-paths.js'"}]
      }
    ]
  }
}
JSON
chmod 640 "$MERGE_REPO/.claude/settings.json"
ORIGINAL_MERGE="$TMP_ROOT/original-settings.json"
cp "$MERGE_REPO/.claude/settings.json" "$ORIGINAL_MERGE"
(
    cd "$MERGE_REPO"
    "$INSTALLER" --agent claude >/dev/null
)
MERGE_SETTINGS="$MERGE_REPO/.claude/settings.json"
assert_equal "duplicate better-rm Bash hooks collapse to one" "1" "$(hook_count "$MERGE_SETTINGS")"
assert_equal "existing settings mode is preserved" "640" "$(file_mode "$MERGE_SETTINGS")"
assert_equal "changed settings create one backup" "1" "$(backup_count "$MERGE_REPO/.claude" settings.json)"

BACKUP=$(find "$MERGE_REPO/.claude" -maxdepth 1 -type f -name 'settings.json.better-rm.bak.*' | head -n 1)
if cmp -s "$ORIGINAL_MERGE" "$BACKUP"; then
    pass "backup preserves original bytes"
else
    fail "backup preserves original bytes"
fi

if node - "$MERGE_SETTINGS" <<'NODE'
const s = require(process.argv[2]);
const bash = s.hooks.PreToolUse.filter((x) => x.matcher === 'Bash');
if (s.permissions.allow[0] !== 'Read') process.exit(1);
if (s.env.EXAMPLE !== 'yes') process.exit(1);
if (s.hooks.Stop[0].hooks[0].command !== 'echo stop') process.exit(1);
if (s.hooks.PreToolUse[0].matcher !== 'Read') process.exit(1);
if (bash[0].extra !== 'keep-me') process.exit(1);
if (!bash[0].hooks.some((x) => x.command === 'echo unrelated')) process.exit(1);
NODE
then
    pass "merge preserves unrelated settings and hooks"
else
    fail "merge preserves unrelated settings and hooks"
fi

# A second run is a byte-for-byte no-op and creates no backup.
BEFORE_HASH=$(node -e 'process.stdout.write(require("crypto").createHash("sha256").update(require("fs").readFileSync(process.argv[1])).digest("hex"))' "$MERGE_SETTINGS")
BEFORE_MTIME=$(file_mtime "$MERGE_SETTINGS")
BEFORE_BACKUPS=$(backup_count "$MERGE_REPO/.claude" settings.json)
sleep 1
(
    cd "$MERGE_REPO"
    "$INSTALLER" -a claude >/dev/null
)
AFTER_HASH=$(node -e 'process.stdout.write(require("crypto").createHash("sha256").update(require("fs").readFileSync(process.argv[1])).digest("hex"))' "$MERGE_SETTINGS")
assert_equal "idempotent run preserves file bytes" "$BEFORE_HASH" "$AFTER_HASH"
assert_equal "idempotent run preserves modification time" "$BEFORE_MTIME" "$(file_mtime "$MERGE_SETTINGS")"
assert_equal "idempotent run creates no backup" "$BEFORE_BACKUPS" "$(backup_count "$MERGE_REPO/.claude" settings.json)"

# Invalid settings fail without modifying their input.
for fixture in malformed array hooks pretool bashhooks; do
    INVALID_REPO="$TMP_ROOT/invalid-$fixture"
    make_repo "$INVALID_REPO"
    mkdir -p "$INVALID_REPO/.claude"
    case "$fixture" in
        malformed) printf '{bad json\n' > "$INVALID_REPO/.claude/settings.json" ;;
        array) printf '[]\n' > "$INVALID_REPO/.claude/settings.json" ;;
        hooks) printf '{"hooks": []}\n' > "$INVALID_REPO/.claude/settings.json" ;;
        pretool) printf '{"hooks": {"PreToolUse": {}}}\n' > "$INVALID_REPO/.claude/settings.json" ;;
        bashhooks) printf '{"hooks": {"PreToolUse": [{"matcher":"Bash","hooks":{}}]}}\n' > "$INVALID_REPO/.claude/settings.json" ;;
    esac
    INVALID_HASH=$(node -e 'process.stdout.write(require("crypto").createHash("sha256").update(require("fs").readFileSync(process.argv[1])).digest("hex"))' "$INVALID_REPO/.claude/settings.json")
    assert_failure "invalid $fixture settings fail safely" bash -c "cd '$INVALID_REPO' && '$INSTALLER' -a claude"
    assert_equal "invalid $fixture settings remain unchanged" "$INVALID_HASH" "$(node -e 'process.stdout.write(require("crypto").createHash("sha256").update(require("fs").readFileSync(process.argv[1])).digest("hex"))' "$INVALID_REPO/.claude/settings.json")"
done

# Symlink settings are rejected.
SYMLINK_REPO="$TMP_ROOT/symlink-project"
make_repo "$SYMLINK_REPO"
mkdir -p "$SYMLINK_REPO/.claude"
printf '{}\n' > "$TMP_ROOT/real-settings.json"
ln -s "$TMP_ROOT/real-settings.json" "$SYMLINK_REPO/.claude/settings.json"
assert_failure "symbolic-link settings are rejected" bash -c "cd '$SYMLINK_REPO' && '$INSTALLER' -a claude"

# Paths with spaces, quotes, and dollar signs are safely encoded and executable.
SPECIAL_SOURCE="$TMP_ROOT/source space's \$dir"
mkdir -p "$SPECIAL_SOURCE/hooks"
cp "$INSTALLER" "$SPECIAL_SOURCE/install-hooks.sh"
cp "$SCRIPT_DIR/hooks/protect-important-paths.js" "$SPECIAL_SOURCE/hooks/protect-important-paths.js"
chmod +x "$SPECIAL_SOURCE/install-hooks.sh"
SPECIAL_HOME="$TMP_ROOT/special-home"
HOME="$SPECIAL_HOME" CLAUDE_CONFIG_DIR= "$SPECIAL_SOURCE/install-hooks.sh" -a claude --global >/dev/null
SPECIAL_SETTINGS="$SPECIAL_HOME/.claude/settings.json"
SPECIAL_COMMAND=$(node -e 'const s=require(process.argv[1]); process.stdout.write(s.hooks.PreToolUse[0].hooks[0].command)' "$SPECIAL_SETTINGS")
if printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"rm -rf .git"},"cwd":"/workspace/project"}' | bash -c "$SPECIAL_COMMAND" | grep -q '"permissionDecision":"deny"'; then
    pass "special-character hook path executes blocked payload"
else
    fail "special-character hook path executes blocked payload"
fi
if printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"rm file.txt"},"cwd":"/workspace/project"}' | bash -c "$SPECIAL_COMMAND" >/dev/null; then
    pass "installed hook accepts harmless payload"
else
    fail "installed hook accepts harmless payload"
fi

# A readable but stale runtime hook must be refreshed. Keeping it means a hook
# security fix lives only in the source checkout and never reaches the agent.
STALE_HOME="$TMP_ROOT/stale-home"
mkdir -p "$STALE_HOME/.claude"
STALE_HOOK="$STALE_HOME/.claude/protect-important-paths.js"
printf '#!/usr/bin/env node\n// stale hook without the security fix\n' > "$STALE_HOOK"
printf '{"env":{"KEEP_ME":"yes"}}\n' > "$STALE_HOME/.claude/settings.json"
STALE_HOOK_HASH=$(file_hash "$STALE_HOOK")
(
    cd "$TMP_ROOT"
    HOME="$STALE_HOME" CLAUDE_CONFIG_DIR= "$INSTALLER" -a claude --global >/dev/null
)
assert_equal "stale runtime hook is refreshed from source" \
    "$(file_hash "$SCRIPT_DIR/hooks/protect-important-paths.js")" \
    "$(file_hash "$STALE_HOOK")"
STALE_BACKUP=$(find "$STALE_HOME/.claude" -maxdepth 1 -name 'protect-important-paths.js.better-rm.bak.*' | head -1)
if [ -n "$STALE_BACKUP" ] && [ "$(file_hash "$STALE_BACKUP")" = "$STALE_HOOK_HASH" ]; then
    pass "stale runtime hook is backed up before replacement"
else
    fail "stale runtime hook is backed up before replacement"
fi
assert_equal "unrelated settings survive the runtime hook refresh" "yes" \
    "$(node -e 'process.stdout.write(String(require(process.argv[1]).env.KEEP_ME))' "$STALE_HOME/.claude/settings.json")"
assert_equal "refreshed runtime hook is registered once" "1" "$(hook_count "$STALE_HOME/.claude/settings.json")"
(
    cd "$TMP_ROOT"
    HOME="$STALE_HOME" CLAUDE_CONFIG_DIR= "$INSTALLER" -a claude --global >/dev/null
)
assert_equal "an up-to-date runtime hook is not rewritten or re-backed-up" "1" \
    "$(find "$STALE_HOME/.claude" -maxdepth 1 -name 'protect-important-paths.js.better-rm.bak.*' | wc -l | tr -d ' ')"

# The refresh must not depend on `stat`: its flags are not portable between BSD
# and GNU userland. GNU `stat -f` means FILE SYSTEM status and takes the format
# only via -c/--printf, so `stat -f '%Lp' FILE` treats '%Lp' as a second operand:
# it reports an error for that name on stderr and exits 1, yet still prints
# FILE's filesystem block on stdout. A BSD-first probe therefore does fall
# through to its `|| stat -c '%a'` fallback, and the command substitution
# captures BOTH outputs, so the chmod built from them fails mid-install. This
# shim reproduces that shape on any platform.
STAT_HOME="$TMP_ROOT/hostile-stat-home"
mkdir -p "$STAT_HOME/.claude"
STAT_HOOK="$STAT_HOME/.claude/protect-important-paths.js"
printf '#!/usr/bin/env node\n// stale hook, hostile stat\n' > "$STAT_HOOK"
printf '{"env":{"KEEP_ME":"yes"}}\n' > "$STAT_HOME/.claude/settings.json"
chmod 600 "$STAT_HOOK"
STAT_SHIM_BIN="$TMP_ROOT/hostile-stat-bin"
mkdir -p "$STAT_SHIM_BIN"
cat > "$STAT_SHIM_BIN/stat" <<'EOF'
#!/bin/sh
# Mimics GNU stat receiving BSD flags: -f is filesystem mode, the format string
# is taken as a filename operand, so the error goes to stderr with exit 1 while
# the other operand's filesystem block still goes to stdout.
if [ "$1" = "-f" ]; then
    echo "stat: cannot read file system information for '$2': No such file or directory" >&2
    printf '%s\n' "  File: \"$3\"" "Block size: 4096" "Blocks: Total: 1 Free: 1"
    exit 1
fi
# The GNU spelling of "print the mode" still works, which is what makes the
# fallback succeed and the captured output a concatenation of both.
printf '%s\n' '644'
exit 0
EOF
chmod +x "$STAT_SHIM_BIN/stat"
if (
    cd "$TMP_ROOT"
    PATH="$STAT_SHIM_BIN:$PATH" HOME="$STAT_HOME" CLAUDE_CONFIG_DIR= "$INSTALLER" -a claude --global >/dev/null 2>&1
); then
    pass "install does not depend on a platform-specific stat"
else
    fail "install does not depend on a platform-specific stat"
fi
assert_equal "stale hook is refreshed even with a hostile stat" \
    "$(file_hash "$SCRIPT_DIR/hooks/protect-important-paths.js")" "$(file_hash "$STAT_HOOK")"
assert_equal "refreshed runtime hook keeps its original mode" "600" "$(file_mode "$STAT_HOOK")"

# Registration must happen before the runtime hook is replaced. Otherwise a
# failure between the two leaves a new hook on disk that nothing invokes — the
# agent silently loses its guard. Fail the settings merge and require that the
# runtime hook and the settings are both exactly as they were.
HALF_HOME="$TMP_ROOT/half-install-home"
mkdir -p "$HALF_HOME/.claude"
HALF_HOOK="$HALF_HOME/.claude/protect-important-paths.js"
printf '#!/usr/bin/env node\n// stale hook, merge will fail\n' > "$HALF_HOOK"
printf '{"env":{"KEEP_ME":"yes"}}\n' > "$HALF_HOME/.claude/settings.json"
HALF_HOOK_HASH=$(file_hash "$HALF_HOOK")
HALF_SETTINGS_HASH=$(file_hash "$HALF_HOME/.claude/settings.json")
FAILING_NODE_BIN="$TMP_ROOT/failing-node-bin"
mkdir -p "$FAILING_NODE_BIN"
REAL_NODE=$(command -v node)
cat > "$FAILING_NODE_BIN/node" <<EOF
#!/bin/sh
# Fail ONLY the settings merge, which is the sole \`node -\` (script on stdin)
# invocation. A blunt always-fail shim would also break the installer's own
# check that the freshly written hook still denies, so the install would abort
# inside the refresh instead of before it, and the ordering under test would
# never be exercised at all.
if [ "\$1" = "-" ]; then
    echo "simulated node failure" >&2
    exit 1
fi
exec "$REAL_NODE" "\$@"
EOF
chmod +x "$FAILING_NODE_BIN/node"
if (
    cd "$TMP_ROOT"
    PATH="$FAILING_NODE_BIN:$PATH" HOME="$HALF_HOME" CLAUDE_CONFIG_DIR= "$INSTALLER" -a claude --global >/dev/null 2>&1
); then
    fail "a failed settings merge aborts the install"
else
    pass "a failed settings merge aborts the install"
fi
assert_equal "a failed settings merge leaves the runtime hook untouched" \
    "$HALF_HOOK_HASH" "$(file_hash "$HALF_HOOK")"
assert_equal "a failed settings merge leaves the settings untouched" \
    "$HALF_SETTINGS_HASH" "$(file_hash "$HALF_HOME/.claude/settings.json")"
assert_equal "a failed settings merge leaves no hook backup behind" "0" \
    "$(find "$HALF_HOME/.claude" -maxdepth 1 -name 'protect-important-paths.js.better-rm.bak.*' | wc -l | tr -d ' ')"

# A hook that exits 0 with no output is an ALLOW under every agent contract in
# this repo, so a truncated or 0-byte runtime hook does not merely fail to
# update — it disarms the guard completely. That state must be unreachable no
# matter which write fails, and it is worse than the stale hook being replaced.
hook_is_permissive() {
    local out status
    out=$(printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"rm -rf /"},"cwd":"/"}' | node "$1" 2>/dev/null)
    status=$?
    if [ "$status" -eq 0 ] && ! printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then
        return 0
    fi
    return 1
}

DISARM_HOME="$TMP_ROOT/disarm-home"
mkdir -p "$DISARM_HOME/.claude"
DISARM_HOOK="$DISARM_HOME/.claude/protect-important-paths.js"
printf '#!/usr/bin/env node\n// stale hook, every write will fail\n' > "$DISARM_HOOK"
printf '{"env":{"KEEP_ME":"yes"}}\n' > "$DISARM_HOME/.claude/settings.json"
FAILING_CAT_BIN="$TMP_ROOT/failing-cat-bin"
mkdir -p "$FAILING_CAT_BIN"
cat > "$FAILING_CAT_BIN/cat" <<'EOF'
#!/bin/sh
# The shell truncated the redirect target before this ran, so failing here is
# exactly the shape of a half-completed write: the destination is now empty.
exit 1
EOF
chmod +x "$FAILING_CAT_BIN/cat"
if (
    cd "$TMP_ROOT"
    PATH="$FAILING_CAT_BIN:$PATH" HOME="$DISARM_HOME" CLAUDE_CONFIG_DIR= "$INSTALLER" -a claude --global >/dev/null 2>&1
); then
    fail "a failed hook write aborts the install"
else
    pass "a failed hook write aborts the install"
fi
if hook_is_permissive "$DISARM_HOOK"; then
    fail "a failed hook write never leaves an allow-everything hook"
else
    pass "a failed hook write never leaves an allow-everything hook"
fi
assert_equal "a failed hook write keeps a backup to recover from" "1" \
    "$(find "$DISARM_HOME/.claude" -maxdepth 1 -name 'protect-important-paths.js.better-rm.bak.*' | wc -l | tr -d ' ')"
DISARM_BACKUP=$(find "$DISARM_HOME/.claude" -maxdepth 1 -name 'protect-important-paths.js.better-rm.bak.*' | head -1)
assert_contains "the recoverable backup holds the previous hook" "$(cat "$DISARM_BACKUP")" "stale hook, every write will fail"

# The dangerous shape is a write that REPORTS SUCCESS while leaving the file
# empty or partial: nothing in the exit status betrays it, so the install would
# happily declare victory over a hook that allows everything. The only way to
# know is to run the freshly written hook and require it to still deny.
SILENT_HOME="$TMP_ROOT/silent-truncation-home"
mkdir -p "$SILENT_HOME/.claude"
SILENT_HOOK="$SILENT_HOME/.claude/protect-important-paths.js"
printf '#!/usr/bin/env node\n// stale hook, writes silently truncate\n' > "$SILENT_HOOK"
printf '{"env":{"KEEP_ME":"yes"}}\n' > "$SILENT_HOME/.claude/settings.json"
SILENT_CAT_BIN="$TMP_ROOT/silent-cat-bin"
mkdir -p "$SILENT_CAT_BIN"
cat > "$SILENT_CAT_BIN/cat" <<'EOF'
#!/bin/sh
# Writes nothing and reports success: the redirect target has already been
# truncated by the shell, so the caller sees exit 0 over an empty file.
exit 0
EOF
chmod +x "$SILENT_CAT_BIN/cat"
if (
    cd "$TMP_ROOT"
    PATH="$SILENT_CAT_BIN:$PATH" HOME="$SILENT_HOME" CLAUDE_CONFIG_DIR= "$INSTALLER" -a claude --global >/dev/null 2>&1
); then
    fail "a silently truncated hook write is not reported as success"
else
    pass "a silently truncated hook write is not reported as success"
fi
if hook_is_permissive "$SILENT_HOOK"; then
    fail "a silently truncated hook write never leaves an allow-everything hook"
else
    pass "a silently truncated hook write never leaves an allow-everything hook"
fi

# The restore-succeeded branch: the write fails but the restore works, so the
# installer falls back to the PREVIOUS hook. Matching the backup byte for byte
# says nothing about whether that backup was ever a working hook — and the most
# likely reason someone re-runs the installer is to repair a hook that is
# already broken. Both shapes of a broken predecessor are pinned here.
restore_branch_case() { # name, writer, expectation label
    local name="$1" writer="$2"
    local home="$TMP_ROOT/$name"
    mkdir -p "$home/.claude"
    local hook="$home/.claude/protect-important-paths.js"
    "$writer" "$hook"
    printf '{"env":{"KEEP_ME":"yes"}}\n' > "$home/.claude/settings.json"
    (
        cd "$TMP_ROOT"
        PATH="$SOURCE_READ_FAILS_BIN:$PATH" HOME="$home" CLAUDE_CONFIG_DIR= "$INSTALLER" -a claude --global >/dev/null 2>&1
    )
    printf '%s' "$hook"
}
write_empty_hook() { : > "$1"; }
write_permissive_hook() {
    printf '%s\n' '#!/usr/bin/env node' \
        '// syntactically valid leftover that allows everything' \
        'process.stdin.resume();' \
        'process.stdin.on("end", () => process.exit(0));' > "$1"
}

# `cat` fails only when reading the hook SOURCE, so the write fails while the
# restore from the backup still succeeds — the shape of a full disk.
SOURCE_READ_FAILS_BIN="$TMP_ROOT/source-read-fails-bin"
mkdir -p "$SOURCE_READ_FAILS_BIN"
cat > "$SOURCE_READ_FAILS_BIN/cat" <<'EOF'
#!/bin/sh
case "$1" in
    */hooks/protect-important-paths.js) exit 1 ;;
esac
exec /bin/cat "$@"
EOF
chmod +x "$SOURCE_READ_FAILS_BIN/cat"

EMPTY_PREDECESSOR=$(restore_branch_case restore-empty-predecessor write_empty_hook)
if hook_is_permissive "$EMPTY_PREDECESSOR"; then
    fail "restoring a 0-byte predecessor never ends at allow-everything"
else
    pass "restoring a 0-byte predecessor never ends at allow-everything"
fi
PERMISSIVE_PREDECESSOR=$(restore_branch_case restore-permissive-predecessor write_permissive_hook)
if hook_is_permissive "$PERMISSIVE_PREDECESSOR"; then
    fail "restoring a valid-but-permissive predecessor never ends at allow-everything"
else
    pass "restoring a valid-but-permissive predecessor never ends at allow-everything"
fi

# When only the SELF-CHECK cannot run, the freshly written file is already the
# known-good source. Restoring the predecessor over it would replace a correct
# hook with a broken one, so the probe failure must be distinguished from a
# hook failure by running the same probe against the source as a control.
PROBE_HOME="$TMP_ROOT/probe-unavailable-home"
mkdir -p "$PROBE_HOME/.claude"
PROBE_HOOK="$PROBE_HOME/.claude/protect-important-paths.js"
write_empty_hook "$PROBE_HOOK"
printf '{"env":{"KEEP_ME":"yes"}}\n' > "$PROBE_HOME/.claude/settings.json"
PROBE_SHIM_BIN="$TMP_ROOT/probe-unavailable-bin"
mkdir -p "$PROBE_SHIM_BIN"
cat > "$PROBE_SHIM_BIN/node" <<EOF
#!/bin/sh
# Everything node does works EXCEPT running the hook self-check.
if [ "\$1" = "-" ]; then exec "$REAL_NODE" "\$@"; fi
exit 1
EOF
chmod +x "$PROBE_SHIM_BIN/node"
if (
    cd "$TMP_ROOT"
    PATH="$PROBE_SHIM_BIN:$PATH" HOME="$PROBE_HOME" CLAUDE_CONFIG_DIR= "$INSTALLER" -a claude --global >/dev/null 2>&1
); then
    pass "an unavailable self-check does not fail an otherwise correct install"
else
    fail "an unavailable self-check does not fail an otherwise correct install"
fi
assert_equal "an unavailable self-check keeps the freshly written hook" \
    "$(file_hash "$SCRIPT_DIR/hooks/protect-important-paths.js")" "$(file_hash "$PROBE_HOOK")"
if hook_is_permissive "$PROBE_HOOK"; then
    fail "an unavailable self-check never restores a permissive predecessor"
else
    pass "an unavailable self-check never restores a permissive predecessor"
fi

# A failing backup copy aborts under `set -e` BEFORE any of the hardening above
# can run, leaving whatever was on disk registered and in place. On a full disk
# that is exactly the 0-byte hook someone re-ran the installer to repair, so the
# repair attempt silently leaves the guard disarmed. The shim fails only the
# timestamped backup copy, which is the shape a real ENOSPC produces here.
FAILING_CP_BIN="$TMP_ROOT/failing-backup-cp-bin"
mkdir -p "$FAILING_CP_BIN"
cat > "$FAILING_CP_BIN/cp" <<'EOF'
#!/bin/sh
for arg in "$@"; do
    case "$arg" in
        *.better-rm.bak.*)
            echo "cp: $arg: No space left on device" >&2
            exit 1
            ;;
    esac
done
exec /bin/cp "$@"
EOF
chmod +x "$FAILING_CP_BIN/cp"

backup_failure_case() { # name, writer -> prints hook path
    local name="$1" writer="$2"
    local home="$TMP_ROOT/$name"
    mkdir -p "$home/.claude"
    local hook="$home/.claude/protect-important-paths.js"
    "$writer" "$hook"
    printf '{"env":{"KEEP_ME":"yes"}}\n' > "$home/.claude/settings.json"
    (
        cd "$TMP_ROOT"
        PATH="$FAILING_CP_BIN:$PATH" HOME="$home" CLAUDE_CONFIG_DIR= "$INSTALLER" -a claude --global >/dev/null 2>&1
    )
    printf '%s' "$hook"
}
BACKUP_FAIL_HOOK=$(backup_failure_case backup-cp-fails write_empty_hook)
if hook_is_permissive "$BACKUP_FAIL_HOOK"; then
    fail "a failing backup copy never leaves a permissive hook registered"
else
    pass "a failing backup copy never leaves a permissive hook registered"
fi

# ... but a predecessor that DOES deny must not be downgraded to the stub just
# because the backup could not be written: nothing was touched, so the working
# hook stays exactly as it was.
write_working_variant_hook() {
    cat "$SCRIPT_DIR/hooks/protect-important-paths.js" > "$1"
    printf '\n// older but working runtime hook\n' >> "$1"
}
WORKING_PREDECESSOR=$(backup_failure_case backup-cp-fails-working write_working_variant_hook)
if hook_is_permissive "$WORKING_PREDECESSOR"; then
    fail "a failing backup copy leaves a working predecessor untouched"
else
    assert_contains "a failing backup copy leaves a working predecessor untouched" \
        "$(cat "$WORKING_PREDECESSOR")" "older but working runtime hook"
fi

# When even the stub cannot be written, the predecessor is what stays on disk.
# Claiming "it now fails closed" there would send the user away believing they
# are protected, so the message must say the opposite.
READONLY_HOME="$TMP_ROOT/readonly-hook-home"
mkdir -p "$READONLY_HOME/.claude"
READONLY_HOOK="$READONLY_HOME/.claude/protect-important-paths.js"
write_empty_hook "$READONLY_HOOK"
printf '{"env":{"KEEP_ME":"yes"}}\n' > "$READONLY_HOME/.claude/settings.json"
chmod 444 "$READONLY_HOOK"
READONLY_OUTPUT=$(
    cd "$TMP_ROOT"
    HOME="$READONLY_HOME" CLAUDE_CONFIG_DIR= "$INSTALLER" -a claude --global 2>&1 || true
)
chmod 644 "$READONLY_HOOK"
if printf '%s' "$READONLY_OUTPUT" | grep -q 'may allow everything'; then
    pass "an unwritable stub is reported as unverified, not as fail-closed"
else
    fail "an unwritable stub is reported as unverified, not as fail-closed"
fi
if printf '%s' "$READONLY_OUTPUT" | grep -q 'it now fails closed'; then
    fail "an unwritable stub never claims the hook fails closed"
else
    pass "an unwritable stub never claims the hook fails closed"
fi

# ---------------------------------------------------------------------------
# Release download boundary
# ---------------------------------------------------------------------------
# 測試套件不得依賴外部服務：這裡把 curl/wget 這個網路邊界換成本機替身，
# 由 RELEASE_ASSET_DIR 提供 Release 資產。之前的版本沒有 stub，跑一次 gate
# 就等於對 GitHub Release 發一次真實請求 —— 離線就紅、上游改版就紅，而且測不到
# 「下載內容被竄改」這種真正該測的情境。
# The suite must not depend on an external service. curl/wget — the network
# boundary — are replaced with local shims served from RELEASE_ASSET_DIR.
# BETTER_RM_TEST_RELEASE_BODY overrides the payload so a tampered or truncated
# download can be reproduced, which a live download can never test.
RELEASE_ASSET_DIR="$TMP_ROOT/release-assets"
mkdir -p "$RELEASE_ASSET_DIR"
cp "$SCRIPT_DIR/hooks/protect-important-paths.js" "$RELEASE_ASSET_DIR/protect-important-paths.js"
cp "$SCRIPT_DIR/.opencode/plugins/protect-important-paths.ts" \
    "$RELEASE_ASSET_DIR/opencode-protect-important-paths.ts"

RELEASE_STUB_BIN="$TMP_ROOT/release-stub-bin"
mkdir -p "$RELEASE_STUB_BIN"
cat > "$RELEASE_STUB_BIN/curl" <<'EOF'
#!/bin/bash
url=""
out=""
while [ $# -gt 0 ]; do
    case "$1" in
        -o) out="$2"; shift 2 ;;
        -*) shift ;;
        *) url="$1"; shift ;;
    esac
done
printf '%s\n' "$url" >> "${BETTER_RM_TEST_RELEASE_LOG:-/dev/null}"
if [ -n "${BETTER_RM_TEST_RELEASE_BODY:-}" ]; then
    printf '%s' "$BETTER_RM_TEST_RELEASE_BODY" > "$out"
    exit 0
fi
src="$BETTER_RM_TEST_RELEASE_DIR/${url##*/}"
[ -f "$src" ] || exit 22
/bin/cat "$src" > "$out"
EOF
cat > "$RELEASE_STUB_BIN/wget" <<'EOF'
#!/bin/bash
url=""
out=""
while [ $# -gt 0 ]; do
    case "$1" in
        -qO) out="$2"; shift 2 ;;
        -*) shift ;;
        *) url="$1"; shift ;;
    esac
done
printf '%s\n' "$url" >> "${BETTER_RM_TEST_RELEASE_LOG:-/dev/null}"
if [ -n "${BETTER_RM_TEST_RELEASE_BODY:-}" ]; then
    printf '%s' "$BETTER_RM_TEST_RELEASE_BODY" > "$out"
    exit 0
fi
src="$BETTER_RM_TEST_RELEASE_DIR/${url##*/}"
[ -f "$src" ] || exit 8
/bin/cat "$src" > "$out"
EOF
chmod +x "$RELEASE_STUB_BIN/curl" "$RELEASE_STUB_BIN/wget"

# Missing shared hook fails before touching settings.
MISSING_SOURCE="$TMP_ROOT/missing-source"
mkdir -p "$MISSING_SOURCE"
cp "$INSTALLER" "$MISSING_SOURCE/install-hooks.sh"
chmod +x "$MISSING_SOURCE/install-hooks.sh"
MISSING_HOME="$TMP_ROOT/missing-home"
RELEASE_DOWNLOAD_LOG="$TMP_ROOT/release-download.log"
assert_success "missing shared hook installs from release" \
    env PATH="$RELEASE_STUB_BIN:$PATH" \
        BETTER_RM_TEST_RELEASE_DIR="$RELEASE_ASSET_DIR" \
        BETTER_RM_TEST_RELEASE_LOG="$RELEASE_DOWNLOAD_LOG" \
        HOME="$MISSING_HOME" CLAUDE_CONFIG_DIR= "$MISSING_SOURCE/install-hooks.sh" -a claude --global
assert_file "missing shared hook creates settings" "$MISSING_HOME/.claude/settings.json"
assert_file "missing shared hook installs local runtime" "$MISSING_HOME/.claude/protect-important-paths.js"
# 這行是「stub 真的被走到」的證據：沒有它，上面三個斷言就算改回打真網路也照樣綠。
# Proof the stub was actually exercised; without it the assertions above would
# stay green even if the download went back to hitting the network.
assert_contains "the release download went through the stubbed boundary" \
    "$(cat "$RELEASE_DOWNLOAD_LOG")" "releases/latest/download/protect-important-paths.js"

echo ""
echo "========================================"
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo "========================================"

if [ "$FAILED" -ne 0 ]; then
    exit 1
fi
