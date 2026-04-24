# Round {N} (triad-all)

**Target**: `{target_file}`
**Input type**: {md | code}
**Apply mode**: {true | false}
**Engines**: Claude Agent + Codex CLI (`{codex_model}`)
**Started**: {timestamp}
**Claude wall**: ~{claude_wall}s (3 parallel)
**Codex wall**: ~{codex_wall}s (3 sequential)

---

## 1. LLM Perspective

### Claude
```yaml
{claude_llm_yaml}
```

### Codex ({codex_model})
```yaml
{codex_llm_yaml}
```

### Agreement / Disagreement
- **Cross-model agreement (same issue, both flagged)**: …
- **Claude-only**: …
- **Codex-only**: …

---

## 2. Architect Perspective

### Claude
```yaml
{claude_arch_yaml}
```

### Codex
```yaml
{codex_arch_yaml}
```

### Agreement / Disagreement
- Cross-model agreement: …
- Claude-only: …
- Codex-only: …

---

## 3. EndUser Perspective

### Claude
```yaml
{claude_end_yaml}
```

### Codex
```yaml
{codex_end_yaml}
```

### Agreement / Disagreement
- Cross-model agreement: …
- Claude-only: …
- Codex-only: …

---

## 4. Synthesis (Main — Claude orchestrator)

### Tier 1 — Cross-model agreements (highest confidence)
Both engines flagged the same issue in the same lens. Label: `[cross-model/<lens>]`.

| # | lens | locus | problem | severity (union, conservative = higher) |
|---|---|---|---|---|

### Tier 2 — Single-engine, multi-lens (same engine caught in 2+ lenses)
Label: `[claude/multi-lens]` or `[codex/multi-lens]`.

### Tier 3 — Singletons (one engine, one lens)
Label: `[claude/<lens>]` or `[codex/<lens>]`. Lower confidence; include for breadth.

### Rejected / Conflicting
Engines gave contradictory advice in the same lens. Main surfaces both sides + picks a side with one-line rationale.

---

## 5. Decision Log

| # | tier | decision | reason |
|---|---|---|---|
| 1 | cross-model | ACCEPT | — |
| 2 | singleton | DEFER | round {N+1}로 이월 |

---

## 6. Applied Changes (md + --apply 사용 시에만)

### Diff summary
- `<file>`: +{added} / -{removed}

### Key diffs
```diff
- ...
+ ...
```

(코드 입력 또는 --apply 미사용 시 생략 또는 "N/A — read-only".)

---

## 7. Engine invocation log

| engine | lens | prompt_bytes | response_bytes | duration_s | status |
|---|---|---|---|---|---|
| claude | llm | - | - | - | ok |
| claude | architect | - | - | - | ok |
| claude | enduser | - | - | - | ok |
| codex  | llm | - | - | - | ok |
| codex  | architect | - | - | - | ok |
| codex  | enduser | - | - | - | ok |

Fallbacks:
- claude 실패 시: 해당 관점 섹션 상단에 `[fallback: claude-unavailable — codex-only for this lens]`
- codex 실패 시: 해당 관점 섹션 상단에 `[fallback: codex-unavailable — claude-only for this lens]`
- 한 lens에서 둘 다 실패: 라운드 invalid, 사용자에게 중단 옵션 제시

---

## 8. Carryover to Round {N+1}

- Tier 1 cross-model 중 ACCEPT 후 반영 대기
- Tier 3 singleton 중 DEFER
- 새 open_questions

종결 조건 충족 시 이 섹션 대신 **"CONSENSUS REACHED — see CONSENSUS.md"**.
