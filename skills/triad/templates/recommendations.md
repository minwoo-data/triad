# RECOMMENDATIONS

> 코드 입력에만 생성. triad는 코드를 직접 수정하지 않으므로, 이 문서가 **다음 단계의 입력**이다.
> 포맷은 pumasi의 `tasks[].instruction`과 호환되도록 설계됨. pumasi로 바로 복사해 쓸 수 있다.

**Source file**: `{target_file}`
**Consensus rounds**: {N}
**Date**: {timestamp}

---

## Summary

3 관점 합의 기반, 이 파일에 대한 권고 사항. 세 종류로 분류:

- **REPLACE** - 현재 파일을 새 설계로 대체
- **REFACTOR** - 현재 구조 유지하며 개선
- **ADDITIVE** - 현재 파일은 두고 새 파일/함수 추가

---

## Task 1: {task-name}

### 분류
{REPLACE | REFACTOR | ADDITIVE}

### 대상 경로
```
{target path, 절대 또는 repo-relative}
```

### 시그니처
```python
def new_function_name(arg1: Type1, arg2: Type2) -> ReturnType:
    ...
```

(코드가 아닌 규약/구조 권고면 이 섹션 생략하고 "요구사항"으로 대체)

### 요구사항
- 라이브러리: {specific lib, 필수 import 1줄}
- 제약사항: {금지 사항 명시}
- 스타일: {ESM/strict mode 등}

### 이 권고가 나온 근거
- [R1] LLM: ...
- [R2] Architect: ...
- [R2] EndUser: ...

### 게이트 힌트 (pumasi 사용 시)
```yaml
gates:
  - name: "파일 존재"
    command: "[ -f {path} ]"
  - name: "타입 체크"
    command: "npx tsc --noEmit {path}"
  - name: "시그니처 확인"
    command: "grep -q '{function_name}' {path}"
```

### 리스크
- 이 변경이 깨뜨릴 수 있는 의존자: ...
- 마이그레이션 필요 여부: ...

---

## Task 2: {...}

(위 구조 반복)

---

## Downstream 사용법

### 옵션 A: pumasi에 주입
1. `pumasi.config.yaml`의 `tasks:` 배열에 위 Task들을 복사
2. `/pumasi` 실행
3. Phase 5.7에 `/review-all` 훅 (선택)

### 옵션 B: Claude 직접 구현
1. Task를 순서대로 Claude에게 전달
2. 완료 후 `/mangchi`로 Codex 2차 리뷰 (향후 skill)

### 옵션 C: 보관만
- 당장 구현 안 하고 이 문서만 유지
- 미래 관련 작업 시 참조 자료로 사용

---

## 적용 시 주의

- 이 권고들은 **3 관점 합의 시점의 판단**이다. 코드베이스가 크게 바뀌었다면 재검토 필요.
- pumasi로 구현 시 반드시 `codex-guide.md`의 안티패턴(복붙형 instruction 금지) 준수.
- REPLACE 태스크는 항상 git 백업 후 실행.
