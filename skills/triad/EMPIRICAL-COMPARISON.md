# Triad — Empirical Comparison vs `/review-all` and `/review-devil`

> First attempt at grounding triad's differentiated value in side-by-side
> evidence. See also `CASE-STUDIES.md` for the original n=1 smoke test.

---

## Bench: `src/security/file_validator.py` (Flask upload validator, 126 LoC)

Same target, four tools, identical input, no hints. Goal: answer the
headline adoption question — **"is triad YAGNI given `/review-all` exists?"** —
with specific evidence rather than design intent.

**Environment**:
- Triad: v0.1.1 (post-polish frontmatter / positioning fixes)
- Code mode (read-only, no `updated.md` generated)
- Running as `[fallback: main-local-pass]` because Agent tool was not
  exposed in the test session. This may reduce true cross-lens
  independence; findings unique to a lens are still reported by that
  lens's prompt, but the lack of parallel subagent isolation is a caveat.

---

## Findings (1 round, all 3 lenses REVISE)

### LLM clarity lens — findings unique vs other tools

| Finding | Severity | Claimed by other tools? |
|---------|----------|-------------------------|
| Implicit call-order contract between `is_allowed_file` and `verify_file_magic` — no docstring warning, future LLM-written callers will bypass | high | ❌ none |
| `get_pdf_page_count` returns `None` on failure with no caller-side guidance (fail-open vs fail-closed) | med | ❌ none |
| Module docstring missing threat model → LLM may assume this is a full defense and weaken upstream callers | med | ❌ none |

### Architect longevity lens — findings unique vs other tools

| Finding | Severity | Claimed by other tools? |
|---------|----------|-------------------------|
| `_XLSX_MAX_*` hardcoded constants violate project's `config.json` standard | med | ✅ review-all (same) |
| No unified `validate_upload()` composition entry point | high | ✅ review-all (same) |
| MAGIC_BYTES dict + WebP/HEIC branches asymmetric → new-format addition splits between two spots | med | ❌ none |

### EndUser 5-min comprehension lens — findings unique vs other tools

| Finding | Severity | Claimed by other tools? |
|---------|----------|-------------------------|
| Function naming prefix inconsistent (`is_` / `verify_` / `validate_` / `sanitize_` / `get_`) — 5-min reader can't infer order/responsibility | med | ❌ none |
| `sanitize_filename` UUID-prefix rationale missing from docstring (why not documented) | med | ❌ none |
| MAGIC_BYTES dict doesn't signal that WebP/HEIC exist as separate branches | low | ❌ none |

---

## Comparison summary

| Tool | Findings count | Unique findings | Overlap with triad |
|------|----------------|-----------------|---------------------|
| `/review-devil` | 14 (4C 5H 4M 1L) | Polyglot bypass, ZIP header trust, PyMuPDF CVE, filename tricks | Low — adversarial-thinking focus |
| `/review-all` | 16 (3C 7H 6M + synthesis) | xlsx magic triple-flag, HEIC loose | Medium — shared architecture concerns (`validate_upload`, config.json) |
| `/triad` (this run) | 9 findings (3 per lens) | **6 findings unique to triad**: call-order contract (LLM), `None` return semantics (LLM), threat-model docstring (LLM), naming inconsistency (EndUser), UUID rationale (EndUser), MAGIC_BYTES asymmetry (Architect+EndUser) | — |

**Key observation**: triad's LLM-clarity lens caught **3 findings that no
other tool raised** — specifically about future-LLM-caller contracts. This
is triad's structural value: `/review-all`'s generic lenses (Conflict /
Improvement / Devil / Code Review) do not have a "how will an LLM read
this code" angle, and neither does `/review-devil` in its adversarial focus.
For code that will be extended by AI agents (either Claude Code plugins
themselves, or agent-friendly documentation targets), these findings matter.

---

## Answering "is triad YAGNI vs `/review-all`?"

**No, not YAGNI** — this bench gives concrete evidence:
- 3 findings unique to LLM-clarity lens (no other tool raised them)
- 2 findings unique to EndUser 5-min lens (naming + why-documentation)
- Architect lens had meaningful overlap with review-all but added the
  "MAGIC_BYTES asymmetric structure" observation

**But** the cost was ~3× review-all (3 subagents + main synthesis vs 4
parallel one-shot agents + synthesis). **Decision rule**:
- Use `/review-all` for one-shot survey.
- Use `/triad` when:
  - The target is **documentation that future LLMs will read** (CLAUDE.md,
    plugin README, ADR) — LLM lens shines here
  - The target is a **public/semi-public API** whose human+LLM audience
    both matter — EndUser lens complements
  - You want **multi-round convergence** with state-json audit trail —
    `/review-all` is one-shot only

---

## Limits of this bench

- **n=2** now (this file + Case Study 1's CLAUDE.md). Still not enough to
  claim the 3-lens design generalizes. A third case study on a truly
  different target (e.g., a frontend component) would strengthen the
  evidence.
- **Main-local-pass mode** reduces true lens independence. In a real
  parallel-subagent run, each lens sees only its own prompt + file
  content. Here the same agent ran all three sequentially — may share
  priors between lenses.
- **No ACCEPT/REJECT judgment applied**: this run exercised the review
  mechanic but not the Phase 3 decision layer since it was code mode
  (read-only). The `/mangchi` companion run on the same file does
  exercise the decision layer and applied 3 fixes.
- **No round 2**: terminated after R1 for test-efficiency. Round 2 would
  exercise the round-delta mechanic and convergence tracking — the
  unique parts of triad vs one-shot reviews — which this bench didn't
  test.

---

## Recommended next evidence

1. Run full 3+ round triad on a documentation target (the best-fit use
   case) to exercise convergence behavior.
2. Compare round-over-round issue reduction against `/review-all` re-runs
   on the same target to measure whether round-delta actually converges
   faster.
3. Test with a markdown document where the `--apply` write policy
   actually matters (code mode here skipped that entire half of the
   design).
