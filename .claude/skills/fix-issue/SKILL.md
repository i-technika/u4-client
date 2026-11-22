---
name: fix-issue
description: >-
  서브이슈 번호를 받아 브랜치 생성, 구현, 로컬 검증, PR 작성, 독립 서브에이전트를 통한 2라운드 적대적 코드리뷰와 수정,
  후속 이슈 등록, Linux CI 확인, 마일스톤 브랜치 머지, 이슈 Close 및 프로젝트 보드 Done 처리까지 일괄 수행한다.
  마일스톤 에픽 이슈 번호가 들어오면 거절한다. 사용자가 `/fix-issue <번호>`를 입력하거나 "8번 이슈 진행해줘"처럼
  특정 서브이슈 작업을 요청할 때 사용한다.
argument-hint: <서브이슈 번호>
---

# 서브이슈 처리 + 2라운드 적대적 코드리뷰 (`/fix-issue <번호>`)

입력: `$ARGUMENTS` = 서브이슈 번호 (예: `8`)

> 규칙의 기준은 [CLAUDE.md](../../../CLAUDE.md)이다. 명령은 Bash 도구로 실행하고,
> `flutter`가 없으면 `export PATH="/c/Users/fmthead/develop/flutter/bin:$PATH"`를 앞에 붙인다.
> `gh`에 여러 줄 본문을 넘길 때는 스크래치패드 파일 + `--body-file`을 사용한다.

## 🚫 거절 규칙
- 이슈에 `milestone` 라벨이 있으면 즉시 중단:
  > ⚠️ 이슈 #<번호>는 마일스톤 에픽 이슈이므로 `/fix-issue`로 수행할 수 없습니다. 마일스톤 착수는 `/open-ms <번호>`, 개발은 서브이슈 번호를 지정해 주세요.
- 이슈가 이미 `CLOSED`면 현황만 보고하고 재작업 여부를 묻는다 (단일 선택 질의, CLAUDE.md "질의 규칙").

## 진행 순서
```
1 이슈 분석 → 2 브랜치 → 3 구현·검증 → 4 커밋·PR → 5 리뷰 R1 → 6 수정 → 7 리뷰 R2 → 8 수정
→ 9 후속 이슈 등록 → 10 CI 확인 → 11 머지·Close·보드 Done → 12 보고
```
TodoWrite 등으로 단계를 추적하고, 각 단계 완료 시 짧게 진행 상황을 알린다.

### 1. 이슈 분석
```bash
gh issue view <번호> --json number,title,body,labels,milestone,parent,state,issueType
```
- 상위 에픽(`parent.number`)으로 마일스톤 번호 N을 정하고 베이스 브랜치 `milestone/m<N>`을 확인한다.
- 같은 마일스톤의 다른 서브이슈 본문도 훑어 **이번 이슈의 범위 경계**를 파악한다(다음 이슈의 일을 미리 하지 않는다).
- 원격/로컬에 이미 `issue/<번호>-*` 브랜치나 미커밋 작업물(이전 에이전트의 WIP 등)이 있으면 내용을 검토해 재사용 여부를 판단한다.
- 담당자 지정: `gh issue edit <번호> --add-assignee i-technika` (이미 지정돼 있으면 그대로 둔다)
- 프로젝트 보드: `bash .claude/scripts/set-project-status.sh <번호> "In Progress"`

### 2. 브랜치 생성
```bash
git checkout milestone/m<N> && git pull --ff-only origin milestone/m<N>
git checkout -b issue/<번호>-<영문-키워드>
```
- 미커밋 WIP 파일이 있으면 브랜치 전환 시 그대로 따라오는지 확인한다(추적되지 않은 파일은 따라온다).

### 3. 구현 및 로컬 검증
- CLAUDE.md 규칙 준수: 한국어 주석, `material_ui` import, 웹 표준 API는 폴리필로 처리, 메인·팝업 `AppWebView` 동작 동일, 설정 스키마와 Dart 모델 동시 수정.
- 이슈 체크리스트의 산출물을 모두 만든다. 상수/명세 데이터에는 불변식 테스트를 추가한다.
- ```bash
  flutter analyze   # No issues found! 이어야 함
  flutter test      # All tests passed! 이어야 함
  ```
- 네이티브·웹뷰 동작이 바뀌면 Android 에뮬레이터에서 확인한다 (`flutter build apk --debug --flavor dev` → `adb install -r`).
  기능 테스트 페이지(`test-page/`)로 확인할 수 있으면 해당 항목을 돌린다.
- iOS 실기기·시뮬레이터 확인은 하지 않고 PR에 미확인 항목으로도 적지 않는다 (CLAUDE.md 3장).

### 4. 커밋·푸시·PR
```bash
git add <변경 파일들>   # git add . 대신 명시적으로
git commit -m "feat: <이슈 제목 요약> (#<번호>)"
git push -u origin issue/<번호>-<키워드>
```
PR 본문 파일(`<scratchpad>/pr-<번호>.md`):
```markdown
## 작업 요약
- ...

## 변경 파일
- `path` — 설명

## 검증
- `flutter analyze`: No issues found
- `flutter test`: N개 통과
- Android 에뮬레이터: (확인한 경우 항목과 결과)

## 적대적 코드리뷰
- R1: (리뷰 후 갱신)
- R2: (리뷰 후 갱신)

Closes #<번호>
```
```bash
gh pr create --base milestone/m<N> --head issue/<번호>-<키워드> \
  --title "<이슈 제목 그대로> (#<번호>)" \
  --body-file "<scratchpad>/pr-<번호>.md" \
  --label sub-issue --milestone "<마일스톤 이름>" --project "U4 Client" \
  --assignee i-technika
```
- 이 브랜치의 PR이 이미 있으면(이전 작업 재사용) 새로 만들지 않고 담당자만 붙인다: `gh pr edit <PR> --add-assignee i-technika`

### 5. 적대적 코드리뷰 R1 (독립 서브에이전트)
- 구현자의 편향을 피하기 위해 **새 컨텍스트의 `general-purpose` 서브에이전트**에게 리뷰를 맡긴다. 프롬프트에 포함할 것:
  - 이슈 번호·목표·체크리스트, 베이스 브랜치, `git diff milestone/m<N>...HEAD`로 diff를 직접 보라는 지시
  - 역할: "이 변경을 머지시키지 않으려는 회의적인 시니어 리뷰어. 칭찬 없이 결함만, 심각도(Critical/Major/Minor)와 파일:라인, 근거, 수정안 제시"
  - 점검 항목: 이슈 요구사항 충족 여부, 웹 표준 동작 호환(브라우저와 같은 결과·에러 코드), Android/iOS 플랫폼 차이,
    권한 흐름(허용/거부/영구 거부), 설정 스키마와 `AppConfig`의 일치, flavor(dev/stg/prod)별 차이와 prod 노출 위험,
    Null Safety, 예외 처리, 웹뷰·리스너 해제 누락, 팝업 안에서도 같은 동작인지, 테스트 누락·허술한 테스트,
    다음 서브이슈와의 인터페이스 적합성, CLAUDE.md 위반
  - "코드를 수정하지 말고 보고만 할 것"
- 결과를 검토해 타당한 지적과 기각할 지적(근거 포함)을 구분한다. 리뷰 결과를 PR 코멘트로 남긴다:
  `gh pr comment <PR> --body-file <scratchpad>/review-r1.md`

### 6. R1 수정
- 타당한 지적을 모두 반영하고 `flutter analyze && flutter test` 통과 후 커밋:
  `refactor: Address adversarial review R1 for #<번호>`

### 7. 적대적 코드리뷰 R2 (새 서브에이전트)
- R1과 **다른 새 서브에이전트**에게 R1 지적 목록과 수정 커밋을 알려주고, 회귀·미반영·새 엣지 케이스를 검토시킨다.
- 결과를 PR 코멘트로 남긴다 (`review-r2.md`).

### 8. R2 수정
- 반영 후 검증·커밋: `refactor: Address adversarial review R2 for #<번호>` → `git push`
- PR 본문의 "적대적 코드리뷰" 섹션을 실제 결과로 갱신한다 (`gh pr edit <PR> --body-file ...`).

### 9. 후속 이슈 등록 (사용자에게 묻지 않고 직접 판단)
- 구현·리뷰 중 이번 범위 밖으로 미룬 개선점/리팩토링/검증 과제를 정리하고, **등록할 항목을 Claude가 직접 고른다**
  (CLAUDE.md "질의 규칙" — 여러 개를 고르는 체크박스 질의는 하지 않는다).
  - 먼저 경계: **이번 이슈 범위 안의 결함은 미루지 않고 이번 PR에서 고친다.** 후속 이슈는 범위 밖의 일만 대상이다.
  - 등록: 범위 밖의 실제 결함, 누락된 검증, 실기기 확인처럼 나중에 누군가 해야 하는 일.
    리팩토링·개선은 **구체적인 재현 근거나 측정 근거**(깨지는 입력, 수치, 중복 코드 위치 등)가 있을 때만 등록한다.
  - 등록하지 않음: 이번 PR에서 이미 고친 것, 근거가 약한 취향 수준 지적, 기존 이슈와 겹치는 것(기존 이슈에 코멘트로 보탬).
    겹침 확인은 검색이 아니라 열린 서브이슈 전체 목록으로 한다(다른 마일스톤 포함 — 한국어 제목은 검색 색인으로 잘 찾아지지 않는다):
    `gh issue list --label sub-issue --state open -L 300 --json number,title,milestone`
  - 12단계 보고에 등록한 것·등록하지 않은 것과 각각의 이유를 적는다.
- 제목에는 순번 접두사(`[M<N>-<순번>]`)를 붙이지 않는다 — 이슈 번호·마일스톤·상위 에픽으로 식별한다.
- **마일스톤 기준**: `<마일스톤 이름>`·`<에픽번호>`는 지금 작업 중인 마일스톤이 아니라 **그 후속 이슈가 속할 마일스톤** 기준이다
  (다른 마일스톤에 속하는 과제는 그 마일스톤과 에픽으로 만든다 — 예: 파일 업로드 권한 과제면 `M8: 파일 업로드` 마일스톤, 에픽 #23).
- 항목마다 **A 블록(생성) → B 블록(연결)** 을 각각 한 번의 Bash 호출로 실행한다 (셸 변수는 호출 사이에 남지 않으므로
  A가 출력한 번호를 B의 `NUM=`에 적는다).
  - **A는 같은 항목에 대해 "만들어지지 않았다"고 출력했을 때만 다시 실행한다.** 그 밖의 중단(생성 여부 불명 등)에서는 다시 만들지 않는다.
  - **B는 몇 번을 다시 실행해도 안전하다**(이미 된 단계는 건너뛴다). 어디서 멈췄든 B만 다시 실행해 마무리한다.

  **A 블록 — 생성**
  ```bash
  set -e
  TITLE='<제목>'   # 제목에 작은따옴표가 있으면 '\'' 로 바꿔 쓴다
  TITLE=$(printf '%s' "$TITLE" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')   # GitHub이 앞뒤 공백을 다듬어 저장하므로 미리 맞춘다
  # 이슈 목록("번호<TAB>제목"). 검색(--search)은 한국어·특수문자 제목과 색인 지연 때문에 못 찾으므로 목록에서 정확히 비교한다.
  # 조회 실패와 "목록에 없음"을 구별해야 하므로 파이프로 바로 잇지 않고 변수로 받아 상태를 확인한다(파이프는 gh 실패를 삼킨다).
  rows() { gh issue list --state all -L "$1" --json number,title --jq '.[] | "\(.number)\t\(.title)"'; }
  match() { printf '%s\n' "$1" | T="$TITLE" awk -F'\t' 'substr($0, length($1) + 2) == ENVIRON["T"] { print $1; exit }'; }
  # 1) 같은 제목이 이미 있으면 만들지 않는다 — 그래야 실패 뒤 "같은 제목 = 이번에 만든 이슈"로 판정할 수 있다
  ALL=$(rows 1000) || { echo "목록 조회 실패 — 아무것도 만들지 않았다. 다시 실행해도 된다"; exit 1; }
  DUP=$(match "$ALL")
  [ -z "$DUP" ] || { echo "같은 제목의 이슈 #$DUP 이 이미 있다 — 만들지 않음(그 이슈와 겹치는지 판단해 제목을 바꾸거나 그 이슈에 코멘트)"; exit 1; }
  # 2) 생성. gh는 이슈를 만든 뒤 프로젝트 추가 단계에서 실패할 수 있다 → 실패해도 다시 만들지 않고 생겼는지 확인한다
  if URL=$(gh issue create --title "$TITLE" --body-file <파일> \
      --label sub-issue --milestone "<마일스톤 이름>" --project "U4 Client"); then
    NUM=${URL##*/}
  else
    NUM=""
    for i in 1 2 3; do
      sleep 3
      RECENT=$(rows 30) || { echo "생성 여부 불명(목록 조회도 실패) — 다시 만들지 말 것. 나중에 gh issue list로 이 제목을 확인한 뒤 B 블록"; exit 1; }
      NUM=$(match "$RECENT")
      [ -z "$NUM" ] || break
    done
    [ -n "$NUM" ] || { echo "목록에 없음 — 이슈가 만들어지지 않았다. 원인을 고친 뒤 A 블록을 다시 실행해도 된다"; exit 1; }
    echo "생성은 됐고 뒤 단계(프로젝트 추가 등)가 실패함 — B 블록이 마무리한다"
  fi
  [[ $NUM =~ ^[0-9]+$ ]] || { echo "이슈 번호를 읽지 못했다: $URL — 다시 만들지 말고 gh issue list로 확인"; exit 1; }
  echo "생성: #$NUM → B 블록에 NUM=$NUM"
  ```

  **B 블록 — 프로젝트·에픽·타입 (다시 실행해도 안전)**
  ```bash
  set -e
  NUM=<A가 출력한 번호>; EPIC=<에픽번호>; TYPE=<타입 id>
  # 프로젝트 추가 — 이미 들어 있으면 그대로다(A의 실패 원인일 수 있어 항상 한 번 더 한다)
  gh issue edit "$NUM" --add-project "U4 Client" >/dev/null
  # 상위 에픽 연결 — 이미 연결돼 있으면 건너뛴다(addSubIssue는 중복 연결 시 오류)
  PARENT=$(gh issue view "$NUM" --json parent --jq '.parent.number // empty')
  ISSUE_ID=$(gh issue view "$NUM" --json id --jq .id)   # ID는 변수로 먼저 받는다 — 인자 안의 $(...) 실패는 set -e가 잡지 못한다
  if [ -z "$PARENT" ]; then
    EPIC_ID=$(gh issue view "$EPIC" --json id --jq .id)
    gh api graphql -f query='mutation($p:ID!,$c:ID!){addSubIssue(input:{issueId:$p,subIssueId:$c}){issue{number}}}' \
      -f p="$EPIC_ID" -f c="$ISSUE_ID" >/dev/null
  elif [ "$PARENT" != "$EPIC" ]; then
    echo "#$NUM 은 이미 다른 에픽 #$PARENT 에 연결돼 있다 — 확인 필요"; exit 1
  fi
  # 이슈 타입(Task/Bug/Feature) 지정 — 같은 값으로 다시 지정해도 무방
  gh api graphql -f query='mutation($i:ID!,$t:ID!){updateIssueIssueType(input:{issueId:$i,issueTypeId:$t}){issue{number}}}' \
    -f i="$ISSUE_ID" -f t="$TYPE" >/dev/null
  echo "완료: #$NUM (프로젝트·에픽 #$EPIC·타입)"
  ```
  타입 ID: Task `IT_kwDOBMwL0c4PCk6t`, Bug `IT_kwDOBMwL0c4PCk6u`, Feature `IT_kwDOBMwL0c4PCk6v` (CLAUDE.md "식별자")
  - 성격에 따라 `bug`·`enhancement` 라벨을 함께 붙인다 (A 블록의 `--label sub-issue` 뒤에 `--label bug`처럼 추가).
- 후속 이슈는 아직 착수 전이므로 담당자를 지정하지 않는다 (착수할 때 1단계에서 지정).

### 10. Linux CI 확인
```bash
gh pr checks <PR> --watch
```
- `Linux Analyze, Test & Build`가 통과해야 한다. 실패 시 로그(`gh run view --log-failed`)로 원인을 고친다.

### 11. 머지·이슈 Close·보드 갱신
```bash
gh pr merge <PR> --squash --delete-branch \
  --subject "<PR 제목> (#<PR번호>)"
```
- 마일스톤 브랜치로의 머지에는 `Milestone Full CI`가 돌지 않는다(정상).
- 서브이슈 PR은 기본 브랜치가 아닌 곳으로 머지되므로 **이슈가 자동 Close되지 않는다** → 직접 처리:
  1. 이슈 본문 체크리스트를 `[x]`로 갱신 (`gh issue edit <번호> --body-file ...`)
  2. `gh issue close <번호> --reason completed --comment "PR #<PR번호>로 milestone/m<N>에 머지 완료"`
  3. `bash .claude/scripts/set-project-status.sh <번호> Done` / `... <PR번호> Done`
  4. 마일스톤 PR 본문의 서브이슈 체크리스트가 있으면 해당 항목을 `[x]`로 갱신
- 로컬 정리: `git checkout milestone/m<N> && git pull --ff-only origin milestone/m<N>`

### 12. 보고
- PR/머지 커밋 링크, 변경 요약, 리뷰 R1/R2에서 고친 것, 기각한 지적(이유), 후속 이슈(등록한 것·등록하지 않은 것과 이유), 다음 서브이슈 번호를 짧게 보고한다.
