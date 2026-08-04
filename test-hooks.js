#!/usr/bin/env node
// Tests for cross-agent protected-directory hooks.
// 跨代理受保護目錄 hook 測試。

'use strict';

const assert = require('assert');
const { evaluate } = require('./hooks/protect-important-paths');

const env = { HOME: '/home/tester', BETTER_RM_PROTECTED_DIRS: '/workspace/secrets' };

function claude(command, cwd = '/workspace/project') {
  return { hook_event_name: 'PreToolUse', tool_name: 'Bash', tool_input: { command }, cwd };
}

function copilot(command, cwd = '/workspace/project') {
  return { toolName: 'bash', toolArgs: JSON.stringify({ command }), cwd };
}

const blocked = [
  'rm -rf /',
  'sudo rm -rf /etc',
  'sudo -u root rm -rf /var',
  'env LC_ALL=C rm -rf /boot',
  'SAFE=1 rm -rf /opt',
  'rm -rf /mnt',
  'rm -rf /mnt/c',
  'rm -rf /mnt/../mnt/wsl',
  'command rm -r ~/.git',
  'rm -rf .git',
  'rm -rf .*',
  'rm -rf {.git,dist}',
  '/bin/rm -rf ../project/.git/',
  'rmdir /home/tester',
  'rm -rf /workspace/secrets',
  'echo ok && rm -rf /usr',
  "bash -c 'rm -rf /'",
  "/bin/sh -lc 'rm -rf \"$HOME\"'",
  "env SAFE=1 zsh -c 'command rm -rf .git'",
  "bash -c \"sh -c 'rm -rf /usr'\"",
  "sudo env SAFE=1 bash -c 'rm -rf /usr'",
  "sudo -nHu root rm -rf /usr",
  "sudo -nBu root rm -rf /usr",
  "sudo -inu root rm -rf /usr",
  "sudo -r staff_r rm -rf /usr",
  "sudo --role staff_r rm -rf /usr",
  "sudo --ro staff_r rm -rf /usr",
  "sudo -t staff_t rm -rf /usr",
  "sudo --type staff_t rm -rf /usr",
  "sudo --t staff_t rm -rf /usr",
  "env SAFE=1 command bash -c 'rm -rf /usr'",
  "command env SAFE=1 bash -c 'rm -rf /usr'",
  "env -u PATH bash -c 'rm -rf /usr'",
  "env -iu HOME bash -c 'rm -rf /usr'",
  "env -C /tmp command bash -c 'rm -rf /usr'",
  "env -S \"bash -c 'rm -rf /usr'\"",
  "env -ivS\"bash -c 'rm -rf /usr'\"",
  "env --split-string=\"bash -c 'rm -rf /usr'\"",
  "bash -c 'if true; then rm -rf /usr; fi'",
  "bash -c 'if rm -rf /usr; then true; fi'",
  "bash -c 'for x in a; do rm -rf /usr; done'",
  "bash -c 'while rm -rf /usr; do break; done'",
  "bash -c 'until rm -rf /usr; do break; done'",
  "bash -c '{ rm -rf /usr; }'",
  "bash -c '(rm -rf /usr)'",
  "bash -c 'case x in x) rm -rf /usr;; esac'",
  "bash -c 'f() { rm -rf /usr; }; f'",
  "bash -c 'function cleanup { rm -rf /usr; }; cleanup'",
  "bash -c '! rm -rf /usr'",
  "bash -c 'time -p rm -rf /usr'",
  "bash -c 'exec -a cleanup rm -rf /usr'",
  "bash -c 'exec -cla cleanup rm -rf /usr'",
  "bash -c 'coproc rm -rf /usr'",
  "bash -c 'coproc CLEANUP rm -rf /usr'",
  "bash -c 'coproc { rm -rf /usr; }'",
  "bash -c 'coproc CLEANUP { rm -rf /usr; }'",
  "bash -c 'coproc (rm -rf /usr)'",
  "bash -c 'coproc CLEANUP (rm -rf /usr)'",
  "bash -c 'coproc CLEANUP SAFE=1 rm -rf /usr'",
  "bash -c 'coproc CLEANUP if rm -rf /usr; then true; fi'",
  "bash -c \"coproc CLEANUP eval 'rm -rf /usr'\"",
  "bash -c 'nohup rm -rf /usr'",
  "bash -c 'nice -n 5 rm -rf /usr'",
  "bash -c 'timeout --signal TERM 1 rm -rf /usr'",
  "bash -c 'timeout -vk 1 2 rm -rf /usr'",
  "bash -c 'setsid --fork rm -rf /usr'",
  "bash -c '/usr/bin/time -po /tmp/timing rm -rf /usr'",
  "bash -c '/usr/bin/time -ho /tmp/timing rm -rf /usr'",
  "cat <(rm -rf /usr)",
  "echo hi > >(rm -rf /usr)",
  "bash -c 'cat <(rm -rf /usr)'",
  "fish -C 'rm -rf /usr'",
  "fish --init-command 'rm -rf /var'",
  "fish --command='rm -rf /usr'",
  "bash -c $'rm -rf /boot'",
  "bash -c $'rm -rf \\x2fboot'",
  "bash -c $'rm -rf \\057var'",
  "bash -c $'printf ok\\nrm -rf /usr'",
  "eval 'rm -rf /var'",
  'echo "$(rm -rf /boot)"',
  "printf '%s' \"`rm -rf /usr`\"",
  'rm -rf "$(printf /)"',
  'rm -rf "$TARGET"',
  'HOME=/ rm -rf "$HOME/etc"',
  // A wrapper that ends exactly on a command separator must not swallow it and
  // hide the following rm (regression: unconditional i += 1 after unwrap).
  'sudo -k; rm -rf /etc',
  'sudo -v; rm -rf /etc',
  'sudo -k | rm -rf /etc',
  'nice -n 10\nrm -rf /etc',
  'timeout 5\nrm -rf /etc',
  'env\nrm -rf /etc',
  // A redirection placed before the target must not truncate rm's target scan.
  'rm >/dev/null /etc',
  'rm 2>/dev/null -rf /etc',
  'rm >out -rf /etc',
  // ANSI-C escapes that mint a NUL: real shells truncate the arg at the NUL,
  // so the guard must compare the pre-NUL path (/etc), not '/etc\0'.
  "bash -c $'rm -rf /etc\\x00'",
  "bash -c $'rm -rf /etc\\0'",
  "bash -c $'rm -rf /etc\\000'",
  "bash -c $'rm -rf /etc\\c@'",
  "rm -rf $'/etc\\x00'",
  // \u and \U ANSI-C unicode escapes must decode to the protected path.
  "bash -c $'rm -rf \\u002fetc'",
  "bash -c $'rm -rf \\U0000002fboot'",
];

const allowed = [
  'rm -rf build',
  'rm file.txt',
  'rm -rf /mnt/c/project',
  'echo rm -rf /',
  'better-rm -r tmp',
  "bash -c 'rm -rf build'",
  "bash -c 'echo rm -rf /'",
  "fish -C 'rm -rf build'",
  "fish --init-command 'echo rm -rf /usr'",
  "fish --command='echo rm -rf /usr'",
  "bash -c $'rm -rf build'",
  "bash -c $'rm -rf build\\x2foutput'",
  "bash -c $'echo rm -rf \\057var'",
  "bash -c $'printf rm\\n-rf /usr'",
  "echo '$(rm -rf /)'",
  "env -S \"bash -c 'rm -rf build'\"",
  "env -ivS\"bash -c 'rm -rf build'\"",
  "env -iu HOME bash -c 'rm -rf build'",
  "bash -c 'if true; then rm -rf build; fi'",
  "bash -c 'if rm -rf build; then true; fi'",
  "bash -c 'for x in a; do rm -rf build; done'",
  "bash -c 'while rm -rf build; do break; done'",
  "bash -c 'until rm -rf build; do break; done'",
  "bash -c '{ rm -rf build; }'",
  "bash -c '(rm -rf build)'",
  "bash -c 'case x in x) rm -rf build;; esac'",
  "bash -c 'f() { rm -rf build; }; f'",
  "bash -c 'function cleanup { rm -rf build; }; cleanup'",
  "bash -c '! rm -rf build'",
  "bash -c 'time -p rm -rf build'",
  "bash -c 'exec -a cleanup rm -rf build'",
  "bash -c 'exec -cla cleanup rm -rf build'",
  "bash -c 'coproc rm -rf build'",
  "bash -c 'coproc CLEANUP rm -rf build'",
  "bash -c 'coproc { rm -rf build; }'",
  "bash -c 'coproc CLEANUP { rm -rf build; }'",
  "bash -c 'coproc (rm -rf build)'",
  "bash -c 'coproc CLEANUP (rm -rf build)'",
  "bash -c 'coproc CLEANUP SAFE=1 rm -rf build'",
  "bash -c 'coproc CLEANUP if rm -rf build; then true; fi'",
  "bash -c \"coproc CLEANUP eval 'rm -rf build'\"",
  "bash -c 'coproc echo rm -rf /usr'",
  "bash -c 'coproc CLEANUP echo rm -rf /usr'",
  "bash -c 'nohup rm -rf build'",
  "sudo -nHu root rm -rf build",
  "sudo -nBu root rm -rf build",
  "sudo -inu root rm -rf build",
  "sudo -r staff_r rm -rf build",
  "sudo --role staff_r rm -rf build",
  "sudo --ro staff_r rm -rf build",
  "sudo -t staff_t rm -rf build",
  "sudo --type staff_t rm -rf build",
  "sudo --t staff_t rm -rf build",
  "bash -c 'nice -n 5 rm -rf build'",
  "bash -c 'timeout --signal TERM 1 rm -rf build'",
  "bash -c 'timeout -vk 1 2 rm -rf build'",
  "bash -c 'setsid --fork rm -rf build'",
  "bash -c '/usr/bin/time -po /tmp/timing rm -rf build'",
  "bash -c '/usr/bin/time -ho /tmp/timing rm -rf build'",
  "cat <(printf safe)",
  "echo 'cat <(rm -rf /usr)'",
  "rm -rf '$literal'",
  'rm -rf \\$literal',
  // Redirections trailing an unprotected target stay allowed.
  'rm -rf build >/dev/null',
  'rm -rf build 2>/dev/null',
];

// Finding: a shell carrier nested past the recursion depth cap (8) must fail
// closed — commandTargets yields '/', so evaluate denies — even though the
// innermost command targets only an unprotected path.
let deeplyNestedCarrier = 'rm -rf build';
for (let depthLevel = 0; depthLevel < 10; depthLevel += 1) {
  deeplyNestedCarrier = `bash -c ${JSON.stringify(deeplyNestedCarrier)}`;
}
blocked.push(deeplyNestedCarrier);

for (const command of blocked) {
  const result = evaluate(claude(command), env);
  assert.equal(result?.hookSpecificOutput?.permissionDecision, 'deny', command);
}
for (const command of allowed) {
  assert.equal(evaluate(claude(command), env), null, command);
}

const copilotResult = evaluate(copilot('rm -rf .git'), env);
assert.equal(copilotResult.permissionDecision, 'deny');
assert.match(copilotResult.permissionDecisionReason, /Refused to remove protected directory/);

// Antigravity tests
function antigravity(command, cwd = '/workspace/project') {
  return {
    conversationId: 'test-uuid-12345',
    workspacePaths: ['/workspace/project'],
    stepIdx: 1,
    toolCall: {
      name: 'run_command',
      args: {
        CommandLine: command,
        Cwd: cwd
      }
    }
  };
}

for (const command of blocked) {
  const result = evaluate(antigravity(command), env);
  assert.equal(result.allow_tool, false, command);
  assert.match(result.deny_reason, /Refused to remove protected directory/, command);
}

for (const command of allowed) {
  assert.equal(evaluate(antigravity(command), env).allow_tool, true, command);
}

// Pi coding agent tests
const piResult = evaluate({ tool_input: { command: 'rm -rf .git' }, cwd: '/workspace/project' }, env);
assert.equal(piResult?.hookSpecificOutput?.permissionDecision, 'deny');
assert.match(piResult?.hookSpecificOutput?.permissionDecisionReason, /Refused to remove protected directory/);

// Cursor tests
function cursor(command, cwd = '/workspace/project') {
  return {
    hook_event_name: 'beforeShellExecution',
    command,
    cwd
  };
}

for (const command of blocked) {
  const result = evaluate(cursor(command), env);
  assert.equal(result.permission, 'deny', command);
  assert.match(result.user_message, /Refused to remove protected directory/, command);
}

for (const command of allowed) {
  assert.equal(evaluate(cursor(command), env).permission, 'allow', command);
}

// Grok Build tests
function grok(command, cwd = '/workspace/project') {
  return {
    hookEventName: 'PreToolUse',
    sessionId: 'test-session-555',
    cwd,
    workspaceRoot: '/workspace/project',
    toolName: 'Bash',
    toolInput: {
      command
    }
  };
}

for (const command of blocked) {
  const result = evaluate(grok(command), env);
  assert.equal(result.decision, 'deny', command);
  assert.match(result.reason, /Refused to remove protected directory/, command);
}

for (const command of allowed) {
  assert.equal(evaluate(grok(command), env).decision, 'allow', command);
}

// The parse/error path must fail CLOSED. Claude Code PreToolUse treats only
// exit code 2 as a blocking error; exit 1 is non-blocking and lets the tool
// run despite the "tool call denied" message.
const { spawnSync } = require('child_process');
let errorPathChecks = 0;
for (const badInput of ['not-json{', '', '{"tool_input":']) {
  const child = spawnSync('node', [`${__dirname}/hooks/protect-important-paths.js`], { input: badInput });
  assert.equal(child.status, 2, `malformed hook input must exit 2 (blocking), got ${child.status}`);
  errorPathChecks += 1;
}

// A command word that only exists after expansion (`CMD=rm; $CMD -rf /`) is
// still `rm` when the shell runs it, so the hook must fail closed on it. These
// run through the real stdin JSON contract, because that is the seam every
// agent actually uses; `evaluate()` alone cannot prove the deployed path works.
// 命令字必須展開後才知道是什麼（`CMD=rm; $CMD -rf /`），shell 執行時仍是 rm，
// 因此 hook 必須失敗關閉；此處走真正的 stdin JSON 契約。
function runHookOverStdin(payload) {
  const child = spawnSync('node', [`${__dirname}/hooks/protect-important-paths.js`], {
    input: JSON.stringify(payload),
    encoding: 'utf8',
    env: { ...process.env, ...env },
  });
  return { status: child.status, stdout: child.stdout };
}

const dynamicExecutableBlocked = [
  // Positive control: the literal form was already blocked and must stay blocked.
  'rm -rf /',
  'CMD=rm; $CMD -rf /',
  'CMD=/bin/rm; "$CMD" -rf /',
  'CMD=rmdir; $CMD /etc',
  'CMD=rm; ${CMD} -rf /var',
  'CMD=rm; sudo $CMD -rf /usr',
  // An unresolvable command word may also be a shell carrier.
  "CMD=bash; $CMD -c 'rm -rf /'",
  'CMD=rm; $CMD -rf .git',
  // A command substitution in the executable position is just as unresolvable.
  // These parsed as the word `$` followed by a `(` separator, which both hid
  // the executable and truncated the operand scan before the target.
  '$(which rm) -rf /',
  '`which rm` -rf /',
  '$(echo rm) -rf /',
  '$(echo $(echo rm)) -rf /',
  '"$(which rm)" -rf /',
  '$(which rmdir) /etc',
  'sudo $(which rm) -rf /etc',
  '/bin/$(echo rm) -rf /',
  '$(echo /bin)/rm -rf /',
  '$((0))$(echo rm) -rf /boot',
  'nohup $(which rm) -rf /',
  'env SAFE=1 $(which rm) -rf /',
  'true && $(which rm) -rf /',
  'true | $(which rm) -rf /',
  '$(which bash) -c "rm -rf /"',
];

const dynamicExecutableAllowed = [
  // Negative controls: the guard must not become a blanket deny. A protected
  // path handed to a non-deleting command was allowed before and stays allowed;
  // an unresolvable command word with a harmless operand stays allowed too.
  'ls',
  'ls -la /etc',
  'cat /etc/hosts',
  '$EDITOR notes.txt',
  'CMD=ls; $CMD build',
  '$(which ls) build',
  '$(npm bin)/eslint src',
  "echo '$(which rm) -rf /'",
];

// Every row of the false-denial tables in README.md and CHANGELOG.md. The docs
// claim these verdicts were measured rather than reasoned about; pinning them
// here is what keeps that true, and stops the tables drifting from the parser.
const documentedDenials = [
  '$(which docker) run -v $(pwd):/work img ls',
  '"$(which docker)" run -v $(pwd):/work img ls',  // double quotes do not exempt
  '$(brew --prefix)/bin/rg "$PATTERN" src/',
  '$(which git) -C $(pwd) status',                 // separated from its option
  '$(which cat) $HOME/.zshrc',
  '$(which echo) $USER',
  '$(which echo) /etc',                            // operand need not be dynamic
  '$(which echo) ~',                               // bare ~ IS the protected home
  '`which git` status',                            // backtick with whitespace
  '`command -v ls`',                               // ... even with no operands
];
const documentedAllowances = [
  'docker run -v $(pwd):/work img ls',             // static executable
  '$(command -v python3) ./build.py',
  '$(which make) -j$(nproc) all',                  // adjacent to its option
  '$(which git) -C$(pwd) status',
  "$(which cat) '$HOME/.zshrc'",                   // single quotes are literal
  '$(which cat) ~/.zshrc',
  '`pwd` status',                                  // backtick without whitespace
  'cd $(git rev-parse --show-toplevel)',
];

let stdinChecks = 0;
for (const command of dynamicExecutableBlocked) {
  const { status, stdout } = runHookOverStdin(claude(command));
  assert.equal(status, 0, `${command} (exit)`);
  let parsed = null;
  try { parsed = JSON.parse(stdout); } catch (_) { parsed = null; }
  assert.equal(
    parsed?.hookSpecificOutput?.permissionDecision,
    'deny',
    `dynamic executable must fail closed: ${command} (stdout: ${JSON.stringify(stdout)})`
  );
  stdinChecks += 1;
}
for (const command of dynamicExecutableAllowed) {
  const { status, stdout } = runHookOverStdin(claude(command));
  assert.equal(status, 0, `${command} (exit)`);
  assert.equal(stdout, '', `benign command must stay allowed: ${command}`);
  stdinChecks += 1;
}
for (const command of documentedDenials) {
  const { status, stdout } = runHookOverStdin(claude(command));
  assert.equal(status, 0, `${command} (exit)`);
  let parsed = null;
  try { parsed = JSON.parse(stdout); } catch (_) { parsed = null; }
  assert.equal(
    parsed?.hookSpecificOutput?.permissionDecision,
    'deny',
    `documented as denied, but allowed: ${command}`
  );
  stdinChecks += 1;
}
for (const command of documentedAllowances) {
  const { status, stdout } = runHookOverStdin(claude(command));
  assert.equal(status, 0, `${command} (exit)`);
  assert.equal(stdout, '', `documented as allowed, but denied: ${command}`);
  stdinChecks += 1;
}

// A truncated or 0-byte hook file cannot be told apart from a hook that allows,
// under the two contracts where allow IS the absence of output: Claude Code and
// Copilot both receive null from evaluate() and therefore no stdout. (Cursor,
// Grok and Antigravity expect an explicit allow object instead, so empty output
// is not a valid allow for them and their handling of it is not measured here.)
// Nothing inside the hook can change that, so the property has to be owned by
// whoever writes the file — install-hooks.sh proves the freshly written hook
// still denies, and otherwise leaves a stub that exits 2. These assertions pin
// both halves: that the hazard is real (so the installer-side guarantee is not
// dead weight someone may delete), and that the stub the installer actually
// writes is never read as an allow.
const fs = require('fs');
const os = require('os');
const denyPayload = JSON.stringify(claude('rm -rf /', '/'));
const scratch = fs.mkdtempSync(`${os.tmpdir()}/better-rm-hook-shape-`);
let hookShapeChecks = 0;

const realHook = spawnSync('node', [`${__dirname}/hooks/protect-important-paths.js`], { input: denyPayload, encoding: 'utf8', env: { ...process.env, ...env } });
assert.equal(realHook.status, 0, 'the real hook exits 0');
assert.match(realHook.stdout, /"permissionDecision":"deny"/, 'the real hook denies a protected deletion');
hookShapeChecks += 1;

const emptyHook = `${scratch}/empty.js`;
fs.writeFileSync(emptyHook, '');
const emptyResult = spawnSync('node', [emptyHook], { input: denyPayload, encoding: 'utf8' });
assert.equal(emptyResult.status, 0, 'a 0-byte hook exits 0');
assert.equal(emptyResult.stdout, '', 'a 0-byte hook prints nothing');
// Same shape as an explicit allow under both no-output contracts: this is the
// disarmed state the installer must never leave behind.
assert.equal(evaluate(claude('ls'), env), null, 'Claude Code allow is no output');
assert.equal(evaluate(copilot('ls'), env), null, 'Copilot allow is no output');
hookShapeChecks += 1;

// Read the stub the installer really writes rather than restating it here: a
// literal copy would keep passing after write_fail_closed_hook_stub was changed
// to exit 0, which is the exact failure this is meant to catch.
const stubHook = `${scratch}/stub-from-installer.js`;
const stubExtraction = spawnSync('bash', [
  '-c',
  'eval "$(sed -n "/^write_fail_closed_hook_stub()/,/^}/p" "$1")"; write_fail_closed_hook_stub "$2"',
  'extract-stub',
  `${__dirname}/install-hooks.sh`,
  stubHook,
], { encoding: 'utf8' });
assert.equal(stubExtraction.status, 0, `extracting the installer's stub writer failed: ${stubExtraction.stderr}`);
assert.ok(fs.statSync(stubHook).size > 0, "the installer's stub must not be empty");
const stubResult = spawnSync('node', [stubHook], { input: denyPayload, encoding: 'utf8' });
assert.equal(stubResult.status, 2, "the installer's stub exits 2 (blocking for PreToolUse)");
assert.equal(stubResult.stdout, '', "the installer's stub prints no allow");
hookShapeChecks += 1;

// The installer's own probe, extracted from install-hooks.sh and exercised
// directly. Driving it through a real install cannot pin these properties: when
// the source hook is itself bad, the probe's positive control (which asks
// whether the SOURCE denies) cannot tell that apart from a broken probe. So the
// three properties are pinned here, on the function itself.
function runInstallerProbe(hookFile) {
  return spawnSync('bash', [
    '-c',
    'eval "$(sed -n "/^hook_denies_protected_deletion()/,/^}/p" "$1")"; hook_denies_protected_deletion "$2"',
    'installer-probe',
    `${__dirname}/install-hooks.sh`,
    hookFile,
  ], { encoding: 'utf8', timeout: 120000 });
}

assert.equal(runInstallerProbe(`${__dirname}/hooks/protect-important-paths.js`).status, 0,
  "the installer's probe must accept the real hook");
hookShapeChecks += 1;

// Denying the first payload only. One payload proves the file is not truncated;
// it does not prove the hook protects anything, so the probe must use several.
const selectiveHook = `${scratch}/selective.js`;
fs.writeFileSync(selectiveHook, `
const chunks = [];
process.stdin.on('data', (c) => chunks.push(c));
process.stdin.on('end', () => {
  const payload = JSON.parse(chunks.join(''));
  if (payload.tool_input.command === 'rm -rf /') {
    process.stdout.write(JSON.stringify({ hookSpecificOutput: { permissionDecision: 'deny' } }));
  }
  process.exit(0);
});
`);
assert.notEqual(runInstallerProbe(selectiveHook).status, 0,
  'a hook that denies only the first payload must be rejected');
hookShapeChecks += 1;

// Printing deny while exiting 1: for Claude Code PreToolUse exit 1 is a
// NON-blocking error, so the tool would run despite the deny on stdout.
const denyButExit1 = `${scratch}/deny-exit1.js`;
fs.writeFileSync(denyButExit1, `
process.stdout.write(JSON.stringify({ hookSpecificOutput: { permissionDecision: 'deny' } }));
process.exit(1);
`);
assert.notEqual(runInstallerProbe(denyButExit1).status, 0,
  'a hook that denies but exits 1 must be rejected');
hookShapeChecks += 1;

// A hook that never terminates must not hang the installer forever.
const hangingHook = `${scratch}/hanging.js`;
fs.writeFileSync(hangingHook, 'setInterval(() => {}, 1000);\n');
const hangStarted = Date.now();
const hangResult = runInstallerProbe(hangingHook);
const hangElapsed = Date.now() - hangStarted;
assert.notEqual(hangResult.status, 0, 'a hook that never terminates must be rejected');
assert.ok(hangElapsed < 60000, `the probe must time out, took ${hangElapsed}ms`);
hookShapeChecks += 1;

fs.rmSync(scratch, { recursive: true, force: true });

console.log(`Hooks 測試通過 / Hook tests passed: ${blocked.length * 4 + allowed.length * 4 + 2 + errorPathChecks + stdinChecks + hookShapeChecks}`);
