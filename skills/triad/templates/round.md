# Round {N}

**Target**: `{target_file}`
**Started**: {timestamp}
**Input type**: {md | code}
**Apply mode**: {true | false}

---

## 1. LLM Perspective

```yaml
{llm_yaml_response}
```

## 2. Architect Perspective

```yaml
{architect_yaml_response}
```

## 3. EndUser Perspective

```yaml
{enduser_yaml_response}
```

---

## 4. Synthesis (Main)

### 합의된 쟁점 (dedup + priority)

| # | severity | perspective | locus | problem | proposed_fix |
|---|---|---|---|---|---|
| 1 | high | LLM | ... | ... | ... |
| 2 | med | Architect + EndUser | ... | 두 관점 공통 지적 | ... |

### 충돌하는 제안

어느 관점이 A를 원하고 다른 관점이 B를 원하는 경우. 메인이 판정 근거를 남긴다.

- **쟁점**: LLM은 X를 원함, Architect는 Y를 원함
- **판정**: X 채택 (이유: ...)

---

## 5. Decision Log (Main)

이슈별 처리 선언. 미기재 금지.

| issue # | decision | reason |
|---|---|---|
| 1 | ACCEPT | 다음 섹션에서 반영 |
| 2 | REJECT | 판정 근거 한 줄 |
| 3 | DEFER | round-{N+1}로 이월 |

---

## 6. Applied Changes (md + --apply 사용 시에만)

### Diff summary
- `docs/design/architecture.md`: +{added} / -{removed} lines

### Key diffs
```diff
- 이전 문장
+ 수정 문장
```

(코드 입력이거나 --apply 미사용 시 이 섹션 생략 또는 "N/A - read-only")

---

## 7. Carryover to Round {N+1}

- DEFER된 이슈 리스트
- 새로 발견된 open_questions

종결 조건 충족 시 이 섹션 대신 **"CONSENSUS REACHED - see CONSENSUS.md"**.
