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

- **The release download has no integrity check.** `download_release_file`
  (used when `hooks/` is missing from the checkout) is a bare `curl -fsSL`
  followed only by `[ -f ]` and `[ -r ]`. A captive portal that answers with an
  HTML page installs that page as the runtime hook: the install exits 0 with no
  warning, and the hook then throws a SyntaxError on every invocation — which is
  a non-blocking exit for PreToolUse, i.e. it silently allows everything. A
  checksum or a "does this file actually deny" probe on the downloaded file
  would close it. Note this also limits the claim made in
  `install-hooks.sh`'s `hook_is_trustworthy`: validating the source is normally
  `test-hooks.js`'s job, but a network accident can supply a source that never
  passed through it.
- **First install is not probed.** `resolve_shared_hook_for_settings` copies the
  hook when the destination is missing, and no trust probe runs on that path;
  `hook_is_trustworthy` is only used by the refresh. A corrupted first install is
  therefore accepted silently.
- **`install-hooks.sh:1199` and `:1225`** (OpenCode plugin and runtime) still use
  `stat -f '%Lp' || stat -c '%a'`, which yields concatenated garbage on GNU
  userland and aborts the install mid-write. The shared-hook path no longer reads
  the mode at all; these two were left alone as a separate change. No test
  reaches that branch today, which is why CI never caught it.
- **A broken `sed` extraction would misdirect.** `test-hooks.js` extracts
  `hook_denies_protected_deletion` and `write_fail_closed_hook_stub` from
  `install-hooks.sh` with a `sed` range ending at `/^}/`. Re-indenting the
  embedded JS so a line starts at column zero truncates the extraction, and the
  resulting failure message points at the probe rather than at the extraction.
  An assertion on the extracted line count would save that trip.

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
