#!/usr/bin/env node
// Block coding agents from passing protected directories to destructive shell commands.
// 阻擋 coding agent 將受保護目錄傳給破壞性 shell 命令。

'use strict';

const os = require('os');
const path = require('path');

const SYSTEM_DIRS = [
  '/', '/bin', '/boot', '/dev', '/etc', '/home', '/lib', '/lib64', '/mnt', '/opt',
  '/proc', '/root', '/sbin', '/sys', '/usr', '/var',
];

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

function shellWords(command) {
  const words = [];
  const input = String(command || '');
  let word = '';
  let quote = '';
  let escaped = false;

  for (let index = 0; index < input.length; index += 1) {
    const char = input[index];
    if (escaped) {
      word += char;
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
      else word += char;
    } else if (char === '$' && input[index + 1] === "'") {
      quote = 'ansi-c';
      index += 1;
    } else if (char === '"' || char === "'") {
      quote = char;
    } else if (';&|()<>\n'.includes(char)) {
      if (word) words.push(word), word = '';
      words.push(char);
    } else if (/\s/.test(char)) {
      if (word) words.push(word), word = '';
    } else {
      word += char;
    }
  }
  if (escaped) word += '\\';
  if (word) words.push(word);
  return words;
}

function commandSubstitutions(command) {
  const input = String(command || '');
  const commands = [];
  let quote = '';
  let escaped = false;

  function readParenthesized(openIndex) {
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
      const nested = readParenthesized(i + 1);
      if (nested) {
        commands.push(nested.command);
        i = nested.end;
      }
      continue;
    }
    if ((char === '<' || char === '>') && input[i + 1] === '(') {
      const nested = readParenthesized(i + 1);
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
  const expanded = expandHome(value.replace(/[\\/]+$/, '') || '/', home);
  if (/[*?\[\]{}]/.test(expanded)) return expanded;
  return path.resolve(cwd, expanded);
}

function globCanMatchGit(value) {
  const basename = path.basename(value);
  if (!/[*?\[\]{}]/.test(basename)) return false;
  const alternatives = basename.replace(/^\{(.+)\}$/, '$1').split(',');
  return alternatives.some((pattern) => {
    const expression = pattern
      .replace(/[.+^$()|\\]/g, '\\$&')
      .replace(/\*/g, '.*')
      .replace(/\?/g, '.');
    try { return new RegExp(`^${expression}$`).test('.git'); } catch (_) { return true; }
  });
}

function protectedReason(target, cwd, home, extraDirs = []) {
  const normalized = normalizedTarget(target, cwd, home);
  const exactDirs = [...SYSTEM_DIRS, home, ...extraDirs].map((item) => path.resolve(item));

  if (exactDirs.includes(normalized)) return normalized;

  // Protect first-level mount roots under /mnt (such as /mnt/c), while allowing items inside them.
  // 保護 /mnt 的第一層掛載根（如 /mnt/c），但允許操作掛載點內的項目（如 /mnt/c/project）。
  const mntRelative = path.relative('/mnt', normalized);
  if (
    mntRelative &&
    !mntRelative.startsWith('..') &&
    !path.isAbsolute(mntRelative) &&
    !mntRelative.includes(path.sep)
  ) return normalized;

  if (normalized === '.git' || normalized.endsWith(`${path.sep}.git`)) return normalized;

  if (/(^|[\\/])\.git([\\/]|$)/.test(normalized)) return normalized;
  // A glob that can select .git is unsafe even though it cannot be resolved beforehand.
  // 可能選中 .git 的萬用字元無法事先解析，因此一律視為不安全。
  if (globCanMatchGit(normalized)) return normalized;
  return null;
}

function commandTargets(command, depth = 0) {
  const words = shellWords(command);
  const targets = [];
  const separators = new Set([';', '&', '|', '(', ')', '<', '>', '\n']);
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
  const substitutions = commandSubstitutions(command);
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

      break;
    }

    i += 1;
    if (['rm', 'rmdir'].includes(executable)) {
      for (; i < words.length && !separators.has(words[i]); i += 1) {
        const candidate = words[i];
        if (candidate === '--') continue;
        if (!candidate.startsWith('-') || candidate === '-') targets.push(candidate);
      }
    } else if (shellCarriers.has(executable)) {
      const nestedCommands = [];
      for (; i < words.length && !separators.has(words[i]); i += 1) {
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
    process.exit(1);
  }
}

if (require.main === module) main();

module.exports = { commandTargets, evaluate, globCanMatchGit, normalizedTarget, protectedReason, shellWords };
