# Triad - 3-Perspective Deliberation

**Language**: **English** · [한국어](README.ko.md)

**Ever shipped a design doc only to find later that AI agents could not parse it, the architecture aged badly, or new users could not make sense of it in 5 minutes?** triad deliberates one document through three fixed lenses (LLM clarity / architectural longevity / end-user comprehension) until all three lenses agree.

> Review one document or code file through three fixed perspectives -
> LLM clarity, architectural longevity, and end-user comprehension.
> Accumulate rounds until all three perspectives agree, or hit the cap.

---

## 30-second demo

**Without triad:**

You write a design doc, one reviewer says "looks fine", you commit it. Three weeks later: (a) an AI agent reading that doc gets confused and ships a broken feature, (b) the architecture choice painted you into a corner, (c) a new hire takes 15 minutes to figure out what the doc is even saying.

**With triad:**

`/triad docs/features/billing.md`. Three independent agents read the doc through fixed lenses: LLM clarity, architectural longevity, end-user comprehension in 5 minutes. They keep passing the doc back until all three agree, or round 5 caps out. The consensus is written to `updated.md` without touching the original.

## Who should use this

- **Project instruction docs** (`CLAUDE.md`, agent prompts, onboarding) - read by AI too, the LLM lens is especially valuable
- **ADRs (Architecture Decision Records)** - verify the choice from three angles before committing
- **Public docs** (README, getting-started, API) - the end-user lens catches things readers silently give up on
- **Code files you want thoroughly reviewed read-only** - triad does not edit code, only produces `RECOMMENDATIONS.md`
- **Before opening a PR** - triangulate the justification for the change

## Sibling tools (same marketplace)

- **[ddaro](https://github.com/minwoo-data/ddaro)** - worktree-based parallel Claude Code sessions with safe merge.
- **[prism](https://github.com/minwoo-data/prism)** - 5-angle parallel code review with singleton verification (wider, one-shot).
- **[mangchi](https://github.com/minwoo-data/mangchi)** - iterative code refinement loop with Claude + Codex cross-review.

---

## What this is

A Claude Code plugin that deliberates on a **single file** through three
fixed review lenses, run in parallel by independent Claude subagents:

- **LLM Clarity** - "Can a future AI agent read this and act correctly
  without hallucinating?"
- **Architect** - "Is this design maintainable a year from now? Are
  responsibility boundaries clear?"
- **EndUser** - "Can someone seeing this for the first time answer *what*,
  *why*, and *how* within five minutes?"

Each round produces a structured critique from all three perspectives.
Main agent synthesizes, makes decisions, and optionally applies changes
(for markdown only). Rounds accumulate - round 2 sees only the issues
that round 1 didn't resolve. Terminates on unanimous PASS, round cap, or
user stop.

Think of it as a design review where three very different reviewers show
up, can't see each other's comments, and won't go home until the document
stops provoking objections.

## When to use it

- **Project instruction files** (`CLAUDE.md`, agent prompts, onboarding
  docs) - the LLM lens is especially valuable because these files are
  read by AI agents, not just humans
- **Architecture decision records** before committing to a direction
- **Public-facing documents** where first-time-reader comprehension
  matters (READMEs, getting-started guides, API docs)
- **Code files you want to scrutinize but not yet modify** - triad's
  code mode is read-only and produces a `RECOMMENDATIONS.md` instead
  of editing the code
- **Before a pull request** when you want three independent critiques
  of the change rationale

## When NOT to use it

- **Small, obvious changes** - the overhead of three parallel agents
  exceeds the signal
- **Routine bug fixes** - just fix the bug
- **Code you want to iteratively improve** - triad never modifies code;
  use an iterative code-refinement tool (e.g. [mangchi](https://github.com/minwoo-data/mangchi)) for that
- **Pure natural-language prose** that isn't instruction-like - the LLM
  lens and architect lens have less to say about creative writing

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

Each subagent returns structured YAML:

```yaml
verdict: PASS | REVISE | BLOCK
top_issues:
  - severity: high | med | low
    locus: "file:line or section name"
    problem: "what's wrong from this lens"
    proposed_fix: "concrete change"
open_questions:
  - "escalate to the main agent / user"
```

Per-perspective cap: **max 3 high-severity issues** per round. Prevents
rambling critique.

## Input types and write permission

| Input | Default | `--apply` | `--apply=original` |
|---|---|---|---|
| `.md` | Original untouched, no changes | `updated.md` created/updated, original untouched | `updated.md` + original Edit |
| `.py`/`.js`/code | Original untouched, `RECOMMENDATIONS.md` produced | `--apply` ignored with warning | `--apply=original` ignored with warning |

**Code files are never modified** by triad. This is a hard invariant -
if you want to mutate code, that's a different tool's job.

## Termination conditions

Any of:

1. **All three perspectives return `verdict: PASS`** AND the main agent's
   open-questions list is empty
2. **Round cap** - 5 rounds by default
3. **User `/stop`**

The round-delta rule: round N only carries forward unresolved issues from
round N-1. Resolved items don't get re-litigated.

## Install

### Prerequisites

- [Claude Code](https://docs.claude.com/en/docs/claude-code) with access
  to spawn general-purpose subagents

No external CLI required - triad uses Claude's built-in Agent tool.
Runs entirely within Claude Code.

### Plugin install

`triad` is distributed through the **haroom_plugins** aggregator marketplace along with the other haroom plugins (ddaro, prism, mangchi).

```bash
# 1. Add the haroom_plugins marketplace (one time)
/plugin marketplace add https://github.com/minwoo-data/haroom_plugins.git

# 2. Install
/plugin install triad
```

Restart Claude Code after install.

## Usage

```
/triad docs/features/billing.md                    # read-only, consensus doc only
/triad docs/features/billing.md --apply            # create updated.md, original untouched
/triad docs/features/billing.md --apply=original   # also Edit original file
/triad src/routes/auth.py                          # code review, produces RECOMMENDATIONS.md
/triad --continue billing                          # resume in-progress session
/triad --stop billing                              # force close at current round
```

Natural-language: *"three-perspective review"*. (Korean triggers available; see the Korean README.)

See [`skills/triad/references/usage.md`](skills/triad/references/usage.md)
for detailed examples including the `docs/discussion/<slug>/` output
structure.

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

For code inputs, the path is `docs/discussion/code/<slug>/` and the
final file is `RECOMMENDATIONS.md` in a format compatible with downstream
code-generation tools.

## Safety defaults

- Original files are **never** modified without explicit `--apply=original`
- Code files are **never** modified regardless of flags
- Three subagents are spawned in a **single parallel tool call** so they
  cannot see each other's output - prevents groupthink
- If a subagent fails to spawn or crashes, main agent falls back to a
  local review pass and tags the round as `[fallback: main-local-pass]`
  in the output - no silent quality drop

## Evidence

See [`skills/triad/CASE-STUDIES.md`](skills/triad/CASE-STUDIES.md) for
concrete examples of issues caught on real projects, with accept rates,
perspective overlap analysis, and honest limits.

## License

MIT - see [`LICENSE`](LICENSE).

## Credits

- Created by: haroom
- Built on [Claude Code](https://docs.claude.com/en/docs/claude-code) and
  its general-purpose Agent tool
