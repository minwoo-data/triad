# CONSENSUS (triad-all)

**Target**: `{target_file}`
**Input type**: {md | code}
**Engines**: Claude + Codex ({codex_model})
**Started**: {start_timestamp}
**Closed**: {end_timestamp}
**Rounds**: {N} / 5
**Termination**: {all_pass | max_rounds | user_stop | dual_fallback}

---

## 1. 합의된 결정 (Final)

각 bullet에 tier + round 명시.

- [R1 / cross-model/llm] …
- [R2 / claude-multi-lens] …
- [R2 / cross-model/architect] …

## 2. Confidence summary

| Tier | Count | What it means |
|---|---|---|
| Cross-model agreement | N | 두 엔진이 같은 렌즈에서 같은 이슈 → 최고 신뢰 |
| Single-engine multi-lens | N | 한 엔진의 2+ 렌즈가 잡음 → 중간 신뢰 |
| Singleton | N | 한 엔진의 한 렌즈만 → 낮은 신뢰, 참고용 |

## 3. 적용된 변경 (md + --apply만)

- `updated.md` 생성 여부: {yes | no}
- +{added} / -{removed} lines

## 4. 각 엔진의 최종 verdict

### Claude
| lens | verdict | 잔여 non-blocking 제안 |
|---|---|---|
| LLM | PASS | … |
| Architect | PASS | … |
| EndUser | PASS | … |

### Codex ({codex_model})
| lens | verdict | 잔여 non-blocking 제안 |
|---|---|---|
| LLM | PASS | … |
| Architect | PASS | … |
| EndUser | PASS | … |

## 5. 보존되는 반대의견 (Dissent)

합의는 이뤘으나 특정 엔진/렌즈가 trade-off로 남긴 반대. 미래 기여자가 뒤집을 때 근거.

- [claude/architect] "A를 B로 바꿨지만, 만약 C 조건이 오면 재검토 필요"
- [codex/llm] "…"

## 6. 타임라인

| round | claude_wall | codex_wall | claude_fallbacks | codex_fallbacks | outcome |
|---|---|---|---|---|---|
| R1 | {s}s | {s}s | [] | [] | … |
| R2 | {s}s | {s}s | [] | [] | … |

## 7. Downstream hooks

- 코드 입력 → `RECOMMENDATIONS.md` 참조
- md 입력 → `updated.md` 최신본 (`--apply` 사용 시)
