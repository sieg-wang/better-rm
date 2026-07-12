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
    node - "$1" <<'NODE'
const fs = require('fs');
const settings = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
let count = 0;
for (const entry of settings.hooks?.PreToolUse ?? []) {
  if (entry?.matcher !== 'Bash' || !Array.isArray(entry.hooks)) continue;
  for (const hook of entry.hooks) {
    if (hook?.type === 'command' && typeof hook.command === 'string'
        && hook.command.includes('hooks/protect-important-paths.js')) count += 1;
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

backup_count() {
    local directory="$1"
    local name="$2"
    find "$directory" -maxdepth 1 -type f -name "$name.better-rm.bak.*" | wc -l | tr -d ' '
}

echo "========================================"
echo "install-hooks.sh tests"
echo "========================================"

# CLI parsing
assert_success "--help succeeds" "$INSTALLER" --help
HELP_TEXT=$("$INSTALLER" --help)
assert_contains "help shows supported agents" "$HELP_TEXT" "supported:"
assert_contains "help shows claude as supported agent" "$HELP_TEXT" "claude"
assert_contains "help shows codex as supported agent" "$HELP_TEXT" "codex"
assert_failure "missing --agent fails" "$INSTALLER"
assert_failure "missing --agent value fails" "$INSTALLER" --agent
assert_failure "unknown option fails" "$INSTALLER" --wat
assert_failure "unsupported agent fails" "$INSTALLER" --agent cursor
assert_failure "duplicate --agent fails" "$INSTALLER" -a claude --agent claude

# Project mode resolves the caller's Git root.
PROJECT="$TMP_ROOT/project"
make_repo "$PROJECT"
mkdir -p "$PROJECT/src/nested"
(
    cd "$PROJECT/src/nested"
    "$INSTALLER" -a claude >/dev/null
)
PROJECT_SETTINGS="$PROJECT/.claude/settings.json"
assert_file "project settings are created at Git root" "$PROJECT_SETTINGS"
assert_equal "project install contains one better-rm hook" "1" "$(hook_count "$PROJECT_SETTINGS")"
assert_equal "new project settings use mode 644" "644" "$(file_mode "$PROJECT_SETTINGS")"
assert_failure "project install fails outside Git" bash -c "cd '$TMP_ROOT' && '$INSTALLER' -a claude"

PROJECT_COMMAND=$(node -e 'const s=require(process.argv[1]); process.stdout.write(s.hooks.PreToolUse[0].hooks[0].command)' "$PROJECT_SETTINGS")
case "$PROJECT_COMMAND" in
    *"$SCRIPT_DIR/hooks/protect-important-paths.js"*) pass "project hook uses installer checkout path" ;;
    *) fail "project hook uses installer checkout path" ;;
esac

# Codex project install.
CODEX_PROJECT="$TMP_ROOT/codex-project"
make_repo "$CODEX_PROJECT"
mkdir -p "$CODEX_PROJECT/src/nested"
(
    cd "$CODEX_PROJECT/src/nested"
    "$INSTALLER" -a codex >/dev/null
)
CODEX_SETTINGS="$CODEX_PROJECT/.codex/hooks.json"
assert_file "codex project settings are created at Git root" "$CODEX_SETTINGS"
assert_equal "codex project install contains one better-rm hook" "1" "$(hook_count "$CODEX_SETTINGS")"
assert_equal "codex project settings use mode 644" "644" "$(file_mode "$CODEX_SETTINGS")"
CODEX_COMMAND=$(node -e 'const s=require(process.argv[1]); process.stdout.write(s.hooks.PreToolUse[0].hooks[0].command)' "$CODEX_SETTINGS")
case "$CODEX_COMMAND" in
    *"$SCRIPT_DIR/hooks/protect-important-paths.js"*) pass "codex hook uses installer checkout path" ;;
    *) fail "codex hook uses installer checkout path" ;;
esac
assert_failure "codex global mode is unsupported" bash -c "cd '$TMP_ROOT' && '$INSTALLER' -a codex --global"

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

# Missing shared hook fails before touching settings.
MISSING_SOURCE="$TMP_ROOT/missing-source"
mkdir -p "$MISSING_SOURCE"
cp "$INSTALLER" "$MISSING_SOURCE/install-hooks.sh"
chmod +x "$MISSING_SOURCE/install-hooks.sh"
MISSING_HOME="$TMP_ROOT/missing-home"
assert_failure "missing shared hook fails" env HOME="$MISSING_HOME" CLAUDE_CONFIG_DIR= "$MISSING_SOURCE/install-hooks.sh" -a claude --global
if [ ! -e "$MISSING_HOME/.claude/settings.json" ]; then
    pass "missing shared hook does not create settings"
else
    fail "missing shared hook does not create settings"
fi

echo ""
echo "========================================"
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo "========================================"

if [ "$FAILED" -ne 0 ]; then
    exit 1
fi
