# 트라이어드 (Triad) - 3-관점 숙의 도구

**Language**: [English](README.md) · **한국어**

**문서를 확정했는데 나중에 AI가 이해 못하거나, 아키텍처가 빨리 낡거나, 새 사용자가 5분 안에 파악 못해서 곤란한 적 있나요?** triad는 하나의 문서를 3개 고정 관점(LLM clarity / architectural longevity / end-user comprehension)에서 세 관점이 모두 합의할 때까지 숙의합니다.

> 하나의 문서 또는 코드 파일을 세 가지 고정 관점(LLM 가독성 / 아키텍트 / 엔드유저)으로 검토합니다. 세 관점이 모두 동의하거나 cap에 도달할 때까지 라운드를 누적합니다.

---

## 30초 데모

**triad 없이:**

디자인 문서를 쓰고, 리뷰어 한 명이 "괜찮아 보인다" 해서 commit. 3주 뒤: (a) 그 문서를 읽은 AI 에이전트가 혼란스러워하며 엉뚱한 기능을 구현, (b) 아키텍처 선택이 나중에 자충수가 됨, (c) 새 인력이 문서 의미 파악하는 데 15분 걸림.

**triad로:**

`/triad docs/features/billing.md`. 3개의 독립 에이전트가 고정 렌즈로 문서를 읽습니다: LLM 명확성, 아키텍처 수명, 5분 내 사용자 이해도. 세 관점이 모두 합의하거나 라운드 5 cap에 도달할 때까지 반복. 합의 결과는 원본을 건드리지 않고 `updated.md`에 기록.

## 누가 써야 하는가

- **프로젝트 지시 문서** (`CLAUDE.md`, 에이전트 프롬프트, 온보딩 문서) - AI도 읽기 때문에 LLM 렌즈가 특히 가치
- **ADR (Architecture Decision Record)** - commit 전에 3각도에서 선택을 검증
- **공개 문서** (README, getting-started, API) - end-user 렌즈가 "처음 읽는 사람이 조용히 포기하는 지점"을 잡아냄
- **코드 파일을 철저히 read-only 리뷰** 하고 싶을 때 - triad는 코드 수정 안 함, `RECOMMENDATIONS.md`만 산출
- **PR 올리기 전** - 변경 근거에 대한 3자 독립 검토

## 자매 도구 (같은 마켓플레이스)

- **[ddaro](https://github.com/minwoo-data/ddaro)** - worktree 기반 병렬 Claude Code 세션 + 안전한 merge.
- **[prism](https://github.com/minwoo-data/prism)** - 5-각도 병렬 코드 리뷰 + singleton 검증 (더 넓게, 1회성).
- **[mangchi](https://github.com/minwoo-data/mangchi)** - Claude + Codex cross-review로 파일 반복 다듬기.

---

## 이런 분을 위한 도구입니다

- **프로젝트 지시 문서**(`CLAUDE.md`, 에이전트 프롬프트, 온보딩 문서)의 품질을 올리고 싶은 분 - LLM 관점이 특히 가치. 이 파일들은 사람뿐 아니라 AI 에이전트도 읽음
- **ADR (Architecture Decision Record)**을 커밋하기 전에 3각도에서 검증하고 싶은 분
- **공개 문서** (README, getting-started, API 문서) - 처음 읽는 사람의 5분 이해도가 중요한 경우
- **코드 파일을 철저히 점검하되 수정은 별도로** 하고 싶은 분 - triad의 코드 모드는 read-only. `RECOMMENDATIONS.md`를 산출
- **PR 올리기 전**, 변경 근거에 대한 3자 독립 검토가 필요한 분

## 이런 작업엔 쓰지 마세요

- **작고 명백한 변경** - 3 병렬 에이전트 오버헤드가 signal 대비 큼
- **일상 버그 수정** - 그냥 고쳐라
- **코드를 반복 개선하고 싶음** - triad는 코드를 절대 수정하지 않음. iterative code refinement가 필요하면 별도 도구 사용
- **창작/산문** - LLM/아키텍트 관점은 지시문이 아닌 글에 대해 할 말이 적음

---

## 어떻게 작동하나요

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

**3 관점의 고정 질문**:

| 관점 | 질문 |
|---|---|
| **LLM 가독성** | 미래의 AI 에이전트가 이 자료를 읽고 틀리지 않게 행동할 수 있는가? |
| **아키텍트** | 1년 뒤에도 유지될 설계인가? 결합도·책임 경계가 명확한가? |
| **엔드유저** | 처음 본 사람이 5분 안에 *무엇*/*왜*/*어떻게*를 답할 수 있는가? |

각 서브에이전트는 YAML로 답변. 라운드당 **관점별 high-severity 최대 3개** - 장황한 비판 방지.

---

## 입력 유형과 수정 권한

| 입력 | 기본 | `--apply` | `--apply=original` |
|---|---|---|---|
| `.md` | 원본 불변, 변경 없음 | `updated.md` 생성/갱신, 원본 여전히 불변 | `updated.md` + 원본 Edit 반영 |
| `.py`/`.js`/코드 | 원본 불변, `RECOMMENDATIONS.md` 산출 | `--apply` 무시 (경고) | `--apply=original` 무시 (경고) |

**코드 파일은 어떤 플래그로도 수정되지 않음.** 이 계약은 깨지지 않음. 코드를 수정하고 싶으면 다른 도구를 써라.

---

## 종결 조건

다음 중 하나라도 충족되면 종결:

1. **3 관점 모두 `verdict: PASS`** AND 메인의 open-questions 리스트가 빔
2. **라운드 5 도달** (hard cap)
3. **사용자 `/stop`**

**Round-delta 원칙**: 라운드 N은 라운드 N-1의 미해결 쟁점만 이어감. 이미 합의된 건 재논의 금지.

---

## 관련 도구 (생태계 위치)

Triad는 코드 생성·수정 도구들과 직교적. 다음 단계에서 유용:

| 단계 | 도구 | 역할 |
|---|---|---|
| **숙의** | **Triad (이 도구)** | **단일 파일 다관점 검토, 읽기 전용 또는 md-only 반영** |
| 구현 | 코드 생성 플러그인 (예: [pumasi](https://github.com/fivetaku/pumasi)) | 병렬 greenfield 구현 |
| 다듬기 | iterative 리뷰 도구 (예: [mangchi](https://github.com/minwoo-data/mangchi)) | 단일 파일 cross-model 반복 리뷰 |
| 검증 | 기존 리뷰/테스트 러너 | merge 전 최종 게이트 |

Triad는 **"결정 직전"에 가장 유용**. 한 번 합의된 문서가 downstream 모든 구현에 영향을 미치는 경우.

---

## 설치

### 전제 조건

- [Claude Code](https://docs.claude.com/en/docs/claude-code) - general-purpose 서브에이전트 스폰 가능해야 함

**외부 CLI 불필요**. Claude 내장 Agent tool만 사용. Claude Code 안에서 완결.

### 플러그인 설치

`triad` 는 haroom 플러그인 (ddaro, prism, mangchi) 과 함께 **haroom_plugins** aggregator 마켓플레이스를 통해 배포됩니다.

```bash
# 1. haroom_plugins 마켓플레이스 등록 (처음 한 번만)
/plugin marketplace add https://github.com/minwoo-data/haroom_plugins.git

# 2. 플러그인 설치
/plugin install triad
```

설치 후 Claude Code **재시작**.

---

## 사용법

```
/triad docs/features/billing.md                    # read-only, CONSENSUS.md만
/triad docs/features/billing.md --apply            # updated.md 생성, 원본 불변
/triad docs/features/billing.md --apply=original   # 원본 파일도 Edit
/triad src/routes/auth.py                          # 코드 리뷰, RECOMMENDATIONS.md 산출
/triad --continue billing                          # 진행 중 세션 이어하기
/triad --stop billing                              # 현 라운드까지 결과로 강제 종결
```

자연어: *"triad로 검토해줘"*, *"3관점 리뷰"*.

자세한 예시는 [`skills/triad/references/usage.md`](skills/triad/references/usage.md) 참조.

---

## 산출 파일 구조

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

코드 입력 시 경로는 `docs/discussion/code/<slug>/`이며 최종 파일은 `RECOMMENDATIONS.md`로 downstream 코드 생성 도구와 호환되는 포맷.

---

## 안전 기본값

- 원본 파일은 **절대로 자동 수정되지 않음** (명시적 `--apply=original` 없이는)
- 코드 파일은 **어떤 플래그에도 수정되지 않음**
- 세 서브에이전트는 **단일 병렬 tool call**로 스폰 → 서로의 응답을 볼 수 없음 (groupthink 방지)
- 서브에이전트 스폰 실패/크래시 시 메인이 local-pass로 대체, 라운드 문서에 `[fallback: main-local-pass]` 명시 - 조용한 품질 저하 없음

---

## 검증 근거

실제 프로젝트의 검토 결과는 [`skills/triad/CASE-STUDIES.md`](skills/triad/CASE-STUDIES.md)에 기록. 관점별 채택률, 중복 분석, 솔직한 한계 포함.

---

## 업데이트

- **2026-04-24** — Codex CLI `gpt-5.4` → `gpt-5.5` 마이그레이션 기록 및 벤치마크 ([docs/codex-5.4-to-5.5.md](docs/codex-5.4-to-5.5.md)). "model does not exist" 에러를 계정 문제로 단정하기 전에 먼저 읽어볼 것.

---

## 라이선스

MIT - [`LICENSE`](LICENSE) 참조.

## 크레딧

- Created by: haroom
- [Claude Code](https://docs.claude.com/en/docs/claude-code)의 general-purpose Agent tool 위에 구축
