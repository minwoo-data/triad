---
name: triad
user-invocable: true
argument-hint: "<file> [--apply|--apply=original] | --continue <slug> | --stop <slug>"
description: 3-perspective deliberation on one markdown/document file - LLM clarity, architecture longevity, end-user 5-min understanding. Multi-round convergence until consensus; hard cap 5. Documents only (code → /prism or /mangchi). Writes to updated.md unless --apply=original. Use over /prism when you need audit trail + convergence delta + write-discipline.
---

# Triad - 3-Perspective Deliberation

> Triad는 **문서(markdown) 하나**를 3 관점으로 숙의하고 라운드별로 파일에 누적한다.
> 코드 파일은 받지 않는다 (코드 리뷰는 `/prism`, 반복 수정은 `/mangchi`). md는 `--apply`로 `updated.md`를 생성하고, 원본 교체는 `--apply=original`일 때만 수행한다.

## When to use - differentiation matrix

> `/triad` is NOT "same as /prism but three agents" - it's a different tool for a different input type. Pick the right one:

| 상황 | 도구 | 이유 |
|------|------|------|
| **문서**가 6개월 이상 살 예정 + AI가 읽을 예정 + 감사 기록 필요 | **`/triad`** | 다라운드 convergence, state.json, 고정 3 lens, updated.md write discipline |
| 코드 파일 결함 리뷰 (one-shot, 증거 기반) | `/prism` | 5 defect 렌즈 병렬 + Evidence pass |
| 코드 파일, 크로스모델 신뢰 필요 | `/prism-all` | Claude 5 + Codex 5 |
| 코드 파일을 실제로 수정해야 함 | `/mangchi` | Claude↔Codex 적대적 반복 편집 |
| 설계 문서가 **맞는지** (기존 코드와 충돌, 문서의 코드 주장 검증, 실패 모드) | `/prism <doc>` | design 렌즈셋 (prism ≥0.3.1). triad는 문서가 **잘 쓰였는지**를 본다. `/ddaro:review`는 둘 다 돌린다 |

**Cost envelope** (typical):
- 2 라운드에 수렴 → 6 agent calls, ~60-90초, Claude 토큰만 (Codex 안 씀).
- 최악: R5 cap → 15 calls. `/prism` 1회(5 discovery + evidence) 대비 **2-3배 비용**.
- 문서가 아니라 코드라면 triad가 아니라 `/prism`이 맞는 도구다 - 비용과 무관하게.

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
| `.md` / `.mdx` / `.txt` / `.rst` 등 문서 | 원본 불변, updated.md 없음 | updated.md 생성/갱신, 원본 여전히 불변 | updated.md + 원본 Edit 반영 |
| `.py`/`.js`/`.ts`/기타 코드 | **거부** | 거부 | 거부 |

**코드 입력 거부 (v0.2.0+)**: 대상이 코드 파일이면 라운드를 시작하지 않고 아래 한 줄만 출력하고 종료한다.

```
triad는 문서 전용입니다. 코드 리뷰는 /prism <file> (결함 탐지, 증거 기반), 반복 수정은 /mangchi <file> 을 쓰세요.
```

이유: 코드 대상에서 Architect 관점은 `/mangchi`의 design 축, `/prism`의 Testability 렌즈와 같은 질문을 하므로 중복 도구가 된다. 문서는 triad, 코드는 prism/mangchi로 경로를 하나씩만 둔다.

슬러그 규칙: 파일명의 확장자 제거 + 공백/특수문자 `-`로 치환.
예: `docs/design/architecture.md` → slug=`architecture`
예: `docs/adr/0003 auth model.md` → slug=`0003-auth-model`

## 7단계 워크플로우

### Phase 0: 초기화 (메인)
- 입력 파일 존재 확인
- **문서 파일인지 확인** - 코드 확장자면 거부 메시지 출력 후 종료 (§입력 유형)
- 슬러그 계산, 출력 디렉토리 생성
- `source.md`로 원본 스냅샷 저장
- `state.json` 생성: `{round: 1, status: "open", started_at, target_file}`

### Phase 1: 병렬 스폰 (메인 → 3 서브에이전트)
**중요**: 3 에이전트를 **동시**에 `Agent` tool로 스폰. 서로의 응답을 못 보게 **독립**하게. 그룹싱크 방지.

각 에이전트에게 전달 (**이 순서로** - 아래 호출 규약 참조):
- 원본 파일 내용 (3 에이전트 공통 - 맨 앞)
- 지난 라운드들의 CONSENSUS 섹션 (round ≥ 2일 때만, 공통)
- 해당 관점 프롬프트 (`agents/<perspective>.md` 내용 - 에이전트별로 다른 부분은 맨 뒤)

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
기본 원칙: **메인은 권고만 누적** (`round-N.md`). `updated.md`는 `--apply`가 명시되었을 때만 생성. 원본 파일은 `--apply=original`이 있을 때만 Edit.

| 플래그 | 동작 |
|---|---|
| 플래그 없음 | 원본 불변. `updated.md` 생성 안 함 (권고만 `round-N.md`에) |
| `--apply` | 원본 불변. ACCEPT 이슈를 반영한 **`updated.md`** 생성/갱신. 이동은 사용자가 수동. |
| `--apply=original` | 위 + 원본 md도 Edit으로 반영. 각 diff를 `round-N.md`에 기록. |

이 정책으로 사용자가 "실수로 문서 덮어씌워짐"을 만나지 않는다.

### Phase 4: 종결 판정 (메인)
**종결 조건 AND** (둘 다 만족해야 종결):
1. 3 관점 모두 `verdict: PASS` (이번 라운드)
2. 메인의 open_questions 리스트 = 빈 배열

**강제 종결**:
- round 5 도달 (hard cap)
- 사용자 명시 `/triad --stop`

**종결 시**: `CONSENSUS.md` 작성 (`templates/consensus.md`).

### Phase 5: 다음 라운드 or 종료
- 종결 미충족 → round N+1 진입. `state.json` 업데이트. 남은 쟁점만 다음 라운드 입력으로.
- 종결 충족 → `state.json` status="closed", 완료 메시지.

## Round-Delta 원칙 (MUST)

라운드 N의 입력은 **지난 라운드에서 해소 안 된 쟁점 + 원본**. 이미 합의된 건 재논의 금지. 이걸 지켜야 파일이 안 불어나고 수렴이 가시적임.

## 서브에이전트 호출 규약

`Agent` tool, `subagent_type: "general-purpose"`. 3 에이전트를 **한 메시지 안에서 병렬** 호출 (독립 tool_use 블록 3개).

각 에이전트에게 줄 prompt 템플릿 (**대상 문서를 맨 앞에**, 관점 정의를 맨 뒤에):
```
[아래 대상 파일을 읽고, 마지막에 주어지는 관점으로만 평가하라]

## 대상 파일: <path>
<파일 전체 내용>

## 지난 라운드 합의 (round >= 2만)
<CONSENSUS 누적>

## 너의 관점 정의
<agents/<perspective>.md 전체>

## 출력 포맷
Phase 1의 YAML 포맷을 그대로 준수 (verdict/top_issues/open_questions).
```

순서 이유: 3 에이전트 프롬프트에서 공통인 부분(대상 문서 + 지난 합의)이 앞에 오고 에이전트별로 다른 부분(관점)이 뒤에 오면, 공통 prefix가 프롬프트 캐시에 걸려 3콜 중 2콜의 입력 토큰 비용이 크게 줄어든다. 관점을 앞에 두면 첫 토큰부터 달라져 캐시가 전혀 적중하지 않는다.

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
└── <slug>/
    ├── source.md                    # 원본 스냅샷 (불변)
    ├── state.json
    ├── round-1.md
    ├── round-2.md
    ├── ...
    ├── CONSENSUS.md
    └── updated.md                   # --apply 이상에서만 생성. 원본은 --apply=original에서만 교체.
```

(v0.1.x의 `docs/discussion/code/<slug>/` 트리와 `RECOMMENDATIONS.md`는 코드 입력 폐기와 함께 제거됨. 기존 디렉토리는 그대로 두되 `--continue`는 문서 세션에만 적용.)

## 참조

- Agent prompts: `agents/llm-perspective.md`, `agents/architect-perspective.md`, `agents/enduser-perspective.md`
- Templates: `templates/round.md`, `templates/consensus.md`
- Usage examples: `references/usage.md`

## 안티패턴

- ❌ 3 에이전트를 순차 호출 (그룹싱크 위험 증가 + 느림) - **반드시 병렬**
- ❌ 코드 파일을 입력으로 받아 라운드 진행 - 거부 메시지 후 종료 (`/prism`, `/mangchi`로 안내)
- ❌ 관점 정의를 프롬프트 맨 앞에 배치 - 공통 prefix(대상 문서) 먼저, 관점은 마지막
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
