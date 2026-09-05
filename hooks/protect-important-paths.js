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

// How many substitution reads inside a double quote may FAIL before the three
// readers below stop being called at all. A read that fails scans to end of input
// and the caller then advances ONE character, so N unbalanced openers cost
// O(N x len) -- measured through the real stdin entry point: `echo "` + '${' x
// 60,000 + '" ; rm -rf /etc' cost 6,071 ms at 5bf41fe against 35 ms before those
// readers existed, past the live 5,000 ms PreToolUse timeout. A hook that outruns
// its timeout produces NO decision, so the deletion on that same line runs
// unjudged -- and the padding costs whoever writes the command nothing.
//
// Past the budget the arms fall through to `word += char`, which is exactly what
// this file did before those readers were added: the direction is more refusals,
// never fewer. Only FAILED reads spend budget, so a command whose substitutions
// close -- every real one -- never reaches it, and the nested-quote fix those
// readers exist for is untouched. 64 is far above any real command and far below
// the point where the quadratic matters.
// 雙引號裡的替換讀取「失敗」幾次之後，下面三個 reader 就不再被呼叫。一次失敗的讀取會掃到輸入
// 結尾，而呼叫端只前進一個字元，所以 N 個不收尾的開頭要花 O(N x len)——實測 6,071 ms，超過
// live 的 5,000 ms 逾時，而逾時的 hook 不產生任何裁決。超過預算之後這幾個臂會退回
// `word += char`，也就是這些 reader 加進來以前的行為：方向是「更常拒絕」，不是更少。
// 只有「失敗」的讀取會花預算，所以真實命令（替換都收得了尾）永遠碰不到它。
const MAX_FAILED_SUBSTITUTION_READS = 64;

function shellWords(command) {
  const words = [];
  const dynamicExpansions = [];
  // Per invocation, not per file: each shellWords() call gets its own budget.
  // 逐次呼叫各自一份預算。
  let failedSubstitutionReads = 0;
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
  // Whether the NEXT character would begin a new word. Only a '#' in that
  // position opens a comment -- bash's own rule. This has to be a FLAG and not
  // `word === ''`: a closed EMPTY quote leaves `word` empty while the shell is
  // still inside a word, so `ls ""#; /bin/rm -rf ~/.ssh` read as a comment, the
  // skip ran to end of LINE, and the whole ';'-separated deletion after it
  // vanished -- reopening a bypass this file had already closed. Measured
  // 2026-08-29 against bash 5.3: `ls '#'` runs, then the rm really executes.
  // The first version of the comment rule used `word === ''` and argued in a
  // comment that it was harmless because `#x` is not a protected path. That
  // argument reasoned about the rest of the WORD and missed that the skip runs
  // to the end of the LINE. Do not reintroduce it.
  // 下一個字元會不會是新的字的開頭。只有在那個位置的 '#' 才開啟註解——這是 bash 自己的
  // 規則。必須是「旗標」而不是 `word === ''`：關閉的空引號會讓 word 仍為空字串，但 shell
  // 其實還在一個字裡面，於是 `ls ""#; /bin/rm -rf ~/.ssh` 被讀成註解、跳到「行尾」，把後面
  // 整條以 ';' 分隔的刪除指令一起吞掉——重新打開了本檔早已關上的繞過。
  let atWordStart = true;

  // Where the word-start flag stood when the BACKSLASH was read, so a
  // backslash-newline can put it back. bash deletes that pair before it
  // tokenises anything, so the two characters are not a word boundary and not
  // part of a word either -- whatever came after them was at a word start
  // exactly if the backslash itself was. Without this the pair silently cleared
  // the flag, the '#' that followed stopped being a comment, and the odd
  // apostrophe in `# it's fine` reopened the quote-to-end-of-input bypass the
  // comment rule above exists to close.
  // 記住讀到「反斜線」時字首旗標的狀態,好讓反斜線接換行把它還原。bash 在斷詞之前就把這
  // 兩個字元刪掉,所以它們既不是字界也不屬於任何字:後面那個字元是否位在字首,完全等於這個
  // 反斜線是否位在字首。少了這一行,這個字元對會默默清掉旗標,後面的 '#' 就不再是註解。
  let escapedFromWordStart = false;

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
    // Default to "inside a word"; only the branches that END a word set it back.
    // 預設為「在字裡面」，只有真正結束一個字的分支才把它設回 true。
    const wasAtWordStart = atWordStart;
    atWordStart = false;
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
      // A line continuation is deleted whole, so the word-start state the
      // backslash stood at survives it. Only the newline spelling: `\x` really
      // is part of a word, and restoring the flag there would make `ls x\#y`
      // read as a comment when the shell reads it as one word.
      // 行接續整組被刪掉,反斜線當時的字首狀態因此存活。只有換行這種寫法如此:`\x` 確實
      // 屬於一個字,在那裡還原旗標會把 `ls x\#y` 誤讀成註解。
      else atWordStart = escapedFromWordStart;
      escaped = false;
    } else if (quote === 'ansi-c') {
      if (char === "'") quote = '';
      else if (char === '\\') {
        const decoded = decodeAnsiCEscape(input, index);
        word += decoded.value;
        index = decoded.end;
      } else word += char;
    } else if (
      char === '\\' && quote !== "'"
      // Inside DOUBLE QUOTES a backslash is only special before `$`, backtick,
      // `"`, `\` and newline; before anything else bash keeps BOTH characters
      // (measured with od(1) under bash 5.3.15 and /bin/bash 3.2.57:
      // `printf "%s" "rm\x20-rf"` writes r m \ x 2 0 - r f). Treating every
      // backslash as an escape here turned `echo -e "rm\x20-rf\x20/etc" | bash`
      // into the single word `rmx20-rfx20/etc` -- a word the shell never
      // produces, with no `rm` in it and no escape left for the decode above to
      // find -- so the deletion was ALLOWED while the single-quoted twin next to
      // it was refused (measured at ee2cb0e; a touch payload really ran).
      // The comment on the continuation branch above is about `\` + NEWLINE,
      // which really is deleted in both contexts; this is every OTHER character.
      // 雙引號裡的反斜線只有在 `$`、反引號、`"`、`\`、換行之前才是逸出；其餘一律「兩個字元
      // 都保留」（od(1) 實測，bash 5.3.15 與 /bin/bash 3.2.57 一致）。把它們全當逸出，會讓
      // `echo -e "rm\x20-rf\x20/etc" | bash` 變成 shell 根本不會產生的單一個字
      // `rmx20-rfx20/etc`：裡面沒有 rm，也沒有逸出序列可以給上面那層解碼看見。
      && (quote !== '"' || input[index + 1] === undefined || '$`"\\\n'.includes(input[index + 1]))
    ) {
      escapedFromWordStart = wasAtWordStart;
      escaped = true;
    } else if (quote) {
      if (char === quote) quote = '';
      // A `$(` inside DOUBLE QUOTES opens a command substitution, and bash parses
      // its body in a FRESH quoting context: the `"` in
      // `echo "T: $(echo a | sed "s|$X/||")"` OPENS a new quote, it does not close
      // the outer one. Without this branch the tokenizer closed the outer quote
      // there, believed it was back at top level for the rest of the
      // substitution, and read the `|` inside `s|$X/||` as a real pipeline
      // operator -- so `$X/` became the receiving end of a pipe, the R4
      // dynamic-carrier arm fired on it, and an ordinary sed one-liner was
      // REFUSED with `unresolvable pipe target ($X/)` (measured 2026-09-04
      // through the live stdin contract; the same command without the outer
      // `"$( … )"` was allowed). `V=1; echo "$(printf "%s|%s" "$V" y)"` and
      // `echo "n=$(ls | wc -l) $(echo "a|$X")"` were refused the same way.
      // The body is consumed with the SAME readParenthesized() the top-level
      // `$(` branch uses -- it already honours nesting and quotes -- so the
      // substitution lands in the word it sits in, exactly like its unquoted
      // twin, and commandSubstitutions() scans it from there. A regex over the
      // raw text would have to re-answer "which quote am I in", which is the
      // question this branch exists to answer.
      // 雙引號裡的 `$(` 開啟命令替換，而 bash 解析它的內文時是「全新的引號脈絡」：
      // `echo "T: $(echo a | sed "s|$X/||")"` 裡那個 `"` 是「開啟」新引號，不是關掉外層的。
      // 少了這個分支，tokenizer 會在那裡把外層引號關掉、以為自己回到了頂層，於是把
      // `s|$X/||` 裡的 `|` 當成真正的管線運算子——`$X/` 成了管線接收端，R4 的動態 carrier
      // 分支就對它開火，一條普通的 sed 被以 `unresolvable pipe target ($X/)` 擋掉。
      // 內文用的是頂層 `$(` 分支同一個 readParenthesized()（它本來就處理巢狀與引號），
      // 所以替換會落在它所屬的那個字裡，與沒有外層引號的雙胞胎一致。
      else if (
        quote === '"' && char === '$' && input[index + 1] === '('
        && failedSubstitutionReads < MAX_FAILED_SUBSTITUTION_READS
      ) {
        const substitution = readParenthesized(input, index + 1);
        wordHasDynamicExpansion = true;
        if (substitution) {
          word += input.slice(index, substitution.end + 1);
          index = substitution.end;
        } else {
          // Unbalanced '(': keep the old character-by-character behaviour, the
          // same fallback the top-level branch takes.
          failedSubstitutionReads += 1;
          word += char;
        }
      }
      // The same fresh-context rule for the other two substitution spellings that
      // can hold a quote of their own. `${x:-"a|$X"}` and the backtick form were
      // measured refused (2026-09-04) for exactly the reason `$( … )` was: the
      // inner `"` closed the OUTER quote, the rest was read at top level, and a
      // '|' inside it became a pipeline. A fix that closed only `$( … )` would
      // have left two siblings of the same defect open -- and `$(( … ))` needs no
      // branch of its own, because readParenthesized already matches its
      // parentheses from the first one.
      // 另外兩種「裡面可以自帶引號」的替換寫法，同一條規則。只修 `$( … )` 會留下同一個缺陷
      // 的兩個兄弟站點。`$(( … ))` 不需要自己的分支：readParenthesized 從第一個括號起就會
      // 把巢狀括號配對完。
      else if (
        quote === '"' && char === '$' && input[index + 1] === '{'
        && failedSubstitutionReads < MAX_FAILED_SUBSTITUTION_READS
      ) {
        const braced = readBraced(input, index + 1);
        wordHasDynamicExpansion = true;
        if (braced !== null) {
          word += input.slice(index, braced + 1);
          index = braced;
        } else {
          failedSubstitutionReads += 1;
          word += char;
        }
      }
      else if (
        quote === '"' && char === '`'
        && failedSubstitutionReads < MAX_FAILED_SUBSTITUTION_READS
      ) {
        const backquoted = readBackquoted(input, index);
        wordHasDynamicExpansion = true;
        if (backquoted !== null) {
          word += input.slice(index, backquoted + 1);
          index = backquoted;
        } else {
          failedSubstitutionReads += 1;
          word += char;
        }
      }
      else {
        if (quote === '"' && (char === '$' || char === '`')) {
          wordHasDynamicExpansion = true;
        }
        word += char;
      }
    } else if (char === '$' && input[index + 1] === "'") {
      quote = 'ansi-c';
      index += 1;
    } else if (
      char === '$' && input[index + 1] === '('
      // The TOP-LEVEL twin of the in-quote arm above spends the SAME budget, and
      // it has to: its failure path is character-for-character identical (scan to
      // end of input, return null, caller advances one character), so N unclosed
      // `$(` outside a quote cost O(N x len) exactly as they did inside one.
      // Measured before this guard, through the real stdin entry point:
      // `echo ` + `$(` x n + ` ; rm -rf /etc` took 820 ms at 16 KB, 2,870 ms at
      // 32 KB and 11,458 ms at 64 KB -- past the live 5,000 ms timeout, where the
      // hook makes NO decision and the deletion after the `;` runs unjudged. The
      // in-quote spelling was HALF that (382/1,428/5,678 ms) because only one of
      // the two sites was unbounded there. One counter for all four arms: a
      // second budget would let a command spend 64 in each.
      // 頂層這個臂與上面雙引號那個共用同一份預算：它的失敗路徑一模一樣（掃到輸入結尾、回
      // null、呼叫端只前進一個字元），所以引號外 N 個不收尾的 `$(` 同樣是 O(N x len)。
      // 加這道守衛之前實測：16 KB 820 ms、32 KB 2,870 ms、64 KB 11,458 ms，已經超過 live
      // 的 5,000 ms 逾時，而逾時的 hook 不做任何裁決，`;` 後面的刪除就不受判定地執行。
      // 四個臂共用一份計數：分兩份會讓同一條命令在每一份各花 64 次。
      && failedSubstitutionReads < MAX_FAILED_SUBSTITUTION_READS
    ) {
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
        failedSubstitutionReads += 1;
        word += char;
      }
    } else if (char === '#' && wasAtWordStart) {
      // A COMMENT, and it runs to the end of the line. Without this the '#' and
      // everything after it were tokenised as shell, and an ODD quote inside a
      // comment -- "# don't", '# say "hi' -- opened a quote state that ran to the
      // end of the INPUT. Every command on every following line was swallowed
      // into that one quoted word and never scanned, so
      // `git status # it's fine` + newline + `/bin/rm -rf ~/.ssh` was ALLOWED.
      // `/bin/rm` also sidesteps the rm->better-rm alias, so both layers missed
      // it. Measured 2026-08-29. This is bash's own rule, and the `word === ''`
      // half is what keeps it from over-reaching: a '#' only opens a comment at
      // the START of a word, so `file#1`, `http://x#frag`, `${#arr[@]}` and `$#`
      // all keep their '#' as ordinary text.
      // The newline is deliberately NOT consumed: the heredoc branches below key
      // on it, and eating it here would detach a body from its operator.
      // 這是註解，一路到行尾。少了這個分支，'#' 與其後全部被當 shell 斷詞，而註解裡一個
      // 落單的引號會開啟一路吃到「輸入結尾」的引號狀態——後面每一行的每一條命令都被吞進
      // 那個字裡，從未被掃描。「字首」那一半是防止過度延伸的關鍵。刻意不吃掉換行，否則
      // 下面的 heredoc 分支會與內文失聯。
      const lineEnd = input.indexOf('\n', index);
      index = (lineEnd === -1 ? input.length : lineEnd) - 1;
    } else if (char === '"' || char === "'") {
      quote = char;
    } else if (char === '<' && input[index + 1] === '<' && input[index + 2] === '<') {
      // A here-STRING. It has no body, and the heredoc branch below already
      // excludes it -- but only when the scan is looking at the FIRST '<'. The
      // loop then advanced one character and looked again from the SECOND '<',
      // where the next two characters are '<' and the delimiter, so `<<<y`
      // parsed as '<' followed by a heredoc `<< y`. Everything after the
      // newline became that heredoc's BODY, and a body is DATA: it goes back
      // only to a shell carrier, and `echo` is not one, so it was never
      // scanned as commands at all.
      // Measured 2026-08-29 against bash 5.3 (deletion replaced with a touch,
      // marker file appeared): `echo x <<<y` + newline + `rm -rf /etc` was
      // ALLOWED while bash really ran the rm. Pre-existing -- it predates the
      // comment rule and reproduces on the version before it.
      // Consuming all three characters here is the fix: the scan can no longer
      // land inside the sequence.
      // 這是 here-string,沒有內文,而下面的 heredoc 分支確實排除了它——但只在掃描看著
      // 「第一個」'<' 的時候。迴圈往前一格後從「第二個」'<' 再看一次,那裡後面正好是
      // '<' 加結束標記,於是 `<<<y` 被解析成 '<' 加一個 heredoc `<< y`,換行之後的一切
      // 都成了那個 heredoc 的內文——而內文是「資料」,只會交還給 shell carrier,
      // echo 不是,所以它從來沒有被當成命令掃描過。
      if (word) pushWord(word), word = '';
      pushWord('<<<', true);
      index += 2;
      atWordStart = true;
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
      atWordStart = true;
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
      atWordStart = true;
    } else if (';&|()<>\n'.includes(char)) {
      if (word) pushWord(word), word = '';
      pushWord(char, true);
      atWordStart = true;
    } else if (/\s/.test(char)) {
      if (word) pushWord(word), word = '';
      atWordStart = true;
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
  // Read by test-hooks.js: the property this budget is pinned by is a COUNT, not
  // a duration -- a millisecond ceiling on this path measures the host.
  // 由 test-hooks.js 讀取：釘住這個預算的是「次數」而不是「時間」。
  Object.defineProperty(words, 'failedSubstitutionReads', { value: failedSubstitutionReads });
  return words;
}

// Find the ')' that closes the '(' at openIndex, honouring nesting and quotes.
// Shared by the tokenizer and the substitution scanner so both agree on where a
// command substitution ends.
// Where the '}' that closes the '${' at openIndex sits, honouring nesting, quotes
// and backslashes; null if it never closes. Used only from inside a double quote,
// where the body may carry a quote of its own (`"${x:-"a|b"}"`) and reading that
// quote as the end of the OUTER one is the defect this exists to stop.
// `${` 的收尾 '}' 在哪裡（處理巢狀、引號、反斜線）；沒有收尾就回 null。
function readBraced(input, openIndex) {
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
    } else if (char === '"' || char === "'") {
      innerQuote = char;
    } else if (char === '{') {
      depth += 1;
    } else if (char === '}') {
      depth -= 1;
      if (depth === 0) return i;
    }
  }
  return null;
}

// Where the '`' that closes the one at openIndex sits. A backquoted substitution
// ends at the next backslash-free backtick -- it does not nest -- so this is a
// scan, not a depth count. null if it never closes.
// 反引號替換在「下一個未被反斜線跳脫的反引號」結束（不巢狀），沒有收尾就回 null。
function readBackquoted(input, openIndex) {
  for (let i = openIndex + 1; i < input.length; i += 1) {
    if (input[i] === '\\') {
      i += 1;
      continue;
    }
    if (input[i] === '`') return i;
  }
  return null;
}

function readParenthesized(input, openIndex) {
  let depth = 1;
  let innerQuote = '';
  let innerEscaped = false;
  // Where the ')' scan is, is also where a COMMENT would start -- and a comment
  // hides both quotes and parentheses from this scan. Same rule as the tokenizer:
  // '#' opens a comment only unquoted and only at the start of a word.
  // 找 ')' 的掃描同時也要認得註解——註解會同時遮蔽引號與括號。規則與 tokenizer 相同。
  let atWordStart = true;
  for (let i = openIndex + 1; i < input.length; i += 1) {
    const char = input[i];
    const wasAtWordStart = atWordStart;
    atWordStart = false;
    if (innerEscaped) {
      innerEscaped = false;
    } else if (char === '\\' && innerQuote !== "'") {
      innerEscaped = true;
    // `!innerQuote` here is defence in depth, not the load-bearing guard: the
    // word-start update below is itself gated on `!innerQuote`, so atWordStart
    // can never be true inside quotes and a mutant that deletes either one alone
    // is EQUIVALENT -- no test can kill it. Measured 2026-08-29; recorded so the
    // next reviewer does not go looking for the missing test.
    // 這裡的 `!innerQuote` 是縱深防禦而非承重的守衛:下面更新字首狀態那一行本身就被
    // `!innerQuote` 包住,所以引號內 atWordStart 永遠不會是 true。單獨刪掉其中任一個都是
    // 等價突變,沒有測試殺得掉。記在這裡,免得下一個審查者去找那個不存在的測試。
    } else if (char === '#' && !innerQuote && wasAtWordStart) {
      const lineEnd = input.indexOf('\n', i);
      // A comment with no newline after it swallows the closing ')' too, which is
      // exactly what bash does -- `echo $(ls # x)` is an unterminated substitution
      // and a syntax error. Returning null keeps the caller's existing fallback.
      // 沒有換行的註解會把收尾的 ')' 一起吃掉，這正是 bash 的行為（該式子是語法錯誤）。
      if (lineEnd === -1) return null;
      i = lineEnd;
      atWordStart = true;
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
    if (!innerQuote && !innerEscaped && /[\s;&|()<>]/.test(char)) atWordStart = true;
  }
  return null;
}

// noCommentSpans: [start, end) offsets of UNQUOTED heredoc bodies. Inside a
// heredoc body a '#' is ordinary text, not a comment -- but `$( )` in an
// unquoted body IS expanded, before the reading command ever sees the result.
// Applying the comment rule there hid every substitution after a '#' on that
// line, so `cat <<EOF` + newline + `# $(rm -rf ~/.ssh)` + newline + `EOF` was
// ALLOWED while bash really ran the deletion (measured 2026-08-29). The spans
// scope the NEW rule only; substitution finding is untouched, so a `$(` that
// opens outside a body and closes inside it still resolves exactly as before.
// noCommentSpans:未加引號 heredoc 內文的 [start, end) 位移。內文裡的 '#' 是普通文字而不是
// 註解，但那裡的 `$( )` 是真的會展開的。把註解規則套進去會藏掉該行 '#' 之後的每一個替換。
function commandSubstitutions(command, noCommentSpans = []) {
  const input = String(command || '');
  const commands = [];
  // The same failed-read budget the tokenizer spends, for the same reason and on
  // the same shape -- this scanner re-reads the RAW command text after
  // tokenizing, so the tokenizer's per-call counter cannot reach it and its two
  // readParenthesized call sites below carried the whole `$(` quadratic on their
  // own. Measured before this counter, real stdin entry point, `echo "` + `$(` x n
  // + `" ; rm -rf /etc`: 382 ms at 16 KB, 1,428 ms at 32 KB, 5,678 ms at 64 KB,
  // and the cost was ATTRIBUTED with an instrumented copy rather than assumed --
  // at 16 KB the tokenizer spent its 64 failed reads and THIS function spent
  // 8,192, scanning 33.7 M characters. The `<(` site four lines below has the
  // identical failure path (785 ms / 2,965 ms at 16 KB / 32 KB) and shares the
  // counter. Only FAILED reads spend it, so every command whose substitutions
  // close -- every real one -- never reaches it.
  // What a spent budget costs, stated rather than hidden: past the cap a `$(`
  // that WOULD have closed is no longer read, so a substitution after 64 unclosed
  // ones is not returned and its body is not scanned.
  // THIS COMMENT USED TO SAY that reaching the cap needs "64 openers that never
  // balance anywhere in the rest of the input, which is a syntax error in every
  // shell this file models (`bash -n` refuses it), so no command that reaches the
  // cap is a command that runs". That was FALSE, and the counter-example is
  // twenty lines below in this same function: an UNQUOTED heredoc body is
  // deliberately kept in `scannable` because its substitutions really do run, so
  // this scanner reads that text while bash treats it as ordinary DATA. 64 x `$(`
  // in a heredoc body is not a syntax error -- `bash -n` accepts it, bash prints
  // a NON-fatal `bad substitution: no closing )` at run time and carries on to
  // the next line. Measured 2026-09-05 (r5-validate-better-rm-7): `cat <<EOF` +
  // 64 x `$(` + `EOF` + `echo $(rm -rf /etc)` was ALLOWED and really removed the
  // target under bash 5.3.15, /bin/bash 3.2.57 and /bin/sh; 63 openers denied and
  // 64 allowed. The general rule this file may not forget again: a bash-LITERAL
  // context that this gate still scans is scannable text for the gate and inert
  // text for the shell, so "the padding would be a syntax error" is never an
  // argument for a state being unreachable here.
  // So a spent budget is no longer silence: commandTargetsScan reads this counter
  // and pushes SUBSTITUTION_BUDGET_EXHAUSTED, which refuses the whole invocation
  // (R5-13). The counter is what makes that possible, which is why it is exposed.
  // 與 tokenizer 同一份失敗讀取預算、同樣的理由、同樣的形狀：這個掃描器在斷詞之後重讀原始
  // 文字，tokenizer 的計數器碰不到它，`$(` 的平方級成本整份都由這裡的兩個 readParenthesized
  // 站點扛著（實測 16 KB 382 ms、32 KB 1,428 ms、64 KB 5,678 ms；用加了計數器的複本歸因，
  // 16 KB 時這個函式失敗了 8,192 次、掃了 3,370 萬個字元）。只有「失敗」的讀取會花預算。
  // 代價講明白：超過上限之後，「本來讀得完」的 `$(` 不再被讀出來。
  // 這段註解原本寫著「要走到那一步，輸入裡得有 64 個到結尾都不收尾的開頭，而那在本檔案建模
  // 的每一種 shell 裡都是語法錯誤，所以走到上限的命令不是會執行的命令」——那句話是錯的，
  // 反例就在同一個函式往下二十行：未加引號的 heredoc 內文「刻意」留在 scannable 裡（因為它
  // 裡面的替換是真的會執行），所以這個掃描器會讀那段文字，而 bash 只把它當資料。heredoc 內
  // 文裡的 64 個 `$(` 完全不是語法錯誤：`bash -n` 接受，bash 執行時只印一則非致命的
  // `bad substitution`，然後繼續跑下一行（2026-09-05 實測：`cat <<EOF` + 64 個 `$(` + `EOF`
  // + `echo $(rm -rf /etc)` 被放行且真的刪掉目標，63 個拒絕、64 個放行）。
  // 通則，別再忘記：任何「bash 當成字面資料、而這道閘門仍然會掃」的脈絡，都是「掃得到但不
  // 是語法」的文字，所以「那樣寫會是語法錯誤」永遠不能拿來論證某個狀態不可能發生。
  // 因此預算花完不再等於沉默：commandTargetsScan 會讀這個計數並推入
  // SUBSTITUTION_BUDGET_EXHAUSTED，整條命令直接拒絕（R5-13）。計數器對外可見正是為了這件事。
  let failedSubstitutionReads = 0;
  const inNoCommentSpan = (i) => noCommentSpans.some(([a, b]) => i >= a && i < b);
  let quote = '';
  let escaped = false;
  // Same comment rule as the tokenizer. This scanner has no word accumulator, so
  // "start of a word" is tracked explicitly instead of read off `word === ''`.
  // 與 tokenizer 相同的註解規則。這個掃描器沒有字的累加器，所以「字首」用旗標明確追蹤。
  let atWordStart = true;
  // Same line-continuation rule as the tokenizer, and this scanner needs it for
  // a second reason: both of its escape branches `continue`, which skips the
  // bottom-of-loop update that would otherwise have set the flag from the
  // newline. So the pair cleared word-start here too, and
  // `echo \<nl># don't<nl>$(rm -rf /etc)` was ALLOWED even with the tokenizer
  // half fixed -- measured. readParenthesized does not need it: its update at
  // the bottom of the loop is reached, so the pair already sets the flag there.
  // 與 tokenizer 相同的行接續規則,而且這個掃描器還多一個理由:它的兩個跳脫分支都
  // `continue`,跳過了迴圈底部那一行——否則換行本來就會把旗標設起來。所以這裡的字元對同樣
  // 會清掉字首,就算 tokenizer 那一半修好了,上面那條命令仍然放行(實測)。
  let subEscapedFromWordStart = false;

  for (let i = 0; i < input.length; i += 1) {
    const char = input[i];
    const wasAtWordStart = atWordStart;
    atWordStart = false;
    if (escaped) {
      if (char === '\n') atWordStart = subEscapedFromWordStart;
      escaped = false;
      continue;
    }
    if (char === '\\' && quote !== "'") {
      subEscapedFromWordStart = wasAtWordStart;
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
    // `!quote` is defence in depth here for the same reason as in
    // readParenthesized: the word-start update at the bottom of this loop is
    // gated on `!quote`, so deleting either alone is an equivalent mutant.
    // 這裡的 `!quote` 與 readParenthesized 同理,是縱深防禦;單獨刪掉是等價突變。
    if (!quote && char === '#' && wasAtWordStart && !inNoCommentSpan(i)) {
      const lineEnd = input.indexOf('\n', i);
      if (lineEnd === -1) break;
      i = lineEnd;
      atWordStart = true;
      continue;
    }
    if (char === '$' && input[i + 1] === '(') {
      // The budget test is INSIDE the branch, not in its condition: the branch
      // ends in `continue`, and letting a `$` fall through to the bottom of the
      // loop instead would change nothing here but would change it for the `<(`
      // sibling below, whose character IS in the word-start class. Keeping both
      // branches shaped the same way means a spent budget skips the READ and
      // nothing else.
      // 預算判斷放在分支「裡面」而不是條件上：這個分支以 continue 結尾，改成落到迴圈底部對
      // 這裡沒差，對下面 `<(` 那個兄弟站點卻有（它的字元本身就在字首類別裡）。預算用完只會
      // 少做那一次讀取，不會改變別的事。
      let nested = null;
      if (failedSubstitutionReads < MAX_FAILED_SUBSTITUTION_READS) {
        nested = readParenthesized(input, i + 1);
        // Only a read that was ATTEMPTED and FAILED spends budget. Incrementing
        // outside this guard would keep counting after the cap and turn the
        // counter into a length measurement, which is the one thing the row that
        // pins it (`half === full`) exists to catch.
        // 只有「真的試了而且失敗」的讀取才花預算。
        if (!nested) failedSubstitutionReads += 1;
      }
      if (nested) {
        // `$((` is ARITHMETIC, not a command substitution wrapping a subshell.
        // readParenthesized counts the inner '(' too, so for `$(( expr ))` it
        // returns the whole `( expr )` -- and pushing that as a COMMAND is what
        // caused the false refusals: the expression was scanned as if the shell
        // were about to run it, a dynamic first token made the command word
        // unresolvable, and the "an unresolvable command word must be assumed
        // to be rm" rule turned every later token into a deletion operand.
        // `echo $(( $a / 2 ))` was refused with "protected directory: /",
        // because the division operator was read as the root directory.
        // Nothing inside `$(( ))` executes as a command word, so that rule does
        // not apply. The INTERIOR is still scanned, because a substitution
        // inside an arithmetic expression really does run -- `$(( $(rm -rf
        // /etc) ))` stays refused.
        // The `$( (subshell) )` ambiguity is resolved conservatively: only a
        // body with no command separator is treated as arithmetic, so a real
        // subshell keeps the old handling.
        // `$((` 是「算術」,不是包著 subshell 的命令替換。readParenthesized 連內層的 '('
        // 也算進去,所以對 `$(( expr ))` 它回傳整個 `( expr )`——把那個當成「命令」推進去
        // 正是誤拒的成因:運算式被當成即將執行的命令來掃描,第一個 token 是動態展開就讓
        // 命令字不可知,而「不可知的命令字必須假設是 rm」接著把後面每個 token 都當成刪除
        // 操作元。`$(( ))` 裡沒有任何東西會以命令字的身分執行。內部仍然會掃,因為算術式
        // 裡的替換是真的會執行的。
        const body = nested.command;
        const looksArithmetic = input[i + 2] === '('
          && body.startsWith('(')
          && body.endsWith(')')
          && !/[;&|\n]/.test(body);
        if (looksArithmetic) {
          commands.push(...commandSubstitutions(body.slice(1, -1), noCommentSpans));
        } else {
          commands.push(body);
        }
        i = nested.end;
      }
      continue;
    }
    if ((char === '<' || char === '>') && input[i + 1] === '(') {
      // The sibling of the `$(` site above: same reader, same scan-to-EOF failure
      // path, same one-character advance, and it was measured quadratic on its
      // own (`echo ` + `<(` x n + ` ; rm -rf /etc`: 785 ms at 16 KB, 2,965 ms at
      // 32 KB). It shares the counter -- fixing only the `$(` half would have
      // left the shape one character away.
      // `$(` 站點的兄弟：同一個 reader、同一條失敗路徑、同樣只前進一個字元，自己就量得出平方
      // 級。共用同一份計數；只修 `$(` 那一半，形狀只要改一個字元就繞過去了。
      let nested = null;
      if (failedSubstitutionReads < MAX_FAILED_SUBSTITUTION_READS) {
        nested = readParenthesized(input, i + 1);
        if (!nested) failedSubstitutionReads += 1;
      }
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
    if (!quote && /[\s;&|()<>]/.test(char)) atWordStart = true;
  }
  // Read by test-hooks.js, exactly like shellWords' counter and for the same
  // reason: what pins this budget is a COUNT, not a duration -- a millisecond
  // ceiling on this path measures the host, not the gate. Non-enumerable, so an
  // array of substitutions is still just an array everywhere else.
  // 由 test-hooks.js 讀取，與 shellWords 的計數器同理：釘住這份預算的是「次數」而不是時間。
  Object.defineProperty(commands, 'failedSubstitutionReads', { value: failedSubstitutionReads });
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

// What a LITERAL emitter writes down a pipe is not the text on the command line:
// `echo -e 'rm\x20-rf\x20/etc'` is ONE shell word here and three words there, so
// a gate that scans only the word it was handed reads `rm` as part of a single
// operand and never as a command. Measured at ee2cb0e through the real stdin
// entry point: twelve spellings ALLOWED, with a touch payload that really ran
// under bash 5.3.15, /bin/bash 3.2.57, /bin/sh, zsh and /bin/csh.
//
// The decode is UNCONDITIONAL -- it is NOT gated on `echo -e`. Which shell reads
// the pipe is not visible from here, dash's and ksh's echo decode by default,
// `bash -O xpg_echo` makes bash's do it too (measured: the payload ran), and
// printf decodes its FORMAT always and its `%b` ARGUMENTS as well. Being wrong
// about the option costs a refusal; being wrong about the shell costs a deletion.
//
// The decoded text is ADDED to the scan set, never substituted for the raw one:
// this hands the ordinary rules more text to judge, so it can only ever turn an
// allowance into a refusal, never the reverse. `\\` is the FIRST alternative so
// that `\\x20` stays two characters and does not become a space.
// 字面產生器寫進 pipe 的東西，不等於命令列上的文字：`echo -e 'rm\x20-rf\x20/etc'` 在這裡是
// 「一個」shell 字，在那裡是三個字。解碼刻意不以 `-e` 為條件：從這裡看不出讀 pipe 的是哪個
// shell，dash 與 ksh 的 echo 預設就解碼，`bash -O xpg_echo` 讓 bash 的也解碼（實測 payload
// 真的執行），而 printf 永遠解碼格式字串、`%b` 連參數一起解。判斷錯選項的代價是一次誤擋，
// 判斷錯 shell 的代價是一次刪除。解碼後的文字是「加入」掃描集合而不是取代原文：這只會把放行
// 變成拒絕，不會反過來。`\\` 放在第一個選項，好讓 `\\x20` 維持兩個字元、不要變成空白。
const SHELL_ESCAPE = /\\(?:\\|x[0-9A-Fa-f]{1,2}|u[0-9A-Fa-f]{1,4}|U[0-9A-Fa-f]{1,8}|0[0-7]{0,3}|[0-7]{1,3}|[abefnrtv])/g;
const ESCAPE_LETTERS = {
  a: '\u0007', b: '\b', e: '\u001b', f: '\f', n: '\n', r: '\r', t: '\t', v: '\v', '\\': '\\',
};
function decodeShellEscapes(text) {
  if (typeof text !== 'string' || text.indexOf('\\') === -1) return text;
  return text.replace(SHELL_ESCAPE, (sequence) => {
    const body = sequence.slice(1);
    const head = body[0];
    if (Object.prototype.hasOwnProperty.call(ESCAPE_LETTERS, head)) return ESCAPE_LETTERS[head];
    if (head === 'x') return String.fromCharCode(parseInt(body.slice(1), 16));
    if (head === 'u' || head === 'U') {
      const point = parseInt(body.slice(1), 16);
      // A lone surrogate or an out-of-range point cannot be spelled, and
      // String.fromCodePoint throws on it: keep the raw text rather than let a
      // hostile escape turn a refusal into a crash (the parse path exits 2, but
      // this one runs inside evaluate() where a throw is not a decision).
      // 孤立代理對或超出範圍的碼位拼不出來，String.fromCodePoint 會丟例外：保留原文，不要讓
      // 一個惡意的逸出序列把「拒絕」變成「例外」。
      if (!Number.isFinite(point) || point > 0x10ffff || (point >= 0xd800 && point <= 0xdfff)) return sequence;
      return String.fromCodePoint(point);
    }
    // Octal, with or without the leading `0`: bash's `echo -e` spells it `\0nnn`
    // and printf's FORMAT spells it `\nnn`, and both reach here.
    // 八進位，帶不帶開頭的 `0` 都有：`echo -e` 寫 `\0nnn`，printf 的格式字串寫 `\nnn`。
    return String.fromCharCode(parseInt(head === '0' ? body.slice(1) || '0' : body, 8));
  });
}

// A shell carrier whose SCRIPT this gate could not read: it arrived on a pipe,
// through a process substitution, or as the output of a command substitution
// inside the carrier's own here-string or heredoc body. Same sentinel
// discipline as UNRESOLVED_TARGET above -- including the reason it is written as
// an ESCAPE and never as a raw byte -- and the same reason for existing: the
// refusal has to say what it actually is, not borrow the protected-directory
// wording for a path the command never named. It carries the SHAPE
// (`curl | bash`) so the message can quote the command rather than describe it.
// carrier 的腳本這道閘門讀不到：它從 pipe、process substitution，或 carrier 自己的
// here-string／heredoc 內文裡的命令替換輸出進來。與上面的 UNRESOLVED_TARGET 同一套規矩
// （包含為什麼寫成跳脫序列而不是原始位元組），存在的理由也相同：拒絕訊息必須說出它真正是
// 什麼，不能借用受保護目錄那套措辭去講一條命令根本沒寫的路徑。它帶著「形狀」
// （`curl | bash`），讓訊息可以引用命令本文而不是描述它。
const UNSCANNABLE_SCRIPT = '\u0000unscannable:';

// The receiving end of a pipe is a command word this gate cannot resolve, and
// nothing after it names a file to read. It may be a shell taking its script
// from the pipe, so it is refused -- but it is NOT the refusal above, and the
// difference is the message: nothing here is known to be a shell, so telling the
// reader that this command "feeds a script into a shell" and pointing at
// PIPED_SCRIPT_EXCEPTIONS describes a command they did not write and offers a
// knob that cannot help them. Measured 2026-09-03: `git log | $PAGER` and
// `ps aux | "$HOME/bin/filter.sh"` both received exactly that message. The second
// is now resolved and allowed; the first still refuses, with wording that says
// what actually happened and how to spell it so it does not.
// 管線的接收端是一個這道閘門解不開的命令字，而它後面沒有任何字指出要讀哪個檔案。它可能是
// 一個從 pipe 讀腳本的 shell，所以拒絕——但它不是上面那一種拒絕，差別就在訊息：這裡沒有
// 任何東西被認定是 shell，跟使用者說「這條命令把腳本餵給 shell」再叫他去改
// PIPED_SCRIPT_EXCEPTIONS，是在描述一條他沒有寫的命令、並給他一個幫不上忙的旋鈕。
const UNREADABLE_PIPE_TARGET = '\u0000pipe-target:';

// An `env -S` string this gate could not split the way env(1) splits it, with the
// same discipline as the sentinels above (r5-fix-better-rm-6, R5-10b). env's -S
// grammar is small but it is NOT the shell's, and three of its rules decide
// whether a removal is there at all: `\\_` is a space that SPLITS, `#` at the
// start of a word comments out the rest of the string, and `${VAR}` is expanded
// (all three measured on macOS BSD env and GNU coreutils 9.11 env, which agree).
// The first two are modelled. Expansion cannot be: the value is not known before
// the command runs, and `env -S '${X}' -rf /etc` is a removal exactly when X says
// so. Same for an escape this gate does not model and for a quote that is never
// closed -- in both cases the words are a guess, and a guess is not an answer.
// 一段這道閘門沒辦法照 env(1) 的規則切開的 `-S` 字串，與上面幾個 sentinel 同一套規矩
// （r5-fix-better-rm-6，R5-10b）。env 的 -S 文法很小，但它不是 shell 的文法，而其中三條
// 規則直接決定「有沒有刪除」：`\\_` 是「會切開」的空白、`#` 在字首把字串剩下的部分變成註
// 解、`${VAR}` 會被展開（三條都在 macOS BSD env 與 GNU coreutils 9.11 env 上實測，兩者一
// 致）。前兩條有建模，展開不可能建模：值要到執行時才知道，而 `env -S '${X}' -rf /etc` 是
// 不是刪除完全由 X 決定。沒有建模的跳脫、以及沒有收掉的引號也一樣——切出來的字都是猜的，
// 而猜不是答案。
const UNJUDGEABLE_ENV_S = '\u0000env-s:';

// A `trap` ACTION this gate could not read (R5-c, r5-fix-better-rm-7). Same
// discipline as the sentinels above -- written as an ESCAPE and not a raw byte,
// for the install-hooks.sh reason spelled out at UNRESOLVED_TARGET -- and it
// needs to be its OWN sentinel for the reason each of them does: the message.
// unscannableScriptDenial states as fact that the command feeds a script into a
// shell through a pipe or a process substitution and offers
// PIPED_SCRIPT_EXCEPTIONS as the way out; for `trap "$CMD" EXIT` there is no
// pipe, no URL, and the thing that could not be read is an ARGUMENT. Sending
// that user to a URL allowlist describes a command they did not write, which is
// the defect these separate messages exist to prevent. A trap action is scanned
// as a nested script whenever this gate CAN read it -- $HOME/$PWD/$TMPDIR are
// resolved by exactly the function an rm operand uses -- so this sentinel is
// reached only when the action's TEXT is unknown before the command runs.
// 「讀不到的 trap 動作」（R5-c）。與上面幾個 sentinel 同一套規矩（同樣寫成足以避開原始位元組的跳脱序列，
// 理由見 UNRESOLVED_TARGET），而它必須自成一種的理由也一樣是訊息：
// `trap "$CMD" EXIT` 沒有 pipe、沒有網址，讀不到的是一個「引數」，叫使用者去改網址允許清
// 單，等於在描述一條他沒有寫的命令。動作只要讀得到就會被當成巢狀腳本掃描
// （$HOME／$PWD／$TMPDIR 用的是 rm 操作元同一個函式），所以只有「文字要執行後才知道」時才會走到這裡。
const UNREADABLE_TRAP_ACTION = '\u0000trap-action:';

// A scan that ran out of failed-read budget (R5-13, r5-fix-better-rm-8). Same
// discipline as the sentinels above, and it needs to be its own for the same
// reason each of them does: what could not be read here is not a path, not a
// piped script and not an argument -- it is the REST OF THE COMMAND. Past
// MAX_FAILED_SUBSTITUTION_READS the readers stop reading, so a `$( ... )` after
// the padding is not returned and its body is never scanned; before this sentinel
// that state produced no refusal at all, and `cat <<EOF` + 64 x `$(` + `EOF` +
// `echo $(rm -rf /etc)` was ALLOWED while bash really ran the deletion (measured
// 2026-09-05 under bash 5.3.15, /bin/bash 3.2.57 and /bin/sh; 63 openers denied,
// 64 allowed). The value carried is the COUNT of unreadable openers, because that
// number is the one thing the user can act on: it says how much of their own
// command this gate could not see.
// This is the fail-CLOSED half of the budget the R5-a fix added. The budget still
// bounds the cost -- a spent budget skips the READ, exactly as before -- and this
// sentinel is what stops "skipped the read" from also meaning "answered as if it
// had read it".
// A scan is exhausted at EXACTLY the cap and never past it: the counters are only
// incremented inside the guard that tests them, so `>= MAX` and `=== MAX` are the
// same question, and `>=` is written because a future site that increments
// elsewhere must still be caught.
// (SCAN, NOT SYNTAX) `$(( ... ))`'s recursive commandSubstitutions() call keeps a
// counter of its own and is deliberately NOT wired to this sentinel: it runs only
// after readParenthesized balanced the whole `$(( ... ))`, and readParenthesized
// counts a `$(` inside a double quote as depth exactly as it counts an unquoted
// one, so padding that would spend the inner budget makes the OUTER read fail and
// is recorded by the outer counter instead. test-hooks.js pins that -- it is a
// measured property of this file's own reader, not a claim about shells.
// 「掃描把失敗讀取的預算用完了」（R5-13）。與上面幾個 sentinel 同一套規矩，而它必須自成一種
// 的理由也一樣：這裡讀不到的既不是路徑、不是管線腳本、也不是某個引數，而是「命令剩下的部
// 分」。超過上限之後 reader 就不再讀，填充後面的 `$( ... )` 不會被回傳、內文也不會被掃；在
// 這個 sentinel 之前，那個狀態根本不產生任何拒絕（實測：`cat <<EOF` + 64 個 `$(` + `EOF` +
// `echo $(rm -rf /etc)` 被放行，而 bash 真的執行了刪除；63 個拒絕、64 個放行）。帶的值是
// 「讀不出來的開頭有幾個」，因為那是使用者唯一能據以行動的數字。
// 這是 R5-a 那份預算的 fail-closed 那一半：預算照舊只是「少做那一次讀取」，而這個 sentinel
// 讓「少讀了」不再同時代表「當作讀過了」。
// 計數只在「測試它的那道守衛裡面」遞增，所以 `>= MAX` 與 `=== MAX` 是同一個問題；寫 `>=` 是
// 為了讓將來在別處遞增的站點一樣會被接住。
// `$(( ... ))` 的遞迴刻意不接這個 sentinel：它只有在 readParenthesized 把整段配對成功之後才
// 會跑，而它連雙引號裡的 `$(` 都算深度，所以會花掉內層預算的填充一定先讓外層讀取失敗、由外
// 層計數器記下來。test-hooks.js 有釘住這一點——那是本檔案自己 reader 的實測性質，不是對
// shell 的臆測。
const SUBSTITUTION_BUDGET_EXHAUSTED = '\u0000substitution-budget:';

// The install routes exempted from the rule above, as raw URL text prefixes.
// Every entry is scheme + host + owner/repo and MUST end with '/': a bare host
// would except every repository on that host, a scheme-less entry would match
// inside a longer host (`raw.githubusercontent.com.evil.tld`), and the trailing
// slash is what rejects `better-rm-evil`. Literal startsWith, no wildcards, no
// port spellings, no `http://` -- it should stay this simple, and extending it
// is a user's decision, which is why the refusal message names the constant.
// Deliberately NOT listed: `doggy8088/better-rm` (the upstream this repo is
// forked from -- no route in this README cites it, and this repo's own release
// path targets sieg-wang), and `github.com/sieg-wang/better-rm` (the HTML host,
// which nothing pipes from).
// WHAT THIS LIST IS NOT: an identity check. It matches text on the command line,
// so anything that can write the command can write the prefix, and this gate
// cannot verify what the server returns. Its job is to stop the sound rule from
// refusing this project's own documented install route (README.md), never to
// establish trust. That is why the option allowlists below exist: measured
// 2026-09-03, `curl -k --connect-to raw.githubusercontent.com:443:127.0.0.1:18443
// -sSL <prefix-matching URL>` delivered attacker-controlled bytes from a
// loopback TLS server while the URL text matched this prefix byte for byte, and
// `--resolve`, `--proxy`, `--unix-socket`, `-K` and `-o` move the fetch the same
// way. So an exempted fetch may carry only options that cannot move it.
// 這份清單「不是」身分驗證：它比對的是命令列上的文字，任何能寫命令的人都能寫出這個前綴，而
// 這道閘門無法驗證伺服器回什麼。它的職責只是不要讓那條成立的規則擋掉本專案 README 記載的
// 安裝路徑，不是建立信任。底下的選項白名單就是為此存在：2026-09-03 實測，`--connect-to`
// 能在網址文字逐位元組相符的情況下，從 loopback TLS 伺服器送出攻擊者控制的內容，
// `--resolve`、`--proxy`、`--unix-socket`、`-K`、`-o` 也一樣會移動這次抓取。
const PIPED_SCRIPT_EXCEPTIONS = [
  'https://raw.githubusercontent.com/sieg-wang/better-rm/',
];

// The exemption above has exactly ONE condition now, and this is it: the WHOLE
// command line must be one of these documented install routes, byte for byte,
// after trimming leading and trailing ASCII whitespace and collapsing runs of
// spaces and tabs. Nothing else may be on the line -- no prefix (`cd ... &&`,
// `if ...; then`, an assignment, a wrapper), no suffix (`; ...`, `&& ...`,
// `| ...`, a `#` comment), no newline anywhere inside it, no quoting beyond what
// is written here, and no alternate spelling of the same route (a different
// option order or a different case is NOT this line). Everything else falls
// through to the unscannable piped-script refusal.
// WHY A WHOLE LINE INSTEAD OF A SET OF CONDITIONS: three rounds of this gate
// tried to enumerate the ways a line can put something else behind `curl`, and
// every round was defeated by a spelling nobody had enumerated -- the last by
// in-word quote removal, `e''val 'c''url() { ... }'; <route>`, which the shell
// rebuilds into `eval` and `curl` while the raw bytes contain neither (measured
// 2026-09-05 through the real stdin entry point: it really defines the function
// and really runs the replacement under bash 5.3.15 and /bin/bash 3.2.57). A
// whole-line literal cannot be defeated that way, and not because a longer list
// of shapes was found: any character an attacker adds is a character that stops
// the line from BEING this line, so the class is closed by construction rather
// than by enumeration. The cost is stated rather than discovered -- prefixes,
// suffixes, comments and reordered options are now refused, and the way through
// is to run the route on a line of its own.
// 上面那條豁免現在只有一個條件，就是這個：整條命令列必須逐位元組等於下列其中一條記載中的
// 安裝路徑（先去掉前後的 ASCII 空白，再把連續的空白／tab 併成一個空格）。行上不可以有別的
// 東西——前面不行（`cd … &&`、`if …; then`、變數指派、包裝命令），後面也不行（`; …`、
// `&& …`、`| …`、`#` 註解），中間不可以有換行，不可以有這裡沒寫的引號，也不接受同一條路徑
// 的其他寫法（選項順序或大小寫不同，就不是這一行）。其餘一律落回「讀不到的 piped script」。
// 為什麼是「整行」而不是一組條件：這道閘門用三輪去列舉「一行上有多少種方法把別的東西塞到
// curl 後面」，每一輪都被一種沒被列舉到的寫法打穿，最後一次是「字裡面的引號消去」
// （`e''val 'c''url() { … }'; <路徑>`）——shell 會把它還原成 eval 與 curl，而原始位元組裡
// 兩者都不存在（2026-09-05 走真正的 stdin 入口實測：函式真的被定義、替身真的被執行，
// bash 5.3.15 與 /bin/bash 3.2.57 皆然）。整行字面比對打不穿這一點，而且理由不是「找到了
// 更長的形狀清單」：攻擊者多加的任何一個字元，都是讓這一行不再是這一行的字元，所以這一類是
// 「由構造上」關掉的，不是靠列舉關掉的。代價寫在這裡而不是留給人踩：前綴、後綴、註解、選項
// 換順序從此都被拒絕，繞法是把那條路徑單獨寫成一行。
// This array and README.md's 「允許的 piped installer 清單」 block are ONE list in
// two places: test-hooks.js reads the README and fails if they differ, so a
// widening here that is not written down goes red, and so does a README edit
// that is not implemented.
// 這個陣列與 README.md 的「允許的 piped installer 清單」是同一份清單的兩個副本：
// test-hooks.js 會去讀 README 比對，兩邊不一致就轉紅——在這裡放寬而沒有寫進文件會紅，
// 在文件上寫了而沒有實作也會紅。
const CANONICAL_INSTALL_LINES = [
  'curl -sSL https://raw.githubusercontent.com/sieg-wang/better-rm/main/install.sh | bash',
  'wget -qO- https://raw.githubusercontent.com/sieg-wang/better-rm/main/install.sh | bash',
  'curl -sSL https://raw.githubusercontent.com/sieg-wang/better-rm/main/install-hooks.sh | bash -s -- -a claude',
  'curl -sSL https://raw.githubusercontent.com/sieg-wang/better-rm/main/install-hooks.sh | bash -s -- -a claude --global',
];

// Trim and collapse ASCII space, tab, CR and LF only -- deliberately NOT
// String.trim(), which also eats U+00A0 and the other Unicode spaces. A trailing
// non-breaking space is a character the shell KEEPS, so `... | bash\u00a0` names
// a command word that does not exist; folding it away here would exempt a line
// this list does not hold. Interior newlines are not collapsed either, so
// `curl ... |\nbash` is not this line.
// 只處理 ASCII 的 space／tab／CR／LF，刻意不用 String.trim()（它連 U+00A0 之類都會吃掉）。
// 尾端的 non-breaking space 是 shell 會留下來的字元，`… | bash\u00a0` 指的是一個不存在的
// 命令字；在這裡把它折掉，等於豁免一條清單上沒有的行。中間的換行也不會被併掉。
const isCanonicalInstallLine = (raw) => CANONICAL_INSTALL_LINES.includes(
  String(raw || '')
    .replace(/^[ \t\r\n]+/, '')
    .replace(/[ \t\r\n]+$/, '')
    .replace(/[ \t]+/g, ' ')
);

// Deny-by-default option allowlists for an exempted fetch. An option that is
// NOT on these lists makes the producer unreadable again, which is the
// fail-closed direction: a curl option added upstream cannot silently join the
// exemption, and a reader can see exactly what the exemption tolerates.
// 豁免抓取的選項白名單（預設拒絕）。不在清單上的選項會讓產生器重新變成「讀不到」，這是
// fail-closed 的方向：curl 日後新增的選項不會自己混進豁免裡，而且讀的人一眼看得出豁免容忍
// 的到底是哪幾個選項。
const EXEMPT_CURL_OPTIONS = /^(?:-[sSLf46#]+|--silent|--show-error|--location|--fail|--ipv4|--ipv6|--compressed|--no-progress-meter)$/;
const EXEMPT_WGET_OPTIONS = /^(?:-q|-nv|-4|-6|-O-|-qO-|--quiet|--no-verbose|--output-document=-)$/;

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

// The scans this walk has already done for THIS top-level command, keyed by the
// three things that decide a scan's answer: the text, the depth it is read at
// (the depth cap is part of the answer) and whether the caller is handing it a
// shell body. `expansionEnv` is not in the key -- it is threaded through every
// recursive call unchanged, so it is the same object for the whole invocation;
// the memo records the one it was built for and refuses to answer for any other,
// so a future caller that threads a different environment gets a real scan
// rather than a stale one.
// WHY IT EXISTS, with the measurement: the env -S walk below re-reads the SAME
// inner text three times (the string itself, the string with leading assignments
// stripped, and the string re-prefixed as env's own argv), and the operand scan
// reads it once more -- four scans of one text per level. Nested, that is 4^depth
// scans of texts that are byte-identical, so `env -S "env -S \"... rm -rf build\""`
// eight levels deep produced 87,381 scans and 65,536 copies of ONE target.
// Measured 2026-09-05 with node 22.17.0 on this Mac: 65,536 targets cost 1,024 ms
// of judging on arm64 and 1,461 ms on x86_64 (Rosetta) in a fresh process, and
// inside the full suite the x86_64 run crossed the 2,000 ms JUDGING_BUDGET_MS --
// `judged 64800 of 65536` -- so a BENIGN `rm -rf build` was refused as
// unjudgeable on the ubuntu-24.04 runner (x86_64) and allowed on this Mac
// (arm64). That is a fail-closed direction bug, but it is still the gate giving
// two different answers to one command because of how fast the host is.
// Deduplicating is not a heuristic: a repeated scan of the same text at the same
// depth is the same pure computation, and judging the same target twice cannot
// find anything the first judgement did not. 87,381 scans collapse to 17 and the
// cost becomes linear in the nesting depth.
// The arrays handed back are shared, so no caller may mutate one; every call
// site spreads the result into its own `targets` and none does.
// 這一次頂層命令裡「已經掃過」的結果，鍵是決定答案的三件事：文字、讀它時的 depth（深度上限
// 也是答案的一部分）、以及呼叫端是否把它當成 shell 內文交過來。`expansionEnv` 不在鍵裡——它
// 在每一次遞迴呼叫都原封不動傳下去，整趟就是同一個物件；memo 記下自己是為哪一個建的，換了
// 別的就不作答，改走真正的掃描，未來有人改傳別的環境也不會拿到過期答案。
// 為什麼要有它（附實測）：下面 env -S 的走訪會把「同一段內層文字」讀三次（字串本身、去掉開
// 頭指派後的字串、重新前綴成 env 自己 argv 的字串），操作元掃描再讀一次——一層四次。層層相
// 疊就是 4^depth 次「位元組完全相同」的掃描：八層的
// `env -S "env -S \"... rm -rf build\""` 產生 87,381 次掃描與 65,536 份「同一個」目標。
// 2026-09-05 用 node 22.17.0 在這台實測：65,536 個目標的判定在 arm64 是 1,024 ms、在 x86_64
// （Rosetta）是 1,461 ms（單跑一條的新行程）；放進整套測試裡，x86_64 那一輪越過了 2,000 ms
// 的 JUDGING_BUDGET_MS——`judged 64800 of 65536`——於是一條無害的 `rm -rf build` 在
// ubuntu-24.04（x86_64）runner 上被當成「判不完」拒絕，在這台 Mac（arm64）上卻放行。方向是
// fail-closed 沒錯，但同一條命令因為主機快慢而得到兩種答案。
// 去重不是啟發式：同一段文字在同一個 depth 再掃一次，是同一個純計算；同一個目標判第二次也
// 不可能找到第一次沒找到的東西。87,381 次掃描收斂成 17 次，成本從指數變成隨層數線性。
// 回傳的陣列是共用的，任何呼叫端都不得就地修改；所有呼叫端都是把結果展開進自己的 `targets`，
// 沒有一個會改它。
let nestedScanMemo = null;

// What a repeated scan is allowed to contribute. Every one of the eleven nested
// call sites does `targets.push(...nestedScan(...))`, and every scan returns its
// own `targets`, so whatever the FIRST scan of a text found has already been
// pushed all the way up into the top-level list. A second scan of the same text
// at the same depth can therefore only append a copy of targets that are already
// there: the SET is unchanged, and dropping the copies is what turns 65,536
// entries into one. Frozen because it is shared by every repeat.
// 重複掃描能貢獻的東西。十一個巢狀呼叫端全都是 `targets.push(...nestedScan(...))`，而每一次
// 掃描回傳的都是它自己的 `targets`，所以「第一次」掃到的東西早就一路被推進最上層的清單了。
// 同一段文字在同一個 depth 再掃一次，只能追加一份「已經在裡面」的副本：集合不變，把副本丟掉
// 正是 65,536 收斂成 1 的原因。凍結，因為所有重複共用同一個。
const NO_NEW_TARGETS = Object.freeze([]);

function nestedScan(text, depth, bodiesAreCode, expansionEnv) {
  if (nestedScanMemo === null || nestedScanMemo.expansionEnv !== expansionEnv) {
    return commandTargetsScan(text, depth, bodiesAreCode, expansionEnv);
  }
  const key = `${depth}\u0000${bodiesAreCode ? 1 : 0}\u0000${text}`;
  if (nestedScanMemo.scanned.has(key)) return NO_NEW_TARGETS;
  // Recorded BEFORE the scan runs, so a text that somehow reached itself could
  // not spin -- depth strictly increases on every nested call, so it cannot, and
  // this costs nothing to guarantee anyway.
  // 在掃描開始「之前」就記錄，萬一有文字繞回自己也不會空轉——每次巢狀呼叫 depth 都嚴格遞增，
  // 本來就繞不回來，但保證它不花任何成本。
  nestedScanMemo.scanned.add(key);
  return commandTargetsScan(text, depth, bodiesAreCode, expansionEnv);
}

// The entry point, and the only owner of the memo: it lives for exactly one
// top-level scan and is dropped in a `finally`, so a throw cannot leave answers
// behind for the next command. Re-entrant by construction -- an inner call that
// reached this function instead of nestedScan() would find a memo already owned
// and would not clear it.
// 進入點，也是 memo 唯一的擁有者：只活在一次頂層掃描裡，並在 `finally` 清掉，即使中途丟出
// 例外也不會把答案留給下一條命令。設計上可重入——萬一有內層呼叫走到這個函式而不是
// nestedScan()，它會看到 memo 已經有主人，不會把它清掉。
function commandTargets(command, depth = 0, bodiesAreCodeFromCaller = false, expansionEnv = null) {
  const owned = nestedScanMemo === null;
  if (owned) nestedScanMemo = { expansionEnv, scanned: new Set() };
  try {
    return commandTargetsScan(command, depth, bodiesAreCodeFromCaller, expansionEnv);
  } finally {
    if (owned) nestedScanMemo = null;
  }
}

function commandTargetsScan(command, depth = 0, bodiesAreCodeFromCaller = false, expansionEnv = null) {
  const words = shellWords(command);
  const dynamicExpansions = words.dynamicExpansions || [];
  // Which words were written as unquoted shell operators. `;`, `\;` and `';'`
  // tokenize to the same one-character word and only the FIRST of them ends a
  // command, so every scan that decides where a simple command stops has to ask
  // this and not just what the word spells.
  // 哪些字是「未加引號的 shell 運算子」。`;`、`\;`、`';'` 斷詞後是同一個單字元字，而只有第
  // 一個會結束命令，所以每一處判斷「簡單命令在哪裡停住」的掃描都必須問這個，而不是只問這個
  // 字長什麼樣。
  const operatorTokens = words.operatorTokens || [];
  // The one place that pairing is written down (r5-fix-better-rm-6, R5-f). Before
  // it, `rm -rf ';' /etc` was ALLOWED and really removed /etc: `;` `&` `|` `(`
  // `)` are in `terminators`, so the operand scan stopped and collected nothing,
  // and `>` `<` `<<` are in `redirectors`, whose arm skips the operator AND the
  // word after it -- the target. `&&` `||` `;;` `2>` `>>` `{` `}` are in neither
  // set, so the same quoting trick with them never hid anything: that asymmetry
  // is what says set membership, not quoting, was doing the deciding.
  // A quoted operator-shaped word is an ordinary OPERAND, and must go on being
  // one -- so this reads as a question about the word's spelling AND its writing,
  // never as "refuse anything that looks like an operator".
  // Grep for `operatorAt(` to see every scan that asks; the sites that
  // deliberately do NOT are the `controlWords` ones (`{`, `}`, `if`, ... are
  // words, not operators, and a quoted one is already an ordinary operand there).
  // 這一對關係只寫在這裡（r5-fix-better-rm-6，R5-f）。在它之前，`rm -rf ';' /etc` 是放行的，
  // 而且真的會刪掉 /etc：`;` `&` `|` `(` `)` 屬於 `terminators`，操作元掃描直接停下、什麼都
  // 沒收；`>` `<` `<<` 屬於 `redirectors`，那條臂會跳過運算子「以及它後面那個字」——也就是目
  // 標。`&&` `||` `;;` `2>` `>>` `{` `}` 兩個集合都不屬於，同樣的加引號手法對它們從來藏不住
  // 東西：這個不對稱正說明真正在做決定的是集合成員資格，不是引號。
  // 加了引號、長得像運算子的字是「普通操作元」，而且必須繼續是——所以這裡問的是「字面 且 寫
  // 法」，絕不是「凡是長得像運算子就拒絕」。
  // 用 `operatorAt(` grep 就能看到每一處會問的掃描；刻意不問的是 `controlWords` 那幾處
  // （`{`、`}`、`if` … 是「字」不是運算子，加了引號在那裡本來就已經是普通操作元）。
  const operatorAt = (index, set) => operatorTokens[index] === true && set.has(words[index]);
  const targets = [];
  // R5-13: EVERY failed-read budget in this file fails CLOSED, through one
  // helper, applied at every site that spends one. A budget bounds what a scan
  // may cost; it must not also decide what the gate answers. Past the cap the
  // readers stop reading, so a `$( ... )` after the padding is never returned and
  // its body is never scanned -- and until this helper existed, that produced no
  // refusal at all: `cat <<EOF` + 64 x `$(` + `EOF` + `echo $(rm -rf /etc)` was
  // ALLOWED and really removed the target (measured 2026-09-05).
  // One helper rather than four copies of the test, for the reason this file
  // gives everywhere else: the copies are what drift. Every call that spends a
  // budget in this scan goes through it -- shellWords here, commandSubstitutions
  // over `scannable`, and the two inside the producer/carrier classifiers below
  // -- and each of those is measurably reachable on its own (test-hooks.js pins
  // one row per site). A sentinel pushed here refuses the WHOLE invocation, not
  // just the segment: the part of the command this gate did not read is not
  // scoped to the segment the padding sat in.
  // R5-13：本檔案「每一份」失敗讀取預算都 fail-closed，統一走這一個 helper。預算界的是成本，
  // 不該連「閘門要回答什麼」也一起決定。上限之後 reader 不再讀，填充後面的 `$( ... )` 不會被
  // 回傳、內文也不會被掃——而在這個 helper 出現之前，那個狀態不產生任何拒絕（實測：上面那條
  // 命令被放行且真的刪掉目標）。寫成一個 helper 而不是四份相同的判斷，理由與本檔案其他地方
  // 一樣：會走鐘的永遠是抄出來的那幾份。
  const noteSubstitutionBudget = (scanned) => {
    if (scanned.failedSubstitutionReads >= MAX_FAILED_SUBSTITUTION_READS) {
      targets.push(SUBSTITUTION_BUDGET_EXHAUSTED + scanned.failedSubstitutionReads);
    }
    return scanned;
  };
  noteSubstitutionBudget(words);
  const separators = new Set([';', '&', '|', '(', ')', '<', '>', '\n']);
  // Redirections (`<`, `>`) stay within a simple command; they are not command
  // terminators. The rm/rmdir argument scan must skip a redirection and its
  // operand and keep collecting targets, or a leading `>/dev/null` hides them.
  // `<<` and `<<-` are the same shape -- operator plus operand -- and their
  // operand is a delimiter, never a path. The body they introduce is not in this
  // word stream at all; it sits beside it, addressed by the operator's index.
  // `<<` 與 `<<-` 形狀相同：運算子加操作元，而那個操作元是結束標記、不是路徑。它們帶出
  // 來的內文根本不在這串字裡，而是放在旁邊、用運算子的索引定址。
  // '<<<' belongs here for the same reason as '<<': it is an operator whose
  // operand is not a path the command deletes. It fed rm's STDIN, which rm never
  // reads, and collecting it as a target made `rm -rf ./build <<< /etc` refuse
  // while NAMING /etc -- a path that command does not touch. It is safe to skip
  // here specifically because the two carrier routes above now claim the same
  // operand as a script, so it is not skipped everywhere, only in the scan that
  // was reading it as a filename.
  // '<<<' 屬於這裡,理由與 '<<' 相同:它是運算子,操作元不是那條命令會刪掉的路徑。它餵的是
  // rm 的 stdin,而 rm 從不讀 stdin,把它當目標收走會讓 `rm -rf ./build <<< /etc` 以「/etc」
  // 為由被拒——那條命令根本不碰 /etc。在這裡跳過是安全的,正因為上面兩條 carrier 路徑已經
  // 把同一個操作元當成腳本接手了:它不是到處都被跳過,只在原本把它讀成檔名的那個掃描裡。
  const redirectors = new Set(['<', '>', '<<', '<<-', '<<<']);
  // operator word index -> the heredoc body it introduced.
  const heredocBodies = new Map((words.heredocs || []).map((entry) => [entry.operatorIndex, entry.body]));
  const terminators = new Set([';', '&', '|', '(', ')', '\n']);
  const controlWords = new Set([
    'if', 'then', 'elif', 'else', 'fi',
    'for', 'while', 'until', 'select', 'do', 'done',
    'case', 'in', 'esac', '{', '}',
  ]);
  // csh/tcsh belong here for the same reason every other name does: a script
  // piped into one really runs. On this stock macOS /bin/csh and /bin/tcsh are the
  // same inode, both are in /etc/shells, and a touch payload through either one
  // executes -- while `fish`, already on this list, is not installed here at all.
  // The four lists derived below are spreads of this one, so this is the only
  // place a carrier name is written.
  // csh／tcsh 屬於這裡的理由與其他每一個名字相同：灌進去的腳本真的會執行。在這台原廠 macOS
  // 上 /bin/csh 與 /bin/tcsh 是同一個 inode、都在 /etc/shells 裡；反倒是清單上的 fish 沒裝。
  // 下面四份清單都是對這一份的展開，所以 carrier 名字只在這裡寫一次。
  const shellCarriers = new Set(['sh', 'bash', 'dash', 'zsh', 'ksh', 'fish', 'csh', 'tcsh']);
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
    // `afterEnv` is the same env(1)-versus-shell distinction the executable walk
    // makes below: BEFORE any wrapper, an assignment prefix must be a shell
    // IDENTIFIER (`FOO%%=1 bash -c '...'` runs nothing -- bash reports
    // `FOO%%=1: command not found`, measured), but AFTER `env` any word with an
    // `=` is an assignment and the shell behind it really runs. Without this,
    // `env "F-O=1" bash <<'EOF' ... EOF` stopped the walk at the odd name, no
    // carrier was seen, and the heredoc body was read as data -- measured
    // 2026-09-05, the body's touch marker was created (both for `bash` and for
    // `bash -s`) while the hook allowed the line.
    // `afterEnv` 就是底下那個「env(1) 不是 shell」的區分：在任何包裝命令之前，指派前綴必須
    // 是 shell 識別字（`FOO%%=1 bash -c '…'` 什麼都不會跑，bash 會說
    // `FOO%%=1: command not found`，實測），但在 `env` 之後，任何含 `=` 的字都是指派，它後
    // 面的 shell 是真的會跑的。少了這一條，`env "F-O=1" bash <<'EOF' … EOF` 會在那個怪名字
    // 上停住、看不到 carrier、heredoc 內文被當成資料——2026-09-05 實測，內文的 touch marker
    // 真的被建立（`bash` 與 `bash -s` 都是），而 hook 放行了那一行。
    let afterEnv = false;
    for (let w = 0; w < words.length; w += 1) {
      const word = words[w];
      if (operatorAt(w, separators)) { atCommandPosition = true; afterEnv = false; continue; }
      if (!atCommandPosition) continue;
      const name = path.basename(word);
      if (carriers.has(name)) { carrierPresent = true; break; }
      if (transparent.has(name)) { if (name === 'env') afterEnv = true; continue; }
      if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(word)) continue;
      if (afterEnv && !word.startsWith('-') && word.includes('=')) continue;
      atCommandPosition = false;
    }
  }

  // `env -S "<string>"` is env parsing its own arguments a second time, not a
  // shell parsing a command line, and the difference is the same one as above:
  // inside that string too, ANY word containing `=` is an assignment and the
  // first word without one is the command. Re-tokenizing the string as a SHELL
  // line gets the identifier spellings right by accident (a shell also skips
  // `FOO=1` as a prefix) and the odd ones wrong: re-read as a shell line,
  // `env -S "FOO%%=1 rm -rf /etc"` has `FOO%%=1` in command position, so `rm`
  // never is, and the line was ALLOWED. Measured 2026-09-05 with touch markers:
  // `FOO%%=1`, `F-O=1` and `FOO.BAR=1` all really ran the command under BSD env
  // and under GNU coreutils 9.11 env. The stripped text is ADDED to the scan and
  // never substituted for it, for the same reason the emitter scans are additive:
  // a strip that guesses wrong must not be able to hide what the raw text shows.
  // `env -S "<字串>"` 是 env 再解析一次「自己的參數」，不是 shell 在解析命令列，差別跟上面
  // 那條一樣：那個字串裡面，只要一個字含 `=` 就是指派，第一個沒有 `=` 的字才是命令。把它當
  // shell 那樣重新斷詞，識別字寫法會「碰巧」對（shell 同樣會跳過 `FOO=1` 前綴），怪名字就錯
  // 了：`env -S "FOO%%=1 rm -rf /etc"` 當 shell 讀時 `FOO%%=1` 站在命令位置，`rm` 就永遠不在
  // 命令位置，於是放行。2026-09-05 用 touch marker 實測：`FOO%%=1`、`F-O=1`、`FOO.BAR=1` 在
  // BSD env 與 GNU coreutils 9.11 env 上都真的把命令跑掉了。剝掉指派之後的文字是「加入」掃描
  // 而不是取代原文，理由與產生器那四種掃法相同：剝錯的時候，不可以把原文看得見的東西藏起來。
  // What `-S` splits into does not stand alone: env INSERTS those words into its
  // own argument list in place of the option, so the words that follow `-S` on
  // the real command line are the split command's OPERANDS. Judging the string
  // by itself stops at that boundary, and the operands -- which is where the
  // path is -- were never seen: `env -S 'rm' -rf /etc`, `env -S 'FOO=1 rm' -rf
  // /etc` and `env -S '-u X rm' -rf /etc` were all ALLOWED while env really ran
  // the deletion. Measured 2026-09-05 with mkdir markers on BOTH implementations
  // this repository runs on -- macOS BSD env (whose usage line is
  // `env [-0iv] [-C workdir] [-P utilpath] [-S string] [-u name] ...`) and GNU
  // coreutils 9.11 env, the ubuntu runner's: all eight shapes below executed on
  // both, sixteen for sixteen, and `env -S 'FOO=1 /usr/bin/env' | grep -c
  // '^FOO=1'` = 1 on both, so the assignment inside the string is really kept.
  // The reconstruction is scanned as env's ARGV -- literally by prefixing `env`
  // -- rather than as a shell line, because that is what it is: the walk above
  // then applies env's own rules (any word with `=` is an assignment, options
  // take their values, `--` ends them) instead of the shell's, which is the
  // difference that leaves `-u X rm` with `-u` in command position when a shell
  // reads it. Each appended word is re-quoted so re-tokenizing reproduces it
  // exactly: `words` has already had its quotes removed, so joining them bare
  // would re-split any operand containing a space and lose it -- measured, with
  // a protected directory named `/workspace/my secrets`, which a bare join turns
  // into the two unprotected words `/workspace/my` and `secrets` and allows.
  // This scan is ADDED to the two above and never substituted for them, for the
  // same reason they are additive.
  // `-S` 拆出來的那些字並不是獨立的一條命令：env 會把它們「插回自己的參數表」取代該選項，
  // 所以命令列上跟在 `-S` 後面的字，就是那個命令的操作元。只判斷字串本身會停在這個邊界上，
  // 而路徑正好在外面，於是 `env -S 'rm' -rf /etc`、`env -S 'FOO=1 rm' -rf /etc`、
  // `env -S '-u X rm' -rf /etc` 全部被放行，而 env 真的把刪除跑掉了。2026-09-05 用 mkdir
  // marker 在本 repo 會跑到的兩種實作上實測（macOS BSD env 與 ubuntu runner 的 GNU
  // coreutils 9.11 env）：下面八種形狀十六次全部執行，且兩邊
  // `env -S 'FOO=1 /usr/bin/env' | grep -c '^FOO=1'` 都是 1。重組出來的文字是當成 env 的
  // 「argv」來掃（直接前綴一個 `env`）而不是當成 shell 命令列，因為它本來就是 argv：上面
  // 那段走訪會套用 env 自己的規則（含 `=` 就是指派、選項吃掉自己的值、`--` 結束選項），
  // 而不是 shell 的規則——`-u X rm` 被 shell 讀時 `-u` 會站在命令位置，差別就在這裡。
  // 每個附加的字都重新加引號，好讓重新斷詞完全還原：`words` 的引號早就被拿掉了，直接用空白
  // 接起來會把 `"/etc/my dir"` 重新拆開，也會讓加了引號的 `';'` 把掃描截斷。這一掃是「加入」
  // 上面兩掃而不是取代它們，理由與它們是加法的理由相同。
  const envArgvWordLiteral = (word) => `'${String(word).replace(/'/g, "'\\''")}'`;
  // env(1)'s own -S grammar, and only the part of it that both implementations
  // agree on. Everything else returns `unjudgeable` and the caller fails closed.
  // Measured 2026-09-05 with marker directories on macOS BSD env and on GNU
  // coreutils 9.11 env (the ubuntu-24.04 runner's), identical on both:
  //   `mkdir\_-p <dir>`        creates it  -> `\_` is a space that SPLITS
  //   `mkdir # x -p <dir>`     creates it  -> `#` at a word start comments to the
  //                                            end of the STRING, and the argv
  //                                            after -S still follows
  //   `mkdir#x -p <dir>`       creates nothing -> `#` mid-word is not a comment
  //   `mkdir\ -p <dir>`        creates nothing -> `\ ` is not a word split
  //   `mkdir\t-p <dir>`        creates nothing -> an escape does not split
  //   `mkdir\c -p <dir>`       creates it  -> `\c` ends the string early
  //   `${MKDIRNAME} -p <dir>`  creates it  -> `$` really is expanded
  //   `mkdir '-p' <dir>` and `mkdir "-p" <dir>` create it -> quotes group
  // env(1) 自己的 -S 文法，而且只取兩種實作都同意的那一部分；其餘一律回報 unjudgeable，由呼
  // 叫端失敗即關閉。2026-09-05 用 marker 目錄在 macOS BSD env 與 GNU coreutils 9.11 env（即
  // ubuntu-24.04 runner 用的那個）上實測，兩邊完全一致，逐條如上。
  const ENV_S_ESCAPES = new Map([
    ['\\', '\\'], ['#', '#'], ['$', '$'], ["'", "'"], ['"', '"'],
    ['f', '\f'], ['n', '\n'], ['r', '\r'], ['t', '\t'], ['v', '\v'],
  ]);
  const envSplitWords = (text) => {
    const words = [];
    let word = '';
    let building = false;
    let quote = '';
    const endWord = () => { if (building) { words.push(word); word = ''; building = false; } };
    const add = (char) => { word += char; building = true; };
    for (let k = 0; k < text.length; k += 1) {
      const char = text[k];
      // A `$` is an expansion in every position this gate can see, and what it
      // expands to is not knowable here.
      // `$` 在這裡看得到的每一個位置都是展開，展開成什麼在這裡不可能知道。
      if (char === '$') return { words, unjudgeable: 'a $ expansion' };
      if (quote === "'") {
        if (char === "'") { quote = ''; continue; }
        // A backslash inside single quotes is a quirk, not a rule: measured on
        // both implementations, `-S "DUMP 'a\\\\b'"` yields <a\\b> (the `\\\\` WAS
        // processed) while `-S "DUMP 'a\\_b'"` yields <a\\_b> (the `\\_` was NOT).
        // Two escapes, two answers, inside the same quotes -- not a rule this
        // gate can carry, so it stops.
        // 單引號裡的反斜線是個怪癖而不是規則：兩種實作實測，`'a\\\\b'` 得到 <a\\b>（`\\\\` 有被處
        // 理），`'a\\_b'` 得到 <a\\_b>（`\\_` 沒有）。同樣在單引號裡、兩個跳脫兩種答案——這不是
        // 這道閘門扛得住的規則，所以就此停下。
        if (char === '\\') return { words, unjudgeable: 'a backslash inside single quotes' };
        add(char);
        continue;
      }
      if (quote === '"') {
        if (char === '"') { quote = ''; continue; }
        if (char !== '\\') { add(char); continue; }
        // Inside double quotes `\_` is a literal space that does NOT split, and
        // `\c` was not measured there, so it is not modelled there.
        // Measured with an argv dumper on both implementations:
        //   -S 'DUMP a\_b'    -> argc=2 <a><b>
        //   -S 'DUMP "a\_b"'  -> argc=1 <a b>
        // 雙引號裡的 `\_` 是「不會切開」的字面空白，而 `\c` 在引號裡沒有實測過，所以不建模。
        if (text[k + 1] === '_') { k += 1; add(' '); continue; }
        if (text[k + 1] === 'c') return { words, unjudgeable: 'a \\c inside double quotes' };
      } else {
        if (char === "'") { quote = "'"; building = true; continue; }
        if (char === '"') { quote = '"'; building = true; continue; }
        if (char === ' ' || char === '\t' || char === '\n') { endWord(); continue; }
        // Only at a word START. `mkdir#x` is a command name, measured.
        // 只在「字首」。`mkdir#x` 是命令名稱，實測如此。
        if (char === '#' && !building) { endWord(); return { words, unjudgeable: null }; }
        if (char !== '\\') { add(char); continue; }
      }
      // A backslash, in either the unquoted or the double-quoted state.
      // 反斜線，未加引號與雙引號兩種狀態共用。
      const next = text[k + 1];
      if (next === undefined) return { words, unjudgeable: 'a trailing backslash' };
      k += 1;
      // `\_` IS the separator; the space it stands for does not stay in the word.
      // Measured: -S 'DUMP a\_b' -> argc=2 <a><b>, not <a ><b>.
      // `\_` 本身就是分隔符；它代表的那個空白不會留在字裡。
      if (next === '_') { endWord(); continue; }
      if (next === 'c') { endWord(); return { words, unjudgeable: null }; }
      const literal = ENV_S_ESCAPES.get(next);
      if (literal === undefined) return { words, unjudgeable: `the escape \\${next}` };
      add(literal);
    }
    if (quote) return { words, unjudgeable: 'an unclosed quote' };
    endWord();
    return { words, unjudgeable: null };
  };
  const envSplitStringTargets = (splitString, argvAfter = []) => {
    const text = String(splitString || '');
    if (!text && argvAfter.length === 0) return;
    if (depth >= 8) { targets.push('/'); return; }
    if (text) targets.push(...nestedScan(text, depth + 1, false, expansionEnv));
    const parts = text.trim().split(/\s+/);
    let p = 0;
    while (p < parts.length && !parts[p].startsWith('-') && parts[p].includes('=')) p += 1;
    const stripped = parts.slice(p).join(' ');
    if (p > 0 && stripped) targets.push(...nestedScan(stripped, depth + 1, false, expansionEnv));
    // The -S string is env's ARGV, so it is split by env's rules and then each
    // word is re-quoted exactly the way the words after -S already are. Splicing
    // the raw string in and letting the SHELL lexer re-split it was the defect:
    // `rm\_-rf` came back as the single word `rm_-rf` (no command at all) and
    // `rm # x` truncated the reconstruction at the `#`, dropping the very
    // operands it exists to append. Measured 2026-09-05 with marker directories,
    // both spellings really run `rm -rf <target>` on BSD env and on GNU env.
    // -S 字串就是 env 的 argv，所以用 env 的規則切、再把每個字照 -S 後面那些字已經在用的方
    // 式重新加引號。把原始字串原封不動接進去、讓 shell 斷詞器重新切，就是那個缺陷：
    // `rm\_-rf` 會變回單一個字 `rm_-rf`（根本不是命令），而 `rm # x` 會在 `#` 上把重組截
    // 斷，丟掉的正是它要接上去的那些操作元。2026-09-05 用 marker 目錄實測，兩種拼法在 BSD
    // env 與 GNU env 上都真的跑了 `rm -rf <目標>`。
    const split = envSplitWords(text);
    if (split.unjudgeable) targets.push(UNJUDGEABLE_ENV_S + split.unjudgeable);
    const asEnvArgv = ['env', ...split.words.map(envArgvWordLiteral), ...argvAfter.map(envArgvWordLiteral)]
      .filter((piece) => piece !== '')
      .join(' ');
    targets.push(...nestedScan(asEnvArgv, depth + 1, false, expansionEnv));
  };
  // The words that follow the `-S` option, up to the end of this simple command.
  // `separators` alone is what the enclosing walk (`while (i < words.length &&
  // !separators.has(words[i]))` just below) and both rm operand scans use to
  // decide where a simple command ends, so this stops exactly where they do.
  // That shared rule treats a QUOTED separator-shaped word as a separator too,
  // which is a real pre-existing gap -- `rm -rf ';' /etc` yields no targets and
  // is ALLOWED with no env(1) involved at all -- but it is one property of the
  // whole gate, not of this reconstruction, and reading `operatorTokens` here
  // alone would fork the convention without closing anything: the operand scan
  // truncates on the same word a moment later. Measured: making this site read
  // `operatorTokens` changes no row of the 47-row env probe and no row of the
  // 823-row corpus. Reported as a finding instead of patched here.
  // 跟在 `-S` 選項後面、到這條簡單命令結束為止的那些字。外層走訪（緊接在下面那句
  // `while (i < words.length && !separators.has(words[i]))`）與兩處 rm 操作元掃描，判斷
  // 簡單命令在哪裡結束用的都是 `separators` 本身，所以這裡停的位置與它們完全一致。那條共用
  // 規則會把「加了引號、長得像分隔符」的字也當成分隔符，這確實是既有的缺口——`rm -rf ';'
  // /etc` 掃不出任何目標、而且完全沒有 env(1) 也一樣被放行——但那是整道閘門的性質，不是這段
  // 重組的性質；只在這裡改讀 `operatorTokens` 會分岔慣例卻關不掉任何東西：操作元掃描下一步
  // 就會在同一個字上截斷。實測：這一處改讀 `operatorTokens`，47 列 env 探針與 823 列語料
  // 都沒有任何一列改變。因此列為 finding 回報，不在這裡就地修補。
  const envArgvAfter = (from) => {
    const rest = [];
    for (let k = from; k < words.length && !operatorAt(k, separators); k += 1) rest.push(words[k]);
    return rest;
  };
  // A here-string is the same shape as a heredoc body for this purpose, and it
  // needs the same second route: `source /dev/stdin <<< "rm -rf /etc"` never
  // reaches the shellCarriers branch (`source` is not one of them), so the arm
  // added there does not cover it. Its heredoc twin was already refused here,
  // which is what makes the gap visible: two spellings of one command, one
  // refused and one allowed.
  // here-string 在這裡與 heredoc 內文是同一種形狀,需要同一條第二路徑:
  // `source /dev/stdin <<< "rm -rf /etc"` 根本不會走到 shellCarriers 分支(source 不在
  // 那個集合裡),所以那邊新增的分支蓋不到它。它的 heredoc 雙胞胎在這裡早就被拒了。
  const hereStringBodies = [];
  for (let hi = 0; hi + 1 < words.length; hi += 1) {
    if (operatorTokens[hi] && words[hi] === '<<<') hereStringBodies.push(words[hi + 1]);
  }
  if (carrierPresent) {
    for (const entry of bodies) {
      if (depth >= 8) targets.push('/');
      else targets.push(...nestedScan(entry.body, depth + 1, true, expansionEnv));
    }
    for (const body of hereStringBodies) {
      if (depth >= 8) targets.push('/');
      else targets.push(...nestedScan(body, depth + 1, true, expansionEnv));
    }
  }

  // Unquoted bodies stay in `scannable` (their substitutions really run), so the
  // comment rule has to be switched off across exactly those spans.
  // 未加引號的內文仍留在 scannable 裡（它們的替換是真的會執行），所以註解規則必須在正好
  // 那些區間上關閉。
  const unquotedBodySpans = (words.heredocs || [])
    .filter((entry) => !entry.quoted)
    .map((entry) => [entry.bodyStart, entry.bodyEnd]);
  const substitutions = noteSubstitutionBudget(
    commandSubstitutions(scannable, unquotedBodySpans),
  );
  if (substitutions.length > 0) {
    if (depth >= 8) targets.push('/');
    else {
      for (const nested of substitutions) {
        targets.push(...nestedScan(nested, depth + 1, carrierPresent, expansionEnv));
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
    // xargs' `-I`/`-i`/`--replace` string, when one was given. Null means the
    // command line carried none, in which case xargs APPENDS the stdin words
    // instead of substituting them.
    // xargs 的替換字串（沒有就是 null，那時 xargs 是把 stdin 的字「接在後面」）。
    let xargsReplaceString = null;
    while (i < words.length && !operatorAt(i, separators)) {
      while (i < words.length && /^[A-Za-z_][A-Za-z0-9_]*=/.test(words[i])) i += 1;
      if (i >= words.length || operatorAt(i, separators)) break;
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
          // env(1) is not the shell: it takes ANY word containing `=` as an
          // assignment, whatever the name looks like, and the first word without
          // one is the command. Testing for a shell IDENTIFIER here stopped the
          // walk at the odd name, so the command word was never found and
          // `env "FOO%%=1" rm -rf /etc` was ALLOWED while env really kept the
          // variable and really ran the rm. Measured 2026-09-05 with touch
          // markers on BOTH implementations this repository runs on -- macOS BSD
          // env and GNU coreutils 9.11 env (the ubuntu CI runner's) -- for
          // `FOO%%=1`, `F-O=1`, `FOO.BAR=1`, `1FOO=1` and `FOO BAR=1`: all ten
          // executed and all ten kept the variable. The one difference is the
          // EMPTY name `=1`: GNU env accepts it and execs, BSD env refuses with
          // `setenv =1: Invalid argument` and never execs. Counting it as an
          // assignment is the fail-closed side of that difference -- the gate
          // then finds the command word and judges it on the platform where it
          // runs, and over-denies on the platform where it would not have run.
          // A word starting with `-` is still an OPTION, not an assignment, so
          // `--split-string=...` keeps its own branch below.
          // env(1) 不是 shell：只要一個字裡面有 `=`，不管名字長什麼樣，它都當成變數指派，
          // 而第一個沒有 `=` 的字就是命令。這裡原本比對的是「shell 識別字」，於是走訪在那個
          // 怪名字上停住、命令字永遠找不到，`env "FOO%%=1" rm -rf /etc` 就被放行了——而 env
          // 真的把那個變數留著、真的執行了 rm。2026-09-05 用 touch marker 在本 repo 會跑到
          // 的兩種實作上實測（macOS 的 BSD env 與 ubuntu runner 的 GNU coreutils 9.11）：
          // `FOO%%=1`、`F-O=1`、`FOO.BAR=1`、`1FOO=1`、`FOO BAR=1` 十次全部執行、十次都留下
          // 變數。唯一的差別是「空名字」`=1`：GNU env 收下並執行，BSD env 直接報
          // `setenv =1: Invalid argument` 而不執行。把它也算成指派，是這個差異的 fail-closed
          // 那一邊——閘門因此會找到命令字、在真的會跑的平台上正確判定，而在不會跑的平台上多擋
          // 一次。以 `-` 開頭的字仍然是選項不是指派，所以 `--split-string=…` 走它自己的分支。
          if (!option.startsWith('-') && option.includes('=')) {
            i += 1;
          } else if (option === '--') {
            i += 1;
            break;
          } else if (option === '-S' || option === '--split-string') {
            envSplitStringTargets(words[i + 1] || '', envArgvAfter(i + 2));
            i += 2;
          } else if (option.startsWith('--split-string=')) {
            envSplitStringTargets(option.slice('--split-string='.length), envArgvAfter(i + 1));
            i += 1;
          } else if (option.startsWith('-S') && option.length > 2) {
            envSplitStringTargets(option.slice(2), envArgvAfter(i + 1));
            i += 1;
          } else if (/^-[iv]*S.+/.test(option)) {
            envSplitStringTargets(option.replace(/^-[iv]*S/, ''), envArgvAfter(i + 1));
            i += 1;
          } else if (/^-[iv]*S$/.test(option)) {
            envSplitStringTargets(words[i + 1] || '', envArgvAfter(i + 2));
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
        // xargs' options that take a SEPARATE following word, and only those
        // (R5-14). This set decides where the command word is, so an entry that
        // eats one word too many walks past the shell and allows the deletion the
        // rule exists to catch.
        // NOT here, and the reason is the grammar rather than a policy: GNU
        // findutils spells `-i[replace-str]`, `-e[eof-str]` and `-l[max-lines]`
        // with an OPTIONAL, ATTACHED argument (`--replace[=…]`, `--eof[=…]`,
        // `--max-lines[=…]` likewise), so a bare `-i` consumes nothing at all.
        // While they were in this set, `echo 'rm -rf /etc' | xargs -i sh -c '{}'`
        // swallowed `sh`, landed on `-c`, found no carrier and was ALLOWED, while
        // GNU xargs really runs `sh -c '<the stdin line>'`. The asymmetry that
        // exposed it: the attached `--replace={}` -- identical semantics -- was
        // refused all along. Grammar checked against the findutils manual
        // (man7.org/linux/man-pages/man1/xargs.1.html, 2026-09-05); it could not
        // be executed here, because this host's BSD xargs rejects all three
        // outright (`xargs: invalid option -- i`, measured), which also makes
        // refusing them fail-closed on both platforms.
        // ADDED here, and these are not theoretical: BSD's `-J replstr`,
        // `-R replacements` and `-S replsize` take a mandatory separate word and
        // were missing entirely, so the walk stopped ON the value. Measured on
        // this host with a marker file under bash 5.3.15 and /bin/bash 3.2.57:
        // `-R 3 -I{} sh -c '{}'`, `-S 5000 -I{} sh -c '{}'` and
        // `-J % -I{} sh -c '{}'` all really executed a payload that arrived on
        // stdin, and all three were ALLOWED. GNU's `--process-slot-var` is the
        // same shape.
        // xargs 裡「吃掉下一個字」的選項，而且只有這些（R5-14）。這個集合決定命令字在哪裡，
        // 多吃一個字就會走過 shell、放行本該被擋的刪除。
        // 不在這裡的：GNU 的 `-i[replace-str]`／`-e[eof-str]`／`-l[max-lines]`（以及三個長寫
        // 法）引數是「選填且相連」的，裸寫時一個字都不吃。它們還在集合裡時，`xargs -i sh -c`
        // 會把 `sh` 吞掉、停在 `-c`、找不到 carrier 而放行，而 GNU xargs 真的會執行 stdin 那
        // 一行。文法對照 findutils 手冊；本機 BSD xargs 直接拒絕這三個短選項（實測），所以
        // 兩邊都是 fail-closed。
        // 新加的：BSD 的 `-J`／`-R`／`-S` 原本完全不在表裡，走訪會停在它們的「值」上——這三個
        // 在本機用 marker 實測，`-R 3 -I{} sh -c '{}'`、`-S 5000 -I{} sh -c '{}'`、
        // `-J % -I{} sh -c '{}'` 都真的執行了從 stdin 進來的腳本，而且全部被放行。
        const optionsWithValue = new Set([
          '-a', '--arg-file', '-d', '--delimiter', '-E',
          '-I', '-J', '-L', '-n', '--max-args', '-P', '--max-procs',
          '-R', '-S', '-s', '--max-chars', '--process-slot-var',
        ]);
        while (i < words.length && words[i].startsWith('-')) {
          // xargs' REPLACE STRING, observed on the way past without changing how
          // many words each option consumes -- the walk above is what decides
          // where the command word is, and it is not this rule's to move.
          // It is needed because `-I{}` makes the `-c` argument a PLACEHOLDER
          // rather than a script: `… | xargs -I{} sh -c '{}'` shows a `-c` with
          // an argument, and what runs is the stdin line, not the `{}` on the
          // command line (measured, marker file, BSD xargs under bash 5.3.15 and
          // 3.2.57). Both separated (`-I {}`) and attached (`-I{}`) spellings,
          // plus GNU's `--replace=` and `-i` -- this repository ships to Linux
          // (README.md:7, CI on ubuntu-24.04), where those two exist.
          // xargs 的「替換字串」，只是順路記下來，不改變每個選項吃幾個字（命令字在哪裡由上面
          // 那段走訪決定，不歸這條規則動）。需要它是因為 `-I{}` 會讓 `-c` 的引數變成「佔位
          // 符」而不是腳本：真正跑的是 stdin 那一行（實測有 marker）。分開與相連的寫法都認，
          // 另外 GNU 的 `--replace=`／`-i` 也認，因為本專案有出貨到 Linux。
          const option = words[i];
          // `-I` and BSD's `-J` take their replace string as the NEXT word; the
          // optional-argument spellings (`-i`, `--replace`) written bare take no
          // word at all and mean `{}` -- "the effect is the same as -I{}", in the
          // findutils manual's own words. Reading `words[i + 1]` for those was
          // the same modelling error as the option table above, one line apart:
          // it named `sh` as the replace string AND ate it.
          // `-I` 與 BSD 的 `-J` 用「下一個字」當替換字串；`-i`／`--replace` 裸寫時不吃字，
          // 意思就是 `{}`（findutils 手冊原話：效果等同 `-I{}`）。對它們去讀下一個字，與上面
          // 那張表是同一個建模錯誤：把 `sh` 當成替換字串，還把它吃掉。
          if (option === '-I' || option === '-J') {
            xargsReplaceString = (i + 1 < words.length ? words[i + 1] : '') || '{}';
          } else if (option === '-i' || option === '--replace') {
            xargsReplaceString = '{}';
          } else if (option.startsWith('-J') && option.length > 2) {
            xargsReplaceString = option.slice(2);
          } else if (option.startsWith('--replace=')) {
            xargsReplaceString = option.slice('--replace='.length) || '{}';
          } else if (option.startsWith('-I') && option.length > 2) {
            xargsReplaceString = option.slice(2);
          } else if (option.startsWith('-i') && option.length > 2 && !option.startsWith('-i-')) {
            xargsReplaceString = option.slice(2);
          }
          i += optionsWithValue.has(words[i]) ? 2 : 1;
        }
        executable = '';
        continue;
      }

      break;
    }
    return {
      executable, executableIndex, index: i, stdinCompletesOperands, xargsReplaceString,
    };
  }

  // A carrier whose SCRIPT arrives on a PIPE or through a PROCESS SUBSTITUTION.
  // The routes above read a script the command line SHOWS (`-c`, a heredoc body,
  // a here-string). This one is about a script the command line does not show:
  // measured 2026-09-03 with the deletion replaced by a touch, so the marker
  // file proves the shell really runs them, `echo "rm -rf /etc" | bash`,
  // `curl … | bash`, `cat f | bash`, `bash <(…)` and `… | tee f | bash` were all
  // ALLOWED while their byte-equivalent heredoc and here-string spellings were
  // refused -- the only difference was where the script came from.
  // The rule, and it is a posture change the user approved (FOLLOWUP.md decision
  // 1, 2026-09-03): when a carrier's script comes from a pipe or a process
  // substitution, this gate must be able to READ it. A LITERAL emitter
  // (echo/printf words, `cat <<EOF`) is read and judged by the ordinary rules,
  // so `echo hi | bash` stays allowed; an install route on
  // PIPED_SCRIPT_EXCEPTIONS is let through; anything else -- INCLUDING a
  // producer this parser cannot classify -- is refused. There is no fail-open
  // branch here on purpose: an unclassifiable producer is a refusal, not an
  // allowance.
  // What it does NOT close, stated so nobody reads the rule as complete:
  // `bash < file`, `bash script.sh`, `bash -c "$(curl …)"` WITH NO PIPE (the
  // pipe-fed spelling `curl … | bash -c "$(cat)"` is refused since 2026-09-04),
  // `eval "$(curl …)"`, `… | xargs -I{} bash -c "{}"` and `… | xargs -0 bash -c`
  // are all still allowed (KNOWN-RESIDUALS.md R4-b), as is a carrier option that
  // takes an argument outside the bash/sh spellings this walk enumerates
  // (`curl … | fish -d 3`, R4-c). `cat f | bash` is refused while the one-character-different
  // `bash < f` is not, so anyone who knows the rule walks around it: what this
  // buys is that the gate stops being blind to a common shape, not that an
  // adversary cannot get a script past it.
  // carrier 的腳本從 pipe 或 process substitution 進來。上面那幾條路徑讀的是命令列「看得
  // 見」的腳本（-c、heredoc 內文、here-string），這一條講的是命令列看不見的那種：2026-09-03
  // 把刪除換成 touch 實測（標記檔證明 shell 真的會跑），`echo "rm -rf /etc" | bash`、
  // `curl … | bash`、`cat f | bash`、`bash <(…)`、`… | tee f | bash` 全部放行，而它們逐位元組
  // 等價的 heredoc 與 here-string 寫法卻都被拒——差別只在腳本從哪裡進來。
  // 規則（這是使用者裁決過的姿態改變，FOLLOWUP.md 決定 1）：carrier 的腳本從 pipe 或 process
  // substitution 進來時，這道閘門必須讀得到它。字面產生器（echo/printf 的字、`cat <<EOF`）
  // 會被讀出來、照一般規則判；PIPED_SCRIPT_EXCEPTIONS 上的安裝路徑放行；其餘一律拒絕，
  // 包含「這個解析器分類不出來的產生器」。這裡刻意沒有 fail-open 的分支。
  const r4Carriers = new Set([...shellCarriers, 'source', '.']);
  // `/proc/self/fd/0` is Linux's spelling of the two /dev entries beside it, and
  // this project ships to Linux (README.md:7, install.sh, CI on ubuntu-24.04).
  // It is text on the command line here, never a path this hook stats, so adding
  // it costs macOS nothing and cannot become a host-dependent answer.
  // `/proc/self/fd/0` 是旁邊那兩個 /dev 項目在 Linux 上的寫法，而本專案有出貨到 Linux。
  // 這裡它只是命令列上的文字，不會被 stat，所以在 macOS 上不花任何代價。
  const stdinScriptPaths = new Set(['/dev/stdin', '/dev/fd/0', '/proc/self/fd/0', '-']);
  // Matching ')' for every operator '(' , computed once for the whole word
  // stream. Scanning per substitution instead was quadratic on nested
  // `<( <( … ) )`, and a gate that outruns the live 5,000 ms hook timeout makes
  // NO decision and does not block the command -- slow is the same as absent,
  // which is the measurement the JUDGING_BUDGET_MS comment below was written for.
  // 每個運算子 '(' 的對應 ')' 只算一次。改成「每個替換各掃一次」在
  // `<( <( … ) )` 這種嵌套下是平方級，而跑贏 5,000 ms 逾時的閘門不做任何裁決、也不會擋下
  // 命令——「慢」等於「不存在」。
  const closingParen = new Map();
  {
    const openParens = [];
    for (let k = 0; k < words.length; k += 1) {
      if (!operatorTokens[k]) continue;
      if (words[k] === '(') openParens.push(k);
      else if (words[k] === ')' && openParens.length > 0) closingParen.set(openParens.pop(), k);
    }
  }
  // A command boundary for this rule. '<' and '>' are NOT boundaries: a
  // redirection stays inside its simple command. An '&' that FOLLOWS a '<' or
  // '>' operator is part of that redirection (`2>&1`), not a terminator --
  // without this carve-out `echo hi 2>&1 | bash` takes the word `1` for its
  // producer and newly refuses (measured ALLOW today, and pinned as an allow row).
  // 這條規則用的命令邊界。'<' 與 '>' 不是邊界（重導向留在它的簡單命令裡）。跟在 '<'／'>'
  // 之後的 '&' 屬於那個重導向（`2>&1`）而不是終止符——少了這個特例，
  // `echo hi 2>&1 | bash` 的產生器會變成 `1` 這個字而被新擋掉。
  const isCommandBoundary = (k) => {
    if (!operatorTokens[k]) return false;
    const word = words[k];
    if (word === ';' || word === '|' || word === '\n' || word === '(' || word === ')') return true;
    if (word !== '&') return false;
    return !(k > 0 && operatorTokens[k - 1] && (words[k - 1] === '>' || words[k - 1] === '<'));
  };
  // Exactly one '|' in the boundary run, so `||` -- which this tokenizer emits
  // as two separate '|' words -- is two commands and not a pipeline, and
  // `false || bash -c 'echo hi'` stays allowed. '&' rides along for `|&`, and a
  // subshell paren rides along for `echo hi | ( bash )` / `( echo hi ) | bash`.
  // 邊界串裡恰好一個 '|'：`||`（這個 tokenizer 會切成兩個 '|' 字）是兩條命令而不是管線。
  const isPipeRun = (run) => {
    let pipes = 0;
    for (const word of run) {
      if (word === '|') pipes += 1;
      else if (word !== '\n' && word !== '&' && word !== '(' && word !== ')') return false;
    }
    return pipes === 1;
  };
  // The word stream plus its sidecars, so one producer classifier can be used
  // both on this command line and on a command substitution re-tokenized out of
  // a carrier's here-string. Two copies of that classifier is the thing that
  // would drift, so there is one.
  // 字串流與它的側車資料一起傳，讓同一個產生器分類器既能用在這條命令列上，也能用在從
  // carrier 的 here-string 重新斷詞出來的命令替換上。抄第二份就是日後會走鐘的那一份。
  const wordContext = (text) => {
    // R5-13, and DEFENCE IN DEPTH rather than the load-bearing guard: this call
    // spends a budget of its own, and it really is reached (measured with a
    // per-site counter on an instrumented copy: `bash <<EOF` + newline +
    // `$(echo "` + 64 x `${` + `")` + newline + `EOF` reaches it). But every shape
    // that reaches it also exhausts one of the two funnel sites at the top of
    // this scan, so deleting this line alone is an EQUIVALENT MUTANT today -- no
    // test kills it, and test-hooks.js says so instead of pretending otherwise.
    // It stays because "the funnels always fire too" is a property of today's
    // call graph, not a guarantee, and R5-13 exists because this file trusted an
    // unreachability argument once already.
    // R5-13，這是縱深防禦而不是承重的守衛：這個呼叫自己會花一份預算，而且真的走得到（用加了
    // 逐站計數的複本實測）。但每一種走得到它的形狀，都同時把這個掃描開頭那兩個「漏斗」站點
    // 之一的預算也花完，所以單獨刪掉這一行在今天是等價突變，沒有測試殺得掉——記在這裡，而不
    // 是假裝有。留著它，是因為「漏斗一定也會觸發」是今天呼叫圖的性質、不是保證，而 R5-13 的
    // 由來正是本檔案曾經相信過一次「不可能發生」的論證。
    const contextWords = noteSubstitutionBudget(shellWords(text));
    const contextOperators = contextWords.operatorTokens || [];
    const contextClosing = new Map();
    const contextOpen = [];
    for (let k = 0; k < contextWords.length; k += 1) {
      if (!contextOperators[k]) continue;
      if (contextWords[k] === '(') contextOpen.push(k);
      else if (contextWords[k] === ')' && contextOpen.length > 0) contextClosing.set(contextOpen.pop(), k);
    }
    return {
      words: contextWords,
      operatorTokens: contextOperators,
      dynamicExpansions: contextWords.dynamicExpansions || [],
      heredocBodies: new Map((contextWords.heredocs || []).map((entry) => [entry.operatorIndex, entry.body])),
      closingParen: contextClosing,
    };
  };
  const outerContext = {
    words, operatorTokens, dynamicExpansions, heredocBodies, closingParen,
  };
  // Deliberately conservative unwrap for a PRODUCER: every wrapper spelling this
  // does not fully understand resolves to a word that is not echo/printf/curl/
  // wget, which makes the producer unreadable -- the fail-closed answer. It is
  // NOT resolveExecutable(): that one is driven by the rm operand scan and
  // consumes option operands per wrapper, and being wrong here must cost a
  // refusal, never an allowance.
  // 產生器端刻意保守的外殼拆解：任何它看不全的外殼寫法都會落在「不是
  // echo/printf/curl/wget」的字上，於是產生器變成讀不到——也就是 fail-closed 的答案。
  // `prefixed` records that something stood in FRONT of the command word that can
  // change what runs or where it fetches from: an environment assignment, or a
  // transparent wrapper and its options. Only the curl/wget EXEMPTION reads it --
  // the literal and heredoc producers stay readable through any prefix, because
  // their output is scanned either way. A shell CONTROL word (`if`, `then`, `do`,
  // `{`) is deliberately NOT a prefix: it is syntax, it cannot move a fetch, and
  // counting it would refuse `if true; then curl <documented URL> | bash; fi` for
  // nothing (measured both ways 2026-09-04).
  // `prefixed` 記的是「命令字前面站了能改變執行內容或抓取位置的東西」：環境變數指派，或透明
  // 包裝及其選項。只有 curl/wget 的豁免會讀它——literal 與 heredoc 產生器照舊容許前綴，因為
  // 它們吐出來的文字兩邊都會被掃。shell 控制字刻意不算前綴：那是語法，搬不動抓取。
  const producerExecutable = (context, start, end) => {
    let k = start;
    let prefixed = false;
    while (k < end) {
      if (context.operatorTokens[k]) return { index: -1, name: '', word: '', prefixed };
      const word = context.words[k];
      if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(word)) { k += 1; prefixed = true; continue; }
      const name = path.basename(word);
      if (controlWords.has(name)) { k += 1; continue; }
      if (transparent.has(name)) {
        prefixed = true;
        k += 1;
        while (k < end && !context.operatorTokens[k] && context.words[k].startsWith('-')) k += 1;
        continue;
      }
      return { index: k, name, word, prefixed };
    }
    return { index: -1, name: '', word: '', prefixed };
  };
  // An exempted producer word is only the command the shell will run while
  // nothing on this command line REDEFINES that name. `curl() { echo "rm -rf
  // /etc"; }; curl -sSL <documented URL> | bash` satisfies every condition the
  // exemption asks -- the word is bare, unprefixed, unpathed, the URL text is
  // byte-for-byte the documented one -- and runs a function instead, with no
  // request ever leaving the host (measured at ee2cb0e: ALLOW, touch payload ran).
  // A definition is not a PREFIX, so `resolved.prefixed` cannot see it; it is a
  // separate command on the same line.
  //
  // `anywhere on the line` is deliberate and fail-CLOSED. A definition written
  // AFTER the pipeline does not shadow it -- bash parses the whole line first but
  // defines the function only when it reaches that command -- so refusing
  // `curl <URL> | bash; curl() { :; }` is a false denial. It is the cheaper error:
  // ordering the scan against the producer's position puts position bookkeeping on
  // a security boundary, and `&`, newlines and line continuations each give that
  // bookkeeping a way to be wrong, in exchange for allowing a command nobody
  // writes. An `alias` is refused on the same terms: it does not expand in a
  // non-interactive shell and could not apply to its own line even in an
  // interactive one, but this gate cannot see which of those it was handed.
  // 被豁免的產生器命令字，只有在「這條命令列沒有重新定義那個名字」時，才真的是 shell 會執行
  // 的東西。定義不是「前綴」，所以 `resolved.prefixed` 看不到它——它是同一行上的另一條命令。
  // 「行上任何位置」是刻意的 fail-closed：寫在管線後面的定義其實遮蔽不了它，拒絕它是誤擋，
  // 但這是比較便宜的錯——照位置排序等於在安全邊界上多一套位置簿記，而 `&`、換行與續行符各自
  // 都能讓它出錯，換到的只是一條沒人會寫的命令的放行。alias 同理。
  const definesName = (contextWords, contextOperators, label) => {
    for (let k = 0; k < contextWords.length; k += 1) {
      if (contextOperators[k]) continue;
      const word = contextWords[k];
      // `name() { … }`, `name () { … }` and `name(){ … }` all reach this
      // tokenizer as the name followed by the operator words '(' and ')'.
      // 這三種函式定義寫法在這個 tokenizer 都是「名字」後面接運算子字 '(' 與 ')'。
      if (
        word === label
        && contextOperators[k + 1] && contextWords[k + 1] === '('
        && contextOperators[k + 2] && contextWords[k + 2] === ')'
      ) return true;
      // `function name { … }` / `function name () { … }`.
      if (word === 'function' && !contextOperators[k + 1] && contextWords[k + 1] === label) return true;
      // `alias name=…`: this tokenizer keeps `name=value` as one word, so the
      // assignment is found on the word itself rather than on a following '='.
      // `alias name=…`：這個 tokenizer 把 `name=value` 留成一個字。
      if (word === 'alias') {
        for (let j = k + 1; j < contextWords.length && !contextOperators[j]; j += 1) {
          if (contextWords[j].startsWith(`${label}=`)) return true;
        }
      }
    }
    return false;
  };
  // definesName() above walks TOKENS, so it only finds a definition the tokenizer
  // emits as separate words. Put the identical definition inside ONE word and it
  // is invisible: `eval 'curl(){ … }'`, `source <(echo 'curl(){ … }')`, `. <(…)`,
  // `source /dev/stdin <<< '…'`, `source /dev/stdin << HEREDOC`, `eval "$(…)"`,
  // ``eval `…` `` -- and every one of them really defines `curl` before the
  // pipeline runs (measured 2026-09-05 with the stand-in name `zzcurl`, which is
  // not a binary, so a marker file appears only when the definition took effect:
  // all of them created their marker under bash 5.3.15 and /bin/bash 3.2.57, the
  // here-string twin also under zsh, while the no-definition negative control
  // created nothing and the plain same-line positive control did).
  //
  // So the same question is asked a SECOND time of the RAW COMMAND TEXT, which no
  // word-splitting can hide anything from. Two shapes void the exemption:
  //   (a) the producer's OWN name being defined -- `curl()`, `function curl`,
  //       `alias curl=` -- or `hash -p`, which points a name at a chosen file;
  //   (b) any of `eval`, `source`, the dot command, `trap`, `exec` appearing at
  //       all, because each of them can put a different command behind that name
  //       before it runs, and the definition text they carry is unreadable here.
  // (a) is per-name on purpose: `wget(){ … }; curl <URL> | bash` must stay
  // allowed, or the rule collapses into "any definition on the line refuses the
  // documented route" (pinned by four controls in test-hooks.js `allowed`).
  // (b) is NOT command-position aware, and cannot be: this is text, not tokens --
  // the whole reason it exists. `echo eval; curl <URL> | bash` is therefore
  // refused although `eval` is an operand there, and so is the everyday
  // `source ~/.profile; curl -fsSL <URL> | bash`. Both are false denials of
  // benign commands and both are ACCEPTED, pinned as refusals in
  // exceptionListControls and written down in README condition 5: the cost is one
  // refusal a user can work around by splitting the line, and the alternative is
  // re-deciding command position on text the tokenizer has already been shown to
  // read differently from the shell.
  // definesName() 掃的是「字」，所以只找得到 tokenizer 會斷成獨立字的定義。把同一個定義塞
  // 進一個字裡面它就看不見了，而那些寫法每一種都真的會在管線跑之前把 curl 定義掉（2026-09-05
  // 用不存在的替身名字 zzcurl 實測，marker 只有在定義生效時才出現：全部都產生了 marker）。
  // 因此同一個問題對「原始命令文字」再問一次——斷詞藏不住東西的地方。兩種形狀作廢豁免：
  // (a) 產生器「自己的名字」被定義（`curl()`／`function curl`／`alias curl=`），或出現
  //     `hash -p`（把一個名字指向指定檔案）；(b) 出現 `eval`、`source`、點命令、`trap`、
  //     `exec` 任何一個，因為它們都能在名字執行前把別的東西塞到那個名字後面，而它們帶的定義
  //     文字在這裡讀不到。(a) 刻意分名字：`wget(){ … }; curl <URL> | bash` 必須照常放行。
  // (b) 刻意「不」判斷命令位置，也判斷不了：這裡是文字不是字串流，這正是它存在的理由。所以
  // `echo eval; curl <URL> | bash` 會被擋（那裡的 eval 是操作元），`source ~/.profile;
  // curl -fsSL <URL> | bash` 也會被擋。兩者都是良性命令的誤擋，而且都「已接受」：代價是一次
  // 拒絕（把那一行拆開就能繞過），換到的是不必在「已被證明和 shell 讀法不同」的文字上重新判
  // 斷命令位置。
  const rawDefinesName = (raw, label) => {
    const name = String(label).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    return new RegExp(`\\b${name}\\s*\\(\\s*\\)`).test(raw)
      || new RegExp(`\\bfunction\\s+${name}\\b`).test(raw)
      || new RegExp(`\\balias\\s+${name}=`).test(raw)
      || /\bhash\s+-p\b/.test(raw);
  };
  // The dot command needs its own shape: a bare `.` is in every relative path on
  // every command line, so it counts only where a command word can stand (start
  // of the text, or after `;`, `&`, `|`, `(`, `{` or whitespace -- and `\s`
  // covers the newline) AND is followed by whitespace. `./install.sh` and
  // `file.sh` therefore do not fire it (both pinned as allowances).
  // 點命令要自己的形狀：裸 `.` 在每一條命令列的每一個相對路徑裡都有，所以只在「命令字站得住
  // 的位置」而且「後面接空白」時才算。`./install.sh` 與 `file.sh` 因此不會觸發它。
  const RAW_PRODUCER_INDIRECTION = /\beval\b|\bsource\b|\btrap\b|\bexec\b|(?:^|[;&|(\s{])\.\s/;
  // Both scopes, because a producer can be classified out of a command
  // substitution re-tokenized from a carrier's here-string: a definition in the
  // OUTER line shadows it just as well as one in the inner text.
  // 兩個範圍都掃：產生器可能是從 carrier here-string 裡重新斷詞出來的命令替換，而外層那一行
  // 上的定義一樣遮蔽得到它。
  const rawCommandText = String(command || '');
  const producerNameShadowed = (context, label) => (
    definesName(context.words, context.operatorTokens, label)
    || definesName(words, operatorTokens, label)
    || rawDefinesName(rawCommandText, label)
    || RAW_PRODUCER_INDIRECTION.test(rawCommandText)
  );
  // Three readable producers, and one refusal that is the default.
  const classifyProducer = (context, start, end) => {
    if (start >= end) return { kind: 'opaque', label: 'unknown' };
    const resolved = producerExecutable(context, start, end);
    if (resolved.index === -1) return { kind: 'opaque', label: 'unknown' };
    const label = resolved.name;
    if (hasUnresolvedTargetExpansion(context.dynamicExpansions[resolved.index])) {
      return { kind: 'opaque', label };
    }
    const argv = [];
    const options = [];
    const operands = [];
    const heredocs = [];
    let dynamic = false;
    let substitutionOperand = false;
    for (let k = resolved.index + 1; k < end; k += 1) {
      // `<<` and `<<-` are NOT operator words in this tokenizer -- the heredoc
      // branch pushes them as ordinary words (measured: operatorTokens is false
      // at their index while it is true for `<<<`, `<`, `>`, `&`) -- so the
      // authoritative signal is the `heredocs` sidecar, keyed by the operator's
      // index. That is the same signal the carrier option route uses (:1930),
      // and reading it off operatorTokens instead made `cat <<EOF | bash` see
      // two extra operands and refuse its own benign form (measured).
      // `<<` 與 `<<-` 在這個 tokenizer 裡不是運算子字（heredoc 分支把它們當普通字推進去），
      // 所以權威訊號是以運算子索引為鍵的 `heredocs` 側車——與 carrier option route 用的是同
      // 一個訊號。改用 operatorTokens 判斷會讓 `cat <<EOF | bash` 多看到兩個操作元而擋掉
      // 自己的良性寫法（實測）。
      if (context.heredocBodies.has(k)) {
        heredocs.push(context.heredocBodies.get(k));
        k += 1;
        continue;
      }
      if (context.operatorTokens[k]) {
        const word = context.words[k];
        if (word === '<<<') { k += 1; continue; }
        if (word === '<' || word === '>') {
          let j = k;
          while (context.operatorTokens[j + 1] && context.words[j + 1] === '<') j += 1;
          if (context.operatorTokens[j + 1] && context.words[j + 1] === '(') {
            substitutionOperand = true;
            k = context.closingParen.has(j + 1) ? context.closingParen.get(j + 1) : end;
            continue;
          }
          if (context.operatorTokens[j + 1] && context.words[j + 1] === '&') { k = j + 2; continue; }
          k = j + 1;
          continue;
        }
        continue;
      }
      const word = context.words[k];
      if (
        /^[0-9]+$/.test(word) && context.operatorTokens[k + 1]
        && (context.words[k + 1] === '<' || context.words[k + 1] === '>')
      ) continue;
      if (hasUnresolvedTargetExpansion(context.dynamicExpansions[k])) dynamic = true;
      if (word === '--') continue;
      argv.push(word);
      if (word.startsWith('-') && word !== '-') options.push(word);
      else operands.push(word);
    }
    // A producer that reads its own operand from a process substitution
    // (`cat <(curl …) | bash`) hands the carrier bytes nobody read.
    if (substitutionOperand) return { kind: 'opaque', label };
    // A heredoc body IS readable text and the carrierPresent route above already
    // scans it, which is why `cat <<EOF | bash` is refused for what the body says
    // and the benign twin stays allowed. It stays readable only while the heredoc
    // is the whole of what the producer emits: `cat script.sh <<EOF | bash`
    // concatenates the FILE first, one token away from the `cat script.sh | bash`
    // this rule refuses.
    // heredoc 內文本身是讀得到的文字，上面的 carrierPresent 路徑早就在掃它。但只有在
    // 「heredoc 就是產生器吐出的全部」時才算讀得到：`cat script.sh <<EOF | bash` 會先把檔案
    // 接上去，而它跟本規則要拒的 `cat script.sh | bash` 只差一個 token。
    if (heredocs.length > 0) {
      if (operands.length > 0 || dynamic) return { kind: 'opaque', label };
      return { kind: 'heredoc', label, bodies: heredocs };
    }
    if ((label === 'echo' || label === 'printf') && !dynamic) {
      // Two scans, union of the targets. The JOIN catches `echo rm -rf /etc`;
      // the per-operand scan catches `printf %s "rm -rf /etc"` and
      // `echo -e "rm -rf /etc"`, where the join puts a format string or an
      // option in command position and the deletion hides behind it. Same two
      // shapes the unresolved-executable arm already needs (:1904-1911).
      // 兩種掃法、目標取聯集。join 抓 `echo rm -rf /etc`；逐操作元掃抓
      // `printf %s "rm -rf /etc"`（join 會把格式字串推到命令位置，把刪除藏在後面）。
      // ...and a THIRD scan, for the spelling neither of the two above can see: a
      // deletion written as separate whitespace-free WORDS. `echo -e rm -rf /etc`
      // has no operand containing a space, and the plain join starts `-e rm …`
      // with the option in command position -- so `rm` is never in command
      // position in any text and the deletion was ALLOWED (measured at 5bf41fe
      // through the real stdin entry point; a touch payload really ran under
      // /bin/bash 3.2.57, bash 5.x, sh, zsh, dash and ksh). Dropping the LEADING
      // option words puts the emitted words back in the order the shell will see
      // them. printf drops one more: its first non-option word is the FORMAT, not
      // part of the output.
      // The benign twins (`echo -e hi`, `printf '%s ' hello world`) stay allowed
      // because this adds TEXT to scan, not a refusal: the ordinary rules judge
      // what the emitter emits, exactly as they do for the join.
      // ……再加第三種掃法，補上前兩種都看不到的那一種寫法：刪除被寫成分開的、各自不含空白的
      // 「字」。`echo -e rm -rf /etc` 沒有任何含空白的操作元，而 join 出來的字串以 `-e` 開頭，
      // `rm` 從來沒有出現在命令位置上——於是這條刪除被放行（實測）。拿掉開頭的選項字，就把
      // 產生器吐出的字還原成 shell 會看到的順序；printf 還要多丟一個：它的第一個非選項字是
      // 格式字串，不是輸出內容。
      let firstOperandIndex = 0;
      while (
        firstOperandIndex < argv.length
        && argv[firstOperandIndex].startsWith('-')
        && argv[firstOperandIndex] !== '-'
      ) firstOperandIndex += 1;
      const emitted = argv.slice(firstOperandIndex);
      const texts = [
        argv.join(' '),
        emitted.join(' '),
        ...(label === 'printf' ? [emitted.slice(1).join(' ')] : []),
        ...operands.filter((word) => /\s/.test(word)),
      ];
      // ...and a FOURTH scan, over the same texts with their backslash escapes
      // DECODED (decodeShellEscapes, above). Every text above is the word as it
      // stands on THIS command line; the emitter writes the decoded form down the
      // pipe. `echo -e 'rm\x20-rf\x20/etc'` is one word here and `rm -rf /etc`
      // there, so `rm` was never in command position in any text and the deletion
      // was ALLOWED (measured at ee2cb0e through the real stdin entry point; a
      // touch payload really ran under bash 5.3.15, /bin/bash 3.2.57, /bin/sh,
      // zsh and /bin/csh). Added to the set, never substituted for it: a decode
      // that guesses wrong must not be able to hide a deletion the raw text shows.
      // ……再加第四種掃法：同一批文字，把反斜線逸出序列解碼過一次。上面每一段都是「這條命令列
      // 上」的字，而產生器寫進 pipe 的是解碼後的形式。是「加入」集合而不是取代：解碼猜錯時，
      // 不可以把原文看得見的刪除藏起來。
      for (const text of texts.slice()) {
        const decoded = decodeShellEscapes(text);
        if (decoded !== text) texts.push(decoded);
      }
      return { kind: 'literal', label, texts };
    }
    // The option allowlist below exists because `--resolve`, `--proxy`,
    // `--unix-socket`, `-K` and `-o` move the fetch while the URL text stays the
    // documented one. An environment assignment (`CURL_HOME`, `WGETRC`,
    // `https_proxy`, `LD_PRELOAD`, `PATH`) and a transparent wrapper move it the
    // same way and never reach `options` -- the scan that fills it starts AFTER
    // the command word -- so the exemption asks for a producer with nothing in
    // front of it. `resolved.word === label` is the other half: the label comes
    // from path.basename(), so without it `/tmp/evil/curl` and `./curl` inherited
    // the exemption. Measured 2026-09-04: `curl -K /tmp/evil/.curlrc <URL> | bash`
    // was refused while `CURL_HOME=/tmp/evil curl <URL> | bash` -- the same config
    // file, through the environment -- was allowed.
    // 選項白名單存在的理由是那幾個選項會「保留網址文字但把抓取搬走」。環境變數指派與透明包裝
    // 用同樣的方式搬動抓取，而且永遠不會進到 `options`（填它的掃描從命令字之後才開始），所以
    // 豁免要求產生器前面什麼都沒有。`resolved.word === label` 是另一半：label 來自
    // path.basename()，少了它，任何叫做 `curl` 的執行檔都會繼承豁免。
    // isCanonicalInstallLine() is the whole rule (see CANONICAL_INSTALL_LINES),
    // and `depth === 0` is what makes "the whole command line" mean the line the
    // user actually typed. At depth > 0 the text being judged is something this
    // gate RECONSTRUCTED -- a heredoc body, an emitter's output, the argument of
    // `bash -c`, an `env -S` string -- and a route that is only canonical after
    // that reconstruction is a route somebody else assembled. Measured
    // 2026-09-05: `BASH_ENV=/tmp/evil.sh bash -c '<canonical route>'` really runs
    // the planted file's definition and was ALLOWED while its non-exempt twin was
    // refused, i.e. the exemption was what let it through; with this clause the
    // inner text is judged like any other unreadable piped script. The cost is
    // that `bash -c '<canonical route>'` and `echo '<canonical route>' | bash`
    // are refused too -- neither is a documented route, and the documented one is
    // to type the route itself.
    // isCanonicalInstallLine() 就是全部的規則（見 CANONICAL_INSTALL_LINES），而 `depth === 0`
    // 是讓「整條命令列」真的等於「使用者打的那一行」的那一半。depth > 0 時被判的文字是這道
    // 閘門自己「重建」出來的——heredoc 內文、產生器的輸出、`bash -c` 的參數、`env -S` 字串
    // ——而一條要靠重建才變成記載路徑的路徑，是別人組出來的。2026-09-05 實測：
    // `BASH_ENV=/tmp/evil.sh bash -c '<記載路徑>'` 真的會執行被植入檔案裡的定義，而它放行、
    // 非豁免的雙胞胎被拒——也就是放行的原因就是豁免；加上這一條之後，內層文字就跟其他讀不到
    // 的 piped script 一樣被判。代價是 `bash -c '<記載路徑>'` 與 `echo '<記載路徑>' | bash`
    // 也會被拒——兩者都不是記載中的路徑，而記載中的做法就是直接打那條路徑本身。
    // Everything below it is now UNREACHABLE BY CONSTRUCTION -- a line that is
    // byte-equal to a canonical route cannot carry a prefix, a second operand, a
    // non-allowlisted option, a `..`, or a redefinition of the producer's name,
    // because every one of those is a character the canonical line does not have.
    // They are kept as defence in depth, and their controls are kept in
    // test-hooks.js: they are what still refuses if this line is ever widened
    // back into a set of conditions, and deleting a guard because today's rule
    // makes it redundant is how the redundancy stops being true.
    // isCanonicalInstallLine() 就是全部的規則（見 CANONICAL_INSTALL_LINES）。它底下每一個
    // 條件現在都「在構造上」到不了——逐位元組等於記載路徑的一行，不可能同時帶著前綴、第二個
    // 操作元、白名單外的選項、`..`，或把產生器的名字重新定義掉，因為那每一樣都是這一行沒有
    // 的字元。留著它們是縱深防禦，測試也照留：萬一哪天這條規則又被放寬回「一組條件」，擋下來
    // 的就是它們；而「今天用不到就刪掉」正是讓那個「用不到」不再成立的做法。
    if (
      depth === 0 && isCanonicalInstallLine(rawCommandText)
      && (label === 'curl' || label === 'wget') && !dynamic && operands.length === 1
      && !resolved.prefixed && resolved.word === label
      && !producerNameShadowed(context, label)
      && !/\.\.|%2e|%2f|%5c/i.test(operands[0])
      && PIPED_SCRIPT_EXCEPTIONS.some((prefix) => operands[0].startsWith(prefix))
      && options.every((option) => (
        label === 'curl' ? EXEMPT_CURL_OPTIONS : EXEMPT_WGET_OPTIONS
      ).test(option))
    ) return { kind: 'exempt', label };
    return { kind: 'opaque', label };
  };
  const scriptFromProducer = (context, start, end, shape, nest, opaque) => {
    const verdict = classifyProducer(context, start, end);
    if (verdict.kind === 'exempt') return;
    if (verdict.kind === 'literal') {
      for (const text of verdict.texts) {
        if (!text) continue;
        if (depth >= 8) targets.push('/');
        else targets.push(...nestedScan(text, depth + 1, true, expansionEnv));
      }
      return;
    }
    if (verdict.kind === 'heredoc') {
      for (const body of verdict.bodies) {
        unscannableSubstitutions(body, shape, nest + 1);
      }
      return;
    }
    targets.push(opaque ? opaque() : UNSCANNABLE_SCRIPT + shape(verdict.label));
  };
  // The carrier's script text is visible, but a command SUBSTITUTION inside it is
  // not: `bash <<< "$(curl -s URL)"` runs whatever that URL serves, and it was
  // measured ALLOW while the plain `curl … | bash` next to it was refused --
  // six characters cheaper than the workaround the new refusal recommends.
  // carrier 的腳本文字看得見，但裡面的命令替換看不見：`bash <<< "$(curl -s URL)"` 執行的是
  // 那個網址吐出來的東西，實測放行，而它旁邊的 `curl … | bash` 是拒絕的。
  function unscannableSubstitutions(text, shape, nest) {
    // R5-13, and DEFENCE IN DEPTH rather than the load-bearing guard: this call
    // spends a budget of its own, and it really is reached (measured with a
    // per-site counter on an instrumented copy: `bash <<EOF` + newline +
    // `$(echo "` + 64 x `${` + `")` + newline + `EOF` reaches it). But every shape
    // that reaches it also exhausts one of the two funnel sites at the top of
    // this scan, so deleting this line alone is an EQUIVALENT MUTANT today -- no
    // test kills it, and test-hooks.js says so instead of pretending otherwise.
    // It stays because "the funnels always fire too" is a property of today's
    // call graph, not a guarantee, and R5-13 exists because this file trusted an
    // unreachability argument once already.
    // R5-13，這是縱深防禦而不是承重的守衛：這個呼叫自己會花一份預算，而且真的走得到（用加了
    // 逐站計數的複本實測）。但每一種走得到它的形狀，都同時把這個掃描開頭那兩個「漏斗」站點
    // 之一的預算也花完，所以單獨刪掉這一行在今天是等價突變，沒有測試殺得掉——記在這裡，而不
    // 是假裝有。留著它，是因為「漏斗一定也會觸發」是今天呼叫圖的性質、不是保證，而 R5-13 的
    // 由來正是本檔案曾經相信過一次「不可能發生」的論證。
    const inners = noteSubstitutionBudget(commandSubstitutions(String(text || '')));
    if (inners.length === 0) return;
    if (nest >= 4) {
      targets.push(UNSCANNABLE_SCRIPT + shape('nested substitution'));
      return;
    }
    for (const inner of inners) {
      const context = wordContext(inner);
      scriptFromProducer(context, 0, context.words.length, shape, nest);
    }
  }
  // Every INPUT process substitution on the command line, keyed by the fd it is
  // attached to: `3< <(…)` -> '3', a bare `< <(…)` -> '0'. Built once over the
  // whole word stream, not per segment, because `exec 3< <(curl …); bash /dev/fd/3`
  // opens the fd in one command and names it in the next. Output substitutions
  // (`> >(…)`) are deliberately absent: they are not a script source
  // (KNOWN-RESIDUALS.md R4-b).
  // 整條命令列上每一個「輸入方向」的 process substitution，以它掛的 fd 為鍵。只建一次、不
  // 分段，因為 `exec 3< <(…); bash /dev/fd/3` 是在前一條命令開的 fd。
  const procsubByFd = new Map();
  for (let k = 0; k < words.length; k += 1) {
    if (!operatorTokens[k] || words[k] !== '<') continue;
    // The second '<' of a `< <(` run belongs to the substitution, not to a
    // redirection of its own.
    if (k > 0 && operatorTokens[k - 1] && words[k - 1] === '<') continue;
    let j = k;
    while (operatorTokens[j + 1] && words[j + 1] === '<') j += 1;
    if (!(operatorTokens[j + 1] && words[j + 1] === '(')) continue;
    const close = closingParen.has(j + 1) ? closingParen.get(j + 1) : words.length;
    const fd = (k > 0 && !operatorTokens[k - 1] && /^[0-9]+$/.test(words[k - 1]))
      ? words[k - 1]
      : '0';
    if (!procsubByFd.has(fd)) procsubByFd.set(fd, { start: j + 2, end: close });
  }
  {
    const segments = [];
    let cursor = 0;
    while (cursor < words.length) {
      const run = [];
      while (cursor < words.length && isCommandBoundary(cursor)) {
        run.push(words[cursor]);
        cursor += 1;
      }
      const start = cursor;
      while (cursor < words.length && !isCommandBoundary(cursor)) cursor += 1;
      segments.push({ start, end: cursor, run });
    }
    for (let n = 0; n < segments.length; n += 1) {
      const segment = segments[n];
      if (segment.start >= segment.end) continue;
      const {
        executable, executableIndex, stdinCompletesOperands, xargsReplaceString,
      } = resolveExecutable(segment.start);
      if (!executable || executableIndex < 0) continue;
      // A command word that only exists after expansion may BE a carrier, and it
      // gets the same answer the rest of this file gives that shape: assume the
      // worst. Its here-string twin already fails closed (:1900-1903), so
      // `CMD=bash; $CMD <<< "rm -rf /etc"` was refused while
      // `CMD=bash; curl … | $CMD` was allowed -- one unknowable, two answers.
      // ... but "only exists after expansion" is NOT the same as "unknowable":
      // this file already resolves $HOME, $PWD and $TMPDIR for every rm operand
      // (targetFromWord -> resolveKnownExpansions), and reading a pipe target
      // with a different rule than an rm operand is exactly how
      // `ps aux | "$HOME/bin/filter.sh"` came to be refused while
      // `rm -rf "$HOME/build"` is allowed (measured 2026-09-03). Resolve first,
      // with the SAME function, and only what is still unresolved after that is
      // treated as a possible carrier. resolveKnownExpansions fails closed on
      // everything it does not understand (`${PAGER:-less}`, `$(…)`, an empty or
      // relative value, a value carrying whitespace), so this cannot widen past
      // the three names.
      // 展開後才知道的命令字可能就是 carrier，答案與本檔案其他地方一致：假設最壞。它的
      // here-string 雙胞胎早就 fail closed，於是同一種不可知先前有兩種答案。但「展開後才
      // 知道」不等於「不可知」：這個檔案對每一個 rm 操作元早就會解 $HOME／$PWD／$TMPDIR，
      // 管線接收端改用另一套規則讀，正是 `ps aux | "$HOME/bin/filter.sh"` 被擋掉而
      // `rm -rf "$HOME/build"` 放行的原因。先用同一個函式解，解不開的才當成可能的 carrier。
      const carrierWord = words[executableIndex];
      let dynamicCarrier = hasUnresolvedTargetExpansion(dynamicExpansions[executableIndex]);
      let carrier = path.basename(executable);
      if (dynamicCarrier) {
        const resolvedCarrier = resolveKnownExpansions(carrierWord, expansionEnv);
        if (resolvedCarrier !== null) {
          dynamicCarrier = false;
          carrier = path.basename(resolvedCarrier);
        }
      }
      // `eval` is deliberately NOT a carrier here: it never reads a script from
      // stdin, so `echo x | eval` is a no-op and refusing it would be a pure
      // false denial. It stays in the `carriers` set above, which is about
      // heredoc bodies, not about stdin.
      // `eval` 刻意不算 carrier：它從不從 stdin 讀腳本，`echo x | eval` 是空操作，擋它是
      // 純粹的誤擋。
      if (carrier === 'eval') continue;
      if (!r4Carriers.has(carrier) && !dynamicCarrier) continue;
      // `-n` (bash/sh/dash/zsh/ksh noexec, fish --no-execute) makes the carrier
      // PARSE its input and stop. `… | xargs -n1 bash -n`, `cat f | env bash -n`,
      // `cat f | timeout 5 bash -n` and `| sh -n` are the syntax check this
      // machine's own suites run on every shell file; nothing they read is
      // executed, so refusing them was a pure false denial (measured 2026-09-03:
      // all six spellings DENY, and the payload never ran under either bash).
      // The scan stops at `--` and at the option that carries a script, because
      // after either of those an `-n` is an argument and not an option.
      // `-n` 讓 carrier 只解析不執行：`… | xargs -n1 bash -n`、`cat f | env bash -n`、
      // `| sh -n` 是本機各套測試都在跑的語法檢查，讀進去的東西一個都不會被執行，擋它是純粹
      // 的誤擋。掃描在 `--` 與「帶腳本的那個選項」處停下：在那之後的 `-n` 是引數不是選項。
      let noExec = false;
      for (let k = executableIndex + 1; k < words.length && !isCommandBoundary(k); k += 1) {
        if (operatorTokens[k] || heredocBodies.has(k)) continue;
        const word = words[k];
        if (word === '--') break;
        if (word === '--noexec' || word === '--no-execute' || word === '--no-exec') {
          noExec = true;
          break;
        }
        if (!word.startsWith('-') || word === '-') continue;
        if (word.startsWith('--')) continue;
        if (/^-[^-]*c/.test(word)) break;
        if (/^-[A-Za-z]*n/.test(word)) {
          noExec = true;
          break;
        }
      }
      if (noExec) continue;
      let visible = false;
      let scriptIsFile = false;
      let stdinMarker = false;
      let commandOption = null;
      const procsubRanges = [];
      const scriptBodies = [];
      const fileOperands = [];
      for (let k = executableIndex + 1; k < words.length && !isCommandBoundary(k); k += 1) {
        const word = words[k];
        // A heredoc on the carrier's OWN argv (`bash <<EOF`): its body is the
        // script, an existing route already scans it, and it overrides stdin.
        // Keyed off the `heredocs` sidecar, not operatorTokens -- see the note in
        // classifyProducer above.
        if (heredocBodies.has(k)) {
          visible = true;
          scriptBodies.push(heredocBodies.get(k));
          k += 1;
          continue;
        }
        if (operatorTokens[k]) {
          if (word === '<<<') {
            visible = true;
            if (k + 1 < words.length) scriptBodies.push(words[k + 1]);
            k += 1;
            continue;
          }
          if (word === '<' || word === '>') {
            // `bash < <(…)` tokenizes as two separate '<' operator words -- the
            // second belongs to the substitution -- so a run of them is one
            // redirection here.
            let j = k;
            while (operatorTokens[j + 1] && words[j + 1] === '<') j += 1;
            if (operatorTokens[j + 1] && words[j + 1] === '(') {
              const close = closingParen.has(j + 1) ? closingParen.get(j + 1) : words.length;
              if (word === '<') procsubRanges.push({ start: j + 2, end: close });
              k = close;
              continue;
            }
            // `<&`/`0<&0` is fd DUPLICATION, not a file redirect: it does not
            // take stdin away from the pipe. Measured, marker files created
            // under bash 5.3.15 and /bin/bash 3.2.57: `echo "…" | bash 0<&0`,
            // `| bash <&0`, `| /bin/bash 0<&0` and `| bash 0<&0 -s` all execute
            // the piped script, so reading `<&` as "a redirect overrides the
            // pipe" would have shipped this rule with a four-character bypass.
            // `<&`／`0<&0` 是 fd 複製而不是檔案重導向：它沒有把 stdin 從 pipe 那裡拿走。
            // 實測（bash 5.3.15 與 /bin/bash 3.2.57 都產生標記檔）四種寫法都會執行從
            // pipe 進來的腳本，所以把 `<&` 讀成「重導向覆蓋 pipe」等於帶著一個四字元的
            // 繞法出貨。
            if (operatorTokens[j + 1] && words[j + 1] === '&') { k = j + 2; continue; }
            // `<>` opens the fd for reading AND writing, and this tokenizer emits
            // it as two operator words. `bash <> /dev/stdin` is still reading the
            // pipe, so the target below has to be inspected for this spelling too.
            // `<>` 是讀寫開啟，這個 tokenizer 會切成兩個運算子字；`bash <> /dev/stdin`
            // 讀的仍然是 pipe，所以底下那個判斷也要看得到這種寫法。
            let redirect = j;
            if (word === '<' && operatorTokens[redirect + 1] && words[redirect + 1] === '>') {
              redirect += 1;
            }
            // A plain `< file` really does override the pipe, and a FILE is out
            // of this rule's scope (KNOWN-RESIDUALS.md R4-b) -- but ONLY when the
            // target really is a file. `/dev/stdin`, `/dev/fd/0` and `-` name the
            // pipe itself, and reading them as "a file overrides the pipe" left
            // `curl … | bash < /dev/stdin`, `< /dev/fd/0`, `0< /dev/stdin`,
            // `sudo bash < /dev/stdin` and `zsh < /dev/stdin` ALLOWED while the
            // plain `curl … | bash` next to them was refused (measured 2026-09-03,
            // marker files under bash 5.3.15 and /bin/bash 3.2.57). It is the same
            // list stdinScriptPaths already uses for an OPERAND; the redirect
            // simply was not consulting it.
            // 純粹的 `< file` 確實會蓋掉 pipe，而「檔案」不在這條規則範圍內——但只有在目標
            // 真的是檔案時才成立。`/dev/stdin`、`/dev/fd/0`、`-` 指的就是那個 pipe 自己。
            if (word === '<') {
              const redirectTarget = (redirect + 1 < words.length && !operatorTokens[redirect + 1])
                ? words[redirect + 1]
                : null;
              if (redirectTarget === null || !stdinScriptPaths.has(redirectTarget)) {
                scriptIsFile = true;
              }
            }
            k = redirect + 1;
            continue;
          }
          continue;
        }
        // An fd number written before a redirection operator belongs to it, not
        // to the argv (`bash 0<&0`, `bash 2>/dev/null`).
        if (
          /^[0-9]+$/.test(word) && operatorTokens[k + 1]
          && (words[k + 1] === '<' || words[k + 1] === '>')
        ) continue;
        if (word === '--') continue;
        // A lone `\\` is a line continuation with nothing after it. bash 3.2
        // EXECUTES `cat f | bash \\` (measured: marker file under /bin/bash 3.2.57;
        // bash 5.3.15 errors instead), and 3.2 is the interpreter five launchd
        // plists on this machine actually run, so reading the backslash as a
        // script FILE operand shipped the shape allowed on the interpreter that
        // matters. It names no file either way.
        // 單獨一個 `\\` 是「後面沒東西」的續行。實測 bash 3.2 會執行 `cat f | bash \\`
        // （5.3 則報錯），而 3.2 正是本機五個 launchd plist 真正跑的直譯器。
        if (word === '\\') continue;
        if ((word.startsWith('-') && word !== '-') || (word.startsWith('+') && word.length > 1)) {
          // The option that carries the script, spelled with the SAME test the
          // option route uses (/^-[^-]*c/), so a bundle counts exactly as a bare
          // `-c` does: `cat f | bash -lc 'wc -l'`, `-ec` and `sh -exc` are the
          // login-shell idiom this machine's launchd and ssh wrappers use, and
          // spelling the exclusion as the exact word `-c` would newly refuse all
          // three.
          // 帶腳本的那個選項，用的是與 option route 相同的判斷（/^-[^-]*c/），所以合寫的
          // `-lc`、`-ec`、`-exc` 與單獨的 `-c` 一視同仁。
          if (
            word === '--command' || /^-[^-]*c/.test(word)
            || (carrier === 'fish' && (
              word === '-C' || word.startsWith('--init-command') || word.startsWith('--command=')
            ))
          ) {
            commandOption = (k + 1 < words.length && !operatorTokens[k + 1])
              ? words[k + 1]
              : null;
            // A `-c` reached THROUGH xargs is not the same thing as a `-c` typed
            // on this line: xargs supplies its script from stdin, which is
            // precisely what this rule exists to refuse (R4-b). Two shapes, both
            // measured with touch markers under BSD xargs on bash 5.3.15 and
            // 3.2.57:
            //   (a) no argument at all -- `… | xargs -0 bash -c` -- where xargs
            //       APPENDS the stdin line and it becomes the script;
            //   (b) an argument that IS the replace string -- `… | xargs -I{} sh
            //       -c '{}'` -- where the `{}` on the command line is a
            //       placeholder and the stdin line is what runs.
            // Seven spellings execute the payload as written (`-0 bash -c`,
            // `-0 sh -c`, `-I{} sh -c '{}'`, `-I{} bash -c '{}'`, `-0 -- bash -c`,
            // `-P4 -0 bash -c`, `-0 zsh -c`). Three more -- bare `xargs bash -c`,
            // `-L1 bash -c`, `-n1 sh -c` -- split stdin on whitespace, so a
            // MULTI-word payload runs only its first word as the script and the
            // marker never appeared; but with a single-word payload all three
            // really do run it (measured, same probe), so the script still comes
            // from stdin in every one of them. They are refused by the same rule
            // rather than carved out: "the script comes from stdin" is one rule,
            // and "…unless xargs' word splitting would have mangled this
            // particular payload" would be a second one that has to model that
            // splitting to stay true.
            // What stays VISIBLE, and is the row that keeps this from collapsing
            // into "xargs plus a shell is refused": a `-c` argument that is on the
            // command line and that no replace string can rewrite --
            // `… | xargs -0 bash -c 'echo hi'` -- where stdin becomes $0/$1 and
            // not the script (measured NOT to execute the payload).
            // 走過 xargs 的 `-c` 與這一行上打出來的 `-c` 不是同一回事：腳本由 xargs 從 stdin
            // 補上，而那正是這條規則要擋的。兩種形狀（都有 marker 實測）：(a) 後面根本沒有引
            // 數，stdin 那一行被接上去就成了腳本；(b) 引數就是替換字串，命令列上的 `{}` 只是
            // 佔位符。另外三種（裸的、`-L1`、`-n1`）依空白切開，多字 payload 不會照原樣執行，
            // 但單字 payload 三種都會執行——腳本一樣來自 stdin，所以用同一條規則拒絕。
            // 仍然算「看得見」的是：`-c` 的引數寫在命令列上、又沒有替換字串會改寫它。
            const scriptComesFromStdin = stdinCompletesOperands && (
              commandOption === null
              || (xargsReplaceString !== null && commandOption.includes(xargsReplaceString))
            );
            visible = !scriptComesFromStdin;
            if (scriptComesFromStdin) commandOption = null;
            break;
          }
          if (/^-[A-Za-z]*s/.test(word)) stdinMarker = true;
          // `-O shopt`, `+O shopt`, `-o option`, `+o option`, `--rcfile FILE` and
          // `--init-file FILE` take their argument as a SEPARATE word (bash --help,
          // "invocation only"). Without consuming it that word was read as the
          // script FILE, and `curl … | bash -O extglob` was ALLOWED -- measured
          // 2026-09-03 with a touch payload, marker files under both bash 5.3.15
          // and /bin/bash 3.2.57 for all seven spellings. `--norc`, `--posix`,
          // `--login`, `--noediting` and every other long option take none, and the
          // `--rcfile=FILE` spelling carries its own, so neither consumes a word.
          // Consuming one word too many can only ADD a refusal, never remove one:
          // a word this loop does not see cannot set scriptIsFile.
          // 這幾個選項的引數是「分開的下一個字」（bash --help 的 invocation only 那組）。
          // 不吃掉它，那個字就會被當成腳本檔，於是 `curl … | bash -O extglob` 放行——實測
          // 七種寫法在 5.3 與 3.2 下都產生標記檔。多吃一個字只會多一個拒絕、不會少一個。
          if (/^[-+][A-Za-z]*[Oo]$/.test(word) || word === '--rcfile' || word === '--init-file') {
            if (k + 1 < words.length && !operatorTokens[k + 1]) k += 1;
          }
          continue;
        }
        // `-s`, `-` and a stdin PATH are markers, not script files: after one of
        // them the remaining operands are positional arguments and stdin is
        // still the script, which is why `echo "rm -rf /etc" | bash /dev/stdin`
        // and `| bash -s` are refused rather than read as `bash <script file>`.
        if (stdinScriptPaths.has(word)) { stdinMarker = true; continue; }
        if (!stdinMarker) fileOperands.push(word);
      }
      // A `/dev/fd/N` operand is not a FILE when a process substitution opened
      // fd N: `bash /dev/fd/3 3< <(curl …)` names the substitution, and reading it
      // as a script file let the whole shape through -- measured 2026-09-03,
      // marker file under both bash 5.3.15 and /bin/bash 3.2.57, for the operand
      // written before the redirect and after it. procsubByFd is built over the
      // WHOLE command line rather than this segment, so the
      // `exec 3< <(curl …); bash /dev/fd/3` spelling -- which opens the fd in an
      // earlier command -- is answered by the same test. Attributing a procsub to
      // a later segment can only add a refusal.
      // `/dev/fd/N` 操作元在「fd N 是被 process substitution 開的」時不是檔案。
      // procsubByFd 是對整條命令列建的，所以跨 `;` 的 `exec 3< <(…); bash /dev/fd/3`
      // 也由同一個判斷接住。
      for (const operand of fileOperands) {
        const fdMatch = /^(?:\/dev\/fd|\/proc\/self\/fd)\/([0-9]+)$/.exec(operand);
        const fdRange = fdMatch ? procsubByFd.get(fdMatch[1]) : undefined;
        if (fdRange) {
          if (!procsubRanges.some((range) => range.start === fdRange.start)) {
            procsubRanges.push(fdRange);
          }
          continue;
        }
        scriptIsFile = true;
      }
      const pipeFed = n > 0 && isPipeRun(segment.run);
      // Reached the carrier test only because the word is unresolvable, not
      // because it is a shell this gate knows. The refusal is the same; the
      // MESSAGE must not be, or it tells the reader their command feeds a script
      // into a shell and sends them to a URL allowlist that has nothing to do
      // with `git log | $PAGER`.
      // 只因為「這個字解不開」才走到 carrier 判斷，而不是因為它真的是 shell。拒不拒一樣，
      // 訊息不能一樣。
      const opaquePipeTarget = (dynamicCarrier && !r4Carriers.has(carrier))
        ? () => UNREADABLE_PIPE_TARGET + carrierWord
        : null;
      // The SHAPE quoted back in the refusal. When the carrier was reached
      // through xargs, `curl | bash` would describe a command line that does not
      // contain the word `bash` next to the pipe -- the reader has to be able to
      // find the shape in what they typed, which is the whole reason these
      // messages quote a shape instead of describing one.
      // 拒絕訊息裡引用的「形狀」。走過 xargs 時只寫 `curl | bash`，讀的人在自己打的那一行上
      // 找不到那個形狀——這些訊息引用形狀而不是描述行為，理由就在這裡。
      const carrierShape = stdinCompletesOperands
        ? `xargs … ${carrier} -c`
        : String(carrier);
      if (!visible && !scriptIsFile && pipeFed) {
        const producer = segments[n - 1];
        if (segment.run.includes(')') || producer.start >= producer.end) {
          // A compound producer (`( curl … ) | bash`, `{ …; } | bash`): every
          // command inside it feeds the pipe, so there is no single producer to
          // classify and the honest answer is that this gate did not read it.
          // 複合產生器：裡面每一條命令都在餵那個 pipe，沒有單一產生器可以分類。
          targets.push(
            opaquePipeTarget ? opaquePipeTarget() : `${UNSCANNABLE_SCRIPT}subshell | ${carrierShape}`,
          );
        } else {
          scriptFromProducer(
            outerContext, producer.start, producer.end,
            (label) => `${label} | ${carrierShape}`, 0, opaquePipeTarget,
          );
        }
      }
      // The carrier's script IS visible (`-c '…'`) and it is STILL fed by a pipe:
      // a command substitution inside that string reads the pipe.
      // `curl … | bash -c "$(cat)"`, `-c "$(cat /dev/stdin)"` and
      // `bash -s -c "$(cat)"` all execute what the pipe carried and were ALLOWED
      // (measured 2026-09-03, marker files under bash 5.3.15 and /bin/bash
      // 3.2.57), while `curl … | bash` beside them was refused. This is the SAME
      // substitution check the here-string route runs, on the -c argument, and it
      // is applied only when a pipe feeds the segment: `bash -c "$(curl …)"` with
      // no pipe is KNOWN-RESIDUALS.md R4-b and stays out of scope.
      // 腳本看得見（`-c '…'`）而且仍然有 pipe 在餵它：那串文字裡的命令替換讀的就是 pipe。
      // 這裡用的是 here-string 路徑同一個替換檢查，而且只在「有 pipe 餵這一段」時才跑。
      if (visible && commandOption !== null && pipeFed) {
        unscannableSubstitutions(
          commandOption, (label) => `${carrier} -c "$(${label})"`, 0,
        );
      }
      // A process substitution in a carrier's argv is in scope even with `-s`
      // (fail closed): telling "the procsub IS the script" apart from "the
      // procsub is $1" needs modelling positional parameters, which this gate
      // cannot do. If that ever bites, the narrowing is "a procsub is a script
      // source only when the carrier has no -s".
      // carrier 的 argv 裡的 process substitution 即使有 `-s` 也在範圍內（fail closed）：
      // 要分辨「procsub 就是腳本」與「procsub 是 $1」得建模位置參數。
      if (!visible && !scriptIsFile) {
        for (const range of procsubRanges) {
          scriptFromProducer(
            outerContext, range.start, range.end,
            (label) => `${carrier} <(${label})`, 0,
          );
        }
      }
      for (const body of scriptBodies) {
        unscannableSubstitutions(body, (label) => `${carrier} <<< "$(${label})"`, 0);
      }
    }
  }

  let i = 0;

  while (i < words.length) {
    while (i < words.length && operatorAt(i, separators)) i += 1;
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
      for (; i < words.length && !operatorAt(i, terminators); i += 1) {
        const candidate = words[i];
        if (operatorAt(i, redirectors)) {
          // ...but this loop also runs for an UNRESOLVABLE command word, and
          // that word may be a shell carrier, in which case its here-string is
          // the script -- the same rule the shellCarriers branch applies. Before
          // '<<<' joined the skip list these operands were collected as targets
          // and the whitespace arm below read them as commands, so
          // `CMD=bash; $CMD <<< "rm -rf /etc"` was refused; skipping them
          // outright would have turned that into an allow (measured). Only the
          // here-string spelling: '<' and '<<' take a filename, not a script.
          // ...但這個迴圈同時也服務「不可知的命令字」,而那個字可能就是 shell carrier,
          // 那樣的話它的 here-string 就是腳本——與 shellCarriers 分支同一條規則。'<<<'
          // 加進跳過清單之前,這些操作元會被當目標收走、再由下面那個空白字元的分支當成命令
          // 讀,所以 `CMD=bash; $CMD <<< "rm -rf /etc"` 是拒絕;直接跳過會讓它變成放行
          // (實測)。只針對 here-string:'<' 與 '<<' 接的是檔名,不是腳本。
          if (unresolvedExecutable && candidate === '<<<' && i + 1 < words.length) {
            if (depth >= 8) targets.push('/');
            else targets.push(...nestedScan(words[i + 1], depth + 1, false, expansionEnv));
          }
          // Skip the redirection and its filename operand (not an rm target),
          // but never skip a command terminator that follows a bare redirect.
          if (i + 1 < words.length && !operatorAt(i + 1, terminators)) i += 1;
          continue;
        }
        if (candidate === '--') continue;
        // An unresolvable command word may also be a shell carrier, so an
        // operand holding a whole command string (`$CMD -c 'rm -rf /'`) has to
        // be parsed as a command as well as compared as a path.
        if (unresolvedExecutable && /\s/.test(candidate)) {
          if (depth >= 8) targets.push('/');
          else targets.push(...nestedScan(candidate, depth + 1, false, expansionEnv));
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
        // `bash <<< "rm -rf /etc"` has no -c either: the here-STRING is what
        // bash reads on stdin, so it is the script, exactly like the heredoc
        // body above. Measured with the deletion replaced by a touch: the
        // marker appeared under /bin/bash 3.2.57, 5.3.15, `bash -s` and `sh`.
        // It reaches this loop as an operator word because the tokenizer emits
        // '<<<' as one -- the operatorTokens check is what keeps a literal
        // `echo '<<<'` from being read as the operator.
        // `bash <<< "rm -rf /etc"` 同樣沒有 -c:here-string 就是 bash 從 stdin 讀到的
        // 東西,也就是腳本本身,與上面的 heredoc 內文完全同理(把刪除換成 touch 實測,
        // 3.2.57、5.3.15、`bash -s`、`sh` 都產生了標記檔)。它以運算子字的身分進到這個
        // 迴圈,而 operatorTokens 的檢查是防止字面的 `echo '<<<'` 被當成運算子。
        if (operatorTokens[i] && words[i] === '<<<') {
          if (i + 1 < words.length) nestedCommands.push(words[i + 1]);
          i += 1;
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
        else targets.push(...nestedScan(nestedCommand, depth + 1, false, expansionEnv));
      }
      while (i < words.length && !operatorAt(i, separators)) i += 1;
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
      while (i < words.length && !operatorAt(i, terminators)) {
        // A root that only exists after expansion is unknowable, exactly as an rm
        // operand is: `find $DIR -delete` and `find "$DIR" -delete` both delete
        // (measured), and the rm branch already folds that shape to '/'. The find
        // branch pushed the raw word, so the same unknowable got two answers.
        // 展開後才知道的 root 與 rm 的操作元一樣不可知：`find $DIR -delete` 與
        // `find "$DIR" -delete` 實測都會刪。rm 那邊早就把這種形狀折成 '/'，find 這邊卻推
        // 原字，同一種不可知得到兩種答案。
        const asRoot = (index) => targetFromWord(words[index], dynamicExpansions[index], expansionEnv);
        if (words[i] === '-f') {
          if (i + 1 < words.length && !operatorAt(i + 1, terminators)) searchRoots.push(asRoot(i + 1));
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
        // NOT gated on `operatorAt` (r5-fix-better-rm-6 deliberately stops here):
        // only `;` and `+` terminate an -exec clause, which is POSIX, so an
        // escaped or quoted `|`, `&` or `(` really does end find's read of the
        // clause -- measured, BSD find answers `-exec: no terminating ";" or "+"`,
        // exits 1 and removes nothing. The three `find /etc -exec cat {} '|'
        // -delete` rows in test-hooks.js pin that, and gating this site turned
        // all three into refusals of a command that deletes nothing.
        // 這一處刻意不接上 `operatorAt`：只有 `;` 與 `+` 會終止 -exec 子句（POSIX），所以
        // 跳脫或加引號的 `|`、`&`、`(` 真的會結束 find 對子句的讀取——實測 BSD find 回
        // 「no terminating ";" or "+"」、exit 1、什麼都沒刪。test-hooks.js 裡那三列
        // `find /etc -exec cat {} '|' -delete` 就是釘它的，把這裡接上會把三列都變成誤擋。
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
    } else if (executable === 'trap') {
      // `trap '<action>' <sigspec…>`: the action is SHELL CODE, and it runs when
      // the signal arrives. Nothing in this file used to treat "this command's
      // argument is a script" as a scan source, so `trap 'rm -rf /etc' EXIT`
      // was allowed and really deleted (KNOWN-RESIDUALS.md R5-c). MEASURED with
      // touch markers rather than reasoned about, 2026-09-05: the action really
      // executes for EXIT, ERR, DEBUG, a named signal, the numeric `0`, the
      // lowercase `exit`, several signals at once, after `--`, and through
      // `builtin trap` / `command trap` / `\trap` -- under bash 5.3.15,
      // bash 3.2.57, sh, zsh, dash and ksh alike.
      // The action is handed to nestedScan, the same treatment `bash -c '…'`
      // gets, so every rule in this file applies inside it instead of a second
      // copy of any of them living here.
      // `trap '<動作>' <訊號>` 的第一個引數就是 shell 程式碼，訊號到達時會執行。本檔案先前
      // 沒有任何一支把「某個命令的引數其實是腳本」當成掃描來源。動作交給 nestedScan，與
      // `bash -c '…'` 同一條路，所以規則只有一份。
      let actionIndex = -1;
      let sawDoubleDash = false;
      for (; i < words.length && !separators.has(words[i]); i += 1) {
        const word = words[i];
        if (operatorTokens[i] || heredocBodies.has(i)) continue;
        if (!sawDoubleDash && word === '--') { sawDoubleDash = true; continue; }
        // `-l` and `-p` are trap's PRINT options. Skipping the option WORD and
        // going on to read the next operand is one branch; "print mode, so do
        // not look at all" would be a second branch whose only effect is to turn
        // a refusal into an allowance for `trap -p '<action>' EXIT` -- a shape
        // measured NOT to execute, so the allowance would buy nothing and the
        // branch would be one more thing to get wrong.
        // `-l`／`-p` 是列印選項。跳過選項字、繼續讀下一個操作元就夠了；多寫一個「列印模式
        // 就不要看」的分支，唯一作用是把一個實測不會執行的形狀從拒絕改成放行。
        if (!sawDoubleDash && /^-[lp]+$/.test(word)) continue;
        actionIndex = i;
        break;
      }
      // `trap - EXIT` (reset) and `trap '' INT` (ignore) are the two most common
      // lines in any script that cleans up after itself, and neither is an
      // action. Reading them as one would refuse both.
      // `trap - EXIT`（重設）與 `trap '' INT`（忽略）都不是動作。
      const action = actionIndex >= 0 ? words[actionIndex] : '';
      if (action !== '' && action !== '-') {
        // The action's TEXT has to be known before it can be scanned. It is
        // resolved by exactly the function an rm operand uses, so
        // `trap 'rm -rf "$TMPDIR/x"' EXIT` is read, resolved and judged ordinary
        // while `trap "$CMD" EXIT` -- whose text only exists after expansion --
        // fails closed. A blanket "the word contains a $" test would refuse the
        // first one too, which is the shape a real cleanup trap is written in.
        // 動作的「文字」要先知道才掃得了。用的是 rm 操作元同一個解析函式，所以真正的清理
        // trap 讀得出來，而文字要展開後才知道的那種 fail closed。
        const actionText = hasUnresolvedTargetExpansion(dynamicExpansions[actionIndex])
          ? resolveKnownExpansions(action, expansionEnv)
          : action;
        if (actionText === null) targets.push(UNREADABLE_TRAP_ACTION + action);
        else if (depth >= 8) targets.push('/');
        else targets.push(...nestedScan(actionText, depth + 1, false, expansionEnv));
      }
      while (i < words.length && !operatorAt(i, separators)) i += 1;
    } else if (executable === 'eval') {
      const nestedCommand = [];
      for (; i < words.length && !separators.has(words[i]); i += 1) {
        nestedCommand.push(words[i]);
      }
      if (nestedCommand.length > 0) {
        if (depth >= 8) targets.push('/');
        else targets.push(...nestedScan(nestedCommand.join(' '), depth + 1, false, expansionEnv));
      }
    } else {
      while (i < words.length && !operatorAt(i, separators)) i += 1;
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
// The refusal for an `env -S` string this gate could not split the way env(1)
// would. It has to say WHICH rule it could not model, or the reader is left to
// guess at a string they wrote themselves; and it has to offer a way through
// that this gate still judges -- spelling the words out as ordinary argv is
// exactly that, because then there is no -S string left to split.
// 這是「-S 字串沒辦法照 env(1) 的規則切開」時的拒絕。它必須說出「是哪一條規則沒能建模」，否
// 則讀的人只能對著自己寫的字串猜；而它給的出路必須是這道閘門仍然會判定的形狀——把那些字直接
// 寫成普通 argv 正好就是，因為那樣就沒有 -S 字串要切了。
function unjudgeableEnvStringDenial(rule, isCopilot, isAntigravity, isCursor, isGrok) {
  const zh = `拒絕刪除：無法確定 env -S 的字串會被拆成哪些字，因為它含有${rule}，`
    + `而 env(1) 拆 -S 的規則與 shell 不同（\`\\_\` 會切開、字首的 \`#\` 是註解、\`\${VAR}\` 會展開），`
    + `拆錯就等於看不見那條刪除命令。`
    + `繞法：不要用 -S，把那些字直接寫成 env 的引數，例如 env FOO=1 rm -rf /path。`;
  const en = `Refused to remove: cannot determine how env -S splits its string, because it contains ${rule},`
    + ` and env(1) does not split -S the way a shell does (\`\\_\` splits, a leading \`#\` comments,`
    + ` \`\${VAR}\` is expanded); splitting it wrong is the same as not seeing the removal at all.`
    + ` Workaround: drop -S and spell the words as env's own arguments, e.g. env FOO=1 rm -rf /path.`;
  return denialShape(`${zh} / ${en}`, isCopilot, isAntigravity, isCursor, isGrok);
}

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

// The refusal for a script this gate could not READ. It is the first refusal in
// this file that says 拒絕執行 / "Refused to run" rather than 拒絕刪除 /
// "Refused to remove", and the difference is not cosmetic: nothing here names a
// protected directory, and borrowing that wording would send people looking for
// a path the command never wrote -- the same defect UNRESOLVED_TARGET exists to
// avoid. It quotes the SHAPE it saw (`curl | bash`) rather than describing it,
// names the rule so the message can be searched for, and gives two ways through
// plus the one knob, because a refusal with no way out is how people end up
// disabling the gate. Anything that greps this repository's refusals for
// 刪除/remove will not see these: that is a deliberate consequence of the new
// posture, recorded in CHANGELOG.md.
// 這是「腳本讀不到」的拒絕。它是本檔案第一個說「拒絕執行」而不是「拒絕刪除」的訊息，而這個
// 差別不是修辭：這裡沒有任何受保護目錄被指名，借用那套措辭只會讓人去找一條命令從來沒寫過的
// 路徑——與 UNRESOLVED_TARGET 存在的理由是同一件事。訊息引用它看到的「形狀」而不是描述它、
// 指名規則（方便搜尋），並給兩條繞法加一個旋鈕，因為沒有出路的拒絕最後換來的是有人把整道
// 閘門關掉。
function unscannableScriptDenial(shape, isCopilot, isAntigravity, isCursor, isGrok) {
  const zh = `拒絕執行：這條命令把腳本從 pipe 或 process substitution 餵給 shell（${shape}），`
    + `這道閘門在執行前讀不到那段腳本，因此無法判斷它會不會刪除受保護的目錄`
    + `（這不是說它一定會刪，是說這道閘門讀不到）。規則：unscannable piped script。`
    + `繞法：先存成檔案再讀過執行（curl -o install.sh <url> && bash install.sh），`
    + `或把命令寫成字面的 <shell> -c '<命令>'。`
    + `若這是一條你信任的安裝路徑，把「整條命令列」加進 hooks/protect-important-paths.js 的`
    + ` CANONICAL_INSTALL_LINES（豁免比對的是一整行，前後多一個字都不算），`
    + `它的網址前綴同時要在 PIPED_SCRIPT_EXCEPTIONS 上 —— 這兩份清單比對的都是命令列上的`
    + `文字，不是身分驗證。`;
  const en = `Refused to run: this command feeds a script into a shell through a pipe or a process`
    + ` substitution (${shape}), and this gate cannot read that script before it runs, so it cannot tell`
    + ` whether the script removes a protected directory (this does not say that it does; it says this`
    + ` gate could not read it). Rule: unscannable piped script.`
    + ` Workaround: save it to a file and read it first (curl -o install.sh <url> && bash install.sh),`
    + ` or spell the command literally as <shell> -c '<command>'. If this is an install route you trust,`
    + ` add the WHOLE command line to CANONICAL_INSTALL_LINES in hooks/protect-important-paths.js (the`
    + ` exemption matches a whole line, so one extra character before or after it is a different line),`
    + ` and its URL prefix must also be on PIPED_SCRIPT_EXCEPTIONS -- both lists match TEXT on the`
    + ` command line and neither is an identity check.`;
  return denialShape(`${zh} / ${en}`, isCopilot, isAntigravity, isCursor, isGrok);
}

// The refusal for a pipe whose RECEIVING END this gate could not resolve. It is
// separate from unscannableScriptDenial on purpose: that message states as fact
// that the command feeds a script into a shell and offers PIPED_SCRIPT_EXCEPTIONS
// as the way through. Neither is true here -- the word may be a pager, a
// formatter or anything else, and no URL allowlist can help -- and a refusal that
// describes a command the user did not write is the defect UNRESOLVED_TARGET
// exists to avoid. It names the word it could not resolve, names its own rule so
// the message is searchable, and gives the two spellings that make it go away.
// 「管線接收端解不開」的拒絕。刻意與 unscannableScriptDenial 分開：那句話把「餵腳本給
// shell」講成事實、並把 PIPED_SCRIPT_EXCEPTIONS 當成出路，這裡兩者都不成立。
function unreadablePipeTargetDenial(word, isCopilot, isAntigravity, isCursor, isGrok) {
  const zh = `拒絕執行：這條管線的接收端（${word}）是一個要展開後才知道的命令字，`
    + `而它後面沒有任何字指出要讀哪個檔案，所以它可能就是一個從 pipe 讀腳本的 shell，`
    + `這道閘門在執行前分辨不出來（這不是說它一定是，是說這道閘門解不開這個字）。`
    + `規則：unresolvable pipe target。`
    + `繞法：把它寫成字面的絕對路徑（例如 /usr/bin/less），或給它一個檔案操作元。`
    + `只有 $HOME、$PWD、$TMPDIR 會被解析。`;
  const en = `Refused to run: the receiving end of this pipe (${word}) is a command word that only`
    + ` exists after expansion, and nothing after it names a file to read, so it may be a shell taking`
    + ` its script from the pipe and this gate cannot tell before it runs (this does not say that it is;`
    + ` it says this gate could not resolve the word). Rule: unresolvable pipe target.`
    + ` Workaround: spell it as a literal absolute path (e.g. /usr/bin/less), or give it a file operand.`
    + ` Only $HOME, $PWD and $TMPDIR are resolved.`;
  return denialShape(`${zh} / ${en}`, isCopilot, isAntigravity, isCursor, isGrok);
}

// The refusal for a `trap` action this gate could not read (R5-c). Separate from
// unscannableScriptDenial for the reason recorded at UNREADABLE_TRAP_ACTION: that
// message names a pipe, a shell and a URL allowlist, and none of the three is in
// `trap "$CMD" EXIT`. It names the word it could not resolve, names its own rule
// so the message is searchable, and gives the two spellings that make it go away.
// 「讀不到 trap 動作」的拒絕。與 unscannableScriptDenial 分開的理由記在
// UNREADABLE_TRAP_ACTION：那句話講的 pipe、shell 與網址清單，這裡一個都沒有。
function unreadableTrapActionDenial(word, isCopilot, isAntigravity, isCursor, isGrok) {
  const zh = `拒絕執行：這條命令替某個訊號裝上一段這道閘門讀不到的動作（trap 的第一個引數就是`
    + ` shell 程式碼，訊號到達時會執行），而 ${word} 要展開之後才知道是什麼，`
    + `所以無法判斷那段程式碼會不會刪除受保護的目錄`
    + `（這不是說它一定會刪，是說這道閘門讀不到）。規則：unreadable trap action。`
    + `繞法：把動作寫成字面的命令（trap 'rm -rf /tmp/build' EXIT），`
    + `或把它放進腳本檔、改成 trap 'bash /path/cleanup.sh' EXIT。`
    + `只有 $HOME、$PWD、$TMPDIR 會被解析。`;
  const en = `Refused to run: this command installs a trap whose action this gate cannot read`
    + ` (trap's first argument IS shell code and runs when the signal arrives), because ${word}`
    + ` only exists after expansion, so it cannot tell whether that code removes a protected`
    + ` directory (this does not say that it does; it says this gate could not read it).`
    + ` Rule: unreadable trap action.`
    + ` Workaround: spell the action literally (trap 'rm -rf /tmp/build' EXIT), or put it in a`
    + ` script file and trap that (trap 'bash /path/cleanup.sh' EXIT).`
    + ` Only $HOME, $PWD and $TMPDIR are resolved.`;
  return denialShape(`${zh} / ${en}`, isCopilot, isAntigravity, isCursor, isGrok);
}

// The refusal for a scan that ran out of failed-read budget (R5-13). Its own
// wording for the reason recorded at SUBSTITUTION_BUDGET_EXHAUSTED: the other
// three "could not read" messages each name the THING they could not read -- a
// piped script, a pipe target, a trap action -- and here the thing is the rest of
// the command. It names the count, because that is what the user can act on, and
// it names its own rule so the message is searchable.
// The way out is deliberately about the OPENERS and not about the deletion: the
// gate is not asking the user to remove a deletion it never claimed to have
// found, it is asking them to write the 64 unreadable openers in a way a reader
// can get past -- close them, single-quote them, or move the text into a file.
// 「掃描的讀取預算用完」的拒絕（R5-13）。自成一種訊息的理由記在
// SUBSTITUTION_BUDGET_EXHAUSTED：另外三種「讀不到」都指名了讀不到的東西，這裡讀不到的是
// 「命令剩下的部分」。訊息帶著數量（使用者唯一能據以行動的數字）並指名規則名以便搜尋。
// 出路刻意講「開頭」而不是「刪除」：閘門沒有宣稱找到刪除，它要求的是把那些開頭寫成讀得過
// 去的樣子。
function substitutionBudgetDenial(count, isCopilot, isAntigravity, isCursor, isGrok) {
  const zh = '拒絕執行：這條命令裡有 ' + count + ' 個這道閘門讀不出來的替換開頭'
    + '（`$(`、`<(` 或 `${`，到輸入結尾都沒有收尾），單次判定的讀取預算已經用完，'
    + '所以「它們後面」的替換這道閘門一個也沒有掃到——包含可能藏在那裡的刪除'
    + '（這不是說一定有，是說這道閘門沒有讀到）。規則：substitution budget exhausted。'
    + '繞法：把沒有收尾的開頭補完、或改成單引號，或把那段文字放進檔案再讓命令去讀。';
  const en = 'Refused to run: this command carries ' + count + ' substitution openers this gate'
    + ' could not read (`$(`, `<(` or `${` with no closer before the end of the input), which'
    + ' spends the whole per-invocation read budget, so every substitution AFTER them went'
    + ' unscanned -- including any deletion hidden there (this does not say one is; it says this'
    + ' gate did not read it). Rule: substitution budget exhausted (' + count
    + ' unreadable openers).'
    + ' Workaround: close the openers, or single-quote them, or move the text into a file and'
    + ' have the command read it from there.';
  return denialShape(zh + ' / ' + en, isCopilot, isAntigravity, isCursor, isGrok);
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
    if (
      target.startsWith(UNRESOLVED_TARGET)
      || target.startsWith(UNSCANNABLE_SCRIPT)
      || target.startsWith(UNREADABLE_PIPE_TARGET)
      || target.startsWith(UNJUDGEABLE_ENV_S)
      || target.startsWith(UNREADABLE_TRAP_ACTION)
      || target.startsWith(SUBSTITUTION_BUDGET_EXHAUSTED)
    ) continue;
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
  // A script this gate could not read beats the unresolved-variable message:
  // it names a concrete rule and carries the way through, and for
  // `echo "$cmd" | bash` the unresolved message would be a lie -- that command
  // has no deletion target at all. A protected path found in a producer this
  // gate COULD read still wins over both, above.
  // 「讀不到腳本」的訊息優先於「解不開變數」：它指名一條具體規則、也帶著出路，而對
  // `echo "$cmd" | bash` 來說，解不開變數那句話是假的——那條命令根本沒有刪除目標。
  // NOTE, deliberately not "fixed": the sentinel is pushed into `targets`, so it
  // counts toward unjudgeableDenial's totalCount above. Filtering it out would
  // need a second pass over the array to change one number in a timeout message.
  // FIRST among the "could not read" refusals (R5-13), and above them all for a
  // reason none of them shares: the other three describe something this gate DID
  // read and could not resolve -- a script it can see arriving on a pipe, a pipe
  // target word, a trap action -- while this one says a stretch of the command was
  // never read at all. Anything those three could have said about the unread part
  // would be a guess about text nobody looked at. A protected path found BEFORE
  // the budget ran out still wins over this, in the loop above, because a concrete
  // path is the more useful thing to be told -- and every one of the timing rows
  // in test-hooks.js is exactly that shape, so they keep naming `/etc`.
  // 排在所有「讀不到」拒絕的最前面，理由是其他三種都沒有的：它們描述的是「讀到了但解不
  // 開」，這一種說的是「有一段根本沒讀」。上面那個迴圈找到的受保護路徑仍然勝過它——具體的
  // 路徑對使用者更有用。
  for (const target of targets) {
    if (!target.startsWith(SUBSTITUTION_BUDGET_EXHAUSTED)) continue;
    return substitutionBudgetDenial(
      target.slice(SUBSTITUTION_BUDGET_EXHAUSTED.length), isCopilot, isAntigravity, isCursor,
      isGrok,
    );
  }
  for (const target of targets) {
    if (!target.startsWith(UNSCANNABLE_SCRIPT)) continue;
    return unscannableScriptDenial(
      target.slice(UNSCANNABLE_SCRIPT.length), isCopilot, isAntigravity, isCursor, isGrok,
    );
  }
  // Below the unscannable-script refusal and above the unresolved-variable one,
  // for the same reason that one is ordered where it is: it names a concrete rule
  // and carries the way through, while "cannot determine which path this expands
  // to" would be a lie -- `git log | $PAGER` has no deletion target at all.
  // 排在「讀不到腳本」之後、「解不開變數」之前，理由與後者相同：`git log | $PAGER` 根本沒有
  // 刪除目標，用那句話回答是假的。
  for (const target of targets) {
    if (!target.startsWith(UNREADABLE_PIPE_TARGET)) continue;
    return unreadablePipeTargetDenial(
      target.slice(UNREADABLE_PIPE_TARGET.length), isCopilot, isAntigravity, isCursor, isGrok,
    );
  }
  // Above the unresolved-variable refusal, for the same reason the two above it
  // are: this one names the rule it could not model and carries the way through,
  // while "cannot determine which path this expands to" would be pointing at an
  // operand when the thing that could not be read is the -S string.
  // 排在「解不開變數」之前，理由與上面兩個相同：它指名了沒能建模的那條規則、也帶著出路，而
  // 「算不出這個操作元展開成哪條路徑」會指著操作元，可是讀不出來的是那段 -S 字串。
  // Above the unresolved-variable refusal, alongside the two refusals before it
  // and for the same reason: it names the rule it could not read past and carries
  // the way through, while "cannot determine which path this expands to" would
  // point at an operand when the thing that could not be read is the trap action
  // -- and `trap "$CMD" EXIT` has no deletion operand at all.
  // 排在「解不開變數」之前，理由與前面兩個相同：`trap "$CMD" EXIT` 根本沒有刪除操作元，
  // 用那句話回答是假的。
  for (const target of targets) {
    if (!target.startsWith(UNREADABLE_TRAP_ACTION)) continue;
    return unreadableTrapActionDenial(
      target.slice(UNREADABLE_TRAP_ACTION.length), isCopilot, isAntigravity, isCursor, isGrok,
    );
  }
  for (const target of targets) {
    if (!target.startsWith(UNJUDGEABLE_ENV_S)) continue;
    return unjudgeableEnvStringDenial(
      target.slice(UNJUDGEABLE_ENV_S.length), isCopilot, isAntigravity, isCursor, isGrok,
    );
  }
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

module.exports = { HOME_DIRS, MAX_FAILED_SUBSTITUTION_READS, MOUNT_PARENTS, SYSTEM_DIRS, commandSubstitutions, commandTargets, evaluate, globCanMatchGit, hasGlob, normalizedTarget, protectedReason, shellWords };
