'use strict';
// Differential-oracle corpus generator for the R7-a "later heredoc body" shapes
// (test-hooks-heredoc-later-body-corpus.json). Nothing here executes a shape.
//
// A substitution ($( ), "$( )", <( ), or a nested $( $( ) )) opens two or three
// heredocs on one line; an EARLIER one is closed by `DELIM)`. bash 3.2 closes
// the substitution at that `)` and reads the following lines as commands; bash
// 5.3 reads the remaining heredoc bodies as here-data and runs what follows
// them. When a later body holds an unmatched quote, a heredoc operator or a
// backquote, the 3.2 reading can hide the removal after the construct while the
// 5.3 reading runs it (KNOWN-RESIDUALS.md R7-a, closed in round 4b: the gate
// scans both readings and refuses a removal either one runs).
//
// Each shape is rendered twice from one stand-in slot:
//   - a PARSE PROBE: slot = the bare word RUNCMD, wrapped in a never-called
//     `f() { ... }`; label.sh feeds it to `bash -n` only, under two bashes.
//   - the corpus COMMAND: slot = `rm -rf /etc`, handed to the hook's evaluate()
//     only (test-hooks.js), never to a shell.
// So no shell ever sees `rm`, and the hook never runs anything.
//
//   node test/heredoc-later-body/generate.js probes <dir>      write <dir>/<id>.sh
//   test/heredoc-later-body/label.sh <dir> > labels.tsv        label (parse only)
//   node test/heredoc-later-body/generate.js corpus <labels>   print corpus JSON
//
// test-hooks.js re-derives shapes() and checks that the corpus rows are exactly
// this list, in order, so the checked-in labels belong to it.
const fs = require('fs');
const path = require('path');

const MK = 'RUNCMD';
const DEL = 'rm -rf /etc';
const names = ['A', 'B', 'C'];

// container: how the substitution opens and closes.
const containers = {
  dollar: { open: 'x=$(cat ', close: ')' },
  dq: { open: 'x="$(cat ', close: ')"' },
  procsub: { open: 'diff <(cat ', close: ') z.txt' },
  nested: { open: 'x=$(echo $(cat ', close: ')' },
};
// A later heredoc body whose two readings differ (unmatched quote, a heredoc
// operator, a backquote), plus an inert control.
const laterBodies = {
  apos: "it's here",
  dquote: 'say "hi',
  heredocop: 'see <<EOF',
  backtick: 'tick `echo',
  plain: 'plain body',
};
const delimStyle = {
  plain: (n) => ({ op: `<<${n}`, line: n }),
  quoted: (n) => ({ op: `<<'${n}'`, line: n }),
};

function shapes() {
  const out = [];
  const seen = new Set();
  const add = (id, lines) => {
    const cmd = lines.join('\n').replace(/%S%/g, DEL);
    if (seen.has(cmd)) return;
    seen.add(cmd);
    out.push({ id, probe: lines.join('\n').replace(/%S%/g, MK), cmd });
  };
  for (const [cname, c] of Object.entries(containers)) {
    for (const n of [2, 3]) {
      for (const style of ['plain', 'quoted']) {
        const ds = names.slice(0, n).map((nm) => delimStyle[style](nm));
        const ops = ds.map((d) => d.op).join(' ');
        for (let closeAt = 0; closeAt < n - 1; closeAt += 1) {
          for (const [bname, body] of Object.entries(laterBodies)) {
            const lines = [`${c.open}${ops}`];
            for (let i = 0; i < n; i += 1) {
              lines.push(i === closeAt + 1 ? body : `b${i}`);
              lines.push(i === closeAt ? ds[i].line + c.close : ds[i].line);
            }
            if (cname === 'nested') lines.push(')'); // the outer $( of `echo $(`
            lines.push('%S%');
            add(`a-${cname}-n${n}-${style}-c${closeAt}-${bname}`, lines);
          }
        }
      }
    }
  }
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
    purpose: 'R7-a later-heredoc-body differential corpus (round 4b, 2026-10-17). A '
      + 'substitution opens 2-3 heredocs on one line; an earlier one closes by `DELIM)`. '
      + 'runs53/runs32 were measured with bash 5.3.20 and bash 3.2.57 by `bash -n` plus a '
      + '`;;` command-position differential on a never-called function wrapping the shape '
      + 'with a harmless stand-in (NEVER executed); regenerate with '
      + 'test/heredoc-later-body/generate.js and label.sh. A shape with runs53 OR runs32 '
      + 'true is one at least one bash runs the removal on, so the guard must DENY it. The '
      + 'gate reads both bash readings and unions their targets (KNOWN-RESIDUALS.md R7-a).',
    generated: new Date().toISOString().slice(0, 10),
    shapes: rows.length,
    mustDeny,
    rows,
  }, null, 1)}\n`);
}

if (require.main === module) main();

module.exports = { shapes };
