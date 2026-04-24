---
name: triad-codex
description: Codex-backed 3-perspective deliberation. Like triad but the 3 lenses (LLM clarity / architecture longevity / end-user comprehension) are evaluated by Codex CLI (GPT-5.5 generation) instead of Claude subagents. Use when you want a different-model opinion, or when Claude tokens are scarce. Triggers on "/triad-codex <file>", "triad codex로 검토", "codex로 3관점".
argument-hint: "<file> [--apply] [--apply=original] [--continue <slug>] [--stop <slug>]"
user-invocable: true
---

# triad-codex — Codex-backed 3-Perspective Deliberation

> 메인은 Claude (오케스트레이터), 3 관점 판단은 **Codex CLI**. 목적: Claude self-bias 회피 + Claude 토큰 절약.
> 코드는 절대 수정하지 않는다. md는 `--apply`로 `updated.md`를 생성하고, 원본 교체는 `--apply=original`일 때만.

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
| `.md` | 원본 불변 | updated.md 생성/갱신 | updated.md + 원본 Edit |
| `.py`/`.js`/기타 코드 | 원본 불변 | **무시 (경고)** | **무시 (경고)** |

**불변식**: 코드 파일은 어떤 플래그와도 수정되지 않는다.

슬러그 규칙: 확장자 제거 + 공백/특수문자 `-`로. 예: `src/routes/auth.py` → slug=`auth-py`.

---

## 7단계 워크플로우

### Phase 0: 초기화 (메인)
1. `codex --version` → `0.125.0` 이상인지 확인. 이하면 중단 + upgrade 안내 (`npm install -g @openai/codex@latest`).
2. 모델 선택:
   - `~/.codex/config.toml`의 `model` 값 읽기 (기본 `gpt-5.5`).
   - 해당 모델이 호출 실패하면 `~/.codex/models_cache.json`의 `"visibility": "list"` 첫 slug로 폴백. state.json에 `[model-fallback: <picked>]` 기록.
3. 입력 파일 존재 확인.
4. 슬러그 계산, 출력 디렉토리 생성: `docs/discussion/codex/<slug>/` (코드) 또는 `docs/discussion/codex-md/<slug>/` (md).
5. `source.md` 또는 `source-snapshot.md`로 원본 스냅샷 저장.
6. `state.json` 생성: `{round: 1, status: "open", engine: "codex", codex_version, codex_model, started_at, target_file}`.

### Phase 1: 3 Codex 호출 (메인)

**중요**: 3개 Codex 호출을 **순차**로 실행한다 (Claude Agent 병렬 스폰과 달리 Codex CLI는 한 번에 1 호출이 자연스럽고 토큰 경합이 적음).

각 호출마다:
1. 해당 관점 프롬프트 파일 생성 (`round-{N}.<lens>.prompt.txt`)
2. Codex stdin 호출 (아래 규약 엄수)
3. 응답을 `round-{N}.<lens>.codex.txt`에 저장
4. 응답에서 YAML 블록 추출

3 관점: **llm**, **architect**, **enduser** (순서 고정).

### Phase 2: 합성 (메인)
`round-N.md` 작성. `templates/round.md` 채움. 섹션:
1. 각 관점 YAML 원문 (Codex 응답)
2. 메인(Claude)의 쟁점 합성 (중복 제거, 우선순위)
3. Decision log (ACCEPT/REJECT/DEFER 각 이슈별 한 줄 이유)
4. `--apply` 사용 시 적용한 diff
5. Codex invocation log (bytes_in/out, duration, status)
6. 다음 라운드로 이월할 open issues

### Phase 3: 반영 판단 (메인)
| 입력 유형 | 플래그 | 동작 |
|---|---|---|
| 코드 | (모든 플래그) | 원본 불변. `RECOMMENDATIONS.md`에 권고만 누적. |
| md | 플래그 없음 | 원본 불변. updated.md 생성 안 함. |
| md | `--apply` | 원본 불변. updated.md 생성/갱신. |
| md | `--apply=original` | 위 + 원본 md Edit 반영. diff를 `round-N.md`에 기록. |

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
- 미충족 → round N+1. `state.json` 업데이트. 남은 쟁점만 다음 라운드 입력.
- 충족 → `state.json` status="closed".

## Round-Delta 원칙 (MUST)

라운드 N의 입력 = **지난 라운드 미해소 쟁점 + 원본**. 합의된 건 재논의 금지.

---

## Codex 호출 규약 (엄수)

이 섹션은 이 skill 자체가 보유해야 하는 핵심 계약. 외부 공용 파일에 두지 않는다 (plugin 독립성).

### 불변 규칙

1. **argv 금지** — 절대 `codex exec "$PROMPT_TEXT"` 쓰지 않음. Shell injection 벡터.
2. **tempfile + stdin 강제** — `codex exec ... < "$PROMPT_FILE"` 만 허용.
3. **Heredoc quoted** — prompt body 작성 시 `<<'EOF'` (single-quoted)로 shell expansion 차단.
4. **Dynamic content는 파일 append** — 대상 소스, 이전 라운드 decisions digest 등 **모든 동적 섹션은 `cat <source_file> >> "$PROMPT_FILE"` 패턴만 허용**. `echo "$VAR" >>` 같은 unquoted expansion 금지.
5. **Per-call context guard 180K chars** — prompt 파일이 180,000자를 넘으면 호출 중단, 파일 분할 또는 요약 필요.
6. **Timeout 180s** — `timeout 180 codex exec ...`로 hang 방지. 실측: 대부분 15~40s, cold start 시 최대 52s 관찰됨 (CLI 0.125.0 + gpt-5.5).

### 호출 템플릿

```bash
DIR="docs/discussion/codex/<slug>"
N="<round_number>"
LENS="<llm|architect|enduser>"
PROMPT_FILE="$DIR/round-${N}.${LENS}.prompt.txt"
CODEX_OUT="$DIR/round-${N}.${LENS}.codex.txt"

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

# (round >= 2일 때만) 지난 라운드 CONSENSUS 섹션 append
if [ "$N" -ge 2 ]; then
  cat >> "$PROMPT_FILE" <<'EOF'

## 지난 라운드 합의 (이미 해소된 쟁점은 재논의 금지)
EOF
  cat "$DIR/round-$((N-1)).carryover.txt" >> "$PROMPT_FILE"
fi

cat >> "$PROMPT_FILE" <<'EOF'

## 출력 포맷 (엄수)
```yaml
verdict: PASS | REVISE | BLOCK
top_issues:
  - severity: high | med | low
    locus: "..."
    problem: "..."
    proposed_fix: "..."
open_questions:
  - "..."
```
EOF

# 2. context guard
BYTES=$(wc -c < "$PROMPT_FILE")
if [ "$BYTES" -gt 180000 ]; then
  echo "[triad-codex] FAIL prompt ${BYTES}B > 180K for ${LENS}" >&2
  exit 2
fi

# 3. Codex 호출 (stdin)
CODEX="${CODEX:-codex exec --dangerously-bypass-approvals-and-sandbox}"
timeout 120 $CODEX < "$PROMPT_FILE" > "$CODEX_OUT" 2>&1 || {
  echo "[triad-codex] WARN Codex call failed for ${LENS} — fallback" >&2
  echo "[fallback: codex-unavailable]" > "$CODEX_OUT"
}
```

### 출력 포맷 (gpt-5.5, CLI 0.125.0 기준)

Codex 응답은 다음 패턴으로 stdout에 찍힌다:

```
(prompt echo …)
codex
verdict: REVISE
top_issues:
  - severity: high
    locus: "..."
    ...
tokens used
<N>
```

**파서 규약 (엄수)**:
1. **` ```yaml ... ``` ` fence를 찾지 마라** — 5.5는 fence를 안 붙인다. 0.123.0 시절 파서는 무효.
2. 본 응답은 **`^codex$` 마커 라인 직후 `^verdict:`부터 시작**. `^tokens used$`를 만나면 종료.
3. 구버전(0.123.0) 호환 파서를 유지하려면 fenced YAML도 감지하되, 0.125.0+ 로그에서 fenced가 안 나오므로 **raw-YAML 경로를 기본**으로.

**무해한 경고 무시**:

```
ERROR codex_core::session: failed to record rollout items: thread ... not found
```

stderr에 찍히지만 응답은 유효. 로그 파싱 시 필터링.

### Fallback 정책

Codex 호출 실패 시 (timeout, exit != 0, 빈 응답, YAML 추출 실패):
1. 첫 실패 → Phase 0에서 선정한 폴백 모델로 1회 재시도. 성공 시 `state.json`에 `[model-fallback: <picked>]` 기록.
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
├── codex-md/<slug>/                    # md 입력
│   ├── source.md
│   ├── state.json
│   ├── round-1.md
│   ├── round-1.llm.prompt.txt
│   ├── round-1.llm.codex.txt
│   ├── round-1.architect.prompt.txt
│   ├── round-1.architect.codex.txt
│   ├── round-1.enduser.prompt.txt
│   ├── round-1.enduser.codex.txt
│   ├── round-1.carryover.txt
│   ├── ...
│   ├── CONSENSUS.md
│   └── updated.md
│
└── codex/<slug>/                       # 코드 입력
    ├── source-snapshot.md
    ├── state.json
    ├── round-N.md
    ├── round-N.<lens>.prompt.txt
    ├── round-N.<lens>.codex.txt
    ├── CONSENSUS.md
    └── RECOMMENDATIONS.md
```

## 자립성 검증

이 skill 디렉토리에서:
```bash
node verify-independence.js
# 통과 = 다른 plugin/skill에 의존하지 않고, 필수 파일 모두 존재.
node verify-independence.js --strict
# 추가: Codex CLI 존재까지 체크.
```

## 참조 (이 skill 내부에 한함)

- 에이전트 프롬프트: `agents/llm-perspective.md`, `agents/architect-perspective.md`, `agents/enduser-perspective.md`
- 템플릿: `templates/round.md`, `templates/consensus.md`
- 자립성 체크: `verify-independence.js`

## 안티패턴

- ❌ Codex 실패 시 조용히 Claude로 대체 — `[fallback]` 태그 필수.
- ❌ 3 관점을 서로 다른 프롬프트 구조로 호출 — 모두 `agents/<lens>-perspective.md` 기반.
- ❌ argv로 프롬프트 전달 — 항상 tempfile + stdin.
- ❌ 코드 파일을 `--apply`로 수정 — 거부.
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
