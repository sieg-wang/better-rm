# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- 1.5.0: Prepare release 1.5.0


### Fixed
- Protected `/mnt` and its immediate mount roots by default to prevent deleting Windows drives from WSL ([#9](https://github.com/doggy8088/better-rm/issues/9)).
- Store deletion history outside `TRASH_DIR` to avoid macOS log write failures, while retaining legacy log fallback for restore operations ([#10](https://github.com/doggy8088/better-rm/issues/10)).
- Prevent trash-path collisions and late writers from overwriting an existing recovery entry; suffixed recovery paths remain compatible with `--restore`.
- `--restore` no longer deletes the overwritten destination by path. The trashed item is staged in a directory this process creates exclusively and then put in place with a single same-filesystem `rename`, so an existing file or symlink is replaced atomically by the kernel. A concurrent process could previously occupy the move-aside path and have its own data deleted by the success path while `--restore` still returned 0. Every move is now verified by `device:inode`, and a real-directory destination — the only case that still needs a set-aside and a delete — re-verifies both the staging directory and the set-aside object immediately before deleting, refusing to delete on any mismatch.
- `--restore` now exits `2` when the file was restored but the cleanup was refused after detecting a concurrent modification, and prints the leftover path. A partially successful restore never exits `0`. `1` continues to mean the restore did not happen.
- Detect protected removals nested inside shell carriers, `eval`, command substitutions, and chained `sudo`/`env`/`command` wrappers.

### Changed
- The protected-path hook now treats a command word it cannot resolve before execution (`$CMD`, `$( … )`, or a backtick, in any quoting except single quotes) as if it were `rm`, because the shell only resolves it to a real command at run time. **This denies some legitimate commands.** Every verdict below was measured against the hook, not reasoned about.
  - The rule: for such a command, each operand is checked as if it were a deletion target. Words starting with `-` are treated as options and skipped. It is denied when any remaining operand is either dynamic (any expansion is folded to the worst case, `/`) or a statically protected path. A backtick region containing whitespace is a special case — it splits into separate words, so the fragment carrying the closing backtick is itself a dynamic operand and the command is denied *regardless of its operands*, including when it has none.
  - Now denied (previously allowed): `$(which docker) run -v $(pwd):/work img ls` · `"$(which docker)" run -v $(pwd):/work img ls` · `$(brew --prefix)/bin/rg "$PATTERN" src/` · `$(which git) -C $(pwd) status` · `$(which cat) $HOME/.zshrc` · `$(which echo) $USER` · `$(which echo) /etc` · `` `which git` status `` · `` `command -v ls` ``.
  - Still allowed: any static executable (`docker run -v $(pwd):/work img ls`), static operands (`$(command -v python3) ./build.py`), an expansion *adjacent* to an option (`$(which make) -j$(nproc) all`, `$(which git) -C$(pwd) status` — separating them with a space denies), single-quoted text (`$(which cat) '$HOME/.zshrc'`), `~/…` paths (`$(which cat) ~/.zshrc`; a bare `~` is denied because it IS the protected home directory), a backtick with no whitespace inside (`` `pwd` status ``), and `$( … )` anywhere other than the executable position (`cd $(git rev-parse --show-toplevel)`).
  - Frequency: not rare. `$(which X) "$ARG"` is an ordinary shape, and the reviewer of this change hit the denial twice while reviewing it. Expect it in normal sessions rather than once in a while; it is fail-closed, loud, and names the path it refused.
  - Workaround: write the command name directly (`docker run …`), or keep dynamic values adjacent to their option (`-j$(nproc)`), or single-quote them.
- `deletion.log` records now carry a `v2` marker and escape `\\`, `|`, newline, and CR in both path fields, so filenames containing `|` or a newline can be logged and restored. Records written before this change (no `v2` marker) are still read by `--restore`.
- Added `BETTER_RM_STATE_DIR` and XDG state-directory support for `deletion.log`.
- Restricted newly created state directories and deletion logs to user-only access.

### Added
- 1.4.3: Prepare release 1.4.3


### Added
- 1.4.2: Prepare release 1.4.2


### Added
- 1.4.1: Prepare release 1.4.1


### Added
- Added `install-hooks.sh` with `-a`/`--agent` selection and Claude Code support.
- Added project-level and `-g`/`--global` Claude Code hook installation with preserving JSON merges, backups, and idempotent updates.
- Added isolated installer integration tests in `test-install-hooks.sh`.
- Extended `install-hooks.sh` with `codex` agent support for project-level `.codex/hooks.json` installation (global mode not supported).
- Extended `install-hooks.sh` with `cursor` agent support for project-level `.cursor/hooks.json` installation (global mode not supported).

## [1.4.0] - 2026-07-12

### Added
- Bumped minor version to 1.4.0.

## [1.3.0] - 2026-07-11

### Added
- File restore capability (`rm --restore <file>`) to restore the last deleted version of a file to the current folder.
- Interactive overwrite prompts if a file with the same name already exists in the destination folder.
- `-f` (force) flag integration to automatically overwrite existing destination files without prompts.
- Expanded the test suite with a new section "測試 13: 還原功能" covering core restore operations, overwrite handling, and force mode.

## [1.2.1] - 2026-07-11

### Added
- Cross-agent hooks support for Cursor (`.cursor/hooks.json`), OpenCode (`.opencode/plugins/protect-important-paths.ts`), and Grok Build (`.grok/hooks/better-rm.json`)
- Added Cursor and Grok Build test suites to `test-hooks.js`

## [1.2.0] - 2026-07-11

### Added
- Cross-agent `PreToolUse` hooks for Claude Code, Codex, GitHub Copilot, Qoder, Google Antigravity (CLI / 2.0), and Pi coding agent
- Shared protected-directory policy for destructive `rm` and `rmdir` commands
- `BETTER_RM_PROTECTED_DIRS` support for adding project-specific protected paths
- Hook protocol and policy tests in `test-hooks.js` including Antigravity and Pi payload support
- Workspace configuration `.agents/hooks.json` for Google Antigravity
- Native TypeScript hook `.omp/hooks/pre/protect-important-paths.ts` and JSON configuration `.pi/hooks.json` for Pi coding agent

## [1.1.0] - 2025-12-09

### Added
- Timestamp and content hash appended to trashed filenames for better tracking and deduplication
- Filename format in trash: `filename__YYYYMMDD_HHMMSS_NNNNNNNNN__hash`
- MD5 hash calculation for file content (with SHA256 fallback)
- Directory hash calculation based on all contained files
- Nanosecond-precision timestamps to prevent filename collisions during rapid deletions
- Deletion log file (`.deletion_log`) in TRASH_DIR that records all deletion operations
  - Logs timestamp, original path, trash path, hash, and file type for each deletion
  - Format: `TIMESTAMP | ORIGINAL_PATH | TRASH_PATH | HASH | FILE_TYPE`
- Comprehensive test script (`test-better-rm.sh`) for validating all features
  - 28 test cases covering all functionality
  - Container-compatible for CI/CD integration
  - Detailed test documentation in TEST_README.md

### Changed
- Trashed files now always include timestamp and hash suffix (previously only added on conflicts)
- Improved directory hash calculation with secure handling of special characters

### Security
- Use `find -print0`, `sort -z`, and `xargs -0 -r` to safely handle filenames with special characters
- Prevent filename injection attacks when calculating directory hashes

### Fixed
- Empty directory hash calculation now works correctly
- Special characters in filenames are handled safely during hash calculation

## [1.0.0] - 2023-12-09

### Added
- Initial release of better-rm
- Safe file deletion by moving files to trash instead of permanent deletion
- Protected directory list to prevent accidental deletion of critical system directories
- Preserve original directory structure in trash
- Support for all common `rm` parameters (`-r`, `-f`, `-i`, `-v`, etc.)
- Customizable trash directory via `TRASH_DIR` environment variable
- Colored output for better user experience
- Protection for important directories (system, user home, Git repositories)

### Features
- Move files to `~/.Trash` instead of permanent deletion
- Maintain full path structure in trash for easy recovery
- Timestamp-based conflict resolution (legacy behavior, replaced in 1.1.0)
- Interactive and force modes
- Verbose output option
- Compatible with standard `rm` command syntax
