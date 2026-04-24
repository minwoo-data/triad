# Round {N}

**Target**: `{target_file}`
**Started**: {timestamp}
**Input type**: {md | code}
**Apply mode**: {true | false}
**Engine**: codex ({codex_version})

---

## 1. LLM Perspective (Codex)

```yaml
{llm_yaml_response}
```

## 2. Architect Perspective (Codex)

```yaml
{architect_yaml_response}
```

## 3. EndUser Perspective (Codex)

```yaml
{enduser_yaml_response}
```

---

## 4. Synthesis (Main — Claude)

### 합의된 쟁점 (dedup + priority)

| # | severity | perspective | locus | problem | proposed_fix |
|---|---|---|---|---|---|
| 1 | high | LLM | ... | ... | ... |
| 2 | med | Architect + EndUser | ... | 두 관점 공통 지적 | ... |

### 충돌하는 제안

- **쟁점**: LLM은 X를 원함, Architect는 Y를 원함
- **판정**: X 채택 (이유: ...)

---

## 5. Decision Log (Main)

| issue # | decision | reason |
|---|---|---|
| 1 | ACCEPT | 다음 섹션에서 반영 |
| 2 | REJECT | 판정 근거 한 줄 |
| 3 | DEFER | round-{N+1}로 이월 |

---

## 6. Applied Changes (md + --apply 사용 시에만)

### Diff summary
- 파일명: +{added} / -{removed} lines

### Key diffs
```diff
- 이전 문장
+ 수정 문장
```

(코드 입력이거나 --apply 미사용 시 이 섹션 생략 또는 "N/A — read-only")

---

## 7. Codex Invocation Log

| lens | prompt_file | response_file | bytes_in | bytes_out | duration_sec | status |
|---|---|---|---|---|---|---|
| llm | round-{N}.llm.prompt.txt | round-{N}.llm.codex.txt | ... | ... | ... | ok/fallback |
| architect | round-{N}.architect.prompt.txt | round-{N}.architect.codex.txt | ... | ... | ... | ok/fallback |
| enduser | round-{N}.enduser.prompt.txt | round-{N}.enduser.codex.txt | ... | ... | ... | ok/fallback |

Fallback 발생 시 각 관점 섹션 상단에 `[fallback: codex-unavailable — main-local-pass]` 태그.

---

## 8. Carryover to Round {N+1}

- DEFER된 이슈 리스트
- 새로 발견된 open_questions

종결 조건 충족 시 이 섹션 대신 **"CONSENSUS REACHED — see CONSENSUS.md"**.
