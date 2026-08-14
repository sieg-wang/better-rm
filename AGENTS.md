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

- **The OpenCode plugin is no longer downloaded at all.** It used to be fetched
  from the release by `resolve_opencode_plugin` whenever `.opencode/plugins/` was
  missing from the distribution, and the only check on what came back was
  "readable regular file" — so a captive-portal page, a truncated body, or
  syntactically valid TypeScript that registers no hook was copied verbatim to
  the executing location at exit 0. The plugin is the bridge that makes OpenCode
  call the verified runtime hook, so that was silently no protection under
  OpenCode. Verifying it the way the runtime hook is verified was rejected:
  proving a plugin really registers a hook and blocks a deletion needs a
  TypeScript runtime (`bun`, or OpenCode itself) that no other installer path
  requires, and hard-failing installs on every machine without one trades a
  silent hole for a loud regression; a string sniff would stop the HTML page but
  not the valid-TypeScript-that-protects-nothing case, which is the dangerous
  one. `write_bundled_opencode_plugin` therefore ships the plugin inside
  `install-hooks.sh`: plugin and installer are one trusted distribution, the
  poisoned channel is gone rather than inspected, and `-a opencode` no longer
  needs the network for the plugin. The cost is that the bundled copy has to
  track `.opencode/plugins/protect-important-paths.ts`; `test-install-hooks.sh`
  pins it by asserting that a distribution without `.opencode/` installs a plugin
  byte-identical to that file, so drift turns the suite red.
  `resolve_opencode_plugin`'s *runtime hook* download branch was left alone for a
  different reason: `resolve_source_paths` already guarantees `HOOK_SOURCE_PATH`
  is readable before it runs, so that branch is unreachable.
- **`-a opencode` did not go through the shared-hook trust check at all.** The
  other eight agents resolve their runtime hook through
  `resolve_shared_hook_for_settings`, whose first install runs
  `hook_is_trustworthy` and, on failure, writes the fail-closed stub and exits
  non-zero. `install_opencode_hooks` never called that function, so publishing
  `hooks/protect-important-paths.js` was a bare `cp` and nothing else. Measured
  with a `cp` that reports success while writing nothing: `claude --global`,
  `claude`, `codex`, `cursor` and `grok` all exited 1 leaving the stub, while
  `opencode` exited **0 with a 0-byte runtime hook** — and a 0-byte hook exits 0
  with no output, which the contract reads as allow-everything. The guard was
  fully disarmed while the install reported success.
  `require_verified_opencode_runtime` now runs the same check after both of that
  path's writes.
- **What each opencode guard actually needs, measured.** The runtime guard has two
  verifiers and needs **either**: the behavioural probe (`node`) or the byte
  comparison (`cmp`, against `OPENCODE_RUNTIME_SOURCE_PATH`, which *is*
  `HOOK_SOURCE_PATH`). The plugin guard has only `cmp`. Neither is an absolute
  requirement, because both guards read `cmp`'s status as the tri-state it is:

  | available | runtime hook | plugin |
  |---|---|---|
  | `node` + `cmp` | probe, then `cmp` as fallback | `cmp` |
  | `cmp` only | `cmp`, with the byte-comparison warning | `cmp` |
  | `node` only | probe | warns "could not verify", proceeds |
  | neither | warns "could not verify", proceeds | warns "could not verify", proceeds |

  Evidence of corruption always fails closed; absence of measurement never does.
  Measured healthy installs exit 0 in all four rows with both files genuine, which
  matches main. Measured corrupt installs still exit 1 wherever any verifier can
  run — including "no `node`, `cmp` present, truncated runtime hook", which leaves
  the fail-closed stub.
- **`cmp`'s exit status is tri-state, not boolean: 0 same, 1 different, ≥2 the
  comparison could not run.** Both guards shipped briefly with `≥2` folded into
  "different", and that abort produced a *false diagnosis*: with an `exit 127`
  `cmp` on `PATH` the plugin landed byte-perfect, the install aborted anyway, the
  runtime hook was never installed, and the message said "it may be a partial
  copy". The threshold is pinned at exactly **2**, not at some larger number: an
  actual `cmp` error returns 2, and 127 is only the missing-binary case, so a `≥3`
  threshold misreports the most common error code as a mismatch. A same-week
  sibling of this bug appeared in `launchd-tools` (`! cmp -s … 2>/dev/null`), so it
  is worth stating flatly: never use `cmp` as a boolean.
- **Get the trigger condition right: a full disk is LOUD, not silent.** Measured
  on both trees, a `cp` that fails with ENOSPC exits non-zero, lands nothing, and
  the install exits 1 on every agent including `opencode`. The silent shape is
  the *other* one — a `cp` that reports success but writes nothing — which is
  rare on a local filesystem and is the whole reason a write tool's exit status
  cannot stand in for verification. Do not describe this residual as "a full disk
  can leave a truncated file at exit 0"; that was measured false.
- **What the plugin's check does and does not do.** `require_faithful_opencode_plugin`
  compares the published plugin against its source after the copy, so a partial
  write aborts loudly instead of landing silently whenever `cmp` can run (see the
  table above for what happens when it cannot). It proves the copy is faithful,
  not that the plugin protects anything — the plugin is TypeScript and a
  behavioural probe would need a TypeScript runtime the installer does not
  require, so the source's own correctness rests on the bundled copy's
  byte-identity test. Unlike the runtime hook, a failure leaves **no fail-closed
  replacement**: that would need a separate TypeScript stub. The bad copy stays on
  disk, the message says so, and re-running the installer repairs it.
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

**Now a promise, and it used to read as the opposite here:** the publish `rename`
is always `-n` and never replaces anything. Consent names the object that occupied
the destination when the restore began, and that object has already been set aside
before the publish runs, so the destination is empty by construction. Anything
occupying it at publish time therefore arrived *after* the set-aside and was never
consented to: the publish fails, the unwind runs, and both objects survive. The
`-f` this paragraph used to describe had exactly one remaining subject — that
successor — and destroyed it with no trash entry and no backup (measured, exit 0).

The two paragraphs above this one predate `60c2efa` and describe a narrower
clearing rule than the code has had since: every occupant is set aside now, not
only the shapes `rename` could not replace.

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

It is a **degraded** outcome and says so at every channel a caller might read.
The displaced object is outside the trash and outside the deletion log, so
clearing it up is work the user has to do, and an outcome that leaves work behind
must not be spelled the same way as one that does not. `--restore` therefore
exits `2` on this route — the code it already used for "the item was restored but
a named residue is left" — and the set-aside path is printed on **stdout as well
as stderr**, uncoloured, so a caller that discards stderr still learns where the
object went. Measured before that change: exit `0`, zero bytes of stdout, and the
only trace on a stream the shape `rm -f --restore x 2>/dev/null` throws away.

Same-device destinations are untouched by all of this: that clearing step is a
`rename`, which never needed space. The measurement is a decision input, not a
guarantee — `du` and `df` can both be wrong about a compressed, sparse or
hard-linked tree, and space can disappear between the measurement and the copy.
That residual is what the fallback above exists for; what remains after both is
an `ENOSPC` mid-copy whose partial copy `mv` leaves in the trash, which is the
tool's own pre-existing behaviour for an ordinary `rm` of a file too large for
the trash volume (same on `main`, unchanged here).

### Disclosed, not fixed

- **The `-exec` branch shares the wrapper list with command position, not the
  decision.** Both call `resolveExecutable`, so `-exec sudo rm`, `-exec nice rm`
  and `-exec env SAFE=1 command rm` are all read as rm. Command position has
  three further rules the find branch does not: it fails closed on a command word
  that only exists after expansion, it fails closed on operands that arrive via
  `xargs`, and it descends into shell carriers. So `find . -exec sh -c 'rm -rf
  /etc' \;` (and the `bash`/`zsh`/`sudo sh` spellings), `-exec $CMD -rf /etc`,
  an rm reached through `xargs`, and a nested `find … -exec find … -exec rm` are
  allowed, while the same words written directly are refused. Every one of them
  is allowed at the previous release too; none is a regression. Folding the
  remaining three rules in is a real change with its own over-refusal surface,
  not a one-line addition, which is why it is disclosed rather than done.
- **A variable resolved by the hook is resolved in the HOOK's environment, not
  the command's.** `$HOME`, `$PWD` and `$TMPDIR` are substituted and the result
  is judged by the ordinary rules; everything else stays unknown and is refused.
  Resolution stops for a name the command could change first — an `NAME=`
  assignment anywhere in the text (including the prefix form `HOME=/ rm …`),
  `unset`/`export`/`declare`/`typeset`, and for `$PWD` any `cd`/`pushd`/`popd` —
  and the check is a text scan, so it will occasionally stop resolving for a
  mention that is not an assignment. That direction is deliberate: the fallback
  is a refusal, which is what shipped before. The residual it cannot cover is a
  value that differs between the hook's environment and the command's at
  execution time through some other mechanism; the verdict is then made on the
  hook's value. Low probability, real, and disclosed rather than silent.
  `$HOME` deliberately does NOT fall back to `os.homedir()` the way the
  protected-path check does: that fallback answers "where is home", while
  resolution must answer "what will `$HOME` expand to", and a shell with an empty
  HOME expands `$HOME/build` to `/build`.
  A value carrying whitespace is not resolved at all, because unquoted it is not
  one path: the shell splits it and rm gets several operands, so substituting it
  whole compares a string no argument will ever equal. Measured with
  `TMPDIR='/tmp/x /etc'`, `rm -rf $TMPDIR` removes /etc while the joined word is
  an ordinary unprotected path. The guard cannot see the quoting from where it
  runs, so it assumes the split reading and refuses. The cost is a home directory
  or a TMPDIR with a space in it: on such a machine every `$HOME` command goes
  back to being refused as unknown.
- **A variable is resolved in a TARGET, never in a command word.** An executable
  that only exists after expansion is still assumed to be rm and its operands
  scanned, exactly as before, so `eval ${HOME} /System` is refused although the
  literal `eval /Users/you /System` is not. That is the safe direction and it is
  older than resolution, but it means the variable spelling and the literal
  spelling are interchangeable only in TARGET position — which is where 120,000
  generated commands were diffed against their substituted forms to confirm it,
  finding no case where the variable spelling was the weaker of the two.
- **Two `/` targets still report the protected-directory wording even though the
  command never named `/`.** An rm whose operands arrive on stdin through
  `xargs`, and a command nested past the recursion cap, both push `/` and are
  refused with "protected directory: /". The refusal is right; the wording has
  the same defect the variable case had and was left alone this round only
  because it is a different mechanism with its own rows.
- **The gate stops judging after 2,000 ms and refuses what it did not read.**
  Per-target cost is bounded but the NUMBER of targets is the caller's, and a
  symlink target costs twenty-six `lstat` calls because that is when
  `declaredLink()` compares it against every declared entry. Measured against a
  `/etc` that really is removed: `rm -rf <60,000 relative symlink operands> /etc`
  took 6,215 ms at `d3aed08` in 300 KB of command text, and a 30 MB spelling of
  the same shape never answered at all — past the live 5,000 ms hook timeout,
  which produces NO decision and does not block the call. That is older than
  variable resolution: judging every operand is what this gate has always done.
  A time budget rather than a target count, because per-target cost spans two
  orders of magnitude: a 5,000-target cap was tried first and refused
  `find . -exec rm …x6000` (6,001 targets, 118 ms, deletes nothing, pinned as
  ordinary by the suite). What the budget does NOT cover, stated rather than left
  to be found: the tokenizing pass runs before the first check, at roughly 40 ms
  per megabyte of command text, so a command large enough to outrun the timeout
  on parsing alone is not stopped here. Measured after: the 30 MB shape answers
  in 3.7 s.
- **A `;` is only find's clause terminator when it was NOT written as a shell
  operator.** `;`, `\;` and `';'` tokenize to the same one-character word, so the
  tokenizer records which spelling produced it and the find scan asks. That flag
  is consulted for `;` and for nothing else: only `;` and `+` terminate an
  `-exec` clause (POSIX), so an escaped or quoted `|`, `&` or `(` still ends the
  read. Measured, real BSD find answers `no terminating ";" or "+"` and removes
  nothing for those, so the narrower rule is the accurate one — but it means the
  flag exists for exactly one character, and anyone widening it should expect
  over-refusals rather than new coverage.
- **`+` cannot be added to `terminators`, however obvious it looks.** It ends an
  `-exec` clause exactly as `;` does, so putting it in the set is the natural
  simplification — and it stops the clause skip without ending the find loop, so
  the wrapper scan is re-entered once per clause and the quadratic returns:
  measured 40,561 ms at 20,000 clauses, eight times the hook's own 5 s timeout,
  which means no verdict at all. The `+` question is handled where the blind step
  is instead, in `resolveExecutable`'s `timeout` branch.
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
- **Repeated `rm --restore <name>` no longer walks back through older versions;
  it alternates between the two newest.** `--restore` takes the newest record for
  that name, and the set-aside writes a record of its own, so the object it just
  displaced becomes the newest record and the next call brings it straight back.
  Measured: delete the same filename three times (`V1`, `V2`, `V3`), then run
  `rm -f --restore` five times, and the destination holds `V3`, `V2`, `V3`, `V2`,
  `V3`. `V1` is never reached again after the first restore. It is not lost — it
  is still whole in the trash under its own timestamped path — but no `--restore`
  spelling reaches it; recovering an older version means moving it back by hand,
  or renaming the current occupant out of the way first. This is the price of
  trashing the displaced object instead of destroying it: the old shape really did
  walk backwards, at the cost of permanently destroying one version per step.
  Documented rather than changed, because the fix is a selector (`--restore
  --version N`, or "skip records this call created") and that is an interface
  decision, not a bug fix.
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
