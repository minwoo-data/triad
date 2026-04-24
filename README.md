# triad

> Language: **English** · [한국어](README.ko.md)

**Run a single file through three fixed-perspective reviewers until they all agree.**

Docs get shipped with "looks fine" approval, then three weeks later they bite back: an AI agent can't parse them, the architecture aged badly, or a new hire gives up at minute six. triad runs three independent lenses on one file in parallel and keeps deliberating until all three pass.

```
/triad <file>                  -> read-only consensus (CONSENSUS.md)
/triad <file> --apply          -> md: generate updated.md (original untouched)
/triad <file> --apply=original -> md: also Edit the original
/triad <code.py>               -> code: always read-only, RECOMMENDATIONS.md
```

Three subagents, three biases (LLM clarity / architectural longevity / end-user comprehension), one orchestrator. Round N only carries forward what round N-1 didn't resolve. Hard cap at round 5. Code is never modified — ever.

---

## 30-second demo

**Without triad:**

You write a design doc, one reviewer says "looks fine", you commit it. Three weeks later: (a) an AI agent reading that doc gets confused and ships a broken feature, (b) the architecture choice painted you into a corner, (c) a new hire takes 15 minutes to figure out what the doc is even saying.

**With triad:**

`/triad docs/features/billing.md`. Three agents read the doc through fixed lenses in parallel — LLM clarity, architectural longevity, end-user comprehension. They keep passing the doc back until all three agree, or round 5 caps out. The consensus is written to `updated.md` without touching the original.

## Who should use this

- **Project instruction docs** (`CLAUDE.md`, agent prompts, onboarding) — read by AI too, the LLM lens is especially valuable
- **ADRs** (Architecture Decision Records) — verify the choice from three angles before committing
- **Public-facing docs** (README, getting-started, API) — the end-user lens catches things readers silently give up on
- **Code files you want thoroughly reviewed read-only** — triad never edits code, only produces `RECOMMENDATIONS.md`
- **Before a PR** — triangulate the justification for the change

## Sibling tools (same marketplace)

- **[ddaro](https://github.com/minwoo-data/ddaro)** — worktree-based parallel Claude Code sessions with safe merge.
- **[prism](https://github.com/minwoo-data/prism)** — 5-angle parallel code review with singleton verification (wider, one-shot).
- **[mangchi](https://github.com/minwoo-data/mangchi)** — iterative code refinement loop with Claude + Codex cross-review.

---

## Quick Start

### 1. Add the haroom_plugins marketplace (one time)

```
/plugin marketplace add https://github.com/minwoo-data/haroom_plugins.git
```

`triad` is distributed through the **haroom_plugins** aggregator along with the other haroom plugins (ddaro, prism, mangchi).

### 2. Install

```
/plugin install triad
```

### 3. Use

```
/triad docs/features/billing.md          # three-lens review, read-only
/triad docs/features/billing.md --apply  # also produce updated.md
/triad src/routes/auth.py                # code mode, read-only
```

Restart Claude Code after install/update.

---

## Variants shipped in this plugin

Installing `triad` gives you three independent skills that share the 3-lens framework but differ in who judges:

| Skill | Engine | When to use |
|---|---|---|
| `/triad` | **Claude only** — 3 subagents in parallel | Default. Fastest wall-time, no external CLI needed. |
| `/triad-codex` | **Codex CLI only** — 3 sequential calls, gpt-5.5 | Save Claude tokens, or get a different-model opinion. Requires `codex-cli >= 0.125.0`. |
| `/triad-all` | **Claude + Codex in parallel** — 6 calls | Highest confidence. Same-lens cross-model agreement produces a Tier 1 finding class no single-engine variant can isolate. Requires both. |

All three live inside one plugin install. Pick one per run. Codex CLI prerequisite details: [`docs/codex-5.4-to-5.5.md`](docs/codex-5.4-to-5.5.md) (the "model does not exist" error on older CLIs is a version issue, not an account issue).

---

## The three lenses

| Lens | Fixed question |
|---|---|
| **LLM Clarity** | Can a future AI agent read this and act correctly without hallucinating? |
| **Architect** | Is this design maintainable a year from now? Are responsibility boundaries clear? |
| **EndUser** | Can someone seeing this for the first time answer *what*, *why*, and *how* within five minutes? |

Each subagent returns a structured YAML verdict with a cap of **max 3 high-severity issues per round** to prevent rambling critique.

## How it works

```
┌─ Main Agent (Claude) ─────────────────────────┐
│  Parse target → spawn 3 subagents in parallel │
│  Synthesize → apply (md only) → next round    │
└───────────────────────────────────────────────┘
          ↓ (parallel, independent)
   ┌──────────────┬──────────────┬──────────────┐
   ↓              ↓              ↓
┌──────────┐  ┌──────────┐  ┌──────────┐
│   LLM    │  │Architect │  │ EndUser  │
│  lens    │  │  lens    │  │  lens    │
└──────────┘  └──────────┘  └──────────┘
```

Each agent runs in a forked context so the main conversation stays clean. Agents cannot see each other's output — prevents groupthink.

## Features

- **Round-delta** — round N only sees unresolved issues from round N-1. Resolved items never get re-litigated, so consensus files stay short.
- **Input-aware write permission** — markdown can be modified (explicit `--apply` / `--apply=original`); code files are read-only regardless of flags. Hard invariant.
- **Fork isolation** — subagents can't see each other's answers, so agreement is independent signal, not echo.
- **Fallback with loud tagging** — if a subagent fails to spawn or crashes, the main agent falls back to a local pass and tags the round `[fallback: main-local-pass]`. No silent quality drop.
- **Natural termination** — three PASS verdicts **AND** zero open questions. Any slip sends you to the next round. Hard cap at round 5.

---

## Input types and write permission

| Input | Default | `--apply` | `--apply=original` |
|---|---|---|---|
| `.md` | Original untouched, no changes | `updated.md` created/updated, original untouched | `updated.md` + original Edit |
| `.py` / `.js` / code | Original untouched, `RECOMMENDATIONS.md` produced | `--apply` ignored with warning | `--apply=original` ignored with warning |

**Code files are never modified.** If you want to mutate code, that's a different tool's job (try `/mangchi`).

## Termination conditions

Any of:

1. All three perspectives return `verdict: PASS` **AND** the main agent's open-questions list is empty
2. Round cap — 5 rounds by default
3. User `/triad --stop <slug>`

## Output files

```
docs/discussion/<slug>/
├── source.md              # snapshot of input at round 1 start
├── state.json             # round, status, decisions
├── round-1.md             # 3 perspectives + main synthesis + diff (if applied)
├── round-2.md             # only carries over unresolved issues
├── ...
├── CONSENSUS.md           # final decisions + preserved dissent
└── updated.md             # only if --apply was used (md inputs)
```

For code inputs, the path is `docs/discussion/code/<slug>/` and the final artifact is `RECOMMENDATIONS.md` in a format compatible with downstream code-generation tools. `/triad-codex` and `/triad-all` write into `docs/discussion/codex/<slug>/` and `docs/discussion/all/<slug>/` respectively.

---

## Example session

```
/triad docs/features/billing.md
# → Spawns 3 subagents in parallel (LLM, Architect, EndUser lenses)
# → Round 1: 2 agents REVISE, 1 BLOCK. 5 open issues carried forward.

/triad --continue billing
# → Round 2: input = previous issues + original doc only. Resolved items dropped.
# → Round 2: 1 REVISE, 2 PASS. 1 issue left.

/triad --continue billing --apply
# → Round 3: all PASS, open_questions = []. Consensus reached.
# → updated.md written with accepted changes, original billing.md untouched.

cat docs/discussion/billing/CONSENSUS.md
# → Final decisions with round attribution + preserved dissent

cat docs/discussion/billing/updated.md
# → Applied version, ready to move to docs/features/billing.md when you're happy
```

### Code review mode (always read-only)

```
/triad src/routes/auth.py
# → docs/discussion/code/auth-py/round-1.md ... RECOMMENDATIONS.md
# → Source file is never touched. Apply recommendations with a different tool.
```

### Cross-model mode

```
/triad-all docs/features/billing.md
# → 3 Claude subagents + 3 Codex CLI calls run in parallel
# → Tier 1: findings both engines flagged in the same lens
# → Tier 2: one engine, multiple lenses
# → Tier 3: singletons (one engine, one lens)
# → Requires codex-cli >= 0.125.0 (see docs/codex-5.4-to-5.5.md)
```

---

## Update

```
/plugin update
```

Then restart Claude Code.

---

## Troubleshooting

### `/triad` doesn't appear after install

Plugins are loaded at Claude Code startup. If `/triad` doesn't show up:

1. **Restart Claude Code** — required after every install and update.
2. Run `/plugin` and confirm `triad` is listed as **enabled**.
3. If listed but disabled: `/plugin enable triad@haroom_plugins`.
4. Still missing? Check that `~/.claude.json` has a `triad` entry under `enabledPlugins`. If it's `{}`, the install didn't complete — rerun `/plugin install triad`.

### `/triad-codex` or `/triad-all` errors with "model does not exist"

That's a Codex CLI version issue, not an account issue. Upgrade:

```
npm install -g @openai/codex@latest
codex --version   # must be >= 0.125.0
```

Full writeup: [`docs/codex-5.4-to-5.5.md`](docs/codex-5.4-to-5.5.md).

### Subagent crashed mid-round

Main agent automatically falls back to a local pass and tags the round `[fallback: main-local-pass]`. The round is valid but noted. If 2+ lenses fall back in the same round, stop and investigate (usually a prompt length issue — try a smaller target).

---

## Requirements

- Claude Code (any version with `/plugin` command) — spawns general-purpose subagents
- *(Optional — only for `/triad-codex` and `/triad-all`)* [Codex CLI](https://github.com/openai/codex) `>= 0.125.0`
- Works on Windows (Git Bash / WSL2), macOS, Linux

The base `/triad` runs entirely within Claude Code. No external CLI required.

---

## Evidence

See [`skills/triad/CASE-STUDIES.md`](skills/triad/CASE-STUDIES.md) for concrete examples of issues caught on real projects, with accept rates, perspective overlap analysis, and honest limits.

## Philosophy

Three reviewers who cannot see each other, with fixed questions that cannot drift, deliberating one file until consensus or cap. The round-delta rule keeps the document short — once something is settled, it stays settled. Markdown can move; code never does. If you need code to change, that's a different tool.

## Updates

- **2026-04-24** — Codex CLI `gpt-5.4` → `gpt-5.5` migration notes and benchmark ([docs/codex-5.4-to-5.5.md](docs/codex-5.4-to-5.5.md)). New sibling skills `/triad-codex` and `/triad-all` shipped — same framework, different engines. Read the migration doc before assuming a "model does not exist" error means your account is missing access.

## License

MIT — see [`LICENSE`](LICENSE).

## Author

haroom — [github.com/minwoo-data](https://github.com/minwoo-data)

## Contributing

Issues and PRs welcome at [github.com/minwoo-data/triad](https://github.com/minwoo-data/triad).
