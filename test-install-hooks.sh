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

assert_not_contains() {
    local name="$1"
    local haystack="$2"
    local needle="$3"
    if printf '%s\n' "$haystack" | grep -q "$needle"; then
        fail "$name"
    else
        pass "$name"
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

# 第一次安裝（目的地本來就沒有 hook）在同一情況下必須說一樣的話。
# hook_is_trustworthy 在探測跑不起來時退化成「與來源位元組相同」，那抓得到截斷的
# 複製，但抓不到「來源自己不擋」。refresh 路徑會明講，第一次安裝若沉默，一台沒有可
# 用 node 的機器就會拿到一個「看起來通過行為驗證、其實只做了 cmp」的安裝。
# The first install — destination hook absent — has to say the same thing in the
# same situation. hook_is_trustworthy degrades to "byte-identical to the source"
# when the probe cannot run: that catches a truncated copy but not a source that
# fails to deny. The refresh path says so; a silent first install would hand a
# machine with no usable node an install that looks behaviourally verified when
# only a cmp had run.
FIRST_PROBE_HOME="$TMP_ROOT/first-install-probe-home"
mkdir -p "$FIRST_PROBE_HOME/.claude"
printf '{"env":{"KEEP_ME":"yes"}}\n' > "$FIRST_PROBE_HOME/.claude/settings.json"
FIRST_PROBE_OUT="$TMP_ROOT/first-install-probe.out"
(
    cd "$TMP_ROOT"
    PATH="$PROBE_SHIM_BIN:$PATH" HOME="$FIRST_PROBE_HOME" CLAUDE_CONFIG_DIR= "$INSTALLER" -a claude --global
) > "$FIRST_PROBE_OUT" 2>&1
if grep -q "self-check" "$FIRST_PROBE_OUT"; then
    pass "a first install reports that the self-check could not run"
else
    fail "a first install reports that the self-check could not run"
fi
assert_equal "a first install without a self-check still writes the source hook" \
    "$(file_hash "$SCRIPT_DIR/hooks/protect-important-paths.js")" \
    "$(file_hash "$FIRST_PROBE_HOME/.claude/protect-important-paths.js")"

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

# PreToolUse 的完整契約：只有 exit 2、或 exit 0 且印出 deny，才算「擋下」。
# 其餘一律是放行 —— 包含 SyntaxError 這種非零結束，本專案自己的註解就說那是
# 「非阻擋錯誤」，工具照樣執行。hook_is_permissive 只認得 exit 0 那一種形狀，
# 所以驗「下載回來的 HTML」時會誤判成安全，這裡需要完整的契約。
# The full PreToolUse contract: only exit 2, or exit 0 with a deny, blocks.
# Everything else allows, including a SyntaxError's non-zero exit, which this
# repo's own comments call a NON-blocking error. hook_is_permissive only knows
# the exit-0 shape, so it would call a downloaded HTML page safe.
hook_allows_protected_deletion() {
    local out status
    out=$(printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"rm -rf /"},"cwd":"/"}' | node "$1" 2>/dev/null)
    status=$?
    if [ "$status" -eq 2 ]; then
        return 1
    fi
    if [ "$status" -eq 0 ] && printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then
        return 1
    fi
    return 0
}

# 下載回來的 hook 完全沒有被驗證。captive portal 的登入頁、被截斷的回應、CDN 的
# 錯誤頁，都會原封不動被裝成 runtime SAFETY hook：安裝 exit 0、毫無警告，之後每
# 次呼叫都 SyntaxError，也就是安靜地放行一切。
# The downloaded hook is not verified at all. A captive-portal page, a truncated
# body or a CDN error page is installed verbatim as the runtime SAFETY hook: the
# install exits 0 with no warning and every later invocation SyntaxErrors, which
# is a silent allow-everything.
CAPTIVE_SOURCE="$TMP_ROOT/captive-portal-source"
mkdir -p "$CAPTIVE_SOURCE"
cp "$INSTALLER" "$CAPTIVE_SOURCE/install-hooks.sh"
chmod +x "$CAPTIVE_SOURCE/install-hooks.sh"
CAPTIVE_HOME="$TMP_ROOT/captive-portal-home"
CAPTIVE_HOOK="$CAPTIVE_HOME/.claude/protect-important-paths.js"
CAPTIVE_STATUS=0
CAPTIVE_OUTPUT=$(
    env PATH="$RELEASE_STUB_BIN:$PATH" \
        BETTER_RM_TEST_RELEASE_DIR="$RELEASE_ASSET_DIR" \
        BETTER_RM_TEST_RELEASE_BODY='<html><head><title>Sign in to continue</title></head><body>Wi-Fi login required</body></html>' \
        HOME="$CAPTIVE_HOME" CLAUDE_CONFIG_DIR= "$CAPTIVE_SOURCE/install-hooks.sh" -a claude --global 2>&1
) || CAPTIVE_STATUS=$?
if [ "$CAPTIVE_STATUS" -ne 0 ]; then
    pass "a tampered release download aborts the install"
else
    fail "a tampered release download aborts the install"
fi
# 訊息必須指出是「下載回來的東西不會擋」，而不是含糊的失敗：這條路徑上使用者能做
# 的補救（換網路重試）完全取決於他看不看得懂發生什麼事。
# The message has to name the actual problem — the download does not block —
# because the only remedy on this path (change network, retry) depends on it.
assert_contains "a tampered release download says why it aborted" \
    "$CAPTIVE_OUTPUT" "does not block protected deletions"
if [ -f "$CAPTIVE_HOOK" ] && grep -q 'Wi-Fi login required' "$CAPTIVE_HOOK"; then
    fail "a tampered release download is never installed as the runtime hook"
else
    pass "a tampered release download is never installed as the runtime hook"
fi
if [ ! -f "$CAPTIVE_HOME/.claude/settings.json" ]; then
    pass "a tampered release download never leaves an allow-everything hook registered"
elif [ -f "$CAPTIVE_HOOK" ] && ! hook_allows_protected_deletion "$CAPTIVE_HOOK"; then
    pass "a tampered release download never leaves an allow-everything hook registered"
else
    fail "a tampered release download never leaves an allow-everything hook registered"
fi

# ---------------------------------------------------------------------------
# OpenCode plugin provenance
# ---------------------------------------------------------------------------
# 外掛是「讓 OpenCode 去呼叫已驗證 runtime hook」的橋接層：外掛壞掉等於 OpenCode
# 底下完全沒有保護，而安裝程式照樣回報成功。發佈物裡沒有 `.opencode/` 時（單獨拿
# 到 install-hooks.sh 的那種安裝方式），外掛以前是去 Release 下載的，而下載回來的
# 東西只被檢查「是可讀的一般檔案」——captive portal 的 HTML、被截斷的 body、以及
# 語法正確但根本不註冊任何 hook 的 TypeScript，全都會被原封不動複製到專案的執行
# 位置，exit 0、毫無警告，之後也沒有任何刪除防護。
# runtime hook 那條路已經有行為驗證，外掛這條沒有：外掛是 TypeScript，安裝程式並
# 不要求 TypeScript runtime，所以驗不了。因此改成把外掛與安裝程式綁成同一份可信
# 發佈物——外掛內嵌在 install-hooks.sh 裡，那條被汙染的通道整條消失。
# 這裡的斷言刻意分成三種，因為它們保護的是三件不同的事：
#   (A) 執行位置上的外掛永遠不是網路來的東西（真正的安全性質）；
#   (B) 根本不會為了取得外掛去打網路（「同一份可信發佈物」的可觀測形式）；
#   (C) 正常路徑沒有被這道防線一起否決——安裝仍然成功，且裝上去的是正確的外掛。
# The plugin is the bridge that makes OpenCode call the verified runtime hook, so a
# broken plugin means no protection under OpenCode at all, reported as success.
# When the distribution has no `.opencode/` (the standalone install-hooks.sh shape)
# the plugin used to be downloaded from the release and only checked for "readable
# regular file", so a captive-portal page, a truncated body, and syntactically valid
# TypeScript that registers no hook were all copied verbatim to the executing
# location: exit 0, no warning, no deletion protection afterwards.
# The runtime hook's download is verified behaviourally; the plugin's could not be,
# because it is TypeScript and the installer does not require a TypeScript runtime.
# The plugin is therefore bundled into install-hooks.sh instead, which removes the
# poisoned channel rather than inspecting what comes out of it.
# The three assertion shapes guard three different things:
#   (A) the plugin at the executing location is never network content (the security
#       property itself, which holds whichever fix is chosen);
#   (B) the network is not consulted for the plugin at all (the observable form of
#       "one trusted distribution");
#   (C) the normal path is not denied along with the bad ones — the install still
#       succeeds and the plugin it lands is the genuine one.
OPENCODE_DIST="$TMP_ROOT/opencode-bundled-dist"
mkdir -p "$OPENCODE_DIST/hooks"
cp "$INSTALLER" "$OPENCODE_DIST/install-hooks.sh"
chmod +x "$OPENCODE_DIST/install-hooks.sh"
cp "$SCRIPT_DIR/hooks/protect-important-paths.js" "$OPENCODE_DIST/hooks/protect-important-paths.js"
# 刻意不放 .opencode/：這正是會觸發外掛下載的發佈物形狀。
# Deliberately no .opencode/: this is the distribution shape that triggered the
# plugin download.
OPENCODE_GENUINE_PLUGIN_HASH=$(file_hash "$SCRIPT_DIR/.opencode/plugins/protect-important-paths.ts")

# $1 label, $2 poisoned release body, $3 a string that only the poisoned body contains
assert_opencode_plugin_provenance() {
    local label="$1"
    local body="$2"
    local marker="$3"

    local project="$TMP_ROOT/opencode-provenance-$label"
    make_repo "$project"
    local log="$TMP_ROOT/opencode-provenance-$label.log"
    : > "$log"
    local plugin="$project/.opencode/plugins/protect-important-paths.ts"

    local status=0
    (
        cd "$project" &&
        env PATH="$RELEASE_STUB_BIN:$PATH" \
            BETTER_RM_TEST_RELEASE_DIR="$RELEASE_ASSET_DIR" \
            BETTER_RM_TEST_RELEASE_LOG="$log" \
            BETTER_RM_TEST_RELEASE_BODY="$body" \
            HOME="$TMP_ROOT/opencode-provenance-home-$label" CLAUDE_CONFIG_DIR= \
            "$OPENCODE_DIST/install-hooks.sh" -a opencode
    ) >/dev/null 2>&1 || status=$?

    if [ -f "$plugin" ] && grep -q "$marker" "$plugin"; then
        fail "opencode plugin is never the tampered download ($label)"
    else
        pass "opencode plugin is never the tampered download ($label)"
    fi

    assert_not_contains "opencode plugin is never fetched over the network ($label)" \
        "$(cat "$log")" "opencode-protect-important-paths.ts"

    if [ "$status" -eq 0 ] && [ -f "$plugin" ] &&
       [ "$(file_hash "$plugin")" = "$OPENCODE_GENUINE_PLUGIN_HASH" ]; then
        pass "opencode install lands the genuine plugin regardless of the release body ($label)"
    else
        fail "opencode install lands the genuine plugin regardless of the release body ($label)"
    fi
}

assert_opencode_plugin_provenance 'captive-portal' \
    '<html><head><title>Sign in to continue</title></head><body>Wi-Fi login required</body></html>' \
    'Wi-Fi login required'

# 截斷：前綴完全是合法外掛，只是 body 在中途斷掉。位元組層級的檢查（大小、可讀）
# 抓不到，語法上也「看起來像那個檔案」。
# Truncated: the prefix is the genuine plugin, the body just stops mid-statement.
# Size/readability checks cannot see it and it still "looks like" the real file.
assert_opencode_plugin_provenance 'truncated' \
    'import type { Plugin } from "@opencode-ai/plugin";
// @ts-ignore
import { evaluate } from "../../hooks/protect-important-paths";

export const ProtectImportantPathsPlugin: Plugin = async (ctx) => {
  return {
    "tool.execute.before": async (input, output) => {
      if (input.tool === "bash") {
        const comm' \
    'const comm$'

# 語法正確、型別正確、export 名稱一模一樣，就是不註冊任何 hook。這是 checksum 之外
# 的那一類：檔案完好無損地抵達，內容卻什麼都不保護。
# Syntactically and structurally valid, same export names, registers no hook. This
# is the class a checksum cannot address: the file arrives intact and protects
# nothing.
assert_opencode_plugin_provenance 'registers-no-hook' \
    'import type { Plugin } from "@opencode-ai/plugin";

export const ProtectImportantPathsPlugin: Plugin = async (ctx) => {
  return {};
};

export default ProtectImportantPathsPlugin;' \
    'return {};'

# 網路整條不通（Release 上沒有這個 asset、或離線）也必須照裝：外掛既然隨安裝程式
# 一起出貨，就不該有任何理由依賴網路。
# A dead network (asset missing from the release, or offline) must still install:
# once the plugin ships with the installer there is no reason to need the network.
OPENCODE_OFFLINE_PROJECT="$TMP_ROOT/opencode-offline-project"
make_repo "$OPENCODE_OFFLINE_PROJECT"
OPENCODE_OFFLINE_EMPTY_ASSETS="$TMP_ROOT/opencode-offline-empty-assets"
mkdir -p "$OPENCODE_OFFLINE_EMPTY_ASSETS"
OPENCODE_OFFLINE_PLUGIN="$OPENCODE_OFFLINE_PROJECT/.opencode/plugins/protect-important-paths.ts"
OPENCODE_OFFLINE_STATUS=0
(
    cd "$OPENCODE_OFFLINE_PROJECT" &&
    env PATH="$RELEASE_STUB_BIN:$PATH" \
        BETTER_RM_TEST_RELEASE_DIR="$OPENCODE_OFFLINE_EMPTY_ASSETS" \
        HOME="$TMP_ROOT/opencode-offline-home" CLAUDE_CONFIG_DIR= \
        "$OPENCODE_DIST/install-hooks.sh" -a opencode
) >/dev/null 2>&1 || OPENCODE_OFFLINE_STATUS=$?
if [ "$OPENCODE_OFFLINE_STATUS" -eq 0 ]; then
    pass "opencode install does not need the network for the plugin"
else
    fail "opencode install does not need the network for the plugin"
fi
assert_equal "opencode offline install lands the genuine plugin" \
    "$OPENCODE_GENUINE_PLUGIN_HASH" \
    "$([ -f "$OPENCODE_OFFLINE_PLUGIN" ] && file_hash "$OPENCODE_OFFLINE_PLUGIN" || echo missing)"

# ---------------------------------------------------------------------------
# OpenCode publish integrity
# ---------------------------------------------------------------------------
# `-a opencode` 不經過 resolve_shared_hook_for_settings，所以 hook_is_trustworthy
# 與 write_fail_closed_hook_stub 這道防線在這條路徑上從來沒有生效過：其他八個 agent
# 的第一次安裝都會驗，opencode 只有一個裸 `cp`。實測（cp 回報成功卻沒寫入任何內容）
# 的差異是決定性的：claude/codex/cursor/grok 全部 exit 1 並留下 fail-closed stub，
# opencode 是 exit 0 加一個 0 位元組的 runtime hook —— 而 0 位元組的 hook 以 exit 0
# 與空輸出結束，在契約上就是「放行一切」，也就是防護被完全解除卻回報成功。
# 觸發條件要說準：磁碟滿是「大聲」的（`cp` 非零退出、什麼都沒落地、安裝 exit 1，
# 兩棵樹皆然）。會安靜的是「`cp` 回報成功但寫入為空」，本機檔案系統上罕見，但這正是
# 這道防線存在的理由 —— 寫入工具的回傳值本來就證明不了位元組有沒有落地。
# `-a opencode` does not go through resolve_shared_hook_for_settings, so the
# hook_is_trustworthy / write_fail_closed_hook_stub guard never applied on this
# path: the other eight agents verify their first install, opencode had a bare cp.
# Measured with a cp that reports success while writing nothing, the difference is
# decisive: claude/codex/cursor/grok all exit 1 and leave the fail-closed stub,
# opencode exited 0 with a 0-byte runtime hook — and a 0-byte hook exits 0 with no
# output, which the contract reads as allow-everything, i.e. the guard fully
# disarmed while reporting success.
# The trigger has to be stated accurately: a full disk is LOUD (cp exits non-zero,
# nothing lands, the install exits 1, on both trees). The silent shape is a cp that
# reports success but writes nothing, which is rare on a local filesystem — and is
# exactly why this guard exists, since a write tool's exit status can never prove
# the bytes landed.
# $1 bin dir, $2 destination to truncate (MUST be the physical path), $3 hit log
make_truncating_cp_bin() {
    local bin_dir="$1"
    local victim="$2"
    local hit_log="$3"
    mkdir -p "$bin_dir"
    : > "$hit_log"
    # 必須以「最後一個參數」（目的地）判斷。runtime hook 的來源與目的地檔名完全
    # 相同，比對任意參數會先打中來源，量到的就不是這條路徑了。
    # 目的地必須是實體路徑：安裝程式用 `pwd -P` 解析專案根目錄，而 macOS 的
    # $TMPDIR 是 /var/folders（symlink），安裝程式看到的是 /private/var/folders。
    # 第一版比對 $TMPDIR 那串，於是替身一次都沒被走到，兩個測試都在「以為有截斷、
    # 其實沒有」的情況下紅 —— 命中記錄就是為了讓那種失效大聲出來。
    # The DESTINATION (last argument) is what must be matched. The runtime hook's
    # source and destination share a filename, so matching any argument hits the
    # source first and measures something else entirely.
    # The destination must be the PHYSICAL path: the installer resolves the project
    # root with `pwd -P`, and macOS $TMPDIR is /var/folders (a symlink), which the
    # installer sees as /private/var/folders. The first version compared the
    # $TMPDIR spelling, so the shim was never reached and both tests went red while
    # nothing had actually been truncated. The hit log exists to make that failure
    # mode loud instead of silent.
    cat > "$bin_dir/cp" <<EOF
#!/bin/sh
dest=\$(eval echo "\\\${\$#}")
if [ "\$dest" = "$victim" ]; then
    printf '%s\n' "\$dest" >> "$hit_log"
    : > "\$dest"
    exit 0
fi
exec /bin/cp "\$@"
EOF
    chmod +x "$bin_dir/cp"
}

OPENCODE_TRUNC_RUNTIME_PROJECT="$TMP_ROOT/opencode-truncated-runtime-project"
make_repo "$OPENCODE_TRUNC_RUNTIME_PROJECT"
OPENCODE_TRUNC_RUNTIME="$OPENCODE_TRUNC_RUNTIME_PROJECT/hooks/protect-important-paths.js"
OPENCODE_TRUNC_RUNTIME_HITS="$TMP_ROOT/opencode-trunc-runtime.hits"
make_truncating_cp_bin "$TMP_ROOT/opencode-trunc-runtime-bin" \
    "$(cd "$OPENCODE_TRUNC_RUNTIME_PROJECT" && pwd -P)/hooks/protect-important-paths.js" \
    "$OPENCODE_TRUNC_RUNTIME_HITS"
OPENCODE_TRUNC_RUNTIME_STATUS=0
OPENCODE_TRUNC_RUNTIME_OUTPUT=$(
    cd "$OPENCODE_TRUNC_RUNTIME_PROJECT" &&
    PATH="$TMP_ROOT/opencode-trunc-runtime-bin:$PATH" HOME="$TMP_ROOT/opencode-trunc-runtime-home" \
        CLAUDE_CONFIG_DIR= "$INSTALLER" -a opencode 2>&1
) || OPENCODE_TRUNC_RUNTIME_STATUS=$?
if [ -s "$OPENCODE_TRUNC_RUNTIME_HITS" ]; then
    pass "the opencode runtime truncation was actually injected"
else
    fail "the opencode runtime truncation was actually injected"
fi
if [ "$OPENCODE_TRUNC_RUNTIME_STATUS" -ne 0 ]; then
    pass "a truncated opencode runtime hook aborts instead of reporting success"
else
    fail "a truncated opencode runtime hook aborts instead of reporting success"
fi
if [ -f "$OPENCODE_TRUNC_RUNTIME" ] && hook_is_permissive "$OPENCODE_TRUNC_RUNTIME"; then
    fail "a truncated opencode runtime hook never leaves an allow-everything hook"
else
    pass "a truncated opencode runtime hook never leaves an allow-everything hook"
fi
assert_contains "a truncated opencode runtime hook says it now fails closed" \
    "$OPENCODE_TRUNC_RUNTIME_OUTPUT" "fails closed"

# 外掛沒有行為探測可用（它是 TypeScript），但「複製過去的內容是否與來源相同」是
# 驗得了的，而來源本身的正確性已由上面的 byte-identity 斷言釘住。這裡要求的只有
# 一件事：靜默截斷不得以 exit 0 收場。
# No behavioural probe is available for the plugin (it is TypeScript), but whether
# the copy matches its source is checkable, and the source's own correctness is
# pinned by the byte-identity assertions above. The requirement here is only that a
# silent truncation must not end at exit 0.
OPENCODE_TRUNC_PLUGIN_PROJECT="$TMP_ROOT/opencode-truncated-plugin-project"
make_repo "$OPENCODE_TRUNC_PLUGIN_PROJECT"
OPENCODE_TRUNC_PLUGIN="$OPENCODE_TRUNC_PLUGIN_PROJECT/.opencode/plugins/protect-important-paths.ts"
OPENCODE_TRUNC_PLUGIN_HITS="$TMP_ROOT/opencode-trunc-plugin.hits"
make_truncating_cp_bin "$TMP_ROOT/opencode-trunc-plugin-bin" \
    "$(cd "$OPENCODE_TRUNC_PLUGIN_PROJECT" && pwd -P)/.opencode/plugins/protect-important-paths.ts" \
    "$OPENCODE_TRUNC_PLUGIN_HITS"
OPENCODE_TRUNC_PLUGIN_STATUS=0
OPENCODE_TRUNC_PLUGIN_OUTPUT=$(
    cd "$OPENCODE_TRUNC_PLUGIN_PROJECT" &&
    PATH="$TMP_ROOT/opencode-trunc-plugin-bin:$PATH" HOME="$TMP_ROOT/opencode-trunc-plugin-home" \
        CLAUDE_CONFIG_DIR= "$INSTALLER" -a opencode 2>&1
) || OPENCODE_TRUNC_PLUGIN_STATUS=$?
if [ -s "$OPENCODE_TRUNC_PLUGIN_HITS" ]; then
    pass "the opencode plugin truncation was actually injected"
else
    fail "the opencode plugin truncation was actually injected"
fi
if [ "$OPENCODE_TRUNC_PLUGIN_STATUS" -ne 0 ]; then
    pass "a truncated opencode plugin aborts instead of reporting success"
else
    fail "a truncated opencode plugin aborts instead of reporting success"
fi
if [ -f "$OPENCODE_TRUNC_PLUGIN" ] && [ ! -s "$OPENCODE_TRUNC_PLUGIN" ]; then
    assert_contains "a truncated opencode plugin says the copy does not match its source" \
        "$OPENCODE_TRUNC_PLUGIN_OUTPUT" "does not match its source"
else
    fail "a truncated opencode plugin says the copy does not match its source"
fi

# 第一次安裝（目的地不存在）走的是純 cp，完全沒有信任探測；hook_is_trustworthy
# 只服務 refresh 路徑。cp 回報成功不代表寫進去的是完整內容：磁碟滿或檔案系統錯誤
# 會留下 0 byte 的檔案，而那在契約上就是「放行一切」。
# The first install (destination absent) is a plain cp with no trust probe;
# hook_is_trustworthy only covers the refresh path. cp reporting success does not
# mean the bytes landed — a full disk leaves a 0-byte file, which the contract
# reads as allow-everything.
FIRST_INSTALL_CP_BIN="$TMP_ROOT/first-install-cp-bin"
mkdir -p "$FIRST_INSTALL_CP_BIN"
cat > "$FIRST_INSTALL_CP_BIN/cp" <<'EOF'
#!/bin/sh
# 只讓「第一次把共用 hook 複製到目的地」變成靜默截斷：回報成功、留下空檔。
for arg in "$@"; do
    case "$arg" in
        */.claude/protect-important-paths.js)
            : > "$arg"
            exit 0
            ;;
    esac
done
exec /bin/cp "$@"
EOF
chmod +x "$FIRST_INSTALL_CP_BIN/cp"
FIRST_INSTALL_HOME="$TMP_ROOT/first-install-truncated-home"
FIRST_INSTALL_HOOK="$FIRST_INSTALL_HOME/.claude/protect-important-paths.js"
FIRST_INSTALL_STATUS=0
FIRST_INSTALL_OUTPUT=$(
    cd "$TMP_ROOT"
    PATH="$FIRST_INSTALL_CP_BIN:$PATH" HOME="$FIRST_INSTALL_HOME" CLAUDE_CONFIG_DIR= \
        "$INSTALLER" -a claude --global 2>&1
) || FIRST_INSTALL_STATUS=$?
if [ "$FIRST_INSTALL_STATUS" -ne 0 ]; then
    pass "a truncated first install aborts instead of reporting success"
else
    fail "a truncated first install aborts instead of reporting success"
fi
if [ -f "$FIRST_INSTALL_HOOK" ] && hook_is_permissive "$FIRST_INSTALL_HOOK"; then
    fail "a truncated first install never leaves an allow-everything hook"
else
    pass "a truncated first install never leaves an allow-everything hook"
fi
assert_contains "a truncated first install says the hook now fails closed" \
    "$FIRST_INSTALL_OUTPUT" "fails closed"

# CLEANUP_DIRS 是以空白串接的字串，trap 用未加引號的 $CLEANUP_DIRS 迴圈，於是
# 只要 mktemp -d 交回含空白的路徑，rm -rf 就會打在被切開的目標上。GNU 的
# mktemp -d 會沿用 TMPDIR（含空白的 TMPDIR 就會產生這種路徑），BSD 的不會，
# 所以直接在 mktemp 這個邊界注入：測的是「不管 mktemp 交回什麼路徑，清理都不得
# 打錯目標」。這是 rm 打在被切開的路徑上，照高後果處理 —— 誘餌目錄就放在第一個
# 切片會落下的位置。
# CLEANUP_DIRS is a whitespace-joined string iterated unquoted, so any temp path
# containing whitespace makes the trap's rm -rf hit split targets. GNU mktemp -d
# honours TMPDIR (a TMPDIR with whitespace produces exactly such a path) while
# BSD's does not, so the injection happens at the mktemp boundary itself. The
# decoy sits exactly where the first split lands.
WHITESPACE_MKTEMP_BIN="$TMP_ROOT/whitespace-mktemp-bin"
mkdir -p "$WHITESPACE_MKTEMP_BIN"
cat > "$WHITESPACE_MKTEMP_BIN/mktemp" <<EOF
#!/bin/sh
if [ "\$1" != "-d" ] || [ \$# -ne 1 ]; then
    exec "$(command -v mktemp)" "\$@"
fi
candidate="\$BETTER_RM_TEST_TMP_PARENT/space dir/tmp.\$\$"
mkdir -p "\$candidate" || exit 1
printf '%s\n' "\$candidate"
EOF
chmod +x "$WHITESPACE_MKTEMP_BIN/mktemp"
WHITESPACE_PARENT="$TMP_ROOT/whitespace-parent"
mkdir -p "$WHITESPACE_PARENT"
WHITESPACE_DECOY="$WHITESPACE_PARENT/space"
mkdir -p "$WHITESPACE_DECOY"
printf '%s\n' "DECOY" > "$WHITESPACE_DECOY/decoy.txt"
WHITESPACE_SOURCE="$TMP_ROOT/whitespace-source"
mkdir -p "$WHITESPACE_SOURCE"
cp "$INSTALLER" "$WHITESPACE_SOURCE/install-hooks.sh"
chmod +x "$WHITESPACE_SOURCE/install-hooks.sh"
WHITESPACE_HOME="$TMP_ROOT/whitespace-home"
assert_success "a whitespace temp path still installs" \
    env PATH="$WHITESPACE_MKTEMP_BIN:$RELEASE_STUB_BIN:$PATH" \
        BETTER_RM_TEST_RELEASE_DIR="$RELEASE_ASSET_DIR" \
        BETTER_RM_TEST_TMP_PARENT="$WHITESPACE_PARENT" \
        HOME="$WHITESPACE_HOME" CLAUDE_CONFIG_DIR= "$WHITESPACE_SOURCE/install-hooks.sh" -a claude --global
assert_file "the cleanup trap never rm -rf's a split path" "$WHITESPACE_DECOY/decoy.txt"
assert_equal "the whitespace temp dir is still cleaned up" "0" \
    "$(find "$WHITESPACE_PARENT/space dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"

# OpenCode 的插件與 runtime 更新路徑仍用 BSD 優先的 `stat -f '%Lp' || stat -c '%a'`。
# 在 GNU userland，`-f` 是「檔案系統狀態」，'%Lp' 被當成另一個 operand：stderr 報錯、
# 結束碼 1，但仍把該檔案的檔案系統資訊印到 stdout，命令替換於是把兩段 stdout 一起
# 收下，chmod 吃到垃圾而失敗，安裝在寫到一半的狀態下中止。
# Same class already fixed for the shared hook: on GNU userland `-f` means FILE
# SYSTEM status, so the mode capture picks up unexpected stdout and chmod aborts
# the install midway.
REAL_STAT=$(command -v stat)
if "$REAL_STAT" -f '%Lp' "$INSTALLER" >/dev/null 2>&1; then
    STAT_MODE_ARGS="-f %Lp"
else
    STAT_MODE_ARGS="-c %a"
fi
GNU_STAT_BIN="$TMP_ROOT/gnu-stat-bin"
mkdir -p "$GNU_STAT_BIN"
cat > "$GNU_STAT_BIN/stat" <<EOF
#!/bin/sh
# 模擬 GNU coreutils 的 stat：-f 是檔案系統狀態，格式字串被當成另一個 operand。
if [ "\$1" = "-f" ]; then
    shift
    fmt="\$1"; shift
    echo "stat: cannot read file system information for '\$fmt': No such file or directory" >&2
    for f in "\$@"; do
        echo "  File: \"\$f\""
        echo "    ID: 0        Namelen: 255     Type: apfs"
    done
    exit 1
fi
if [ "\$1" = "-c" ]; then
    shift
    shift
    for f in "\$@"; do
        "$REAL_STAT" $STAT_MODE_ARGS "\$f"
    done
    exit 0
fi
exec "$REAL_STAT" "\$@"
EOF
chmod +x "$GNU_STAT_BIN/stat"
GNU_STAT_PROJECT="$TMP_ROOT/gnu-stat-opencode-project"
make_repo "$GNU_STAT_PROJECT"
mkdir -p "$GNU_STAT_PROJECT/.opencode/plugins" "$GNU_STAT_PROJECT/hooks"
GNU_STAT_PLUGIN="$GNU_STAT_PROJECT/.opencode/plugins/protect-important-paths.ts"
GNU_STAT_RUNTIME="$GNU_STAT_PROJECT/hooks/protect-important-paths.js"
printf 'stale plugin that must be replaced\n' > "$GNU_STAT_PLUGIN"
printf '// stale runtime hook that must be replaced\n' > "$GNU_STAT_RUNTIME"
chmod 640 "$GNU_STAT_PLUGIN" "$GNU_STAT_RUNTIME"
if (
    cd "$GNU_STAT_PROJECT"
    PATH="$GNU_STAT_BIN:$PATH" "$INSTALLER" -a opencode >/dev/null 2>&1
); then
    pass "opencode install survives a GNU-userland stat"
else
    fail "opencode install survives a GNU-userland stat"
fi
assert_equal "opencode plugin is updated under a GNU-userland stat" \
    "$(file_hash "$SCRIPT_DIR/.opencode/plugins/protect-important-paths.ts")" \
    "$(file_hash "$GNU_STAT_PLUGIN")"
assert_equal "opencode runtime hook is updated under a GNU-userland stat" \
    "$(file_hash "$SCRIPT_DIR/hooks/protect-important-paths.js")" \
    "$(file_hash "$GNU_STAT_RUNTIME")"
assert_equal "opencode plugin keeps its original mode" "640" "$(file_mode "$GNU_STAT_PLUGIN")"
assert_equal "opencode runtime hook keeps its original mode" "640" "$(file_mode "$GNU_STAT_RUNTIME")"

echo ""
echo "========================================"
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo "========================================"

if [ "$FAILED" -ne 0 ]; then
    exit 1
fi
