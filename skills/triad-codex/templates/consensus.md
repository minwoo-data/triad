# CONSENSUS (triad-codex)

**Target**: `{target_file}`
**Input type**: {md | code}
**Engine**: codex ({codex_version})
**Started**: {start_timestamp}
**Closed**: {end_timestamp}
**Rounds consumed**: {N} / 5
**Termination reason**: {all_pass | max_rounds | user_stop | codex_unavailable}

---

## 1. 합의된 결정 (Final)

각 bullet은 **어느 라운드에서 결정**됐는지 명시.

- [R1] 결정 내용 1
- [R2] 결정 내용 2

## 2. 적용된 변경 (md + --apply 경우만)

- `updated.md` 생성 여부: {yes | no}
- 원본 대비 변경 요약: +{added} / -{removed} lines
- 주요 diff는 각 라운드 파일 참조.

## 3. 각 관점의 최종 의견 (Codex)

### LLM
- 최종 verdict: PASS
- 남은 미세 제안 (non-blocking): ...

### Architect
- 최종 verdict: PASS
- 남은 미세 제안 (non-blocking): ...

### EndUser
- 최종 verdict: PASS
- 남은 미세 제안 (non-blocking): ...

## 4. 보존되는 반대의견 (Dissent)

합의는 이뤘으나 특정 관점이 trade-off로 남긴 반대. 반대의견 없으면 "없음".

## 5. 타임라인

| round | duration | codex_calls | main_outcome |
|---|---|---|---|
| R1 | {mm:ss} | 3 | {summary} |
| R2 | {mm:ss} | 3 | {summary} |

## 6. Downstream Hooks

- **코드 입력**이었다면: 이 CONSENSUS.md → 직접 구현 입력
- **md 입력**이었다면: `updated.md`가 최신본 (`--apply` 사용 시)
