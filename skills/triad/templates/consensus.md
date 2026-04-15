# CONSENSUS

**Target**: `{target_file}`
**Input type**: {md | code}
**Started**: {start_timestamp}
**Closed**: {end_timestamp}
**Rounds consumed**: {N} / 5
**Termination reason**: {all_pass | max_rounds | user_stop}

---

## 1. 합의된 결정 (Final)

각 bullet은 **어느 라운드에서 결정**됐는지 명시.

- [R1] 결정 내용 1
- [R2] 결정 내용 2
- ...

## 2. 적용된 변경 (md + --apply 경우만)

- `updated.md` 생성 여부: {yes | no}
- 원본 대비 변경 요약: +{added} / -{removed} lines, {섹션수}개 섹션 재작성
- 주요 diff는 각 라운드 파일 참조.

## 3. 각 관점의 최종 의견

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

합의는 이뤘으나 특정 관점이 trade-off로 남긴 반대. 미래 기여자가 이 결정을 뒤집을 때 근거가 됨.

- [Architect] "X를 Y로 바꿨지만, 만약 Z 조건이 오면 다시 검토 필요"
- ...

반대의견 없으면 "없음"으로 기재.

## 5. 타임라인

| round | duration | main outcome |
|---|---|---|
| R1 | {mm:ss} | {summary} |
| R2 | {mm:ss} | {summary} |
| ... | | |

## 6. Downstream Hooks

이 consensus 문서를 어떻게 활용할 수 있는가:

- **코드 입력**이었다면: `RECOMMENDATIONS.md` 참조 → pumasi 또는 직접 구현에 입력
- **md 입력**이었다면: `updated.md`가 최신본 (`--apply` 사용 시). 원본 경로로 이동할지는 사용자 결정.
- GSD phase 내부라면: PLAN.md 또는 해당 phase 산출물에 이 결정 링크.
