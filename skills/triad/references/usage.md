# Triad 사용 예시

## 예시 1: md 문서 리뷰 (read-only)

```
/triad docs/design/architecture.md
```

결과:
- `docs/discussion/architecture/source.md` — 원본 스냅샷
- `docs/discussion/architecture/round-1.md` — 3 관점 + 합성
- 필요 시 round-2, round-3, ...
- `docs/discussion/architecture/CONSENSUS.md` — 최종 합의
- 원본 파일은 **건드리지 않음**

## 예시 2: md 문서 + 자동 반영

```
/triad docs/design/architecture.md --apply
```

결과:
- 위 파일들 + `updated.md` — 합의된 개선 적용본
- 원본 `docs/design/architecture.md`에도 Edit으로 반영
- 각 round-N.md의 "Applied Changes" 섹션에 diff 기록

## 예시 3: 코드 파일 리뷰 (항상 read-only)

```
/triad src/api/handlers.py
/triad src/api/handlers.py --apply    # --apply 무시됨, 경고 후 진행
```

결과:
- `docs/discussion/code/handlers-py/source-snapshot.md` — 코드를 md로 스냅샷
- `docs/discussion/code/handlers-py/round-N.md` — 3 관점 리뷰
- `docs/discussion/code/handlers-py/CONSENSUS.md` — 합의
- `docs/discussion/code/handlers-py/RECOMMENDATIONS.md` — **pumasi tasks 호환 포맷의 구현 권고**
- 원본 `.py`는 **절대 수정 안 함**

## 예시 4: 이어하기

```
/triad --continue architecture
```

기존 `docs/discussion/<slug>/`의 state.json을 읽어 다음 라운드 진행.

## 예시 5: 강제 종결

```
/triad --stop <slug> --reason "충분함"
```

state.json을 closed로 마크, CONSENSUS.md를 그 시점까지의 내용으로 작성.

---

## 언제 쓰는가 (Use)

- 설계 방향이 두 갈래 이상 있는 문서 (예: SQLite vs Postgres 선택)
- 용어/네이밍이 장기에 영향 (DB 컬럼명, API path, 이벤트 이름)
- LLM이 자주 읽는 문서 (`.claude/CLAUDE.md`, rules/*.md) — LLM 관점 특히 가치
- 낡아 보이는 `docs/`의 문서들
- 리팩토링 전 코드 파일 (권고안 뽑아서 pumasi로 재구현)

## 언제 쓰지 말 것 (Skip)

- 표준 기능 구현 ("Todo 앱 만들기") — 바로 pumasi
- 버그 수정, 소규모 개선 — Claude 직접
- 이미 ADR/PRD가 명확한 경우
- 개인 메모, 임시 노트

## 실전 교훈 (첫 드라이런, 2026-04-15, 대상: .claude/CLAUDE.md)

드라이런에서 발견된 skill 운영 규칙:

1. **리뷰 프롬프트에서 대상 내용을 축약하지 말 것.**
   첫 번째 R2 실행 시 메인이 프롬프트 길이를 줄이려 `[command block with: ...]` 같은 placeholder로 대상 파일 일부를 생략했더니, EndUser 에이전트가 그 placeholder 자체를 "opaque content"로 정확히 지적함. **대상 파일은 반드시 full text로 넘겨라.** 토큰 경제보다 리뷰 fidelity 우선.
2. **R1 수정의 사실 검증은 R2의 주 과제 중 하나다.**
   메인이 R1에서 `processing.confidence_thresholds` 같은 설정 경로를 **검증 없이 가정**하면 R2가 그 거짓을 잡아냄. 즉 triad는 메인의 착각도 catch하는 2차 필터 역할. 이걸 설계된 동작으로 받아들이고 R1 수정 전 코드베이스 조사를 선제적으로 하는 게 좋다.
3. **3-agent 수렴은 강력한 신호.**
   Port fallback 드리프트처럼 3 관점이 동시 지적하면 메인이 결정 망설임 없이 ACCEPT. 반대로 1 관점만 지적한 low severity는 DEFER/REJECT 비율이 높음. 수렴 수를 decision weight로 쓰면 합성이 간결해짐.
4. **Open question은 라운드 내에 해소돼야 라운드가 끝난다.**
   EndUser의 Q1(audience)이 한 라운드 결정 14개 중 7개를 바꿨음. 메인이 답 못 구하면 유저에게 바로 escalate — 유예 금지.

## 5-agent team rule 관계

프로젝트에 "review/refactor/analysis 작업은 5 parallel agents" 규칙이 있지만, **triad는 예외**다.
이유: 3 관점(LLM/Architect/EndUser)의 고정 비대칭성이 triad의 identity. 관점 수가 늘면 렌즈가 희석된다.
무차별 리뷰가 필요하면 `/review-all`(4-agent) 또는 `/gsd-review`를 사용.
