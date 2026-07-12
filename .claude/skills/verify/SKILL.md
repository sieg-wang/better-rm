---
name: verify
summary: Verify better-rm CLI and hook changes through their terminal surfaces.
---

# Verify better-rm

Use isolated temporary directories so verification never changes the real trash, shell configuration, or coding-agent settings.

## Hook installer

1. Create a temporary Git repository with representative `.claude/settings.json` content.
2. From a nested directory, run `install-hooks.sh -a claude` and inspect the resulting settings and backup.
3. Run it again and compare modification time and backup count to confirm a no-op.
4. Outside Git, set a temporary `HOME` or `CLAUDE_CONFIG_DIR` and run `install-hooks.sh -a claude --global`; confirm mode `0600`.
5. Extract the installed hook command from JSON and pipe Claude `PreToolUse` payloads through it. Confirm `.git` deletion returns `permissionDecision: deny` and a harmless file deletion exits 0 without denial output.
6. Probe a missing `--agent` value and malformed settings; confirm clear nonzero exits and unchanged malformed input.

## Main CLI

For `better-rm` behavior changes, use a temporary `HOME` and disposable files/directories. Drive the public `better-rm` command rather than sourcing internal functions. Never point verification at real user data.
