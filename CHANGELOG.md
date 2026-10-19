# Changelog

All notable changes to the Triad plugin are documented here.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [Semantic Versioning](https://semver.org/).

## [0.3.3] - 2026-10-19

Fixes from a /prism-all review of 0.3.2 (triad PR #7), Claude and Codex with 5 lenses each:
30 candidates, 23 supported by quoted code and machine-checked, none HIGH. Some 0.3.2 notes
claimed more than the code did; corrections are marked below.

### Fixed
- **Documented example values were quarantined again** (0.3.2 regression, MED). The value-only
  placeholder test skipped values that 0.3.1 had dropped:
  - shell defaults: `${POSTGRES_PASSWORD:-changeme}`, `DB_PASSWORD:=changeme123`
  - a vendor prefix followed only by x or *: `AKIAXXXXXXXXXXXXXXXX`, `ghp_xxxx…`,
    `sk-proj-xxxx…`, `xoxb-xxxx-xxxx`
  - AWS's `…EXAMPLE` and `…EXAMPLEKEY` values

  A reviewer quoting one of these in a suggested fix turned the lens into a security incident.
  They are dropped again.
- **"Whole value is a placeholder" was really a prefix test** (MED in effect; the 0.3.2 note
  overstated the fix). `API_KEY=your_Zk81mQp2…`, `DB_PASSWORD=ExampleCorp2024Secret` and
  `postgres://u:dummyZk81…@` were dropped as examples. A placeholder word may now be followed
  only by more words (`your_api_key_here`, `changeme_please`) or only by digits (`changeme123`).
- **Lock reclaim race not closed** (MED; the 0.3.2 note "two runs cannot both take it" was
  wrong). The slower of two attempts that found the same abandoned lock could rename away the
  lock the faster one had just re-created. Reclaim now happens under a second lock
  (`<out>.lock.reclaim`), and the lock is checked again once that is held.
- **A late interrupt could replace a finished answer** (0.3.2 regression). The raw stream was
  shredded while the interrupt handler was still armed. The handler is now disarmed before
  cleanup. A signal that arrives while Codex and the watchdog are starting is held until their
  pids are known, so the handler can stop them; before, it could leave Codex running.
- **`cleanup_failed` missed the scratch dir** (0.3.2 overstated it). The scratch dir was deleted
  only on exit, after the JSON and summary had been written. It is now deleted before publishing.
  A failure sets `cleanup_failed`, adds `,cleanup-failed` to a `secret-scrubbed(...)` status, and
  adds a CLEANUP FAILED line to a security marker. The summary line quotes the path.
- Fail-closed gaps in the scan and sweep:
  - A failing `sort` in `new_secret_in` returned "clean".
  - A failing `find` in the stale-scratch sweep counted as "nothing recent", so the dir was
    deleted. It now counts as recent.
  - An unreadable mtime made a pid-less lock look new forever. It now counts as old.
- **An interrupt could still lose a security incident or a cleanup report** (LOW):
  - A signal that came while the scan was deciding on a leak ran the handler before the leak was
    recorded, so the run read as an ordinary interrupt. Signals are now held until the verdict is
    recorded. A scan that fails meanwhile counts as interrupted, not `scan-failed`, because a
    Ctrl-C also kills the scan's grep.
  - A second, different signal re-entered the interrupt handler halfway (bash nests handlers for
    different signals) and could drop the CLEANUP FAILED report. The handler now ignores further
    signals.
- **A marker could be read as a verdict** (LOW; needs control of TMPDIR). The JSON of a run that
  is not `ok` is now always DEGRADED, whatever text its marker embeds (for example a scratch path
  holding newlines and a findings fence).
- `cr_exit` warns when another attempt took the lock over. Before, it stayed silent.
- The fallback JSON (written when parse-triad.js cannot run) now blanks control characters in
  `cleanup_failed`.
- SKILL.md (triad-all, triad-codex):
  - `scan-failed` (status `secret-scrubbed(scan-failed)`) is never auto-retried: tell the user,
    and re-run once the disk or permissions are fixed. 0.3.2 also told the model to re-run it,
    which contradicted the fallback table.
  - After exit 130, read the JSON `status` before re-running.
  - The takeover warning is described.

### Changed (selftest, 54 → 69 in triad-all)
- The two symlink cases now run on Git Bash without Developer Mode, using `MSYS=winsymlinks:sys`.
  In 0.3.2 they were silently skipped there. Cases this machine still cannot run count as
  "skipped" in the last line.
- Mtimes are moved back with `touch -t` (GNU or BSD `date`), so the lock and sweep cases also run
  on macOS. "Dead" pids are reaped children, not hard-coded 999999.
- The portable-watchdog check runs with a 40 s kill grace (test-only `_CODEX_RUN_KILL_GRACE`).
  The 18 s bound from 0.3.2 no longer hid a watchdog that holds the caller's pipe.
- The quarantine-interrupt case waits on a handshake instead of a fixed 3 s sleep.
- New cases:
  - a late reclaimer
  - a reclaim already in progress
  - takeover warning
  - unreadable mtime
  - failing `find`
  - failing `sort`
  - interrupt with an undeletable scratch dir
  - leak path with an undeletable scratch dir
  - fallback-JSON escaping
  - the placeholder forms above, in both directions
  - an interrupt while the scan decides, and a scan that fails during it
  - a second signal during the interrupt handler
  - an old scratch dir with a recently written file in it
  - a marker that embeds a findings fence

### Not fixed (suspected, no confirmed precondition)
- `[ -O ]` might be false for the user's own dirs on some Windows setups: none seen.
- The `destroy_dir` check-then-use window needs a shared TMPDIR without the sticky bit.
- mawk 1.3.3 might not support `[[:space:]]`; that case fails closed.
- A prompt file deleted mid-run under `TRIAD_CODEX_SANDBOX=bypass`.

## [0.3.2] - 2026-10-18

Security fixes in the shared safety core of `codex-run.sh`, ported from mangchi 0.4.0
(main 996f145). A /prism-all review of mangchi PR #3 found them in the code all three plugins
copied from prism 0.4.2. They are all LOW severity, and each needs an unusual condition: a
shared TMPDIR, two calls of the same lens starting together, a signal at the wrong moment, or a
failing `sed`.

### Fixed
- **Placeholder filter looked at the whole match** (PRISM-031). `EXAMPLE_API_KEY=<real value>`
  or `DUMMY_SERVICE_TOKEN=<real value>` was dropped as an example because the key *name* said
  example/dummy, so a leak with such a name was not quarantined. Now only the value counts, and
  only when the whole value is a placeholder (`your_…`, `<…>`, `changeme…`, `xxxx`, `…`); for a
  DSN, the password.
- **A failing filter stage read as clean** (PRISM-020). The `sed`/placeholder stage and the PEM
  base64 scan ran without a status check. A failure now returns "could not scan", which callers
  treat as a hit (fail closed).
- **Stale-scratch sweep could follow a planted symlink** (PRISM-017) and delete files outside
  `$TMPDIR`. The sweep now skips symlinks and dirs owned by another user; `destroy` and
  `destroy_dir` never shred through a link.
- **Sweep could delete a scratch dir an orphaned Codex was still writing** (PRISM-024). A dead
  attempt's dir is now swept only when nothing in it changed for 10 minutes.
- **Lock race** (PRISM-019). A lock without a pid (an attempt that has just started) is not taken
  over for 10 s. A stale lock is reclaimed by rename, so two runs cannot both take it. On exit an
  attempt removes the lock only if it still holds its own pid. Exit 2 says
  "another attempt of this call is starting".
- **An interrupt during quarantine erased the incident** (PRISM-012). It used to leave
  `[fallback: interrupted]`, which the skills treat as safe to re-run. Now the security marker
  and `secret-scrubbed(...)` status stay.
- **Cleanup failures were silent** (PRISM-021). The raw stream is deleted before publishing.
  A file or scratch dir that cannot be deleted shows up as `cleanup_failed` in the JSON,
  `cleanup_failed=<path>` in the summary line, and a CLEANUP FAILED line in an interrupt marker.

### Changed
- The shared code now sits between `BEGIN/END SHARED SAFETY CORE` markers, like mangchi's. Lines
  that differ from mangchi are marked `triad:`. Lines marked `mangchi:` are the fixes above,
  which prism 0.4.2 still lacks.
- SKILL.md (triad-all, triad-codex): the status paragraph adds `scan-failed`, the "attempt
  starting" exit 2, interrupts during quarantine, and `cleanup_failed` (tell the user which path
  to delete).
- `--selftest`: 42 → 54 cases in triad-all (53 in the triad-codex copy, which skips the one
  triad-all-only case). Each fix above was reverted on its own (10 mutants), and every revert
  failed its new test. The two symlink cases are skipped where native symlinks are not available,
  such as Git Bash without Developer Mode. The portable-watchdog timing bound is 18 s, as in
  mangchi (it was 12 s, which failed under load on Windows; the fake still sleeps 20 s).
- `publish_json`'s fallback record (written when parse-triad.js cannot run) JSON-escapes the
  `cleanup_failed` path, and a test checks that it parses.

## [0.3.1] - 2026-10-14

`/triad` now runs the `triad` skill directly. The duplicate `commands/triad.md` is gone: the
skill was already user-invocable, so the plugin listed `triad` twice (about 90 always-on tokens)
and every `/triad` read a 2.8k-token wrapper that only told the model to read SKILL.md.

### Moved into `skills/triad/SKILL.md`
- Argument table → §트리거 / 인자 (`<!-- args-table -->`), now also stating that arguments arrive
  as `ARGUMENTS: ...`. Fixes a contradiction while at it: the old trigger line said a plain
  `/triad <file>` writes an `updated.md` draft; Phase 3 and the command file said it does not.
- No-argument AskUserQuestion menu → same section (`<!-- no-arg-menu -->`), JSON unchanged.
- Short-document warning (about 30 lines) → Phase 0.
- "Parallel subagents unavailable in this environment" warning → Fallback step 5.
- CONSENSUS.md contents (final decisions + preserved dissent + timeline) → file-structure note.
- Already in SKILL.md, not duplicated: the code refusal line, target-exists check, invariants
  (target first, three parallel subagents, 3 high issues cap, round-delta, `--apply=original`
  only), termination rules, main-local-pass fallback.
- Not carried over: the command's `allowed-tools` list (it omitted `Agent`, which triad needs).

### Added
- `skills/triad/verify-entry.js`: fails (exit 2) when SKILL.md loses `user-invocable`, a row of
  the argument table, the no-argument menu JSON, the code refusal line, the short-document
  warning or the fallback tag. Each of those was broken once to confirm the check catches it.

### Removed
- `commands/triad.md` and the `"commands"` entry in `.claude-plugin/plugin.json`.

## [0.3.0] - 2026-10-14

The Codex invocation contract is now a script. triad-all and triad-codex call
`codex-run.sh lens <dir> <round> <lens> --target <doc>` once per lens instead of having the model
re-type a bash template. Ported from prism 0.4.1, which had the same template problem.

### Why
- The 0.2.x template had **no safety preamble, no secret scrub, and ran Codex with
  `--dangerously-bypass-approvals-and-sandbox`**, and it kept Codex's raw stream (prompt echo plus
  anything Codex printed) as `round-N.*.codex.txt.log` inside `docs/discussion/`, usually a
  committed directory.
- On 2026-10-13 a triad-all run on a design doc did not use the template at all: the orchestrator
  wrote its own runner (all lenses in one Bash loop, no effort pin).

### Added
- **`codex-run.sh`** (`skills/triad-all/`, byte-identical copy in `triad-codex/`):
  - Builds the prompt in the 0.2.x order: target → optional `--context` → round N-1 carryover
    (attached automatically from round 2; missing carryover warns) → `agents/<lens>-perspective.md`
    → the `TRIAD-FINDINGS v1` contract. The lens perspective is read from the skill's own file, so
    the model only names the lens.
  - Sandbox Safety Preamble first, prompt via file + stdin, 180 KB guard, timeout 300 s and effort
    `high` (`TRIAD_CODEX_TIMEOUT`, `TRIAD_CODEX_EFFORT`), `TRIAD_CODEX_MODEL` for the fallback-model
    retry.
  - **Read-only sandbox** for every command Codex runs (no writes, no network).
    `TRIAD_CODEX_SANDBOX=bypass` is an explicit per-run opt-out, printed in the summary line.
  - **Secret scrub** over the raw stream, the last message and the prompt; a string is allowed
    back only if the prompt held it before the run. Only the `--output-last-message` answer is
    kept and parsed; the raw stream is never stored.
  - `parse-triad.js` runs on every answer; stdout is one summary line
    (`status=… verdict=… issues=N questions=N sandbox=…`) plus the parser JSON.
  - Failures degrade the lens (`[fallback: <reason>]` → verdict DEGRADED), never the round.
  - `--selftest`: 42 cases against a fake Codex.
- **One prompt structure for both engines.** The output contract lives in one file,
  `templates/output-contract.md`, appended to every prompt. `codex-run.sh prompt` writes the Claude
  agent prompt (`round-N.claude.<lens>.prompt.txt`): the Codex prompt minus the preamble, byte for
  byte. The selftest fails if the contract file or its use goes missing, if a perspective file asks
  for another format, or if the two prompts differ. (A first draft of 0.3.0 deleted the v1 grammar
  together with the old bash template, which left the Claude agents without it; a prism-all review
  caught it.)
- `--instructions <file>` (e.g. `/ddaro:review`'s verify-against-code instruction) and repeated
  `--context`.
- Round-Delta is enforced: from round 2 the round-(N-1) carryover file is required (`## 합의됨` /
  `## 미해소`), `--no-carryover` skips it explicitly.
- The shared safety core matches prism 0.4.2: scratch outside the discussion dir, per-lens lock,
  incident markers kept, no false quarantines on quoted values or placeholder fixes, more secret
  forms, fail-closed scan, interrupt JSON, Git Bash for `--strict` on Windows, Codex flag probe.
- `skills/sync-review-parsers.sh` (referenced by the parser header but missing until now) copies
  `parse-triad.js` and `codex-run.sh` from triad-all to triad-codex and checks for drift.
- `verify-independence.js --strict` now requires and selftests `parse-triad.js` and `codex-run.sh`.

### Changed (breaking behavior)
- triad-codex's `CODEX` env override (the whole command) is gone: use `TRIAD_CODEX_BIN`,
  `TRIAD_CODEX_MODEL`, `TRIAD_CODEX_EFFORT`. Codex now runs in the read-only sandbox by default.
- `agents/*-perspective.md` and `templates/round.md` use the v1 records instead of YAML.
- `parse-triad.js` ignores the contract's own template lines if a model echoes them
  (`VERDICT | PASS|REVISE|BLOCK` used to parse as PASS).

### Changed
- triad-all runs its 3 Codex lenses as 3 parallel Bash calls next to the Claude agents (was one
  Bash looping all three). Codex wall time about 45–60 s instead of 90–110 s.
- File names in `docs/discussion/` are unchanged, plus `*.codex.txt.json`; `*.codex.txt.log` is no
  longer written.
- SKILL.md: the template and its rules are replaced by the script usage (triad-all 16.4 → 14.5 KB,
  triad-codex 15.9 → 13.7 KB). Per round the model no longer writes the ~1.9 KB template per lens.

## [0.2.1] - 2026-10-13

### Changed
- **Codex calls pin `model_reasoning_effort=high` and a 300 s timeout** (triad-all was 180 s,
  triad-codex 120 s, both followed the `~/.codex/config.toml` default effort). xhigh exhausts the
  Codex usage limit within a few calls. Override per run with `TRIAD_CODEX_EFFORT`
  (low/medium/high/xhigh/max/ultra) and `TRIAD_CODEX_TIMEOUT` (seconds); for max and above set the
  timeout to 480+. Measured on CLI 0.159.3 with a 24 KB prompt: high 44 s, xhigh 113 s, max 227 s.
  Ported from the unreleased `feat/codex-effort` work.
- Differentiation matrix and READMEs: a design doc has two separate questions. prism ≥0.3.1
  (design lens set) checks whether the design is *sound*; triad checks whether the document is
  *well written*. `/ddaro:review` runs both. triad itself stays documents-only.

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
