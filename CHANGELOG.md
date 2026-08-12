# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- 1.5.0: Prepare release 1.5.0
- `--` is honoured as the option terminator, by both `rm` and `rm --restore`. What follows it is a pathname rather than an option, which is what makes a file whose name starts with a dash nameable at all: `rm -- -dash.txt` deletes it and `rm --restore -- -dash.txt` puts it back. Previously a bare `--` fell through to the combined-option parser and died with `invalid option -- '-'`, so such a file could not be deleted by any spelling. **The two sides take different numbers of pathnames**: deletion accepts any number after the terminator, `--restore` accepts exactly one and refuses anything further (see Changed). Without the terminator nothing changes: `rm -dash.txt` is still refused as an invalid option, exactly as `rm(1)` refuses it, and a dash-leading argument directly after `--restore` is still reported as a missing argument so a mistyped `rm --restore -f` cannot silently name a file to restore.
- `/Applications`, `/Library`, `/Network`, `/System`, `/Users`, `/cores` and `/private` are protected. The list was Linux-only, so on macOS every one of these was an ordinary deletion target — `/Applications` needs no root at all, and `rm -rf /Applications` moved every installed application into the trash and exited `0`. Protection is exact-path, as it already was for the Linux entries: the directory itself is refused and its contents are not, so removing a single app bundle still works. `/private` covers `/private` only — macOS `/etc` and `/var` are symlinks to `/private/etc` and `/private/var`, and the physical spellings remain unprotected because the list is compared literally.
- The macOS firmlink spelling `/System/Volumes/Data/...` is recognised as the same object as the root spelling, by both guards. `/Users/you` and `/System/Volumes/Data/Users/you` are the same device and the same inode — measured with `stat -f '%d:%i'` — and so are `/Applications` and `/System/Volumes/Data/Applications`. A firmlink is not a symlink: `readlink -f` hands either spelling straight back, so nothing ever canonicalised one into the other and **the `$HOME` protection had this hole from the first day** — `/System/Volumes/Data`, `/System/Volumes/Data/Users`, `/System/Volumes/Data/Users/<you>` and `/System/Volumes/Data/Applications` were all ordinary deletion targets, so the whole home directory was removable under that spelling. The `/System/Volumes/Data/` prefix is now mapped back before the list is consulted, so `rm -rf /System/Volumes/Data/Users/you` is refused exactly as `rm -rf ~` is. The criterion is not existence: a `/System/Volumes/Data/Users/<name>` that has not been created yet is refused too. The mapped path still goes through the same exact-path comparison, so `/System/Volumes/Data/Users/you/project` stays removable, and the prefix must align on a whole component, so `/System/Volumes/DataDrive/...` is untouched. This is a spelling correspondence, not proof of identity: something the data volume does not hold (`/System/Volumes/Data/usr`) maps to `/usr` and is refused with it, which is the safe direction, while two spellings of one inode produced by a bind mount or a hard-linked directory are outside the rule.
- `/System/Volumes` and each `/System/Volumes/<volume>` mount root are protected, the way `/mnt` and `/Volumes` already were. That is where a modern Mac mounts its own APFS volumes — `Data`, `Preboot`, `VM`, `Update` — and neither guard had it in the mount-parent rule or in the list. Items below the first level are unaffected.
- `/Volumes` and each `/Volumes/<disk>` mount root are protected, the way `/mnt` and `/mnt/c` already were. `/Volumes/<disk>` is where every external disk, Time Machine target and network share is attached on macOS, so naming one took the whole disk's mount point rather than a directory. The protection stops at the mount root: `/Volumes/Backup/old.log` and anything else inside a mounted disk is still removable. Both mount parents now run through the same block, so the `/mnt` behaviour is unchanged — measured path by path, the only verdicts this changes are `/Volumes` and its first level.


### Fixed
- Protected `/mnt` and its immediate mount roots by default to prevent deleting Windows drives from WSL ([#9](https://github.com/doggy8088/better-rm/issues/9)).
- Store deletion history outside `TRASH_DIR` to avoid macOS log write failures, while retaining legacy log fallback for restore operations ([#10](https://github.com/doggy8088/better-rm/issues/10)).
- Prevent trash-path collisions and late writers from overwriting an existing recovery entry; suffixed recovery paths remain compatible with `--restore`.
- `--restore` no longer deletes anything, by path or otherwise. The trashed item is staged in a directory this process creates exclusively and then put in place with a single same-filesystem `rename`, so an existing file or symlink is replaced atomically by the kernel. If an initially absent destination appears before publish, an unconfirmed restore aborts, returns the item to trash, and never makes that destination the target of even one `mv`.
- `--restore` can now restore a trashed directory onto an existing file or symlink. `rename(dir, non-dir)` is `ENOTDIR`, and only a real-directory destination used to be cleared out of the way, so restoring a directory over a file, a symlink, or a symlink to a directory failed outright.
- A destination that `rename` cannot replace — a real directory, or any destination when the restored item is a real directory — is now cleared by **moving it into the trash** rather than by `rm -rf`. It keeps a deletion-log record under its own original path and is recoverable with `rm --restore <name>`, which the message states explicitly. An overwrite is a deletion, and deletions through this tool are recoverable. The residual race inside the trash-move can at worst move an unrelated directory into the trash, where it survives intact; it can no longer destroy one.
- `--restore` now works when the trash and the destination are on different filesystems (an external drive, a network mount, or a second APFS volume with the default `$HOME/.Trash`). A cross-device `mv` is copy-then-unlink, so the inode necessarily changes; requiring inode equality made every such restore fail *after* the trash source had been consumed, leaving the user's only copy in the staging directory while the log still pointed at a trash path that no longer existed. The acceptance test is now split by device, and a failed cross-device extraction prints the path where the data actually is.
- `--restore` exits `2` only when the item was restored but the staging directory could not be removed, and prints the leftover path. A partially successful restore never exits `0`. `1` continues to mean the restore did not happen, and its message names anything that could not be put back.
- Clearing the destination into the trash no longer half-copies onto a trash volume that cannot hold it. Across devices that move is a full copy: measured on a real 20 MB HFS+ trash volume with a 41 MB destination, it died of `ENOSPC` half way and left a permanent 20 MB half-copy nothing mentioned, the user's file stranded in the staging directory instead of restored, and the trash source already consumed. The landing filesystem is now measured first (`df` against `du`); when it does not fit — or when the trash move fails anyway while the destination is still, by inode, the object that was verified — the destination is set aside in place in an exclusively created `<name>.better-rm-displaced-XXXXXX` directory by a same-filesystem `rename`, which needs no space. The restore completes, both objects survive, and the message names the set-aside path and says `rm --restore` cannot reach it. Protected destinations (e.g. `.git`) never take that route.
- A destination that reached the trash but whose deletion-log record could not be written no longer tells the user to run `rm --restore <name>`, which would answer "no deletion record found". `move_to_trash` reports that state as its own exit code `3`; an ordinary `rm` still exits `0` there, exactly as before.
- `--restore` now says that `mktemp` is what is missing when it cannot create its staging directory, instead of only reporting that the directory could not be created. `--restore` hard-depends on `mktemp`; deletion does not.
- Detect protected removals nested inside shell carriers, `eval`, command substitutions, and chained `sudo`/`env`/`command` wrappers.

### Changed
- `BETTER_RM_PROTECTED_DIRS` is honoured by `better-rm` itself, not only by the agent hook. The variable is the only interface for adding protection of your own, and the hook has always read it — while `better-rm` had no reference to it anywhere in the file, so a user who set it, watched their coding agent get refused, and concluded they were covered still had the directory removable by `rm`. Both guards now parse it identically: `:` separated, empty entries skipped, relative entries resolved against the working directory, and exact-match like the built-in list, so `secrets` is refused and `secrets/notes.txt` is not. Skipping empty entries is what keeps a trailing colon from resolving to `.` and making the working directory undeletable.
- Everything **inside** `.git` is protected, not just the `.git` directory itself. `.git` is now matched as a path COMPONENT by both guards, so `rm -rf .git/objects`, `rm -rf .git/refs` and `rm -f .git/index.lock` are refused. Previously the pattern list matched only a path that ENDED at `.git`, so the object store — as unrecoverable as the repository it is — was an ordinary deletion target: `rm -rf .git/objects` moved it to the trash and exited `0`. The agent-path hook already refused every one of those paths, so the two guards were answering the same path differently; better-rm is aligned onto the stricter side. **This denies one legitimate thing**: clearing a stale `.git/index.lock` by hand after an interrupted git operation. Use `/bin/rm -f .git/index.lock` for that — it bypasses this tool, so there is no trash copy. Whether a lockfile exemption should exist is a policy call the maintainer has not made. Names that merely contain `.git` are unaffected: `.gitignore`, `.github/workflows` and `vendor.git/objects` stay removable.
- The protected-path hook now treats a command word it cannot resolve before execution (`$CMD`, `$( … )`, or a backtick, in any quoting except single quotes) as if it were `rm`, because the shell only resolves it to a real command at run time. **This denies some legitimate commands.** Every verdict below was measured against the hook, not reasoned about.
  - The rule: for such a command, each operand is checked as if it were a deletion target. Words starting with `-` are treated as options and skipped. It is denied when any remaining operand is either dynamic (any expansion is folded to the worst case, `/`) or a statically protected path. A backtick region containing whitespace is a special case — it splits into separate words, so the fragment carrying the closing backtick is itself a dynamic operand and the command is denied *regardless of its operands*, including when it has none.
  - Now denied (previously allowed): `$(which docker) run -v $(pwd):/work img ls` · `"$(which docker)" run -v $(pwd):/work img ls` · `$(brew --prefix)/bin/rg "$PATTERN" src/` · `$(which git) -C $(pwd) status` · `$(which cat) $HOME/.zshrc` · `$(which echo) $USER` · `$(which echo) /etc` · `` `which git` status `` · `` `command -v ls` ``.
  - Still allowed: any static executable (`docker run -v $(pwd):/work img ls`), static operands (`$(command -v python3) ./build.py`), an expansion *adjacent* to an option (`$(which make) -j$(nproc) all`, `$(which git) -C$(pwd) status` — separating them with a space denies), single-quoted text (`$(which cat) '$HOME/.zshrc'`), `~/…` paths (`$(which cat) ~/.zshrc`; a bare `~` is denied because it IS the protected home directory), a backtick with no whitespace inside (`` `pwd` status ``), and `$( … )` anywhere other than the executable position (`cd $(git rev-parse --show-toplevel)`).
  - Frequency: not rare. `$(which X) "$ARG"` is an ordinary shape, and the reviewer of this change hit the denial twice while reviewing it. Expect it in normal sessions rather than once in a while; it is fail-closed, loud, and names the path it refused.
  - Workaround: write the command name directly (`docker run …`), or keep dynamic values adjacent to their option (`-j$(nproc)`), or single-quote them.
- `deletion.log` records now carry a `v2` marker and escape `\\`, `|`, newline, and CR in both path fields, so filenames containing `|` or a newline can be logged and restored. Records written before this change (no `v2` marker) are still read by `--restore`.
- Added `BETTER_RM_STATE_DIR` and XDG state-directory support for `deletion.log`.
- Restricted newly created state directories and deletion logs to user-only access.
- `install-hooks.sh -a opencode` can no longer write outside the project. It only checked whether the final destination was a symlink, so a symlinked ancestor such as `.opencode/plugins` or `hooks` left the final component non-existent, the check passed, and `mkdir -p` plus `cp` then created the plugin and the runtime hook outside the Git root — exiting 0 while doing it. Both destinations are now resolved to their physical path and required to land inside the physical Git root, and either one failing rejects the install before *either* file is written.
- The same containment now applies to every other agent, not just OpenCode. `install-hooks.sh` builds the settings path for the eight JSON-style agents (`claude`, `codex`, `cursor`, `copilot`, `antigravity`, `qoder`, `pi`, `grok`) by concatenating the *lexical* Git toplevel with a fixed subpath, and the settings merge inspects only the final leaf — which does not exist yet when the ancestor is the symlink. A symlinked `.claude`, `.codex`, `.cursor`, … therefore let `mkdir -p`, `cp` and the final `rename` all traverse the link: measured in an isolated repo, `-a claude` wrote both the runtime hook and `settings.json` outside the project root and exited 0 while claiming to be project-scoped. The settings file and the shared hook beside it are now both resolved to their physical path and required to land inside the physical Git root, before any directory is created or any file is copied, backed up or renamed. This applies to project-scoped installs only; a `--global` destination legitimately lives outside every repository and is unaffected.
- `rm --restore -- <file>` now refuses any further argument instead of interpreting it, and exits `1` without touching anything. `--restore` puts back exactly one item, so a second word after the terminator was previously either discarded in silence (`rm --restore -- a b` ignored `b`) or parsed as a flag — measured, `rm --restore -- victim.txt -f` exited `0`, force-replaced the destination with no prompt, and left zero trash entries, so whatever had been in the way was gone with no recovery path. **This breaks spellings that used to work.** `rm --restore -- <file> -v` no longer runs; write `rm -v --restore -- <file>` instead, and `rm -f --restore -- <file>` for a forced overwrite. Flags written before `--restore` are unaffected, and `rm --restore <file> -f` without the terminator is unchanged.
- `rm --restore` now exits `2`, not `0`, when the old destination had to take the in-place `<name>.better-rm-displaced-XXXXXX` route, and prints the set-aside path on **stdout as well as stderr**. **This changes an exit code that used to be `0`.** That route keeps the data — it never loses the occupant and it is not going away — but it is a degraded outcome: the displaced object sits outside the trash and outside the deletion log, `rm --restore` cannot reach it, and clearing it up is the user's job. Measured before this change: exit `0`, zero bytes of stdout, and the only trace of it on stderr, so `rm -f --restore x 2>/dev/null` was indistinguishable from a restore that left nothing behind. It is no longer a rare corner either — the route is reachable for files, symlinks, hardlinks and FIFOs rather than directories alone, and from an ordinary permission failure rather than only a full trash volume. `2` is the code this command already used for "restored, but a named residue is left behind"; the clean route still exits `0` and still prints nothing extra. The two stdout lines are uncoloured so a caller can read the path out of them.
- Whatever occupies a `--restore` destination now goes **into the trash** before it is overwritten, instead of being unlinked by the publish `rename`. Only the two shapes `rename(2)` cannot replace atomically — a real directory, or any destination when the restored item is a real directory — used to be cleared out of the way; every other occupant was destroyed. Measured before this change, with a file at the destination: `rm -f --restore -- victim.txt` exited `0`, printed nothing, took the trash from one entry to zero, and left the occupant in neither the trash nor the working directory — this is the "gone with no recovery path" half of the entry above, for the spelling that was never refused. The occupant now gets its own deletion-log record under its own original path and comes back with `rm --restore <name>`, which the message states outright. A symlink occupant is trashed as the link itself and is never followed. The interactive prompt keeps its shape: `y` trashes the occupant exactly as `-f` does, `n` still touches nothing at all. Ordering carries the guarantee — the set-aside completes before the publish, so a set-aside that cannot complete returns the staged item to the trash and exits `1` with the destination never touched. The existing fallbacks are unchanged and now apply to every occupant: a trash volume that cannot hold it, or a trash move that fails while the destination is still by inode the object that was verified, still take the in-place `<name>.better-rm-displaced-XXXXXX` route with the path named in the message; a protected occupant such as `.git` takes neither route, so the restore aborts and leaves the destination exactly as it was.

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
