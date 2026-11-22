#!/usr/bin/env bash
# 빌드한 APK의 런처 이름이 설정 JSON의 app.name과 같은지 검사한다 (#39).
# build.gradle.kts의 appNameOf(flavor)가 config/app_config.<flavor>.json의 app.name을 읽어
# android:label에 넣는다. test/app_display_name_test.dart는 이 연결을 정적으로만 보므로,
# appNameOf가 실제로 JSON 값을 돌려주는지는 빌드 결과(aapt2 dump badging)로 확인한다.
# Sub-issue Linux CI(dev debug)와 Milestone Full CI(전 flavor release APK)가 같이 쓴다.
#
# 실행: bash tool/check_android_app_label.sh <apk>... (bash 3.2 이상, 경로는 현재 위치 기준)
# flavor는 APK 파일 이름(app-<flavor>-<buildType>.apk)에서 읽는다.
# aapt2는 $AAPT2, 없으면 $ANDROID_HOME(또는 $ANDROID_SDK_ROOT)/build-tools의 최신 정식 버전을 쓴다.
# JSON은 python3(없으면 python)으로 읽는다. $PYTHON으로 바꿀 수 있다.
set -euo pipefail
TOOL_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$TOOL_DIR/.." && pwd)"
# find_aapt2
. "$TOOL_DIR/android_sdk.sh"

if [ "$#" -eq 0 ]; then
  echo "사용법: bash tool/check_android_app_label.sh <apk>..." >&2
  exit 2
fi

find_python() {
  local py
  for py in "${PYTHON:-}" python3 python; do
    # Windows의 python3는 스토어 안내용 가짜 실행 파일일 수 있어 실제로 실행해 본다.
    if [ -n "$py" ] && "$py" -c '' >/dev/null 2>&1; then
      echo "$py"
      return
    fi
  done
  echo "python3를 찾을 수 없습니다. PYTHON을 지정하세요" >&2
  return 1
}
PYTHON_BIN=$(find_python)

# 설정 JSON의 app.name을 aapt2 badging과 같은 표기로 출력한다.
# aapt2는 라벨을 출력할 때 \ → \\, " → \", 줄바꿈 → \n으로 바꾼다 (ResTable::normalizeForOutput).
# 끝에 줄바꿈을 붙이지 않는다. 문자열이 아니거나 비어 있으면 실패한다.
expected_label() {
  "$PYTHON_BIN" -I -X utf8 - "$1" <<'EOF'
import json, sys
path = sys.argv[1]
try:
    with open(path, encoding="utf-8") as f:
        name = json.load(f)["app"]["name"]
except (OSError, ValueError, KeyError, TypeError) as e:
    sys.exit(f"{path}: app.name을 읽을 수 없습니다 ({type(e).__name__}: {e})")
if not isinstance(name, str) or not name:
    sys.exit(f"{path}: app.name이 비어 있거나 문자열이 아닙니다")
sys.stdout.write(name.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n"))
EOF
}

# badging 덤프에서 런처 이름 줄의 값을 "<줄 이름>\t<값>" 형식으로 출력한다.
# - application-label:'…'         앱 기본 라벨
# - application-label-<로캘>:'…'  로캘별 라벨. 앱이나 라이브러리 리소스에 있는 로캘마다 나온다
#                                 (라벨이 리터럴이면 모두 기본 라벨과 같다)
# - launchable-activity: … label='…' icon='…'  런처 activity의 라벨. 비어 있으면 앱 라벨을 쓴다
# 값 안의 '는 aapt2가 이스케이프하지 않으므로, 줄 끝(또는 icon=) 직전의 '까지를 값으로 본다.
label_values() {
  tr -d '\r' | sed -n -E \
    -e "s/^(application-label(-[^:]+)?):'(.*)'$/\1	\3/p" \
    -e "s/^(launchable-activity):.*[[:space:]]label='(.*)'[[:space:]]+icon='[^']*'$/\1	\2/p"
}

# 덤프 하나를 판정한다. 통과하면 0, 아니면 1을 돌려주고 이유를 표준 오류에 쓴다.
# $1: 표시 이름, $2: aapt2 dump badging 출력, $3: 기대 라벨(badging 표기)
check_dump() {
  local label="$1" dump="$2" want="$3"
  local values bad key
  values=$(printf '%s\n' "$dump" | label_values)
  # 기본 라벨과 런처 activity 줄은 반드시 있어야 한다. 없으면 출력 형식이 바뀐 것이다.
  for key in application-label launchable-activity; do
    if ! printf '%s\n' "$values" | grep -q "^$key	"; then
      echo "$label: badging에서 $key 라벨을 찾지 못했습니다 (aapt2 출력 형식이 바뀌었을 수 있음):" >&2
      printf '%s\n' "$dump" | tr -d '\r' | grep -E '^(application-label:|application:|launchable-activity:)' >&2 || true
      return 1
    fi
  done
  # awk -v는 \를 이스케이프로 해석하므로 기대값은 환경 변수로 넘긴다.
  # activity 라벨이 비어 있으면 앱 라벨을 물려받으므로 통과로 본다.
  bad=$(printf '%s\n' "$values" | WANT="$want" awk -F '\t' '
    $1 == "launchable-activity" && $2 == "" { next }
    $2 != ENVIRON["WANT"]' || true)
  if [ -n "$bad" ]; then
    echo "$label: 런처 이름이 설정 JSON의 app.name과 다릅니다" >&2
    echo "  기대: '$want'" >&2
    # 로캘 라벨은 수십 줄이므로 앞의 5줄만 보이고 나머지는 개수만 알린다.
    printf '%s\n' "$bad" | awk -F '\t' '
      NR <= 5 { printf "  실제: %s = '"'"'%s'"'"'\n", $1, $2 }
      END { if (NR > 5) printf "  … 외 %d줄\n", NR - 5 }' >&2
    echo "  android/app/build.gradle.kts의 appNameOf와 매니페스트의 android:label을 확인하세요 (docs/phase-1-setup.md 2장)" >&2
    return 1
  fi
  echo "ok -- $label: 런처 이름 '$want' ($(printf '%s\n' "$values" | grep -c .)개 라벨 줄 확인)"
}

# 판정 로직이 실제로 동작하는지 먼저 확인한다. 정상 덤프는 통과하고, 라벨이 하나라도 다르거나
# 라벨 줄이 빠지면 이유를 밝히고 실패해야 한다. 이름에 '·"·공백이 있어도 값을 끝까지 읽어야 한다.
# 덤프 형식은 aapt2 2.20(build-tools 37.0.0) 출력을 따른다.
FIXTURE_NAME="U4 it's \\\"DEV\\\""
fixture_dump() {
  # $1: 기본 라벨, $2: 로캘 라벨, $3: activity 라벨
  printf '%s\n' \
    "package: name='com.itechnika.u4.dev' versionCode='1' versionName='1.0.0'" \
    "application-label:'$1'" \
    "application-label-en-GB:'$2'" \
    "application-label-ko:'$2'" \
    "application: label='$1' icon='res/mipmap-mdpi-v4/ic_launcher.png'" \
    "launchable-activity: name='com.itechnika.u4.MainActivity'  label='$3' icon=''" \
    "feature-group: label=''"
}
N="$FIXTURE_NAME"
expect_pass() {
  local what="$1" dump="$2" out
  if ! out=$(check_dump fixture "$dump" "$N" 2>&1); then
    echo "$what 덤프가 실패했습니다:" >&2
    printf '%s\n' "$out" >&2
    exit 1
  fi
}
expect_fail() {
  local what="$1" dump="$2" reason="$3" out
  if out=$(check_dump fixture "$dump" "$N" 2>&1) || ! printf '%s\n' "$out" | grep -qF "$reason"; then
    echo "$what 덤프가 '$reason'로 실패하지 않았습니다:" >&2
    printf '%s\n' "$out" >&2
    exit 1
  fi
}
MISMATCH="런처 이름이 설정 JSON의 app.name과 다릅니다"
expect_pass "activity 라벨이 빈" "$(fixture_dump "$N" "$N" "")"
expect_pass "activity 라벨이 같은" "$(fixture_dump "$N" "$N" "$N")"
expect_fail "기본 라벨이 다른" "$(fixture_dump "U4" "$N" "")" "$MISMATCH"
expect_fail "기본 라벨 끝이 잘린" "$(fixture_dump "U4 it's \\\"DEV" "$N" "")" "$MISMATCH"
expect_fail "로캘 라벨이 다른" "$(fixture_dump "$N" "U4" "")" "$MISMATCH"
expect_fail "activity 라벨이 다른" "$(fixture_dump "$N" "$N" "U4")" "$MISMATCH"
expect_fail "기본 라벨이 없는" "$(fixture_dump "$N" "$N" "" | grep -v '^application-label:')" \
  "application-label 라벨을 찾지 못했습니다"
expect_fail "activity 줄이 없는" "$(fixture_dump "$N" "$N" "" | grep -v '^launchable-activity:')" \
  "launchable-activity 라벨을 찾지 못했습니다"
expect_fail 빈 "" "application-label 라벨을 찾지 못했습니다"
echo "ok -- 런처 이름 검사 동작 확인"

AAPT2_BIN=$(find_aapt2)
echo "aapt2: $AAPT2_BIN ($("$AAPT2_BIN" version 2>&1 | tr -d '\r' | head -n 1))"
FAILED=0
for apk in "$@"; do
  if [ ! -f "$apk" ]; then
    echo "$apk: 파일이 없습니다" >&2
    FAILED=1
    continue
  fi
  # app-<flavor>-<buildType>.apk → config/app_config.<flavor>.json
  base=$(basename "$apk" .apk)
  flavor=$(printf '%s\n' "$base" | sed -n -E 's/^app-([a-z]+)-[a-zA-Z]+$/\1/p')
  config="$ROOT_DIR/config/app_config.$flavor.json"
  if [ -z "$flavor" ] || [ ! -f "$config" ]; then
    echo "$apk: 파일 이름(app-<flavor>-<buildType>.apk)에서 flavor 설정 파일을 찾지 못했습니다 (${config#"$ROOT_DIR"/})" >&2
    FAILED=1
    continue
  fi
  if ! want=$(expected_label "$config"); then
    FAILED=1
    continue
  fi
  if ! DUMP=$("$AAPT2_BIN" dump badging "$apk"); then
    echo "$apk: aapt2 dump badging 실패" >&2
    FAILED=1
    continue
  fi
  check_dump "$apk ($flavor)" "$DUMP" "$want" || FAILED=1
done

exit "$FAILED"
