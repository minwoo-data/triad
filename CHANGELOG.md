# Changelog

All notable changes to the Triad plugin are documented here.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [Semantic Versioning](https://semver.org/).

## [0.1.0] — 2026-04-15

Initial public release.

### Added
- Core `/triad <file>` command with 7-phase deliberation workflow
- Three fixed review perspectives, run as independent parallel subagents:
  - **LLM clarity** — catches ambiguous references, implicit prerequisites,
    structural signal weaknesses that trip up future AI agents
  - **Architect** — flags coupling, unclear responsibility boundaries,
    irreplaceable assumptions, extensibility cliffs
  - **EndUser** — enforces the 5-minute test: *what / why / how* should
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
