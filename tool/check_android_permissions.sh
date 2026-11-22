#!/usr/bin/env bash
# 빌드한 APK의 최종 권한(병합된 매니페스트)에 금지 권한이 없는지 검사한다 (#36).
# 금지 목록은 tool/android_forbidden_permissions.txt. 소스 매니페스트 검사(flutter test)로는
# 플러그인을 추가·업데이트해서 새로 들어온 권한을 잡을 수 없어서 APK를 직접 본다.
# Sub-issue Linux CI(dev debug)와 Milestone Full CI(전 flavor release APK)가 같이 쓴다.
# AAB는 aapt2가 읽지 못해 아직 검사하지 않는다 (docs/phase-1-setup.md 3장).
#
# 실행: bash tool/check_android_permissions.sh <apk>... (bash 3.2 이상, 경로는 현재 위치 기준)
# aapt2는 $AAPT2, 없으면 $ANDROID_HOME(또는 $ANDROID_SDK_ROOT)/build-tools의 최신 정식 버전을 쓴다.
set -euo pipefail
TOOL_DIR="$(cd "$(dirname "$0")" && pwd)"
# find_aapt2
. "$TOOL_DIR/android_sdk.sh"

if [ "$#" -eq 0 ]; then
  echo "사용법: bash tool/check_android_permissions.sh <apk>..." >&2
  exit 2
fi

# 주석·빈 줄을 뺀 금지 권한 이름 (android.permission. 접두사를 붙인다)
FORBIDDEN=$(sed -e 's/#.*//' -e 's/[[:space:]]//g' -e '/^$/d' -e 's/^/android.permission./' \
  "$TOOL_DIR/android_forbidden_permissions.txt")
if [ -z "$FORBIDDEN" ]; then
  echo "금지 권한 목록이 비어 있습니다: $TOOL_DIR/android_forbidden_permissions.txt" >&2
  exit 1
fi
# 덤프를 제대로 읽었는지 확인하는 용도. main 매니페스트가 선언하므로 모든 APK에 있어야 한다.
# main 매니페스트에서 이 선언을 바꾸면 여기도 고친다.
REQUIRED="android.permission.INTERNET
android.permission.POST_NOTIFICATIONS"

# aapt2 dump permissions 출력에서 앱이 요청하는 권한 줄만 남긴다.
# uses-permission과 uses-permission-sdk-23 둘 다 본다. permission:(앱이 정의하는 권한)과
# optional-permission:(required="false"일 때 추가로 나오는 줄)은 뺀다.
permission_lines() {
  tr -d '\r' | grep -E '^uses-permission(-sdk-23)?:' || true
}

# 권한 줄에서 name='…' 값만 뽑는다. 속성 순서와 상관없이 찾는다.
names_of() {
  sed -n -E "s/^.*[[:space:]]name='([^']+)'.*$/\1/p"
}

# 금지 권한이 들어 있는 덤프 줄을 출력한다. 줄 형식(태그·들여쓰기)과 상관없이
# 'android.permission.X'가 나오는 줄을 모두 찾아, 형식이 바뀌어도 놓치지 않는다.
# permission:(앱이 정의하는 권한) 줄만 뺀다. grep 오류(exit 2 이상)는 실패로 돌려준다.
forbidden_lines() {
  local dump="$1" f rc
  for f in $FORBIDDEN; do
    rc=0
    printf '%s\n' "$dump" | tr -d '\r' | grep -v '^permission:' | grep -F "'$f'" || rc=$?
    if [ "$rc" -gt 1 ]; then
      return "$rc"
    fi
  done
}

# 병합 리포트에서 "<태그>#<권한>" 항목 블록을 출력한다. 블록은 헤더 줄과 그 뒤의
# ADDED·MERGED·REJECTED·INJECTED·IMPLIED 줄(들여쓴 줄 포함)이고, 다음 헤더에서 끝난다.
report_block() {
  awk -v key="$2" '
    $0 == key { on = 1; print; next }
    on && /^[^[:space:]]/ && !/^(ADDED|MERGED|REJECTED|INJECTED|IMPLIED) / { on = 0 }
    on { print }
  ' "$1"
}

# 덤프 하나를 판정한다. 통과하면 0, 아니면 1을 돌려주고 이유를 표준 오류에 쓴다.
# $1: 표시 이름, $2: aapt2 dump permissions 출력, $3: 병합 리포트 경로(없으면 빈 값)
check_dump() {
  local label="$1" dump="$2" report="${3:-}"
  local lines names missing found
  lines=$(printf '%s\n' "$dump" | permission_lines)
  names=$(printf '%s\n' "$lines" | names_of | sort -u)
  # 줄마다 이름을 하나씩 뽑았는지 본다. 형식이 바뀌어 일부 줄을 놓치면 REQUIRED 확인이 무의미해진다.
  if [ "$(printf '%s\n' "$lines" | grep -c . || true)" -ne \
    "$(printf '%s\n' "$lines" | names_of | grep -c . || true)" ]; then
    echo "$label: name을 읽지 못한 권한 줄이 있습니다 (aapt2 출력 형식이 바뀌었을 수 있음):" >&2
    printf '%s\n' "$dump" >&2
    return 1
  fi
  missing=$(printf '%s\n' "$REQUIRED" | grep -Fxv -f <(printf '%s\n' "$names") || true)
  if [ -n "$missing" ]; then
    echo "$label: 있어야 할 권한이 덤프에 없습니다:" >&2
    printf '  %s\n' $missing >&2
    echo "  aapt2 출력 형식이 바뀌었거나, main 매니페스트에서 이 권한을 뺐다면 스크립트의 REQUIRED를 고치세요" >&2
    printf '%s\n' "$dump" >&2
    return 1
  fi
  if ! found=$(forbidden_lines "$dump"); then
    echo "$label: 금지 권한을 찾는 중 grep이 실패했습니다" >&2
    return 1
  fi
  if [ -n "$found" ]; then
    echo "$label: 금지 권한이 들어 있습니다 (tool/android_forbidden_permissions.txt):" >&2
    printf '%s\n' "$found" | sed 's/^/  /' >&2
    cat >&2 <<'EOF'
  어느 라이브러리가 넣었는지 병합 리포트(build/app/outputs/logs/manifest-merger-*-report.txt)에서 찾고,
  main 매니페스트에 같은 태그로 selector 없이 제거 선언을 둡니다 (docs/phase-1-setup.md 3장).
    uses-permission:        <uses-permission android:name="…" tools:node="remove" />
    uses-permission-sdk-23: <uses-permission-sdk-23 android:name="…" tools:node="remove" />
  tools:node="remove"는 같은 태그의 선언만 지운다.
EOF
    if [ -z "$report" ]; then
      return 1
    fi
    if [ ! -f "$report" ]; then
      echo "  병합 리포트 없음: $report" >&2
      return 1
    fi
    echo "  $report:" >&2
    local line tag name key
    while IFS= read -r line; do
      tag=$(printf '%s\n' "$line" | sed -E 's/^[[:space:]]*([^:[:space:]]+).*/\1/')
      name=$(printf '%s\n' "$line" | names_of)
      key="$tag#$name"
      if grep -Fqx "$key" "$report"; then
        report_block "$report" "$key" | sed 's/^/    /' >&2
      else
        echo "    $key 항목이 리포트에 없습니다" >&2
      fi
    done <<<"$found"
    return 1
  fi
  echo "ok -- $label: 금지 권한 없음 ($(printf '%s\n' "$names" | grep -c .)개 권한 확인)"
}

# 판정 로직이 실제로 동작하는지 먼저 확인한다. 금지 목록의 모든 권한을 여러 형식
# (uses-permission-sdk-23, maxSdkVersion, 속성 순서)으로 담은 fixture는 실패하고 정확히
# 그 목록만 나와야 한다. 비슷한 이름(READ_MEDIA_VISUAL_USER_SELECTED, 금지 이름을 포함하는
# 다른 권한)은 잡지 않아야 한다.
# 줄 형식이 바뀐 경우(들여쓰기, 모르는 태그)도 잡아야 한다. 정상 fixture는 통과해야 한다.
# 금지 목록을 바꾸면 fixture도 같이 고친다.
BAD_FIXTURE="$TOOL_DIR/fixtures/aapt2_permissions_forbidden.txt"
OK_FIXTURE="$TOOL_DIR/fixtures/aapt2_permissions_ok.txt"
if OUT=$(check_dump fixture "$(cat "$BAD_FIXTURE")" 2>&1); then
  echo "$BAD_FIXTURE가 통과했습니다: 금지 권한 검사가 동작하지 않습니다" >&2
  exit 1
fi
GOT=$(printf '%s\n' "$OUT" | names_of | sort -u)
WANT=$(printf '%s\n' "$FORBIDDEN" | sort -u)
if [ "$GOT" != "$WANT" ]; then
  echo "$BAD_FIXTURE에서 금지 권한을 정확히 찾지 못했습니다:" >&2
  printf '%s\n' "$OUT" >&2
  echo "  기대: $(echo $WANT)" >&2
  exit 1
fi
if ! OUT=$(check_dump fixture "$(cat "$OK_FIXTURE")" 2>&1); then
  echo "$OK_FIXTURE가 실패했습니다:" >&2
  printf '%s\n' "$OUT" >&2
  exit 1
fi
# 가드 분기: 빈 덤프와 name을 읽을 수 없는 줄은 이유를 밝히고 실패해야 한다.
expect_guard() {
  local what="$1" dump="$2" reason="$3"
  if OUT=$(check_dump fixture "$dump" 2>&1) || ! printf '%s\n' "$OUT" | grep -qF "$reason"; then
    echo "$what 덤프가 '$reason'로 실패하지 않았습니다:" >&2
    printf '%s\n' "$OUT" >&2
    exit 1
  fi
}
expect_guard 빈 "" "있어야 할 권한이 덤프에 없습니다"
expect_guard "name을 읽을 수 없는" "$(cat "$OK_FIXTURE")
uses-permission: name=\"android.permission.CAMERA\"" "name을 읽지 못한 권한 줄"
echo "ok -- 금지 권한 검사 동작 확인 (fixtures/aapt2_permissions_*.txt)"

AAPT2_BIN=$(find_aapt2)
echo "aapt2: $AAPT2_BIN ($("$AAPT2_BIN" version 2>&1 | tr -d '\r' | head -n 1))"
FAILED=0
for apk in "$@"; do
  if [ ! -f "$apk" ]; then
    echo "$apk: 파일이 없습니다" >&2
    FAILED=1
    continue
  fi
  if ! DUMP=$("$AAPT2_BIN" dump permissions "$apk"); then
    echo "$apk: aapt2 dump permissions 실패" >&2
    FAILED=1
    continue
  fi
  # app-<flavor>-<buildType>.apk → manifest-merger-<flavor>-<buildType>-report.txt
  base=$(basename "$apk" .apk)
  report="$(dirname "$apk")/../logs/manifest-merger-${base#app-}-report.txt"
  check_dump "$apk" "$DUMP" "$report" || FAILED=1
done

exit "$FAILED"
