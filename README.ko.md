# triad

> Language: [English](README.md) · **한국어**

**하나의 문서를 고정된 3 관점으로, 세 관점이 모두 합의할 때까지 돌린다.**

문서는 "괜찮아 보인다" 승인으로 나가고 3주 뒤에 비로소 문제가 터진다 — AI 에이전트가 파싱 못 하거나, 아키텍처가 빨리 낡거나, 새 인력이 5분 안에 파악을 포기한다. triad는 단일 파일을 3 독립 렌즈로 병렬 리뷰하고 세 관점이 전부 PASS 할 때까지 숙의한다.

```
/triad <file>                  -> 읽기 전용 합의 (CONSENSUS.md)
/triad <file> --apply          -> md: updated.md 생성 (원본 불변)
/triad <file> --apply=original -> md: 원본도 Edit
/triad <code.py>               -> 거부: 문서 전용 (코드는 /prism 또는 /mangchi)
```

3 서브에이전트, 3 편향 (LLM 명확성 / 아키텍처 수명 / 엔드유저 이해도), 1 오케스트레이터. 라운드 N은 N-1의 미해결 쟁점만 이어받는다. Hard cap 라운드 5. **0.2.0부터 문서 전용** — 코드 파일은 `/prism`(리뷰) 또는 `/mangchi`(반복 수정)로 안내한다.

---

## 30초 데모

**triad 없이:**

디자인 문서를 쓰고, 리뷰어 한 명이 "괜찮아 보인다" 해서 commit. 3주 뒤: (a) 그 문서를 읽은 AI 에이전트가 혼란스러워하며 엉뚱한 기능을 구현, (b) 아키텍처 선택이 나중에 자충수가 됨, (c) 새 인력이 문서 의미 파악하는 데 15분 걸림.

**triad로:**

`/triad docs/features/billing.md`. 3개의 독립 에이전트가 고정 렌즈로 문서를 병렬 리뷰한다 — LLM 명확성, 아키텍처 수명, 엔드유저 5분 이해도. 세 관점이 모두 합의하거나 라운드 5 cap 도달할 때까지 반복. 합의는 원본을 건드리지 않고 `updated.md`에 기록.

## 누가 써야 하는가

- **프로젝트 지시 문서** (`CLAUDE.md`, 에이전트 프롬프트, 온보딩 문서) — AI도 읽기 때문에 LLM 렌즈가 특히 가치
- **ADR** (Architecture Decision Record) — commit 전에 3각도에서 선택을 검증
- **공개 문서** (README, getting-started, API) — endUser 렌즈가 "처음 읽는 사람이 조용히 포기하는 지점"을 잡아냄
- **PR 올리기 전** — 변경 근거에 대한 3자 독립 검토

## 자매 도구 (같은 마켓플레이스)

- **[ddaro](https://github.com/minwoo-data/ddaro)** — worktree 기반 병렬 Claude Code 세션 + 안전한 merge.
- **[prism](https://github.com/minwoo-data/prism)** — 증거 기반 5-렌즈 코드 리뷰 (1회성). **코드는 이걸로**; triad는 문서용.
- **[mangchi](https://github.com/minwoo-data/mangchi)** — Claude + Codex cross-review로 파일 반복 다듬기.

---

## Quick Start

### 1. haroom_plugins 마켓플레이스 등록 (처음 한 번)

```
/plugin marketplace add https://github.com/minwoo-data/haroom_plugins.git
```

`triad` 는 haroom 플러그인 (ddaro, prism, mangchi) 과 함께 **haroom_plugins** aggregator 마켓플레이스를 통해 배포됩니다.

### 2. 설치

```
/plugin install triad
```

### 3. 사용

```
/triad docs/features/billing.md          # 3 렌즈 검토, read-only
/triad docs/features/billing.md --apply  # updated.md 추가 생성
/prism src/routes/auth.py                # 코드는 triad가 아니라 prism (수정은 /mangchi)
```

설치/업데이트 후 Claude Code **재시작**.

---

## 이 플러그인이 제공하는 3 variant

`triad` 플러그인을 설치하면 같은 3-렌즈 프레임워크를 공유하되 **판단 주체가 다른** 3 skill이 함께 들어옵니다:

| Skill | 엔진 | 언제 쓰나 |
|---|---|---|
| `/triad` | **Claude 서브에이전트 3** 병렬 | 기본. Wall-time 가장 빠름, 외부 CLI 불필요. |
| `/triad-codex` | **Codex CLI 3** 순차 (gpt-5.5) | Claude 토큰 절약 / 다른 모델 관점 필요. `codex-cli >= 0.125.0` 필수. |
| `/triad-all` | **Claude 3 + Codex 3 = 6 병렬** | 최고 신뢰. 같은 렌즈에서 두 엔진이 모두 flag한 이슈는 Tier 1로 승급 — 단일 엔진으로는 만들 수 없는 신호. 둘 다 필수. |

세 variant 전부 한 번의 플러그인 설치에 포함. Codex CLI 전제 상세: [`docs/codex-5.4-to-5.5.md`](docs/codex-5.4-to-5.5.md) (구버전 CLI에서 나오는 "model does not exist" 에러는 계정 문제가 아니라 버전 문제).

---

## 3 관점 (고정 질문)

| 관점 | 질문 |
|---|---|
| **LLM 가독성** | 미래의 AI 에이전트가 이 자료를 읽고 틀리지 않게 행동할 수 있는가? |
| **아키텍트** | 1년 뒤에도 유지될 설계인가? 결합도·책임 경계가 명확한가? |
| **엔드유저** | 처음 본 사람이 5분 안에 *무엇*/*왜*/*어떻게*를 답할 수 있는가? |

각 서브에이전트는 YAML로 답변. 라운드당 **관점별 `severity: high` 최대 3개** — 장황한 비판 방지.

## 어떻게 작동하나

```
┌─ 메인 에이전트 (Claude) ──────────────────────┐
│  대상 파싱 → 3 서브에이전트 병렬 스폰         │
│  합성 → 반영(md만) → 다음 라운드              │
└──────────────────────────────────────────────┘
          ↓ (병렬, 독립)
   ┌──────────────┬──────────────┬──────────────┐
   ↓              ↓              ↓
┌──────────┐  ┌──────────┐  ┌──────────┐
│   LLM    │  │아키텍트   │  │ 엔드유저  │
│   관점   │  │   관점    │  │   관점    │
└──────────┘  └──────────┘  └──────────┘
```

각 에이전트는 forked context에서 실행 — 메인 대화가 오염되지 않음. 에이전트끼리 서로의 응답을 볼 수 없음 — groupthink 방지.

## Features

- **Round-delta** — 라운드 N은 N-1의 미해결 쟁점만 본다. 해결된 항목은 재논의 금지. 합의 파일이 부풀지 않음.
- **명시적 수정 권한** — 원본은 `--apply=original`일 때만 수정, `--apply`는 옆에 `updated.md`만 생성. 코드 파일은 받지 않음 (0.2.0+).
- **Fork 격리** — 서브에이전트끼리 서로의 답을 못 봄 → agreement가 echo가 아닌 독립 signal.
- **명시적 Fallback 태그** — 서브에이전트가 크래시 시 메인이 local pass 수행 + 라운드에 `[fallback: main-local-pass]` 태그. 품질 저하가 조용히 숨지 않음.
- **자연 종결** — 3 PASS **AND** open_questions 빈 배열. 하나라도 어긋나면 다음 라운드. Hard cap 라운드 5.

---

## 입력 유형과 수정 권한

| 입력 | 기본 | `--apply` | `--apply=original` |
|---|---|---|---|
| `.md` / `.mdx` / `.txt` / `.rst` (문서) | 원본 불변 | `updated.md` 생성, 원본 여전히 불변 | `updated.md` + 원본 Edit |
| `.py`/`.js`/`.ts`/코드 | **거부** | 거부 | 거부 |

**코드 파일은 받지 않는다 (0.2.0+).** triad는 `/prism <file>`(증거 기반 리뷰) 또는 `/mangchi <file>`(반복 수정)로 안내하는 한 줄만 출력하고 종료한다. 이유: 코드 대상에서 Architect 렌즈는 mangchi의 `design` 축, prism의 Testability 렌즈와 같은 질문을 하므로 중복 도구였다. 입력 유형별 경로 하나: 문서 → triad, 코드 → prism/mangchi.

## 종결 조건

다음 중 하나:

1. 3 관점 모두 `verdict: PASS` **AND** 메인의 open_questions 빈 배열
2. 라운드 5 도달 (hard cap)
3. 사용자 `/triad --stop <slug>`

## 산출 파일

```
docs/discussion/<slug>/
├── source.md              # 라운드 1 시작 시 입력 스냅샷
├── state.json             # 라운드, 상태, 결정 로그
├── round-1.md             # 3 관점 + 메인 합성 + diff (반영 시)
├── round-2.md             # 미해결 쟁점만 이어짐
├── ...
├── CONSENSUS.md           # 최종 결정 + 반대 의견 보존
└── updated.md             # --apply 사용 시에만 (md 입력)
```

`/triad-codex`와 `/triad-all`은 각각 `docs/discussion/codex-md/<slug>/`, `docs/discussion/all-md/<slug>/`에 기록. (0.1.x의 `docs/discussion/code/<slug>/` 트리와 `RECOMMENDATIONS.md`는 코드 입력 지원과 함께 제거.)

---

## 사용 예시

```
/triad docs/features/billing.md
# → 3 서브에이전트 병렬 스폰 (LLM/Architect/EndUser)
# → 라운드 1: 2개 REVISE, 1개 BLOCK. 5개 open 이슈 다음 라운드로.

/triad --continue billing
# → 라운드 2: 입력 = 미해결 쟁점 + 원본. 해결된 건 빠짐.
# → 라운드 2: 1개 REVISE, 2개 PASS. 1개 남음.

/triad --continue billing --apply
# → 라운드 3: 전부 PASS, open_questions = []. 합의 도달.
# → updated.md 작성, 원본 billing.md 불변.

cat docs/discussion/billing/CONSENSUS.md
# → 라운드별 결정 + 보존된 반대의견

cat docs/discussion/billing/updated.md
# → 반영본. 만족스러우면 수동으로 docs/features/billing.md로 이동
```

### 코드 파일? 여기선 안 받음

```
/triad src/routes/auth.py
# → "triad는 문서 전용입니다. 코드 리뷰는 /prism <file>, 반복 수정은 /mangchi <file> 을 쓰세요."
```

### Cross-model 모드

```
/triad-all docs/features/billing.md
# → Claude 서브에이전트 3 + Codex CLI 3 병렬
# → Tier 1: 두 엔진이 같은 렌즈에서 flag한 이슈
# → Tier 2: 한 엔진의 여러 렌즈가 잡은 이슈
# → Tier 3: singleton (한 엔진 한 렌즈만)
# → codex-cli >= 0.125.0 필요 (docs/codex-5.4-to-5.5.md 참조)
```

---

## 업데이트

```
/plugin update
```

설치 후 Claude Code 재시작.

---

## 트러블슈팅

### 설치 후 `/triad`가 안 보임

플러그인은 Claude Code 시작 시점에 로드됩니다.

1. **Claude Code 재시작** — 설치/업데이트 때마다 필수.
2. `/plugin` 실행, `triad`가 **enabled** 상태인지 확인.
3. disabled면 활성화: `/plugin enable triad@haroom_plugins`.
4. 여전히 안 보임? `~/.claude.json`의 `enabledPlugins`에 `triad` 항목 있는지 확인. `{}`면 설치가 안 된 것 — 재설치.

### `/triad-codex` 또는 `/triad-all`이 "model does not exist" 에러

계정 문제가 아니라 **Codex CLI 버전 문제**. 업그레이드:

```
npm install -g @openai/codex@latest
codex --version   # >= 0.125.0 이어야 함
```

상세: [`docs/codex-5.4-to-5.5.md`](docs/codex-5.4-to-5.5.md).

### 서브에이전트가 라운드 중에 크래시

메인이 자동으로 local pass로 대체하고 라운드에 `[fallback: main-local-pass]` 태그 기록. 라운드는 유효하지만 표시됨. 같은 라운드에 2+ 렌즈가 fallback이면 중단하고 조사 (보통 prompt 길이 문제 — 더 작은 target 시도).

---

## Requirements

- Claude Code (`/plugin` 명령 있는 버전) — general-purpose 서브에이전트 스폰
- *(선택 — `/triad-codex`, `/triad-all`에만)* [Codex CLI](https://github.com/openai/codex) `>= 0.125.0`
- Windows (Git Bash / WSL2), macOS, Linux 지원

기본 `/triad`는 외부 CLI 없이 Claude Code 안에서 완결.

---

## 검증 근거

실제 프로젝트 검토 결과는 [`skills/triad/CASE-STUDIES.md`](skills/triad/CASE-STUDIES.md). 관점별 채택률, 중복 분석, 솔직한 한계 포함.

## 철학

서로의 응답을 볼 수 없는 세 리뷰어가 고정 질문으로 한 파일을 합의 또는 cap까지 숙의한다. Round-delta 원칙으로 문서가 짧게 유지됨 — 한 번 합의된 건 그대로 남는다. 문서 전용이다. 코드는 `/prism`(리뷰)이나 `/mangchi`(수정)로.

## 업데이트 기록

- **2026-04-24** — Codex CLI `gpt-5.4` → `gpt-5.5` 마이그레이션 기록 ([docs/codex-5.4-to-5.5.md](docs/codex-5.4-to-5.5.md)). 새 자매 skill `/triad-codex`, `/triad-all` 추가 — 같은 프레임워크, 다른 엔진. "model does not exist" 에러를 계정 문제로 단정하기 전에 읽어보세요.

## 라이선스

MIT — [`LICENSE`](LICENSE) 참조.

## Author

haroom — [github.com/minwoo-data](https://github.com/minwoo-data)

## Contributing

Issues와 PR 환영: [github.com/minwoo-data/triad](https://github.com/minwoo-data/triad).
