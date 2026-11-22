#!/usr/bin/env bash
# 빌드한 APK의 최종 권한(병합된 매니페스트)에 금지 권한이 없는지 검사한다 (#36).
# 금지 목록은 tool/android_forbidden_permissions.txt. 소스 매니페스트 검사(flutter test)로는
# 플러그인을 추가·업데이트해서 새로 들어온 권한을 잡을 수 없어서 APK를 직접 본다.
# Sub-issue Linux CI(dev debug)와 Milestone Full CI(전 flavor release)가 같이 쓴다.
#
# 실행: bash tool/check_android_permissions.sh <apk>... (bash 3.2 이상)
# aapt2는 $AAPT2, 없으면 $ANDROID_HOME(또는 $ANDROID_SDK_ROOT)/build-tools의 최신 버전을 쓴다.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ "$#" -eq 0 ]; then
  echo "사용법: bash tool/check_android_permissions.sh <apk>..." >&2
  exit 2
fi

# 주석·빈 줄을 뺀 금지 권한 이름 (android.permission. 접두사를 붙인다)
FORBIDDEN=$(sed -e 's/#.*//' -e 's/[[:space:]]//g' tool/android_forbidden_permissions.txt |
  grep -v '^$' | sed 's/^/android.permission./')
if [ -z "$FORBIDDEN" ]; then
  echo "금지 권한 목록이 비어 있습니다" >&2
  exit 1
fi
# 덤프를 제대로 읽었는지 확인하는 용도. main 매니페스트가 선언하므로 모든 APK에 있어야 한다.
REQUIRED="android.permission.INTERNET
android.permission.POST_NOTIFICATIONS"

# aapt2 dump permissions 출력에서 앱이 요청하는 권한 이름만 뽑는다.
# uses-permission과 uses-permission-sdk-23 둘 다 본다. permission:(앱이 정의하는 권한)은 뺀다.
requested_permissions() {
  tr -d '\r' | sed -n -E "s/^uses-permission(-sdk-23)?: name='([^']+)'.*/\2/p" | sort -u
}

# 표준 입력의 aapt2 출력에서 금지 권한을 찾아 출력한다 (정확히 같은 이름만).
forbidden_in() {
  requested_permissions | grep -Fx -f <(printf '%s\n' "$FORBIDDEN") || true
}

find_aapt2() {
  if [ -n "${AAPT2:-}" ]; then
    echo "$AAPT2"
    return
  fi
  local sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
  if [ -z "$sdk" ] || [ ! -d "$sdk/build-tools" ]; then
    echo "Android SDK를 찾을 수 없습니다. ANDROID_HOME 또는 AAPT2를 지정하세요" >&2
    return 1
  fi
  local v
  for v in $(ls "$sdk/build-tools" | sort -V -r); do
    for exe in aapt2 aapt2.exe; do
      if [ -x "$sdk/build-tools/$v/$exe" ]; then
        echo "$sdk/build-tools/$v/$exe"
        return
      fi
    done
  done
  echo "$sdk/build-tools에 aapt2가 없습니다" >&2
  return 1
}

AAPT2_BIN=$(find_aapt2)
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
  PERMS=$(printf '%s\n' "$DUMP" | requested_permissions)
  MISSING=$(printf '%s\n' "$REQUIRED" | grep -Fxv -f <(printf '%s\n' "$PERMS") || true)
  if [ -n "$MISSING" ]; then
    echo "$apk: 있어야 할 권한이 덤프에 없습니다 (출력 형식이 바뀌었을 수 있음):" >&2
    printf '  %s\n' $MISSING >&2
    printf '%s\n' "$DUMP" >&2
    FAILED=1
    continue
  fi
  FOUND=$(printf '%s\n' "$DUMP" | forbidden_in)
  if [ -n "$FOUND" ]; then
    echo "$apk: 금지 권한이 들어 있습니다 (tool/android_forbidden_permissions.txt):" >&2
    printf '  %s\n' $FOUND >&2
    echo "  새 플러그인이 추가했다면 main 매니페스트에 tools:node=\"remove\"로 제거하세요 (docs/phase-1-setup.md 3장)" >&2
    FAILED=1
    continue
  fi
  echo "ok -- $apk: 금지 권한 없음 ($(printf '%s\n' "$PERMS" | grep -c .)개 권한 확인)"
done

# 검사 로직이 실제로 금지 권한을 잡는지 확인한다. 금지 목록의 모든 권한을 여러 형식
# (uses-permission-sdk-23, maxSdkVersion)으로 담은 fixture에서 정확히 그 목록만 나와야 한다.
# 비슷한 이름(READ_MEDIA_VISUAL_USER_SELECTED)은 잡지 않아야 한다.
FIXTURE=tool/fixtures/aapt2_permissions_forbidden.txt
GOT=$(forbidden_in <"$FIXTURE")
WANT=$(printf '%s\n' "$FORBIDDEN" | sort -u)
if [ "$GOT" != "$WANT" ]; then
  echo "$FIXTURE에서 금지 권한을 정확히 찾지 못했습니다:" >&2
  echo "  기대: $(echo $WANT)" >&2
  echo "  결과: $(echo $GOT)" >&2
  FAILED=1
else
  echo "ok -- 금지 권한 검사 동작 확인 ($FIXTURE)"
fi

exit "$FAILED"
