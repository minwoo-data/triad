---
name: triad-all
description: Dual-engine 3-perspective deliberation. Runs the 3 lenses (LLM clarity / architecture longevity / end-user comprehension) on BOTH Claude subagents and Codex CLI in parallel, then promotes issues by cross-model agreement. Use for consequential files where you want the highest-confidence review. Triggers on "/triad-all <file>", "triad all로 검토", "크로스모델 3관점".
argument-hint: "<file> [--apply] [--apply=original] [--continue <slug>] [--stop <slug>]"
user-invocable: true
---

# triad-all — Dual-Engine 3-Perspective Deliberation

> 메인은 Claude (오케스트레이터). 매 라운드 **Claude 서브에이전트 3 + Codex CLI 3 = 6콜**을 병렬 발사하고, **같은 렌즈에서 두 엔진이 모두 잡은 이슈**를 최고 신뢰 티어로 승급한다.
> 코드 파일은 절대 수정하지 않는다. md는 `--apply`로 `updated.md`를 생성하고, 원본 교체는 `--apply=original`일 때만.

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

슬러그: 확장자 제거 + 공백/특수문자 `-`로. 예: `src/routes/auth.py` → `auth-py`.

---

## 5단계 워크플로우

### Phase 0: 초기화 (메인)
1. `codex --version ≥ 0.125.0` 확인. 부적합 시 중단.
2. Codex 모델 결정 (config 기본 → 필요시 cache 폴백).
3. 입력 파일 존재 확인.
4. 슬러그 계산. 출력 디렉토리:
   - 코드 입력: `docs/discussion/all/<slug>/`
   - md 입력:  `docs/discussion/all-md/<slug>/`
5. 원본 스냅샷 (`source.md` 또는 `source-snapshot.md`) 저장.
6. `state.json`: `{round: 1, status: "open", engine: "all", codex_version, codex_model, started_at, target_file}`.

### Phase 1: 6 병렬 실행 (메인)

**한 메시지 안에서 전부 병렬**:

- Claude 3개: `Agent` tool × 3 (llm/architect/enduser), `subagent_type: "general-purpose"`, forked context.
- Codex 3개: `Bash` tool × 1 안에 3개 순차 (Codex CLI는 한 번에 1콜이 안정적). 전체 Bash는 Claude Agent들과 **병렬**.

Wall time = max(Claude 3 parallel ≈ 30~40s, Codex 3 sequential ≈ 90~110s) ≈ **Codex wall로 결정** (주요 병목).

각 엔진은 `agents/<lens>-perspective.md` 프롬프트 그대로 사용. 응답은:
- Claude: Agent 반환값 (YAML 그대로)
- Codex: `round-N.<engine>.<lens>.{prompt,codex}.txt` 파일에 저장

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

| 입력 | 플래그 | 동작 |
|---|---|---|
| 코드 | (모든 플래그) | 원본 불변, `RECOMMENDATIONS.md`만 누적 |
| md | 없음 | 원본 불변, updated.md 생성 안 함 |
| md | `--apply` | updated.md 생성/갱신 (원본 불변) |
| md | `--apply=original` | 위 + 원본 md Edit |

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

- 미충족 → round N+1. state.json 업데이트. Tier 1/2 ACCEPT는 반영, Tier 3 DEFER + 새 open_questions만 다음 라운드 입력.
- 충족 → `CONSENSUS.md` (templates/consensus.md) 작성, status="closed".

## Round-Delta 원칙 (MUST)

라운드 N 입력 = **지난 라운드 미해소 쟁점 + 원본**. 이미 합의된 건 재논의 금지 — 파일이 안 불어나고 수렴 가시적.

---

## Codex 호출 규약 (엄수)

Codex 호출 로직은 이 skill이 자체 보유한다 (외부 공용 파일 금지 — plugin 독립성).

### 불변 규칙

1. **argv 금지** — 절대 `codex exec "$PROMPT_TEXT"`. Shell injection 벡터.
2. **tempfile + stdin 강제** — `codex exec ... < "$PROMPT_FILE"`.
3. **Heredoc quoted** — `<<'EOF'`로 shell expansion 차단.
4. **Dynamic content는 파일 append** — `cat <source_file> >> "$PROMPT_FILE"`. `echo "$VAR" >>` 같은 unquoted expansion 금지.
5. **Per-call context guard 180K chars** — 넘으면 중단, 분할 필요.
6. **Timeout 180s** — `timeout 180 codex exec ...`. 실측 15~40s, cold start 시 최대 52s.

### 호출 템플릿

```bash
DIR="docs/discussion/all/<slug>"
N="<round_number>"
LENS="<llm|architect|enduser>"
PROMPT_FILE="$DIR/round-${N}.codex.${LENS}.prompt.txt"
CODEX_OUT="$DIR/round-${N}.codex.${LENS}.codex.txt"

# 1. prompt 조립 (quoted heredoc)
cat > "$PROMPT_FILE" <<'EOF'
[이 파일 내용을 읽고 <관점>으로만 평가하라]

## 너의 관점 정의
EOF

cat "agents/${LENS}-perspective.md" >> "$PROMPT_FILE"

cat >> "$PROMPT_FILE" <<'EOF'

## 대상 파일
EOF

cat "$TARGET_FILE" >> "$PROMPT_FILE"

# (round >= 2일 때만) 지난 라운드 carryover append
if [ "$N" -ge 2 ]; then
  cat >> "$PROMPT_FILE" <<'EOF'

## 지난 라운드 합의 (이미 해소된 쟁점은 재논의 금지)
EOF
  cat "$DIR/round-$((N-1)).carryover.txt" >> "$PROMPT_FILE"
fi

cat >> "$PROMPT_FILE" <<'EOF'

## 출력 포맷 (엄수, YAML 하나만)
verdict: PASS | REVISE | BLOCK
top_issues:
  - severity: high | med | low
    locus: "..."
    problem: "..."
    proposed_fix: "..."
open_questions:
  - "..."
EOF

# 2. context guard
BYTES=$(wc -c < "$PROMPT_FILE")
if [ "$BYTES" -gt 180000 ]; then
  echo "[triad-all] FAIL prompt ${BYTES}B > 180K for ${LENS}" >&2
  exit 2
fi

# 3. Codex 호출 (stdin)
timeout 180 codex exec --dangerously-bypass-approvals-and-sandbox < "$PROMPT_FILE" > "$CODEX_OUT" 2>&1 || {
  echo "[triad-all] WARN Codex call failed for ${LENS}" >&2
  echo "[fallback: codex-unavailable]" > "$CODEX_OUT"
}
```

### 출력 포맷 (gpt-5.5, CLI 0.125.0 기준)

Codex stdout 패턴:
```
(prompt echo …)
codex
verdict: REVISE
top_issues:
  ...
tokens used
<N>
```

**파서 규약**:
1. ` ```yaml ... ``` ` fence 찾지 마라 (5.5는 안 쓴다).
2. `^codex$` 마커 직후 `^verdict:`부터 시작, `^tokens used$`에서 종료.

**무해한 stderr 경고** 필터링:
```
ERROR codex_core::session: failed to record rollout items: thread ... not found
```

### Fallback 정책

| 상황 | 동작 |
|---|---|
| 특정 렌즈에서 Claude Agent 실패 (timeout, 크래시, 스폰 실패) | 해당 lens에 `[fallback: claude-unavailable]` 태그. Codex 응답만으로 해당 lens 판정. state.json의 `rounds[N].fallbacks`에 `claude/<lens>` 추가. |
| 특정 렌즈에서 Codex 실패 (timeout, exit != 0, YAML 추출 실패) | Phase 0 폴백 모델로 1회 재시도. 여전히 실패하면 해당 lens에 `[fallback: codex-unavailable]`. Claude 응답만으로 판정. state.json의 `rounds[N].fallbacks`에 `codex/<lens>` 추가. |
| 같은 lens에서 **양쪽 엔진 모두 실패** | 라운드 invalid. 사용자에게 "`/triad` (Codex 쪽 전부 고장) 또는 `/triad-codex` (Claude Agent 쪽 전부 고장) 또는 `/triad-all --stop`" 선택 제시. |
| 라운드 중 3 렌즈 모두 한쪽 엔진이 실패 | 이 skill이 반만 돌고 있으므로 경고 + 자동으로 중단. 사용자가 선호 엔진의 전용 skill로 재호출. |

---

## 파일 구조

```
docs/discussion/
├── all-md/<slug>/                        # md 입력
│   ├── source.md
│   ├── state.json
│   ├── round-1.md                        # 6 responses + synthesis
│   ├── round-1.codex.llm.prompt.txt
│   ├── round-1.codex.llm.codex.txt
│   ├── round-1.codex.architect.prompt.txt
│   ├── round-1.codex.architect.codex.txt
│   ├── round-1.codex.enduser.prompt.txt
│   ├── round-1.codex.enduser.codex.txt
│   ├── round-1.carryover.txt
│   ├── CONSENSUS.md
│   └── updated.md                        # --apply에서만
│
└── all/<slug>/                           # 코드 입력
    ├── source-snapshot.md
    ├── state.json
    ├── round-N.md
    ├── round-N.codex.<lens>.prompt.txt
    ├── round-N.codex.<lens>.codex.txt
    ├── CONSENSUS.md
    └── RECOMMENDATIONS.md
```

Claude Agent 원본 응답은 Agent tool의 반환값으로만 존재 (별도 파일 저장 불필요 — round-N.md의 "Claude" 섹션에 기록됨).

## 자립성 검증

```bash
node verify-independence.js           # 필수 파일 + cross-ref 체크
node verify-independence.js --strict  # + Codex CLI ≥ 0.125.0 체크
```

## 안티패턴

- ❌ Claude 3개와 Codex 3개를 순차 실행 — **반드시 병렬**. 시퀀셜이면 이 skill 쓰는 이유 없음.
- ❌ 교차 합의(Tier 1)가 나왔는데 Tier 3 singleton으로 동등 취급 — confidence tier 준수.
- ❌ 한쪽 엔진 실패 시 조용히 다른 쪽만으로 계속 — fallback 태그 + state.json 기록 필수.
- ❌ argv로 Codex 프롬프트 전달 — 항상 tempfile + stdin.
- ❌ 코드 파일을 `--apply` 류로 수정 — 거부.
- ❌ 이미 합의된 쟁점을 다음 라운드에 재수록 — Round-Delta 위반.
- ❌ 5 라운드 초과 — hard cap.
- ❌ 다른 plugin/skill 파일을 참조 — 전역 hook이 차단.

## 자매 skill과의 관계

| Skill | 엔진 | 언제 쓰는가 |
|---|---|---|
| `/triad` | Claude 3 | Claude 토큰 여유 충분, 빠른 1-엔진 리뷰 |
| `/triad-codex` | Codex 3 | Claude 토큰 아끼고 싶거나 다른 모델 관점 원할 때 |
| `/triad-all` (이 skill) | Claude 3 + Codex 3 | 중요한 파일, 최고 신뢰, 양쪽 토큰 OK |

세 skill은 완전히 독립된 plugin으로 각자 자기 프롬프트·템플릿·Codex 규약을 보유한다. 하나만 설치해도 나머지 없이 동작.
