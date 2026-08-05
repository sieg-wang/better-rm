# Agents

This document describes the AI agents and automation used in the development of better-rm.

## Overview

This project uses GitHub Copilot, Google Antigravity, Pi, Grok Build, and AI-assisted development to maintain code quality, implement features, and address issues efficiently.

## Development Agents

### Google Antigravity (CLI / 2.0)
- **Purpose**: Safety gating and execution control
- **Scope**: Intercepts run_command tool calls to prevent destructive deletions of protected paths
- **Integration**: Workspace-scoped hooks config in `.agents/hooks.json`
- **Feedback**: Automatically blocks unauthorized tool execution and returns a descriptive denial reason

### Pi Coding Agent
- **Purpose**: Safety gating and validation for tool calls
- **Scope**: Intercepts bash tool execution to block dangerous deletions of protected directories
- **Integration**: Native TypeScript hook in `.omp/hooks/pre/protect-important-paths.ts` and JSON configuration in `.pi/hooks.json`
- **Feedback**: Stops execution and supplies a rejection reason when a deletion violates security policy

### Cursor Agent
- **Purpose**: Safety gating and execution control for shell commands
- **Scope**: Intercepts shell execution to block dangerous deletions of protected directories
- **Integration**: Workspace-scoped hooks config in `.cursor/hooks.json`
- **Feedback**: Automatically blocks unauthorized shell execution and returns a descriptive permission rejection

### OpenCode Agent
- **Purpose**: Safety gating and validation for tool calls
- **Scope**: Intercepts tool execution to block dangerous deletions of protected directories
- **Integration**: Workspace-scoped TypeScript plugin in `.opencode/plugins/protect-important-paths.ts`
- **Feedback**: Stops tool execution and throws an error when a deletion violates security policy

### Grok Build Agent
- **Purpose**: Safety gating and execution control
- **Scope**: Intercepts tool calls (like Bash) to prevent dangerous deletions of protected directories
- **Integration**: Workspace-scoped hooks config in `.grok/hooks/better-rm.json`
- **Feedback**: Stops tool execution and returns a descriptive denial reason

### Code Review Agent
- **Purpose**: Automated code review for pull requests
- **Scope**: Reviews all code changes for security, performance, and maintainability issues
- **Integration**: Runs automatically on PR commits
- **Feedback**: Provides actionable comments on the code

### Security Agent (CodeQL)
- **Purpose**: Static security analysis
- **Scope**: Scans for security vulnerabilities in code changes
- **Integration**: Runs before finalizing changes
- **Note**: Currently limited support for Bash scripts, but best practices are followed

### Testing Agent
- **Purpose**: Automated testing of functionality
- **Scope**: Validates file operations, hash calculations, timestamp generation, and edge cases
- **Coverage**: 
  - Regular files with various content types
  - Empty files and directories
  - Files with special characters
  - Rapid deletion scenarios
  - Symlinks
  - Force mode operations

## Future Development Guidelines

### When Adding New Features

1. **Security First**: Always consider security implications
   - Use secure command patterns (`-print0`, `-0`, etc.)
   - Validate and sanitize all inputs
   - Protect against injection attacks

2. **Maintain Compatibility**: Ensure backward compatibility with existing trash structure
   - New features should not break existing trashed files
   - Consider migration paths for format changes

3. **Test Thoroughly**: Test all edge cases
   - Empty inputs
   - Special characters in filenames
   - Large directories
   - Rapid operations
   - Error conditions

4. **Document Changes**: Update all relevant documentation
   - CHANGELOG.md for user-facing changes
   - README.md for feature descriptions
   - Code comments for complex logic
   - This AGENTS.md for development process changes

### Code Style Guidelines

1. **Comments**: Use bilingual comments (Chinese + English) for consistency
2. **Error Handling**: Always provide clear error messages in both languages
3. **Color Output**: Use colored output for better UX (red for errors, green for success, yellow for warnings)
4. **Shell Best Practices**:
   - Quote all variables
   - Use `local` for function variables
   - Handle edge cases (empty strings, special characters)
   - Use `2>/dev/null` to suppress expected errors

### Performance Considerations

1. **Hash Calculation**: 
   - Be mindful of large directory operations
   - Current implementation may be slow for directories with many files
   - Consider optimization for production use

2. **Timestamp Precision**: Nanosecond precision is sufficient for collision prevention

3. **Fallback Mechanisms**: Always provide fallbacks (e.g., md5sum → sha256sum → "nohash")

## Known gaps in the hook install path (deliberately not fixed yet)

Recorded during the 2026-08 hook review. Each was reproduced; none is fixed
here, so nobody has to rediscover them.

The three that used to head this list — the unverified release download, the
unprobed first install, and the OpenCode `stat -f || stat -c` portability bug —
were fixed on 2026-08-04 and are no longer open. What replaced them:

- The downloaded hook now goes through `require_verified_downloaded_hook`, which
  runs the real deny probe against the download and uses a *synthesised*
  known-good / known-bad pair as its control (the download cannot be its own
  positive control). Failing either way aborts the install.
- The first install runs `hook_is_trustworthy` on the freshly copied file and,
  on failure, writes the fail-closed stub and exits non-zero. Follow-up on
  2026-08-04: when the probe itself cannot run, `hook_is_trustworthy` degrades to
  "byte-identical to the source", and the first install used to accept that
  silently — so on a machine with no usable `node` the install *looked*
  behaviourally verified when only a `cmp` had run. It now prints the same
  "could not run the hook self-check" warning the refresh path already printed
  (`HOOK_PROBE_UNAVAILABLE` was assigned there and never read, which is what gave
  it away). The degraded check still catches the truncated / 0-byte copy this
  path exists to catch; what it cannot catch is a source that does not deny, and
  validating the source stays `test-hooks.js`'s job.
- `install-hooks.sh` no longer invokes `stat` at all; `cp` onto an existing file
  already preserves its inode and mode, which made the `chmod` redundant.

- **The OpenCode plugin download is still unverified.** The runtime hook
  (`protect-important-paths.js`) is now probed behaviourally, but
  `opencode-protect-important-paths.ts` — downloaded from the same release by
  `resolve_opencode_plugin` when `.opencode/plugins/` is missing from the
  checkout — is not. It is the bridge that makes OpenCode call the verified
  runtime hook, so a corrupted plugin means no protection under OpenCode.
  Probing it needs a TypeScript runtime (`bun`, or OpenCode itself), which the
  installer does not otherwise require; a content sniff would only narrow the
  window, so nothing was added rather than something that looks like a check and
  is not. `resolve_opencode_plugin`'s *runtime hook* download branch was left
  alone for a different reason: `resolve_source_paths` already guarantees
  `HOOK_SOURCE_PATH` is readable before it runs, so that branch is unreachable.
- **A broken `sed` extraction would misdirect.** `test-hooks.js` extracts
  `hook_denies_protected_deletion` and `write_fail_closed_hook_stub` from
  `install-hooks.sh` with a `sed` range ending at `/^}/`. Re-indenting the
  embedded JS so a line starts at column zero truncates the extraction, and the
  resulting failure message points at the probe rather than at the extraction.
  An assertion on the extracted line count would save that trip.

## `--restore` and concurrent processes (what is closed, what is not)

`--restore` used to move the trashed item onto the destination and then
`/bin/rm -rf` the path it had moved the old destination to. Making that path
unpredictable (`mktemp -d`) was **not** enough: a same-UID process can enumerate
the parent directory, find the staging directory and pre-create its own object at
the child path better-rm is about to use. Measured against that version, a
fork-free glob-polling attacker destroyed unrelated data in 9 of 10 runs, 7 of
them while `--restore` returned exit 0.

**`--restore` never deletes anything, by path or otherwise.** The trashed item is
moved into a staging directory this process created exclusively, and is then put
in place by a single same-filesystem `rename`, which replaces an existing file or
symlink atomically — the kernel unlinks the old destination as part of that call.
Landing spots are verified afterwards rather than trusted to flags, because BSD
`mv -h` still treats a real directory as a container and BSD `mv -n` returns 0
without doing anything when the target exists.

`rename` cannot replace a destination in two shapes: the destination is a real
directory (`EISDIR`/`ENOTEMPTY`), or the staged item is a real directory and the
destination is not (`ENOTDIR`). Linux's `mv -T` is `rename(2)` as well, so this is
not macOS-specific. In both shapes the destination is cleared out of the way by
**moving it into the trash** through `move_to_trash`, never by `rm -rf`. An
overwrite *is* a deletion, and the whole point of this tool is that deletions are
recoverable; the previous shape did inside `--restore` exactly what the tool
exists to prevent. The old destination therefore lands in the trash with its own
deletion-log record and comes back with `rm --restore <name>`, which the success
message says out loud.

`move_to_trash` takes an optional third argument: a `device:inode` the caller has
already proven. `--restore` passes the destination's identity, so the clearing
step is bound to the object that was verified rather than to a pathname.

**Closed:** no destination shape can lose data to a recursive delete any more,
because there is no recursive delete on the route. A same-UID process that swaps
the destination between the identity proof and the clearing step is detected and
the restore aborts at exit 1 with nothing moved (measured: deterministic
injection, 1 of 1 aborted, all three parties intact).

**Narrowed, not closed:** the interval inside `move_to_trash` between its last
`stat` of the source and its `mv`. A same-UID process that swaps the destination
pathname inside that interval gets *its own* directory moved into the trash.
This cannot be closed in POSIX shell: there is no way to bind a name to an inode
for `rename`, i.e. no way to act through a handle only this process can produce.
What changed is the consequence, not the probability: the worst case is now a
logged, reversible move into the trash instead of an irreversible `rm -rf`.
Measured with deterministic injection at that exact window: 1 of 1 swapped, the
unrelated directory intact in the trash and restorable, `0` bytes destroyed. Note
the residual is *misfiled*, not lost — the log records the destination's path, so
the unrelated directory comes back under the destination's name. This is the same
window every ordinary `rm` through this tool already has; `--restore` is no longer
worse than the tool's own baseline.

**Not a promise:** when `rename` *can* replace the destination atomically (both
sides are non-directories), the kernel unlinks the old destination and it is gone,
exactly as `mv -f` would leave it. Only the shapes that need clearing get the
trash treatment.

Exit contract, because "partially successful" must not read as success:
`0` = restored and nothing unintended was touched — a destination that was
renamed away by the kernel, moved into the trash, or set aside in place is not
"unintended", and every one of those is said out loud, including the case where
the set-aside reached the trash but its deletion-log record did not (there the
message must not repeat the `rm --restore <name>` instruction, which would answer
"no deletion record found"); `1` = the restore did not happen and the error names
anything that could not be put back — including a cross-device copy that already
consumed the trash source, whose staging path is printed outright; `2` = the item
*was* restored but a leftover could not be cleaned up, and the leftover path is
printed.

### Cross-device restores

The trash and the destination are often on different filesystems: an external
drive, a network mount or a second APFS volume combined with the default
`$HOME/.Trash`. There `mv` degrades into copy-then-unlink, so the inode
**necessarily** changes and inode equality cannot be the acceptance test — using
it made every cross-device restore fail after the trash source had already been
consumed, leaving the user's only copy in the staging directory while the log
still pointed at a trash path that no longer existed.

The acceptance test is therefore split by device. Same device: `mv` is a `rename`,
the inode must be preserved, strict equality applies. Different device: the source
must be gone, something must exist at the staging path, and that path must not be
the "a concurrent process pre-created a directory and the item was moved inside
it" shape. That last condition is sound rather than heuristic — had the staging
path pre-existed, `mv -n` would have done nothing and left the source in place.
Inode identity is unusable across devices; these three conditions are the
strongest evidence a shell has on this platform.

Note that only the staging↔trash leg can cross devices. The staging directory is
created inside the destination's own parent, so staging↔destination is always a
same-device `rename` and the publish step keeps its strict inode check — against
the *staged* object's identity, not against an inode that no longer exists.

The suite reproduces both decisive properties with a `stat` shim (the trash
subtree reports a different device number) and an `mv` shim (a source inside the
trash moves by copy+unlink), so CI covers this without mounting a second
filesystem. Both were cross-checked against a real 40 MB HFS+ disk image: the
pre-fix binary fails and the fixed binary succeeds, identically under the shims
and on the real second device.

### Clearing the destination when the trash volume has no room

Routing the old destination into the trash instead of `rm -rf`-ing it costs
something the `rm -rf` shape did not: **space**. Across devices that move is a
full copy, and the trash volume has to hold it. Measured on a real 20 MB HFS+
volume with a 41 MB destination directory, the trash route died of `ENOSPC` half
way and left the worst possible state — exit 1, a permanent 20 MB half-copy on
the trash volume that no message mentioned, the user's file stranded in the
staging directory rather than restored, and the trash source the log pointed at
already consumed, so the next `--restore` answered "not found". The `rm -rf`
shape had none of that: it *freed* space instead of consuming it.

So the route is now measured before it is taken. When the destination and the
trash landing directory are on different devices, the landing filesystem's free
space (`df -Pk`) is compared against the destination's size (`du -sk`); if it
does not fit, the destination is set aside **in place** instead: an exclusively
created `<dest>.better-rm-displaced-XXXXXX` directory in the destination's own
parent, reached by a same-filesystem `rename` that needs no space at all. The
restore then completes, both objects survive, and the message names the exact
path — `rm --restore` cannot reach an in-place set-aside, and saying otherwise
would be the same lie in a different place. Two properties keep this from being a
back door:

- A **protected** destination never takes the in-place route. `move_to_trash`
  refuses those on principle rather than for lack of space, and routing around
  that refusal would dismantle the `.git` protection.
- The in-place route is also the fallback when the trash route fails anyway
  (space that ran out after the measurement, a momentarily unwritable trash), but
  only while the destination is still, by inode, the object that was verified. A
  mismatching identity is a different object and aborts as before.

Same-device destinations are untouched by all of this: that clearing step is a
`rename`, which never needed space. The measurement is a decision input, not a
guarantee — `du` and `df` can both be wrong about a compressed, sparse or
hard-linked tree, and space can disappear between the measurement and the copy.
That residual is what the fallback above exists for; what remains after both is
an `ENOSPC` mid-copy whose partial copy `mv` leaves in the trash, which is the
tool's own pre-existing behaviour for an ordinary `rm` of a file too large for
the trash volume (same on `main`, unchanged here).

### Disclosed, not fixed

- **The `HASH` column describes the object as it was when it was hashed, not
  necessarily what is in the trash.** `move_to_trash` hashes the source, then
  reserves a name, re-verifies the source's `device:inode`, and moves. The inode
  check catches a *swapped* object, but not a rewrite of the same inode or a
  change inside the same directory — deterministic injection at that window
  (adding a file to the source tree between the hash and the `mv`) produces a
  logged hash of `481f8e…` for a tree that hashes `2924aa…` once in the trash,
  and the trash pathname embeds the same stale hash. This is identical on `main`
  (measured, same injection) and applies to any `rm`, not only to `--restore`.
  It is not fixed because the hash is advisory — it disambiguates trash paths and
  records what was deleted — and re-hashing after the move would require renaming
  the trash entry afterwards, i.e. adding a race to remove a label error. Do not
  use this column as an integrity proof of the trash contents.
- **`--restore` hard-depends on `mktemp`.** The whole overwrite path is built on
  a staging directory only this process can have created, under a name it cannot
  predict; there is no safe fallback for a missing `mktemp`, so `--restore` fails
  closed and now says which tool is missing rather than only that the directory
  could not be created. `main` restores without `mktemp` because it had no such
  directory — it displaced by a predictable `$$`-suffixed name and `rm -rf`'d it,
  which is the defect this whole section exists to remove. Deletion is
  unaffected; only `--restore` needs it.
- **The exit-1 wording for a set-aside that reached the trash unlogged** (the
  publish then failing as well) is the one message branch here with no test: it
  needs a log-write failure and a publish failure in the same run. Its sibling on
  the success path is covered.

## Suggested Future Enhancements

### High Priority
- [x] Implement restore functionality (`rm --restore`)
- [ ] Add trash management commands (list, clean, empty)
- [ ] Automatic cleanup of old trashed files
- [ ] Configuration file support (~/.better-rm.conf)

### Medium Priority
- [ ] Enhanced hash calculation for large directories
- [ ] Trash statistics and reporting
- [ ] Integration with file managers
- [ ] Support for network filesystems

### Low Priority
- [ ] GUI for trash management
- [ ] Scheduled trash cleanup
- [ ] Compression of old trashed files
- [ ] Cloud backup integration

## Testing New Features

When implementing new features, ensure comprehensive testing:

```bash
# Create test environment
mkdir -p /tmp/test-better-rm
cd /tmp/test-better-rm
TRASH_DIR=/tmp/test-trash

# Test scenarios
# 1. Regular files
echo "content" > file.txt
better-rm -v file.txt

# 2. Empty files/directories
touch empty.txt
mkdir emptydir
better-rm -v empty.txt
better-rm -rv emptydir

# 3. Special characters
touch "file with spaces.txt"
better-rm -v "file with spaces.txt"

# 4. Rapid deletions
for i in {1..10}; do echo "$i" > "file$i.txt"; done
better-rm -v file*.txt

# 5. Large directories
mkdir largedir
for i in {1..1000}; do echo "content $i" > "largedir/file$i.txt"; done
better-rm -rv largedir

# Clean up
rm -rf /tmp/test-better-rm /tmp/test-trash
```

## Contributing

When contributing to this project:

1. Follow the existing code style and patterns
2. Add tests for new functionality
3. Update CHANGELOG.md with your changes
4. Ensure all automated checks pass
5. Request review from maintainers

## Contact

For questions about the development process or AI agent configurations, please open an issue on GitHub.
