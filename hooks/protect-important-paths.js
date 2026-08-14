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

// Protected directories that live under the user's HOME, named relative to it
// because there is no absolute spelling to put in SYSTEM_DIRS: the home
// directory is a per-machine, per-call value, and this list is joined onto the
// same `home` the protected-path check already receives (env.HOME, falling back
// to os.homedir()), so it reuses that one mechanism rather than introducing a
// second. Kept in step with better-rm's own PROTECTED_DIRS exactly as
// SYSTEM_DIRS is -- those entries are spelled "$HOME/.ssh" and "$HOME/.claude"
// there, and the drift guard in test-hooks.js compares the two lists including
// these.
// They get precisely what /etc gets and nothing more: the directory ITSELF is
// refused, everything inside it stays ordinary work. `rm -rf ~/.ssh` is refused;
// `rm -f ~/.ssh/known_hosts.old` and `rm -rf ~/.claude/projects/<session>` are
// not. The one place that is not obvious is a glob: a pattern whose parent is a
// protected directory selects that directory's entire contents, so `rm -rf
// ~/.ssh/*` is refused for the same reason `rm -rf /etc/*` is.
// Why these two. ~/.ssh holds private keys and known_hosts: losing it is not a
// rebuild, it is re-enrolling every host and every forge that trusts the key.
// ~/.claude holds this machine's agent configuration, hooks and the session
// transcripts under projects/, and this hook is loaded FROM that configuration.
// Until now `rm -rf ~/.ssh` was refused only by accident -- an unresolved
// variable folded to '/' and every spelling was refused for the wrong reason,
// while the literal `rm -rf ~/.ssh` was allowed all along.
// Why NOT ~/Library. Clearing a cache under it (~/Library/Caches/<tool>) is
// routine, and the guard protects a directory rather than its contents, so
// adding it would buy nothing for the ordinary command and would refuse
// `rm -rf ~/Library/*`-shaped cleanups. An over-refusal on a gate with no
// override is a live cost, and this one has no matching benefit.
// 受保護目錄中位於使用者家目錄底下的那幾項，以「相對家目錄」的形式列出：家目錄是每台機器、
// 每次呼叫才知道的值，SYSTEM_DIRS 裡沒有可以寫死的絕對拼寫。這份清單會接到受保護路徑判定
// 本來就收到的那個 home 上，重用既有機制而不是另開一套。與 better-rm 的 PROTECTED_DIRS
// 保持一致（那邊寫作 "$HOME/.ssh"、"$HOME/.claude"），test-hooks.js 的漂移守衛會比對。
// 它們拿到的保護與 /etc 完全相同、不多不少：擋的是目錄本身，裡面的東西照舊是日常工作。
// 唯一不那麼直觀的是萬用字元：父目錄受保護的樣式選中的是該目錄的全部內容，所以
// `rm -rf ~/.ssh/*` 會被擋，理由與 `rm -rf /etc/*` 相同。
// 為什麼是這兩個：~/.ssh 是私鑰與 known_hosts，丟了不是重建而是把每一台主機、每一個平台重新
// 授權一次；~/.claude 是這台機器的 agent 設定、hooks 與 projects/ 底下的對話記錄，而這支
// hook 本身就是從那份設定載入的。在此之前 `rm -rf ~/.ssh` 只是「碰巧」被擋——解不開的變數被
// 折成 '/' 而以錯誤的理由拒絕——字面的 `rm -rf ~/.ssh` 一直都是放行的。
// 為什麼不加 ~/Library：清 ~/Library/Caches/<tool> 是例行工作，而這道守衛保護的是目錄本身
// 不是內容，加了對常見命令毫無幫助，卻會擋掉 `rm -rf ~/Library/*` 這類清理。在一道沒有豁免
// 管道的閘門上，誤擋是實實在在的成本，而這一項沒有對等的收益。
const HOME_DIRS = ['.claude', '.ssh'];

// Every location judged by exact spelling, for one call: the absolute list, the
// home directory, the home-relative list joined onto it, and whatever the user
// declared through BETTER_RM_PROTECTED_DIRS. In one function because the exact
// check and the symlink-identity check must ask about the SAME entries -- they
// each built this list by hand before, and an entry added to one of them and not
// the other is protected by spelling but not by identity.
// 一次呼叫裡所有「以完全比對判定」的位置：絕對清單、家目錄、接到家目錄上的相對清單，加上使用
// 者透過 BETTER_RM_PROTECTED_DIRS 宣告的項目。寫成一個函式，是因為完全比對與 symlink 身分
// 比對必須問同一批項目——先前兩處各自手動組出這份清單，只加其中一處就會變成「拼寫受保護、身分
// 不受保護」。
function protectedEntries(home, extraDirs) {
  return [...SYSTEM_DIRS, home, ...HOME_DIRS.map((leaf) => path.join(home, leaf)), ...extraDirs];
}

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

  // Whether the word at this index was written as an unquoted shell OPERATOR
  // rather than as text that happens to spell one. `;`, `\;` and `';'` all
  // tokenize to the same one-character word, and only the first of the three
  // ends a command -- the other two are find's -exec clause terminator, which is
  // an ordinary operand as far as the shell is concerned. Without this flag the
  // find scan had to guess, guessed "shell separator", and stopped; every find
  // operator after a `\;` was then invisible to every rule in this file.
  // 這個字是不是「未加引號的 shell 運算子」，而不是剛好拼成運算子的文字。`;`、`\;`、`';'`
  // 斷出來是同一個單字元字，但只有第一個會結束命令，另外兩個是 find 的 -exec 子句終止符
  // ——對 shell 而言只是普通操作元。沒有這個旗標，find 的掃描只能猜，而它猜「shell 分隔
  // 符」就停下來，於是 `\;` 後面的每一個 find 運算子對本檔案的所有規則都是隱形的。
  const operatorTokens = [];

  function pushWord(value, writtenAsOperator = false) {
    words.push(value);
    dynamicExpansions.push(wordHasDynamicExpansion);
    operatorTokens.push(writtenAsOperator);
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
        // Clamped, and this is not cosmetic. A body that runs to the end of the
        // input leaves `position` one PAST the end, so a SECOND heredoc in the
        // same command started after the end while its end was clamped to it --
        // a negative span, and the ' '.repeat() that masks a literal body threw
        // `Invalid count value: -1`. On a PreToolUse gate a throw is exit 2,
        // which BLOCKS the tool call, so twenty bytes of legitimate shell
        // (`cat <<'A' <<'B'` and one line of body) hard-refused with a message
        // that blamed the hook's input. Measured; found by an acceptance review,
        // not by any of the three suites.
        // 夾住上下界，而且這不是美化。內文一路吃到輸入結尾時 position 會停在結尾之後一
        // 格，於是同一條命令裡的「第二個 heredoc」起點在終點之後——一段負長度，用來把
        // 字面內文抹白的 ' '.repeat() 就丟出 Invalid count value: -1。PreToolUse 丟例外
        // 等於 exit 2，會擋掉那次工具呼叫。
        const bodyStart = Math.min(position, input.length);
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
      pushWord('\n', true);
      index = Math.min(position, input.length) - 1;
    } else if (';&|()<>\n'.includes(char)) {
      if (word) pushWord(word), word = '';
      pushWord(char, true);
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
  Object.defineProperty(words, 'operatorTokens', { value: operatorTokens });
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

// A target this gate could not work out. It is still a refusal -- nothing about
// failing closed changes -- but the MESSAGE has to say "unknown", not "/".
// Saying `/` was factually false: the command never named `/`, the gate simply
// folded an unknown to the worst case and then reported the worst case as if it
// were the argument. A message that describes something the user did not write
// is the same class of defect as a doc that describes behaviour the code does
// not have, and this round has now found several of those.
// NUL cannot occur in a pathname, so this prefix cannot collide with one.
// 這個閘門算不出來的目標。照舊是拒絕（fail closed 完全沒變），但訊息必須說「不知道」而不是
// 「/」。說 `/` 是不實陳述：命令根本沒有寫 `/`，只是閘門把未知折成最壞情況、又把最壞情況
// 當成使用者寫的引數報出來。訊息描述使用者沒寫的東西，與文件描述程式沒有的行為是同一類缺
// 陷。路徑不可能含 NUL，所以這個前綴不會撞到真路徑。
// Written as an ESCAPE, never as a raw byte. install-hooks.sh verifies a
// candidate hook by handing the file's own text to `node -e` as an argv
// entry, and spawn(2) rejects an argument containing a NUL: a literal NUL in
// this file made the OpenCode runtime hook unverifiable, so the installer
// published its fail-closed replacement and refused every tool call. Caught by
// the installer suite, which is the only one that executes the file that way.
// 寫成跳脫序列，絕不寫成原始位元組。install-hooks.sh 驗證候選 hook 的方式是把檔案本文當成
// `node -e` 的一個 argv 傳進去，而 spawn(2) 拒絕含 NUL 的引數：檔案裡真的放一個 NUL
// 會讓 OpenCode runtime hook 驗不過，安裝程式於是發布 fail-closed 替代品，拒掉每一次工具呼叫。
const UNRESOLVED_TARGET = '\u0000unresolved:';

// The only variables this gate will resolve. Everything else stays unknown and
// is refused, which is the decided policy: a short allowlist buys back the
// commands people actually type without pretending the gate can predict a shell.
// PWD is taken from the tool call's own cwd rather than from the hook process's
// environment, because that is the directory the command will actually run in.
// 這個閘門唯一會解析的變數。其餘一律維持未知並拒絕，這是既定政策：一份短清單換回大家真的
// 會打的那些命令，同時不假裝閘門能預測 shell。PWD 取的是這次工具呼叫自己的 cwd，因為那才是
// 命令真正會執行的目錄。
const RESOLVABLE_VARIABLES = ['HOME', 'PWD', 'TMPDIR'];

// Substitute the allowlisted variables and report whether anything expansion
// shaped is left. Returns null when the word cannot be fully resolved, which
// keeps the old fail-closed answer for every shape this does not understand:
// `$(…)`, backticks, `$$`, `$1`, `$@`, `${VAR:-default}`, and any name not on
// the list. Matching is on the WHOLE name, so $HOMEBREW_PREFIX is not $HOME.
// 代入清單上的變數，並回報是否還剩下任何「長得像展開」的東西。不能完全解析就回 null，於是
// 這個函式看不懂的每一種形狀都維持原本的 fail-closed 答案。比對的是完整名稱，所以
// $HOMEBREW_PREFIX 不是 $HOME。
// Three of the guards below are REDUNDANT TODAY and are kept deliberately, the
// same way declaredLink() keeps its pair: `$(`, the `${ }` name shape and the
// allowlist membership test can each be deleted on their own without moving a
// single verdict -- `(` never matches the name pattern, an inner that is not a
// bare name is never a name on the list, and a name off the list has no value in
// expansionEnv, which the type test below already refuses. Each states a
// distinct policy in the code, and every one of them fails CLOSED, so a future
// edit that widens one of them still meets the next. Measured: mutating any one
// of the three leaves the whole suite green, which is why this paragraph exists
// instead of a test that cannot be written.
// RESOLVABLE_VARIABLES drifts in ONE DIRECTION ONLY, and the direction is the
// safe one. Removing a name from it stops that variable resolving (measured: the
// suite goes red), while ADDING one changes nothing at all, because
// resolvableEnvironment() builds the environment object with three names spelled
// out and a name with no value there is refused below. A name has to appear in
// BOTH places to be resolved, so a half-finished edit refuses rather than
// resolves. That is also why this list cannot be trusted as the answer to "what
// does this gate resolve": resolvableEnvironment() is.
// 底下有三道防線「今天是多餘的」，但刻意保留，與 declaredLink 保留它那一對的理由相同：
// `$(`、`${ }` 的名稱形狀、白名單成員檢查，任何一道單獨拿掉都不會改變任何一個判定。三者各自
// 在程式碼裡陳述一條不同的政策，而且全都是 fail closed，所以日後有人放寬其中一道，還會撞上
// 下一道。實測：單獨突變其中任何一道，整套測試都不會轉紅——所以寫成這段註解，而不是一個寫
// 不出來的測試。
// RESOLVABLE_VARIABLES 只會往一個方向漂移，而那是安全的方向：從清單裡「拿掉」名字，那個變數
// 就不再解析（實測會讓測試轉紅）；「加上」名字則完全沒有作用，因為 resolvableEnvironment 是
// 把三個名字逐一寫出來建出環境物件的，沒有值的名字在下面會被拒。名字必須同時出現在兩個地方
// 才會被解析，所以改到一半的編輯結果是「拒絕」而不是「解析」。也因此，要回答「這個閘門到底
// 解析什麼」，該看的是 resolvableEnvironment，不是這份清單。
function resolveKnownExpansions(word, expansionEnv) {
  if (!expansionEnv) return null;
  const text = String(word);
  let out = '';
  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];
    if (char === '`') return null;
    if (char !== '$') { out += char; continue; }
    const rest = text.slice(index + 1);
    if (rest.startsWith('(')) return null;
    let name = null;
    let consumed = 0;
    if (rest.startsWith('{')) {
      const close = rest.indexOf('}');
      if (close === -1) return null;
      const inner = rest.slice(1, close);
      // Anything but a bare name (`:-`, `#`, `%`, `[`, nested `$`) is a shell
      // operation this gate does not model.
      if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(inner)) return null;
      name = inner;
      consumed = close + 1;
    } else {
      const match = /^[A-Za-z_][A-Za-z0-9_]*/.exec(rest);
      // `$$`, `$1`, `$@`, `$*`, `$?`, `$-`, a trailing bare `$`: all unknown.
      if (!match) return null;
      name = match[0];
      consumed = match[0].length;
    }
    if (!RESOLVABLE_VARIABLES.includes(name)) return null;
    const value = expansionEnv[name];
    // An empty or relative value is not something to build a path out of: an
    // empty HOME would turn `$HOME/build` into `/build`, which is a different
    // and far more dangerous path than the one the user meant. Both are the one
    // test -- '' is not an absolute path -- and the type test in front of it is
    // not decoration: path.isAbsolute(undefined) THROWS, and a throw here is a
    // hook that exits non-zero on every command.
    // 空值或相對值不能拿來組路徑：HOME 是空的時候 `$HOME/build` 會變成 `/build`，那是一條
    // 與使用者本意完全不同、而且危險得多的路徑。兩者是同一個判斷（空字串不是絕對路徑）；前面
    // 的型別判斷也不是裝飾：path.isAbsolute(undefined) 會丟例外，而這裡一丟例外，整個 hook
    // 就會在每一條命令上非零結束。
    if (typeof value !== 'string' || !path.isAbsolute(value)) return null;
    // A value carrying whitespace is not one path. Unquoted, the shell SPLITS it
    // and hands rm several operands, so substituting it whole would judge a
    // string that no argument will ever equal: measured with TMPDIR='/tmp/x /etc',
    // `rm -rf $TMPDIR` removes /etc while the resolved single word '/tmp/x /etc'
    // is an ordinary unprotected path -- allowed, and it deletes. Quoted, the
    // value really is one operand, but this gate cannot see the quoting from
    // here, so the split reading is the one it has to assume. Refusing to
    // resolve puts the operand back where it was before this file resolved
    // anything: unknown, and refused.
    // 值裡有空白就不是「一條路徑」。沒加引號時 shell 會把它切開、交給 rm 好幾個操作元，整段代
    // 入等於在比對一個永遠不會等於任何一個引數的字串：實測 TMPDIR='/tmp/x /etc' 時
    // `rm -rf $TMPDIR` 會刪掉 /etc，而解出來的單一字 '/tmp/x /etc' 是普通的未受保護路徑，
    // 放行、而且真的刪。加了引號時它確實是一個操作元，但這裡看不到引號，只能假設會被切開。
    // 不解析就是把這個操作元放回這個檔案開始解析之前的位置：未知，而且拒絕。
    if (/\s/.test(value)) return null;
    out += value;
    index += consumed;
  }
  return out;
}

// The one place a target word becomes a target. A word with no expansion is
// itself; a word whose expansions all resolve is the resolved path, judged by
// the ORDINARY protected-path rules afterwards (so `rm -rf "$HOME"` is still
// refused and `rm -rf "$HOME/projects/x/build"` is not); anything else is
// unknown and refused.
// 一個「字」變成「目標」的唯一入口。沒有展開就是它自己；展開全部解得開就用解出來的路徑，
// 之後照舊走一般的受保護路徑判定；其餘一律未知並拒絕。
function targetFromWord(word, isDynamic, expansionEnv) {
  if (!hasUnresolvedTargetExpansion(isDynamic)) return word;
  const resolved = resolveKnownExpansions(word, expansionEnv);
  return resolved === null ? UNRESOLVED_TARGET + word : resolved;
}

// The value a variable has in THIS process is only the value the command will
// see if nothing in the command changes it first -- and a command can:
//   HOME=/ rm -rf "$HOME/etc"          the shell sets HOME for that command
//   cd /etc && rm -rf "$PWD"           PWD is whatever cd left behind
//   HOME=/ bash -c 'rm -rf "$HOME"'    the assignment is OUTSIDE the nested word
//                                      list, so a per-word check inside misses it
// The first of those was already a row in the suite before any of this, and it
// is what caught the first version of this resolution: taking the hook's own
// HOME made `HOME=/ rm -rf "$HOME/etc"` read as an ordinary subdirectory of the
// home directory while the command really removes /etc.
// So the question is asked of the WHOLE command text, once, before parsing. Text
// matching is crude and will occasionally disable resolution for a mention that
// is not an assignment (`echo "HOME=/x"`) -- and that is the right direction to
// be crude in, because the fallback is exactly the behaviour that shipped
// before: the operand stays unknown and is refused.
// 這個行程裡的變數值，只有在「命令本身不會先改掉它」時才等於命令看到的值，而命令改得掉。
// 上面第一種在這一切之前就已經是測試的一列，也正是它抓到這套解析的第一版：拿 hook 自己的
// HOME 去解，`HOME=/ rm -rf "$HOME/etc"` 會被讀成家目錄底下的普通子目錄，而它真正刪的是
// /etc。所以這個問題是對「整段命令文字」問一次、在解析之前問。文字比對很粗，偶爾會因為一
// 段不是賦值的文字而關掉解析——而這正是應該粗的方向，因為退路就是先前出貨的行為：操作元維
// 持未知並被拒絕。
// NOTE the HOME argument is `env.HOME` as given, NOT the `env.HOME ||
// os.homedir()` the protected-path check uses. Those answer different questions.
// The protected-path check asks "which directory is this machine's home", and
// os.homedir() is a fine answer. Resolution asks "what will `$HOME` expand to
// when this command runs", and there os.homedir() is a GUESS: a shell with HOME
// empty expands `$HOME/build` to `/build`, one level under the root, and
// substituting the real home would call that ordinary. An absent or empty HOME
// therefore resolves nothing and the operand stays unknown -- the behaviour that
// shipped before.
// 注意 HOME 這個引數是「原樣的 env.HOME」，不是受保護路徑判定用的 `env.HOME || os.homedir()`。
// 兩者回答的是不同問題：前者問「這台機器的家目錄是哪個」，os.homedir() 是好答案；解析問的是
// 「這條命令執行時 `$HOME` 會展開成什麼」，那裡 os.homedir() 只是猜測——HOME 是空的 shell 會
// 把 `$HOME/build` 展開成 `/build`，代進真正的家目錄反而會把它當成普通路徑。
function resolvableEnvironment(command, home, cwd, env) {
  const text = String(command || '');
  const mentionsAssignment = (name) => new RegExp(`(?:^|[^A-Za-z0-9_])${name}=`).test(text);
  // `unset`/`export`/`declare`/`typeset` can rewrite any of them without an
  // `=` in front of the name, and a directory change moves PWD.
  // unset/export/declare/typeset 不必在名字前面帶 `=` 就能改掉它們，而換目錄會移動 PWD。
  const rewritesAnything = /(?:^|[^A-Za-z0-9_-])(?:unset|export|declare|typeset)(?:[^A-Za-z0-9_-]|$)/.test(text);
  const changesDirectory = /(?:^|[^A-Za-z0-9_-])(?:cd|chdir|pushd|popd)(?:[^A-Za-z0-9_-]|$)/.test(text);
  const resolved = {};
  if (!rewritesAnything && !mentionsAssignment('HOME')) resolved.HOME = home;
  if (!rewritesAnything && !mentionsAssignment('TMPDIR')) resolved.TMPDIR = env.TMPDIR;
  if (!rewritesAnything && !mentionsAssignment('PWD') && !changesDirectory) resolved.PWD = cwd;
  return resolved;
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
// The cap has to bound the RECURSION, not just what the recursion pushes. It did
// not: every alternative's recursive call ran to completion before the cap was
// consulted, so the cost was 2^groups and the string `{a,b}` twenty-six times --
// 137 bytes -- took 6.8 seconds end to end, past the hook's 5,000 ms timeout.
// A timed-out PreToolUse hook is documented as rendering no decision and NOT
// blocking, so this was not a slow guard, it was an ABSENT one; and bash does
// not expand a QUOTED brace word at all, so a word inert to the shell could
// knock the gate out. Measured before the fix: `rm -rf '{a,b}x40' ; rm -rf /etc`
// exceeded 12 s and never answered, while the same pair with /etc first denied.
// 上限必須限制「遞迴」，不是只限制遞迴推進去的結果。原本每一個分支的遞迴呼叫都會整個
// 跑完才去看上限，成本是 2^群組數：`{a,b}` 重複 26 次（137 bytes）端到端要 6.8 秒，超過
// hook 的 5,000 ms 逾時。逾時的 PreToolUse hook 依官方文件不做任何裁決、也不會擋下工具
// 呼叫，所以那不是「慢」，是「不存在」；而 bash 根本不展開加了引號的大括號，於是一個對
// shell 完全無作用的字就能把閘門打掉。
function expandBraces(pattern, limit = 64) {
  if (limit <= 0) return { patterns: [], truncated: true };
  const open = pattern.indexOf('{');
  if (open === -1) return { patterns: [pattern], truncated: false };
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
  if (close === -1 || commas.length === 0) return { patterns: [pattern], truncated: false };
  const head = pattern.slice(0, open);
  const tail = pattern.slice(close + 1);
  const bounds = [open, ...commas, close];
  const patterns = [];
  for (let i = 0; i < bounds.length - 1; i += 1) {
    if (patterns.length >= limit) return { patterns, truncated: true };
    const alternative = pattern.slice(bounds[i] + 1, bounds[i + 1]);
    const nested = expandBraces(`${head}${alternative}${tail}`, limit - patterns.length);
    for (const expansion of nested.patterns) patterns.push(expansion);
    if (nested.truncated) return { patterns, truncated: true };
  }
  return { patterns, truncated: false };
}

// Does the bracket expression starting at `open` close, and where?
// A ']' immediately after '[' or '[!' is a literal, not the close.
function bracketEnd(pattern, open) {
  let i = open + 1;
  if (pattern[i] === '!' || pattern[i] === '^') i += 1;
  if (pattern[i] === ']') i += 1;
  while (i < pattern.length && pattern[i] !== ']') {
    // A `[:class:]` carries a ']' of its own; the bracket does not end there.
    if (pattern[i] === '[' && pattern[i + 1] === ':') {
      const classEnd = pattern.indexOf(':]', i + 2);
      if (classEnd !== -1) { i = classEnd + 2; continue; }
    }
    i += 1;
  }
  return i < pattern.length ? i : -1;
}

// POSIX character classes, because bash honours them inside a bracket and a
// guard that does not is answering a different question: measured,
// `rm -rf /et[[:alpha:]]` hands rm /etc.
// bash 在中括號裡認 POSIX 字元類別，不認的守衛回答的是另一個問題：實測
// `rm -rf /et[[:alpha:]]` 交給 rm 的就是 /etc。
const POSIX_CLASSES = {
  alpha: (c) => /[A-Za-z]/.test(c),
  digit: (c) => /[0-9]/.test(c),
  alnum: (c) => /[0-9A-Za-z]/.test(c),
  lower: (c) => /[a-z]/.test(c),
  upper: (c) => /[A-Z]/.test(c),
  space: (c) => /\s/.test(c),
  blank: (c) => c === ' ' || c === '\t',
  punct: (c) => /[!-/:-@[-`{-~]/.test(c),
  print: (c) => /[ -~]/.test(c),
  graph: (c) => /[!-~]/.test(c),
  cntrl: (c) => /[\x00-\x1f\x7f]/.test(c),
  xdigit: (c) => /[0-9A-Fa-f]/.test(c),
  word: (c) => /\w/.test(c),
};

function bracketMatches(spec, character) {
  let body = spec;
  let negated = false;
  if (body.startsWith('!') || body.startsWith('^')) {
    negated = true;
    body = body.slice(1);
  }
  let matched = false;
  for (let i = 0; i < body.length; i += 1) {
    if (body[i] === '[' && body[i + 1] === ':') {
      const end = body.indexOf(':]', i + 2);
      if (end !== -1) {
        const test = POSIX_CLASSES[body.slice(i + 2, end)];
        // An unknown class name is not ours to interpret; treat it as matching so
        // the verdict errs toward refusing rather than toward missing.
        if (!test || test(character)) matched = true;
        i = end + 1;
        continue;
      }
    }
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
  const expansion = expandBraces(basename);
  // A truncated expansion has words this never saw; one of them could be .git.
  if (expansion.truncated) return true;
  return expansion.patterns.some((pattern) => globMatchesPath(pattern, '.git'));
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

  const exactDirs = protectedEntries(home, extraDirs).map((item) => path.resolve(item));

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
    const expansion = expandBraces(normalized);
    // An expansion that hit the cap was not fully read, so one of the words this
    // guard never saw could be a protected path. Refuse rather than answer from a
    // partial list -- and nothing ordinary reaches this: 64 alternatives is far
    // past `report-{2024,2025}-{01,02,03}.csv`, and a word big enough to truncate
    // is one bash would expand into millions.
    // 展開撞到上限就代表沒讀完，沒看到的那些字裡可能就有受保護的路徑。寧可拒絕，也不要
    // 拿一份不完整的清單去回答。普通用法碰不到這裡。
    if (expansion.truncated) return normalized;
    for (const pattern of expansion.patterns) {
      // '..' is collapsed lexically here, and only here. Everywhere else in this
      // file a lexical collapse would be wrong, because '..' after a symlink
      // resolves onto the TARGET's parent -- but a pattern cannot be resolved at
      // all, so the choice is between collapsing and not asking: without it
      // `/Users/sieg/../*` is not recognised as `/Users/*`.
      // This comment used to end "collapsing can only make this rule match MORE
      // patterns, never fewer". That is FALSE and was measured false: with
      // `userlink -> /Users`, the shell reaches /Users from `userlink/../[U]sers`
      // while the collapse lands on `<cwd>/[U]sers` and the pattern is allowed --
      // the same path without the bracket is refused, by the resolution rules
      // that do get to ask the filesystem. Collapsing trades one class of miss
      // for another, and this is the class that stays open. Closing it needs a
      // pattern to be resolved against a filesystem, which is the one thing a
      // pattern cannot do before the shell expands it.
      // '..' 只在這裡做詞法折疊（本檔其他地方這樣做都是錯的，因為 '..' 經過 symlink 會落在
      // target 的父目錄），因為樣式根本無法解析，選擇只有「折疊」或「不問」。
      // 這段註解原本結尾寫「折疊只會讓規則 match 更多、不會更少」——那是錯的，而且已被實測
      // 推翻：`userlink -> /Users` 時，shell 從 `userlink/../[U]sers` 會走到 /Users，而折疊
      // 落在 `<cwd>/[U]sers`，於是放行。這一類仍是開著的。
      const absolute = path.posix.normalize(pattern.startsWith('/') ? pattern : `${base}/${pattern}`);
      const patternBase = absolute.slice(absolute.lastIndexOf('/') + 1);
      if (globMatchesPath(patternBase, '.git')) return normalized;
      if (exactDirs.some((directory) => globMatchesPath(absolute, directory))) return normalized;
      // A pattern whose PARENT is protected selects that directory's entire
      // contents. `rm -rf /etc/*` hands rm all 79 entries of /etc (measured) --
      // /etc/sudoers, /etc/master.passwd, /etc/ssh -- and `rm -rf ~/*` empties
      // the home directory. Both were refused before this round, by the blanket
      // "any dir/* could select .git" rule that was replaced here for being
      // wrong about dotfiles; that rule was over-broad AND was the only thing
      // standing between the agent path and these. Asking about the parent keeps
      // them refused without bringing the over-refusal back: `dist/*` has an
      // unprotected parent and stays ordinary.
      // The parent is matched as a PATTERN too, so `/Vol*/Coca` -- measured, bash
      // hands rm the mounted volume /Volumes/Coca -- and `/S*/V*/Data` are read
      // for what they can name rather than for how they are spelled.
      // 父目錄受保護的樣式，選中的是那個目錄的全部內容：`rm -rf /etc/*` 實測會把 /etc 底下
      // 79 個項目全部交給 rm，`rm -rf ~/*` 則清空家目錄。這兩個在本輪之前是被擋的——擋它們
      // 的正是那條「凡 dir/* 都可能選到 .git」的粗規則，而那條規則同時是錯的、也是 agent
      // 路徑上唯一擋住這些的東西。改問父目錄，就能留住這份保護而不把誤擋帶回來。父目錄本身
      // 也當樣式比對，所以 `/Vol*/Coca`（實測交給 rm 的是掛載中的 /Volumes/Coca）也算。
      const patternParent = absolute.slice(0, absolute.lastIndexOf('/')) || '/';
      if (exactDirs.some((directory) => globMatchesPath(patternParent, directory))) return normalized;
      if (MOUNT_PARENTS.some((parent) => globMatchesPath(patternParent, parent))) return normalized;
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
  for (const entry of protectedEntries(home, extraDirs)) {
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

function commandTargets(command, depth = 0, bodiesAreCodeFromCaller = false, expansionEnv = null) {
  const words = shellWords(command);
  const dynamicExpansions = words.dynamicExpansions || [];
  // Which words were written as unquoted shell operators. Only the find branch
  // consults it, and only for `;`: everywhere else a separator-shaped word is
  // treated as a separator exactly as before, which keeps this change to the one
  // question that needed answering.
  // 哪些字是「未加引號的 shell 運算子」。只有 find 那一支會問，而且只問 `;`：其他地方對長得
  // 像分隔符的字照舊當分隔符，這個改動就只回答需要回答的那一個問題。
  const operatorTokens = words.operatorTokens || [];
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
  // A heredoc body is data because of what its command does with it -- and the
  // command that READS a heredoc is not always the one that RUNS it. Measured,
  // all nine refused before this round and allowed after it until this block:
  //   cat <<EOF | bash          cat <<'EOF' | sudo bash     source /dev/stdin <<EOF
  //   eval "$(cat <<'EOF' … )"  bash -c "$(cat <<'EOF' … )" bash < <(cat <<EOF … )
  // Asking only whether the heredoc's OWN command is a shell missed every one.
  // So when a shell appears anywhere in COMMAND POSITION in this command line,
  // every body in it is read as code as well. Command position matters: it keeps
  // `grep bash <<'EOF'` -- where bash is a search string -- data.
  // heredoc 內文之所以是資料，取決於它的命令拿它做什麼；而「讀」heredoc 的命令未必是「執
  // 行」它的那個。只問 heredoc 自己的命令是不是 shell，上面九種全都漏掉。因此只要這條命令
  // 列裡有 shell 出現在「命令位置」，裡面每一段內文就同時當程式碼讀。限定命令位置是為了讓
  // `grep bash <<'EOF'`（bash 是搜尋字串）維持資料。
  // The flag is INHERITED into command substitutions, because the shell that
  // runs the body can sit outside them: in `eval "$(cat <<'EOF' … )"` the
  // heredoc belongs to `cat`, which is not a carrier, while the thing that
  // executes the result is the `eval` one level up. Without inheriting, that
  // shape was the last row still more permissive than the pushed baseline.
  // 這個旗標會被帶進命令替換裡，因為真正執行內文的 shell 可能在外面：
  // `eval "$(cat <<'EOF' … )"` 的 heredoc 屬於 cat（不是 carrier），執行它的是外面那個
  // eval。不往下傳的話，這一種形狀就是最後一列仍比已推送基準寬鬆的。
  const bodies = words.heredocs || [];
  const carriers = new Set([...shellCarriers, 'eval', 'source', '.']);
  const transparent = new Set([
    'sudo', 'env', 'command', 'builtin', 'nohup', 'setsid', 'exec', 'time',
    'nice', 'timeout', '!', 'coproc', 'noglob',
  ]);
  let carrierPresent = bodiesAreCodeFromCaller;
  if (!carrierPresent) {
    let atCommandPosition = true;
    for (const word of words) {
      if (separators.has(word)) { atCommandPosition = true; continue; }
      if (!atCommandPosition) continue;
      const name = path.basename(word);
      if (carriers.has(name)) { carrierPresent = true; break; }
      if (transparent.has(name) || /^[A-Za-z_][A-Za-z0-9_]*=/.test(word)) continue;
      atCommandPosition = false;
    }
  }
  if (carrierPresent) {
    for (const entry of bodies) {
      if (depth >= 8) targets.push('/');
      else targets.push(...commandTargets(entry.body, depth + 1, true, expansionEnv));
    }
  }

  const substitutions = commandSubstitutions(scannable);
  if (substitutions.length > 0) {
    if (depth >= 8) targets.push('/');
    else {
      for (const nested of substitutions) {
        targets.push(...commandTargets(nested, depth + 1, carrierPresent, expansionEnv));
      }
    }
  }
  // Wrapper commands can be chained arbitrarily (for example
  // `sudo env SAFE=1 command bash -c ...`). Unwrap each layer until the
  // actual executable is reached; every branch advances i, so malformed
  // wrapper-only input remains bounded.
  // The command `find` runs through -exec wears exactly these wrappers and
  // deletes exactly the same, so it asks this same function rather than re-
  // reading the word after -exec: `find /etc -exec sudo rm -rf {} \;` deletes
  // /etc just as `find /etc -exec rm -rf {} \;` does, and matching only the
  // bare word saw `sudo`, called that find a reader, and allowed it (measured,
  // together with `-exec nice rm` and `-exec env SAFE=1 command rm`). A second
  // copy of this list is the thing that would drift, so there is one.
  // find 用 -exec 跑的命令戴的就是這一族外殼，刪的東西一模一樣，所以它問同一個函式，而不是
  // 自己再讀一次 -exec 後面那個字：只比對裸字會看到 sudo，就把這個 find 當成讀取工具放行
  // （實測 `-exec nice rm`、`-exec env SAFE=1 command rm` 也一樣放行）。抄第二份清單就是
  // 日後會走鐘的那一份，所以只留一份。
  function resolveExecutable(start) {
    let i = start;
    let executable = '';
    let executableIndex = -1;
    // Set when a wrapper hands the command its operands on stdin (xargs), where
    // the paths are unknowable before the command runs.
    let stdinCompletesOperands = false;
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
            else if (splitString) targets.push(...commandTargets(splitString, depth + 1, false, expansionEnv));
            i += 2;
          } else if (option.startsWith('--split-string=')) {
            const splitString = option.slice('--split-string='.length);
            if (depth >= 8) targets.push('/');
            else if (splitString) targets.push(...commandTargets(splitString, depth + 1, false, expansionEnv));
            i += 1;
          } else if (option.startsWith('-S') && option.length > 2) {
            const splitString = option.slice(2);
            if (depth >= 8) targets.push('/');
            else targets.push(...commandTargets(splitString, depth + 1, false, expansionEnv));
            i += 1;
          } else if (/^-[iv]*S.+/.test(option)) {
            const splitString = option.replace(/^-[iv]*S/, '');
            if (depth >= 8) targets.push('/');
            else targets.push(...commandTargets(splitString, depth + 1, false, expansionEnv));
            i += 1;
          } else if (/^-[iv]*S$/.test(option)) {
            const splitString = words[i + 1] || '';
            if (depth >= 8) targets.push('/');
            else if (splitString) targets.push(...commandTargets(splitString, depth + 1, false, expansionEnv));
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
        // timeout's first non-option operand is the duration. This is the one
        // step in this function that consumes a word WITHOUT looking at it, so
        // it is the one that can swallow a `+` -- which ends a find -exec clause
        // exactly as `;` does, and is not a separator, so nothing downstream
        // notices. Measured, all DENY before the -exec branch began skipping
        // consumed clauses and ALLOW after, and this one really deletes: in a
        // sandbox `find /etc -exec timeout -s {} + ! -delete` emptied the tree on
        // both BSD find and bfs (timeout dies on the signal name, `-delete` runs
        // anyway). It defeats the whole file, not this branch: the same shape
        // inside `$(…)`, `bash -c`, `eval` and a heredoc was allowed too.
        // A duration is never `+` -- timeout's operand is unsigned -- so
        // declining to eat one costs nothing: `timeout 30 pytest` and
        // `timeout -k 5 10 ls` are unchanged.
        // The fix belongs HERE and not in the -exec clause skip: `+` cannot join
        // `terminators`, because that stops the jump without ending the find
        // loop, so the wrapper scan is re-entered once per clause and the
        // quadratic comes straight back (measured 40,561ms at N=20,000, eight
        // times the hook's own 5s timeout).
        // timeout 的第一個非選項操作元是逾時值。這是本函式裡唯一「不看內容就吃掉一個字」的
        // 步驟，也就是唯一可能把 `+` 吞掉的地方——而 `+` 與 `;` 一樣會結束 find 的 -exec
        // 子句，又不是 separator，後面沒有人會發現。實測這一種真的會刪：sandbox 裡
        // `find /etc -exec timeout -s {} + ! -delete` 在 BSD find 與 bfs 上都把整棵樹清空。
        // 逾時值不可能是 `+`（它是無號的），所以不吃它零成本。
        // 修在這裡而不是修在子句跳躍那邊：`+` 不能加進 terminators，那樣只會擋住跳躍卻沒有
        // 結束 find 迴圈，外殼掃描就會每個子句重進一次，平方級立刻回來（實測 N=20,000 時
        // 40,561ms，是 hook 自己 5 秒逾時的八倍）。
        if (i < words.length && !separators.has(words[i]) && words[i] !== '+') i += 1;
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
    return { executable, executableIndex, index: i, stdinCompletesOperands };
  }

  let i = 0;

  while (i < words.length) {
    while (i < words.length && separators.has(words[i])) i += 1;
    if (i >= words.length) break;
    if (controlWords.has(words[i])) {
      i += 1;
      continue;
    }
    const {
      executable, executableIndex, index, stdinCompletesOperands,
    } = resolveExecutable(i);
    i = index;

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
          else targets.push(...commandTargets(candidate, depth + 1, false, expansionEnv));
        }
        if (!candidate.startsWith('-') || candidate === '-') {
          targets.push(
            targetFromWord(candidate, dynamicExpansions[i], expansionEnv)
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
        else targets.push(...commandTargets(nestedCommand, depth + 1, false, expansionEnv));
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
      // Options come BEFORE the paths on BSD find (-x -d -s -E -H -L -P, and -f
      // whose operand IS a path). Stopping at the first '-' made `find -x /etc
      // -delete` collect no roots at all and fall back to '.', so the one path it
      // was given went unjudged -- measured, that command deletes /etc.
      // BSD find 的選項排在路徑前面（-f 的操作元本身就是路徑）。碰到第一個 '-' 就停下，會
      // 讓 `find -x /etc -delete` 一個 root 都沒收到、退回 '.'，於是它拿到的那條路徑根本
      // 沒被判——實測那條命令會刪掉 /etc。
      const leadingOptions = new Set(['-x', '-d', '-s', '-E', '-H', '-L', '-P', '-h', '-X']);
      while (i < words.length && !terminators.has(words[i])) {
        // A root that only exists after expansion is unknowable, exactly as an rm
        // operand is: `find $DIR -delete` and `find "$DIR" -delete` both delete
        // (measured), and the rm branch already folds that shape to '/'. The find
        // branch pushed the raw word, so the same unknowable got two answers.
        // 展開後才知道的 root 與 rm 的操作元一樣不可知：`find $DIR -delete` 與
        // `find "$DIR" -delete` 實測都會刪。rm 那邊早就把這種形狀折成 '/'，find 這邊卻推
        // 原字，同一種不可知得到兩種答案。
        const asRoot = (index) => targetFromWord(words[index], dynamicExpansions[index], expansionEnv);
        if (words[i] === '-f') {
          if (i + 1 < words.length && !terminators.has(words[i + 1])) searchRoots.push(asRoot(i + 1));
          i += 2;
          continue;
        }
        if (leadingOptions.has(words[i])) { i += 1; continue; }
        if (words[i].startsWith('-')) break;
        searchRoots.push(asRoot(i));
        i += 1;
      }
      const execOperands = [];
      for (; i < words.length; i += 1) {
        if (terminators.has(words[i])) {
          // The `;` that closes an -exec clause has to be hidden from the shell,
          // so it is written `\;` or `';'` -- and the tokenizer turns all three
          // spellings into the same one-character word. Only the bare one ends
          // the command; the escaped and quoted ones end the CLAUSE and the find
          // keeps going. Reading them all as "the command ends here" made every
          // find operator after the first clause invisible, and the natural
          // spelling of the shape is the one that deletes:
          //   find /etc -exec cat {} \; -delete
          // measured DENY nowhere and a real BSD find emptying the tree (4 files
          // -> 0). It needed no wrapper and no trick, and it was allowed at every
          // revision in this round until here, including against `/`, `~`, `.git`
          // and BETTER_RM_PROTECTED_DIRS.
          // 收掉 -exec 子句的那個 `;` 必須躲開 shell，所以要寫成 `\;` 或 `';'`——而斷詞器把
          // 三種拼寫都變成同一個單字元字。只有裸的那個會結束命令；跳脫與加引號的那兩個結束
          // 的是「子句」，find 還會繼續。把三者都當成「命令到此為止」，會讓第一個子句之後
          // 的每一個 find 運算子都變成隱形，而這個形狀最自然的拼寫正好就會刪東西（實測真的
          // BSD find 把整棵樹清空，4 個檔案變 0）。
          if (words[i] !== ';' || operatorTokens[i]) break;
          continue;
        }
        if (words[i] === '-delete') deletes = true;
        // The word after -exec is the command find runs, and it can wear the
        // same wrapper layers any other command can. Comparing that one word
        // against rm/rmdir saw `sudo`, `nice`, `env` -- none of them rm -- and
        // called the find a reader: measured, `find /etc -exec sudo rm -rf {} \;`
        // was allowed and deletes /etc. It calls resolveExecutable, the same
        // unwrapper command position uses -- the wrapper LIST is now shared, but
        // the DECISION is not: command position also fails closed on an
        // unresolvable command word, on operands arriving via xargs, and it
        // descends into shell carriers, none of which this branch does. So
        // `find . -exec sh -c 'rm -rf /etc' \;` and `-exec $CMD -rf /etc` are
        // still allowed here while the same words in command position are not.
        // -exec 後面那個字是 find 要跑的命令，而它可以戴上任何命令都能戴的外殼。拿那一個字
        // 去比對 rm/rmdir，看到的是 sudo、nice、env，沒有一個是 rm，於是把這個 find 判成
        // 讀取工具：實測 `find /etc -exec sudo rm -rf {} \;` 被放行，而它會刪掉 /etc。
        // 共用的是「外殼清單」，不是「判定」：命令位置還會對不可知的命令字、xargs 從 stdin
        // 補上的操作元失效關閉，也會鑽進 shell carrier，這一支都沒有。
        const execCommand = ['-exec', '-execdir', '-ok', '-okdir'].includes(words[i])
          ? resolveExecutable(i + 1)
          : null;
        if (execCommand) {
          // Where this -exec clause ends. Everything from here to that point is
          // the exec'd command's own argv, which find does not re-read for
          // operators -- and neither may this loop, or the work is quadratic.
          // Measured, each row a command that DELETES and a gate that answered
          // too late or not at all (the live hook's timeout is 5s):
          //   find . + '-exec sudo '*6000  ->  5,525ms   (this branch, before)
          //   find . + '-exec rm '*6000    -> 210,178ms  (operand scan, and the
          //                                   SAME 210s at b66f502 -- older than
          //                                   the wrapper hole this round fixed)
          // A hook that times out is a hook that did not answer, and the padding
          // is inert: it costs the attacker nothing and suppresses every rule in
          // this file, not just this branch. So each clause is consumed once.
          // 這個 -exec 子句到哪裡結束。從這裡到那一點都是被執行命令自己的 argv，find 不會
          // 再把它們當運算子讀，這個迴圈也不可以，否則就是平方級。實測兩列都是「會刪東西、
          // 而閘門太慢或根本沒答」（live hook 逾時 5 秒），且第二列在 b66f502 就有，比這一
          // 輪修掉的外殼漏洞更老。逾時的閘門等於沒有閘門，而填充料是惰性的。
          let clauseEnd = execCommand.index;
          if (['rm', 'rmdir'].includes(execCommand.executable)) {
            deletes = true;
            // The exec command has operands of its own, and they are not the search
            // roots: `find . -exec rm -rf /etc \;` runs rm on /etc once per file
            // found (measured). Judging only the roots read the wrong argument.
            // exec 那個命令自己也有操作元，而它們不是搜尋起點：`find . -exec rm -rf /etc \;`
            // 每找到一個檔案就對 /etc 跑一次 rm（實測）。只判 roots 是讀錯了引數。
            // The operand scan starts after the UNWRAPPED command word, so a
            // wrapper's own arguments (`sudo -u root`) are not read as rm targets.
            // 掃描從拆完外殼的那個命令字之後開始，外殼自己的引數不會被當成 rm 的目標。
            for (
              clauseEnd = execCommand.index + 1;
              clauseEnd < words.length
                && !terminators.has(words[clauseEnd])
                && words[clauseEnd] !== '+';
              clauseEnd += 1
            ) {
              if (words[clauseEnd] === '{}' || words[clauseEnd].startsWith('-')) continue;
              execOperands.push(
                targetFromWord(words[clauseEnd], dynamicExpansions[clauseEnd], expansionEnv),
              );
            }
          }
          // Never jump over a terminator. resolveExecutable stops AT a separator
          // when it reads one as a word, but its option-with-value branches step
          // two words at a time without looking, so an option written with its
          // value MISSING eats the separator as that value and reports a clause
          // end on the far side of it. Landing there would resume the find scan
          // past the end of the find, and the command after the separator would
          // never be parsed by anything -- every rule in this file, not just this
          // branch. Measured, all DENY before this round and ALLOW with the
          // unclamped jump, all real commands the shell splits and runs:
          //   find . -exec timeout -k ; rm -rf /       find . -exec sudo -u ; find /etc -delete
          //   find . -exec nice -n | bash -c 'rm -rf /etc'
          // 34 option spellings across sudo/env/nice/timeout/time/exec/xargs can
          // do it, and `timeout` is the worst because it eats a second word as
          // the duration -- a bare `rm -rf /etc` behind it was allowed too.
          // So the jump is clamped to the first terminator in the span. That
          // keeps it linear: the clamp scan and the loop each visit a word once.
          // 絕不跳過終止符。resolveExecutable 讀到「當成字的分隔符」時會停，但它那些「選項
          // 帶值」的分支是不看內容就 i += 2，於是一個「值被省略」的選項會把分隔符當成值吃
          // 掉，回報的子句結尾落在分隔符的另一邊。停在那裡等於讓 find 的掃描越過 find 本身
          // 的結尾，分隔符後面那條命令就再也沒有人解析——失效的是整個檔案的每一條規則，不只
          // 這一支。實測上面三條在這一輪之前全是 DENY、不夾限就全變 ALLOW，而且都是 shell
          // 會拆開並執行的真命令；34 種選項拼寫做得到，其中 timeout 最糟（它還多吃一個字當
          // 逾時值，連裸的 `rm -rf /etc` 都會被放行）。夾限到區間內第一個終止符即可，而且
          // 仍是線性的：夾限掃描與主迴圈各只走過每個字一次。
          let clauseStop = clauseEnd;
          for (let k = i + 1; k < clauseStop && k < words.length; k += 1) {
            if (terminators.has(words[k])) { clauseStop = k; break; }
          }
          // `- 1` because this loop's own header increments before it re-tests:
          // landing ON the terminator is what lets the test see it. Without it
          // the clamp is a no-op, which is how the first attempt at this failed.
          // `- 1` 是因為本迴圈的標頭會先加一才重測：要「停在終止符上」才看得到它。少了它這
          // 個夾限就是空操作——第一次寫的時候就是這樣，什麼都沒修到。
          if (clauseStop - 1 > i) i = clauseStop - 1;
        }
      }
      if (deletes) {
        // GNU find defaults to the working directory when no path is given.
        const roots = searchRoots.length > 0 ? searchRoots : ['.'];
        for (let r = 0; r < roots.length; r += 1) targets.push(roots[r]);
        for (const operand of execOperands) targets.push(operand);
      }
    } else if (executable === 'eval') {
      const nestedCommand = [];
      for (; i < words.length && !separators.has(words[i]); i += 1) {
        nestedCommand.push(words[i]);
      }
      if (nestedCommand.length > 0) {
        if (depth >= 8) targets.push('/');
        else targets.push(...commandTargets(nestedCommand.join(' '), depth + 1, false, expansionEnv));
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

// The refusal for a target this gate could not work out. It must NOT borrow the
// protected-directory wording: the command did not name a protected directory,
// and reporting `/` as the argument sent people looking for a `/` they never
// wrote. Name the operand that could not be resolved, say plainly that the
// answer is unknown rather than dangerous, and give the way through -- `cd` to
// the directory and name the target relatively, which contains no expansion and
// is judged literally.
// 這是「算不出來」的拒絕，不能借用受保護目錄那套措辭：命令並沒有寫到受保護目錄，把 `/` 當
// 成引數報出來，只會讓人去找一個他從來沒寫過的 `/`。要指名解不開的那個操作元、直說答案是
// 未知而不是危險，並給出繞法：`cd` 過去、用相對路徑寫，那裡沒有展開，會被逐字判定。
// How long this gate will spend judging targets before it refuses instead of
// answering. A single target costs a bounded amount of work, but the NUMBER of
// targets is the caller's to choose, and each one costs up to three filesystem
// calls -- twenty-six when the target is a symlink, because that is when
// declaredLink() has to compare it against every declared entry.
// Measured on this machine, all against a `/etc` that really is removed, and all
// against the live 5,000 ms hook timeout (a PreToolUse hook that times out makes
// NO decision and does not block the call, so a slow gate is an absent one):
//   rm -rf <60,000 relative symlink operands> /etc   6,215 ms at d3aed08, 300 KB
//   rm -rf <60,000 "$PWD"/link operands> /etc        4,386 ms here,      720 KB
//   rm -rf <260,000 "$HOME"/pad-N operands> /etc     4,584 ms here,      4.8 MB
// The first of those is older than this budget and older than variable
// resolution: judging every operand is what this gate has always done, and the
// number of operands was never bounded. Resolution did not open that door, it
// only made the variable spelling as expensive as the literal one always was.
// A TIME budget rather than a target COUNT, because the cost per target spans
// two orders of magnitude and a count cannot tell the two apart: measured, a
// count cap of 5,000 refused `find . -exec rm ...x6000` -- 6,001 targets, 118 ms,
// a command that deletes nothing and that this suite pins as ordinary -- while
// letting through shapes that cost far more. The budget refuses only what really
// cannot be judged in time, and it adapts to a machine slower than this one.
// What it does NOT cover, stated rather than left to be found: the tokenizing
// pass that produces the targets runs before the first check, at roughly 40 ms
// per megabyte of command text (measured, 316 ms for 4.8 MB), so a command large
// enough to outrun the timeout on parsing alone is not stopped here.
// 這個閘門在「改成拒絕」之前，最多花多少時間判定目標。單一目標的成本有上限，但目標「數量」
// 由呼叫端決定，而每個目標最多三次檔案系統呼叫——是 symlink 時二十六次，因為那時 declaredLink
// 必須拿它跟每一個宣告項目比對。上面三列都是實測、刪的都是真的 /etc；live hook 逾時是
// 5,000 ms，而逾時的 PreToolUse hook 不做任何裁決、也不會擋下呼叫，所以「慢」等於「不存在」。
// 第一列比這個預算、也比變數解析更老：逐一判定每個操作元一直是這個閘門的做法，數量從來沒有
// 上限。用「時間」而不是「數量」，是因為每個目標的成本差兩個數量級，數量分不出來：實測 5,000
// 的數量上限會擋掉 `find . -exec rm …x6000`（6,001 個目標、118 ms、什麼都不刪，而且本測試
// 套件把它釘為普通命令），卻放過成本高得多的形狀。時間預算只擋真的判不完的東西，而且在比這
// 台更慢的機器上會自動調整。它「不」涵蓋的部分明講：產生目標的斷詞在第一次檢查之前就跑完，
// 成本約每 MB 40 ms（實測 4.8 MB 為 316 ms），所以光靠斷詞就跑贏逾時的巨大命令，這裡擋不住。
const JUDGING_BUDGET_MS = 2000;

// The refusal for a command this gate ran out of time on. It is not a
// protected-directory refusal and it is not an unresolved-variable one: the
// operands may all be ordinary, and the gate is saying it stopped reading.
// Saying so is the whole point -- the alternative is running out of time, which
// on a PreToolUse hook is not a refusal at all.
// 閘門「時間用完」時的拒絕。它既不是受保護目錄、也不是解不開的變數：那些操作元可能全都很普
// 通，閘門只是說「我停止讀了」。說出來正是重點——另一條路是超時，而超時在 PreToolUse hook 上
// 根本不算拒絕。
function unjudgeableDenial(judgedCount, totalCount, isCopilot, isAntigravity, isCursor, isGrok) {
  const zh = `拒絕刪除：這條命令有 ${totalCount} 個刪除目標，這道閘門在 ${JUDGING_BUDGET_MS}ms 內`
    + `只判定了 ${judgedCount} 個，其餘沒有讀到。逾時的 PreToolUse hook 不會做出任何裁決，`
    + `也就不會擋下命令，所以這裡選擇拒絕而不是來不及回答。`
    + `繞法：拆成多條命令，或改成刪除它們的上層目錄。`;
  const en = `Refused to remove: this command has ${totalCount} deletion targets and this gate`
    + ` judged ${judgedCount} of them within ${JUDGING_BUDGET_MS}ms; the rest went unread.`
    + ` A PreToolUse hook that times out makes no decision and does not block the command,`
    + ` so this refuses rather than answering too late.`
    + ` Workaround: split it into several commands, or remove their parent directory instead.`;
  return denialShape(`${zh} / ${en}`, isCopilot, isAntigravity, isCursor, isGrok);
}

// The refusal for an operand this gate could not work out. The way through it
// offers has to be a shape the gate still JUDGES. The one this message used to
// carry -- `cd <dir> && rm -rf <relative path>` -- is the opposite: the verdict
// is made from command text against the tool call's cwd and nothing threads a
// `cd` through it, so measured from any cwd but the home directory,
// `cd ~ && rm -rf .ssh` produces no decision at all and /bin/rm runs with no
// trash copy. That shape walks past every declared entry, not just this one, so
// a refusal recommending it was the gate teaching its own bypass. A literal
// absolute path is judged by the ordinary rules, which is the whole reason to
// ask for one.
// 這是「算不出來」時的拒絕。它給的下一步必須是這道閘門仍然會判定的形狀。原本那句
// （`cd <目錄> && rm -rf <相對路徑>`）正好相反：判定是拿命令文字對著呼叫端的 cwd 做的，沒有
// 任何地方把 `cd` 串進去，所以實測在家目錄以外的任何 cwd 下，`cd ~ && rm -rf .ssh` 根本不
// 產生裁決，/bin/rm 就直接跑了，連垃圾桶副本都沒有。那個形狀打穿的是每一個宣告項目，不只
// 這一個，所以推薦它的拒絕訊息等於閘門自己教人繞過自己。字面的絕對路徑會照一般規則判定，
// 這正是要求它的理由。
function unknownDenial(operand, isCopilot, isAntigravity, isCursor, isGrok) {
  const zh = `拒絕刪除：無法在執行前確定 '${operand}' 會展開成哪一條路徑，因此不予放行`
    + `（這不是說它是受保護的目錄，是說這道閘門不知道它是什麼）。`
    + `目前只會解析 $HOME、$PWD、$TMPDIR。`
    + `繞法：把目標改寫成字面的絕對路徑，例如 rm -rf /home/you/build，它就會照一般規則被判定；`
    + `若那條路徑要到執行時才存在，就把這個操作放進腳本檔裡執行。`;
  const en = `Refused to remove: cannot determine before execution which path '${operand}' expands to`
    + ` (this does not say it is a protected directory; it says this gate does not know what it is).`
    + ` Only $HOME, $PWD and $TMPDIR are resolved.`
    + ` Workaround: spell the target as a literal absolute path, e.g. rm -rf /home/you/build, which is`
    + ` judged by the ordinary rules; if the path only exists at run time, put the operation in a script file.`;
  return denialShape(`${zh} / ${en}`, isCopilot, isAntigravity, isCursor, isGrok);
}

function denial(reason, isCopilot, isAntigravity, isCursor, isGrok) {
  const message = `拒絕刪除受保護的目錄：${reason} / Refused to remove protected directory: ${reason}`;
  return denialShape(message, isCopilot, isAntigravity, isCursor, isGrok);
}

// Every agent's own deny shape, in one place, so a new refusal reason cannot
// accidentally support fewer agents than the old one.
// 各家 agent 的拒絕格式集中在一處，新的拒絕理由才不會比舊的少支援幾家。
function denialShape(message, isCopilot, isAntigravity, isCursor, isGrok) {
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

  // The values the allowlisted variables really have for THIS call. HOME is the
  // one the rest of this file already trusts; PWD is the tool call's own cwd,
  // which is where the command will run, not the hook process's directory.
  // 這次呼叫裡那幾個允許解析的變數真正的值。HOME 與本檔案其他地方用的是同一個；PWD 取這次
  // 工具呼叫自己的 cwd，那才是命令會執行的地方，而不是 hook 行程的目錄。
  const expansionEnv = resolvableEnvironment(command, env.HOME, cwd, env);

  // Two passes on purpose. A command can name a genuinely protected path AND
  // carry a variable this gate cannot resolve; the protected path is the more
  // useful thing to be told about, so it wins the message. Both refuse either
  // way -- the order decides what the user reads, not whether it is denied.
  // 刻意分兩輪。一條命令可能同時寫了真正受保護的路徑，又帶著這個閘門解不開的變數；對使用者
  // 更有用的是前者，所以由它決定訊息。兩者都會拒絕，順序只決定使用者看到什麼。
  const targets = commandTargets(command, 0, false, expansionEnv);
  const deadline = Date.now() + JUDGING_BUDGET_MS;
  let judged = 0;
  for (; judged < targets.length; judged += 1) {
    // The clock is read on EVERY target, so the budget can be overrun by at most
    // one target rather than by 64 of them.
    // It was read once every 64 before, on the measurement that 64 of the most
    // expensive target cost about 5 ms. That figure holds only while a target's
    // cost is bounded by an ordinary local filesystem, and the gate does not get
    // to choose the filesystem. Measured here with HOME on this Mac's autofs
    // /home -- one lstat under it costs 9.7 ms against 0.001 ms under /Users,
    // because every lookup goes through automountd -- one symlink target costs
    // 28.8 ms, so a 64-target block is 1,843 ms and the 2,000 ms budget was
    // overrun to 3,687 ms: 120,000 symlink operands answered in 3,921 ms against
    // a live 5,000 ms timeout, and a PreToolUse hook that times out makes no
    // decision and does not block the command. Reading the clock every target
    // brought the same command to 2,435 ms.
    // The cost of reading it that often is measured, not assumed: 20,000 cheap
    // targets took 286 ms with the 64-target mask and 281 ms without it -- one
    // Date.now() per target is inside the noise, because even the cheapest target
    // is three orders of magnitude more expensive than reading a clock.
    // 每一個目標都讀時鐘，於是預算最多只會被超出「一個目標」而不是 64 個。
    // 先前每 64 個讀一次，依據是「最貴的目標 64 個約 5 ms」——那個數字只在「單一目標的成本被
    // 一顆普通本機磁碟框住」時成立，而這道閘門無權選擇檔案系統。實測：HOME 落在這台 Mac 的
    // autofs /home 時，底下一次 lstat 要 9.7 ms（/Users 底下是 0.001 ms，差別在每次查找都要
    // 經過 automountd），一個 symlink 目標就要 28.8 ms，64 個是 1,843 ms，2,000 ms 的預算被
    // 撐到 3,687 ms：120,000 個 symlink 操作元耗時 3,921 ms，而 live 逾時是 5,000 ms，逾時的
    // PreToolUse hook 不做任何裁決、也不會擋下命令。改成每個目標都讀，同一條命令降到 2,435 ms。
    // 讀這麼頻繁的成本是實測的、不是假設的：20,000 個便宜目標，有 64 的遮罩是 286 ms，沒有是
    // 281 ms——一個目標讀一次時鐘落在雜訊裡，因為連最便宜的目標都比讀一次時鐘貴三個數量級。
    if (Date.now() > deadline) break;
    const target = targets[judged];
    if (target.startsWith(UNRESOLVED_TARGET)) continue;
    const reason = protectedReason(target, cwd, home, extraDirs);
    if (reason) return denial(reason, isCopilot, isAntigravity, isCursor, isGrok);
  }
  // Out of time with targets left. A protected path found BEFORE the budget ran
  // out still wins the message, because that is the useful thing to be told;
  // everything after it is unread, and unread is refused.
  // 時間用完而目標還有剩。預算用完之前找到的受保護路徑仍然決定訊息（那才是有用的資訊），之後
  // 的都沒有讀到，而沒有讀到就是拒絕。
  if (judged < targets.length) {
    return unjudgeableDenial(judged, targets.length, isCopilot, isAntigravity, isCursor, isGrok);
  }
  // Reached only when every target was judged: the branch above returns
  // otherwise, so there is no "unjudged" target left for this scan to reach.
  // 只有在每個目標都判完時才會走到這裡：否則上面那個分支已經回傳了，這個掃描不可能碰到沒判
  // 過的目標。
  for (const target of targets) {
    if (!target.startsWith(UNRESOLVED_TARGET)) continue;
    return unknownDenial(
      target.slice(UNRESOLVED_TARGET.length), isCopilot, isAntigravity, isCursor, isGrok,
    );
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

module.exports = { HOME_DIRS, MOUNT_PARENTS, SYSTEM_DIRS, commandTargets, evaluate, globCanMatchGit, hasGlob, normalizedTarget, protectedReason, shellWords };
