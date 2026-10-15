#!/usr/bin/env node
// triad - entry-contract check for the /triad skill.
//
// Since 0.3.1 there is no commands/triad.md: /triad runs this skill directly, so the
// argument table, the no-argument menu and the code refusal live only in SKILL.md.
// This fails when any of them is lost, so a later edit cannot silently drop them.
// Self-contained, no deps. Exit 0 = ok, 2 = contract broken.
// Usage: node verify-entry.js [path/to/SKILL.md]

'use strict';

const fs = require('fs');
const path = require('path');

const file = process.argv[2] || path.join(__dirname, 'SKILL.md');
const errors = [];
const need = (cond, msg) => { if (!cond) errors.push(msg); };

let text = '';
try { text = fs.readFileSync(file, 'utf8').replace(/\r\n/g, '\n'); }
catch (e) { process.stderr.write(`[verify-entry:triad] FAIL  cannot read ${file}: ${e.message}\n`); process.exit(2); }

function block(name) {
  const m = text.match(new RegExp(`<!-- ${name} -->\\n([\\s\\S]*?)\\n<!-- /${name} -->`));
  return m ? m[1] : null;
}

// 1. Frontmatter: the skill is what /triad invokes.
const fm = (text.match(/^---\n([\s\S]*?)\n---\n/) || [])[1] || '';
need(/^name: triad$/m.test(fm), 'frontmatter name is not "triad"');
need(/^user-invocable: true$/m.test(fm), 'frontmatter lacks "user-invocable: true" (/triad would not reach the skill)');
need(/^argument-hint: .*--continue <slug>.*--stop <slug>/m.test(fm), 'frontmatter argument-hint lacks --continue/--stop');

// 2. Argument table: every route the old command file handled.
const table = block('args-table');
need(table !== null, 'missing <!-- args-table --> block');
if (table !== null) {
  const rows = [
    ['`<file>` (문서)', 'new session on a document'],
    ['`<file> --apply`', '--apply'],
    ['`<file> --apply=original`', '--apply=original'],
    ['`<file>` (코드)', 'code refusal route'],
    ['`--continue <slug>`', '--continue'],
    ['`--stop <slug>`', '--stop'],
    ['(인자 없음)', 'no-argument route'],
  ];
  for (const [cell, what] of rows) {
    need(table.split('\n').some((l) => l.startsWith(`| ${cell} |`)), `argument table lacks the ${what} row (${cell})`);
  }
}
need(/ARGUMENTS: /.test(text), 'SKILL.md no longer says how invocation arguments arrive (ARGUMENTS: ...)');

// 3. No-argument menu: the AskUserQuestion JSON, verbatim and parseable.
const menu = block('no-arg-menu');
need(menu !== null, 'missing <!-- no-arg-menu --> block');
if (menu !== null) {
  const m = menu.match(/```json\n([\s\S]*?)\n```/);
  need(!!m, 'no-arg menu is not a ```json block');
  if (m) {
    let q = null;
    try { q = JSON.parse(m[1]).questions; } catch (e) { errors.push(`no-arg menu JSON does not parse: ${e.message}`); }
    if (q) {
      const labels = (q[0] && q[0].options || []).map((o) => o.label).join(' / ');
      need(Array.isArray(q) && q.length === 1, 'no-arg menu must hold exactly one question');
      need(labels === 'Markdown document / Continue session / Stop session', `no-arg menu options changed: ${labels}`);
    }
  }
}
need(/AskUserQuestion/.test(text), 'SKILL.md no longer names the AskUserQuestion tool for the no-argument route');

// 4. Rules the command file used to carry.
need(text.includes('triad는 문서 전용입니다.'), 'code refusal line is missing');
need(/30줄/.test(text), 'short-document warning (about 30 lines) is missing');
need(/\[fallback: main-local-pass\]/.test(text), 'main-local-pass fallback tag is missing');

if (errors.length) {
  for (const e of errors) process.stderr.write(`[verify-entry:triad] FAIL  ${e}\n`);
  process.exit(2);
}
process.stdout.write('[verify-entry:triad] OK    entry contract intact (args table, no-arg menu, refusal, fallback, short-doc warning)\n');
