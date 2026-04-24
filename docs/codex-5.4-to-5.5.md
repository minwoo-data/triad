# Codex CLI: the "model does not exist" trap, and what gpt-5.5 actually changes

> **TL;DR** — If your Codex CLI reports `The model 'gpt-5.5' does not exist or you do not have access to it`, the problem is probably **your CLI version, not your account**. Upgrade to `codex-cli >= 0.125.0` first. Then you get a real speedup on small files, roughly a third fewer tokens per review, and a cleaner output format that breaks your old parser.

## The trap, in order

1. A Codex-backed review skill boots with `model = "gpt-5.5"` in `~/.codex/config.toml` and `codex-cli 0.123.0`.
2. First call errors with `The model 'gpt-5.5' does not exist or you do not have access to it`. Five reconnect retries, ~30s wasted.
3. Natural reading: "my account doesn't have gpt-5.5 yet, rollout hasn't reached me." Work around by forcing `-c model=gpt-5.4` on every call, move on.
4. Hours later, recheck. `~/.codex/models_cache.json` now lists gpt-5.5 with `"visibility": "list"` — account clearly has access. But the call **still fails**, now with a different message: `The 'gpt-5.5' model requires a newer version of Codex. Please upgrade to the latest app or CLI and try again.`
5. `npm install -g @openai/codex@latest` → 0.125.0. gpt-5.5 calls succeed immediately.

The first error message is ambiguous enough to send you down the wrong path. The second one is clear. **Try the CLI upgrade before blaming account access.**

## What gpt-5.5 (via CLI 0.125.0) actually changes

Benchmarked on three files through the triad-codex skill (3 independent lenses: LLM-clarity, architect/longevity, end-user comprehension).

### Wall time (seconds, 3 lenses sequential)

| Target | size | 5.4 | 5.5 | Δ |
|---|---|---|---|---|
| file-b (small utility module) | ~150 LOC | 110s | **78s** | **−29%** |
| file-a (Flask auth routes) | ~540 LOC | 116s | 103s | −11% |
| file-c (Flask upload route) | ~390 LOC | 96s | 99s | +3% |
| sum | | 322s | 280s | −13% |

One 5.4 call on file-a was a 52s cold start; normalize it and the 5.4 total drops to ~94s, making 5.5 marginally slower on that file. **Honest take: the wall-time win is concentrated on small prompts.** Fixed per-request overhead is proportionally smaller at larger prompt sizes.

### Output / token efficiency (LLM lens on file-b)

| | 5.4 | 5.5 | Δ |
|---|---|---|---|
| Output bytes | 19,726 | 11,522 | **−42%** |
| Tokens (self-reported) | 7,891 | 5,091 | **−35%** |

The main driver is deduplication. On 5.4, Codex always dumped a prompt-scaffold echo at the top of the response plus the real YAML at the bottom — essentially two copies. 5.5 emits once.

### Output format — this breaks your parser

| | 5.4 | 5.5 |
|---|---|---|
| Wrapping | ` ```yaml ... ``` ` fenced | raw YAML, no fences |
| Occurrences | 2 (echo + response) | 1 |
| Marker | none | `codex` line precedes the response |

If you were extracting the first fenced `yaml` block, you need a new strategy on 5.5. Ours now reads raw YAML starting at the first `verdict:` line after the `codex` marker.

### Analytical coverage (same benchmark file)

| | 5.4 | 5.5 |
|---|---|---|
| Total findings | 16 | 12 |
| `high` severity | 5 | 3 |
| Shared themes with 5.4 | — | 7 |
| Theme only 5.4 caught | scope mismatch between a comment mentioning an extension family and code that only handles one extension | — |
| Theme only 5.5 caught | — | docstring claims the function guards one thing while the body also enforces structural + path-traversal + size checks |
| Verdict per lens | REVISE / REVISE / REVISE | REVISE / REVISE / REVISE |

Roughly a wash on analytical power, with different strengths. 5.5 trims the low-signal tail and catches one new class of issue (docstring-understates-scope) that 5.4 missed. 5.4 was slightly more precise on enumerating brand-level scope mismatches. Neither is strictly better for all findings.

### Stderr noise to ignore

5.5 prints this to stderr on most runs and does not affect the response:

```
ERROR codex_core::session: failed to record rollout items: thread <id> not found
```

Filter it in your log ingestion if you're tailing Codex output.

## Action items if you run a Codex-backed skill

1. Pin `codex-cli >= 0.125.0`. Probe `codex --version` on skill init and fail fast with an upgrade hint.
2. Update your YAML extractor. Don't look for ```yaml fences on 5.5 output.
3. Drop `-c model=gpt-5.4` overrides if you were using them — `~/.codex/config.toml` default works again.
4. Optional, defends against future version drift: read `~/.codex/models_cache.json`, pick the first entry with `"visibility": "list"` if the configured model rejects you.
5. Filter the `rollout items` stderr warning out of your logs.

## Credits

Written from real benchmark runs on a small project's source tree (three files, 3 lenses each, two models). Raw numbers and output artifacts are in the sandbox that produced them; this writeup is the public, trap-shaped-not-timeline-shaped version. If you're about to reach for a model override, read this first.
