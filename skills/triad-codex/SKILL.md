---
name: triad-codex
description: Codex-backed 3-perspective deliberation on one markdown/document file. Like triad but the 3 lenses (LLM clarity / architecture longevity / end-user comprehension) are evaluated by Codex CLI (GPT-5.5 generation) instead of Claude subagents. Documents only (code → /prism-codex). Use when you want a different-model opinion, or when Claude tokens are scarce. Triggers on "/triad-codex <file>", "triad codex로 검토", "codex로 3관점".
argument-hint: "<file> [--apply] [--apply=original] [--continue <slug>] [--stop <slug>]"
user-invocable: true
---

# triad-codex — Codex-backed 3-Perspective Deliberation

> 메인은 Claude (오케스트레이터), 3 관점 판단은 **Codex CLI**. 목적: Claude self-bias 회피 + Claude 토큰 절약.
> **문서 전용** - 코드 파일은 거부한다 (코드는 `/prism-codex`). md는 `--apply`로 `updated.md`를 생성하고, 원본 교체는 `--apply=original`일 때만.

## 핵심 가치

| 관점 | 고정 질문 |
|---|---|
| **LLM** | 미래의 LLM이 이 자료를 읽고 **틀리지 않게 행동**할 수 있는가? |
| **Architect** | 1년 뒤에도 유지될 설계인가? 결합도/책임 경계는? |
| **EndUser** | 처음 본 사람이 **5분 안에** 무엇/왜/어떻게를 답할 수 있나? |

이 3 렌즈는 고정. 추가/교체 금지.

## 전제 (Prerequisite)

이 skill은 **Codex CLI ≥ 0.125.0**을 필수로 요구한다 (gpt-5.5 payload 지원 최소 버전). 진입 시점에 확인:

```bash
codex --version      # codex-cli 0.125.0 이상이어야 함
```

**버전 체크 (필수)**:
- `codex-cli` 미설치 → 중단 + "/triad (Claude 단독)로 전환" 안내
- `codex-cli < 0.125.0` → 중단 + `npm install -g @openai/codex@latest` 안내
  - 주의: 구버전은 gpt-5.5 호출 시 `"The model 'gpt-5.5' does not exist or you do not have access to it"` 또는 `"The 'gpt-5.5' model requires a newer version of Codex"`로 거부. 에러 문구가 계정 문제처럼 보이지만 실제는 CLI 버전 문제.

**모델 선택**:
- 기본: `~/.codex/config.toml`의 `model` 값 그대로 사용 (권장 `gpt-5.5`)
- 실패 시 폴백: `~/.codex/models_cache.json`에서 `"visibility": "list"`인 첫 slug로 자동 전환하고 로그에 `[model-fallback: <picked>]` 기록
- 과거 워크어라운드 `-c model=gpt-5.4`는 **삭제**. CLI 0.125.0에서 기본값이 정상 동작.

**자동 대체 금지**: Codex CLI 자체가 없으면 Claude 서브에이전트로 갈아타지 않는다 — 이 skill의 존재 이유(다른 모델 관점/Claude 토큰 절약)가 무너짐. 사용자에게 `/triad` 재선택을 제시.

## 트리거

- `/triad-codex <file>` — read-only (원본 불변, updated.md 없음)
- `/triad-codex <file> --apply` — md 대상이면 `updated.md` 생성/갱신 (원본 불변)
- `/triad-codex <file> --apply=original` — md 대상일 때만 원본까지 Edit 반영
- `/triad-codex --continue <slug>` — 기존 토론 이어가기
- `/triad-codex --stop <slug>` — 강제 종결
- 자연어: "triad codex로 검토", "codex로 3관점"

## 입력 유형과 수정 권한

| 입력 | read-only 기본 | `--apply` | `--apply=original` |
|---|---|---|---|
| `.md` / `.mdx` / `.txt` / `.rst` 등 문서 | 원본 불변 | updated.md 생성/갱신 | updated.md + 원본 Edit |
| `.py`/`.js`/`.ts`/기타 코드 | **거부** | 거부 | 거부 |

**코드 입력 거부 (v0.2.0+)**: 코드 확장자면 라운드를 시작하지 않고 한 줄로 거부 후 종료:

```
triad-codex는 문서 전용입니다. 코드 리뷰는 /prism-codex <file>, 반복 수정은 /mangchi <file> 을 쓰세요.
```

슬러그 규칙: 확장자 제거 + 공백/특수문자 `-`로. 예: `docs/design/architecture.md` → slug=`architecture`.

---

## 7단계 워크플로우

### Phase 0: 초기화 (메인)
1. `codex --version` → `0.125.0` 이상인지 확인. 이하면 중단 + upgrade 안내 (`npm install -g @openai/codex@latest`).
2. 모델 선택:
   - `~/.codex/config.toml`의 `model` 값 읽기 (기본 `gpt-5.5`).
   - 해당 모델이 호출 실패하면 `~/.codex/models_cache.json`의 `"visibility": "list"` 첫 slug로 폴백. state.json에 `[model-fallback: <picked>]` 기록.
3. 입력 파일 존재 확인 + **문서 파일인지 확인** (코드면 거부 후 종료).
4. 슬러그 계산, 출력 디렉토리 생성: `docs/discussion/codex-md/<slug>/`.
5. `source.md`로 원본 스냅샷 저장.
6. `state.json` 생성: `{round: 1, status: "open", engine: "codex", codex_version, codex_model, started_at, target_file}`.

### Phase 1: 3 Codex 호출 (메인)

lens당 `Bash` 1개로 `codex-run.sh lens`를 실행한다 (아래 §Codex 호출). 순서는 **llm → architect → enduser** 고정, 한 번에 하나씩(Codex 사용량 경합을 줄인다). 스크립트가 프롬프트 조립·호출·scrub·파싱을 하고 `round-{N}.<lens>.{prompt.txt,codex.txt,codex.txt.json}`에 남긴다.

### Phase 2: 합성 (메인)
`round-N.md` 작성. `templates/round.md` 채움. 섹션:
1. 각 관점 YAML 원문 (Codex 응답)
2. 메인(Claude)의 쟁점 합성 (중복 제거, 우선순위)
3. Decision log (ACCEPT/REJECT/DEFER 각 이슈별 한 줄 이유)
4. `--apply` 사용 시 적용한 diff
5. Codex invocation log (bytes_in/out, duration, status)
6. 다음 라운드로 이월할 open issues

### Phase 3: 반영 판단 (메인)
| 플래그 | 동작 |
|---|---|
| 플래그 없음 | 원본 불변. updated.md 생성 안 함. |
| `--apply` | 원본 불변. updated.md 생성/갱신. |
| `--apply=original` | 위 + 원본 md Edit 반영. diff를 `round-N.md`에 기록. |

### Phase 4: 종결 판정 (메인)
**종결 조건 AND**:
1. 3 관점 모두 `verdict: PASS` (이번 라운드)
2. 메인의 open_questions 리스트 = 빈 배열

**강제 종결**:
- round 5 도달 (hard cap)
- 사용자 `/triad-codex --stop`
- Codex CLI 연속 실패 (같은 라운드에서 2 관점 이상 fallback 발생)

**종결 시**: `CONSENSUS.md` 작성.

### Phase 5: 다음 라운드 or 종료
- 미충족 → round N+1. `state.json` 업데이트. 남은 쟁점만 다음 라운드 입력. `round-N.carryover.txt`를 쓴다: `## 합의됨`(ACCEPT·반영 완료·REJECT — 다음 라운드에서 재논의 금지) / `## 미해소`(DEFER·새 open_questions — 다시 확인). 이 파일이 없으면 N+1 라운드 호출이 exit 2로 멈춘다.
- 충족 → `state.json` status="closed".

## Round-Delta 원칙 (MUST)

라운드 N의 입력 = **지난 라운드 미해소 쟁점 + 원본**. 합의된 건 재논의 금지.

---

## Codex 호출 (엄수: `codex-run.sh`로만)

Codex 호출 계약은 이 skill 디렉토리의 `codex-run.sh`가 코드로 강제한다 (외부 공용 파일 없음 - plugin 독립성). 호출 템플릿을 손으로 쓰거나 `codex exec`를 직접 부르지 않는다. lens당 Bash 1개, Bash tool `timeout` = (`TRIAD_CODEX_TIMEOUT`(기본 300) + 30) × 1000 ms, 최대 600000:

```bash
bash "<skill dir>/codex-run.sh" lens <discussion-dir> <N> <llm|architect|enduser> --target <원본 문서> [--context <파일>]... [--instructions <파일>] [--no-carryover]
```

스크립트가 강제하는 것:
- **프롬프트 구조 (두 엔진 공통, 스크립트가 조립)**: 대상 문서 → 배경(`--context`, 여러 개 가능) → 추가 지시(`--instructions`, 예: "모든 file:line 주장을 코드와 대조") → 지난 라운드 carryover(N≥2면 `round-<N-1>.carryover.txt` **필수**, 없으면 exit 2, 의도적으로 건너뛸 때만 `--no-carryover`) → `agents/<lens>-perspective.md` → 출력 계약 `templates/output-contract.md`(**단일 소스**, `<<<TRIAD-FINDINGS v1>>>`). Codex에는 맨 앞에 Sandbox Safety Preamble이 붙는다. 앞부분이 3 렌즈 공통이라 프롬프트 캐시에 걸린다. 출력 계약 파일·관점 파일의 형식·두 엔진의 동일 입력은 selftest가 검사한다 — 구조가 빠지면 `verify-independence.js --strict`가 실패한다.
- 파일 + stdin 전달, 180K 가드, timeout 300s·effort high(`TRIAD_CODEX_TIMEOUT`·`TRIAD_CODEX_EFFORT`로 변경), **read-only 샌드박스**(Codex가 실행하는 명령은 읽기만, 쓰기·네트워크 차단).
- **secret scrub**: Codex 출력 전체를 검사해, 프롬프트에 없던 secret 모양 문자열이 나오면 출력을 지우고 `[fallback: codex-output-contained-secret-pattern]`.
- `--output-last-message`의 최종 답만 쓴다. raw 스트림은 프롬프트를 되울리므로 파싱하지도 저장하지도 않는다. 결과는 `parse-triad.js`로 파싱.
- 결과 파일: `round-N.<lens>.prompt.txt` / `.codex.txt` / `.codex.txt.json`. stdout = 요약 1줄(`status=… verdict=… issues=N questions=N sandbox=…`) + 파서 JSON.

실패한 lens도 exit 0 + `[fallback: <사유>]` 마커 → 파서가 `verdict=DEGRADED`. 사유: `timeout`, `codex-unavailable`(stderr 끝 300자 포함), `no-last-message`, `prompt-too-large`, `prompt-build-failed`, `interrupted`, `codex-output-contained-secret-pattern`·`prompt-modified-during-run`(이 둘은 보안 사건 - 판정에서 빼고 사용자에게 알린다), `scan-failed`(출력을 스캔하지 못해 지웠다 - 디스크·권한 확인 후 재실행). exit 2 = 인자·설정·설치 오류, carryover 누락, 또는 같은 렌즈가 아직 실행 중이거나 막 시작하는 중(고친 뒤, 또는 몇 초 뒤 다시 실행; 다른 모델로 재시도하지 않는다). exit 130 = 중단(마커와 DEGRADED JSON은 남는다. 보안 격리 도중 중단되면 보안 사건 마커와 `secret-scrubbed(...)` 상태가 남는다). 보안 사건 마커는 다음 실행 때 `*.incident.*`로 보존된다. 요약 줄 끝의 `cleanup_failed=<경로>`(JSON `cleanup_failed`)는 지우지 못한 Codex 출력이다(scrub 전 내용일 수 있음): 판정은 그대로 쓰되 사용자에게 그 경로를 손으로 지우라고 알린다.

샌드박스가 못 읽는 경로(예: Google Drive `H:`)의 사실 확인 자료는 `--context`로, 호출자가 덧붙일 지시(예: `/ddaro:review`의 코드 대조 지시)는 `--instructions`로 넘긴다(스크립트가 샌드박스 밖에서 읽어 넣는다). 샌드박스 없이 돌리기는 사용자가 요청할 때만 `TRIAD_CODEX_SANDBOX=bypass`. 실측(CLI 0.159.3 + gpt-6-astra, 24KB 프롬프트): effort high 44s, xhigh 113s, max 227s. max 이상은 `TRIAD_CODEX_TIMEOUT=480` 이상과 함께.

### 출력 파서 (`parse-triad.js`, 헤더가 정본)

→ `{lens, verdict, degraded, issues:[{severity,locus,text}], questions:[..]}`. 모든 펜스 블록 중 verdict가 있고 항목이 많은 블록을 고르고, severity 별칭을 정규화하고, verdict가 없으면 DEGRADED(이미 파싱한 issue는 보존). synthesis와 종결 판정(PASS)은 이 레코드로 한다. 자가 검증: `node parse-triad.js --selftest`.

### Fallback 정책

Codex 호출 실패 시 (요약 줄 `status=degraded(timeout|codex-unavailable|no-last-message)`; `prompt-too-large`·`prompt-build-failed`는 재시도하지 않고, `secret-scrubbed(...)`는 보안 사건이라 재시도 없이 사용자에게 알린다):
1. 첫 실패 → Phase 0에서 선정한 폴백 모델로 1회 재시도(`TRIAD_CODEX_MODEL=<slug>`를 붙여 같은 명령 재실행). 성공 시 `state.json`에 `[model-fallback: <picked>]` 기록.
2. 재시도도 실패 → 해당 라운드의 해당 관점에 `[fallback: codex-unavailable]` 태그.
3. `state.json`의 `rounds[N].fallbacks` 배열에 관점 이름 추가.
4. 메인(Claude)이 해당 관점 프롬프트를 **자체적으로 local pass**. 결과에 동일 태그 유지.
5. 같은 라운드에서 **3 관점 중 2개 이상 fallback** 발생 시: 라운드 invalid, 사용자에게 "/triad로 전환" 또는 "/triad-codex --stop" 선택지 제시.

이 규약으로 Codex 장애가 조용히 품질 저하로 이어지는 걸 방지한다.

### Migration note

- 과거(0.123.0 시절) SKILL은 `-c model=gpt-5.4` override를 권장했다. **그 workaround는 삭제**. CLI 0.125.0에서 `~/.codex/config.toml`의 `model = "gpt-5.5"` 기본값이 정상 동작.
- `"The model 'gpt-5.5' does not exist or you do not have access to it"` 또는 `"The 'gpt-5.5' model requires a newer version of Codex"` 에러는 **계정 문제가 아니라 CLI 버전 문제일 확률이 높음**. 먼저 `codex --version`과 `npm install -g @openai/codex@latest`로 해결.
- 상세 벤치마크/포스트-모템: (이 skill 밖의 공개 문서 참조 권장. 예: triad plugin의 `docs/codex-5.4-to-5.5.md`)

---

## 파일 구조

```
docs/discussion/
└── codex-md/<slug>/
    ├── source.md
    ├── state.json
    ├── round-1.md
    ├── round-1.llm.prompt.txt
    ├── round-1.llm.codex.txt       # + .codex.txt.json (parse-triad.js)
    ├── round-1.architect.prompt.txt
    ├── round-1.architect.codex.txt
    ├── round-1.enduser.prompt.txt
    ├── round-1.enduser.codex.txt
    ├── round-1.carryover.txt
    ├── ...
    ├── CONSENSUS.md
    └── updated.md
```

(v0.1.x의 `docs/discussion/codex/<slug>/` 코드 트리와 `RECOMMENDATIONS.md`는 코드 입력 폐기와 함께 제거됨.)

## 자립성 검증

이 skill 디렉토리에서:
```bash
node verify-independence.js
# 통과 = 다른 plugin/skill에 의존하지 않고, 필수 파일 모두 존재.
node verify-independence.js --strict
# 추가: parse-triad.js·codex-run.sh selftest + Codex CLI 존재까지 체크.
```

## 참조 (이 skill 내부에 한함)

- 에이전트 프롬프트: `agents/llm-perspective.md`, `agents/architect-perspective.md`, `agents/enduser-perspective.md`
- 템플릿: `templates/round.md`, `templates/consensus.md`
- Codex 호출: `codex-run.sh` / 출력 파서: `parse-triad.js`
- 자립성 체크: `verify-independence.js`

## 안티패턴

- ❌ Codex 실패 시 조용히 Claude로 대체 — `[fallback]` 태그 필수.
- ❌ 3 관점을 서로 다른 프롬프트 구조로 호출 — 모두 `agents/<lens>-perspective.md` 기반.
- ❌ `codex exec`를 직접 호출하거나 자체 실행 스크립트를 만듦 — preamble·scrub·샌드박스·출력 계약이 빠진다. Codex는 `codex-run.sh`로만.
- ❌ 코드 파일을 입력으로 받아 라운드 진행 — 거부 후 `/prism-codex`, `/mangchi` 안내.
- ❌ 관점 정의를 프롬프트 맨 앞에 — 공통 prefix(대상 문서) 먼저.
- ❌ 이미 합의된 쟁점을 다음 라운드에 재수록 — Round-Delta 위반.
- ❌ 5 라운드 초과 진입 — hard cap.
- ❌ 다른 plugin/skill 파일을 참조 — 전역 hook과 `verify-independence.js`가 차단.

## triad (Claude 버전)과의 관계

같은 3 렌즈 · 같은 수렴 규약 · 같은 파일 구조. 차이는 **판단 주체**:

| 축 | triad | triad-codex |
|---|---|---|
| 판단 모델 | Claude 서브에이전트 | Codex CLI |
| 호출 방식 | Agent tool 병렬 | CLI tempfile+stdin 순차 |
| Claude 토큰 소비 | 많음 (메인 + 3 서브) | 적음 (메인만) |
| Codex 요금/쿼터 | 없음 | 사용 |
| self-bias 회피 | 약함 | **강함** (다른 모델) |

어느 쪽이 좋은지는 대상 파일 성격·토큰 잔량·다른-모델 관점이 필요한지에 따름. 성능 비교는 `docs/benchmarks/triad-vs-triad-codex-*.md` 참조.
