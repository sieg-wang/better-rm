#!/usr/bin/env node
// Tests for cross-agent protected-directory hooks.
// 跨代理受保護目錄 hook 測試。

'use strict';

const assert = require('assert');
const { MOUNT_PARENTS, SYSTEM_DIRS, evaluate } = require('./hooks/protect-important-paths');

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

// This repository carries TWO protected-path lists: better-rm's PROTECTED_DIRS
// and this hook's SYSTEM_DIRS. Only the first was updated when the macOS entries
// landed, so the hook still allowed `rm -rf /Applications`, and on the agent path
// there is no alias over rm — this hook is the only guard there, with no trash,
// no ledger and no undo behind it.
//
// The test that stood here asserted SYSTEM_DIRS coverage against its own
// hard-coded copy of the same 16 names, which is why that shipped: an entry
// missing from BOTH the array and the copy was structurally invisible. The
// hard-coding was aimed at a real failure (a name read back from the module
// shrinks with the module and keeps passing), but the fix for it is a SECOND
// independent source, not a transcription. Both lists are therefore read from
// where they actually live — PROTECTED_DIRS parsed out of the better-rm script
// with the sed-range idiom test-better-rm.sh already uses, SYSTEM_DIRS imported
// from the hook module — and compared. Neither file can gain or lose an entry
// without this going red, and a transcription in this file could not drift with
// them because there is none.
// 本 repo 有兩份受保護清單，macOS 項目只加進了 better-rm。舊測試拿自己寫死的 16
// 個名字去比對 SYSTEM_DIRS，兩邊同時缺項就永遠看不見——這正是缺漏得以出貨的原因。
// 寫死是為了防「從模組讀回來會隨模組一起縮小」，但解法是第二個獨立來源，不是抄寫：
// 兩份清單各自從真正的出處讀出來比對，任一邊增減都會立刻轉紅。
const betterRmSource = require('fs').readFileSync(`${__dirname}/better-rm`, 'utf8');
const protectedDirsBlock = betterRmSource.match(/^PROTECTED_DIRS=\(\n([\s\S]*?)^\)$/m);
assert.ok(protectedDirsBlock, 'PROTECTED_DIRS was not found in better-rm; this extraction is broken');
const cliProtectedDirs = protectedDirsBlock[1]
  .split('\n')
  .map((line) => line.trim())
  .filter((line) => line && !line.startsWith('#'))
  .map((line) => line.replace(/^"(.*)"$/, '$1'));
// The extraction must fail loudly rather than quietly return nothing: an empty
// or malformed parse would make the comparison below trivially true.
// 抽取失敗必須大聲失敗，否則空清單會讓底下的比對變成恆真。
assert.ok(cliProtectedDirs.length > 0, 'PROTECTED_DIRS parsed as empty; this extraction is broken');
for (const entry of cliProtectedDirs) {
  assert.match(entry, /^(\/|\$HOME)/, `PROTECTED_DIRS parsed a non-path entry: ${entry}`);
  assert.doesNotMatch(entry, /["']/, `PROTECTED_DIRS entry kept its quoting: ${entry}`);
}
// $HOME reaches the hook as protectedReason's `home` argument rather than through
// SYSTEM_DIRS, so it is added on the hook side of the comparison; trailing slashes
// are a spelling, not an entry, and better-rm strips them before comparing too.
// $HOME 在 hook 是走 protectedReason 的 home 參數而非 SYSTEM_DIRS；結尾斜線只是寫法。
const stripTrailingSlash = (item) => item.replace(/(.)\/+$/, '$1');
const cliProtectedSet = [...new Set(
  cliProtectedDirs.map((item) => stripTrailingSlash(item.replace(/^\$HOME/, env.HOME))),
)].sort();
const hookProtectedSet = [...new Set([...SYSTEM_DIRS, env.HOME].map(stripTrailingSlash))].sort();
assert.deepStrictEqual(
  hookProtectedSet,
  cliProtectedSet,
  'the hook\'s SYSTEM_DIRS and better-rm\'s PROTECTED_DIRS have drifted apart',
);

// Parity of the two lists is a name check; these rows are what proves the hook
// acts on them. Generated from the extracted list so a new entry is exercised
// the moment it is added, in both directions: the directory itself refused, and
// an item inside it still allowed. The second half is not decoration — widening
// the comparison to a prefix match would satisfy every deny row above while
// turning `rm -rf /Applications/Foo.app` (ordinary work, no root required) into
// a refusal, which is a worse regression than the missing entries were.
// Mount parents are excluded here and covered separately: everything at their
// first level is a mount root, so an item there is protected, not allowed.
// 名稱比對之外還要證明 hook 真的據此行動：由抽出的清單生成，兩個方向都測——目錄
// 本身被拒、目錄內的項目仍放行。後者不是裝飾：比對一旦擴大成前綴匹配，上面每一
// 列 deny 都仍是綠的，卻會把刪除單一 app bundle 這種日常操作變成拒絕。
const cliMountParentLine = betterRmSource.match(/^\s*for mount_parent in (.+); do$/m);
assert.ok(cliMountParentLine, 'the mount-parent loop was not found in better-rm; this extraction is broken');
const cliMountParents = cliMountParentLine[1].trim().split(/\s+/);
for (const entry of cliMountParents) {
  assert.match(entry, /^\//, `the mount-parent loop parsed a non-path entry: ${entry}`);
}
// Same two-source comparison as the list above, for the same reason: the mount
// rule is duplicated in both guards and diverged once already.
// 與上面同樣的雙來源比對：掛載規則同樣兩邊各有一份，而且已經走岔過一次。
assert.deepStrictEqual(
  [...MOUNT_PARENTS].sort(),
  [...cliMountParents].sort(),
  'the hook\'s MOUNT_PARENTS and better-rm\'s mount-parent loop have drifted apart',
);
for (const protectedDir of cliProtectedSet) {
  blocked.push(`rm -rf ${protectedDir}`, `rm -rf ${protectedDir}/`);
  if (protectedDir === '/' || cliMountParents.includes(protectedDir)) continue;
  allowed.push(`rm -rf ${protectedDir}/inside-item`);
}

// Under a mount parent the first level is not an ordinary directory: it is where
// a whole disk is attached, so `rm -rf /Volumes/Backup` is the backup disk and
// `rm -rf /mnt/c` is the Windows filesystem. better-rm protects the first level
// of every mount parent and allows what is inside it, and the hook had that rule
// for /mnt alone while better-rm's loop covered /mnt and /Volumes. The parents
// are read from that loop rather than restated, so a third one added there is
// exercised here without anyone remembering to.
// 掛載父目錄底下的第一層不是普通目錄，而是整顆磁碟的掛載點。better-rm 保護每個掛載
// 父目錄的第一層、放行其內容；hook 先前只有 /mnt。父目錄清單直接從那個迴圈讀出來。
for (const mountParent of cliMountParents) {
  blocked.push(`rm -rf ${mountParent}/probe-disk`, `rm -rf ${mountParent}/probe-disk/`);
  allowed.push(`rm -rf ${mountParent}/probe-disk/inside-item`);
  // A mount root whose name begins with '..' is still a mount root -- a volume can
  // be named that, and better-rm protects it: measured, it refuses /Volumes/..disk
  // and still allows /Volumes/..disk/inside-item. Expressing "did not escape the
  // parent" as "the relative path does not start with .." reads those leading dots
  // as an escape and hands the disk over, which is the one shape where the two
  // guards' spelling of the same rule disagrees.
  // 名字以 '..' 開頭的掛載根仍然是掛載根（磁碟可以取這種名字），better-rm 實測會擋。
  // 用「相對路徑不以 .. 開頭」表達「沒有跳出父目錄」會把這種名字誤判成跳脫而放行。
  blocked.push(`rm -rf ${mountParent}/..probe-disk`);
  allowed.push(`rm -rf ${mountParent}/..probe-disk/inside-item`);
}
// The home directory itself, in the spellings a shell can hand over.
// 家目錄本身的各種寫法。
blocked.push('rm -rf ~', 'rm -rf $HOME', 'rm -rf /home/tester/');

// macOS firmlinks: /System/Volumes/Data/X and /X are the same object. Measured
// with stat -f '%d:%i', /Users/<user> and /System/Volumes/Data/Users/<user> share
// a device and an inode, and so do /Applications and its Data-volume spelling. A
// firmlink is not a symlink -- readlink -f hands either spelling straight back --
// so no canonicalisation brings the two together and each guard has to carry the
// rule separately. Both carry it now; for one round better-rm did and this hook
// did not, and the list check above could not see that, because the rule lives in
// a function body rather than in a list. The gap was live: `rm -rf
// /System/Volumes/Data/Users` was allowed on the agent path, where there is no
// alias over rm, no trash and no undo. These rows are what keeps it closed.
// The prefix is read out of better-rm rather than transcribed, for the same
// reason the two lists above are: a copy here would keep passing after better-rm
// changed it, and the rows would then prove the wrong thing.
// macOS firmlink：/System/Volumes/Data/X 與 /X 是同一個 device、同一個 inode，而
// firmlink 不是 symlink，沒有任何正規化會讓兩種拼寫碰面，所以兩道守衛各自都要有
// 這條規則。現在兩邊都有了；曾有一輪只有 better-rm 有、hook 沒有，而清單比對看不見
// 寫在函式本體裡的規則——下面這幾列就是把它釘住的東西。
// 前綴從 better-rm 讀出來而不是抄寫，理由與上面兩份清單相同。
const firmlinkPrefixMatch = betterRmSource.match(/^\s*(?:local\s+)?firmlink_prefix="([^"]+)"$/m);
assert.ok(firmlinkPrefixMatch, 'the firmlink prefix was not found in better-rm; this extraction is broken');
const firmlinkPrefix = firmlinkPrefixMatch[1];
assert.match(firmlinkPrefix, /^\/[^"\s]+[^/]$/, `the firmlink prefix parsed as a non-path: ${firmlinkPrefix}`);
blocked.push(`rm -rf ${firmlinkPrefix}`, `rm -rf ${firmlinkPrefix}/`);
for (const protectedDir of cliProtectedSet) {
  // The root's Data-volume spelling is the prefix itself, pushed above.
  // 根目錄的 Data 卷宗拼寫就是前綴本身，已在上面加入。
  if (protectedDir === '/') continue;
  blocked.push(`rm -rf ${firmlinkPrefix}${protectedDir}`);
  // The same anti-tautology half as the list rows above: what is protected is the
  // directory, not everything on the data volume. Mount parents are excluded for
  // the same reason as above -- their first level is a mount root.
  // 反恆真的另一半：受保護的是那個目錄，不是整顆資料卷宗。
  if (cliMountParents.includes(protectedDir)) continue;
  allowed.push(`rm -rf ${firmlinkPrefix}${protectedDir}/inside-item`);
}
// The prefix has to align on a whole component: a volume merely NAMED Data...
// is a different disk, and folding it into the root spelling would refuse
// /System/Volumes/DataDrive/file.txt, an ordinary file on an ordinary disk.
// 前綴必須整段對齊：名字剛好以 Data 開頭的另一顆磁碟不能被折進根拼寫。
allowed.push(`rm -rf ${firmlinkPrefix}Drive/file.txt`);
allowed.push(`rm -rf ${firmlinkPrefix}/not-a-protected-name`);

// A path INSIDE .git is as unrecoverable as .git itself: `.git/objects` or
// `.git/refs` loses the repository, and there is no trash copy on this path —
// the hook's job is to stop the command before rm runs. Every .git row above
// ends AT the .git component, so the mid-path rule could be deleted (it looks
// redundant next to the endsWith one) while the suite stayed green.
// .git 內部的路徑與 .git 本身一樣不可還原；先前的案例都只到 .git 那一層為止，
// 因此看起來多餘的「中段 .git」規則可以刪掉而全套仍綠。
blocked.push(
  'rm -rf /workspace/project/.git/objects',
  'rm -rf .git/objects/pack',
  'rm -rf ../project/.git/hooks/pre-commit',
  'rmdir /workspace/project/.git/refs/heads',
);
// Negative control: .git has to be a path COMPONENT, not a substring. A widened
// rule that also matched .gitignore or .github would be a blanket refusal of
// ordinary repository housekeeping.
// 負對照：.git 必須是路徑元件而非子字串，否則會誤擋 .gitignore、.github。
allowed.push('rm -rf build/.gitignore', 'rm -rf .github/workflows');

// `depth >= 8` fails closed in nine places, and the shell carrier above was the
// only one anybody had exercised. Each wrapper below reaches a DIFFERENT one of
// them, so each needs its own row: making any single site fail OPEN left the
// whole suite green and handed out a mechanical bypass, since adding another
// layer of nesting costs the caller nothing.
// (The ninth site — an unresolvable command word whose operand is itself a whole
// command — is not reachable this way: that shape already denies for another
// reason, so nesting it proves nothing and it stays unpinned.)
// `depth >= 8` 的失敗關閉共有九處，先前只有上面的 shell carrier 被執行過。下面
// 每個包裝各自打到不同的一處，因此必須各有一列：任何一處改成 fail open，全套
// 都仍是綠的，而多包一層對攻擊者毫無成本。
// （第九處——命令字無法解析、其運算元本身是一整條命令——用這個形狀打不到：那種
// 寫法本來就會因為別的理由被拒絕，包再多層也證明不了什麼，因此仍未釘住。）
const recursionCapWrappers = [
  (inner) => `echo $(${inner})`,                           // command substitution
  (inner) => `eval ${JSON.stringify(inner)}`,              // eval
  (inner) => `env -S ${JSON.stringify(inner)}`,            // env -S <string>
  (inner) => `env -S${JSON.stringify(inner)}`,             // env -S<string>
  (inner) => `env -ivS ${JSON.stringify(inner)}`,          // env -ivS <string>
  (inner) => `env -ivS${JSON.stringify(inner)}`,           // env -ivS<string>
  (inner) => `env --split-string=${JSON.stringify(inner)}`,
];
for (const wrapPastCap of recursionCapWrappers) {
  let pastCapDestructive = 'rm -rf /';
  let pastCapBenign = 'rm -rf build';
  let insideCapBenign = 'rm -rf build';
  for (let depthLevel = 0; depthLevel < 10; depthLevel += 1) {
    pastCapDestructive = wrapPastCap(pastCapDestructive);
    pastCapBenign = wrapPastCap(pastCapBenign);
    if (depthLevel < 8) insideCapBenign = wrapPastCap(insideCapBenign);
  }
  // The hazard the cap exists for, and — because past the cap the hook can no
  // longer reason about the command at all — the same nesting around a harmless
  // target, which must fail closed too.
  // 上限存在的理由；以及同樣層數但目標無害的版本，超過上限就無從判斷，也必須關閉。
  blocked.push(pastCapDestructive, pastCapBenign);
  // Negative control: the cap is a boundary, not a blanket refusal. Nesting that
  // stops just inside it (8 levels) must still be allowed, or `depth >= 7` would
  // pass just as well.
  // 負對照：上限是邊界而非一律拒絕。剛好在界內（8 層）仍須放行，否則改成 `>= 7`
  // 也會是綠的。
  allowed.push(insideCapBenign);
}

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

// ---------------------------------------------------------------------------
// What the FILESYSTEM says the argument names.
//
// Case folding, Unicode normalisation and symlink-through spellings are
// properties of the filesystem, not of the string, and no list of spellings can
// keep up with them: /Users alone has 2^5 case spellings before Unicode is
// considered. This hook was purely lexical, so `rm -rf link/` -- which resolves
// the final component, destroys the target's contents and leaves the link --
// read as an ordinary directory removal on the one path where this hook is the
// only guard.
// The fixtures below are symlinks and declared directories rather than /Users
// and /etc, so every row means the same thing on a case-sensitive filesystem as
// it does on macOS. The two questions only the filesystem can answer (a case
// fold, a Unicode normalisation) MEASURE the aliasing and assert whichever
// answer is true there, so neither platform is handed a row that silently tests
// nothing.
// 大小寫、Unicode 正規化、穿過 symlink 的拼寫都是檔案系統的性質而不是字串的性質，
// 列不完（光 /Users 就有 2^5 種大小寫寫法，還沒算 Unicode）。這支 hook 原本純字面，
// 於是 `rm -rf link/`——它會解析最後一段、毀掉 target 的內容、只留下連結——在只有它
// 在守的那條路徑上，讀起來就只是一次普通的目錄刪除。下面的 fixture 一律用 symlink
// 與自行宣告的目錄，因此每一列在分大小寫的檔案系統上與在 macOS 上意義相同；只有檔案
// 系統能回答的那兩列則實地量測別名關係、兩種答案各自斷言，沒有任何一個平台會拿到
// 一列什麼都沒測到的測試。
// ---------------------------------------------------------------------------
let resolutionChecks = 0;
{
  // realpathSync so the fixture root is the PHYSICAL path: macOS resolves TMPDIR
  // through /var -> /private/var, and a fixture reached through a symlink
  // component would make every row below about that symlink instead.
  // 取實體路徑：macOS 的 TMPDIR 會經過 /var -> /private/var，否則下面每一列測到的都是
  // 那條 symlink。
  const box = fs.realpathSync(fs.mkdtempSync(`${os.tmpdir()}/better-rm-hook-resolve-`));
  const boxHome = `${box}/home`;
  const declared = `${box}/secrets`;
  const inner = `${declared}/inner`;
  const project = `${box}/project`;
  const caseFixture = `${box}/CaseSecrets`;
  const unicodeFixture = `${box}/café-secrets`; // NFC, as a JavaScript source file produces it
  // A declared directory that IS a symlink, for the union rule below.
  // 一個「本身就是 symlink」的宣告目錄，給下面的聯集規則用。
  const linkedDeclared = `${box}/linked-secrets`;
  const linkedActual = `${box}/actual`;
  for (const directory of [boxHome, inner, `${project}/build`, `${project}/.git`,
    caseFixture, unicodeFixture, linkedActual]) {
    fs.mkdirSync(directory, { recursive: true });
  }
  fs.symlinkSync(declared, `${box}/link-to-secrets`);
  fs.symlinkSync(inner, `${box}/link-to-inner`);
  fs.symlinkSync(`${project}/build`, `${box}/link-to-build`);
  fs.symlinkSync(`${project}/.git`, `${box}/link-to-git`);
  fs.symlinkSync(project, `${box}/projlink`);
  fs.symlinkSync(`${box}/nothing-is-mounted-here/item`, `${box}/dangling`);
  fs.symlinkSync(`${box}/loop-b`, `${box}/loop-a`);
  fs.symlinkSync(`${box}/loop-a`, `${box}/loop-b`);
  fs.symlinkSync(linkedActual, linkedDeclared);

  const boxEnv = {
    HOME: boxHome,
    BETTER_RM_PROTECTED_DIRS: [declared, caseFixture, unicodeFixture, linkedDeclared].join(':'),
  };
  const boxVerdict = (command, environment = boxEnv) => (evaluate({
    hook_event_name: 'PreToolUse',
    tool_name: 'Bash',
    tool_input: { command },
    cwd: box,
  }, environment)?.hookSpecificOutput?.permissionDecision === 'deny' ? 'DENY' : 'ALLOW');
  const rmOf = (spelling) => `rm -rf '${spelling}'`;
  const denies = (spelling, why) => {
    assert.equal(boxVerdict(rmOf(spelling)), 'DENY', `${why}: ${spelling}`);
    resolutionChecks += 1;
  };
  const allows = (spelling, why) => {
    assert.equal(boxVerdict(rmOf(spelling)), 'ALLOW', `${why}: ${spelling}`);
    resolutionChecks += 1;
  };

  // The link itself is not its target. Deleting a link cannot touch what it
  // points at, so refusing this would make every ~/applink shortcut undeletable
  // with no override -- the rule better-rm adopted in 2c34f8d.
  // 連結本身不是它的目標：刪連結碰不到 target，拒絕它會讓 ~/applink 這種捷徑刪不掉，
  // 而且沒有任何旗標可以蓋過去。
  allows('link-to-secrets', 'a symlink argument is judged by the link, not by its target');
  allows(`${box}/link-to-secrets`, 'the same, spelled absolutely');
  // ...but a trailing slash (and `/.`, and `//`, and `/./`) forces resolution of
  // the final component, so these spellings reach the TARGET: `rm -rf link/`
  // returns 0, destroys the target's contents and leaves the link behind. Each
  // spelling is its own row because each is a different string arriving at the
  // same place, and a rule written for one of them can miss the others.
  // 結尾斜線（以及 /.、//、/./）會強制解析最後一段，這些拼寫碰到的是 target 本身。
  // 每一種拼寫各佔一列：它們是不同的字串、同一個落點，只針對其中一種寫的規則會漏掉
  // 其他幾種。
  for (const spelling of ['link-to-secrets/', 'link-to-secrets//', 'link-to-secrets/.',
    'link-to-secrets/./', `${box}/link-to-secrets/`]) {
    denies(spelling, 'a trailing slash resolves the final component and reaches the target');
  }
  // '..' resolves through the link as well, onto the parent of the TARGET rather
  // than the directory the link sits in: realpath of '<box>/link-to-inner/..' is
  // '<box>/secrets', while a lexical collapse says '<box>'. A guard that
  // collapsed '..' before asking the filesystem would answer a different
  // question from the one the shell is about to ask.
  // '..' 同樣會穿過連結，落在 target 的父目錄而不是連結所在的目錄；先把 '..' 字面折掉
  // 再問，問到的就不是 shell 接下來要做的那件事。
  denies('link-to-inner/..', "'..' resolves through the link, onto the declared directory");
  denies('link-to-inner/../', "'..' resolves through the link, onto the declared directory");
  denies('link-to-git/', 'the resolved path is a .git directory');

  // Anti-tautology, and the failure that matters most here: resolution must not
  // become "anything reached through a link is refused". This hook gates EVERY
  // agent command on the machine, so an over-broad rule costs more than the hole
  // it closes.
  // 反恆真，而且是這裡最要緊的失敗模式：解析不能變成「凡是穿過連結的一律拒絕」。這支
  // hook 是每一次 agent 命令都會經過的閘門，過度拒絕的代價比它補起來的洞還大。
  allows('link-to-build/', 'a link to ordinary build output stays ordinary');
  allows('link-to-inner/', 'inside a declared directory is ordinary work');
  allows('projlink/build', 'a project reached through a symlinked root is ordinary work');
  allows('projlink/build/', 'the same, with a trailing slash');
  allows(`${box}/projlink/build`, 'the same, spelled absolutely');
  allows('project/build', 'and the same project reached directly');

  // A partial resolution must not be trusted, and nothing here may throw: a
  // dangling link and a symlink cycle make the filesystem answer ENOENT and
  // ELOOP, and every errno means the same thing -- nothing learned, so the
  // lexical verdict stands. An exception instead of a verdict would deny every
  // Bash call on the machine.
  // 半途的解析結果不可採信，而且這裡絕不能丟例外：斷連結與連結環會讓檔案系統回
  // ENOENT／ELOOP，每一種 errno 的意思都一樣——什麼都沒學到，維持字面判定。這裡丟出
  // 例外會擋掉整台機器上所有的 Bash 呼叫。
  allows('dangling', 'a dangling link is not a protected path');
  allows('dangling/', 'a partial resolution must not be trusted');
  allows('loop-a/', 'a symlink cycle answers ELOOP; the verdict falls back, it does not throw');
  allows('loop-a/../', 'the same, through ..');

  // The union of both spellings, which is what better-rm's is_protected() has
  // always compared: it tests its readlink-resolved path AND its unresolved one
  // against every list. The declared directory here IS a symlink, so its
  // resolved path is something else entirely -- judging by the RESOLVED path
  // alone would permit removing a declared entry, the mirror image of the hole
  // above. This is the shape of `/var/.` on macOS, without depending on macOS.
  // 取聯集，與 better-rm 的 is_protected 一直以來的做法相同（同時拿解析後與未解析的
  // 拼寫去比對每一份清單）。這裡宣告的受保護目錄本身就是一條 symlink，只看解析後的
  // 路徑會放行對「已宣告項目」的刪除——與上面那個洞正好相反的方向。這就是 macOS 上
  // `/var/.` 的形狀，而且不必依賴 macOS。
  denies('linked-secrets', 'a declared directory that is a symlink is still declared');
  denies('linked-secrets/.', 'the spelling as written is still the declared directory');
  denies(`${box}/linked-secrets/.`, 'the same, spelled absolutely');
  allows('actual', 'what the declared link points at was never the declared entry');

  // Two spellings name one object, or they do not: asked of the filesystem
  // rather than assumed from the platform. A case-insensitive volume can be
  // mounted on Linux and a case-SENSITIVE one formatted on macOS, so an
  // expectation derived from process.platform would be wrong on both. lstat
  // dev+ino rather than realpath, because Node's own realpath hands back the
  // spelling it was given (measured: fs.realpathSync('/USERS') is '/USERS').
  // 兩種拼寫是不是同一個物件，用問檔案系統的、不是照平台猜的：Linux 可以掛不分大小寫
  // 的卷宗，macOS 也能格式化分大小寫的。用 lstat 的 dev+ino 而不是 realpath——Node 自己
  // 的 realpath 會原樣回傳拼寫（實測 fs.realpathSync('/USERS') 就是 '/USERS'）。
  const sameObject = (left, right) => {
    try {
      const a = fs.lstatSync(left);
      const b = fs.lstatSync(right);
      return a.dev === b.dev && a.ino === b.ino;
    } catch (_) {
      return false;
    }
  };
  const foldedSpelling = `${box}/casesecrets`;
  if (sameObject(caseFixture, foldedSpelling)) {
    denies(foldedSpelling, 'a case-folded spelling of a declared directory is that directory');
    allows(`${foldedSpelling}/inside-item`, 'inside it is still ordinary work');
  } else {
    allows(foldedSpelling, 'a case-SENSITIVE filesystem: the folded spelling is a different path');
  }
  const nfdSpelling = unicodeFixture.normalize('NFD');
  assert.notEqual(nfdSpelling, unicodeFixture, 'the Unicode fixture has no second encoding');
  resolutionChecks += 1;
  if (sameObject(unicodeFixture, nfdSpelling)) {
    denies(nfdSpelling, 'the NFD spelling of a directory declared NFC is that directory');
  } else {
    allows(nfdSpelling, 'a normalisation-sensitive filesystem: the NFD spelling is a different path');
  }

  // A path that does not exist has to be judged exactly as it was before this
  // hook could see anything. That is the whole reason it was filesystem-free:
  // an inode needs the path to exist, and a home directory that has not been
  // created yet must still be protected.
  // 不存在的路徑必須與「還看不見檔案系統」時判得一模一樣——這正是它原本完全不碰檔案
  // 系統的理由：inode 要求路徑存在，而還沒建立的家目錄同樣必須受保護。
  denies(boxHome, 'the home directory is protected');
  allows(`${boxHome}/keep`, 'inside the home directory is ordinary work');
  allows(`${box}/never-created`, 'a path that does not exist is not protected by accident');
  const absentHomeEnv = { HOME: `${box}/never-created`, BETTER_RM_PROTECTED_DIRS: '' };
  assert.equal(
    boxVerdict(rmOf(`${box}/never-created`), absentHomeEnv),
    'DENY',
    'a home directory that has not been created yet is still protected',
  );
  resolutionChecks += 1;

  fs.rmSync(box, { recursive: true, force: true });
}

// ---------------------------------------------------------------------------
// The OpenCode plugin's own decision. install-hooks.sh embeds a byte-identical
// copy of the plugin and test-install-hooks.sh pins the installed file to that
// source by hash — but nothing ever RAN the handler, so inverting the deny
// comparison in BOTH copies left all 1079 checks green while OpenCode permitted
// `rm -rf /`. OpenCode has no PreToolUse JSON hook: this plugin is its entire
// guard, the one agent whose protection has no second layer.
// OpenCode 外掛的判斷邏輯。既有測試只用 hash 比對兩份副本的位元組，從未執行
// handler，因此把 deny 比對同時改在兩份副本上，全套仍綠，而 OpenCode 會放行
// `rm -rf /`——OpenCode 沒有 PreToolUse hook，這支外掛就是它的全部防護。
//
// The plugin is TypeScript and CI runs plain node, so the erasable type syntax
// is stripped and the hook import is bound to the module this file already
// loaded. Every rewrite is asserted before it is applied: if the plugin stops
// having this shape the loader fails loudly instead of quietly measuring
// nothing. The decision itself is the shipped source, unmodified.
// ---------------------------------------------------------------------------
const pluginPath = `${__dirname}/.opencode/plugins/protect-important-paths.ts`;
const pluginRewrites = [
  [/^import type \{ Plugin \} from "@opencode-ai\/plugin";$/m, ''],
  [/^\/\/ @ts-ignore$/m, ''],
  [
    /^import \{ evaluate \} from "\.\.\/\.\.\/hooks\/protect-important-paths";$/m,
    'const { evaluate } = hookModule;',
  ],
  [/: Plugin\b/, ''],
  [/\(ctx as any\)/, 'ctx'],
  [/^export const /m, 'const '],
  [/^export default ProtectImportantPathsPlugin;$/m, ''],
];
let pluginBody = fs.readFileSync(pluginPath, 'utf8');
for (const [pattern, replacement] of pluginRewrites) {
  assert.match(
    pluginBody,
    pattern,
    `the OpenCode plugin no longer matches ${pattern}; update this loader`
  );
  pluginBody = pluginBody.replace(pattern, replacement);
}
const pluginFactory = new Function(
  'hookModule',
  `${pluginBody}\nreturn ProtectImportantPathsPlugin;`
)({ evaluate });

const pluginDenied = ['rm -rf /', 'rm -rf /etc', 'rm -rf .git', 'CMD=rm; $CMD -rf /'];
const pluginAllowed = ['rm -rf build', 'ls -la /etc', 'echo rm -rf /'];

async function runOpenCodePluginChecks() {
  let pluginChecks = 0;
  const hooks = await pluginFactory({ directory: '/workspace/project' });
  const before = hooks['tool.execute.before'];
  assert.equal(typeof before, 'function', 'the OpenCode plugin registers tool.execute.before');
  pluginChecks += 1;

  for (const command of pluginDenied) {
    let thrown = null;
    try {
      await before({ tool: 'bash' }, { args: { command } });
    } catch (error) {
      thrown = error;
    }
    assert.ok(thrown, `the OpenCode plugin must refuse: ${command}`);
    assert.match(
      thrown.message,
      /Refused to remove protected directory/,
      `the OpenCode refusal must name the reason: ${command}`
    );
    pluginChecks += 1;
  }

  // Negative controls: the plugin must not become a blanket refusal, and a tool
  // that is not bash carries no shell command to inspect.
  // 負對照：不能變成一律拒絕；非 bash 的工具沒有 shell 命令可檢查。
  for (const command of pluginAllowed) {
    try {
      await before({ tool: 'bash' }, { args: { command } });
    } catch (error) {
      assert.fail(`the OpenCode plugin must not refuse: ${command} (${error.message})`);
    }
    pluginChecks += 1;
  }
  try {
    await before({ tool: 'read' }, { args: { command: 'rm -rf /' } });
  } catch (error) {
    assert.fail(`a tool that is not bash carries no command to inspect (${error.message})`);
  }
  pluginChecks += 1;

  // The session directory has to reach evaluate(): a relative BETTER_RM_PROTECTED_DIRS
  // entry is resolved against it, so dropping `cwd` from the payload silently
  // moves every relative decision to the node process's own directory.
  // ctx.directory 必須傳到 evaluate()：相對的 BETTER_RM_PROTECTED_DIRS 是以它為
  // 基準解析的，payload 少了 cwd 會讓所有相對判斷改用 node 行程自己的目錄。
  const previousExtraDirs = process.env.BETTER_RM_PROTECTED_DIRS;
  process.env.BETTER_RM_PROTECTED_DIRS = 'secrets';
  try {
    let thrown = null;
    try {
      await before({ tool: 'bash' }, { args: { command: 'rm -rf /workspace/project/secrets' } });
    } catch (error) {
      thrown = error;
    }
    assert.ok(thrown, 'the OpenCode plugin must pass ctx.directory to evaluate as cwd');
    pluginChecks += 1;
  } finally {
    if (previousExtraDirs === undefined) delete process.env.BETTER_RM_PROTECTED_DIRS;
    else process.env.BETTER_RM_PROTECTED_DIRS = previousExtraDirs;
  }

  return pluginChecks;
}

// The plugin handler is async, so its checks cannot run before the summary is
// printed the way every check above does. Exit non-zero until they finish:
// a file that exited 0 without having run them would look green.
// 外掛 handler 是 async，無法在總結列印前完成，因此先設為失敗，跑完才清為 0——
// 否則「沒跑到」會看起來是綠的。
process.exitCode = 1;
runOpenCodePluginChecks().then((pluginChecks) => {
  console.log(`Hooks 測試通過 / Hook tests passed: ${blocked.length * 4 + allowed.length * 4 + 2 + errorPathChecks + stdinChecks + hookShapeChecks + resolutionChecks + pluginChecks}`);
  process.exitCode = 0;
}).catch((error) => {
  console.error(error && error.stack ? error.stack : error);
  process.exitCode = 1;
});
