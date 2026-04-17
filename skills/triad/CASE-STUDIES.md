# Triad — Case Studies

> Evidence of what triad has caught in real-world deliberations.
> Factual. No marketing. Honest about limits.
>
> Each study anonymizes project identity while preserving deliberation
> mechanics, perspective outputs, and aggregate metrics.

> **⚠️ Evidence strength: n=1 so far.** One case study is weak positive
> evidence for the 3-lens design — it shows the lenses *can* produce
> complementary findings, not that they *will* under all conditions.
> "0 cross-perspective conflicts" in Case Study 1 means the lenses
> agreed on what they disagreed about — **not that they are orthogonal**.
> Treat this file as a smoke test, not a benchmark. Second case study
> on a different project type is needed before claiming the lens design
> generalizes.

---

## Case Study 1 — Project Instruction File Deliberation

**Target kind**: A Claude Code project's `CLAUDE.md` file — the
instruction document that bootstraps AI agents working on a codebase.
~75 lines; imports five rules files via `@rules/*.md` syntax; documents
commands, rules, and reference skills.

**Environment**:
- Main agent: Claude Opus 4.6 (1M context)
- Subagents: 3 × Claude Opus 4.6 general-purpose agents (parallel,
  independent — spawned in a single message so they cannot see each
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

- **Role enumeration absent** — the document referenced a "4-tier RBAC"
  system without naming the four tier values. An LLM asked to set or
  reason about roles would hallucinate names. Specific to how LLMs
  consume instruction documents; a human reader wouldn't care.
- **Drift-prone hardcoded counts** — the document mentioned specific
  quantitative facts (table counts, schema versions, test counts) that
  drift from code. LLMs cite such numbers authoritatively without
  verification, producing confidently-wrong statements.
- **Ambiguous antecedent "the client"** — a CI note said "tests must
  mock the client" without specifying which client (HTTP? SDK? LLM
  provider? SMTP?). LLMs writing new tests would mock the wrong layer.
- **Config key paths asserted without file anchors** — "port is read
  from config.json (default 5000)" doesn't specify the key path. LLM
  must guess (`server.port` vs `app.port` vs `port`).

#### Unique to the Architect perspective

- **No ownership boundaries on imported rule files** — five rules were
  loaded unconditionally with no documented scope contract. When a
  sixth rule is added, contributors have no boundary map and rules will
  overlap or contradict.
- **Platform assumption not stated** — Windows-specific scripts
  (`.bat`, PowerShell) mixed freely with cross-platform commands. First
  macOS contributor would either duplicate every script or silently
  break.
- **CLI overloading the web entry point** — `python app.py --add-user`
  overloads the web server entry with admin CLI subcommands. Dual-purpose
  entry point will force awkward workarounds for containerized deployment
  + CLI scripting.

#### Unique to the EndUser perspective

- **No purpose statement** — the document answered *what* but never
  *why*. A novice reader couldn't decide if the project was relevant to
  them. Required user clarification: was this file meant for humans, AI
  agents, or both? (Answer: AI-only — which reduced the accept count on
  other EndUser findings.)
- **Jargon density in opening paragraph** — one sentence dropped seven
  specialized terms (RBAC, SMTP, AJAX, prompt injection, confidence
  routing, ...). Non-expert first-time readers lose the thread before
  reaching the command section.
- **No quick-start path** — 25+ commands listed with no ordering. A
  first-time reader had no way to know which to run first.

#### Surfaced by multiple perspectives (convergence = strong signal)

- **Drift-prone hardcoded numbers** — flagged by LLM ("confidently wrong
  citations") AND Architect ("single source of truth issue"). Different
  framing, same root cause. Main agent accepted immediately; convergence
  across perspectives is a strong accept signal.
- **Rules/Skills ownership** — flagged by Architect (enforcement gap)
  AND EndUser (readers don't know what to skim). Again different framing,
  converged fix direction.

### Open questions that changed decisions

**Q1 (from EndUser)**: *"Is this file intended for humans, AI agents,
or both?"* — the user answered "AI-only, no separate README exists."
This single answer **reduced the EndUser-surfaced issue set from 6
findings down to 2**, because 4 of them (purpose statement, jargon,
quick-start, example) only applied to human onboarding. The perspective
didn't disappear — its scope sharpened.

**Q2 (from LLM)**: actual role literal values. Main agent resolved
by grepping the source code, then accepted the LLM's enumeration
recommendation.

**Q3 (from LLM)**: actual config.json key path. Same resolution.

### What triad did NOT find

- **Anything about code correctness** — triad deliberates on files, not
  runtime behavior. A buggy function on which the document was correct
  would pass triad unchallenged.
- **Security vulnerabilities in the described system** — the document
  mentioned "prompt injection defense" as a feature, but triad didn't
  audit whether the defense was implemented correctly; it only checked
  whether the description was clear to readers.
- **Performance characteristics** — not in scope.

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
- `source.md` — snapshot of the input at round-1 start
- `state.json` — round progression, verdicts, open questions
- `round-N.md` — each subagent's YAML output + main synthesis +
  decision log
- `CONSENSUS.md` — final decisions + preserved dissent + timeline

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
  — go find the actual answer before round 2.
- **Code-mode produces `RECOMMENDATIONS.md`, not patches.** If you
  want code to change, a separate code-modification tool handles the
  implementation. Triad stops at "here's what should change and why."

---

## Template for future case studies

Append new case studies to the TOP of this file. Keep the oldest at
the bottom for release-over-release comparison.

```markdown
## Case Study N — <anonymized target kind> (<date>)

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
