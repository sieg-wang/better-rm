#!/usr/bin/env node
// Block coding agents from passing protected directories to destructive shell commands.
// 阻擋 coding agent 將受保護目錄傳給破壞性 shell 命令。

'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');

// Kept in step with better-rm's own PROTECTED_DIRS; test-hooks.js compares the
// two lists directly, because on the agent path this hook is the only guard.
// 與 better-rm 的 PROTECTED_DIRS 保持一致；agent 路徑上只有這支 hook 在守。
// /private/etc and /private/var are what /etc and /var NAME on macOS (measured:
// realpath(/etc) is /private/etc). A protected spelling whose contents live at an
// unprotected path is not protected: removing /private/etc destroys exactly what
// listing /etc is for, and both were allowed on both guards. /private/tmp is
// deliberately NOT here -- that is where scratch work lives.
// /private/etc 與 /private/var 是 macOS 上 /etc 與 /var 真正指到的地方（實測 realpath）。
// 受保護的拼寫如果內容存在一條沒受保護的路徑上，那份保護就是空的。/private/tmp 刻意不
// 加：那是暫存工作的地方。
const SYSTEM_DIRS = [
  '/', '/Applications', '/Library', '/Network', '/System', '/System/Volumes',
  '/Users', '/Volumes',
  '/bin', '/boot', '/cores', '/dev', '/etc', '/home', '/lib', '/lib64', '/mnt',
  '/opt', '/private', '/private/etc', '/private/var', '/proc', '/root', '/sbin',
  '/sys', '/usr', '/var',
];

// The directories whose first level is a mount root rather than an ordinary
// directory, as better-rm's own is_protected loops over them.
// 第一層是掛載根而非普通目錄的父目錄，與 better-rm 的 is_protected 迴圈一致。
// /System/Volumes is where a modern Mac mounts its own APFS volumes (Data,
// Preboot, VM, Update, ...), so its first level is a mount root exactly as
// /Volumes' and /mnt's are. Kept identical to better-rm's mount-parent loop --
// the drift guard in the suite compares the two.
// /System/Volumes 是現代 Mac 掛載自己那幾顆 APFS 卷宗的地方，第一層同樣是掛載根。
const MOUNT_PARENTS = ['/mnt', '/Volumes', '/System/Volumes'];

// The macOS data volume, whose contents appear a second time at the root.
// Kept identical to better-rm's firmlink_prefix, which carries the long-form
// reasoning; test-hooks.js reads that one and drives this rule with it.
// macOS 資料卷宗的掛載點，其內容會在根目錄再出現一次。與 better-rm 的
// firmlink_prefix 保持一致（完整理由寫在那裡）。
const FIRMLINK_PREFIX = '/System/Volumes/Data';

function decodeAnsiCEscape(input, slashIndex) {
  const escape = input[slashIndex + 1];
  if (escape === undefined) return { value: '\\', end: slashIndex };

  const simple = {
    '\\': '\\',
    "'": "'",
    '"': '"',
    '?': '?',
    a: '\x07',
    b: '\b',
    e: '\x1b',
    E: '\x1b',
    f: '\f',
    n: '\n',
    r: '\r',
    t: '\t',
    v: '\v',
  };
  if (Object.prototype.hasOwnProperty.call(simple, escape)) {
    return { value: simple[escape], end: slashIndex + 1 };
  }
  if (escape === '\n') return { value: '', end: slashIndex + 1 };

  if (/[0-7]/.test(escape)) {
    let end = slashIndex + 1;
    while (
      end + 1 < input.length
      && end - slashIndex < 3
      && /[0-7]/.test(input[end + 1])
    ) end += 1;
    return {
      value: String.fromCodePoint(Number.parseInt(input.slice(slashIndex + 1, end + 1), 8)),
      end,
    };
  }

  const hexLimits = { x: 2, u: 4, U: 8 };
  if (Object.prototype.hasOwnProperty.call(hexLimits, escape)) {
    let end = slashIndex + 1;
    while (
      end + 1 < input.length
      && end - (slashIndex + 1) < hexLimits[escape]
      && /[0-9A-Fa-f]/.test(input[end + 1])
    ) end += 1;
    if (end === slashIndex + 1) {
      return { value: `\\${escape}`, end };
    }
    const digits = input.slice(slashIndex + 2, end + 1);
    const codePoint = Number.parseInt(digits, 16);
    if (codePoint <= 0x10FFFF && !(codePoint >= 0xD800 && codePoint <= 0xDFFF)) {
      return { value: String.fromCodePoint(codePoint), end };
    }
    return { value: input.slice(slashIndex, end + 1), end };
  }

  if (escape === 'c' && input[slashIndex + 2] !== undefined) {
    const control = input[slashIndex + 2];
    const codePoint = control === '?' ? 0x7F : control.toUpperCase().codePointAt(0) & 0x1F;
    return { value: String.fromCodePoint(codePoint), end: slashIndex + 2 };
  }

  // Bash preserves the backslash for escape sequences it does not recognize.
  return { value: `\\${escape}`, end: slashIndex + 1 };
}

// Read a heredoc's delimiter, starting just past the '<<' (or '<<-') operator.
// The delimiter can be quoted or backslash-escaped, and the quoting is what tells
// the SHELL whether to expand the body -- it is not our business here, we only
// need the text that ends the body.
// 讀 heredoc 的結束標記。標記可以被引號或反斜線包住，那個引號決定 shell 會不會展開內文
// ——這裡不管展開，只需要「什麼字串會結束這段內文」。
function heredocDelimiter(input, start) {
  let index = start;
  while (index < input.length && (input[index] === ' ' || input[index] === '\t')) index += 1;
  let delimiter = '';
  let quote = '';
  // Any quoting at all on the delimiter makes the body LITERAL: no parameter
  // expansion, no command substitution. That is the shell's own switch for
  // whether the body can execute anything, so it decides whether this guard
  // reads the body as text or as something with commands hiding in it.
  // 結束標記只要帶引號，內文就是字面的：不做參數展開、也不做命令替換。這是 shell 自己
  // 用來決定「這段內文能不能執行東西」的開關，所以也由它決定守衛要不要往裡面看。
  let quoted = false;
  while (index < input.length) {
    const char = input[index];
    if (quote) {
      if (char === quote) quote = '';
      else delimiter += char;
      index += 1;
    } else if (char === '"' || char === "'") {
      quote = char;
      quoted = true;
      index += 1;
    } else if (char === '\\' && index + 1 < input.length) {
      delimiter += input[index + 1];
      quoted = true;
      index += 2;
    } else if (/[\s;&|()<>]/.test(char)) {
      break;
    } else {
      delimiter += char;
      index += 1;
    }
  }
  return { delimiter, end: index, quoted };
}

function shellWords(command) {
  const words = [];
  const dynamicExpansions = [];
  // Bodies lifted OUT of the word stream, each remembering which '<<' word it
  // belongs to, so commandTargets can hand a body back to a shell carrier and to
  // nothing else.
  // 從字流裡抽出來的 heredoc 內文，各自記得屬於哪一個 '<<'，好讓 commandTargets 只把它
  // 交還給 shell carrier。
  const heredocs = [];
  const pendingHeredocs = [];
  const input = String(command || '');
  let word = '';
  let wordHasDynamicExpansion = false;
  let quote = '';
  let escaped = false;

  function pushWord(value) {
    words.push(value);
    dynamicExpansions.push(wordHasDynamicExpansion);
    wordHasDynamicExpansion = false;
  }

  for (let index = 0; index < input.length; index += 1) {
    const char = input[index];
    if (escaped) {
      // A backslash-newline is a LINE CONTINUATION, and bash deletes BOTH
      // characters before it tokenises anything -- unquoted and inside double
      // quotes alike (measured with od(1): `/et\<nl>c` and `"/et\<nl>c"` both
      // arrive as /etc, while the single-quoted spelling keeps the backslash and
      // the newline, which is why this branch is never reached inside single
      // quotes). Keeping the newline in the word instead spelled the target
      // '\n/etc' -- a string on no list -- so `rm -rf \<nl>/etc` passed the one
      // guard standing on the agent path, where there is no trash, no ledger and
      // no undo. The executable was readable the same way: `r\<nl>m` is the word
      // rm, and it really does run /bin/rm (measured: it answered with rm's own
      // usage message).
      // The same misreading also refused ordinary work: a continuation line was
      // parsed as a fresh command, so a line beginning with "$HOME" became an
      // unknowable executable, was assumed to be rm, and had its operands
      // refused with '/' as the target.
      // 反斜線接換行是行接續，bash 在斷詞前就把兩個字元一起刪掉（未加引號與雙引號內
      // 皆然，od(1) 實測；單引號內原樣保留，所以這個分支在單引號裡永遠不會走到）。
      // 把換行留在字裡會讓目標拼成 '\n/etc'——任何清單上都沒有的字串——於是
      // `rm -rf \<nl>/etc` 直接穿過 agent 路徑上唯一的守衛。同一個誤讀也會反過來擋掉
      // 普通指令：續行被當成新命令，開頭是 "$HOME" 就成了不可知的執行檔。
      if (char !== '\n') word += char;
      escaped = false;
    } else if (quote === 'ansi-c') {
      if (char === "'") quote = '';
      else if (char === '\\') {
        const decoded = decodeAnsiCEscape(input, index);
        word += decoded.value;
        index = decoded.end;
      } else word += char;
    } else if (char === '\\' && quote !== "'") {
      escaped = true;
    } else if (quote) {
      if (char === quote) quote = '';
      else {
        if (quote === '"' && (char === '$' || char === '`')) {
          wordHasDynamicExpansion = true;
        }
        word += char;
      }
    } else if (char === '$' && input[index + 1] === "'") {
      quote = 'ansi-c';
      index += 1;
    } else if (char === '$' && input[index + 1] === '(') {
      // A command substitution belongs to the word it sits in, exactly like a
      // parameter expansion. Splitting it on the parentheses made
      // `$(which rm) -rf /` tokenize as the word `$` followed by a `(`
      // separator: the executable vanished and the operand scan stopped at that
      // separator before ever reaching the target.
      const substitution = readParenthesized(input, index + 1);
      wordHasDynamicExpansion = true;
      if (substitution) {
        word += input.slice(index, substitution.end + 1);
        index = substitution.end;
      } else {
        // Unbalanced '(': keep the old character-by-character behaviour.
        word += char;
      }
    } else if (char === '"' || char === "'") {
      quote = char;
    } else if (char === '<' && input[index + 1] === '<' && input[index + 2] !== '<') {
      // A HEREDOC, not two redirections. The body that follows is DATA: this
      // guard was tokenising it as shell, so a line of ordinary prose became a
      // command, and a line whose first word is an expansion became an
      // unknowable executable -- assumed to be rm, with its operands refused
      // as '/'. Measured on 2026-08-13: a `git commit -F -` message written in
      // this repository's own style was refused, twice, with no override.
      // The operator and its delimiter stay in the stream as a redirection so
      // the operand scans skip them; the body goes to the side, addressed by the
      // index of this operator word, and only a shell carrier gets it back.
      // '<<<' is a here-STRING and is excluded above -- it has no body.
      // 這是 heredoc，不是兩個重導向。後面的內文是「資料」：這道守衛原本把它當 shell 斷
      // 詞，於是一行散文變成一條命令，而以展開開頭的那一行變成不可知的執行檔——被假設成
      // rm，操作元以 '/' 被拒。2026-08-13 實測擋掉兩次 `git commit -F -`。
      // 運算子與結束標記留在字流裡當重導向（讓操作元掃描跳過），內文則移到旁邊，用這個
      // 運算子的索引定址，只有 shell carrier 拿得回去。'<<<' 是 here-string，上面已排除。
      if (word) pushWord(word), word = '';
      const stripTabs = input[index + 2] === '-';
      pushWord(stripTabs ? '<<-' : '<<');
      const operatorIndex = words.length - 1;
      const parsed = heredocDelimiter(input, index + (stripTabs ? 3 : 2));
      pushWord(parsed.delimiter);
      pendingHeredocs.push({
        operatorIndex, delimiter: parsed.delimiter, stripTabs, quoted: parsed.quoted,
      });
      index = parsed.end - 1;
    } else if (char === '\n' && pendingHeredocs.length > 0) {
      // The bodies begin on the next line, in the order the operators appeared.
      // 內文從下一行開始，順序與運算子出現的順序相同。
      if (word) pushWord(word), word = '';
      let position = index + 1;
      for (const pending of pendingHeredocs) {
        const bodyLines = [];
        const bodyStart = position;
        while (position <= input.length) {
          let lineEnd = input.indexOf('\n', position);
          const atEnd = lineEnd === -1;
          if (atEnd) lineEnd = input.length;
          const line = input.slice(position, lineEnd);
          position = lineEnd + 1;
          // An unterminated heredoc runs to the end of the input, exactly as a
          // shell reading a script that stops mid-heredoc would see it.
          if ((pending.stripTabs ? line.replace(/^\t+/, '') : line) === pending.delimiter) break;
          bodyLines.push(line);
          if (atEnd) break;
        }
        heredocs.push({
          operatorIndex: pending.operatorIndex,
          body: bodyLines.join('\n'),
          // Where the body sits in the ORIGINAL text, so the substitution scan
          // can be told to leave a literal body alone.
          quoted: pending.quoted,
          bodyStart,
          bodyEnd: Math.min(position, input.length),
        });
      }
      pendingHeredocs.length = 0;
      pushWord('\n');
      index = Math.min(position, input.length) - 1;
    } else if (';&|()<>\n'.includes(char)) {
      if (word) pushWord(word), word = '';
      pushWord(char);
    } else if (/\s/.test(char)) {
      if (word) pushWord(word), word = '';
    } else {
      if (char === '$' || char === '`') wordHasDynamicExpansion = true;
      word += char;
    }
  }
  if (escaped) word += '\\';
  if (word) pushWord(word);
  Object.defineProperty(words, 'dynamicExpansions', { value: dynamicExpansions });
  Object.defineProperty(words, 'heredocs', { value: heredocs });
  return words;
}

// Find the ')' that closes the '(' at openIndex, honouring nesting and quotes.
// Shared by the tokenizer and the substitution scanner so both agree on where a
// command substitution ends.
function readParenthesized(input, openIndex) {
  let depth = 1;
  let innerQuote = '';
  let innerEscaped = false;
  for (let i = openIndex + 1; i < input.length; i += 1) {
    const char = input[i];
    if (innerEscaped) {
      innerEscaped = false;
    } else if (char === '\\' && innerQuote !== "'") {
      innerEscaped = true;
    } else if (innerQuote) {
      if (char === innerQuote) innerQuote = '';
      else if (innerQuote === '"' && char === '$' && input[i + 1] === '(') {
        depth += 1;
        i += 1;
      }
    } else if (char === '"' || char === "'") {
      innerQuote = char;
    } else if (char === '$' && input[i + 1] === '(') {
      depth += 1;
      i += 1;
    } else if (char === '(') {
      depth += 1;
    } else if (char === ')') {
      depth -= 1;
      if (depth === 0) {
        return { command: input.slice(openIndex + 1, i), end: i };
      }
    }
  }
  return null;
}

function commandSubstitutions(command) {
  const input = String(command || '');
  const commands = [];
  let quote = '';
  let escaped = false;

  for (let i = 0; i < input.length; i += 1) {
    const char = input[i];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (char === '\\' && quote !== "'") {
      escaped = true;
      continue;
    }
    if (quote === "'") {
      if (char === "'") quote = '';
      continue;
    }
    if (char === quote && quote) {
      quote = '';
      continue;
    }
    if (!quote && (char === '"' || char === "'")) {
      quote = char;
      continue;
    }
    if (char === '$' && input[i + 1] === '(') {
      const nested = readParenthesized(input, i + 1);
      if (nested) {
        commands.push(nested.command);
        i = nested.end;
      }
      continue;
    }
    if ((char === '<' || char === '>') && input[i + 1] === '(') {
      const nested = readParenthesized(input, i + 1);
      if (nested) {
        commands.push(nested.command);
        i = nested.end;
      }
      continue;
    }
    if (char === '`') {
      let end = i + 1;
      let tickEscaped = false;
      for (; end < input.length; end += 1) {
        if (tickEscaped) {
          tickEscaped = false;
        } else if (input[end] === '\\') {
          tickEscaped = true;
        } else if (input[end] === '`') {
          break;
        }
      }
      if (end < input.length) {
        commands.push(input.slice(i + 1, end));
        i = end;
      }
    }
  }
  return commands;
}

function expandHome(value, home) {
  if (value === '~') return home;
  if (value.startsWith('~/')) return path.join(home, value.slice(2));
  if (value === '$HOME' || value === '${HOME}') return home;
  if (value.startsWith('$HOME/')) return path.join(home, value.slice(6));
  if (value.startsWith('${HOME}/')) return path.join(home, value.slice(8));
  return value;
}

function normalizedTarget(value, cwd, home) {
  // Real shells truncate an argument at the first NUL byte, so an ANSI-C
  // ($'...') escape that mints a NUL (backslash x00, backslash 0, etc.) must be
  // truncated here too; otherwise the guard compares '/etc\0' (never a match)
  // while the shell actually runs rm on '/etc'.
  const truncated = String(value).split('\0')[0];
  // A trailing slash is dropped here, and with it the one thing that tells this
  // guard the argument reaches a symlink's TARGET: `rm -rf link/` resolves the
  // final component, destroys what the link points at and leaves the link.
  // This function stays purely lexical, because a path that does not exist yet
  // must still be judged -- but it is no longer the only thing protectedReason()
  // consults. resolvedTarget() lstats the spelling AS WRITTEN, where `link` and
  // `link/` are two different objects, and the two verdicts are unioned.
  // 結尾斜線在這裡被去掉，連同「這個引數會碰到 symlink target」的唯一線索。本函式維持
  // 純字面（不存在的路徑也必須判得出來），但它不再是 protectedReason 唯一的依據：
  // resolvedTarget 會對「原樣拼寫」做 lstat，那裡 `link` 與 `link/` 是兩個不同的東西，
  // 兩邊的判定取聯集。
  const expanded = expandHome(truncated.replace(/[\\/]+$/, '') || '/', home);
  if (/[*?\[\]{}]/.test(expanded)) return expanded;
  return path.resolve(cwd, expanded);
}

// The argument as an absolute spelling, expanded but NOT lexically collapsed.
// path.resolve() folds '..' away before anything is asked of the filesystem, and
// `link/..` is precisely the spelling whose meaning depends on the link:
// measured, realpath(3) reports '<sandbox>/link-to-usr/..' as '/' -- the parent
// of the link's TARGET -- while a lexical collapse says '<sandbox>'. The
// filesystem has to be handed the spelling the shell would hand it.
// 原樣的絕對拼寫，不做字面收斂：path.resolve 會先把 '..' 折掉，而 `link/..` 的意義
// 正好取決於那條連結（實測 realpath 回報的是連結目標的父目錄，不是字面上的上一層）。
function absoluteSpelling(value, cwd, home) {
  const truncated = String(value).split('\0')[0];
  // A pattern names no single file, so there is nothing to ask the filesystem
  // about; the lexical rules already refuse the ones that could select .git.
  // 萬用字元不指名任何一個檔案，沒有東西可問檔案系統。
  if (/[*?[\]{}]/.test(truncated)) return null;
  // The trailing slash is the whole point of this function, so it survives the
  // same home expansion normalizedTarget() performs. Re-appended rather than
  // carried through, because the path.join() inside expandHome() would drop it.
  // 結尾斜線正是本函式存在的理由，所以要在同一套 home 展開之後補回來。
  const trailingSlash = truncated.endsWith('/') ? '/' : '';
  const expanded = expandHome(truncated.replace(/[\\/]+$/, '') || '/', home) + trailingSlash;
  return path.isAbsolute(expanded) ? expanded : `${cwd}/${expanded}`;
}

// What the FILESYSTEM says this spelling names, or null when it cannot say.
// Case folding, Unicode normalisation and symlink-through spellings are all
// properties of the filesystem rather than of the string, and there is no
// enumerating one's way out of them: /Users alone has 2^5 case spellings before
// Unicode is considered. The guard that has to answer for them must ask the only
// thing that knows.
// 大小寫、Unicode 正規化、穿過 symlink 的拼寫，三者都是檔案系統的性質而不是字串的
// 性質，列舉不完（光 /Users 就有 2^5 種大小寫寫法，還沒算 Unicode）。要回答這些，只能
// 去問唯一知道答案的那個東西。
function resolvedTarget(value, cwd, home) {
  const absolute = absoluteSpelling(value, cwd, home);
  if (absolute === null) return null;
  try {
    // lstat the spelling AS WRITTEN. An argument that IS a symlink is judged by
    // the link's own path and never by its target: deleting a link cannot touch
    // what it points at, so resolving one would refuse `rm ~/applink` because
    // /Applications is protected -- a false positive with no override. That is
    // the rule better-rm adopted in 2c34f8d, reached here through the same test
    // it uses ([ ! -L "$path" ]).
    // A trailing slash then separates the two cases by itself, with no second
    // rule: measured on macOS 26.6 and ubuntu-24.04, lstat('link') reports a
    // symlink while lstat('link/') reports the directory it points at, because a
    // trailing slash forces POSIX resolution of the final component. So `link`
    // is judged leniently and `link/` -- which really does destroy the target's
    // contents -- is judged by what it reaches.
    // 引數自己就是連結時不解析（刪連結碰不到 target，解析會把 ~/applink 這種捷徑變成
    // 刪不掉）。而結尾斜線本身就把兩種情形分開了，不需要第二條規則：實測
    // lstat('link') 是連結、lstat('link/') 是它指向的目錄。
    if (fs.lstatSync(absolute).isSymbolicLink()) return null;
    // realpathSync.NATIVE, not realpathSync: the JavaScript implementation walks
    // the path itself and hands back the spelling it was given (measured:
    // fs.realpathSync('/USERS') is '/USERS'), while the native one goes through
    // realpath(3) and returns what is on disk (measured: '/Users'). Only the
    // native call asks the filesystem, and the filesystem is the whole point.
    // 用 realpathSync.native 而不是 realpathSync：後者自己走路徑、原樣回傳拼寫（實測
    // fs.realpathSync('/USERS') 就是 '/USERS'），前者才會經過 realpath(3) 拿到磁碟上的
    // 拼寫（實測 '/Users'）。
    return fs.realpathSync.native(absolute);
  } catch (_) {
    // Every errno lands here on purpose, and every one of them means one thing:
    // the filesystem could not answer, so the verdict stays the lexical one this
    // guard produced before it ever looked. ENOENT and ENOTDIR are the ordinary
    // case -- a target that does not exist yet must still be judged, which is why
    // this guard was filesystem-free to begin with -- and EACCES on an unreadable
    // parent, ELOOP on a symlink cycle and ENAMETOOLONG say the same thing:
    // nothing learned, nothing changed. That cannot open a hole, because the
    // lexical rules still run and still refuse everything they refused before; it
    // can only decline to close one. It also must not throw: this is a PreToolUse
    // gate on every agent command, and an exception here denies every Bash call
    // on the machine.
    // 所有 errno 都落到這裡，而且意思都一樣：檔案系統答不出來，判定就維持原本的字面
    // 判定。這不會開洞（字面規則照跑），只會少補一個洞。而且絕不能往外丟例外：這是每
    // 一次 agent 命令都會經過的閘門，一個例外就會擋掉整台機器上所有 Bash 呼叫。
    return null;
  }
}

function hasUnresolvedTargetExpansion(isDynamic) {
  // Even HOME is unknowable here: the same simple command can override it
  // (`HOME=/ rm "$HOME/etc"`). Every real shell expansion in an rm operand
  // therefore fails closed; single-quoted and escaped dollars are not marked.
  return Boolean(isDynamic);
}

// A glob is a QUESTION ABOUT PATHS, and this file used to answer only one small
// part of it: "can the basename select a .git?", by building a regular
// expression. That was wrong in three ways at once, all measured.
//   rm -rf /et[c]   bash hands rm the path /etc   the guard said ALLOW
//   rm -rf dist/*   bash never matches dist/.git  the guard REFUSED it
//   rm -rf ****…    ~85 stars                     the regex exceeded the 5s timeout
// The three share one cause: a pattern was turned into a regex and asked a
// question about a string, instead of being matched against paths the way a
// shell matches them. What follows is a matcher, not a translator.
// glob 是一個「關於路徑」的問題，而這支檔案原本只回答其中很小的一塊（「basename 有沒有
// 可能選到 .git」），做法是組一個正則。三個症狀同源：把 pattern 翻譯成正則去問一個關於
// 字串的問題，而不是照 shell 的方式拿它去比對路徑。

// Brace expansion, bounded. `{a,b}` is not a glob operator -- the shell expands
// it into separate words before matching -- so it is expanded here too.
// 大括號展開（有上限）。它不是 glob 運算子，shell 會在比對之前先把它展成多個字。
function expandBraces(pattern, limit = 64) {
  const open = pattern.indexOf('{');
  if (open === -1) return [pattern];
  let depth = 0;
  let close = -1;
  const commas = [];
  for (let i = open; i < pattern.length; i += 1) {
    if (pattern[i] === '{') depth += 1;
    else if (pattern[i] === '}') {
      depth -= 1;
      if (depth === 0) { close = i; break; }
    } else if (pattern[i] === ',' && depth === 1) commas.push(i);
  }
  if (close === -1 || commas.length === 0) return [pattern];
  const head = pattern.slice(0, open);
  const tail = pattern.slice(close + 1);
  const bounds = [open, ...commas, close];
  const expanded = [];
  for (let i = 0; i < bounds.length - 1; i += 1) {
    const alternative = pattern.slice(bounds[i] + 1, bounds[i + 1]);
    for (const rest of expandBraces(`${head}${alternative}${tail}`, limit)) {
      if (expanded.length >= limit) return expanded;
      expanded.push(rest);
    }
  }
  return expanded;
}

// Does the bracket expression starting at `open` close, and where?
// A ']' immediately after '[' or '[!' is a literal, not the close.
function bracketEnd(pattern, open) {
  let i = open + 1;
  if (pattern[i] === '!' || pattern[i] === '^') i += 1;
  if (pattern[i] === ']') i += 1;
  while (i < pattern.length && pattern[i] !== ']') i += 1;
  return i < pattern.length ? i : -1;
}

function bracketMatches(spec, character) {
  let body = spec;
  let negated = false;
  if (body.startsWith('!') || body.startsWith('^')) {
    negated = true;
    body = body.slice(1);
  }
  let matched = false;
  for (let i = 0; i < body.length; i += 1) {
    if (body[i + 1] === '-' && i + 2 < body.length) {
      if (character >= body[i] && character <= body[i + 2]) matched = true;
      i += 2;
    } else if (body[i] === character) matched = true;
  }
  return negated ? !matched : matched;
}

// One path COMPONENT against one pattern component. Iterative, with a single
// backtrack point per '*', so the cost is bounded by pattern x text rather than
// exploding: the regular expression this replaces took over five seconds on
// ~85 stars (measured), which on a PreToolUse gate is a timeout, and a timed-out
// gate is a gate that did not answer.
// 單一路徑「段」對單一 pattern 段。迭代式、每個 '*' 只留一個回溯點，成本上限是
// pattern×text 而不會爆炸：它取代的那個正則在約 85 個 '*' 時要五秒以上（實測），對
// PreToolUse 閘門而言那就是逾時，而逾時的閘門等於沒有回答。
function componentMatches(pattern, text) {
  let p = 0;
  let t = 0;
  let starPattern = -1;
  let starText = 0;
  while (t < text.length) {
    const character = pattern[p];
    if (p < pattern.length && character === '[') {
      const end = bracketEnd(pattern, p);
      if (end !== -1) {
        if (bracketMatches(pattern.slice(p + 1, end), text[t])) {
          p = end + 1;
          t += 1;
          continue;
        }
      } else if (character === text[t]) {
        p += 1;
        t += 1;
        continue;
      }
    } else if (p < pattern.length && (character === '?' || character === text[t])) {
      p += 1;
      t += 1;
      continue;
    } else if (p < pattern.length && character === '*') {
      starPattern = p;
      starText = t;
      p += 1;
      continue;
    }
    if (starPattern !== -1) {
      starText += 1;
      t = starText;
      p = starPattern + 1;
      continue;
    }
    return false;
  }
  while (p < pattern.length && pattern[p] === '*') p += 1;
  return p === pattern.length;
}

// A whole path. Two rules that a regex translation cannot express and that are
// exactly where the old answer went wrong:
//   - '*', '?' and '[...]' never cross a '/', so the two sides must have the
//     same number of components;
//   - none of them matches a LEADING DOT. `dist/*` cannot select `dist/.git`
//     (measured in bash: it does not), which is why refusing it was wrong. A
//     pattern component that starts with a literal '.' can, which is why `.*`
//     and `.gi*` are still refused.
// 兩條正則翻譯表達不出來、而舊答案正好錯在這裡的規則：萬用字元不跨 '/'；而且都不匹配
// 開頭的點——`dist/*` 選不到 `dist/.git`（bash 實測），所以擋它是錯的；以字面 '.' 開頭的
// pattern 段則選得到，所以 `.*` 與 `.gi*` 照樣擋。
function globMatchesPath(pattern, target) {
  const patternParts = pattern.split('/');
  const targetParts = target.split('/');
  if (patternParts.length !== targetParts.length) return false;
  for (let i = 0; i < patternParts.length; i += 1) {
    if (targetParts[i].startsWith('.') && !patternParts[i].startsWith('.')) return false;
    if (!componentMatches(patternParts[i], targetParts[i])) return false;
  }
  return true;
}

function hasGlob(value) {
  return /[*?[\]{}]/.test(value);
}

// Kept as its own name because test-guard-parity.js asks the hook this exact
// question when it classifies a declared cross-layer difference.
function globCanMatchGit(value) {
  const basename = value.slice(value.lastIndexOf('/') + 1);
  if (!hasGlob(basename)) return false;
  return expandBraces(basename).some((pattern) => globMatchesPath(pattern, '.git'));
}

// Today's rules, asked of ONE already-normalised spelling. Split out of
// protectedReason() so the same rules can be asked of the spelling as written
// and of what the filesystem says it is, without either being a second copy.
// 同一組規則，對「一個已正規化的拼寫」提問。從 protectedReason 拆出來，好讓字面拼寫
// 與檔案系統解析後的拼寫走完全相同的規則，而不是兩份副本。
function protectedSpelling(spelling, home, extraDirs, cwd) {
  let normalized = spelling;

  // macOS firmlink: /System/Volumes/Data/X and /X are the same object. Measured
  // with stat -f '%d:%i', /Users/<user> and /System/Volumes/Data/Users/<user>
  // share a device and an inode, and so does /Applications. A firmlink is not a
  // symlink, so nothing canonicalises one spelling into the other -- the whole
  // home directory was removable here under the Data-volume spelling, on the one
  // path where this hook is the only guard. Rewriting the prefix onto the root
  // spelling before any comparison is what better-rm's is_protected does; the
  // rule is stated once there in full, including why it is a spelling
  // correspondence rather than an inode comparison (an inode needs the path to
  // exist, and a home directory that has not been created yet must not be walked
  // through either).
  // The prefix has to align on a WHOLE component: /System/Volumes/DataDrive is a
  // different disk and must keep its own spelling, or removing a file on it
  // becomes a refusal.
  // macOS firmlink：/System/Volumes/Data/X 與 /X 是同一個物件（同 device 同
  // inode），firmlink 不是 symlink，沒有任何正規化會讓兩種拼寫碰面——整個家目錄
  // 本來可以用 Data 卷宗的拼寫在這裡被放行。比對前先把前綴改寫回根拼寫，與
  // better-rm 的 is_protected 相同（完整理由寫在那裡）。前綴必須整段對齊。
  if (normalized === FIRMLINK_PREFIX || normalized.startsWith(`${FIRMLINK_PREFIX}/`)) {
    normalized = normalized.slice(FIRMLINK_PREFIX.length) || '/';
  }

  const exactDirs = [...SYSTEM_DIRS, home, ...extraDirs].map((item) => path.resolve(item));

  if (exactDirs.includes(normalized)) return normalized;

  // Protect the first-level mount roots under each mount parent (such as /mnt/c on
  // WSL and /Volumes/Backup on macOS), while allowing items inside them.
  // 保護各掛載父目錄的第一層掛載根（如 WSL 的 /mnt/c、macOS 的 /Volumes/Backup），
  // 但允許操作掛載點內的項目（如 /mnt/c/project）。
  for (const mountParent of MOUNT_PARENTS) {
    // Only the exact '..' means the target sits outside the parent: anything that
    // escapes further carries a separator and is excluded below, while a mount root
    // may legitimately be NAMED '..something'.
    // 只有剛好等於 '..' 才代表跳出父目錄；跳更多層一定帶分隔符，而掛載根本身可以叫做
    // '..某某'。
    const mountRelative = path.relative(mountParent, normalized);
    if (
      mountRelative &&
      mountRelative !== '..' &&
      !path.isAbsolute(mountRelative) &&
      !mountRelative.includes(path.sep)
    ) return normalized;
  }

  if (normalized === '.git' || normalized.endsWith(`${path.sep}.git`)) return normalized;

  if (/(^|[\\/])\.git([\\/]|$)/.test(normalized)) return normalized;

  // A pattern cannot be expanded here -- the filesystem it will be expanded
  // against is the one that exists a moment from now -- but it can be ASKED
  // whether it is capable of naming something protected. Two questions, and the
  // second one was never asked before: can it select a .git, and can it name a
  // protected directory itself? `rm -rf /et[c]` hands rm the path /etc (measured
  // with a fake rm printing its argv) and was allowed by every rule above it,
  // because each of them compares strings and `/et[c]` is not the string /etc.
  // 樣式在這裡展不開（它要對付的是「下一刻」的檔案系統），但可以問它「有沒有能力指到
  // 受保護的東西」。兩個問題，而第二個以前從來沒問過：它能不能選到 .git、它能不能指名
  // 一個受保護的目錄本身。`rm -rf /et[c]` 交給 rm 的就是 /etc（用會印 argv 的假 rm 實測），
  // 而上面每一條規則比的都是字串，`/et[c]` 不是 /etc 這個字串。
  if (hasGlob(normalized)) {
    const base = cwd.replace(/\/+$/, '');
    for (const pattern of expandBraces(normalized)) {
      // '..' is collapsed lexically here, and only here. Everywhere else in this
      // file a lexical collapse would be wrong, because '..' after a symlink
      // resolves onto the TARGET's parent -- but a pattern cannot be resolved at
      // all, so the choice is between collapsing and not asking: without it
      // `/Users/sieg/../*` is not recognised as `/Users/*`. Collapsing can only
      // make this rule match MORE patterns, never fewer.
      // '..' 只在這裡做詞法折疊。本檔其他地方這樣做都是錯的（'..' 經過 symlink 會落在
      // target 的父目錄），但樣式根本無法解析，所以選擇只有「折疊」或「不問」：不折疊的
      // 話 `/Users/sieg/../*` 就不會被認出是 `/Users/*`。折疊只會讓這條規則match 更多。
      const absolute = path.posix.normalize(pattern.startsWith('/') ? pattern : `${base}/${pattern}`);
      const patternBase = absolute.slice(absolute.lastIndexOf('/') + 1);
      if (globMatchesPath(patternBase, '.git')) return normalized;
      if (exactDirs.some((directory) => globMatchesPath(absolute, directory))) return normalized;
      // Mount roots need nothing here: the loop above already reads `/Volumes/*`
      // as a first-level entry under a mount parent and refuses it, because that
      // rule never cared whether the name was literal. Measured -- an added
      // mount-root question for patterns was mutation-tested and NOTHING went
      // red, which is the whole reason it is not here.
      // 掛載根不需要在這裡處理：上面那圈迴圈本來就把 `/Volumes/*` 讀成掛載父目錄下的第一
      // 層項目而拒絕，因為那條規則從來不在意名字是不是字面的。實測：為樣式另外加的掛載根
      // 判斷做突變測試時沒有任何測試轉紅，這正是它不在這裡的理由。
    }
  }
  return null;
}

// The union of what the spelling says and what the filesystem says it is, which
// is what better-rm's is_protected() has always compared: it tests both its
// readlink-resolved path and its unresolved one against every list. The union is
// not a belt-and-braces choice, it is load-bearing in both directions --
// `/var/.` resolves to /private/var, which is not on the list, while the
// spelling as written is /var, which is; and `/USERS` is not on the list as
// written while what it names is. Judging by either one alone opens a hole.
// TOCTOU: this verdict is produced before the command runs, so what the
// filesystem says here can change before rm sees it. That race is inherent to a
// pre-execution gate -- better-rm's own stat has it too -- and is not something
// this guard can close.
// 取「字面拼寫」與「檔案系統認定」的聯集，與 better-rm 的 is_protected 一直以來的做法
// 相同（它同時拿 real_path 與 norm_path 去比對每一份清單）。兩個方向都會用到：`/var/.`
// 解析後是 /private/var（不在清單上）但字面是 /var（在清單上），`/USERS` 則相反。只取
// 其中一邊就會開洞。TOCTOU：判定發生在命令執行之前，這個競態是前置閘門本質上就有的。
function protectedReason(target, cwd, home, extraDirs = []) {
  const lexical = normalizedTarget(target, cwd, home);
  const lexicalReason = protectedSpelling(lexical, home, extraDirs, cwd);
  if (lexicalReason) return lexicalReason;
  const resolved = resolvedTarget(target, cwd, home);
  if (resolved !== null && resolved !== lexical) {
    const resolvedReason = protectedSpelling(resolved, home, extraDirs, cwd);
    if (resolvedReason) return resolvedReason;
  }
  return declaredLink(target, cwd, home, extraDirs);
}

// The one question left when the argument IS a symlink. Resolution stops there
// on purpose -- deleting a link cannot touch what it points at -- so the only
// thing still judging such an argument is its spelling, and a spelling is a
// string while the entry on the list is an OBJECT. On this Mac /etc, /var and
// /home are symlinks: /ETC names the same link as /etc (measured: one dev:ino)
// and only the lower-case spelling was refused, while every declared entry that
// is a real directory folded correctly the moment resolvedTarget() consulted the
// filesystem. So ask the filesystem the same way here -- is this argument that
// entry? -- rather than folding the string, which would be a guess about the
// volume and wrong on a case-sensitive one.
// What it widens, exactly, measured rather than claimed: dev:ino names an
// INODE while rm unlinks a NAME, so a second name for a declared entry -- a hard
// link to the link itself -- is refused too, even though unlinking it leaves the
// declared entry in place. Reaching that shape takes linkat(2) with
// AT_SYMLINK_FOLLOW cleared (macOS `ln` refuses it; GNU `ln` does it by default),
// and it is an over-refusal in the safe direction, so it is accepted and stated
// here rather than worked around. Nothing else moves: every link that merely
// POINTS AT something declared stays deletable -- the ~/applink shortcut this
// rule exists to protect, and, measured across all 64,253 symlinks on this
// machine's sealed system volume, exactly the three declared ones match.
// 引數自己就是一條連結時，剩下的唯一問題。解析在那裡停住是刻意的（刪連結碰不到它指向
// 的東西），於是只剩「拼寫」在判它——但拼寫是字串，清單上的項目是一個物件。這台 Mac 上
// /etc、/var、/home 都是連結：/ETC 與 /etc 是同一條連結（實測同 dev:ino），卻只有小寫
// 那種寫法被擋下來；而是真目錄的宣告項目，在 resolvedTarget 問過檔案系統之後全都折對
// 了。所以這裡也去問檔案系統，而不是把字串折成小寫——後者是在猜這顆卷宗的性質，在分
// 大小寫的檔案系統上會猜錯。這不會擴大保護範圍：只有「引數就是清單上那一項」才成立。
function declaredLink(value, cwd, home, extraDirs) {
  const absolute = absoluteSpelling(value, cwd, home);
  if (absolute === null) return null;
  // BigInt, not the default Number: an APFS inode is routinely larger than
  // 2^53 (measured on this volume: /etc is ino 1152921500312571429), and a
  // Number-typed inode is rounded. Two distinct links would then compare equal
  // and this rule would refuse an unrelated path.
  // 用 BigInt 而不是預設的 Number：APFS 的 inode 動輒超過 2^53（實測 /etc 是
  // 1152921500312571429），Number 會捨入，兩條不同的連結就會比對成相等。
  let argument;
  try {
    argument = fs.lstatSync(absolute, { bigint: true });
  } catch (_) {
    // The filesystem could not answer, exactly as in resolvedTarget(): nothing
    // learned, so nothing changes. It must not throw -- this gate runs on every
    // agent command, and an exception here denies every Bash call on the machine.
    return null;
  }
  // This line and the one on the declared side are removable ONE AT A TIME
  // without changing a verdict -- an inode is unique within its device, so an
  // argument that is not a link cannot carry the same dev:ino as an entry that is
  // one -- and each on its own buys only speed: one lstat instead of twenty-six
  // on every ordinary target that reaches this far.
  // TOGETHER they are the rule. Remove both and the comparison escapes symlinks
  // entirely: a second NAME for a declared ordinary file (a hard link, which does
  // share its dev and ino) is refused, though unlinking that name leaves the
  // declared file exactly where it was. That pair is pinned by the hard-link row
  // in test-hooks.js, which is why deleting either line alone still leaves the
  // suite green and deleting both does not.
  // 這一行與宣告端那一行，「單獨拿掉任一行」都不會改變判定（inode 在同一 device 內唯一，
  // 非連結不可能與連結同 dev:ino），各自只買到速度。但「兩行一起拿掉」就是規則本身：
  // 比對會脫離 symlink 的範圍，宣告過的普通檔案的第二個名字（hard link，同 dev 同 ino）
  // 會被拒絕，而刪掉那個名字根本不會動到那個檔案。這一對由 test-hooks.js 的 hard link
  // 那一列釘住。
  if (!argument.isSymbolicLink()) return null;
  for (const entry of [...SYSTEM_DIRS, home, ...extraDirs]) {
    const spelling = path.resolve(entry);
    try {
      const declared = fs.lstatSync(spelling, { bigint: true });
      // lstat, not stat, on BOTH sides: the question is whether the argument is
      // that entry, never whether the two point at the same place. Following
      // either side would refuse ~/applink for naming /Applications.
      // 兩邊都用 lstat 而不是 stat：問的是「引數是不是那一項」，不是「兩者指向同一處」。
      if (!declared.isSymbolicLink()) continue;
      if (declared.dev === argument.dev && declared.ino === argument.ino) return spelling;
    } catch (_) {
      // An entry that is not on this machine cannot be the argument.
    }
  }
  return null;
}

function commandTargets(command, depth = 0) {
  const words = shellWords(command);
  const dynamicExpansions = words.dynamicExpansions || [];
  const targets = [];
  const separators = new Set([';', '&', '|', '(', ')', '<', '>', '\n']);
  // Redirections (`<`, `>`) stay within a simple command; they are not command
  // terminators. The rm/rmdir argument scan must skip a redirection and its
  // operand and keep collecting targets, or a leading `>/dev/null` hides them.
  // `<<` and `<<-` are the same shape -- operator plus operand -- and their
  // operand is a delimiter, never a path. The body they introduce is not in this
  // word stream at all; it sits beside it, addressed by the operator's index.
  // `<<` 與 `<<-` 形狀相同：運算子加操作元，而那個操作元是結束標記、不是路徑。它們帶出
  // 來的內文根本不在這串字裡，而是放在旁邊、用運算子的索引定址。
  const redirectors = new Set(['<', '>', '<<', '<<-']);
  // operator word index -> the heredoc body it introduced.
  const heredocBodies = new Map((words.heredocs || []).map((entry) => [entry.operatorIndex, entry.body]));
  const terminators = new Set([';', '&', '|', '(', ')', '\n']);
  const controlWords = new Set([
    'if', 'then', 'elif', 'else', 'fi',
    'for', 'while', 'until', 'select', 'do', 'done',
    'case', 'in', 'esac', '{', '}',
  ]);
  const shellCarriers = new Set(['sh', 'bash', 'dash', 'zsh', 'ksh', 'fish']);
  const simpleWrappers = new Set(['!', 'nohup', 'setsid']);
  const wrapperCommands = new Set([
    ...simpleWrappers,
    'time', 'exec', 'coproc', 'function', 'eval', 'nice', 'timeout',
    'sudo', 'command', 'builtin', 'noglob', 'env',
    'echo', 'printf', 'true', 'false',
    ...shellCarriers,
    'rm', 'rmdir', 'better-rm',
  ]);
  // A heredoc with a QUOTED delimiter is literal: the shell performs no
  // substitution inside it, so neither does this scan. Blanking those spans (and
  // only those) is what keeps ordinary text out of the command reader while a
  // body with an UNQUOTED delimiter -- where `$(rm -rf /etc)` really does run
  // before anyone reads the result -- is still scanned in full.
  // Measured: without this, a commit message quoting the very example this guard
  // exists for (a backtick-wrapped `$CMD -rf /`) was refused, through a heredoc
  // whose delimiter was quoted and whose contents the shell never touched.
  // 結束標記有引號的 heredoc 是字面的：shell 不在裡面做任何替換，這個掃描也就不做。只把
  // 那些區段抹白，未加引號的內文照舊整段掃（那裡的 `$(rm -rf /etc)` 是真的會執行）。
  const literalBodies = (words.heredocs || []).filter((entry) => entry.quoted);
  const scannable = literalBodies.length === 0 ? command : literalBodies.reduce(
    (text, entry) => text.slice(0, entry.bodyStart)
      + ' '.repeat(entry.bodyEnd - entry.bodyStart)
      + text.slice(entry.bodyEnd),
    String(command || ''),
  );
  const substitutions = commandSubstitutions(scannable);
  if (substitutions.length > 0) {
    if (depth >= 8) targets.push('/');
    else {
      for (const nested of substitutions) {
        targets.push(...commandTargets(nested, depth + 1));
      }
    }
  }
  let i = 0;

  while (i < words.length) {
    while (i < words.length && separators.has(words[i])) i += 1;
    if (i >= words.length) break;
    if (controlWords.has(words[i])) {
      i += 1;
      continue;
    }
    let executable = '';
    let executableIndex = -1;
    // Set when a wrapper hands the command its operands on stdin (xargs), where
    // the paths are unknowable before the command runs.
    let stdinCompletesOperands = false;

    // Wrapper commands can be chained arbitrarily (for example
    // `sudo env SAFE=1 command bash -c ...`). Unwrap each layer until the
    // actual executable is reached; every branch advances i, so malformed
    // wrapper-only input remains bounded.
    while (i < words.length && !separators.has(words[i])) {
      while (i < words.length && /^[A-Za-z_][A-Za-z0-9_]*=/.test(words[i])) i += 1;
      if (i >= words.length || separators.has(words[i])) break;
      if (controlWords.has(words[i])) {
        i += 1;
        executable = '';
        continue;
      }
      executable = path.basename(words[i]);
      executableIndex = i;

      if (executable === 'sudo') {
        const optionsWithValue = new Set(['-u', '--user', '-g', '--group', '-h', '--host', '-p', '--prompt', '-C', '--close-from', '-T', '--command-timeout', '-R', '--chroot', '-D', '--chdir', '-r', '--role', '-t', '--type']);
        i += 1;
        while (i < words.length && words[i].startsWith('-')) {
          const option = words[i];
          i += optionsWithValue.has(option)
            || /^--(?:ro(?:l)?|t(?:y(?:p)?)?)$/.test(option)
            || /^-[ABbEeHikKNnPSVvs]*[CDghprtRTu]$/.test(option)
            ? 2
            : 1;
        }
        executable = '';
        continue;
      }

      if (executable === 'command' || executable === 'builtin' || executable === 'noglob') {
        do i += 1; while (i < words.length && words[i].startsWith('-'));
        executable = '';
        continue;
      }

      if (executable === 'env') {
        const optionsWithValue = new Set([
          '-u', '--unset', '-C', '--chdir', '-S', '--split-string', '-a', '--argv0', '-P',
        ]);
        i += 1;
        while (i < words.length) {
          const option = words[i];
          if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(option)) {
            i += 1;
          } else if (option === '--') {
            i += 1;
            break;
          } else if (option === '-S' || option === '--split-string') {
            const splitString = words[i + 1] || '';
            if (depth >= 8) targets.push('/');
            else if (splitString) targets.push(...commandTargets(splitString, depth + 1));
            i += 2;
          } else if (option.startsWith('--split-string=')) {
            const splitString = option.slice('--split-string='.length);
            if (depth >= 8) targets.push('/');
            else if (splitString) targets.push(...commandTargets(splitString, depth + 1));
            i += 1;
          } else if (option.startsWith('-S') && option.length > 2) {
            const splitString = option.slice(2);
            if (depth >= 8) targets.push('/');
            else targets.push(...commandTargets(splitString, depth + 1));
            i += 1;
          } else if (/^-[iv]*S.+/.test(option)) {
            const splitString = option.replace(/^-[iv]*S/, '');
            if (depth >= 8) targets.push('/');
            else targets.push(...commandTargets(splitString, depth + 1));
            i += 1;
          } else if (/^-[iv]*S$/.test(option)) {
            const splitString = words[i + 1] || '';
            if (depth >= 8) targets.push('/');
            else if (splitString) targets.push(...commandTargets(splitString, depth + 1));
            i += 2;
          } else if (/^-[iv]*[uPCa]$/.test(option)) {
            i += 2;
          } else if (optionsWithValue.has(option)) {
            i += 2;
          } else if (option.startsWith('-')) {
            i += 1;
          } else {
            break;
          }
        }
        executable = '';
        continue;
      }

      if (simpleWrappers.has(executable)) {
        i += 1;
        while (i < words.length && words[i].startsWith('-')) i += 1;
        executable = '';
        continue;
      }

      if (executable === 'exec') {
        i += 1;
        while (i < words.length && words[i].startsWith('-')) {
          const option = words[i];
          if (option === '--') {
            i += 1;
            break;
          }
          i += /^-[cl]*a$/.test(option) ? 2 : 1;
        }
        executable = '';
        continue;
      }

      if (executable === 'time') {
        const optionsWithValue = new Set(['-f', '--format', '-o', '--output']);
        i += 1;
        while (i < words.length && words[i].startsWith('-')) {
          const option = words[i];
          if (option === '--') {
            i += 1;
            break;
          }
          i += optionsWithValue.has(option) || /^-[ahpqlvV]*[fo]$/.test(option)
            ? 2
            : 1;
        }
        executable = '';
        continue;
      }

      if (executable === 'coproc') {
        i += 1;
        if (
          i + 1 < words.length
          && /^[A-Za-z_][A-Za-z0-9_]*$/.test(words[i])
          && !wrapperCommands.has(path.basename(words[i]))
          && (
            wrapperCommands.has(path.basename(words[i + 1]))
            || controlWords.has(words[i + 1])
            || /^[A-Za-z_][A-Za-z0-9_]*=/.test(words[i + 1])
            || words[i + 1] === '{'
            || words[i + 1] === '('
          )
        ) i += 1;
        if (words[i] === '{' || words[i] === '(') i += 1;
        executable = '';
        continue;
      }

      if (executable === 'function') {
        i += 1;
        if (i < words.length && /^[A-Za-z_][A-Za-z0-9_]*$/.test(words[i])) i += 1;
        if (words[i] === '(') i += 1;
        if (words[i] === ')') i += 1;
        if (words[i] === '{') i += 1;
        executable = '';
        continue;
      }

      if (executable === 'nice') {
        i += 1;
        while (i < words.length && words[i].startsWith('-')) {
          const option = words[i];
          i += option === '-n' || option === '--adjustment' ? 2 : 1;
        }
        executable = '';
        continue;
      }

      if (executable === 'timeout') {
        const optionsWithValue = new Set(['-k', '--kill-after', '-s', '--signal']);
        i += 1;
        while (i < words.length && words[i].startsWith('-')) {
          const option = words[i];
          if (option === '--') {
            i += 1;
            break;
          }
          i += optionsWithValue.has(option) || /^-[pfv]*[ks]$/.test(option)
            ? 2
            : 1;
        }
        // timeout's first non-option operand is the duration.
        if (i < words.length && !separators.has(words[i])) i += 1;
        executable = '';
        continue;
      }

      if (executable === 'xargs') {
        // xargs EXECUTES the command itself, so `| xargs rm -rf` reaches /bin/rm
        // with no `rm` in command position, past the shell alias and past this
        // guard. Unwrap to the command it runs, and remember that its operands
        // are completed from stdin -- which a pre-execution gate cannot read.
        // xargs 自己就會執行那個命令，所以 `| xargs rm -rf` 會直接碰到 /bin/rm，命令位置
        // 上根本沒有 rm，shell alias 與這道守衛都繞過去了。這裡拆到它真正要跑的命令，並
        // 記住它的操作元會由 stdin 補上——那是前置閘門讀不到的東西。
        stdinCompletesOperands = true;
        i += 1;
        const optionsWithValue = new Set([
          '-a', '--arg-file', '-d', '--delimiter', '-E', '-e', '--eof',
          '-I', '--replace', '-i', '-L', '--max-lines', '-l',
          '-n', '--max-args', '-P', '--max-procs', '-s', '--max-chars',
        ]);
        while (i < words.length && words[i].startsWith('-')) {
          i += optionsWithValue.has(words[i]) ? 2 : 1;
        }
        executable = '';
        continue;
      }

      break;
    }

    // Only advance past a real executable. When the unwrap loop above consumed
    // wrapper layers and stopped AT a separator (executable === ''), advancing
    // here would swallow that separator and hide the command that follows it.
    // A command word that only exists after expansion (`CMD=rm; $CMD -rf /`,
    // `"$CMD" -rf /`, backticks) is unknowable here, so it must be assumed to be
    // rm: its operands are scanned exactly like rm operands. Matching on the
    // literal word alone let every dynamic spelling of rm through.
    const unresolvedExecutable = executable !== ''
      && hasUnresolvedTargetExpansion(dynamicExpansions[executableIndex]);
    if (executable) i += 1;
    if (['rm', 'rmdir'].includes(executable) && stdinCompletesOperands) {
      // The literal operands below are still scanned, but the ones arriving on
      // stdin are the whole point of the pipeline and cannot be read here. That
      // is the same unknowable as `rm -rf "$DIR"`, and it gets the same answer.
      // 底下的字面操作元照舊掃，但整條管線的重點是那些從 stdin 進來的路徑，這裡讀不到。
      // 這與 `rm -rf "$DIR"` 是同一種不可知，答案也一樣。
      targets.push('/');
    }
    if (['rm', 'rmdir'].includes(executable) || unresolvedExecutable) {
      for (; i < words.length && !terminators.has(words[i]); i += 1) {
        const candidate = words[i];
        if (redirectors.has(candidate)) {
          // Skip the redirection and its filename operand (not an rm target),
          // but never skip a command terminator that follows a bare redirect.
          if (i + 1 < words.length && !terminators.has(words[i + 1])) i += 1;
          continue;
        }
        if (candidate === '--') continue;
        // An unresolvable command word may also be a shell carrier, so an
        // operand holding a whole command string (`$CMD -c 'rm -rf /'`) has to
        // be parsed as a command as well as compared as a path.
        if (unresolvedExecutable && /\s/.test(candidate)) {
          if (depth >= 8) targets.push('/');
          else targets.push(...commandTargets(candidate, depth + 1));
        }
        if (!candidate.startsWith('-') || candidate === '-') {
          targets.push(
            hasUnresolvedTargetExpansion(dynamicExpansions[i]) ? '/' : candidate
          );
        }
      }
    } else if (shellCarriers.has(executable)) {
      const nestedCommands = [];
      for (; i < words.length && !separators.has(words[i]); i += 1) {
        // `bash <<EOF` has no -c: the heredoc body IS the script, and every rm in
        // it runs. This is the one place a body is code rather than data, and it
        // is why the body is kept beside the word stream instead of discarded.
        // `bash <<EOF` 沒有 -c：那段內文就是腳本本身，裡面的每一個 rm 都會執行。這是
        // 內文唯一算「程式碼」的地方，也正是它被留在旁邊而不是丟掉的理由。
        if (heredocBodies.has(i)) {
          nestedCommands.push(heredocBodies.get(i));
          continue;
        }
        const option = words[i];
        if (
          executable === 'fish'
          && (option === '-C' || option === '--init-command')
        ) {
          i += 1;
          nestedCommands.push(words[i] || '');
        } else if (
          executable === 'fish'
          && option.startsWith('--init-command=')
        ) {
          nestedCommands.push(option.slice('--init-command='.length));
        } else if (
          executable === 'fish'
          && option.startsWith('--command=')
        ) {
          nestedCommands.push(option.slice('--command='.length));
        } else if (option === '--command' || /^-[^-]*c/.test(option)) {
          i += 1;
          nestedCommands.push(words[i] || '');
          if (executable !== 'fish') break;
        }
      }
      for (const nestedCommand of nestedCommands) {
        if (!nestedCommand) continue;
        // Bound adversarial recursion, but fail closed rather than letting a
        // deeply nested shell carrier bypass the protected-directory hook.
        if (depth >= 8) targets.push('/');
        else targets.push(...commandTargets(nestedCommand, depth + 1));
      }
      while (i < words.length && !separators.has(words[i])) i += 1;
    } else if (executable === 'find') {
      // find deletes on its own with -delete, and through the -exec family when
      // the command it runs is rm. Either way the paths it walks are literal
      // operands sitting right here, so they are judged as rm targets -- which
      // keeps `find . -name '*.pyc' -delete` ordinary and refuses
      // `find /etc -delete`.
      // A find that neither deletes nor execs rm is a reader, and almost every
      // find is a reader; treating them all as deleters would refuse a listing.
      // find 自己用 -delete 就會刪，用 -exec 那一族碰到 rm 也會刪。兩種情形要走的路徑都是
      // 就寫在指令裡的字面操作元，所以直接拿它們當 rm 的目標判。既不刪也不 exec rm 的
      // find 只是在讀，而絕大多數 find 都是在讀，全部當成刪除工具會擋掉列檔案。
      const searchRoots = [];
      let deletes = false;
      while (i < words.length && !terminators.has(words[i]) && !words[i].startsWith('-')) {
        searchRoots.push(words[i]);
        i += 1;
      }
      for (; i < words.length && !terminators.has(words[i]); i += 1) {
        if (words[i] === '-delete') deletes = true;
        if (['-exec', '-execdir', '-ok', '-okdir'].includes(words[i])
          && ['rm', 'rmdir'].includes(path.basename(words[i + 1] || ''))) deletes = true;
      }
      if (deletes) {
        // GNU find defaults to the working directory when no path is given.
        for (const root of searchRoots.length > 0 ? searchRoots : ['.']) targets.push(root);
      }
    } else if (executable === 'eval') {
      const nestedCommand = [];
      for (; i < words.length && !separators.has(words[i]); i += 1) {
        nestedCommand.push(words[i]);
      }
      if (nestedCommand.length > 0) {
        if (depth >= 8) targets.push('/');
        else targets.push(...commandTargets(nestedCommand.join(' '), depth + 1));
      }
    } else {
      while (i < words.length && !separators.has(words[i])) i += 1;
    }
  }
  return targets;
}

function extractInput(payload) {
  let toolInput = payload.tool_input ?? payload.toolArgs ?? payload.toolCall?.args ?? payload.toolInput ?? {};
  if (typeof toolInput === 'string') {
    try { toolInput = JSON.parse(toolInput); } catch (_) { toolInput = { command: toolInput }; }
  }
  const command = toolInput?.command ?? toolInput?.cmd ?? toolInput?.CommandLine ?? payload.command ?? '';
  const cwd = payload.cwd || toolInput?.Cwd || process.cwd();
  const isCopilot = 'toolName' in payload || 'toolArgs' in payload;
  const isAntigravity = 'toolCall' in payload;
  const isCursor = payload.hook_event_name === 'beforeShellExecution';
  const isGrok = 'toolInput' in payload || payload.hookEventName === 'PreToolUse';

  return {
    command,
    cwd,
    isCopilot,
    isAntigravity,
    isCursor,
    isGrok,
  };
}

function denial(reason, isCopilot, isAntigravity, isCursor, isGrok) {
  const message = `拒絕刪除受保護的目錄：${reason} / Refused to remove protected directory: ${reason}`;
  if (isGrok) {
    return {
      decision: 'deny',
      reason: message,
    };
  }
  if (isCursor) {
    return {
      permission: 'deny',
      user_message: message,
      agent_message: message,
    };
  }
  if (isAntigravity) {
    return {
      allow_tool: false,
      deny_reason: message,
    };
  }
  return isCopilot
    ? { permissionDecision: 'deny', permissionDecisionReason: message }
    : {
        hookSpecificOutput: {
          hookEventName: 'PreToolUse',
          permissionDecision: 'deny',
          permissionDecisionReason: message,
        },
      };
}

function evaluate(payload, env = process.env) {
  const { command, cwd, isCopilot, isAntigravity, isCursor, isGrok } = extractInput(payload);
  if (!command) {
    if (isGrok) return { decision: 'allow' };
    if (isCursor) return { permission: 'allow' };
    if (isAntigravity) return { allow_tool: true };
    return null;
  }
  const home = env.HOME || os.homedir();
  const extraDirs = (env.BETTER_RM_PROTECTED_DIRS || '')
    .split(path.delimiter).filter(Boolean).map((item) => path.resolve(cwd, item));

  for (const target of commandTargets(command)) {
    const reason = protectedReason(target, cwd, home, extraDirs);
    if (reason) return denial(reason, isCopilot, isAntigravity, isCursor, isGrok);
  }

  if (isGrok) return { decision: 'allow' };
  if (isCursor) return { permission: 'allow' };
  if (isAntigravity) return { allow_tool: true };
  return null;
}

async function main() {
  let input = '';
  for await (const chunk of process.stdin) input += chunk;
  try {
    const result = evaluate(JSON.parse(input.replace(/^\uFEFF/, '')));
    if (result) process.stdout.write(JSON.stringify(result));
  } catch (error) {
    console.error(`Hook 輸入無效，已拒絕工具呼叫 / Invalid hook input; tool call denied: ${error.message}`);
    // Exit 2 so Claude Code PreToolUse treats this as a BLOCKING error and fails
    // closed; exit 1 is a non-blocking error there and would let the tool run.
    process.exit(2);
  }
}

if (require.main === module) main();

module.exports = { MOUNT_PARENTS, SYSTEM_DIRS, commandTargets, evaluate, globCanMatchGit, hasGlob, normalizedTarget, protectedReason, shellWords };
