# Changelog

All notable changes to the Triad plugin are documented here.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [Semantic Versioning](https://semver.org/).

## [0.2.0] - 2026-10-13

Documents-only release. Removes code-input support, fixes stale tool names,
aligns the per-engine agent prompts, and reorders subagent prompts for
prompt-cache reuse. Also back-fills the changelog for two previously
unreleased commits (see 0.1.3 below).

### Changed (breaking behavior)
- **triad / triad-all / triad-codex accept documents only.** A code file
  (`.py` / `.js` / `.ts` / ...) is refused with a one-line pointer to
  `/prism <file>` (evidence-graded review) or `/mangchi <file>` (iterative
  fix) and no session is created. Rationale: on code, the Architect lens
  asked the same questions as mangchi's `design` axis and prism's
  Testability lens, so triad was a duplicate tool for that input type.
  One route per input type - documents → triad, code → prism/mangchi.
- **Subagent prompt order**: target document (shared across the 3 lenses)
  first, previous-round consensus next, perspective definition and output
  format last. The shared prefix is now identical across the 3 calls, so
  prompt caching can serve 2 of 3 inputs; the old order (perspective
  first) diverged from token one. Applies to the Claude Agent prompt
  template and the Codex heredoc template in all three skills.
- **Compressed agent prompts aligned with the originals.** The
  `triad-all` / `triad-codex` Architect prompt carried an extra item 8
  ("불필요한 추가 (YAGNI 위반)") that `triad` lacked - the same lens was
  defined differently per engine, which made cross-model agreement an
  unfair comparison. Item 8 and its constraint/checklist lines are removed;
  YAGNI is explicitly delegated to mangchi's `necessity` axis in all three
  "지적하지 말 것" lists. Item sets (7 per lens) now match across the three
  copies; wording may stay terse in the compressed ones.

### Removed
- `skills/triad/templates/recommendations.md` and every `RECOMMENDATIONS.md`
  reference (SKILL.md ×3, templates, README ×2, usage.md, commands/triad.md).
- `docs/discussion/code/<slug>/`, `docs/discussion/all/<slug>/`,
  `docs/discussion/codex/<slug>/` output trees (code-input artifacts).
  Existing directories are left alone; `--continue` applies to document
  sessions only.
- The "Code file (read-only)" option from the `/triad` no-argument menu.

### Fixed
- Stale `/review-all` and `/review-devil` references (pre-release names of
  what is now `/prism` and the archived `prism-devil`) in the SKILL.md
  differentiation matrix, usage.md, and the EMPIRICAL-COMPARISON header
  (kept as historical evidence with a note).
- Plugin manifests (`plugin.json`, `marketplace.json`) now say documents,
  not "document or code file".

### Not Changed
- The 3 lenses, YAML schema, `<<<TRIAD-FINDINGS v1>>>` fence format,
  `parse-triad.js`, round/consensus templates, termination logic
  (3-PASS AND zero open questions, R5 cap), `--apply` write discipline.

## [0.1.3] - 2026-06-22

Back-filled entry: these commits shipped on `main` without a changelog
line or version bump.

### Added
- **`triad-codex`** (2026-04-24) - the 3 lenses evaluated by Codex CLI
  instead of Claude subagents (different-model opinion / Claude-token
  saving). Codex ≥ 0.125.0 required; tempfile+stdin invocation only.
- **`triad-all`** (2026-04-24) - dual-engine: 3 Claude subagents + 3 Codex
  calls in parallel; issues flagged by both engines in the same lens are
  promoted to Tier 1 (cross-model agreement). Termination = 6-way PASS.
- `docs/codex-5.4-to-5.5.md` - Codex CLI migration write-up.
- **`parse-triad.js`** (2026-06-22) in `triad-all` and `triad-codex` -
  deterministic parser for the `<<<TRIAD-FINDINGS v1>>>` fence (scans all
  fence blocks and picks the one with a verdict and the most issues;
  normalizes severity aliases; preserves parsed issues on degrade).
  Synthesis triages the structured record instead of eyeballing prose.
  `--selftest` included.
- `verify-independence.js` in both Codex-backed skills (required files +
  cross-plugin reference check; `--strict` probes Codex CLI).

## [0.1.2] - 2026-04-17

Docs release - adds Case Study 2 to evidence base, taking n from 1 to 2.
No code or mechanic changes.

### Added
- **Case Study 2** in `skills/triad/CASE-STUDIES.md` - parallel
  4-session breadth sweep on a Python Flask backend (42+ modules across
  4 subsystems, 4 concurrent main agents × 3 parallel subagents per
  file). Demonstrates triad scaling to multi-session parallel execution
  and shows multi-perspective convergence predicting downstream (mangchi)
  patch acceptance: the 2 candidates flagged by all three perspectives
  became src/ patches; the 5 flagged by 1-2 stayed no-patch.
- **Updated evidence-strength banner** - n=1 → n=2 on different target
  types (instruction file + multi-subsystem code sweep). Still short of
  statistical claims; third case on a different language/stack still
  wanted.

### Notes
- **Operational lesson** (in Case Study 2 body): 4-session parallel triad
  requires an external supervisor to catch cross-worktree git contamination.
  Two contamination events caught during this run.

## [0.1.1] - 2026-04-17

Polish release after pre-public-release `/review-all` sweep. Same 3-lens
mechanic; fixes frontmatter blocker, clarifies positioning vs `/review-all`,
walks back over-claimed orthogonality.

### Added
- **`.claude-plugin/marketplace.json`** - so `/plugin marketplace add
  minwoo-data/triad` and `/plugin install triad@triad` actually work. v0.1.0
  shipped README instructions for the marketplace route but lacked the
  manifest, so the command silently failed. Manual clone remains as fallback.
- **`.claude-plugin/plugin.json`** - single-plugin manifest for auto-discovery
  (name, version 0.1.1, author, repo, keywords).
- **Differentiation matrix at top of SKILL.md** - spells out "when triad vs
  `/review-all` vs `/review-devil` vs mangchi." The #1 user question
  ("is this YAGNI given /review-all exists?") deserves an explicit answer
  instead of burying overlap behind 4 lines at the bottom.
- **Cost envelope paragraph** - typical vs worst-case Claude subagent call
  count, and a note that `/review-all` is ~25% the cost for one-shot reviews.

### Changed
- **Frontmatter**: added `user-invocable: true` and `argument-hint` - without
  these, slash-command triggers documented in the body did not fire on a
  clean install. Silent blocker for every first-time user.
- **Frontmatter description**: rewritten from generic feature list to
  differentiation-first ("use over /review-all when you need audit trail +
  convergence delta + write-discipline"). Catalogue browsers get the
  decision framework at first glance.
- **Author history rewritten** via `git filter-branch` to attribute
  consistently to minwoo-data (prior commits were under a work account from
  local git config at the time).

### Fixed
- **Phase 3 intro vs table contradiction on `updated.md` creation**: intro
  said "main only updates updated.md" while the table's first row said
  "updated.md NOT created when no --apply." Intro now correctly reflects
  that updated.md is only created when `--apply` is specified.
- **CASE-STUDIES.md "0 cross-perspective conflicts" framing** - softened
  from implicit "lens orthogonality proven" to explicit n=1 disclaimer:
  weak positive evidence of complementarity, not proof of orthogonality.
  Second case study on a different project type is needed before the lens
  design can be claimed to generalize.

### Not Changed
- Agent perspectives, YAML schema, round/consensus templates, termination
  logic (3-PASS consensus, R5 cap, AND-gate). All mechanics preserved.

## [0.1.0] - 2026-04-15

Initial public release.

### Added
- Core `/triad <file>` command with 7-phase deliberation workflow
- Three fixed review perspectives, run as independent parallel subagents:
  - **LLM clarity** - catches ambiguous references, implicit prerequisites,
    structural signal weaknesses that trip up future AI agents
  - **Architect** - flags coupling, unclear responsibility boundaries,
    irreplaceable assumptions, extensibility cliffs
  - **EndUser** - enforces the 5-minute test: *what / why / how* should
    be answerable after a short read
- Round-delta rule: round N only carries forward unresolved issues from
  round N-1 (prevents re-litigation)
- Safe-by-default write policy:
  - Original files never modified without explicit `--apply=original`
  - Code files never modified regardless of flags (read-only output:
    `RECOMMENDATIONS.md`)
- Hard termination conditions: 3-PASS unanimous agreement / 5-round cap /
  user `/stop`
- Per-perspective high-severity cap (max 3 per round) to prevent rambling
- Subagent-unavailable fallback: main agent performs a local review pass
  with the same perspective prompt, tagged `[fallback: main-local-pass]`
- Bundled reference materials: three perspective prompts, round/consensus/
  recommendations templates, usage examples
- First real-world case study: deliberation on a project instruction file
  (CLAUDE.md) with 14 issues synthesized, 7 accepted after user audience
  clarification

### Known Gaps
- Single-file scope; does not coordinate deliberation across multiple files
- Requires a Claude Code environment that supports spawning parallel
  general-purpose subagents
- Most effective on documents and code files that will be read by others
  (AI agents or humans); less signal on pure creative writing
- Round-cap of 5 prevents infinite loops but may leave some nuance
  undiscussed on complex documents

### Case Studies
- See `skills/triad/CASE-STUDIES.md`
