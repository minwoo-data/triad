# Triad - Case Studies

> Evidence of what triad has caught in real-world deliberations.
> Factual. No marketing. Honest about limits.
>
> Each study anonymizes project identity while preserving deliberation
> mechanics, perspective outputs, and aggregate metrics.

> **⚠️ Evidence strength: n=2.** Two case studies on different target
> types (instruction file + multi-subsystem code sweep). The 3-lens
> design has now held up across (a) a small markdown document consumed
> by both humans and AI agents and (b) a parallel 4-session breadth sweep
> on ~42 source modules. Still not a benchmark - these are concrete
> evidence points, not statistical claims. The lens design appears to
> generalize beyond document deliberation to code-scope breadth review;
> a third case study on a different language/stack would strengthen
> further.

---

## Case Study 2 - Parallel 4-Session Breadth Sweep on a Python Backend

**Target kind**: A Python Flask backend, ~30+ source files partitioned
across 4 subsystems reviewed in parallel - (A) security/core (auth,
rate-limit, session-keyed batch state store, usage-tracking/alerting),
(B) OCR/receipts/matching pipeline, (C) statement/vendor/export/docs,
and (C2) scheduler. Triad was used as the BREADTH phase, feeding
candidates into a downstream mangchi depth phase.

**Environment**:
- Main agents: 4 × Claude Opus 4.7 (1M context), one per subsystem
  session running in isolated git worktrees
- Subagents per file: 3 × Claude Opus 4.7 general-purpose agents
  (parallel, independent, single-message spawn - cannot see each other's
  output)
- Mode: `code` mode, read-only (no `--apply`)
- Output: `RECOMMENDATIONS.md` per subsystem + per-module `round-1.md`
- Supervisor: 5th Claude session monitoring branch state + merge orchestration

### Headline numbers

| Metric | Value |
|---|---|
| Parallel main sessions | 4 (+ 1 supervisor) |
| Files reviewed (triad round-1) | 42+ modules |
| Per-session module count (avg) | 10-28 |
| Rounds consumed (per file) | 1 (breadth only; depth outsourced to mangchi) |
| Candidates escalated to mangchi depth | 7 |
| Real production bugs discovered via breadth-signal | 4 |
| `RECOMMENDATIONS.md` produced | 5 (subsystem synthesis files) |
| `PATTERNS-X.md` aggregate files (one per session) | 3 |
| Cross-session contamination events caught by supervisor | 2 |

### Bug categories landed

#### Unique to the LLM perspective

- **Unicode line-separator injection bypass** - the prompt-injection
  sanitizer matched anchored line-start regexes against `\n`. U+2028,
  U+2029, and U+0085 (NEL) are NOT `\n` for regex purposes but ARE
  treated as line boundaries by most downstream LLM tokenizers. An
  attacker embedding a role marker after `\u2028` would bypass the
  anchored detection while still being parsed as a new line by the
  consumer. Unique to LLM perspective because the class of bypass
  ("regex vs LLM tokenizer unicode normalization divergence") is only
  visible if you reason about LLM input-processing semantics.
  Escalated → mangchi → fix applied.

#### Unique to the Architect perspective

- **Rate-limiter scope not documented** - the rate-limit module counts
  in-process. In a future Gunicorn/multi-worker deployment, limits
  would silently weaken to per-worker. Architect flagged as a
  forward-compatibility gap; main agent accepted as a doc fix.
- **Alert dispatch: caller kwargs don't match signature** - a cross-file
  invariant issue. Architect spotted the mismatch by reading the helper
  signature and comparing to callsite kwargs. Escalated to mangchi,
  where it converged in the same round as a sibling cost-counter race.

#### Unique to the EndUser perspective

- **Enum extended in code, not in doc** - a submission-method enum
  gained new values in code without updating the enum's docstring or
  the top-level architecture notes. Future readers (AI or human) would
  consult the doc and build a wrong mental model.

#### Surfaced by multiple perspectives (convergence = strong signal)

- **Batch state store concurrency** - flagged by LLM ("mutation outside
  lock block") AND Architect ("lock exists but ordering invariant
  undocumented"). Two framings, same root cause. Immediately escalated
  to mangchi depth where it converged to two patches.

### Open questions that changed decisions

- **Scope of a parallel-session-discipline rule file** - under audit
  simultaneously with the codebase sweep. Triad asked: "is this rule
  binding on AI sessions, human contributors, or both?" User's answer
  ("both, authoritative either way") tightened several downstream scope
  decisions.
- **Which subsystem sweep runs first** - both security/core and
  OCR/receipts were candidates. EndUser perspective surfaced that a
  suspected kwargs-drift silent-failure in an alert path was already on
  the user's informal TODO, which set security/core as highest priority.

### What triad did NOT find (Case Study 2-specific)

- **Cross-session branch-hygiene failures.** During 4-way parallel
  execution, git worktree switches between sessions produced file
  contamination: one session's uncommitted docs pulled into a sibling
  session's commit via `git add` timing. Triad deliberates on files; it
  cannot detect git-operation-level races. A supervisor layer is
  required at parallel scale.
- **Runtime concurrency behavior.** Triad's read-only deliberation
  flagged the batch store's lock-ordering invariant as an open question;
  only mangchi's depth round (with applied patch + verification)
  confirmed it as an exploitable race.
- **Per-file performance.** No benchmarks run. Deliberation is
  correctness/clarity-focused, not profile-driven.

### What surprised us

- **Three-perspective independence scaled to parallel sessions.** With
  4 concurrent sessions each spawning 3 subagents per file, perspective
  independence held: no cross-session contamination of subagent
  reasoning. This was expected from single-message-spawn design, but
  N=42+ was the first time we validated it at this scale.
- **Multi-perspective convergence predicted mangchi success.** Of the
  7 candidates triad escalated to mangchi, the 2 that became src/
  patches had been flagged by all three perspectives. The 5 that stayed
  at "no patch needed" in mangchi had been flagged by 1 or 2. Accept
  rate correlated with perspective-convergence count - a useful signal
  for adopters deciding escalation priority.
- **`PATTERNS-X.md` synthesis layer surfaced cross-file invariants.**
  Triad's per-file round-1 focuses on single-file correctness; the
  PATTERNS synthesis produced at the end of each session identified 3
  recurring cross-file issues (hardcoded drift-prone constants,
  inconsistent `[WARN]` logger prefixes, enum extension without doc).
  Session-level artifact, not a triad per-file feature.
- **Operational overhead was the biggest finding.** The supervisor
  session caught 2 contamination events before propagation to main.
  Without it, branch history would have been corrupted. For adopters
  running triad at single-session scale, this isn't a concern; at
  4-session parallel scale, budget a supervisor.

### Reproducibility

Per-session artifacts preserved:
- `docs/refinement/session-burn/<session-id>/<module>/round-1.md` -
  per-file triad YAML outputs (Architect + LLM + EndUser)
- `docs/refinement/session-burn/<session-id>/PATTERNS-X.md` - aggregate synthesis
- `docs/refinement/session-burn/<session-id>/triad-code-findings.md`,
  `…/triad-docs-findings.md` - categorized finding lists

### Key takeaways for Case Study 2 adopters

- **Triad scales to parallel subsystem sweeps** but operational discipline
  at the git-worktree level does NOT come for free. Budget a supervisor
  session if running 3+ concurrent triad sweeps.
- **Triad is upstream, not terminal.** On a codebase this size, the
  value chain is: triad breadth → mangchi depth → src/ patch. Running
  triad alone produces RECOMMENDATIONS + round-1.md artifacts, not code
  changes.
- **Multi-perspective convergence is a useful prioritization signal.**
  If you escalate candidates to a downstream tool, prioritize those
  flagged by all three perspectives - empirical accept rate scales with
  perspective count.
- **PATTERNS synthesis is session-level.** Per-file triad is the
  primitive; aggregate pattern synthesis requires a main-agent
  post-processing pass, not triad itself.

---

## Case Study 1 - Project Instruction File Deliberation

**Target kind**: A Claude Code project's `CLAUDE.md` file - the
instruction document that bootstraps AI agents working on a codebase.
~75 lines; imports five rules files via `@rules/*.md` syntax; documents
commands, rules, and reference skills.

**Environment**:
- Main agent: Claude Opus 4.6 (1M context)
- Subagents: 3 × Claude Opus 4.6 general-purpose agents (parallel,
  independent - spawned in a single message so they cannot see each
  other's output)
- Mode: read-only dry-run (no `--apply` passed; skill mechanics
  validation was the primary goal)
- Rounds consumed: 2 of 5

### Headline numbers

| Metric | Value |
|---|---|
| Rounds consumed | 2 / 5 |
| Total issues raised (across R1 + R2) | 14 (R1) + 5 (R2) |
| Issues **accepted** (after audience clarification) | 7 of 14 |
| Issues **rejected or scoped-out** | 7 of 14 |
| Distinct bug classes surfaced by all 3 perspectives | 2 (drift-prone numbers, rules ownership) |
| Unique-to-one-perspective findings | 6 |
| Blocking open questions escalated to user | 3 |
| Cross-perspective conflicts | 0 |
| High-severity cap respected | Yes, by all three perspectives in both rounds |

### Bug categories landed

#### Unique to the LLM perspective (would likely be missed by a general reviewer)

- **Role enumeration absent** - the document referenced a "4-tier RBAC"
  system without naming the four tier values. An LLM asked to set or
  reason about roles would hallucinate names. Specific to how LLMs
  consume instruction documents; a human reader wouldn't care.
- **Drift-prone hardcoded counts** - the document mentioned specific
  quantitative facts (table counts, schema versions, test counts) that
  drift from code. LLMs cite such numbers authoritatively without
  verification, producing confidently-wrong statements.
- **Ambiguous antecedent "the client"** - a CI note said "tests must
  mock the client" without specifying which client (HTTP? SDK? LLM
  provider? SMTP?). LLMs writing new tests would mock the wrong layer.
- **Config key paths asserted without file anchors** - "port is read
  from config.json (default 5000)" doesn't specify the key path. LLM
  must guess (`server.port` vs `app.port` vs `port`).

#### Unique to the Architect perspective

- **No ownership boundaries on imported rule files** - five rules were
  loaded unconditionally with no documented scope contract. When a
  sixth rule is added, contributors have no boundary map and rules will
  overlap or contradict.
- **Platform assumption not stated** - Windows-specific scripts
  (`.bat`, PowerShell) mixed freely with cross-platform commands. First
  macOS contributor would either duplicate every script or silently
  break.
- **CLI overloading the web entry point** - `python app.py --add-user`
  overloads the web server entry with admin CLI subcommands. Dual-purpose
  entry point will force awkward workarounds for containerized deployment
  + CLI scripting.

#### Unique to the EndUser perspective

- **No purpose statement** - the document answered *what* but never
  *why*. A novice reader couldn't decide if the project was relevant to
  them. Required user clarification: was this file meant for humans, AI
  agents, or both? (Answer: AI-only - which reduced the accept count on
  other EndUser findings.)
- **Jargon density in opening paragraph** - one sentence dropped seven
  specialized terms (RBAC, SMTP, AJAX, prompt injection, confidence
  routing, ...). Non-expert first-time readers lose the thread before
  reaching the command section.
- **No quick-start path** - 25+ commands listed with no ordering. A
  first-time reader had no way to know which to run first.

#### Surfaced by multiple perspectives (convergence = strong signal)

- **Drift-prone hardcoded numbers** - flagged by LLM ("confidently wrong
  citations") AND Architect ("single source of truth issue"). Different
  framing, same root cause. Main agent accepted immediately; convergence
  across perspectives is a strong accept signal.
- **Rules/Skills ownership** - flagged by Architect (enforcement gap)
  AND EndUser (readers don't know what to skim). Again different framing,
  converged fix direction.

### Open questions that changed decisions

**Q1 (from EndUser)**: *"Is this file intended for humans, AI agents,
or both?"* - the user answered "AI-only, no separate README exists."
This single answer **reduced the EndUser-surfaced issue set from 6
findings down to 2**, because 4 of them (purpose statement, jargon,
quick-start, example) only applied to human onboarding. The perspective
didn't disappear - its scope sharpened.

**Q2 (from LLM)**: actual role literal values. Main agent resolved
by grepping the source code, then accepted the LLM's enumeration
recommendation.

**Q3 (from LLM)**: actual config.json key path. Same resolution.

### What triad did NOT find

- **Anything about code correctness** - triad deliberates on files, not
  runtime behavior. A buggy function on which the document was correct
  would pass triad unchallenged.
- **Security vulnerabilities in the described system** - the document
  mentioned "prompt injection defense" as a feature, but triad didn't
  audit whether the defense was implemented correctly; it only checked
  whether the description was clear to readers.
- **Performance characteristics** - not in scope.

### What surprised us

- **Round 2 caught the main agent's own mistakes.** When the main agent
  applied round-1 fixes to a draft, round 2 reviewed the draft and
  flagged that one "fix" actually introduced a factually-wrong config
  path (the main agent had asserted a key path without verifying against
  `config.json`). Triad functions as a second filter on the main
  agent's synthesis, not just on the original document.
- **Perspective independence worked.** The three subagents, spawned in
  parallel with no visibility into each other's output, produced zero
  mutually-contradictory recommendations. Same-symptom framings were
  complementary, not conflicting.
- **One perspective's open question was load-bearing.** The EndUser
  perspective's Q1 (audience clarification) changed the accept/reject
  decision on seven separate issues. Escalating a question instead of
  assuming an answer is a feature, not a weakness.

### Reproducibility

Per-round artifacts preserved under `docs/discussion/<slug>/`:
- `source.md` - snapshot of the input at round-1 start
- `state.json` - round progression, verdicts, open questions
- `round-N.md` - each subagent's YAML output + main synthesis +
  decision log
- `CONSENSUS.md` - final decisions + preserved dissent + timeline

A reader can inspect each subagent's exact YAML to verify that
perspective independence held and that severity caps were respected.

### Key takeaways for adopters

- **Strongest value on documents that are read by both humans and AI
  agents.** Project instruction files, onboarding docs, API guides.
  The three perspectives genuinely ask different questions.
- **Use the `--apply=original` flag only after one read-only round.**
  The round-1 critique often reveals that the document's target
  audience (or scope, or intent) wasn't what you assumed. Applying
  changes before that clarification wastes rounds.
- **Escalate open questions; don't invent answers.** Triad's strength
  is that subagents flag unknowns instead of guessing. Respect that
  - go find the actual answer before round 2.
- **Code-mode produces `RECOMMENDATIONS.md`, not patches.** If you
  want code to change, a separate code-modification tool handles the
  implementation. Triad stops at "here's what should change and why."

---

## Template for future case studies

Append new case studies to the TOP of this file. Keep the oldest at
the bottom for release-over-release comparison.

```markdown
## Case Study N - <anonymized target kind> (<date>)

**Target kind**: <generic description>
**Environment**: <agents, model, config>

### Headline numbers
| Metric | Value |
|---|---|

### Bug categories landed
- **Unique to <perspective>**: <description>
- **Surfaced by multiple perspectives**: <description>

### Open questions that changed decisions
- <question> → <resolution>

### What triad did NOT find
- <honest limitation>

### Reproducibility
- Artifacts preserved at <path>
```
