---
name: triad
description: "3-perspective deliberation on one markdown/document file - LLM clarity, architectural longevity, end-user comprehension - parallel subagents until consensus. Documents only; code goes to /prism or /mangchi."
argument-hint: "<file> [--apply | --apply=original] | --continue <slug> | --stop <slug>"
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
---

# /triad Command

Deliberate on a single document (markdown) through three fixed perspectives
run as independent parallel Claude subagents - LLM clarity, architectural
longevity, and end-user 5-minute comprehension. Round-delta accumulation
until consensus or cap.

## Parse Arguments

Inspect `$ARGUMENTS` to determine the action:

| Argument Pattern | Action |
|---|---|
| `<file.md>` | Start a new deliberation on a markdown file (read-only - produces CONSENSUS.md; original untouched) |
| `<file.md> --apply` | Same as above, BUT also produce `docs/discussion/<slug>/updated.md` with accepted fixes |
| `<file.md> --apply=original` | Same as `--apply` + Edit the original markdown file |
| `<file.py>` / other code | **Refused.** Print one line: `triad는 문서 전용입니다. 코드 리뷰는 /prism <file>, 반복 수정은 /mangchi <file> 을 쓰세요.` and stop. No session is created. |
| `--continue <slug>` | Resume an in-progress session from `docs/discussion/<slug>/state.json` |
| `--stop <slug>` | Force-close the named session with whatever state it has |
| (no argument) | Show interactive menu (see below) |

## No Argument Provided

**EXECUTE:** Call the AskUserQuestion tool with the following JSON:

```json
{
  "questions": [
    {
      "question": "What do you want three perspectives to review?",
      "header": "Triad (트라이어드)",
      "options": [
        {"label": "Markdown document", "description": "Review a document - LLM clarity + architect + end-user lenses. Original untouched by default."},
        {"label": "Continue session", "description": "Resume an in-progress deliberation - you'll be asked for the slug"},
        {"label": "Stop session", "description": "Force-close an in-progress deliberation"}
      ],
      "multiSelect": false
    }
  ]
}
```

After the user selects and provides the file path or slug, re-run this command
with the resolved argument string.

## Prerequisites (check before execute)

1. **Target file exists** - `test -f "<file>"` before starting a new session.
2. **Parallel subagent spawn is available** - triad REQUIRES spawning three `general-purpose` Claude subagents in a single message. If that capability is not available in the current environment, fall back per SKILL.md's `[fallback: main-local-pass]` protocol and warn the user that review quality will be reduced.

## Execute

Read the skill file, then follow its workflow exactly:

1. Read `${CLAUDE_PLUGIN_ROOT}/skills/triad/SKILL.md`
2. Follow SKILL.md's 7-phase workflow with the user's argument string: `$ARGUMENTS`
3. Respect SKILL.md's hard invariants:
   - **Code files are refused** (documents only) - point the user to `/prism` / `/mangchi`
   - Markdown originals are modified ONLY with `--apply=original`
   - Subagent prompts put the **target document first**, perspective definition last (shared prefix → prompt-cache friendly)
   - Three subagents must be spawned in a single parallel tool call (one message, three independent tool_use blocks) so they cannot see each other's output - groupthink prevention is a core design principle
   - Each perspective is capped at max 3 high-severity issues per round
   - Round-delta rule: round N carries forward only unresolved issues from round N-1
4. Preserve per-round audit trail under `docs/discussion/<slug>/` as documented
5. Terminate on unanimous `PASS` + empty `open_questions` / 5-round hard cap / explicit `--stop`

## Output expectations

On success, the user will have:
- `CONSENSUS.md` - final decisions + preserved dissent + timeline
- Per-round `round-N.md` files with YAML responses from each perspective + main-agent synthesis + decisions
- With `--apply`: `updated.md` (and optionally the Edited original)

## Notes for the main agent

- If a perspective subagent fails to spawn or crashes, the main agent performs a local pass with that perspective's prompt and tags the section `[fallback: main-local-pass]`. If two or more perspectives fall back in the same round, warn the user and offer to abort.
- If the target is a code file, do NOT start a session - print the refusal line and name `/prism` (review) and `/mangchi` (fix).
- If the target is a very short document (< ~30 lines), warn that overhead may exceed signal and ask whether to proceed.
