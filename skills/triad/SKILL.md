---
name: triad
user-invocable: true
argument-hint: "<file> [--apply|--apply=original] | --continue <slug> | --stop <slug>"
description: 3-perspective deliberation on one document or code file - LLM clarity, architecture longevity, end-user 5-min understanding. Multi-round convergence until consensus; hard cap 5. Code is read-only; markdown writes to updated.md unless --apply=original. Use over /review-all when you need audit trail + convergence delta + write-discipline; /review-all for one-shot checks.
---

# Triad - 3-Perspective Deliberation

> Triad는 문서/코드 **하나**를 3 관점으로 숙의하고 라운드별로 파일에 누적한다.
> 코드는 절대 수정하지 않는다. md는 `--apply`로 `updated.md`를 생성하고, 원본 교체는 `--apply=original`일 때만 수행한다.

## When to use - differentiation matrix

> `/triad` is NOT "same as /review-all but three agents" - it's a different tool with different artifacts. Pick the right one:

| 상황 | 도구 | 이유 |
|------|------|------|
| 문서가 6개월 이상 살 예정 + AI가 읽을 예정 + 감사 기록 필요 | **`/triad`** | 다라운드 convergence, state.json, 고정 3 lens, updated.md write discipline |
| 한 번 훑고 끝, 복잡한 기록 불필요 | `/review-all` | 4-agent 병렬 + 즉시 synthesis, 가벼움 |
| 약점만 빠르게 보고 싶음 | `/review-devil` | Devil's Advocate 단독, 1 agent |
| 코드 파일을 실제로 수정해야 함 | `/mangchi` (code) | Claude↔Codex 적대적 반복 편집 |

**Cost envelope** (typical):
- 2 라운드에 수렴 → 6 agent calls, ~60-90초, Claude 토큰만 (Codex 안 씀).
- 최악: R5 cap → 15 calls. Review-all(4 calls) 대비 **3-4배 비용**.
- 비용 민감하면 `/review-all` 먼저 돌리고 불만족일 때만 `/triad`.

## 핵심 가치

| 관점 | 고정 질문 |
|---|---|
| **LLM** | 미래의 Claude가 이 자료를 읽고 **틀리지 않게 행동**할 수 있는가? |
| **Architect** | 1년 뒤에도 유지될 설계인가? 결합도/책임 경계는? |
| **EndUser** | 처음 본 사람이 **5분 안에** 무엇/왜/어떻게를 답할 수 있나? |

이 3 렌즈는 고정이다. 추가/교체 금지 (다른 관점이 필요하면 별도 skill로).

## 트리거

- `/triad <file>` - read-only (원본 불변, `updated.md` 초안 생성)
- `/triad <file> --apply` - md 대상이면 `updated.md`를 명시적으로 생성/갱신 (원본은 여전히 불변)
- `/triad <file> --apply=original` - md 대상일 때만 원본 파일까지 Edit으로 반영 (가장 공격적). 코드는 항상 무시.
- `/triad --continue <slug>` - 기존 토론 이어가기 (round-N+1)
- `/triad --stop <slug>` - 강제 종결
- 자연어: "triad로 검토해줘", "3관점으로 봐줘"

## 입력 유형과 수정 권한

| 입력 | read-only 기본 | `--apply` 효과 | `--apply=original` 효과 |
|---|---|---|---|
| `.md` | 원본 불변, updated.md 없음 | updated.md 생성/갱신, 원본 여전히 불변 | updated.md + 원본 Edit 반영 |
| `.py`/`.js`/기타 코드 | 원본 불변 | **무시 (경고)** | **무시 (경고)** |

**불변식**: 코드 파일은 어떤 플래그와도 수정되지 않는다. 이 계약은 깨지지 않는다.

슬러그 규칙: 파일명의 확장자 제거 + 공백/특수문자 `-`로 치환.
예: `docs/design/architecture.md` → slug=`architecture`
예: `src/api/handlers.py` → slug=`handlers-py`

## 7단계 워크플로우

### Phase 0: 초기화 (메인)
- 입력 파일 존재 확인
- 슬러그 계산, 출력 디렉토리 생성
- `source.md` 또는 `source-snapshot.md`로 원본 스냅샷 저장
- `state.json` 생성: `{round: 1, status: "open", started_at, target_file}`

### Phase 1: 병렬 스폰 (메인 → 3 서브에이전트)
**중요**: 3 에이전트를 **동시**에 `Agent` tool로 스폰. 서로의 응답을 못 보게 **독립**하게. 그룹싱크 방지.

각 에이전트에게 전달:
- 해당 관점 프롬프트 (`agents/<perspective>.md` 내용)
- 원본 파일 내용
- 지난 라운드들의 CONSENSUS 섹션 (round ≥ 2일 때만)

각 에이전트 답변 포맷 강제:
```yaml
verdict: PASS | REVISE | BLOCK
top_issues:
  - severity: high | med | low
    locus: "파일:줄 또는 섹션명"
    problem: "..."
    proposed_fix: "..."
open_questions:
  - "메인에게 되물을 것"
```

라운드당 에이전트별 high-severity 상한 **3개**. 장광설 방지.

### Phase 2: 합성 (메인)
`round-N.md` 작성. 템플릿: `templates/round.md`.

섹션 순서:
1. 각 관점 답변 원문
2. 메인의 쟁점 합성 (중복 제거, 우선순위)
3. 이번 라운드 decision log (ACCEPT/REJECT/DEFER 각 이슈별 한 줄 이유)
4. `--apply` 사용 시 적용한 diff 스니펫
5. 다음 라운드로 이월할 open issues

### Phase 3: 반영 판단 (메인)
기본 원칙: **메인은 권고만 누적** (`round-N.md`). `updated.md`는 `--apply`가 명시되었을 때만 생성. 원본 파일은 `--apply=original`이 있을 때만 Edit. 코드는 항상 read-only.

| 입력 유형 | 플래그 | 동작 |
|---|---|---|
| 코드 | (모든 플래그) | 원본 불변. `RECOMMENDATIONS.md`에 권고만 누적. |
| md | 플래그 없음 | 원본 불변. `updated.md` 생성 안 함 (권고만 `round-N.md`에) |
| md | `--apply` | 원본 불변. ACCEPT 이슈를 반영한 **`updated.md`** 생성/갱신. 이동은 사용자가 수동. |
| md | `--apply=original` | 위 + 원본 md도 Edit으로 반영. 각 diff를 `round-N.md`에 기록. |

이 정책으로 사용자가 "실수로 문서 덮어씌워짐"을 만나지 않는다.

### Phase 4: 종결 판정 (메인)
**종결 조건 AND** (둘 다 만족해야 종결):
1. 3 관점 모두 `verdict: PASS` (이번 라운드)
2. 메인의 open_questions 리스트 = 빈 배열

**강제 종결**:
- round 5 도달 (hard cap)
- 사용자 명시 `/triad --stop`

**종결 시**: `CONSENSUS.md` 작성 (`templates/consensus.md`). 코드 입력이면 `RECOMMENDATIONS.md`도 최종화.

### Phase 5: 다음 라운드 or 종료
- 종결 미충족 → round N+1 진입. `state.json` 업데이트. 남은 쟁점만 다음 라운드 입력으로.
- 종결 충족 → `state.json` status="closed", 완료 메시지.

## Round-Delta 원칙 (MUST)

라운드 N의 입력은 **지난 라운드에서 해소 안 된 쟁점 + 원본**. 이미 합의된 건 재논의 금지. 이걸 지켜야 파일이 안 불어나고 수렴이 가시적임.

## 서브에이전트 호출 규약

`Agent` tool, `subagent_type: "general-purpose"`. 3 에이전트를 **한 메시지 안에서 병렬** 호출 (독립 tool_use 블록 3개).

각 에이전트에게 줄 prompt 템플릿:
```
[이 파일 내용을 읽고 <관점>으로만 평가하라]

## 너의 관점 정의
<agents/<perspective>.md 전체>

## 대상 파일: <path>
<파일 전체 내용 또는 필요한 부분>

## 지난 라운드 합의 (round >= 2만)
<CONSENSUS 누적>

## 출력 포맷
Phase 1의 YAML 포맷을 그대로 준수 (verdict/top_issues/open_questions).
```

### Fallback - 서브에이전트 사용 불가 시

`Agent` tool이 실패하거나 해당 관점 스폰이 불가한 경우:
1. 메인 에이전트가 **해당 관점 프롬프트를 직접 읽고** local pass로 대체.
2. `round-N.md`의 해당 관점 섹션 상단에 **`[fallback: main-local-pass]`** 태그 표시.
3. `state.json`의 `rounds[N].fallbacks` 배열에 관점 이름 추가.
4. 같은 라운드에서 3 관점 중 2개 이상 fallback이면 **해당 라운드를 invalid 처리**하고 사용자에게 경고 후 중단 옵션 제시.

이 정책으로 tool 장애가 조용히 품질 저하로 이어지는 것을 방지.

## 파일 구조

```
docs/discussion/
├── <slug>/                          # md 입력
│   ├── source.md                    # 원본 스냅샷 (불변)
│   ├── state.json
│   ├── round-1.md
│   ├── round-2.md
│   ├── ...
│   ├── CONSENSUS.md
│   └── updated.md                   # --apply 이상에서만 생성. 원본은 --apply=original에서만 교체.
│
└── code/<slug>/                     # 코드 입력
    ├── source-snapshot.md
    ├── state.json
    ├── round-N.md
    ├── CONSENSUS.md
    └── RECOMMENDATIONS.md           # pumasi tasks 호환 포맷
```

## 참조

- Agent prompts: `agents/llm-perspective.md`, `agents/architect-perspective.md`, `agents/enduser-perspective.md`
- Templates: `templates/round.md`, `templates/consensus.md`, `templates/recommendations.md`
- Usage examples: `references/usage.md`

## 안티패턴

- ❌ 3 에이전트를 순차 호출 (그룹싱크 위험 증가 + 느림) - **반드시 병렬**
- ❌ 코드 파일을 `--apply`/`--apply=original`로 수정 시도 - 항상 거부, 경고 후 read-only 진행
- ❌ `--apply` 플래그 없이 원본 md Edit - 정책 위반
- ❌ fallback 표시 없이 local pass로 대체 - 품질 저하가 조용히 숨음
- ❌ round-N.md에 이미 해소된 쟁점 재수록 - round-delta 위반
- ❌ 에이전트 프롬프트에 "다른 관점도 봐라" 추가 - 렌즈 혼탁
- ❌ 5 라운드 초과 진입 - hard cap 위반, 종결 강제

## GSD와의 관계

triad는 `/gsd-discuss-phase`, `/gsd-review`, `/gsd-code-review`와 다른 축:
- GSD = phase/work unit 기반, one-shot
- triad = 단일 파일, 다라운드 수렴, 고정 3 렌즈

GSD phase 내부에서 특정 산출물(PLAN.md, UI-SPEC.md)을 triad로 재검토 가능. 병용 OK.
