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
];

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

console.log(`Hooks 測試通過 / Hook tests passed: ${blocked.length * 4 + allowed.length * 4 + 2}`);
