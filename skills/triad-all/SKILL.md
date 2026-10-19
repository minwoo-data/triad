---
name: triad-all
description: Dual-engine 3-perspective deliberation on one markdown/document file. Runs the 3 lenses (LLM clarity / architecture longevity / end-user comprehension) on BOTH Claude subagents and Codex CLI in parallel, then promotes issues by cross-model agreement. Documents only (code → /prism-all). Use for consequential documents where you want the highest-confidence review. Triggers on "/triad-all <file>", "triad all로 검토", "크로스모델 3관점".
argument-hint: "<file> [--apply] [--apply=original] [--continue <slug>] [--stop <slug>]"
user-invocable: true
---

# triad-all — Dual-Engine 3-Perspective Deliberation

> 메인은 Claude (오케스트레이터). 매 라운드 **Claude 서브에이전트 3 + Codex CLI 3 = 6콜**을 병렬 발사하고, **같은 렌즈에서 두 엔진이 모두 잡은 이슈**를 최고 신뢰 티어로 승급한다.
> **문서 전용** - 코드 파일은 거부한다 (코드는 `/prism-all`). md는 `--apply`로 `updated.md`를 생성하고, 원본 교체는 `--apply=original`일 때만.

## 핵심 가치 (cross-model agreement)

기존 `/triad`는 Claude 내부 3 렌즈로 self-bias 일부 상쇄. `/triad-codex`는 그 결정을 다른 모델에게 맡겨 self-bias 완전 회피. **`/triad-all`은 둘 다 돌려서** 같은 렌즈에서 두 엔진이 독립적으로 잡은 이슈 = **최고 신뢰도**. 한쪽만 잡은 이슈는 breadth 기여.

벤치마크 (3 파일 × 2 엔진): Claude-only unique 10+건, Codex-only unique 13+건, 교차 합의 7~8건. 각 엔진이 놓치는 사각지대가 서로 달라서 합치면 커버리지 크게 증가.

## 3 렌즈 (고정, 두 엔진 공통)

| 관점 | 고정 질문 |
|---|---|
| **LLM** | 미래의 LLM이 이 자료를 읽고 틀리지 않게 행동할 수 있는가? |
| **Architect** | 1년 뒤에도 유지될 설계인가? 결합도/책임 경계? |
| **EndUser** | 처음 본 사람이 5분 안에 무엇/왜/어떻게 답할 수 있나? |

## 전제 (Prerequisite)

**둘 다 필수** (부분 폴백은 degraded 모드로만 허용):

1. **Claude Code** (메인 오케스트레이터 + 서브에이전트 3개) — ambient.
2. **Codex CLI ≥ 0.125.0** (gpt-5.5 payload 지원 최소 버전).
   - 확인: `codex --version`
   - 업그레이드: `npm install -g @openai/codex@latest`

**Codex CLI 부재/구버전**: 사용자에게 "`/triad`(Claude only)로 전환" 제시. **자동으로 Claude-only로 떨어지지 않는다** — skill 이름이 `-all`인데 반만 돌면 사용자가 인지 못한 채 품질 저하.

**Codex 모델 선택**:
- 기본: `~/.codex/config.toml`의 `model` (권장 `gpt-5.5`).
- 호출 실패 시 `~/.codex/models_cache.json`에서 `"visibility": "list"`인 첫 slug로 폴백. `state.json`에 `[model-fallback: <picked>]` 기록.

## 트리거

- `/triad-all <file>` — read-only
- `/triad-all <file> --apply` — md 대상이면 `updated.md` 생성/갱신
- `/triad-all <file> --apply=original` — md 대상일 때만 원본까지 Edit
- `/triad-all --continue <slug>` — 이어가기
- `/triad-all --stop <slug>` — 강제 종결
- 자연어: "triad all로 검토", "크로스모델 3관점"

**입력 유형**: 문서(`.md`/`.mdx`/`.txt`/`.rst` 등)만. 코드 확장자(`.py`/`.js`/`.ts`/...)면 라운드를 시작하지 않고 한 줄로 거부:

```
triad-all은 문서 전용입니다. 코드 리뷰는 /prism-all <file> (크로스모델 결함 탐지), 반복 수정은 /mangchi <file> 을 쓰세요.
```

슬러그: 확장자 제거 + 공백/특수문자 `-`로. 예: `docs/design/architecture.md` → `architecture`.

---

## 5단계 워크플로우

### Phase 0: 초기화 (메인)
1. `codex --version ≥ 0.125.0` 확인. 부적합 시 중단.
2. Codex 모델 결정 (config 기본 → 필요시 cache 폴백).
3. 입력 파일 존재 확인 + **문서 파일인지 확인** (코드면 거부 후 종료).
4. 슬러그 계산. 출력 디렉토리: `docs/discussion/all-md/<slug>/`
5. 원본 스냅샷 (`source.md`) 저장.
6. `state.json`: `{round: 1, status: "open", engine: "all", codex_version, codex_model, started_at, target_file}`.

### Phase 1: 6 병렬 실행 (메인)

**한 메시지 안에서 전부 병렬**:

- Claude 3개: `Agent` tool × 3 (llm/architect/enduser), `subagent_type: "general-purpose"`, forked context. 각 Agent의 프롬프트는 먼저 `bash "<skill dir>/codex-run.sh" prompt <dir> <N> <lens> <Codex 호출과 같은 옵션>`으로 만든 `round-N.claude.<lens>.prompt.txt` 하나다 ("이 파일을 Read로 읽고 그대로 따르라"). 그래서 Claude와 Codex가 같은 입력·같은 출력 계약을 받는다 — 프롬프트를 손으로 조립하지 않는다.
- Codex 3개: lens당 `Bash` 1개로 `codex-run.sh lens` (아래 §Codex 호출). Claude Agent 3개와 **같은 메시지에서 병렬**. 한 Bash 안에 3개를 돌리지 않는다 - hang이나 외부 timeout 때 뒤 렌즈가 통째로 사라진다.

Wall time ≈ max(Claude 3 parallel ≈ 30~40s, Codex 3 parallel ≈ 45~60s). Codex 병렬 실행은 2026-10-14 prism-all에서 5개 동시 호출로 확인했다.

두 엔진의 프롬프트는 같은 구조다 (아래 §Codex 호출의 프롬프트 구조, 스크립트가 조립). 응답은:
- Claude: Agent 반환값을 `round-N.claude.<lens>.txt`로 저장 → `node parse-triad.js <파일> <lens> > <파일>.json`
- Codex: `round-N.codex.<lens>.{prompt.txt,codex.txt,codex.txt.json}` (스크립트가 저장·파싱)

### Phase 2: 합성 + 승급 (메인)

`round-N.md`를 `templates/round.md` 채워 작성. 각 이슈를 3 tier로 분류:

**Tier 1 — Cross-model agreement** (최고 신뢰)
- 같은 렌즈에서 Claude와 Codex가 모두 flag한 이슈 (semantic match — 같은 locus 또는 같은 문제 서술).
- 레이블: `[cross-model/<lens>]`
- severity: 두 엔진의 union 중 더 높은 값 (conservative).

**Tier 2 — Single-engine multi-lens** (중간 신뢰)
- 한 엔진의 2+ 렌즈가 같은 이슈 flag.
- 레이블: `[claude/multi-lens]` 또는 `[codex/multi-lens]`.

**Tier 3 — Singleton** (낮은 신뢰, 참고용)
- 한 엔진의 한 렌즈만 flag.
- 레이블: `[claude/<lens>]` 또는 `[codex/<lens>]`.

**Conflicts**: 같은 렌즈에서 두 엔진이 **서로 반대되는 조언**을 낸 경우 → "Conflicting" 섹션에 양쪽 표시 + 메인이 한 줄 판정 근거로 한쪽 선택 (또는 DEFER).

### Phase 3: 반영 판단

기존 triad와 동일:

| 플래그 | 동작 |
|---|---|
| 없음 | 원본 불변, updated.md 생성 안 함 |
| `--apply` | updated.md 생성/갱신 (원본 불변) |
| `--apply=original` | 위 + 원본 md Edit |

### Phase 4: 종결 판정

**종결 조건 AND** (모두 만족):
1. Claude 3 렌즈 모두 `verdict: PASS` (이번 라운드)
2. Codex 3 렌즈 모두 `verdict: PASS` (이번 라운드)
3. 메인의 open_questions 리스트 = 빈 배열

**즉 6-way agreement + zero questions**. `/triad` 단독(3-way)보다 엄격하지만 cross-model 커버리지로 정당화.

**강제 종결**:
- round 5 도달 (hard cap)
- 사용자 `/triad-all --stop`
- **Dual fallback**: 같은 라운드에서 특정 렌즈가 **양쪽 엔진 모두 fallback** 발생 → 라운드 invalid, 사용자에게 "/triad" (Codex 장애) 또는 "/triad-codex" (Agent 장애) 전환 제시.

### Phase 5: 다음 라운드 or 종료

- 미충족 → round N+1. state.json 업데이트. Tier 1/2 ACCEPT는 반영, Tier 3 DEFER + 새 open_questions만 다음 라운드 입력. `round-N.carryover.txt`를 쓴다: `## 합의됨`(ACCEPT·반영 완료·REJECT — 다음 라운드에서 재논의 금지) / `## 미해소`(DEFER·새 open_questions — 다시 확인). 이 파일이 없으면 N+1 라운드 호출이 exit 2로 멈춘다.
- 충족 → `CONSENSUS.md` (templates/consensus.md) 작성, status="closed".

## Round-Delta 원칙 (MUST)

라운드 N 입력 = **지난 라운드 미해소 쟁점 + 원본**. 이미 합의된 건 재논의 금지 — 파일이 안 불어나고 수렴 가시적.

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
- 결과 파일: `round-N.codex.<lens>.prompt.txt` / `.codex.txt` / `.codex.txt.json`. stdout = 요약 1줄(`status=… verdict=… issues=N questions=N sandbox=…`) + 파서 JSON.

실패한 lens도 exit 0 + `[fallback: <사유>]` 마커 → 파서가 `verdict=DEGRADED`. 사유: `timeout`, `codex-unavailable`(stderr 끝 300자 포함), `no-last-message`, `prompt-too-large`, `prompt-build-failed`, `interrupted`, `codex-output-contained-secret-pattern`·`prompt-modified-during-run`(이 둘은 보안 사건 - 판정에서 빼고 사용자에게 알린다), `scan-failed`(출력을 스캔하지 못해 지웠다 - 디스크·권한 확인 후 재실행). exit 2 = 인자·설정·설치 오류, carryover 누락, 또는 같은 렌즈가 아직 실행 중이거나 막 시작하는 중(고친 뒤, 또는 몇 초 뒤 다시 실행; 다른 모델로 재시도하지 않는다). exit 130 = 중단(마커와 DEGRADED JSON은 남는다. 보안 격리 도중 중단되면 보안 사건 마커와 `secret-scrubbed(...)` 상태가 남는다). 보안 사건 마커는 다음 실행 때 `*.incident.*`로 보존된다. 요약 줄 끝의 `cleanup_failed=<경로>`(JSON `cleanup_failed`)는 지우지 못한 Codex 출력이다(scrub 전 내용일 수 있음): 판정은 그대로 쓰되 사용자에게 그 경로를 손으로 지우라고 알린다.

샌드박스가 못 읽는 경로(예: Google Drive `H:`)의 사실 확인 자료는 `--context`로, 호출자가 덧붙일 지시(예: `/ddaro:review`의 코드 대조 지시)는 `--instructions`로 넘긴다(스크립트가 샌드박스 밖에서 읽어 넣는다). 샌드박스 없이 돌리기는 사용자가 요청할 때만 `TRIAD_CODEX_SANDBOX=bypass`. 실측(CLI 0.159.3 + gpt-6-astra, 24KB 프롬프트): effort high 44s, xhigh 113s, max 227s. max 이상은 `TRIAD_CODEX_TIMEOUT=480` 이상과 함께.

### 출력 파서 (`parse-triad.js`, 헤더가 정본)

→ `{lens, verdict, degraded, issues:[{severity,locus,text}], questions:[..]}`. 모든 펜스 블록 중 verdict가 있고 항목이 많은 블록을 고르고, severity 별칭을 정규화하고, verdict가 없으면 DEGRADED(이미 파싱한 issue는 보존). synthesis와 종결 판정(PASS)은 이 레코드로 한다. Claude Agent 반환값은 `round-N.claude.<lens>.txt`로 저장해 같은 파서로 `.json`을 만든다. 자가 검증: `node parse-triad.js --selftest`.

### Fallback 정책

| 상황 | 동작 |
|---|---|
| 특정 렌즈에서 Claude Agent 실패 (timeout, 크래시, 스폰 실패) | 해당 lens에 `[fallback: claude-unavailable]` 태그. Codex 응답만으로 해당 lens 판정. state.json의 `rounds[N].fallbacks`에 `claude/<lens>` 추가. |
| 특정 렌즈에서 Codex 실패 (요약 줄 `status=degraded(timeout|codex-unavailable|no-last-message)`) | Phase 0 폴백 모델로 1회 재시도(`TRIAD_CODEX_MODEL=<slug>`를 붙여 같은 명령 재실행). `prompt-too-large`·`prompt-build-failed`는 재시도하지 않는다(같은 입력은 또 실패). `secret-scrubbed(...)`는 보안 사건 — 재시도하지 말고 사용자에게 알린다. 여전히 실패하면 해당 lens에 `[fallback: codex-unavailable]`. Claude 응답만으로 판정. state.json의 `rounds[N].fallbacks`에 `codex/<lens>` 추가. |
| 같은 lens에서 **양쪽 엔진 모두 실패** | 라운드 invalid. 사용자에게 "`/triad` (Codex 쪽 전부 고장) 또는 `/triad-codex` (Claude Agent 쪽 전부 고장) 또는 `/triad-all --stop`" 선택 제시. |
| 라운드 중 3 렌즈 모두 한쪽 엔진이 실패 | 이 skill이 반만 돌고 있으므로 경고 + 자동으로 중단. 사용자가 선호 엔진의 전용 skill로 재호출. |

---

## 파일 구조

```
docs/discussion/
└── all-md/<slug>/
    ├── source.md
    ├── state.json
    ├── round-1.md                        # 6 responses + synthesis
    ├── round-1.codex.llm.prompt.txt
    ├── round-1.codex.llm.codex.txt       # + .codex.txt.json (parse-triad.js)
    ├── round-1.codex.architect.prompt.txt
    ├── round-1.codex.architect.codex.txt
    ├── round-1.codex.enduser.prompt.txt
    ├── round-1.codex.enduser.codex.txt
    ├── round-1.carryover.txt
    ├── CONSENSUS.md
    └── updated.md                        # --apply에서만
```

(v0.1.x의 `docs/discussion/all/<slug>/` 코드 트리와 `RECOMMENDATIONS.md`는 코드 입력 폐기와 함께 제거됨.)

Claude Agent 프롬프트·응답·파싱 결과: `round-N.claude.<lens>.prompt.txt` / `.txt` / `.txt.json`.

## 자립성 검증

```bash
node verify-independence.js           # 필수 파일 + cross-ref 체크
node verify-independence.js --strict  # + parse-triad.js·codex-run.sh selftest + Codex CLI ≥ 0.125.0
```

## 안티패턴

- ❌ Claude 3개와 Codex 3개를 순차 실행 — **반드시 병렬**. 시퀀셜이면 이 skill 쓰는 이유 없음.
- ❌ 교차 합의(Tier 1)가 나왔는데 Tier 3 singleton으로 동등 취급 — confidence tier 준수.
- ❌ 한쪽 엔진 실패 시 조용히 다른 쪽만으로 계속 — fallback 태그 + state.json 기록 필수.
- ❌ `codex exec`를 직접 호출하거나 자체 실행 스크립트를 만듦 — preamble·scrub·샌드박스·출력 계약이 빠진다. Codex는 `codex-run.sh`로만.
- ❌ 코드 파일을 입력으로 받아 라운드 진행 — 거부 후 `/prism-all`, `/mangchi` 안내.
- ❌ 관점 정의를 프롬프트 맨 앞에 — 공통 prefix(대상 문서) 먼저.
- ❌ 이미 합의된 쟁점을 다음 라운드에 재수록 — Round-Delta 위반.
- ❌ 5 라운드 초과 — hard cap.
- ❌ 다른 plugin/skill 파일을 참조 — 전역 hook이 차단.

## 자매 skill과의 관계

| Skill | 엔진 | 언제 쓰는가 |
|---|---|---|
| `/triad` | Claude 3 | Claude 토큰 여유 충분, 빠른 1-엔진 리뷰 |
| `/triad-codex` | Codex 3 | Claude 토큰 아끼고 싶거나 다른 모델 관점 원할 때 |
| `/triad-all` (이 skill) | Claude 3 + Codex 3 | 중요한 문서, 최고 신뢰, 양쪽 토큰 OK |
| `/prism-all` | Claude 5 + Codex 5 | **코드** 파일, 또는 설계 문서의 **건전성** (design 렌즈셋). triad 계열은 문서의 글 품질 |

세 skill은 완전히 독립된 plugin으로 각자 자기 프롬프트·템플릿·Codex 규약을 보유한다. 하나만 설치해도 나머지 없이 동작.
