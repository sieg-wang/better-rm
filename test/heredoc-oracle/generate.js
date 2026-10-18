'use strict';
// Differential-oracle corpus generator for test-hooks-heredoc-corpus.json
// (heredoc-in-$()/<()/backquote shapes, BR2-2-REG3). Nothing here executes a
// shape: each shape is rendered twice from one stand-in slot --
//   - a PARSE PROBE (slot = the bare word RUNCMD), wrapped in a never-called
//     `f() { ... }`, which label.sh feeds to `bash -n` and a `;;` differential
//     only (parse, never run); and
//   - the corpus COMMAND (slot = `rm -rf /etc`), which test-hooks.js hands to
//     the hook's evaluate() only.
// So no shell ever sees `rm`, and the hook never runs anything.
//
//   node test/heredoc-oracle/generate.js probes <dir>     write <dir>/<id>.sh
//   test/heredoc-oracle/label.sh <dir> > labels.tsv        label (parse only)
//   node test/heredoc-oracle/generate.js corpus <labels>   print corpus JSON
//
// test-hooks.js re-derives shapes() and asserts that the checked-in corpus rows
// are exactly this list, in order (id and command), so the frozen runs53/runs32
// labels belong to it. This is the round-4 enumeration unchanged; it was the
// generator in the 2026-10-17 campaign's private directory, moved in here so the
// labels can be regenerated from the repository (FU-BR-ORACLE-IN-REPO).
const fs = require('fs');
const path = require('path');

const MK = 'RUNCMD';          // the stand-in as a harmless command word (oracle)
const DEL = 'rm -rf /etc';    // the stand-in as a protected removal (hook)
const TAB = '\t';

function delimStyles() {
  return {
    plain: (name) => ({ op: `<<${name}`, endWord: name, dash: false, empty: false }),
    quoted: (name) => ({ op: `<<'${name}'`, endWord: name, dash: false, empty: false }),
    dash: (name) => ({ op: `<<-${name}`, endWord: name, dash: true, empty: false }),
    empty: () => ({ op: "<<''", endWord: '', dash: false, empty: true }),
  };
}

function heredocLines(styles, closes) {
  const lines = [];
  styles.forEach((st, i) => {
    const body = st.empty ? 'ebody' : `body${i}`;
    lines.push(st.dash ? TAB + body : body);
    let delimLine = st.dash ? TAB + st.endWord : st.endWord;
    if (closes[i].paren) delimLine += ')' + (closes[i].tail || '');
    else if (closes[i].tail) delimLine += closes[i].tail;
    lines.push(delimLine);
  });
  return lines;
}

const containers = {
  dollar: { open: 'x=$(cat ', kind: 'sub', closeParen: ')' },
  dq: { open: 'x="$(cat ', kind: 'sub', closeParen: ')"' },
  procsub: { open: 'diff <(cat ', kind: 'sub', closeParen: ') b.txt' },
  backtick: { open: 'x=`cat ', kind: 'backtick', closeParen: '`' },
  nested: { open: 'x=$(echo $(cat ', kind: 'sub', closeParen: '))' },
};

function shapes() {
  const built = [];
  const seen = new Set();
  const add = (rec) => {
    if (seen.has(rec.cmd)) return;
    seen.add(rec.cmd);
    built.push(rec);
  };
  const ST = delimStyles();
  const names = ['A', 'B', 'C'];

  for (const [cname, c] of Object.entries(containers)) {
    const paren = c.kind === 'sub';
    for (let n = 1; n <= 3; n += 1) {
      const styleSets = n === 1
        ? ['plain', 'quoted', 'dash', 'empty'].map((s) => [s])
        : n === 2
          ? [['plain', 'plain'], ['quoted', 'quoted'], ['dash', 'plain'], ['empty', 'plain']]
          : [['plain', 'plain', 'plain'], ['quoted', 'quoted', 'quoted']];
      for (const styleNames of styleSets) {
        const styles = styleNames.map((s, i) => (s === 'empty' ? ST.empty() : ST[s](names[i])));
        const ops = styles.map((s) => s.op).join(' ');
        const closeChoices = [];
        if (paren) {
          for (let mask = 0; mask < (1 << n); mask += 1) {
            const closes = [];
            for (let i = 0; i < n; i += 1) closes.push({ paren: Boolean(mask & (1 << i)) });
            closeChoices.push(closes);
          }
        } else {
          closeChoices.push(Array.from({ length: n }, () => ({ paren: false })));
        }
        for (const baseCloses of closeChoices) {
          for (const placement of ['same', 'next', 'inside']) {
            const closes = baseCloses.map((x) => ({ ...x }));
            const lastIsParen = closes[n - 1].paren;
            let trailingLines = [];
            let standInPlaced = false;
            if (placement === 'inside') {
              const idx = closes.findIndex((x) => x.paren);
              if (paren && idx !== -1) {
                closes[idx].tail = ` %S%`;
                standInPlaced = true;
              } else {
                continue;
              }
            }
            if (!standInPlaced && placement === 'same') {
              const idx = lastIsParen ? n - 1 : -1;
              if (paren && idx !== -1) {
                closes[idx].tail = `; %S%`;
                standInPlaced = true;
              } else if (paren && !lastIsParen) {
                trailingLines = [`${c.closeParen.replace(/^[)]/, ')')}; %S%`];
                standInPlaced = true;
              } else {
                trailingLines = [`${c.closeParen}; %S%`];
                standInPlaced = true;
              }
            }
            if (!standInPlaced && placement === 'next') {
              if (paren && lastIsParen) {
                trailingLines = ['%S%'];
              } else if (paren) {
                trailingLines = [c.closeParen, '%S%'];
              } else {
                trailingLines = [c.closeParen, '%S%'];
              }
              standInPlaced = true;
            }
            const body = heredocLines(styles, closes);
            const parenCloseEmitted = closes.some((x) => x.paren);
            const lines = [];
            lines.push(`${c.open}${ops}`);
            for (const l of body) lines.push(l);
            if (!parenCloseEmitted && placement === 'inside') continue;
            for (const l of trailingLines) lines.push(l);
            const probe = lines.map((l) => l.replace('%S%', MK));
            const cmdLines = lines.map((l) => l.replace('%S%', DEL));
            if (!probe.join('\n').includes(MK)) continue;
            const id = `o-${cname}-n${n}-${styleNames.join('')}-${closes.map((x) => (x.paren ? 'P' : 'x')).join('')}-${placement}`;
            add({ id, probe: probe.join('\n'), cmd: cmdLines.join('\n') });
          }
        }
      }
    }
  }

  // The curated shapes named in the two 2026-10-17 reviews, pinned regardless of
  // the combinatorial enumeration; they go FIRST. `%S%` is the stand-in slot.
  const curated = [
    ['c-m1-dollar-2hd-Apar-next', ['x=$(cat <<A <<B', 'A)', 'B', '%S%']],
    ['c-m1q-dollar-2hd-Apar-next', ["x=$(cat <<'A' <<'B'", 'A)', 'B', '%S%']],
    ['c-m2-dollar-2hd-Apar-same', ['x=$(cat <<A <<B', 'A); %S%', 'B']],
    ['c-m3-version-2hd-Apar-next', ['VERSION=$(cat <<A <<B', '1.2', 'A)', 'B', '%S%']],
    ['c-m1-dq-2hd-Apar-next', ['x="$(cat <<A <<B', 'A)', 'B', ')"', '%S%']],
    ['c-single-eofpar-next', ["x=$(cat <<'EOF'", 'body', 'EOF)', '%S%']],
    ['c-p02-inside-afterdelim', ["x=$(cat <<'EOF'", 'body', 'EOF %S%)']],
    ['c-p09-emptydelim-paren', ["x=$(cat <<''", '%S%)']],
    ['c-p10-procsub-eofpar-next', ['diff <(cat <<A', 'a', 'A) b.txt', '%S%']],
    ['c-procsub-2hd-Apar-next', ['diff <(cat <<A <<B', 'A) b.txt', 'B', '%S%']],
    ['c-p13-last-par-next', ['x=$(cat <<A <<B', 'A', 'B)', '%S%']],
    ['c-nested-2hd-Apar-next', ['x=$(echo $(cat <<A <<B', 'A)', 'B', '))', '%S%']],
    ['c-dash-2hd-Apar-next', ['x=$(cat <<-A <<-B', `${TAB}A)`, `${TAB}B`, '%S%']],
    ['c-m1-threehd-Apar-next', ['x=$(cat <<A <<B <<C', 'A)', 'B', 'C', '%S%']],
    ['c-m1-threehd-Bpar-next', ['x=$(cat <<A <<B <<C', 'A', 'B)', 'C', '%S%']],
  ];
  const curatedShapes = curated.map(([id, lines]) => ({
    id,
    probe: lines.join('\n').replace(/%S%/g, MK),
    cmd: lines.join('\n').replace(/%S%/g, DEL),
  }));
  const curatedSeen = new Set(curatedShapes.map((s) => s.cmd));
  const combos = built.filter((s) => !curatedSeen.has(s.cmd));
  const all = [...curatedShapes, ...combos];
  if (all.length > 600) throw new Error(`corpus too big: ${all.length} > 600; tighten the enumeration`);
  return all;
}

function main() {
  const mode = process.argv[2];
  if (mode === 'probes') {
    const dir = process.argv[3];
    fs.rmSync(dir, { recursive: true, force: true });
    fs.mkdirSync(dir, { recursive: true });
    for (const s of shapes()) fs.writeFileSync(path.join(dir, `${s.id}.sh`), `f() {\n${s.probe}\n}\n`);
    process.stderr.write(`wrote ${shapes().length} probes to ${dir}\n`);
    return;
  }
  if (mode !== 'corpus') {
    process.stderr.write('usage: generate.js probes <dir> | corpus <labels.tsv>\n');
    process.exit(2);
  }
  const labels = new Map(fs.readFileSync(process.argv[3], 'utf8').trim().split('\n').slice(1)
    .map((l) => l.split('\t')).map(([id, r53, r32]) => [id, { r53: r53 === 'yes', r32: r32 === 'yes' }]));
  const rows = shapes().map((s) => {
    const lab = labels.get(s.id);
    if (!lab) throw new Error(`no label for ${s.id}`);
    return { id: s.id, cmd: s.cmd, runs53: lab.r53, runs32: lab.r32 };
  });
  const mustDeny = rows.filter((r) => r.runs53 || r.runs32).length;
  process.stdout.write(`${JSON.stringify({ shapes: rows.length, mustDeny, rows }, null, 1)}\n`);
}

if (require.main === module) main();

module.exports = { shapes };
