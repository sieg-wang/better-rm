'use strict';
// Differential-oracle corpus generator for R7-b (test-hooks-heredoc-backquote-
// corpus.json). Nothing here executes a shape.
//
// An UNQUOTED backquote substitution at the top level of a command holds a
// heredoc whose body the closing backquote ends (the backquote sits on a
// delimiter line, or an empty `<<''` body reaches it), or an unmatched quote, or
// a comment. bash reads the whole backquote as one word, so what follows the
// closing backquote is a command of its own. Read character by character, the
// heredoc (or the quote, or the comment) runs past the closing backquote and
// hides that command (KNOWN-RESIDUALS.md R7-b).
//
// Three families:
//   line-  the closing backquote on a heredoc's delimiter line, or on a line of
//          its own after the delimiters; the stand-in after the backquote, on
//          its line, or as the first body line inside it (round 4b, 132 shapes);
//   tail-  the round-4 guard validator's backquote shapes: one to three heredocs,
//          the closing backquote glued to the last line, the stand-in on the
//          next line;
//   other- an unmatched quote or a comment inside the backquote.
//
// Each shape is rendered twice from one stand-in slot:
//   - a PARSE PROBE: slot = the bare word RUNCMD, wrapped in a never-called
//     `f() { ... }`; label.sh feeds it to `bash -n` only, under two bashes.
//   - the corpus COMMAND: slot = `rm -rf /etc`, handed to the hook's evaluate()
//     only (test-hooks.js), never to a shell.
// So no shell ever sees `rm`, and the hook never runs anything. `bash -n` does
// not parse the inside of a backquote, so a stand-in written as a COMMAND inside
// one would read "does not run" while it does run when the substitution expands;
// no shape here puts it there (inside a backquote it is always heredoc data).
//
//   node test/heredoc-backquote/generate.js probes <dir>      write <dir>/<id>.sh
//   test/heredoc-backquote/label.sh <dir> > labels.tsv        label (parse only)
//   node test/heredoc-backquote/generate.js corpus <labels>   print corpus JSON
//
// test-hooks.js re-derives shapes() and checks that the corpus rows are exactly
// this list, in order, so the checked-in labels belong to it.
const fs = require('fs');
const path = require('path');

const MK = 'RUNCMD';
const DEL = 'rm -rf /etc';
const TAB = '\t';

// line-: the round-4b shapes.
function lineShapes(add) {
  const names = ['A', 'B', 'C'];
  const delimOp = (style, name) => {
    if (style === 'plain') return { op: `<<${name}`, end: name, dash: false, empty: false };
    if (style === 'quoted') return { op: `<<'${name}'`, end: name, dash: false, empty: false };
    if (style === 'dash') return { op: `<<-${name}`, end: name, dash: true, empty: false };
    return { op: "<<''", end: '', dash: false, empty: true };
  };
  // closeAt: the heredoc whose delimiter line carries the closing backquote, or
  // -1 for the backquote on its own line after the delimiters.
  const build = (n, styles, closeAt, placement) => {
    const ds = styles.map((s, i) => delimOp(s, names[i]));
    const lines = [`x=\`cat ${ds.map((d) => d.op).join(' ')}`];
    let slotPlaced = false;
    for (let i = 0; i < n; i += 1) {
      const body = ds[i].empty ? 'ebody' : `body${i}`;
      lines.push(ds[i].dash ? TAB + body : body);
      let delimLine = ds[i].dash ? TAB + ds[i].end : ds[i].end;
      if (i === closeAt) {
        if (placement === 'sameline') { delimLine += '` %S%'; slotPlaced = true; } else delimLine += '`';
      }
      lines.push(delimLine);
    }
    if (closeAt === -1) {
      if (placement === 'sameline') { lines.push('` %S%'); slotPlaced = true; } else lines.push('`');
    }
    if (placement === 'after' && !slotPlaced) { lines.push('%S%'); slotPlaced = true; }
    // the first body line of the first heredoc: here-data inside the backquote
    if (placement === 'inside' && !slotPlaced) { lines.splice(1, 0, '%S%'); slotPlaced = true; }
    if (slotPlaced) add(`line-n${n}-${styles.join('')}-c${closeAt}-${placement}`, lines);
  };
  const styleChoices = ['plain', 'quoted', 'dash', 'empty'];
  for (let n = 1; n <= 3; n += 1) {
    let sets;
    if (n === 1) sets = styleChoices.map((s) => [s]);
    else if (n === 2) {
      sets = [['plain', 'plain'], ['quoted', 'quoted'], ['dash', 'plain'], ['empty', 'plain'],
        ['plain', 'empty'], ['empty', 'empty'], ['quoted', 'plain'], ['dash', 'empty']];
    } else sets = [['plain', 'plain', 'plain'], ['quoted', 'quoted', 'quoted'], ['dash', 'plain', 'empty']];
    for (const styles of sets) {
      for (const closeAt of [-1, ...styles.map((_, i) => i)]) {
        for (const placement of ['after', 'sameline', 'inside']) build(n, styles, closeAt, placement);
      }
    }
  }
}

// tail-: the round-4 guard validator's backquote container, stand-in after it.
function tailShapes(add) {
  const DELIMS = {
    plain: { open: (d) => `<<${d}`, line: (d) => d },
    quoted: { open: (d) => `<<'${d}'`, line: (d) => d },
    dash: { open: (d) => `<<-${d}`, line: (d) => `\t${d}` },
    empty: { open: () => "<<''", line: () => '' },
  };
  // The heredoc at `closeAt` (or none, -1) ends on a `DELIM)` line; the closing
  // backquote is glued to the last line.
  const build = (n, styles, closeAt) => {
    const ids = styles.map((s, i) => (s === 'empty' ? '' : String.fromCharCode(65 + i)));
    const lines = [`cat ${ids.map((d, i) => DELIMS[styles[i]].open(d)).join(' ')}`];
    for (let i = 0; i < n; i += 1) {
      lines.push(`body${i}`);
      const delimLine = DELIMS[styles[i]].line(ids[i]);
      lines.push(i === closeAt ? `${delimLine})` : delimLine);
    }
    add(`tail-n${n}-${styles.join('')}-c${closeAt}-after`, [`x=\`${lines.join('\n')}\``, '%S%']);
  };
  const styleChoices = ['plain', 'quoted', 'dash', 'empty'];
  for (const s of styleChoices) for (const closeAt of [-1, 0]) build(1, [s], closeAt);
  for (const s0 of styleChoices) {
    for (const s1 of ['plain', 'quoted', 'empty']) {
      for (const closeAt of [-1, 0, 1]) build(2, [s0, s1], closeAt);
    }
  }
  for (const s of ['plain', 'quoted']) for (const closeAt of [0, 1, 2]) build(3, [s, s, s], closeAt);
}

// other-: no heredoc; an unmatched quote or a comment inside the backquote.
function otherShapes(add) {
  const inner = {
    apos: "echo it's",
    dquote: 'echo "x',
    comment: 'echo #',
  };
  for (const [name, text] of Object.entries(inner)) {
    add(`other-${name}-nl`, [`x=\`${text}\``, '%S%']);
    add(`other-${name}-semi`, [`x=\`${text}\` ; %S%`]);
  }
}

function shapes() {
  const out = [];
  const seen = new Set();
  // Deduplicated within a family: the round-4 list repeats five round-4b
  // commands, and each family is kept whole.
  const add = (id, lines) => {
    const cmd = lines.join('\n').replace(/%S%/g, DEL);
    const key = JSON.stringify([id.split('-')[0], cmd]);
    if (seen.has(key)) return;
    seen.add(key);
    out.push({ id, probe: lines.join('\n').replace(/%S%/g, MK), cmd });
  };
  lineShapes(add);
  tailShapes(add);
  otherShapes(add);
  return out;
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
  process.stdout.write(`${JSON.stringify({
    purpose: 'R7-b backquote differential corpus (round 4c). An unquoted backquote substitution '
      + 'at the top level holds a heredoc whose body the closing backquote ends, an unmatched '
      + 'quote or a comment. runs53/runs32 were measured with bash 5.3 and bash 3.2 by `bash -n` '
      + 'plus a `;;` command-position differential on a never-called function wrapping the shape '
      + 'with a harmless stand-in (NEVER executed); regenerate with '
      + 'test/heredoc-backquote/generate.js and label.sh. A shape with runs53 OR runs32 true is '
      + 'one at least one bash runs the removal on, so the guard must DENY it.',
    generated: new Date().toISOString().slice(0, 10),
    shapes: rows.length,
    mustDeny,
    rows,
  }, null, 1)}\n`);
}

if (require.main === module) main();

module.exports = { shapes };
