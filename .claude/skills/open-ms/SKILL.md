---
name: open-ms
description: >-
  마일스톤 에픽 이슈 번호를 받아 main에서 milestone/m<N> 브랜치를 분기하고, 마일스톤 통합 Draft PR을 생성해
  라벨·마일스톤·프로젝트·Development(Closes)를 연결한 뒤 프로젝트 보드를 In Progress로 갱신한다.
  사용자가 `/open-ms <번호>`를 입력하거나 "마일스톤 M2 시작해줘"처럼 새 마일스톤 착수를 요청할 때 사용한다.
argument-hint: <마일스톤 에픽 이슈 번호>
---

# 마일스톤 착수 (`/open-ms <번호>`)

입력: `$ARGUMENTS` = 마일스톤 에픽 이슈 번호 (예: `1` → M1)

> 규칙의 기준은 [CLAUDE.md](../../../CLAUDE.md)이다. 명령은 Bash 도구로 실행한다.
> `gh`에 여러 줄 본문을 넘길 때는 스크래치패드에 파일을 만들고 `--body-file`을 사용한다.

## 1. 에픽 이슈 검증
```bash
gh issue view <번호> --json number,title,body,labels,milestone,state,subIssues
```
- `labels`에 `milestone`이 없으면 중단하고 안내한다:
  > ⚠️ 이슈 #<번호>는 마일스톤 에픽 이슈가 아닙니다. `/open-ms`에는 에픽 번호(예: #1)를 지정해 주세요. 서브이슈는 `/fix-issue`를 사용합니다.
- 이미 `milestone/m<번호>` 브랜치나 열린 마일스톤 PR이 있으면(`gh pr list --head milestone/m<번호>`) 새로 만들지 말고 현황만 보고한다.
  이때도 담당자는 맞춰 둔다: `gh issue edit <번호> --add-assignee i-technika`, `gh pr edit <PR번호> --add-assignee i-technika`
- 이전 마일스톤이 아직 `main`에 머지되지 않았다면 단일 선택으로 묻는다 (마일스톤은 순차 진행이 원칙):
  "이전 마일스톤을 먼저 마무리 (Recommended)" / "그래도 새 마일스톤 착수".

## 2. 브랜치 생성
1. `git status --porcelain`으로 작업 트리가 깨끗한지 확인한다. 변경 사항이 있으면 단일 선택으로 묻는다 (CLAUDE.md "질의 규칙"):
   "변경 내용을 보여 주고 중단 (Recommended)" / "stash 후 진행" / "그대로 둔 채 진행".
2. ```bash
   git checkout main && git pull --ff-only origin main
   git checkout -b milestone/m<번호>
   git commit --allow-empty -m "chore: Open milestone M<번호> (#<번호>)"
   git push -u origin milestone/m<번호>
   ```

## 3. 마일스톤 Draft PR 생성
본문 파일 예시 (`<scratchpad>/ms-pr-body.md`):
```markdown
## 마일스톤 M<번호> 통합 PR

M<번호> 마일스톤(<에픽 제목에서 [M<번호>] 제외>)의 세부 서브이슈들을 통합하는 PR입니다.

### 서브이슈
- [ ] #<서브이슈1> <제목>
- [ ] ...

Closes #<번호>
```
```bash
gh pr create --base main --head milestone/m<번호> --draft \
  --title "<에픽 제목> (#<번호>)" \
  --body-file "<scratchpad>/ms-pr-body.md" \
  --label milestone --milestone "<마일스톤 이름>" --project "U4 Client" \
  --assignee i-technika
```
- Draft로 유지해야 서브이슈 개발 중 `Milestone Full Multi-Platform CI`가 돌지 않는다.

## 4. 담당자·프로젝트 보드 갱신
```bash
gh issue edit <번호> --add-assignee i-technika   # 착수한 에픽의 담당자 (서브이슈는 /fix-issue 착수 시 지정)
bash .claude/scripts/set-project-status.sh <번호> "In Progress"
bash .claude/scripts/set-project-status.sh <PR번호> "In Progress"
```

## 5. 완료 보고
- 브랜치명, PR URL, 서브이슈 목록(번호·제목·상태)을 보고하고 첫 서브이슈를 `/fix-issue <번호>`로 착수할 수 있음을 안내한다.
