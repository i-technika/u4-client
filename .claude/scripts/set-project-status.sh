#!/usr/bin/env bash
# GitHub Project #8(U4 Client)에서 이슈/PR의 Status를 변경한다.
# 사용법: bash .claude/scripts/set-project-status.sh <이슈|PR 번호> <Todo|"In Progress"|Done>
# 항목이 프로젝트에 없으면 먼저 추가한 뒤 상태를 설정한다.
set -euo pipefail

NUMBER="${1:?이슈/PR 번호를 입력하세요}"
STATUS="${2:?상태(Todo | In Progress | Done)를 입력하세요}"

OWNER="i-technika"
REPO="i-technika/u4-client"
PROJECT_NUMBER=8
PROJECT_ID="PVT_kwHOBMwL0c4Bsrv0"
STATUS_FIELD_ID="PVTSSF_lAHOBMwL0c4Bsrv0zhq4uqM"

case "$STATUS" in
  "Todo")        OPTION_ID="f75ad846" ;;
  "In Progress") OPTION_ID="47fc9ee4" ;;
  "Done")        OPTION_ID="98236657" ;;
  *) echo "알 수 없는 상태: $STATUS (Todo | In Progress | Done)" >&2; exit 1 ;;
esac

# 프로젝트 항목 ID 조회 (이슈와 PR 번호 공간은 공유되므로 번호만으로 유일)
ITEM_ID=$(gh project item-list "$PROJECT_NUMBER" --owner "$OWNER" --format json --limit 500 \
  --jq ".items[] | select(.content.number == ${NUMBER}) | .id" | head -n1)

if [ -z "$ITEM_ID" ]; then
  # 이슈인지 PR인지 판별 후 프로젝트에 추가
  if gh pr view "$NUMBER" --repo "$REPO" --json url >/dev/null 2>&1; then
    URL=$(gh pr view "$NUMBER" --repo "$REPO" --json url --jq .url)
  else
    URL=$(gh issue view "$NUMBER" --repo "$REPO" --json url --jq .url)
  fi
  ITEM_ID=$(gh project item-add "$PROJECT_NUMBER" --owner "$OWNER" --url "$URL" --format json --jq .id)
fi

gh project item-edit --project-id "$PROJECT_ID" --id "$ITEM_ID" \
  --field-id "$STATUS_FIELD_ID" --single-select-option-id "$OPTION_ID" >/dev/null

echo "#${NUMBER} → ${STATUS} (item: ${ITEM_ID})"
