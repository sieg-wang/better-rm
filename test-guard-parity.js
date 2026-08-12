#!/usr/bin/env node
// Differential parity between the two protected-path guards in this repository.
// 本 repo 兩道受保護路徑守衛的差分對照測試。
//
// This repository ships TWO independent implementations of "is this path
// protected?": better-rm's is_protected() (shell, guards the rm replacement) and
// hooks/protect-important-paths.js's evaluate() (Node, guards the coding-agent
// Bash tool). They have diverged three times. The existing name-level check in
// test-hooks.js compares the two LISTS (PROTECTED_DIRS vs SYSTEM_DIRS,
// mount-parent loop vs MOUNT_PARENTS) and is structurally blind to a RULE that
// lives in one file's body and not the other's: the macOS firmlink rewrite was
// added to better-rm alone, `node test-hooks.js` still reported every check
// passing, and the live hook still ALLOWed `rm -rf /System/Volumes/Data/Users`
// -- the same device and inode as the home directory.
//
// Comparing list literals cannot catch a body-level rule. The only shape that
// can is this one: ONE shared corpus of path spellings, driven through BOTH
// guards, verdicts diffed, differences reported as a table.
// 名稱層級的比對抓不到「只寫在某一邊函式本體裡」的規則（macOS firmlink 改寫就是
// 只加進 better-rm，而 test-hooks.js 全綠）。唯一抓得到的形狀是差分測試：一份共用
// 的路徑拼寫語料，兩道守衛各跑一次，判定逐列比對。
//
// Neither guard is given a real path to act on. Both are pure predicates: the
// hook never touches the filesystem at all, and is_protected() only stats and
// resolves (readlink/realpath/basename). Nothing here deletes, moves or writes
// outside its own temporary sandbox.
// 兩邊都只是純判斷式：hook 完全不碰檔案系統，is_protected 只做 stat 與解析。
//
// Exit codes / 結束碼:
//   0  every row agrees and every expectation holds
//   1  at least one divergence or expectation failure (the work list)
//  99  the harness itself is broken (extraction empty, probe not two-valued,
//      quoting distorted an operand) -- kept distinct from 1 so a broken probe
//      can never read as "no divergences", the same convention test-better-rm.sh
//      uses for its own extraction probe.
//      99 與 1 分開：壞掉的探針不該被讀成「沒有分歧」。

'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const hook = require('./hooks/protect-important-paths');

const REPO_DIR = __dirname;
const BETTER_RM = path.join(REPO_DIR, 'better-rm');
const PROBE_BROKEN_EXIT = 99;

function probeBroken(message) {
  console.error(`探針損壞，判定不可信 / Parity probe broken, verdicts not trustworthy: ${message}`);
  process.exit(PROBE_BROKEN_EXIT);
}

function require_(condition, message) {
  if (!condition) probeBroken(message);
}

// ---------------------------------------------------------------------------
// 1. Both guards' sources, read from where they actually live
//    兩份清單各自從真正的出處讀出來
// ---------------------------------------------------------------------------
// The corpus is generated from the UNION of both guards' lists, so an entry
// added to either side is exercised in every spelling below without anyone
// remembering to add rows. A transcription here would drift with neither.
// 語料由兩邊清單的聯集生成：任一邊新增項目，底下所有拼寫都會自動涵蓋。

const betterRmSource = fs.readFileSync(BETTER_RM, 'utf8');

const protectedDirsBlock = betterRmSource.match(/^PROTECTED_DIRS=\(\n([\s\S]*?)^\)$/m);
require_(protectedDirsBlock, 'PROTECTED_DIRS was not found in better-rm');
const cliProtectedDirsRaw = protectedDirsBlock[1]
  .split('\n')
  .map((line) => line.trim())
  .filter((line) => line && !line.startsWith('#'))
  .map((line) => line.replace(/^"(.*)"$/, '$1'));
require_(cliProtectedDirsRaw.length > 0, 'PROTECTED_DIRS parsed as empty');

const cliMountParentLine = betterRmSource.match(/^\s*for mount_parent in (.+); do$/m);
require_(cliMountParentLine, 'the mount-parent loop was not found in better-rm');
const cliMountParents = cliMountParentLine[1].trim().split(/\s+/);
require_(cliMountParents.length > 0, 'the mount-parent loop parsed as empty');

// Read rather than transcribed, for the same reason as the two lists: a
// hard-coded copy here would keep passing after better-rm changed the prefix.
// Tolerant of the variable being lifted out of the function, but not of it
// disappearing -- without it the firmlink rows cannot be generated at all, and
// silently generating none of them is exactly the blindness this file exists to
// remove.
// 前綴同樣用讀的而不是抄的；容許它被搬出函式，但不容許它消失：少了它就生不出
// firmlink 那組列，而「靜靜地一列都不生」正是本檔要消滅的盲點。
const firmlinkPrefixMatch = betterRmSource.match(/^\s*(?:local\s+)?firmlink_prefix="([^"]+)"$/m);
require_(firmlinkPrefixMatch, 'the firmlink prefix was not found in better-rm');
const FIRMLINK_PREFIX = firmlinkPrefixMatch[1];

require_(Array.isArray(hook.SYSTEM_DIRS) && hook.SYSTEM_DIRS.length > 0,
  'the hook exported no SYSTEM_DIRS');
require_(Array.isArray(hook.MOUNT_PARENTS) && hook.MOUNT_PARENTS.length > 0,
  'the hook exported no MOUNT_PARENTS');
require_(typeof hook.evaluate === 'function', 'the hook exported no evaluate()');
require_(typeof hook.protectedReason === 'function', 'the hook exported no protectedReason()');

// Every extracted entry has to LOOK like a path, or the extraction silently
// picked up a comment, a `local` line or a stray token and the corpus below
// would be generated from garbage.
// 抽出的每一項都必須長得像路徑，否則語料是從垃圾生成的。
for (const entry of cliProtectedDirsRaw) {
  require_(/^(\/|\$HOME)/.test(entry), `PROTECTED_DIRS parsed a non-path entry: ${entry}`);
  require_(!/["']/.test(entry), `PROTECTED_DIRS entry kept its quoting: ${entry}`);
}
for (const entry of [...cliMountParents, ...hook.SYSTEM_DIRS, ...hook.MOUNT_PARENTS, FIRMLINK_PREFIX]) {
  require_(/^\//.test(entry), `a protected-path source parsed a non-path entry: ${entry}`);
}

// ---------------------------------------------------------------------------
// 2. The environment both guards are measured in
//    兩道守衛共用的量測環境
// ---------------------------------------------------------------------------
// HOME is a path that does not exist on either platform and is never written
// to. It is spelled under /Users on purpose: /Users is itself protected, which
// makes the `$HOME/..` spelling meaningful, and it gives the macOS firmlink
// spelling of the home directory (/System/Volumes/Data/Users/...) something to
// bite on without involving the real user's home.
// HOME 刻意放在 /Users 底下（/Users 本身受保護，$HOME/.. 才有意義），而且是一條
// 不存在、也永遠不會被寫入的路徑。
const HOME = '/Users/better-rm-parity-probe';

// realpathSync so the sandbox is the PHYSICAL path: macOS resolves TMPDIR
// through /var -> /private/var, and better-rm's is_protected compares a
// readlink-resolved path against a lexically normalised one. Handing the two
// sides different spellings of the same directory would manufacture divergences
// that belong to the harness rather than to either guard.
// 取實體路徑：macOS 的 TMPDIR 會經過 /var -> /private/var，兩邊拿到不同拼寫會造出
// 假的分歧。
const sandbox = fs.mkdtempSync(path.join(fs.realpathSync(os.tmpdir()), 'better-rm-parity.'));
// Registered on 'exit' rather than called at each return: an unexpected throw
// must not leave the fixture behind in the runner's temporary directory.
process.on('exit', () => {
  try { fs.rmSync(sandbox, { recursive: true, force: true }); } catch (_) { /* best effort */ }
});
const EXTRA_PROTECTED = path.join(sandbox, 'secrets');

// Symlink fixtures. The link TARGET is /usr and only /usr: it is a real
// directory on both macOS and ubuntu, while /etc and /var are symlinks on macOS
// (they resolve to /private/etc, /private/var) and /bin is a symlink on ubuntu
// (it resolves to /usr/bin). Any of those would make the resolved-path rows
// platform-dependent for reasons that have nothing to do with the two guards.
// 連結目標只用 /usr：macOS 上 /etc、/var 是 symlink，ubuntu 上 /bin 是 symlink，
// 用它們當目標會讓「解析後」那幾列的判定隨平台改變，而那與兩道守衛無關。
const LINK_TO_PROTECTED = path.join(sandbox, 'link-to-usr');
const LINK_TO_ITEM_INSIDE = path.join(sandbox, 'link-to-usr-share');
const LINK_DANGLING = path.join(sandbox, 'link-to-unmounted-volume');
const LINK_TO_GIT_DIR = path.join(sandbox, 'link-to-git-dir');
const REPO_FIXTURE = path.join(sandbox, 'repo');
fs.mkdirSync(path.join(REPO_FIXTURE, '.git'), { recursive: true });
fs.symlinkSync('/usr', LINK_TO_PROTECTED);
fs.symlinkSync('/usr/share', LINK_TO_ITEM_INSIDE);
fs.symlinkSync('/Volumes/BetterRmParityNotMounted/item', LINK_DANGLING);
fs.symlinkSync(path.join(REPO_FIXTURE, '.git'), LINK_TO_GIT_DIR);

// ---------------------------------------------------------------------------
// 3. The corpus
//    語料
// ---------------------------------------------------------------------------
// expect:
//   'deny'  both guards must refuse -- the protection itself
//   'allow' both guards must permit -- the anti-tautology half. A guard that
//           went prefix-broad would satisfy every 'deny' row and still be a
//           worse regression than a missing entry: removing one app bundle from
//           /Applications is ordinary work.
//   'agree' no opinion on the verdict, only that the two guards return the SAME
//           one. Rows whose correct answer is a decision for the round, not for
//           this harness, sit here.
// expect：deny＝兩邊都必須拒絕；allow＝兩邊都必須放行（反恆真的另一半）；
// agree＝不預設答案，只要求兩邊一致。

const corpus = [];
const seen = new Set();

function add(group, expect, spelling, note) {
  require_(typeof spelling === 'string' && spelling.length > 0,
    `the corpus generated an empty spelling in group ${group}`);
  require_(!/[\t\n\r\0]/.test(spelling),
    `the corpus generated a spelling the line-based probe cannot carry: ${JSON.stringify(spelling)}`);
  // A leading '-' would be read as an option by the rm operand scan rather than
  // as a target, which would silently make the hook column meaningless.
  // 開頭是 '-' 會被當成選項而不是目標，hook 那一欄會靜靜失去意義。
  require_(!spelling.startsWith('-'),
    `the corpus generated a spelling that rm would read as an option: ${spelling}`);
  const key = `${group} ${spelling}`;
  if (seen.has(key)) return;
  seen.add(key);
  corpus.push({ group, expect, spelling, note: note || '' });
}

const stripTrailingSlash = (item) => item.replace(/(.)\/+$/, '$1');
const join = (base, leaf) => (base === '/' ? `/${leaf}` : `${base}/${leaf}`);

const protectedDirs = [...new Set([
  ...cliProtectedDirsRaw.map((item) => stripTrailingSlash(item.replace(/^\$HOME/, HOME))),
  ...hook.SYSTEM_DIRS.map(stripTrailingSlash),
  HOME,
])].sort();
const mountParents = [...new Set([...cliMountParents, ...hook.MOUNT_PARENTS])].sort();

// -- every protected entry, in every spelling ------------------------------
// bare, trailing slash, doubled slashes, /., /.., and a relative spelling that
// resolves to it. Each is a different code path: better-rm normalises with its
// own normalize_path (sed + IFS split), the hook with path.resolve, and the
// resolved/unresolved halves of is_protected disagree about which one wins.
// 每一項的六種拼寫各自走不同的正規化路徑。
for (const dir of protectedDirs) {
  add('protected-spelling', 'deny', dir);
  add('protected-spelling', 'deny', dir === '/' ? '//' : `${dir}/`);
  add('protected-spelling', 'deny', dir === '/' ? '///' : dir.replace(/\//g, '//'));
  add('protected-spelling', 'deny', join(dir, '.'));
  // '/..' from any first-level entry lands on '/', and from the two nested ones
  // (/System/Volumes, and $HOME under /Users) on their protected parents. The
  // expectation is derived rather than assumed: an entry added later whose
  // parent is NOT protected would otherwise be asserted into a refusal nobody
  // ever intended, and a harness that invents work items is worse than none.
  // 期望值是推導出來的，不是假設的：日後新增一項而它的父目錄不受保護時，寫死
  // 'deny' 會憑空造出一個沒人要求的工作項目。
  const parentDir = path.dirname(dir);
  add('protected-spelling', protectedDirs.includes(parentDir) ? 'deny' : 'agree',
    join(dir, '..'), `resolves to ${parentDir}`);
  const relative = path.relative(sandbox, dir);
  if (relative) add('protected-spelling', 'deny', relative, `resolves to ${dir}`);

  // The anti-tautology half: the directory is protected, what is inside it is
  // not. Excluded for mount parents, where the first level is a mount root and
  // is protected on purpose (covered by the mount group below).
  // 反恆真的另一半：受保護的是目錄本身，不是它底下的一切。掛載父目錄除外。
  if (!mountParents.includes(dir)) {
    add('inside-protected', 'allow', join(dir, 'inside-item'));
  }
}

// -- mount parents ---------------------------------------------------------
// Under a mount parent the first level is where a whole disk is attached:
// /Volumes/Backup is the backup disk, /mnt/c is the Windows filesystem, and
// /System/Volumes/Data is the Mac's own data volume. Both guards protect that
// level and allow what is inside it.
// 掛載父目錄的第一層是整顆磁碟的掛載點，兩邊都保護該層、放行其內容。
for (const parent of mountParents) {
  const leaf = parent.split('/').filter(Boolean).pop();
  add('mount-root', 'deny', `${parent}/probe-disk`);
  add('mount-root', 'deny', `${parent}/probe-disk/`);
  add('mount-root', 'deny', `${parent}/probe disk`, 'a volume name with a space');
  add('mount-root', 'deny', `${parent}/../${leaf}/probe-disk`, 'a mount root re-entered through ..');
  // A mount root may legitimately be NAMED '..something'. Reading those leading
  // dots as an escape from the parent hands the disk over.
  // 掛載根本身可以叫做 '..某某'，把那兩點讀成跳脫等於把整顆磁碟交出去。
  add('mount-root', 'deny', `${parent}/..probe-disk`);
  add('mount-inside', 'allow', `${parent}/probe-disk/inside-item`);
  add('mount-inside', 'allow', `${parent}/..probe-disk/inside-item`);
  add('mount-inside', 'allow', `${parent}/probe-disk/inside-item/deeper`);
}

// -- macOS firmlinks -------------------------------------------------------
// /System/Volumes/Data/X and /X are the same object on a modern Mac: measured
// with stat -f '%d:%i', /Users/<user> and /System/Volumes/Data/Users/<user>
// share a device and an inode. A firmlink is not a symlink -- readlink -f hands
// either spelling straight back -- so no canonicalisation brings the two
// together and each guard has to know the rule separately. better-rm rewrites
// the prefix; the hook has no such rule.
// 這幾列不需要任何路徑存在：兩邊的規則都是字串層面的，ubuntu 上判定完全相同。
for (const dir of protectedDirs) {
  if (dir === '/') continue;
  add('firmlink', 'agree', `${FIRMLINK_PREFIX}${dir}`, `same object as ${dir}`);
}
add('firmlink', 'deny', FIRMLINK_PREFIX, 'the data volume root itself');
add('firmlink', 'deny', `${FIRMLINK_PREFIX}/`, 'the data volume root itself');
// The rule must not become a blanket refusal of everything on the data volume,
// and the prefix has to align on a whole component.
// 反恆真：不能變成整顆資料卷宗一律拒絕，而且前綴必須整段對齊。
add('firmlink', 'allow', `${FIRMLINK_PREFIX}/not-a-protected-name`);
add('firmlink', 'allow', `${FIRMLINK_PREFIX}/not-a-protected-name/inside-item`);
add('firmlink', 'allow', `${FIRMLINK_PREFIX}/usr/local/share/inside-item`);
add('firmlink', 'deny', `${FIRMLINK_PREFIX}Drive`, 'a volume merely named Data...');
add('firmlink', 'allow', `${FIRMLINK_PREFIX}Drive/inside-item`);

// -- symlink spellings -----------------------------------------------------
// better-rm deliberately does not resolve a symlink ARGUMENT: deleting a link
// cannot touch what it points at, so refusing ~/applink -> /Applications would
// be a false positive with no -f override. But `link/` and `link/.` and
// `link/..` are not the link -- a trailing slash forces resolution of the final
// component on both platforms -- so those spellings DO reach the target.
// better-rm 刻意不解析「引數本身就是連結」的情況，但 `link/`、`link/.`、`link/..`
// 依 POSIX 會強制解析最後一段，那幾種拼寫會真的碰到目標。
add('symlink', 'allow', LINK_TO_PROTECTED, 'the link itself is not the target');
add('symlink', 'agree', `${LINK_TO_PROTECTED}/`);
add('symlink', 'agree', `${LINK_TO_PROTECTED}/.`);
add('symlink', 'agree', `${LINK_TO_PROTECTED}/..`, 'resolves to / through the link');
add('symlink', 'allow', LINK_TO_ITEM_INSIDE, 'points inside a protected dir, not at it');
add('symlink', 'allow', `${LINK_TO_ITEM_INSIDE}/`);
add('symlink', 'allow', LINK_DANGLING, 'dangling: the volume is not mounted');
add('symlink', 'allow', `${LINK_DANGLING}/`, 'a partial resolution must not be trusted');
add('symlink', 'allow', LINK_TO_GIT_DIR, 'the link itself is not named .git');
add('symlink', 'agree', `${LINK_TO_GIT_DIR}/`);

// -- .git shapes -----------------------------------------------------------
// A path INSIDE .git is as unrecoverable as .git itself: .git/objects or
// .git/index.lock loses (or wedges) the repository.
// .git 內部的路徑與 .git 本身一樣不可還原。
add('git', 'deny', path.join(REPO_FIXTURE, '.git'));
add('git', 'deny', `${path.join(REPO_FIXTURE, '.git')}/`);
add('git', 'deny', '.git', 'relative to the sandbox');
add('git', 'agree', path.join(REPO_FIXTURE, '.git', 'index.lock'));
add('git', 'agree', path.join(REPO_FIXTURE, 'sub', '.git', 'objects'));
add('git', 'agree', '.git/objects/pack', 'relative to the sandbox');
// Negative control: .git has to be a path COMPONENT, not a substring.
// 負對照：.git 必須是路徑元件而非子字串。
add('git', 'allow', path.join(REPO_FIXTURE, '.gitignore'));
add('git', 'allow', path.join(REPO_FIXTURE, '.github', 'workflows'));
add('git', 'allow', path.join(REPO_FIXTURE, 'vendor.git'));
add('git', 'allow', path.join(REPO_FIXTURE, '.git.bak'));

// -- BETTER_RM_PROTECTED_DIRS ----------------------------------------------
// The hook reads this environment variable and adds its entries to the exact
// list. better-rm has no reference to it anywhere in the file, so the same
// variable that hardens the agent path does nothing for the shell alias.
// hook 會讀這個環境變數並加進清單，better-rm 全檔沒有任何一處提到它。
add('extra-dirs', 'agree', EXTRA_PROTECTED, 'BETTER_RM_PROTECTED_DIRS entry');
add('extra-dirs', 'agree', `${EXTRA_PROTECTED}/`);
add('extra-dirs', 'allow', `${EXTRA_PROTECTED}/inside-item`);

// -- spellings that only one layer ever sees -------------------------------
// The two guards sit at different layers: the hook parses the shell command
// TEXT before expansion, better-rm receives argv AFTER the shell expanded it.
// A quoted operand reaches both unchanged, so these rows are real -- but the
// right resolution for them is a judgement call about layering, not necessarily
// a change to either guard. Grouped separately so the round can triage them.
// 兩道守衛所處的層不同：hook 看的是展開前的命令文字，better-rm 收到的是展開後的
// argv。加引號的引數兩邊都會原樣收到，所以這幾列是真的分歧，但要怎麼收斂是分層
// 判斷，未必是改哪一邊。獨立分組以便分流。
add('shell-layer', 'agree', '~', 'the hook expands it, argv would not');
add('shell-layer', 'agree', '$HOME');
add('shell-layer', 'agree', '${HOME}');
add('shell-layer', 'allow', '~/keep');
add('shell-layer', 'agree', '/usr\\', 'a trailing backslash is a filename character in argv');
// A glob reaches argv literally when nothing matched it; the hook cannot expand
// it and refuses anything that COULD select .git.
// 什麼都沒 match 到時，萬用字元會原樣進 argv；hook 無法展開，只能一律拒絕。
add('shell-layer', 'agree', path.join(sandbox, '*'));
add('shell-layer', 'agree', path.join(sandbox, '.gi*'));
add('shell-layer', 'agree', path.join(sandbox, '{.git,dist}'));
add('shell-layer', 'allow', path.join(sandbox, 'build', '*.log'));

// -- ordinary paths --------------------------------------------------------
// The last line of defence against a guard that simply says yes.
// 最後一道反恆真：守衛不能是一律說是。
add('ordinary', 'allow', path.join(sandbox, 'ordinary.txt'));
add('ordinary', 'allow', path.join(sandbox, 'build'));
add('ordinary', 'allow', 'build/artifacts', 'relative to the sandbox');
add('ordinary', 'allow', '/usr/local/share/inside-item');
add('ordinary', 'allow', '/etc/hosts', 'a real file: only stat-ed, never touched');
add('ordinary', 'allow', join(HOME, 'keep'));

// The generator must actually have covered both extracted lists. A silent
// filter bug that dropped entries would leave a corpus that agrees trivially.
// 生成器必須真的涵蓋抽出的兩份清單，否則語料會恆真。
const bareSpellings = new Set(corpus.filter((row) => row.group === 'protected-spelling').map((row) => row.spelling));
for (const dir of protectedDirs) {
  require_(bareSpellings.has(dir), `the corpus generator dropped a protected entry: ${dir}`);
  require_(corpus.some((row) => row.spelling === `${FIRMLINK_PREFIX}${dir}` || dir === '/'),
    `the corpus generator dropped the firmlink spelling of: ${dir}`);
}
for (const parent of mountParents) {
  require_(corpus.some((row) => row.spelling === `${parent}/probe-disk`),
    `the corpus generator dropped a mount parent: ${parent}`);
}
require_(corpus.length > 0, 'the corpus is empty');
const groups = [...new Set(corpus.map((row) => row.group))];
require_(groups.length >= 9, `the corpus lost a whole group (${groups.join(', ')})`);

// ---------------------------------------------------------------------------
// 4. Hook verdicts, through the exported evaluate()
//    hook 端判定：走它匯出的 evaluate()
// ---------------------------------------------------------------------------
const hookEnv = { HOME, BETTER_RM_PROTECTED_DIRS: EXTRA_PROTECTED };
const hookExtraDirs = hookEnv.BETTER_RM_PROTECTED_DIRS
  .split(path.delimiter).filter(Boolean).map((item) => path.resolve(sandbox, item));

const singleQuote = (value) => `'${value.replace(/'/g, "'\\''")}'`;

function hookVerdict(spelling) {
  const command = `rm -rf ${singleQuote(spelling)}`;
  const payload = {
    hook_event_name: 'PreToolUse',
    tool_name: 'Bash',
    tool_input: { command },
    cwd: sandbox,
  };
  const result = hook.evaluate(payload, hookEnv);
  if (result === null) return 'ALLOW';
  require_(
    result && result.hookSpecificOutput && result.hookSpecificOutput.permissionDecision === 'deny',
    `evaluate() returned a shape that is neither allow nor deny for ${spelling}: ${JSON.stringify(result)}`
  );
  return 'DENY';
}

for (const row of corpus) {
  row.hook = hookVerdict(row.spelling);
  // The operand has to survive the shell tokenizer unchanged, or the hook column
  // is measuring the quoting rather than the guard. protectedReason() is the same
  // predicate evaluate() ends up calling, reached without the tokenizer.
  // 引數必須原樣穿過 tokenizer，否則這一欄量到的是引號而不是守衛。
  const direct = hook.protectedReason(row.spelling, sandbox, HOME, hookExtraDirs) !== null
    ? 'DENY' : 'ALLOW';
  require_(direct === row.hook,
    `the quoted command did not carry the operand to the predicate unchanged: `
    + `${row.spelling} (via evaluate: ${row.hook}, direct: ${direct})`);
}

// ---------------------------------------------------------------------------
// 5. better-rm verdicts, through is_protected() extracted from the script
//    CLI 端判定：用套件既有的 sed 區段抽取法取出 is_protected()
// ---------------------------------------------------------------------------
// The extraction idiom is the one test-better-rm.sh already uses. main() is
// never run: driving the real /usr or /etc through the binary would, the moment
// the guard failed, make the test itself move the filesystem.
// 抽函式而不跑 main：保護一旦失效，跑 main 就是叫測試自己去搬檔案系統。
const corpusPath = path.join(sandbox, 'corpus.txt');
fs.writeFileSync(corpusPath, corpus.map((row) => row.spelling).join('\n') + '\n');

const cliProbe = `
BETTER_RM="$1"
CORPUS="$2"

eval "$(sed -n "/^PROTECTED_DIRS=(/,/^)/p;/^PROTECTED_PATTERNS=(/,/^)/p" "$BETTER_RM")"
eval "$(sed -n "/^normalize_path()/,/^}/p;/^is_protected()/,/^}/p" "$BETTER_RM")"

if [ "$(type -t is_protected)" != function ] ||
   [ "$(type -t normalize_path)" != function ] ||
   [ "\${#PROTECTED_DIRS[@]}" -eq 0 ] ||
   [ "\${#PROTECTED_PATTERNS[@]}" -eq 0 ]; then
    printf "extraction produced no functions or no lists\\n" >&2
    exit 99
fi

verdict() {
    if is_protected "$1" >/dev/null 2>&1; then
        printf "DENY\\n"
    else
        printf "ALLOW\\n"
    fi
}

# The probe must be two-valued before its answers mean anything: one that always
# said ALLOW would make every deny row look like a hook-only refusal, and one
# that always said DENY would hide every gap. Either the extraction is broken or
# the guard itself has stopped distinguishing -- both make every verdict below
# meaningless, so neither may be reported as a finding.
# 探針必須是雙值的，否則它的答案沒有意義：不論是抽取壞了還是守衛本身不再分辨，
# 底下每一列判定都失去意義，兩者都不可被讀成「發現」。
if [ "$(verdict /)" != DENY ] || [ "$(verdict "$PWD/parity-self-check.txt")" != ALLOW ]; then
    printf "is_protected gave / and an ordinary file the same verdict: the extraction is broken, or the guard no longer distinguishes\\n" >&2
    exit 99
fi

while IFS= read -r spelling; do
    verdict "$spelling"
done < "$CORPUS"
`;

let cliOutput;
try {
  cliOutput = execFileSync('bash', ['-c', cliProbe, 'better-rm-is-protected', BETTER_RM, corpusPath], {
    cwd: sandbox,
    encoding: 'utf8',
    maxBuffer: 8 * 1024 * 1024,
    env: {
      PATH: process.env.PATH,
      HOME,
      BETTER_RM_PROTECTED_DIRS: EXTRA_PROTECTED,
      LC_ALL: 'C',
    },
  });
} catch (error) {
  probeBroken(`the is_protected probe exited ${error.status}: ${String(error.stderr || error.message).trim()}`);
}

const cliVerdicts = cliOutput.split('\n').filter((line) => line !== '');
require_(cliVerdicts.length === corpus.length,
  `the is_protected probe returned ${cliVerdicts.length} verdicts for ${corpus.length} corpus rows`);
for (let index = 0; index < corpus.length; index += 1) {
  const verdict = cliVerdicts[index];
  require_(verdict === 'DENY' || verdict === 'ALLOW',
    `the is_protected probe returned an unreadable verdict: ${JSON.stringify(verdict)}`);
  corpus[index].cli = verdict;
}

// Neither column may be constant. A guard that answered the same way for every
// spelling would make the comparison agree (or disagree) for free.
// 任一欄都不能是常數，否則比對是免費的。
for (const side of ['hook', 'cli']) {
  require_(corpus.some((row) => row[side] === 'DENY'),
    `the ${side} column never refused anything: the probe is broken, or that guard now allows everything`);
  require_(corpus.some((row) => row[side] === 'ALLOW'),
    `the ${side} column never allowed anything: the probe is broken, or that guard now refuses everything`);
}

// ---------------------------------------------------------------------------
// 6. Report
//    報告
// ---------------------------------------------------------------------------
// Only the sandbox path is abbreviated: it is long, it changes every run, and
// nothing about a row depends on its spelling. HOME is left literal -- shortening
// it would render the home firmlink row as "/System/Volumes/Data$HOME", which
// hides the very shape that row exists to show.
// 只縮寫 sandbox 路徑；HOME 保持原樣，否則 firmlink 那一列會被縮成看不出形狀。
const display = (spelling) => spelling.split(sandbox).join('$SANDBOX');

function table(rows, columns) {
  const widths = columns.map((column) => Math.max(
    column.header.length,
    ...rows.map((row) => String(column.value(row)).length),
  ));
  const line = (cells) => cells
    .map((cell, index) => (index === cells.length - 1 ? cell : String(cell).padEnd(widths[index])))
    .join('  ');
  const out = [line(columns.map((column) => column.header))];
  out.push(line(widths.map((width) => '-'.repeat(width))));
  for (const row of rows) out.push(line(columns.map((column) => String(column.value(row)))));
  return out.join('\n');
}

const divergences = corpus.filter((row) => row.hook !== row.cli);
const expectationFailures = corpus.filter((row) => row.hook === row.cli
  && ((row.expect === 'deny' && row.hook === 'ALLOW') || (row.expect === 'allow' && row.hook === 'DENY')));

// The corpus header belongs with whichever report is being produced. Splitting
// it across stdout and stderr let the two streams interleave differently on
// different runners, which made two identical results look unequal.
// 標頭跟著該次的報告走：分散在 stdout 與 stderr 會因為 runner 不同而交錯不同，
// 讓兩份相同的結果看起來不一樣。
const header = [
  `Guard parity corpus / 差分語料：${corpus.length} rows, ${groups.length} groups`,
  `  $SANDBOX = ${sandbox}`,
  `  $HOME    = ${HOME}`,
].join('\n');

if (divergences.length === 0 && expectationFailures.length === 0) {
  console.log(header);
  console.log(`Guard parity 測試通過 / Guard parity checks passed: ${corpus.length * 2}`);
  process.exit(0);
}

console.error(header);

if (divergences.length > 0) {
  console.error('');
  console.error(`兩道守衛判定不一致 / The two guards disagree on ${divergences.length} of ${corpus.length} spellings:`);
  console.error(table(divergences, [
    { header: 'group', value: (row) => row.group },
    { header: 'hook', value: (row) => row.hook },
    { header: 'better-rm', value: (row) => row.cli },
    { header: 'direction', value: (row) => (row.hook === 'ALLOW'
      ? 'hook ALLOWs what better-rm refuses'
      : 'better-rm ALLOWs what the hook refuses') },
    { header: 'expect', value: (row) => row.expect },
    { header: 'path', value: (row) => display(row.spelling) + (row.note ? `  (${row.note})` : '') },
  ]));
}

if (expectationFailures.length > 0) {
  console.error('');
  console.error(`兩邊一致但都答錯 / Both guards agree, and both are wrong, on ${expectationFailures.length} spellings:`);
  console.error(table(expectationFailures, [
    { header: 'group', value: (row) => row.group },
    { header: 'expected', value: (row) => row.expect.toUpperCase() },
    { header: 'both said', value: (row) => row.hook },
    { header: 'path', value: (row) => display(row.spelling) + (row.note ? `  (${row.note})` : '') },
  ]));
}

console.error('');
console.error('每一列都是這一輪的工作項目：先決定哪一邊是對的，再讓兩邊一致。');
console.error('Each row is a work item: decide which side is right, then make the two agree.');
process.exit(1);
