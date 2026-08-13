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
// A few spellings cannot agree, because the two guards do not observe the same
// thing: one reads command text before the shell expands it, the other reads argv
// after, and one may touch the filesystem while the other must not. Those are
// declared one by one in section 3b with their direction and reason, and the
// declarations are checked in both directions so the list cannot become a place
// to hide rows -- see the comment there.
// 有幾種拼寫不可能一致（兩邊觀察的不是同一個東西），在 3b 逐條宣告方向與理由，並且
// 雙向檢查，詳見該處註解。
//
// Exit codes / 結束碼:
//   0  every row agrees (or is a declared cross-layer difference that still holds)
//      and every expectation holds
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
// Every list either guard consults is read from where it lives and generates
// rows: better-rm's PROTECTED_DIRS, its mount-parent loop, its firmlink prefix
// and its PROTECTED_PATTERNS; the hook's SYSTEM_DIRS and MOUNT_PARENTS; and the
// BETTER_RM_PROTECTED_DIRS entries the harness itself declares. An entry added
// to any of them is exercised in every spelling below without anyone
// remembering to add rows, and a transcription here would drift with neither.
// This sentence used to claim the corpus came from "the UNION of both guards'
// lists" while PROTECTED_PATTERNS was extracted, asserted non-empty, and then
// never turned into a single row -- adding `.svn` to it produced a real
// CLI-DENY / hook-ALLOW difference that all three suites reported as green. A
// list that is read but not driven is worse than one nobody read: it looks
// covered.
// 兩道守衛用到的每一份清單都從出處讀出來並生成語料：better-rm 的 PROTECTED_DIRS、
// 掛載父目錄迴圈、firmlink 前綴、PROTECTED_PATTERNS，hook 的 SYSTEM_DIRS 與
// MOUNT_PARENTS，以及本檔自己宣告的 BETTER_RM_PROTECTED_DIRS。這句話原本寫「由兩邊
// 清單的聯集生成」，但 PROTECTED_PATTERNS 只被抽出來斷言非空、一列都沒生成——在它
// 加一個 `.svn` 會造出真實的分歧，而三套測試全綠。讀了卻沒驅動的清單比沒讀更糟：
// 它看起來已經涵蓋了。

const betterRmSource = fs.readFileSync(BETTER_RM, 'utf8');

const protectedDirsBlock = betterRmSource.match(/^PROTECTED_DIRS=\(\n([\s\S]*?)^\)$/m);
require_(protectedDirsBlock, 'PROTECTED_DIRS was not found in better-rm');
const cliProtectedDirsRaw = protectedDirsBlock[1]
  .split('\n')
  .map((line) => line.trim())
  .filter((line) => line && !line.startsWith('#'))
  .map((line) => line.replace(/^"(.*)"$/, '$1'));
require_(cliProtectedDirsRaw.length > 0, 'PROTECTED_DIRS parsed as empty');

// better-rm's THIRD protected list. It is matched as a bash glob against the
// basename and against the whole path, so it protects a NAME wherever it occurs
// rather than one absolute location -- the hook has no list of that shape at
// all, only two hard-coded `.git` rules, and whether those two happen to cover
// this list is exactly the question a differential test exists to answer.
// better-rm 的第三份清單：以 bash glob 比對 basename 與整條路徑，保護的是「名字」
// 而不是某個絕對位置；hook 那邊根本沒有同形狀的清單，只有兩條寫死的 .git 規則。
const protectedPatternsBlock = betterRmSource.match(/^PROTECTED_PATTERNS=\(\n([\s\S]*?)^\)$/m);
require_(protectedPatternsBlock, 'PROTECTED_PATTERNS was not found in better-rm');
const cliProtectedPatterns = protectedPatternsBlock[1]
  .split('\n')
  .map((line) => line.trim())
  .filter((line) => line && !line.startsWith('#'))
  .map((line) => line.replace(/^"(.*)"$/, '$1'));
require_(cliProtectedPatterns.length > 0, 'PROTECTED_PATTERNS parsed as empty');

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
// A pattern is a name, not a path: it must not be absolute (an absolute entry
// would belong in PROTECTED_DIRS and the generator below would place it twice),
// and it must not carry whitespace or quoting picked up from the source.
// pattern 是名字不是路徑：不得為絕對路徑，也不得帶著引號或空白。
for (const entry of cliProtectedPatterns) {
  require_(!/["']/.test(entry), `PROTECTED_PATTERNS entry kept its quoting: ${entry}`);
  require_(!/\s/.test(entry), `PROTECTED_PATTERNS parsed an entry with whitespace: ${entry}`);
  require_(!entry.startsWith('/'), `PROTECTED_PATTERNS parsed an absolute path: ${entry}`);
}

// ---------------------------------------------------------------------------
// 2. The environment both guards are measured in
//    兩道守衛共用的量測環境
// ---------------------------------------------------------------------------
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
// HOME is a real, existing directory INSIDE the sandbox, created here and
// removed with it. It used to be '/Users/better-rm-parity-probe' -- a path
// chosen because it cannot exist, which silently disabled half of the guard
// under test: is_protected() only reaches its readlink/realpath branch when
// `[ -e "$path" ]` holds, so with a home that cannot exist no HOME spelling ever
// exercised the resolving side, and the whole class of differences that lives
// there (a case-folded or differently-normalised spelling that the filesystem
// resolves onto the protected directory) could not appear in the corpus at all.
// A real home cannot be the user's own: is_protected() stats what it is given,
// the corpus enumerates ~60 spellings under HOME, and pointing those at the
// machine's real home would make the run depend on that machine's contents and
// walk whatever is mounted inside it. A sandbox directory that really exists
// stands in for it and gives the resolving branch something to resolve.
// The two properties the old /Users placement bought are kept deliberately:
// `$HOME/..` still lands on a protected directory, because HOME's parent
// (<sandbox>/Users) is declared in BETTER_RM_PROTECTED_DIRS below; and the
// macOS firmlink spelling still has something to bite on, because the firmlink
// group prefixes every protected entry including this one.
// HOME 改成 sandbox 裡「真的存在」的目錄（隨 sandbox 一起刪）。原本刻意選一條不可能
// 存在的路徑，等於把受測守衛的一半關掉：is_protected 只有在 `[ -e ]` 成立時才會走到
// readlink/realpath 那一支，家目錄不存在就永遠走不到，而「大小寫或正規化不同的拼寫
// 被檔案系統解析回受保護目錄」這整類差異就進不了語料。不能用使用者真正的家目錄：
// is_protected 會去 stat，語料底下有約 60 條 HOME 拼寫，指到真家目錄會讓結果隨機器
// 內容而變，也會走進裡面掛載的東西。舊 /Users 位置換來的兩個性質都保留：$HOME/..
// 仍落在受保護目錄（父目錄已宣告進 BETTER_RM_PROTECTED_DIRS），firmlink 那組也照樣
// 會把這一條加上前綴。
const HOME_PARENT = path.join(sandbox, 'Users');
const HOME = path.join(HOME_PARENT, 'probe-user');
fs.mkdirSync(HOME, { recursive: true });

const EXTRA_PROTECTED = path.join(sandbox, 'secrets');
const EXTRA_PROTECTED_RELATIVE = 'relative-secrets';

// Unicode fixtures. macOS stores a filename's bytes as given but compares them
// normalisation-insensitively, so a directory created NFC answers to its NFD
// spelling and back: measured, both spellings return one dev:ino, and BSD
// `readlink -f` hands back the spelling that is ON DISK rather than the one it
// was given. better-rm therefore protects a declared directory under both
// encodings, while the hook -- which never touches the filesystem and compares
// strings -- protects only the byte-exact one. Two fixtures, one declared NFC
// and one declared NFD, so neither encoding is privileged as "the" spelling.
// macOS 保存檔名的位元組但比對時不分正規化形式：NFC 建立的目錄用 NFD 也找得到（實測
// 同 dev:ino），而 BSD readlink -f 回傳的是磁碟上的拼寫而不是傳進去的那個。於是
// better-rm 兩種編碼都保護，hook 只保護位元組完全相同的那一種。兩個 fixture 各以一
// 種編碼宣告，不讓任一編碼被當成「正統」。
const UNICODE_DECLARED = ['nfc', 'nfd'].map((label) => {
  const leaf = `café-${label}-secrets`.normalize(label.toUpperCase());
  const directory = path.join(sandbox, leaf);
  fs.mkdirSync(directory);
  return { label: label.toUpperCase(), leaf, directory };
});
for (const { label, leaf } of UNICODE_DECLARED) {
  require_(leaf.normalize('NFC') !== leaf.normalize('NFD'),
    `the unicode fixture declared as ${label} has no second encoding: ${JSON.stringify(leaf)}`);
  require_(leaf === leaf.normalize(label),
    `the unicode fixture declared as ${label} is not in that form: ${JSON.stringify(leaf)}`);
}

// The value both guards are handed: an absolute entry, an EMPTY entry, a
// relative one, the parent of HOME, and the two Unicode fixtures. Written as one
// string rather than separate constants because the separator is part of what is
// being compared -- a guard that split on something else would protect a
// different set.
// 兩邊拿到的同一個值：絕對項、空項、相對項、HOME 的父目錄、兩個 Unicode fixture。
// 分隔符本身就是比對的一部分。
const EXTRA_PROTECTED_ABSOLUTE = [
  EXTRA_PROTECTED,
  HOME_PARENT,
  ...UNICODE_DECLARED.map(({ directory }) => directory),
];
const EXTRA_PROTECTED_VALUE = [
  EXTRA_PROTECTED,
  '',
  EXTRA_PROTECTED_RELATIVE,
  HOME_PARENT,
  ...UNICODE_DECLARED.map(({ directory }) => directory),
].join(path.delimiter);

// The environment the hook is measured in, defined here rather than beside the
// verdicts because the cross-layer class predicates in section 3b consult the
// hook's own exported predicate with exactly these arguments.
// hook 的量測環境提前定義：3b 的跨層分類判準要用同一組參數呼叫 hook 自己的判斷式。
const hookEnv = { HOME, BETTER_RM_PROTECTED_DIRS: EXTRA_PROTECTED_VALUE };
const hookExtraDirs = hookEnv.BETTER_RM_PROTECTED_DIRS
  .split(path.delimiter).filter(Boolean).map((item) => path.resolve(sandbox, item));

// Two spellings name ONE object, or they do not. Asked of the filesystem rather
// than assumed from the platform: a case-insensitive volume can be mounted on
// Linux and a case-SENSITIVE one formatted on macOS, and an expectation derived
// from `process.platform` would be wrong on both. dev+ino rather than realpath,
// because Node's realpath returns the spelling it was given (measured:
// realpathSync('/USERS') is '/USERS') while stat resolves to the object.
// 兩種拼寫是不是同一個物件，用問檔案系統的、不是照平台猜的：Linux 可以掛不分大小寫
// 的卷宗，macOS 也能格式化分大小寫的。用 dev+ino 而不是 realpath——Node 的 realpath
// 會原樣回傳（實測 realpathSync('/USERS') 就是 '/USERS'），stat 才會落到物件上。
function sameObject(left, right) {
  try {
    const a = fs.statSync(left);
    const b = fs.statSync(right);
    return a.dev === b.dev && a.ino === b.ino;
  } catch (_) {
    return false;
  }
}

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

// Where the PROTECTED_PATTERNS rows are placed. A pattern protects a NAME
// wherever it occurs, so it needs a location that is otherwise ordinary and a
// second level, to show that the rule is not anchored to one depth.
// PROTECTED_PATTERNS 那組列的落點：pattern 保護的是名字而非位置，所以需要一個本身
// 平凡的地方，外加一層巢狀來證明規則不綁深度。
const PATTERN_FIXTURE_RELATIVE = 'pattern-fixture';
const PATTERN_FIXTURE = path.join(sandbox, PATTERN_FIXTURE_RELATIVE);
const PATTERN_FIXTURE_NESTED = 'nested';
fs.mkdirSync(path.join(PATTERN_FIXTURE, PATTERN_FIXTURE_NESTED), { recursive: true });

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
// Everything either guard is supposed to treat as an exact protected location:
// the two built-in lists plus the directories this run declares through
// BETTER_RM_PROTECTED_DIRS. The '..' derivation and the case generator both work
// off this, so a declared directory is not a second-class protected entry.
// 兩邊「完全比對」該保護的全部位置：內建清單，加上本次執行透過
// BETTER_RM_PROTECTED_DIRS 宣告的目錄。'..' 推導與大小寫生成器都以它為準。
const exactProtected = [...new Set([...protectedDirs, ...EXTRA_PROTECTED_ABSOLUTE])].sort();

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
  // '/..' from any first-level entry lands on '/', and from the nested ones
  // (/System/Volumes, and $HOME under its declared parent) on their protected
  // parents. The expectation is derived rather than assumed: an entry added later whose
  // parent is NOT protected would otherwise be asserted into a refusal nobody
  // ever intended, and a harness that invents work items is worse than none.
  // 期望值是推導出來的，不是假設的：日後新增一項而它的父目錄不受保護時，寫死
  // 'deny' 會憑空造出一個沒人要求的工作項目。
  const parentDir = path.dirname(dir);
  add('protected-spelling', exactProtected.includes(parentDir) ? 'deny' : 'agree',
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

// Every spelling that forces resolution of the final component, generated
// rather than picked. POSIX resolves the last component of `link/`, `link/.`
// and `link/..`, and each of those can be written several ways -- the four
// spellings this group used to carry by hand were four members of a set with
// many more, and adding one by hand later reads as a new finding instead of the
// same one. The rows added above keep their stronger expectations: `add()` keeps
// the first row for a spelling, so the anti-tautology 'allow' rows are not
// weakened into 'agree' by being regenerated here.
// 每一種會強制解析最後一段的拼寫，用生成的而不是挑的。`link/`、`link/.`、`link/..`
// 各自都有好幾種寫法，原本手寫的那四條只是其中四個成員，之後有人手動補一條就會被
// 讀成新發現。上面已加的列保留較強的期望值：add() 對同一拼寫只留第一列。
const FORCED_RESOLUTION_SUFFIXES = ['/', '//', '/.', '/./', '/..', '/../', '/.././'];
let forcedResolutionRowCount = 0;
for (const link of [LINK_TO_PROTECTED, LINK_TO_ITEM_INSIDE, LINK_DANGLING, LINK_TO_GIT_DIR]) {
  for (const suffix of FORCED_RESOLUTION_SUFFIXES) {
    const before = corpus.length;
    add('symlink', 'agree', `${link}${suffix}`, 'forces resolution of the final component');
    if (corpus.length !== before) forcedResolutionRowCount += 1;
  }
}
require_(forcedResolutionRowCount > 0, 'the forced-resolution generator produced no corpus rows');

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

// -- PROTECTED_PATTERNS ----------------------------------------------------
// better-rm's third list, driven for the first time. The four .git entries the
// list happens to hold today are covered by the hook's own two .git rules, so
// these rows agree -- which is the point: they agree because the hook has that
// rule, not because nobody looked. Add `.svn` to PROTECTED_PATTERNS and the rows
// below turn red immediately, where before this generator existed all three
// suites stayed green.
// A pattern is a bash glob, so it has to be turned into a concrete name before
// it can be a path. Each wildcard is instantiated with a literal token, and the
// result is required to be free of glob characters: an entry this generator
// cannot instantiate must stop the run rather than quietly produce nothing.
// The two shapes a pattern can take are read off the pattern itself:
//   `X`, `*/X`  -- a path that ENDS at X is protected      -> endsAt
//   `*/X/*`     -- a path INSIDE X is protected            -> inside
// so a pattern that only protects the inside does not get its "ends at" row
// asserted into a refusal better-rm never makes, and vice versa.
// better-rm 第三份清單，第一次真的被驅動。今天清單裡那四條 .git 剛好被 hook 自己的
// 兩條 .git 規則涵蓋，所以這幾列會一致——重點正在於此：一致是因為 hook 有那條規則，
// 不是因為沒人看。把 `.svn` 加進 PROTECTED_PATTERNS，下面這些列立刻變紅。
// pattern 是 bash glob，得先實例化成具體名字；實例化後若還留著萬用字元就中止，不允許
// 靜靜地生不出東西。pattern 的兩種形狀直接從它自己讀出來，避免替某一邊憑空造出期望。
function instantiateGlob(pattern) {
  return pattern
    .replace(/\[!?([^\]])[^\]]*\]/g, '$1')
    .replace(/\*/g, 'wildcard')
    .replace(/\?/g, 'w');
}

const patternCores = new Map();
for (const raw of cliProtectedPatterns) {
  let pattern = raw.replace(/\/+$/, '');
  const inside = /\/\*$/.test(pattern);
  if (inside) pattern = pattern.replace(/\/\*$/, '');
  if (pattern.startsWith('*/')) pattern = pattern.slice(2);
  const literal = !/[*?[\]{}]/.test(pattern);
  const core = instantiateGlob(pattern);
  require_(core.length > 0, `PROTECTED_PATTERNS entry instantiated to nothing: ${raw}`);
  require_(!/[*?[\]{}]/.test(core),
    `PROTECTED_PATTERNS entry kept a wildcard after instantiation: ${raw} -> ${core}`);
  require_(!core.startsWith('-') && !core.startsWith('/'),
    `PROTECTED_PATTERNS entry instantiated to something rm would not read as a target: ${raw} -> ${core}`);
  const state = patternCores.get(core)
    || { core, endsAt: false, inside: false, literal: true, sources: [] };
  if (inside) state.inside = true; else state.endsAt = true;
  state.literal = state.literal && literal;
  state.sources.push(raw);
  patternCores.set(core, state);
}

let patternRowCount = 0;
function addPattern(expect, spelling, note) {
  const before = corpus.length;
  add('protected-pattern', expect, spelling, note);
  if (corpus.length !== before) patternRowCount += 1;
}

for (const { core, endsAt, inside, literal } of patternCores.values()) {
  const at = path.join(PATTERN_FIXTURE, core);
  const endsAtExpect = endsAt ? 'deny' : 'agree';
  addPattern(endsAtExpect, at, 'a path that ends at the pattern');
  addPattern(endsAtExpect, `${at}/`, 'the same, with a trailing slash');
  addPattern(endsAtExpect, path.join(PATTERN_FIXTURE_RELATIVE, core), 'relative to the sandbox');
  addPattern(endsAtExpect, path.join(PATTERN_FIXTURE, PATTERN_FIXTURE_NESTED, core),
    'the pattern is a name, not a depth');
  addPattern(inside ? 'deny' : 'agree', path.join(PATTERN_FIXTURE, core, 'inside-item'),
    'a path inside the pattern');
  // Negative controls: the pattern has to match a whole component. Asserted as
  // 'allow' only when the pattern carries no wildcard of its own -- a pattern
  // such as `.git*` really would match `.gitignore`, and demanding a refusal or
  // a permission there would be this harness inventing the answer.
  // 負對照：pattern 必須整段元件對齊。只有在 pattern 本身不含萬用字元時才敢斷言
  // 'allow'，否則像 `.git*` 這種本來就會吃到 `.gitignore`。
  const negative = literal ? 'allow' : 'agree';
  addPattern(negative, path.join(PATTERN_FIXTURE, `${core}ignore`),
    'a component that merely starts with the pattern');
  addPattern(negative, path.join(PATTERN_FIXTURE, `vendor${core}`),
    'a component that merely ends with the pattern');
}

// The blindness this generator exists to remove was exactly "extracted, asserted
// non-empty, never used". Zero rows here has to be as loud as a failed
// extraction, or the next round inherits the same green.
// 這個生成器要消滅的盲點就是「抽出來、斷言非空、然後沒用」。零列必須跟抽取失敗一樣大聲。
require_(patternRowCount > 0, 'PROTECTED_PATTERNS produced no corpus rows');
for (const raw of cliProtectedPatterns) {
  require_([...patternCores.values()].some((state) => state.sources.includes(raw)),
    `the corpus generator dropped a protected pattern: ${raw}`);
}

// -- case-folded spellings -------------------------------------------------
// macOS formats its boot volume case-INsensitive by default: measured with
// stat -f '%d:%i', /Users and /USERS are one device and one inode, and BSD
// `readlink -f /USERS` prints /Users. better-rm resolves, so it refuses; the
// hook compares strings, so it permits -- one object, two answers, on the path
// where the hook is the only guard. Nothing about that is hypothetical and
// nothing about it needs a symlink.
// The expectation is MEASURED per row rather than assumed from the platform. On
// a case-sensitive filesystem `/USERS` is a different (usually absent) path and
// permitting it is correct, so the same generated row is an anti-tautology
// control there instead of a refusal. That keeps the corpus identical on both
// platforms and still says the true thing on each.
// macOS 開機卷宗預設不分大小寫：/Users 與 /USERS 同 device 同 inode，readlink -f
// 會把 /USERS 印成 /Users。better-rm 解析所以拒絕，hook 比字串所以放行——同一個物件
// 兩個答案，而且發生在只有 hook 在守的那條路徑上。期望值逐列量測而不是照平台猜：在
// 分大小寫的檔案系統上 /USERS 是另一條（通常不存在的）路徑，放行才是對的，同一列在
// 那裡就變成反恆真對照。語料在兩個平台完全相同，而每個平台上說的都是真話。
const CASE_VARIANTS = [
  ['upper', (value) => value.toUpperCase()],
  ['lower', (value) => value.toLowerCase()],
  ['mixed', (value) => [...value].map((ch, index) => (index % 2 ? ch.toLowerCase() : ch.toUpperCase())).join('')],
];
// Both spellings of every protected entry, not just the root one. A case fold
// and a firmlink prefix compose: measured, /SYSTEM/VOLUMES/DATA/Users is device
// 16777229 inode 17205, the same object as /Users, and better-rm refuses it
// (readlink -f case-canonicalises, then the prefix rewrite fires) while the hook
// permits it -- its prefix comparison is case-sensitive, so the rewrite never
// runs and the folded spelling is compared against nothing. Folding only the
// root spellings would have found /USERS and stopped one composition short of a
// second, separate hole: making the hook's exact-directory comparison
// case-insensitive fixes /USERS and does NOT fix this one.
// 兩種拼寫都要折：大小寫與 firmlink 前綴會疊加。實測 /SYSTEM/VOLUMES/DATA/Users 與
// /Users 同 device 同 inode，better-rm 拒絕（readlink -f 會正規化大小寫，接著前綴改寫
// 生效），hook 放行（它的前綴比對分大小寫，改寫根本沒跑）。只折根拼寫會找到 /USERS
// 就停在離第二個獨立缺口一步之遙的地方：把 hook 的完全比對改成不分大小寫能修好
// /USERS，修不好這一條。
const caseBases = [...new Set([
  ...exactProtected,
  FIRMLINK_PREFIX,
  ...protectedDirs.filter((dir) => dir !== '/').map((dir) => `${FIRMLINK_PREFIX}${dir}`),
])].sort();

let caseRowCount = 0;
const caseVariantsProduced = new Map(CASE_VARIANTS.map(([label]) => [label, 0]));
for (const base of caseBases) {
  let produced = 0;
  for (const [label, transform] of CASE_VARIANTS) {
    const variant = transform(base);
    // Unchanged is legitimate for ONE transform on ONE base: lower-casing
    // '/bin' returns '/bin'. It is not legitimate for a transform across the
    // whole list, which is checked below -- a fold that quietly became the
    // identity function would leave a corpus that still has a 'case' group,
    // still generates rows, and tests nothing.
    // 單一 base 上某個變換沒變是合理的（小寫 '/bin' 還是 '/bin'）；整份清單上都沒變
    // 就不合理，那代表變換退化成恆等函式，語料還有 case 這一組、還在生成列，卻什麼
    // 都沒測到。
    if (variant === base) continue;
    // A fold that changes the LENGTH has produced a different name, not another
    // spelling of the same one (German ß upper-cases to SS), and no filesystem
    // aliases the two. Generating it would add a row about nothing.
    // 改變長度的折疊產生的是另一個名字（ß -> SS），沒有檔案系統會把兩者當同一個。
    if (variant.length !== base.length) continue;
    const alias = sameObject(base, variant);
    const before = corpus.length;
    add('case', alias ? 'deny' : 'allow', variant,
      `${label}-case spelling of ${base}, measured ${alias ? 'the same object' : 'not the same object'}`);
    if (corpus.length !== before) {
      caseRowCount += 1;
      produced += 1;
      caseVariantsProduced.set(label, caseVariantsProduced.get(label) + 1);
    }
  }
  require_(produced > 0 || !/[a-z]/i.test(base),
    `the case-variant generator produced nothing for a base that has letters: ${base}`);
}
require_(caseRowCount > 0, 'the case-variant generator produced no corpus rows');
for (const [label, count] of caseVariantsProduced) {
  require_(count > 0,
    `the case-variant generator's ${label} transform returned its base every time: it is the identity function`);
}
// Nothing generated here may be a protected entry in its own right. A row that
// coincides with its base -- or with another entry on the list -- is not a
// case-folded spelling of a protected directory, it IS a protected directory,
// and it would pass by testing the thing the corpus already covers.
// 這裡生成的列都不得本身就是清單上的項目：與 base（或清單上另一項）相同的列不是
// 「受保護目錄的大小寫拼寫」，它就是受保護目錄本身，會靠著測已經涵蓋的東西而通過。
for (const row of corpus) {
  if (row.group !== 'case') continue;
  require_(!exactProtected.includes(row.spelling),
    `the case-variant generator produced a row identical to a protected entry: ${row.spelling}`);
}
// Every row generated from a MEASURED aliasing fact carries a verdict, never
// 'agree'. That is not a stylistic detail: section 3b's cross-layer classes may
// only claim 'agree' rows, so this is the structural reason no class -- however
// its predicate is later widened -- can answer a case or Unicode row with "these
// two cannot be consistent". Asserted rather than left to the generators'
// good behaviour, because the next person to touch them will not read this.
// 凡是由「量測到的別名事實」生成的列都帶著判定，不會是 'agree'。這不是風格問題：
// 3b 的跨層類只能認領 'agree' 的列，所以這正是「不論判準日後怎麼放寬，都碰不到大小寫
// 與 Unicode 那兩組」的結構性理由。用斷言寫死，不靠生成器自律。
for (const row of corpus) {
  if (row.group !== 'case' && row.group !== 'unicode') continue;
  require_(row.expect !== 'agree',
    `a measured aliasing row must carry a verdict, or a cross-layer class could claim it: ${row.group} ${row.spelling}`);
}

// -- Unicode normalisation spellings ---------------------------------------
// Both encodings of every declared Unicode fixture. Which one is the declared
// spelling is varied across the fixtures so the rows cannot pass by privileging
// NFC, the form a JavaScript source file produces by default.
// 兩種編碼都生成；哪一種是「宣告的那個」在兩個 fixture 間交換，避免因為偏好 NFC
// （JS 原始碼預設產生的形式）而矇混過關。
let unicodeRowCount = 0;
for (const { label, leaf, directory } of UNICODE_DECLARED) {
  add('unicode', 'deny', directory, `declared in BETTER_RM_PROTECTED_DIRS, spelled ${label}`);
  add('unicode', 'allow', path.join(directory, 'inside-item'),
    'inside a declared directory is ordinary work');
  unicodeRowCount += 2;
  for (const other of ['NFC', 'NFD']) {
    const spelling = path.join(sandbox, leaf.normalize(other));
    if (spelling === directory) continue;
    const alias = sameObject(directory, spelling);
    add('unicode', alias ? 'deny' : 'allow', spelling,
      `${other} spelling of a directory declared ${label}, measured ${alias ? 'the same object' : 'not the same object'}`);
    add('unicode', 'allow', path.join(spelling, 'inside-item'),
      `inside the ${other} spelling`);
    unicodeRowCount += 2;
  }
}
require_(unicodeRowCount > 0, 'the Unicode generator produced no corpus rows');
// Both encodings, for every fixture. Generating only the declared one would
// leave a group named 'unicode' that never asks the question.
// 每個 fixture 兩種編碼都要有：只生成宣告的那一種，等於留下一組叫 unicode 卻從不
// 提問的列。
for (const { label, leaf } of UNICODE_DECLARED) {
  for (const encoding of ['NFC', 'NFD']) {
    require_(corpus.some((row) => row.group === 'unicode'
      && row.spelling === path.join(sandbox, leaf.normalize(encoding))),
    `the Unicode generator produced no ${encoding} row for the fixture declared ${label}`);
  }
}

// -- BETTER_RM_PROTECTED_DIRS ----------------------------------------------
// The hook reads this environment variable and adds its entries to the exact
// list. It is the only interface a user has for adding protection of their own,
// so both guards have to parse it the same way or a declared directory is
// protected on one path and not the other.
// The value carries every parse at once: absolute entries, an EMPTY entry, and
// a relative entry resolved against the working directory. The empty entry is
// the dangerous one -- resolving "" lands on the working directory, so one
// trailing colon would make the user's own project undeletable, which is why the
// sandbox itself is an 'allow' row below.
// hook 會讀這個環境變數並加進清單；這是使用者唯一能自己加保護的介面，兩邊的解析
// 必須一致。值裡一次帶齊所有解析：絕對項、空項、相對項。空項最危險：""會解析成
// 當前目錄，一個結尾冒號就讓使用者的專案變成刪不掉的。
// Every declared absolute entry gets the same treatment rather than only the
// first: HOME's parent and the two Unicode fixtures are declared through the
// very same variable, and a parse that handled entry 1 and dropped entry 4 would
// otherwise be invisible.
// 每一個宣告的絕對項都同等對待，不是只驗第一項：HOME 的父目錄與兩個 Unicode
// fixture 走的是同一個變數，只處理第一項的解析錯誤原本看不見。
for (const entry of EXTRA_PROTECTED_ABSOLUTE) {
  add('extra-dirs', 'agree', entry, 'BETTER_RM_PROTECTED_DIRS entry');
  add('extra-dirs', 'agree', `${entry}/`);
  add('extra-dirs', 'allow', `${entry}/inside-item`);
}
add('extra-dirs', 'agree', EXTRA_PROTECTED_RELATIVE, 'a relative entry, spelled as declared');
add('extra-dirs', 'agree', path.join(sandbox, EXTRA_PROTECTED_RELATIVE),
  'the same relative entry, resolved against the working directory');
add('extra-dirs', 'allow', path.join(sandbox, EXTRA_PROTECTED_RELATIVE, 'inside-item'));
add('extra-dirs', 'allow', sandbox, 'the empty entry must not protect the working directory');
add('extra-dirs', 'allow', path.join(sandbox, 'not-declared'));

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
for (const { core } of patternCores.values()) {
  require_(corpus.some((row) => row.group === 'protected-pattern'
    && row.spelling === path.join(PATTERN_FIXTURE, core)),
  `the corpus generator dropped a protected pattern: ${core}`);
}
// HOME has to be a directory that really exists, or the resolving half of
// is_protected() is switched off for every spelling under it and the case and
// normalisation classes cannot appear at all -- which is precisely how they
// stayed invisible while this file reported green.
// HOME 必須是真的存在的目錄，否則 is_protected 的解析那一支對 HOME 底下每一種拼寫
// 都不會執行，大小寫與正規化兩類差異根本進不了語料。
require_(fs.existsSync(HOME) && fs.statSync(HOME).isDirectory(),
  `HOME must be an existing directory for the resolving half of is_protected to run: ${HOME}`);
require_(corpus.length > 0, 'the corpus is empty');

// A group that stops being generated takes its whole class of differences with
// it and leaves a smaller, quieter, still-green corpus. Named rather than
// counted: a count is satisfied by any nine groups, including nine copies of
// the easy ones.
// 一整組不再生成，就會帶走一整類差異，留下一份更小、更安靜、依然全綠的語料。用名字
// 而不是數量：數量隨便九組都能滿足。
const groups = [...new Set(corpus.map((row) => row.group))];
for (const required of ['protected-spelling', 'inside-protected', 'mount-root', 'mount-inside',
  'firmlink', 'symlink', 'git', 'protected-pattern', 'case', 'unicode', 'extra-dirs',
  'shell-layer', 'ordinary']) {
  require_(groups.includes(required), `the corpus lost the ${required} group (${groups.join(', ')})`);
}

// ---------------------------------------------------------------------------
// 3b. Differences that belong to the two guards' different positions
//     兩道守衛所處位置不同而必然存在的差異
// ---------------------------------------------------------------------------
// A handful of spellings cannot be made to agree by fixing either guard, because
// the two do not observe the same thing. Deleting the row would make the suite
// green by making it blind; leaving the row undeclared would make the suite
// permanently red and train everyone to ignore it. So the differences are
// declared here, and the declarations are checked in BOTH directions: an
// undeclared divergence still fails, and a declared difference that has
// converged (or flipped) fails too, so this cannot quietly rot into a
// suppression file. A row the corpus requires both guards to deny or to allow
// can never be declared here at all.
//
// A declaration is a CLASS with a predicate, not a list of spellings. It used to
// be a list, and the list was wrong in the way lists are: it named
// `link-to-usr/`, `link-to-usr/.`, `link-to-usr/..` and `link-to-git-dir/`, and
// a reviewer who added `link-to-usr//`, `link-to-usr/./`, `link-to-usr/../` and
// four more spellings of the identical situation got seven NEW work items for a
// difference that had already been examined and accepted. A class absorbs its
// own new members; a list turns every one of them into a false alarm, and false
// alarms are how a red suite gets ignored.
//
// Where the line is drawn, and why a class cannot swallow a genuine hole:
//   * A class is only allowed to answer a row the corpus has no opinion about
//     ('agree'). A 'deny' row is the protection itself and an 'allow' row is the
//     anti-tautology half; neither can be answered with "these two cannot be
//     consistent". Every case and Unicode row generated above carries a MEASURED
//     'deny' or 'allow', so no class can reach them however its predicate is
//     later widened.
//   * The predicate has to name the MECHANISM, not the direction. For the
//     agent-path holes (hook ALLOW, better-rm DENY -- the dangerous direction)
//     the mechanism is "resolution walked through a symlink component, and the
//     hook would have refused the resolved path if it could have seen it". The
//     test for that is positive on all four counts: an argument that is not
//     itself a link, a strict prefix that IS a link, a resolved path the hook's
//     own predicate calls protected, and a lexical path it does not. Two
//     spellings that name one object WITHOUT a symlink -- a case fold, a
//     different Unicode normalisation, a firmlink prefix -- are explicitly
//     excluded, because the hook can close those with a string operation and
//     therefore they are holes, not layering.
//   * The other direction (hook DENY, better-rm ALLOW) is the hook refusing more
//     than argv can carry. Its class can only ever absorb an OVER-refusal, which
//     cannot open a hole in either guard; that is why its predicate is allowed to
//     be the broader of the two.
// 宣告的是「類」＋判準，不是拼寫清單。原本是清單，而清單錯在清單會犯的錯：它列了四
// 條 link 拼寫，於是有人補上 `link-to-usr//`、`link-to-usr/./` 等七條完全相同情形的
// 拼寫時，得到的是七個新工作項目——一個已經審視並接受過的差異。類會自己吸收新成員；
// 清單則把每一個新成員變成假警報，而假警報正是紅燈被無視的原因。
// 界線在哪：(1) 類只能回答語料沒有主張的列（'agree'）；大小寫與 Unicode 那兩組每一
// 列都帶著量測出來的 deny/allow，任何判準都碰不到。(2) 判準寫的是機制不是方向：
// agent 路徑上的洞（hook 放行、better-rm 拒絕）機制是「解析穿過了一個 symlink 元件，
// 而 hook 若看得見解析後的路徑就會拒絕」，四項條件全為正面條件；兩種拼寫指向同一物件
// 但沒有 symlink 參與（大小寫、Unicode 正規化、firmlink 前綴）明確排除，因為那幾種
// hook 用字串運算就能補起來，所以是洞不是分層。(3) 反方向是 hook 比 argv 能承載的更
// 嚴格，最多只能吸收「過度拒絕」，不會開洞，所以判準可以寬一點。
const crossLayerClasses = [];

function declareCrossLayerClass({ name, hook: hookVerdictDeclared, cli: cliVerdictDeclared, why, mechanism }) {
  require_(typeof name === 'string' && name.length > 0, 'a cross-layer class carries no name');
  require_(typeof why === 'string' && why.length > 0, `a cross-layer class carries no reason: ${name}`);
  require_(typeof mechanism === 'function', `a cross-layer class carries no mechanism: ${name}`);
  require_(hookVerdictDeclared !== cliVerdictDeclared,
    `a cross-layer class declares agreement, which is not a difference: ${name}`);
  require_(!crossLayerClasses.some((item) => item.name === name),
    `a cross-layer class is declared twice: ${name}`);
  crossLayerClasses.push({ name, hook: hookVerdictDeclared, cli: cliVerdictDeclared, why, mechanism });
}

// The two views a spelling has: what the hook compares (lexical, filesystem-free)
// and what the filesystem says it is. Both asked through the hook's OWN exported
// predicate, so the classification cannot drift from the guard it describes.
// 一條拼寫的兩種視角：hook 拿來比對的（純字面）與檔案系統認定的。都透過 hook 自己
// 匯出的判斷式來問，分類才不會跟它描述的守衛脫節。
const lexicalTarget = (spelling) => hook.normalizedTarget(spelling, sandbox, HOME);
const hookRefuses = (spelling) => hook.protectedReason(spelling, sandbox, HOME, hookExtraDirs) !== null;
const absoluteSpelling = (spelling) => (path.isAbsolute(spelling) ? spelling : path.join(sandbox, spelling));
// NFC + lower-case: the two ways one object can wear two spellings without a
// symlink. Folding them together is how the symlink class refuses to claim them.
// NFC ＋小寫：同一物件在沒有 symlink 的情況下能有兩種拼寫的兩種方式；把它們折疊在
// 一起，正是 symlink 那一類拒絕認領它們的方法。
const foldSpelling = (value) => value.normalize('NFC').toLowerCase();

// Walked over the spelling AS WRITTEN, not over its lexical resolution:
// `link/..` collapses lexically to a path with no link in it at all, and the
// only place the symlink is still visible is the spelling.
// 走的是「原樣拼寫」而不是字面解析後的路徑：`link/..` 字面收斂後裡面一條連結都沒有。
// What a resolver that FOLLOWS links sees, which is what better-rm is looking at
// when it calls readlink -f. Node's own fs.realpathSync cannot be used for this:
// it lexically collapses '..' before it resolves anything, so it reports
// realpathSync('<sandbox>/link-to-usr/..') as the sandbox, while `readlink -f`
// on the same spelling prints '/' -- the parent of the link's TARGET. Getting
// that wrong does not make the class too broad, it makes it too narrow: the
// `link/..` row would be reported as a brand new hole on every run.
// 這是「會跟著連結走」的解析器看到的東西，也就是 better-rm 呼叫 readlink -f 時看到
// 的。不能用 Node 的 fs.realpathSync：它會先字面收斂 '..' 再解析，於是把
// '<sandbox>/link-to-usr/..' 說成 sandbox，而 readlink -f 印的是 '/'（連結目標的父
// 目錄）。搞錯的後果不是類太寬而是太窄：那一列每次執行都會被當成全新的洞。
function resolveFollowingLinks(absolute) {
  let current = '/';
  for (const part of absolute.split('/')) {
    if (part === '' || part === '.') continue;
    if (part === '..') {
      current = path.dirname(current);
      continue;
    }
    current = path.join(current, part);
    for (let hops = 0; hops < 40; hops += 1) {
      let entry;
      try {
        entry = fs.lstatSync(current);
      } catch (_) {
        return null;
      }
      if (!entry.isSymbolicLink()) break;
      const target = fs.readlinkSync(current);
      current = path.isAbsolute(target) ? target : path.resolve(path.dirname(current), target);
    }
  }
  return current;
}

function someStrictPrefixIsSymlink(absolute) {
  const parts = absolute.split('/');
  let prefix = '';
  for (let index = 1; index < parts.length - 1; index += 1) {
    prefix += `/${parts[index]}`;
    try {
      if (fs.lstatSync(prefix).isSymbolicLink()) return true;
    } catch (_) {
      return false;
    }
  }
  return false;
}

// -- the hook reads command text, better-rm reads argv ---------------------
// The hook is handed the command BEFORE the shell expands it, and it cannot know
// what the expansion will produce -- not even for HOME, which the same command can
// override (`HOME=/ rm "$HOME/etc"`). It therefore reads `~`, `$HOME` and `${HOME}`
// as the home directory and refuses. better-rm is handed argv AFTER expansion: if
// the shell expanded them it never sees these spellings at all, and if it did not
// (they were quoted), they are ordinary filenames -- a file literally named `~`,
// or `*` left behind when a glob matched nothing. Refusing those would be a false
// positive at better-rm's layer, and reading them literally would be a hole at the
// hook's. Both sides are right where they stand; there is no third answer, and
// weakening the hook to reach agreement would be a regression.
// hook 看到的是展開前的命令文字，連 HOME 都可能被同一條命令覆寫，所以只能失敗關閉；
// better-rm 收到的是展開後的 argv，那裡的 `~`、`*` 就只是普通檔名。兩邊在各自的層
// 都是對的，為了一致而放寬 hook 會是退化。
declareCrossLayerClass({
  name: 'the hook reads command text, better-rm reads argv',
  hook: 'DENY',
  cli: 'ALLOW',
  why: 'the hook read the operand as something other than the literal filename argv carries',
  // Two shapes, both meaning "the hook did not read this as a filename": it
  // resolved the text to a DIFFERENT path than the literal one (~, $HOME,
  // ${HOME}, and a trailing backslash, which the hook strips as a separator), or
  // it refused the text as a pattern that could select .git without being able
  // to expand it. Neither can hide a hole: the direction is the hook refusing
  // MORE than better-rm.
  // 兩種形狀都代表「hook 沒把它讀成檔名」：把文字解析成與字面不同的路徑，或當成可能
  // 選中 .git 的樣式而拒絕。方向是 hook 比 better-rm 更嚴，藏不住洞。
  mechanism(row) {
    if (!hookRefuses(row.spelling)) return false;
    const asHookReadsIt = lexicalTarget(row.spelling);
    return asHookReadsIt !== path.resolve(sandbox, row.spelling)
      || hook.globCanMatchGit(asHookReadsIt);
  },
});

// -- the hook never touches the filesystem, better-rm must ------------------
// A trailing slash (and `/.`, and `/..`) forces resolution of the final component,
// so `link/` reaches the TARGET: measured, `rm -rf link/` returns 0, destroys the
// target's contents and leaves the link behind. better-rm sees that -- it has to,
// because its own move would follow the link -- and refuses. The hook resolves the
// path lexically and cannot see it.
// It stays that way on purpose. The hook runs as a PreToolUse gate on EVERY agent
// command; a stat that blocks blocks the agent itself, and this machine mounts a
// cloud filesystem that has hard-deadlocked on exactly that kind of access. The
// alternative -- refusing every trailing-slash argument -- would refuse
// `rm -rf build/`, which is ordinary work, and the brief is explicit that ordinary
// directory removals must keep working. So the hook accepts that it cannot see a
// symlink, and the residual gap (`rm -rf ~/applink/` on the agent path) is recorded
// as an open item rather than papered over.
// 結尾斜線會強制解析最後一段，所以 `link/` 碰到的是 target；better-rm 看得見（它自己
// 的搬移也會跟過去）因此拒絕，hook 只做字面解析看不見。這是刻意的：hook 是每一次
// agent 命令都會經過的閘門，一次會阻塞的 stat 就會卡住整個 agent，而這台機器上就掛著
// 一個曾經因為這種存取而硬死鎖的雲端檔案系統；而「一律拒絕結尾斜線」會連 `rm -rf
// build/` 都擋掉。殘留的缺口列為待辦，不是假裝不存在。
declareCrossLayerClass({
  name: 'the hook cannot stat, better-rm must',
  hook: 'ALLOW',
  cli: 'DENY',
  why: 'resolution walked through a symlink component onto a path the hook would refuse if it could see it',
  mechanism(row) {
    const absolute = absoluteSpelling(row.spelling);
    let itself;
    try {
      itself = fs.lstatSync(absolute);
    } catch (_) {
      // Nothing to resolve: a dangling link, a glob, a path that is not there.
      // 沒有東西可解析：斷連結、萬用字元、不存在的路徑。
      return false;
    }
    // better-rm deliberately does NOT resolve an argument that is itself a link,
    // so a bare link cannot be in this class -- and the corpus proves it agrees.
    // better-rm 刻意不解析「引數自己就是連結」，所以裸連結不屬於這一類。
    if (itself.isSymbolicLink()) return false;
    if (!someStrictPrefixIsSymlink(absolute)) return false;
    const resolved = resolveFollowingLinks(absolute);
    if (resolved === null) return false;
    const lexical = lexicalTarget(row.spelling);
    if (resolved === lexical) return false;
    // One object under two spellings with no symlink in the way -- a case fold
    // or a different Unicode normalisation. The hook can close those with a
    // string operation, so they are holes and stay red.
    // 同一物件的兩種拼寫、路上沒有 symlink——大小寫或 Unicode 正規化。hook 用字串
    // 運算就能補，所以那是洞，必須維持紅燈。
    if (foldSpelling(resolved) === foldSpelling(lexical)) return false;
    // The hook has to be right about the resolved path and wrong only because it
    // could not reach it. If it would refuse the lexical path too, the row is not
    // about resolution; if it would permit the resolved path, better-rm's refusal
    // is a difference of POLICY and belongs in the report, not in a class.
    // hook 必須「對解析後的路徑判斷正確、只是搆不到」。字面路徑它也拒絕，那這一列
    // 就不是解析造成的；解析後的路徑它會放行，那 better-rm 的拒絕是政策差異。
    if (hookRefuses(lexical)) return false;
    return hookRefuses(resolved);
  },
});

// ---------------------------------------------------------------------------
// 4. Hook verdicts, through the exported evaluate()
//    hook 端判定：走它匯出的 evaluate()
// ---------------------------------------------------------------------------
// hookEnv and hookExtraDirs are defined in section 2, beside the value both
// guards are handed: section 3b's class predicates ask the hook's own predicate
// with exactly these arguments, and one definition is the only way they cannot
// drift from what section 4 measures.
// hookEnv 與 hookExtraDirs 定義在第 2 節：3b 的分類判準用同一組參數呼叫 hook 自己的
// 判斷式，只有單一定義才不會與第 4 節量到的東西脫節。
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
      BETTER_RM_PROTECTED_DIRS: EXTRA_PROTECTED_VALUE,
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
// nothing about a row depends on its spelling. HOME now lives inside the sandbox
// and is abbreviated with it, which keeps the home firmlink row showing its
// shape (/System/Volumes/Data$SANDBOX/Users/probe-user) instead of hiding it
// behind a second substitution.
// Anything outside printable ASCII is escaped, because the whole point of the
// Unicode rows is a difference a terminal renders identically: café in NFC and
// café in NFD are the same six glyphs and different bytes, and a report that
// printed them raw would show two rows that look like a duplicate.
// 只縮寫 sandbox；HOME 現在住在 sandbox 裡，跟著一起縮寫，firmlink 那一列反而看得出
// 形狀。非可列印 ASCII 一律轉義：Unicode 那組的重點正是終端機看起來一模一樣的差異。
const display = (spelling) => spelling
  .split(sandbox).join('$SANDBOX')
  .replace(/[^\x20-\x7e]/g, (character) => `\\u${character.charCodeAt(0).toString(16).padStart(4, '0')}`);

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

// A divergence counts as answered only if a declared class claims it AND the
// direction matches. The class is asked the other way round too: every row whose
// mechanism the class describes must still diverge in the declared direction, and
// a class that no longer has a single live member is a declaration about nothing.
// Between them those two checks keep a class from becoming a place to hide rows:
// widening a predicate to cover a new row also drags in every row it now matches,
// and any of those that has converged fails the run.
// A class may only ever claim a row the corpus has no opinion about; a 'deny' or
// 'allow' row that diverges is reported however well it fits a mechanism.
// 分歧必須被某個類認領、且方向相符才算已回答。反過來也查：凡是機制符合該類的列都
// 必須仍以宣告的方向分歧，而一個成員都不剩的類就是在宣告一件不存在的事。兩者合起
// 來讓「放寬判準」有代價：它會把所有新符合的列一併拉進來，其中任何已收斂的都會讓
// 這次執行失敗。語料有主張的列（deny／allow）不論多符合機制都照樣回報。
for (const row of corpus) {
  row.crossLayerClass = row.expect === 'agree'
    ? crossLayerClasses.find((cls) => cls.mechanism(row)) || null
    : null;
}
const undeclaredDivergences = divergences.filter((row) => !(row.crossLayerClass
  && row.crossLayerClass.hook === row.hook && row.crossLayerClass.cli === row.cli));
const staleDeclarations = corpus
  .filter((row) => row.crossLayerClass)
  .map((row) => ({ declared: row.crossLayerClass, row }))
  .filter(({ declared, row }) => !(row.hook !== row.cli
    && row.hook === declared.hook && row.cli === declared.cli));
const emptyClasses = crossLayerClasses.filter((cls) => !corpus.some((row) => row.crossLayerClass === cls
  && row.hook === cls.hook && row.cli === cls.cli));

// The corpus header belongs with whichever report is being produced. Splitting
// it across stdout and stderr let the two streams interleave differently on
// different runners, which made two identical results look unequal.
// 標頭跟著該次的報告走：分散在 stdout 與 stderr 會因為 runner 不同而交錯不同，
// 讓兩份相同的結果看起來不一樣。
// The filesystem facts the corpus derived its expectations from are printed with
// the corpus size, because they are what makes two runs on two platforms
// comparable. The same rows are generated everywhere; a case-folded spelling is
// one object here and two objects there, and a reader who cannot see which was
// measured cannot tell a real difference between the runs from a real difference
// between the filesystems.
// 標頭印出語料據以推導期望值的檔案系統事實：兩個平台生成的列完全相同，但大小寫拼寫
// 在這裡是同一個物件、在那裡是兩個，看不到量到的是哪一種就分不清「兩次執行不同」與
// 「兩個檔案系統不同」。
const measuredAliases = (group) => corpus.filter((row) => row.group === group && row.expect === 'deny').length;
const caseAliases = measuredAliases('case');
// One extra line, and it is the most important one in a GREEN log. A run on a
// case-sensitive filesystem generates all of these rows, finds no aliasing, and
// is right to pass -- but "passed" then means "this filesystem cannot exhibit
// the class", not "the two guards agree about case". The repository's CI runs
// ubuntu only; without this line a green CI log is indistinguishable from a run
// that actually checked, and the class would be rediscovered from scratch.
// 綠燈紀錄裡最重要的一行。在分大小寫的檔案系統上，這些列全部生成、量到沒有別名、
// 通過也是對的——但那時「通過」的意思是「這個檔案系統展現不了這一類」，不是「兩道
// 守衛在大小寫上一致」。本 repo 的 CI 只跑 ubuntu；少了這一行，綠燈紀錄與真的檢查過
// 的紀錄長得一模一樣。
const header = [
  `Guard parity corpus / 差分語料：${corpus.length} rows, ${groups.length} groups`,
  `  $SANDBOX = ${sandbox}`,
  `  $HOME    = ${HOME}`,
  `  measured: ${caseAliases} of ${corpus.filter((row) => row.group === 'case').length} case-folded spellings name the same object as their base`,
  `  measured: ${measuredAliases('unicode')} of ${corpus.filter((row) => row.group === 'unicode').length} Unicode rows name a declared directory`,
  ...(caseAliases === 0 ? [
    '  NOTE: this filesystem is case-SENSITIVE, so the case-folded rows below could not exercise',
    '        the class at all. A pass here is not evidence that the two guards agree about case;',
    '        run the suite on a case-insensitive volume (the macOS default) for that.',
    '  注意：本檔案系統分大小寫，大小寫那組列在這次執行中無法展現該類差異；此處通過並不',
    '        代表兩道守衛在大小寫上一致，要驗證請在不分大小寫的卷宗（macOS 預設）上跑。',
  ] : []),
].join('\n');

// The declared differences are printed on the GREEN path too. A difference nobody
// ever reads is one nobody ever revisits, and these are open holes, not settled
// facts: the trailing-slash symlink one is a live gap on the agent path.
// Every member is listed, not just the class: the class explains why they are
// accepted, the members are what is actually open.
// 綠燈時也要把已宣告的差異印出來：沒人看見的差異就沒人會回頭處理，而這幾條是還開著
// 的洞，不是已經結案的事實。連成員一起列出：類說明為什麼被接受，成員才是真的開著的。
function declaredReport() {
  const out = [`已宣告的跨層差異 / Declared cross-layer difference classes: ${crossLayerClasses.length}`];
  for (const cls of crossLayerClasses) {
    const members = corpus.filter((row) => row.crossLayerClass === cls);
    out.push(`  [${cls.name}] hook ${cls.hook} / better-rm ${cls.cli}: ${cls.why}`);
    out.push(table(members, [
      { header: '  path', value: (row) => `  ${display(row.spelling)}` },
      { header: 'group', value: (row) => row.group },
    ]));
  }
  return out.join('\n');
}

if (undeclaredDivergences.length === 0 && staleDeclarations.length === 0
  && emptyClasses.length === 0 && expectationFailures.length === 0) {
  console.log(header);
  console.log(declaredReport());
  const declaredMembers = corpus.filter((row) => row.crossLayerClass).length;
  console.log(`Guard parity 測試通過 / Guard parity checks passed: ${corpus.length * 2 + declaredMembers}`);
  process.exit(0);
}

console.error(header);

if (emptyClasses.length > 0) {
  console.error('');
  console.error(`宣告了一個沒有成員的類 / ${emptyClasses.length} declared cross-layer classes match no divergence at all:`);
  for (const cls of emptyClasses) {
    console.error(`  [${cls.name}] hook ${cls.hook} / better-rm ${cls.cli}: ${cls.why}`);
  }
  console.error('一個成員都沒有的類，要嘛該差異已收斂（刪掉宣告），要嘛生成器不再生成那些拼寫（那是語料的缺口）。');
  console.error('A class with no members means the difference converged (delete the class) or the generator stopped producing those spellings (a hole in the corpus).');
}

if (staleDeclarations.length > 0) {
  console.error('');
  console.error(`宣告與實測不符 / ${staleDeclarations.length} declared cross-layer differences no longer hold:`);
  console.error(table(staleDeclarations, [
    { header: 'class', value: ({ declared }) => declared.name },
    { header: 'declared', value: ({ declared }) => `hook ${declared.hook} / better-rm ${declared.cli}` },
    { header: 'measured', value: ({ row }) => `hook ${row.hook} / better-rm ${row.cli}` },
    { header: 'path', value: ({ row }) => display(row.spelling) },
  ]));
  console.error('已收斂的宣告要刪掉；方向反過來的是新發現，不是宣告過的差異。');
  console.error('A converged declaration must be deleted; a flipped one is a new finding, not a declared difference.');
}

if (undeclaredDivergences.length > 0) {
  console.error('');
  console.error(`兩道守衛判定不一致 / The two guards disagree on ${undeclaredDivergences.length} of ${corpus.length} spellings:`);
  console.error(table(undeclaredDivergences, [
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

// Printed on the RED path as well, after the work list. Someone reading a red
// report has to be able to tell "this row is not here because it was examined
// and accepted" from "this row is not here because nobody generated it" -- and
// the accepted ones are open holes on the agent path, not settled facts.
// 紅燈時也印在工作清單之後：讀報告的人必須能分辨「這一列不在清單上是因為審視過並
// 接受了」與「不在清單上是因為根本沒人生成它」，而被接受的那幾條是還開著的洞。
console.error('');
console.error(declaredReport());

console.error('');
console.error('每一列都是這一輪的工作項目：先決定哪一邊是對的，再讓兩邊一致。');
console.error('Each row is a work item: decide which side is right, then make the two agree.');
process.exit(1);
