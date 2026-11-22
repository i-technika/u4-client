---
name: close-ms
description: >-
  마일스톤 에픽 번호를 받아 모든 서브이슈 완료를 검증하고, 마일스톤 Draft PR을 Ready로 전환해 멀티플랫폼 전체 CI를 통과시킨 뒤
  main에 머지하고 에픽 이슈·milestone.md·프로젝트 보드를 완료 처리한다.
  사용자가 `/close-ms <번호>`를 입력하거나 "M1 마무리/main에 머지해줘"처럼 마일스톤 종료를 요청할 때 사용한다.
argument-hint: <마일스톤 에픽 이슈 번호>
---

# 마일스톤 완료 및 main 머지 (`/close-ms <번호>`)

입력: `$ARGUMENTS` = 마일스톤 에픽 이슈 번호

> 규칙의 기준은 [CLAUDE.md](../../../CLAUDE.md)이다. `main` 머지는 되돌리기 어려운 작업이므로
> **4단계 머지 직전에 반드시 사용자에게 최종 확인**을 받는다.

## 1. 완료 상태 점검
```bash
gh issue view <번호> --json number,title,labels,subIssues,milestone
gh issue list --milestone "<마일스톤 이름>" --state open --json number,title,labels
```
- `milestone` 라벨이 없으면 중단한다.
- 열린 서브이슈가 있으면 목록을 보여 주고 단일 선택으로 묻는다 (CLAUDE.md "질의 규칙"):
  "남은 서브이슈를 먼저 처리 (Recommended)" / "다음 마일스톤으로 옮기고 진행" / "그대로 진행".

## 2. 마일스톤 브랜치 최종 점검
```bash
git checkout milestone/m<번호> && git pull --ff-only origin milestone/m<번호>
git fetch origin main && git merge-base --is-ancestor origin/main HEAD || echo "main이 앞서 있음 → 병합 필요"
flutter analyze && flutter test
```
- `main`이 앞서 있으면 `git merge origin/main`으로 반영 후 푸시한다 (충돌 시 충돌 파일과 각 해결안을 보여 주고 단일 선택으로 묻는다 — 추천안에 `(Recommended)`).
- [milestone.md](../../../milestone.md)의 해당 마일스톤 체크박스와 제목 `[ ]`를 `[x]`로 갱신해 커밋·푸시한다:
  `docs: Mark milestone M<번호> complete in milestone.md (#<번호>)`
- 에픽 이슈 본문의 체크리스트도 완료 항목을 `[x]`로 갱신한다 (`gh issue edit <번호> --body-file ...`).

## 3. PR Ready 전환 및 전체 CI
```bash
gh pr list --head milestone/m<번호> --json number,url,isDraft
gh pr ready <PR번호>
gh pr checks <PR번호> --watch --fail-fast
```
- 대상 Job: `Code Quality`, `Android Build (APK)`, `iOS Build (No CodeSign)`
- 실패 시: 로그(`gh run view <run-id> --log-failed`)를 분석해 원인을 보고한다. 수정이 필요하면
  사용자 승인 후 서브이슈를 만들어(`/fix-issue` 9단계 A·B 블록) `/fix-issue`로 처리하거나, 사소한 빌드 설정은 마일스톤 브랜치에 직접 커밋한다.

## 4. main 머지 (사용자 확인 후)
```bash
gh pr merge <PR번호> --merge --delete-branch=false
```
- 마일스톤 브랜치는 이력 추적을 위해 원격에 남겨 둔다(삭제를 원하면 사용자 지시에 따름).

## 5. 이슈·보드 마무리
```bash
gh issue view <번호> --json state   # Closes #<번호>로 자동 Close되었는지 확인, 아니면 gh issue close
bash .claude/scripts/set-project-status.sh <번호> Done
bash .claude/scripts/set-project-status.sh <PR번호> Done
```

## 6. 로컬 동기화 및 보고
```bash
git checkout main && git pull --ff-only origin main
```
- 머지 커밋, CI 결과 요약, 다음 마일스톤 에픽 번호를 보고하고 `/open-ms <다음 번호>`를 안내한다.
