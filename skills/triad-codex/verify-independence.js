#!/usr/bin/env node
// triad-codex — Layer 2 self-check
//
// Purpose: prove this skill is self-contained before runtime or distribution.
// Fails fast if any file inside this skill references another plugin/skill,
// declares a `_shared/` dependency, or is missing a required internal file.
//
// Usage:
//   node verify-independence.js           # verify installation
//   node verify-independence.js --strict  # also run optional checks
//
// Exit 0 = pass, 2 = violation.
//
// This file is the canonical template. When creating sibling skills
// (prism-codex, prism-all, triad-all), copy this file, update SELF_NAME,
// REQUIRED_FILES, and PREREQUISITES. Do not centralize.

'use strict';

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

// ---- per-skill config ------------------------------------------------------

const SELF_NAME = 'triad-codex';

const REQUIRED_FILES = [
  'SKILL.md',
  'verify-independence.js',
  'agents/llm-perspective.md',
  'agents/architect-perspective.md',
  'agents/enduser-perspective.md',
  'templates/round.md',
  'templates/consensus.md',
];

// Prerequisites — each entry is a CLI existence check. Missing => warn (not fail).
// Fatal prerequisites should be enforced inside SKILL.md at invocation time, not here.
const PREREQUISITES = [
  { cmd: 'codex --version', label: 'Codex CLI', fatal: true },
];

// ---- helpers ---------------------------------------------------------------

const SELF_DIR = __dirname;

function fail(msg) {
  process.stderr.write(`[verify-independence:${SELF_NAME}] FAIL  ${msg}\n`);
  process.exit(2);
}

function warn(msg) {
  process.stderr.write(`[verify-independence:${SELF_NAME}] WARN  ${msg}\n`);
}

function ok(msg) {
  process.stdout.write(`[verify-independence:${SELF_NAME}] OK    ${msg}\n`);
}

function walk(dir, acc = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, acc);
    else if (entry.isFile()) acc.push(full);
  }
  return acc;
}

function normalize(p) { return p.replace(/\\/g, '/'); }

// A reference is a violation only if it points at a plugin/skill OTHER than
// SELF_NAME. Mentioning SELF_NAME in paths is fine (self-reference).
function scanForCrossRefs(filePath, content) {
  const violations = [];

  if (/\/(plugins\/marketplaces\/[^/]+\/plugins|\.claude\/skills)\/_shared(\/|$)/.test(content)) {
    violations.push('references a `_shared/` directory');
  }

  const absRegex = /(?:~|\/c)?\/[^\s`"')\]]*?\.claude\/(?:plugins\/marketplaces\/[^/]+\/plugins|skills)\/([A-Za-z0-9._-]+)/g;
  let m;
  while ((m = absRegex.exec(content)) !== null) {
    const refName = m[1];
    if (refName !== SELF_NAME) {
      violations.push(`references another plugin/skill "${refName}" at absolute path: ${m[0]}`);
    }
  }

  const relRegex = /\.\.\/[^\s`"')\]]*(?:plugins|skills)\/([A-Za-z0-9._-]+)\//g;
  while ((m = relRegex.exec(content)) !== null) {
    const refName = m[1];
    if (refName !== SELF_NAME) {
      violations.push(`relative path crosses into sibling plugin/skill "${refName}": ${m[0]}`);
    }
  }

  return violations;
}

// ---- checks ----------------------------------------------------------------

function checkRequiredFiles() {
  for (const rel of REQUIRED_FILES) {
    const full = path.join(SELF_DIR, rel);
    if (!fs.existsSync(full)) fail(`missing required file: ${rel}`);
  }
  ok(`required files present (${REQUIRED_FILES.length})`);
}

function checkNoCrossRefs() {
  const textExts = new Set(['.md', '.js', '.sh', '.json', '.yml', '.yaml', '.txt', '.py']);
  const files = walk(SELF_DIR).filter(f => textExts.has(path.extname(f)));
  const violationsByFile = {};
  for (const f of files) {
    const content = fs.readFileSync(f, 'utf8');
    const v = scanForCrossRefs(f, content);
    if (v.length > 0) violationsByFile[normalize(path.relative(SELF_DIR, f))] = v;
  }
  const offenders = Object.keys(violationsByFile);
  if (offenders.length > 0) {
    for (const f of offenders) {
      for (const msg of violationsByFile[f]) {
        process.stderr.write(`[verify-independence:${SELF_NAME}] FAIL  ${f} — ${msg}\n`);
      }
    }
    process.exit(2);
  }
  ok(`no cross-plugin references in ${files.length} scanned files`);
}

function checkPrerequisites() {
  for (const p of PREREQUISITES) {
    try {
      execSync(p.cmd, { stdio: 'ignore' });
      ok(`prerequisite present: ${p.label}`);
    } catch (e) {
      if (p.fatal) fail(`prerequisite missing: ${p.label} (\`${p.cmd}\` failed)`);
      else warn(`prerequisite missing: ${p.label} (\`${p.cmd}\` failed) — optional`);
    }
  }
}

// ---- main ------------------------------------------------------------------

function main() {
  const strict = process.argv.includes('--strict');
  checkRequiredFiles();
  checkNoCrossRefs();
  if (strict) checkPrerequisites();
  process.stdout.write(`[verify-independence:${SELF_NAME}] PASS — skill is self-contained\n`);
  process.exit(0);
}

main();
