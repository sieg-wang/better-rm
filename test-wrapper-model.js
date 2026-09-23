#!/usr/bin/env node
// WRAPPER-MODEL GUARD. This file is what replaces the man-page completeness
// sweep, and it makes a DELIBERATELY SMALLER promise than the sweep did.
//
// The sweep walked /usr/share/man, adjudicated candidates, and claimed it would
// "detect an unlisted name". Every time that claim was examined it produced a NEW
// defect -- pages with a `.1m` extension were invisible to its file discovery,
// then `.so` stubs were unresolvable for all 165 base-system stubs, and its
// guarantee text carried wrong figures three separate times. It was not
// converging, so it is gone.
//
// What stands here instead is the shape the hook's three OTHER lists already
// use: SYSTEM_DIRS, HOME_DIRS and MOUNT_PARENTS are a plain pinned list plus a
// test that ITERATES the list. So:
//   1. the pinned names are compared against the table, in BOTH directions, so a
//      name that is deleted goes red and a name that is added goes red until
//      somebody writes it down here too;
//   2. every row of the table is EXERCISED, and the shapes are GENERATED from the
//      row's own valueOptions / clusteredValue / leadingOperands, so a row added
//      tomorrow gets the whole grid -- including the separator grid that the M2
//      regression lived in -- without anybody remembering to add rows;
//   3. completeness across UNLISTED wrappers is NOT GUARANTEED, and this file does
//      not pretend otherwise. The known-unmodelled names are recorded in
//      KNOWN-RESIDUALS.md ("Wrapper completeness is not guaranteed"), measured,
//      with the note that they are ALLOW at git HEAD e1e4277 and therefore
//      pre-existing rather than regressions.
//
// Everything is asked through the REAL STDIN CONTRACT -- a spawned `node <hook>`
// fed the PreToolUse JSON on stdin, verdict read from STDOUT -- because the exit
// code is 0 for both outcomes and reading it would make every row green.
//
// 這支檔案取代 man page 完整性掃描，而且刻意只承諾「更小」的事。那道掃描每次被檢查就生出一
// 個新缺陷（.1m 副檔名看不到、165 個 .so stub 解不開、保證文字三次寫錯數字），不收斂，所以
// 移除。這裡改用 hook 另外三份清單（SYSTEM_DIRS／HOME_DIRS／MOUNT_PARENTS）本來就在用的形
// 狀：固定清單 + 會「走訪清單」的測試。(1) 釘住的名字與表雙向比對：刪掉會紅、加了也會紅，
// 直到有人在這裡寫下來；(2) 每一列都真的被執行，而形狀是從該列自己的 valueOptions /
// clusteredValue / leadingOperands 生成的，所以明天新增的列自動拿到整張格子（含 M2 那個分隔
// 符格子）；(3) 「未列出的包裝命令」的完整性「不保證」，已知未建模的名字寫在
// KNOWN-RESIDUALS.md，有實測、且註明它們在 git HEAD e1e4277 上就是 ALLOW。

const assert = require('assert');
const path = require('path');
const { spawnSync } = require('child_process');

const hookPath = path.resolve(
  process.argv[2] || path.join(__dirname, 'hooks', 'protect-important-paths.js'),
);
const { execWrappers, shellCarriers } = require(hookPath);

const env = { ...process.env, HOME: '/home/tester', TMPDIR: '/tmp/scratch' };
const CWD = '/workspace/project';

let checks = 0;
const failures = [];

function verdict(command) {
  const payload = JSON.stringify({
    hook_event_name: 'PreToolUse',
    tool_name: 'Bash',
    tool_input: { command },
    cwd: CWD,
  });
  const child = spawnSync('node', [hookPath], { input: payload, encoding: 'utf8', env });
  assert.equal(child.status, 0, `the hook must exit 0 on the normal path: ${command}`);
  return /"permissionDecision":"deny"/.test(child.stdout) ? 'DENY' : 'ALLOW';
}

function expect(label, command, wanted) {
  const got = verdict(command);
  checks += 1;
  if (got !== wanted) failures.push(`${label}: wanted ${wanted}, got ${got} -- ${JSON.stringify(command)}`);
}

// ---------------------------------------------------------------------------
// The two controls EVERY batch in this project carries. If either is wrong the
// harness is wrong and nothing below it means anything, so this aborts rather
// than reporting failures that would all be artefacts.
// 每一批都帶的兩個對照組。任何一個錯就是這支 harness 自己錯了，直接中止。
// ---------------------------------------------------------------------------
assert.equal(verdict('rm -rf /etc'), 'DENY',
  'CONTROL: a bare destructive rm against /etc must be DENY -- the harness is wrong');
assert.equal(verdict('ls -l /tmp'), 'ALLOW',
  'CONTROL: `ls -l /tmp` must be ALLOW -- the harness is wrong');
checks += 2;

// ---------------------------------------------------------------------------
// 1. THE PINNED LIST, compared in both directions.
// ---------------------------------------------------------------------------
const PINNED_WRAPPERS = [
  // The three that shipped first.
  '!', 'nohup', 'setsid',
  // Round 1: stock macOS wrappers that had no branch at all.
  'caffeinate', 'stdbuf', 'script',
  // Round 2: the eight wrapper closures this reconstruction keeps.
  'sandbox-exec', 'chroot', 'arch', 'lockf', 'taskpolicy', 'ssh-agent', 'apply',
  // Round 3: the DTraceToolkit family.
  'dtruss', 'dappprof', 'dapptrace', 'procsystime',
].sort();

// `su` is deliberately NOT here: su(1) does not exec its operand. Everything
// after the target login name goes to the login shell, so `-c` is the SHELL's.
// Modelling su as an exec wrapper would have modelled `su nobody rm -rf /etc`,
// which removes nothing, and left `su nobody -c '<destructive>'`, which removes,
// ALLOW -- a fix in the fail-OPEN direction. It belongs in shellCarriers.
// su 刻意不在這裡：它不 exec 自己的操作元，login 名字之後的字全交給 login shell，所以 `-c`
// 是那個 shell 的。當成 exec wrapper 會模型化「不刪東西的拼法」、放掉真的會刪的那個。
const PINNED_CARRIERS = ['sh', 'bash', 'dash', 'zsh', 'ksh', 'fish', 'csh', 'tcsh', 'su'].sort();

assert.ok(execWrappers instanceof Map && execWrappers.size > 0,
  'the hook exported no execWrappers table; this whole file would silently pass');
assert.ok(shellCarriers instanceof Set && shellCarriers.size > 0,
  'the hook exported no shellCarriers set; the coproc and carrier rows below would be vacuous');
assert.deepStrictEqual([...execWrappers.keys()].sort(), PINNED_WRAPPERS,
  'the exec-wrapper table and the pinned list have drifted apart');
assert.deepStrictEqual([...shellCarriers].sort(), PINNED_CARRIERS,
  'shellCarriers and the pinned list have drifted apart');
assert.ok(!execWrappers.has('su'),
  'su must NOT be an exec-wrapper row: that models the harmless spelling and leaves `su <user> -c` open');
checks += 5;

// A representative cluster per row that declares one, pinned here AND checked
// against the row's own regex -- so the pin cannot drift from the pattern, and a
// pattern that stops matching its own documented spelling goes red.
// 每個宣告 clusteredValue 的列各釘一個代表寫法，並用該列自己的 regex 驗證，讓釘住的字不會
// 與樣式走岔。
const CLUSTER_SAMPLES = {
  caffeinate: '-ist',
  script: '-aqt',
  lockf: '-kt',
  taskpolicy: '-bt',
  dtruss: '-ab',
  dappprof: '-cb',
  dapptrace: '-cb',
  procsystime: '-ap',
};
for (const [name, spec] of execWrappers) {
  if (spec.clusteredValue === null) {
    assert.ok(!(name in CLUSTER_SAMPLES),
      `${name} has a pinned cluster sample but declares clusteredValue: null`);
    continue;
  }
  const sample = CLUSTER_SAMPLES[name];
  assert.ok(sample, `${name} declares a clusteredValue but no sample is pinned for it`);
  assert.match(sample, spec.clusteredValue,
    `${name}'s pinned cluster sample ${sample} no longer matches its own clusteredValue`);
  checks += 1;
}

// ---------------------------------------------------------------------------
// 2. EVERY ROW EXERCISED, with the shapes generated from the row itself.
// ---------------------------------------------------------------------------
const SEPARATORS = [';', '&', '|', '\n'];
// A value that is never a path and never a separator, so a row that reads it as
// its option's value behaves the same for every row.
const VALUE = '0';
// The wrapper's own leading operands, when it declares any. `/tmp/scratch/x` is
// not protected, so if the walk mistakenly treated one of these as the COMMAND
// the row would go green for the wrong reason -- which is why the deny target
// below is always the one after them.
const OPERAND = '/tmp/scratch/x';

function operands(spec) {
  return new Array(spec.leadingOperands).fill(OPERAND).join(' ');
}

function assemble(parts) {
  return parts.filter((part) => part !== '').join(' ');
}

for (const [name, spec] of execWrappers) {
  const lead = operands(spec);

  // (a) the bare spelling: the wrapper, its own operands, then the command.
  expect(`${name} bare`, assemble([name, lead, 'rm -rf /etc']), 'DENY');
  expect(`${name} bare home`, assemble([name, lead, 'rm -rf ~/.ssh']), 'DENY');
  // (b) under sudo, because that is how the privileged ones are really written.
  expect(`${name} under sudo`, assemble(['sudo', name, lead, 'rm -rf /etc']), 'DENY');
  // (c) the benign twin, so these rows can fail in the ALLOW direction too. A
  //     test that cannot go red for an over-refusal is half a test.
  expect(`${name} benign`, assemble([name, lead, 'ls -l /tmp']), 'ALLOW');

  for (const option of spec.valueOptions) {
    // (d) the option with its value present.
    expect(`${name} ${option} value`,
      assemble([name, option, VALUE, lead, 'rm -rf /etc']), 'DENY');
    // (e) THE M2 GRID. An option whose value is missing because a SEPARATOR
    //     stands there: the value step must not cross it, or the walk lands one
    //     position too late, eats the next command's command word and hands back
    //     `-rf` as the executable. This is the grid the suite had no row for
    //     anywhere -- measured ALLOW before the fix for script/chroot/lockf, DENY
    //     at git HEAD e1e4277.
    for (const sep of SEPARATORS) {
      expect(`${name} ${option} then ${JSON.stringify(sep)}`,
        `${name} ${option} ${sep} rm -rf /etc`, 'DENY');
      expect(`${name} ${option} then ${JSON.stringify(sep)} under sudo`,
        `sudo ${name} ${option} ${sep} rm -rf /etc`, 'DENY');
    }
    // (f) the option as the LAST word: there is no value, and the walk must end
    //     rather than read past the end of the command.
    expect(`${name} ${option} at end of input`, `${name} ${option}`, 'ALLOW');
  }

  if (spec.clusteredValue !== null) {
    const cluster = CLUSTER_SAMPLES[name];
    expect(`${name} cluster ${cluster} value`,
      assemble([name, cluster, VALUE, lead, 'rm -rf /etc']), 'DENY');
    for (const sep of SEPARATORS) {
      expect(`${name} cluster ${cluster} then ${JSON.stringify(sep)}`,
        `${name} ${cluster} ${sep} rm -rf /etc`, 'DENY');
    }
  }

  if (spec.leadingOperands > 0) {
    // (g) a row with leading operands must still find the command when the
    //     operands are absent because a separator ends the command first.
    for (const sep of SEPARATORS) {
      expect(`${name} no operand then ${JSON.stringify(sep)}`,
        `${name} ${sep} rm -rf /etc`, 'DENY');
    }
  }
}

// ---------------------------------------------------------------------------
// 3. BRM-M1. Command-position `!(...)` is bash's NEGATION reserved word applied
//    to a REAL subshell, not an extglob pattern: `bash -c '!(touch M)'` creates
//    the marker on bash 5.3.20. The tokenizer gate that recognises an extglob
//    accepted the one-character word `!`, swallowed the subshell as a pattern,
//    and nothing scanned inside it.
//    Every `!(` row that existed in test-hooks.js was OPERAND-position
//    (`grep -c "'!(" test-hooks.js` returned 0), which is why a green suite said
//    nothing about this. These rows are COMMAND-position.
// ---------------------------------------------------------------------------
const M1_COMMAND_POSITION = [
  '!(rm -rf /etc)',
  'true ; !(rm -rf /etc)',
  'true && !(rm -rf /etc)',
  'true || !(rm -rf /etc)',
  'true | !(rm -rf /etc)',
  'true & !(rm -rf /etc)',
  'true\n!(rm -rf /etc)',
  '{ !(rm -rf /etc); }',
  '( !(rm -rf /etc) )',
  'if true; then !(rm -rf /etc); fi',
  'for i in 1; do !(rm -rf /etc); done',
  "bash -c '!(rm -rf /etc)'",
  "sh -c '!(rm -rf /etc)'",
  '!(/bin/rm -rf /etc)',
  '!(rm -rf ~/.ssh)',
  '!( !(rm -rf /etc) )',
  '!(sudo rm -rf /etc)',
];
for (const command of M1_COMMAND_POSITION) expect('M1 command position', command, 'DENY');

// The other half of M1: the closure the gate exists FOR must survive the fix.
// These are OPERAND-position patterns, and the fix must not have thrown them away
// -- which is exactly what "reject a one-character word" would have done to the
// four lead characters that are not reserved words.
const M1_OPERAND_POSITION = [
  'rm -rf /et@(c)', 'rm -rf /!(zzz)', 'rm -rf /et?(c)', 'rm -rf /et*(c)',
  'rm -rf /et+(c)', 'rm -rf ~/.ss@(h)', 'rm -rf /et@(c|d)',
];
for (const command of M1_OPERAND_POSITION) expect('M1 operand position', command, 'DENY');

// And a REAL subshell must still be scanned, in both spellings: that is the
// fail-open the gate's own comment named as the risk of getting this wrong.
for (const command of ['(rm -rf /etc)', 'x; (rm -rf /etc)', '! (rm -rf /etc)']) {
  expect('M1 real subshell', command, 'DENY');
}
// ALLOW twins, so these rows can fail in the other direction.
expect('M1 benign command position', '!(ls -l /tmp)', 'ALLOW');
expect('M1 benign operand', 'ls -l /et@(c)', 'ALLOW');

// ---------------------------------------------------------------------------
// 4. BRM-M3. THE COPROC NAME PATH. bash accepts a NAME before a COMPOUND
//    command -- `coproc su { touch M; }` runs the body and never runs su, which
//    is measured -- so what follows the word decides whether the word is a NAME,
//    and that answer cannot depend on what the word spells. Generated over the
//    carrier list so a carrier added later is covered here the moment it is
//    added.
// ---------------------------------------------------------------------------
const COMPOUND = [
  (inner) => `{ ${inner}; }`,
  (inner) => `( ${inner} )`,
  (inner) => `if true; then ${inner}; fi`,
  (inner) => `while true; do ${inner}; done`,
  (inner) => `for i in 1; do ${inner}; done`,
];
for (const name of shellCarriers) {
  for (const shape of COMPOUND) {
    expect(`M3 coproc ${name} compound`, `coproc ${name} ${shape('rm -rf /etc')}`, 'DENY');
  }
  // The carrier reading must survive: with no compound opener after it the word
  // is still the COMMAND, and its `-c` script is still scanned.
  expect(`M3 coproc ${name} -c`, `coproc ${name} -c 'rm -rf /etc'`, 'DENY');
  expect(`M3 coproc ${name} -c benign`, `coproc ${name} -c 'ls -l /tmp'`, 'ALLOW');
}
for (const name of execWrappers.keys()) {
  if (name === '!') continue; // `!` is an operator token, not an identifier NAME
  expect(`M3 coproc ${name} compound`, `coproc ${name} { rm -rf /etc; }`, 'DENY');
}
// A NAME that is not a wrapper name at all, and no NAME at all.
for (const command of [
  'coproc NAME { rm -rf /etc; }',
  'coproc NAME ( rm -rf /etc )',
  'coproc { rm -rf /etc; }',
  'coproc ( rm -rf /etc )',
  'coproc NAME rm -rf /etc',
  'coproc rm -rf /etc',
  // A SIMPLE command takes no NAME, so this really runs `rm in /etc` and really
  // deletes. Reading `rm` as a NAME because `in` is a control word would step the
  // walk past it -- which is why only the words that OPEN a compound command
  // count, not `controlWords` whole.
  'coproc rm in /etc',
]) expect('M3 coproc shape', command, 'DENY');
expect('M3 coproc benign', 'coproc NAME { ls -l /tmp; }', 'ALLOW');

// ---------------------------------------------------------------------------
// 5. su AS A CARRIER, which is why it is not a wrapper row.
// ---------------------------------------------------------------------------
for (const command of [
  "su nobody -c 'rm -rf /etc'",
  "su -m operator -c 'rm -rf /etc'",
  "sudo su nobody -c 'rm -rf ~/.ssh'",
  "su -c 'rm -rf /etc'",
  "su -l nobody -c 'rm -rf /etc'",
  'su nobody <<EOF\nrm -rf /etc\nEOF',
  "su nobody <<< 'rm -rf /etc'",
]) expect('su carrier', command, 'DENY');
expect('su carrier benign', "su nobody -c 'ls -l /tmp'", 'ALLOW');

// ---------------------------------------------------------------------------
if (failures.length > 0) {
  console.error(`Wrapper-model guard FAILED: ${failures.length} of ${checks} checks`);
  for (const line of failures) console.error(`  ${line}`);
  process.exitCode = 1;
} else {
  console.log(`Wrapper-model 測試通過 / Wrapper-model checks passed: ${checks}`);
}
