#!/usr/bin/env bash
# 빌드한 APK의 런처 이름이 설정 JSON의 app.name과 같은지 검사한다 (#39).
# build.gradle.kts의 appNameOf(flavor)가 config/app_config.<flavor>.json의 app.name을 읽어
# android:label에 넣는다. test/app_display_name_test.dart는 이 연결을 정적으로만 보므로,
# appNameOf가 실제로 JSON 값을 돌려주는지는 빌드 결과(aapt2 dump badging)로 확인한다.
# Sub-issue Linux CI(dev·prod debug)와 Milestone Full CI(전 flavor release APK)가 같이 쓴다.
#
# 실행: bash tool/check_android_app_label.sh <apk>... (bash 3.2 이상, 경로는 현재 위치 기준)
# flavor는 APK 파일 이름(app-<flavor>-<buildType>.apk)에서 읽는다.
# aapt2는 $AAPT2, 없으면 $ANDROID_HOME(또는 $ANDROID_SDK_ROOT)/build-tools의 최신 정식 버전을 쓴다.
# JSON은 $PYTHON, 없으면 python3(없으면 python)으로 읽는다.
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
  if [ -n "${PYTHON:-}" ]; then
    if "$PYTHON" -c '' >/dev/null 2>&1; then
      echo "$PYTHON"
      return
    fi
    echo "PYTHON=$PYTHON을 실행할 수 없습니다" >&2
    return 1
  fi
  local py
  for py in python3 python; do
    # Windows의 python3는 스토어 안내용 가짜 실행 파일일 수 있어 실제로 실행해 본다.
    if "$py" -c '' >/dev/null 2>&1; then
      echo "$py"
      return
    fi
  done
  echo "python3를 찾을 수 없습니다. PYTHON을 지정하세요" >&2
  return 1
}
PYTHON_BIN=$(find_python)

# 설정 JSON의 app.name을 aapt2 badging과 같은 표기로 출력한다.
# aapt2는 라벨을 출력할 때 \ → \\, " → \", 줄바꿈 → \n으로 바꾸고 나머지(탭 등)는 그대로 둔다
# (ResTable::normalizeForOutput). 끝에 줄바꿈을 붙이지 않는다. 문자열이 아니거나 비어 있으면 실패한다.
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

# APK 파일 이름(app-<flavor>-<buildType>.apk)에서 flavor를 출력한다. 형식이 다르면 빈 값이다.
flavor_of() {
  basename "$1" | sed -n -E 's/^app-([a-z]+)-[a-zA-Z]+\.apk$/\1/p'
}

# badging 덤프에서 런처 이름 줄의 값을 "<줄 이름>\t<값>" 형식으로 출력한다.
# - application-label:'…'         앱 기본 라벨
# - application-label-<로캘>:'…'  로캘별 라벨. 앱이나 라이브러리 리소스에 있는 로캘마다 나온다
#                                 (라벨이 리터럴이면 모두 기본 라벨과 같다)
# - launchable-activity: … label='…' icon='…'           런처 activity 라벨. 비어 있으면 앱 라벨을 쓴다
# - leanback-launchable-activity: … label='…' icon='…'  TV 런처 activity 라벨 (지금은 없다)
# application: label='…' 줄은 application-label과 같은 값이라 보지 않는다.
# 값 안의 '는 aapt2가 이스케이프하지 않으므로, 줄 끝(또는 icon=) 직전의 '까지를 값으로 본다.
# Windows용 aapt2의 CRLF는 줄 끝에서만 지운다 (값 안의 CR은 그대로 둔다).
label_values() {
  awk '{ sub(/\r$/, ""); print }' | sed -n -E \
    -e "s/^(application-label(-[^:]+)?):'(.*)'$/\1	\3/p" \
    -e "s/^((leanback-)?launchable-activity):.*[[:space:]]label='(.*)'[[:space:]]+icon='[^']*'$/\1	\3/p"
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
      printf '%s\n' "$dump" | grep -E '^(application-label:|application:|launchable-activity:)' >&2 || true
      return 1
    fi
  done
  # 값은 첫 탭 뒤 전부다 (이름에 탭이 있어도 자르지 않는다). awk -v는 \를 이스케이프로 해석하므로
  # 기대값은 환경 변수로 넘기고, 숫자처럼 보이는 이름(1000·1e3)도 문자열로 비교한다.
  # activity 라벨이 비어 있으면 앱 라벨을 물려받으므로 통과로 본다.
  if ! bad=$(printf '%s\n' "$values" | WANT="$want" awk '
    {
      i = index($0, "\t"); key = substr($0, 1, i - 1); v = substr($0, i + 1)
      if (key ~ /launchable-activity$/ && v == "") next
      if ((v "") != (ENVIRON["WANT"] "")) print
    }'); then
    echo "$label: 라벨 비교 중 awk가 실패했습니다" >&2
    return 1
  fi
  if [ -n "$bad" ]; then
    echo "$label: 런처 이름이 설정 JSON의 app.name과 다릅니다 (값은 aapt2 출력 표기: \\·\"·줄바꿈 이스케이프)" >&2
    echo "  기대: '$want'" >&2
    # 로캘 라벨은 수십 줄이므로 앞의 5줄만 보이고 나머지는 개수만 알린다.
    printf '%s\n' "$bad" | awk '
      NR <= 5 { i = index($0, "\t"); printf "  실제: %s = '"'"'%s'"'"'\n", substr($0, 1, i - 1), substr($0, i + 1) }
      END { if (NR > 5) printf "  … 외 %d줄\n", NR - 5 }' >&2
    echo "  android/app/build.gradle.kts의 appNameOf와 매니페스트의 android:label을 확인하세요 (docs/phase-1-setup.md 2장)" >&2
    return 1
  fi
  echo "ok -- $label: 런처 이름 '$want' ($(printf '%s\n' "$values" | grep -c .)개 라벨 줄 확인)"
}

# 판정 로직이 실제로 동작하는지 먼저 확인한다. 정상 덤프는 통과하고, 라벨이 하나라도 다르거나
# 라벨 줄이 빠지면 이유를 밝히고 실패해야 한다. 이름에 '·"·탭·icon='이 있어도 값을 끝까지 읽어야 한다.
# 덤프 형식은 aapt2 2.20(build-tools 37.0.0) 출력을 따른다.
self_test_fail() {
  echo "자기검사 실패: $1" >&2
  [ -z "${2:-}" ] || printf '%s\n' "$2" >&2
  exit 1
}
fixture_dump() {
  # $1: 기본 라벨, $2: 로캘 라벨, $3: activity 라벨, $4: 덧붙일 줄
  printf '%s\n' \
    "package: name='com.itechnika.u4.dev' versionCode='1' versionName='1.0.0'" \
    "application-label:'$1'" \
    "application-label-en-GB:'$2'" \
    "application-label-ko:'$2'" \
    "application: label='$1' icon='res/mipmap-mdpi-v4/ic_launcher.png'" \
    "launchable-activity: name='com.itechnika.u4.MainActivity'  label='$3' icon=''" \
    "feature-group: label=''" \
    ${4:+"$4"}
}
# $1: 설명, $2: 덤프, $3: 기대 라벨
expect_pass() {
  local out
  out=$(check_dump fixture "$2" "$3" 2>&1) || self_test_fail "$1 덤프가 실패했습니다" "$out"
}
# $1: 설명, $2: 덤프, $3: 기대 라벨, $4: 실패 이유
expect_fail() {
  local out
  if out=$(check_dump fixture "$2" "$3" 2>&1) || ! printf '%s\n' "$out" | grep -qF "$4"; then
    self_test_fail "$1 덤프가 '$4'로 실패하지 않았습니다" "$out"
  fi
}
N="U4 it's \\\"DEV\\\""
TAB_N="U4	DEV"
ICON_N="U4' icon='x"
CR_N=$(printf 'U4\rDEV')
MISMATCH="런처 이름이 설정 JSON의 app.name과 다릅니다"
LEANBACK="leanback-launchable-activity: name='com.itechnika.u4.TvActivity'  label='U4' icon=''"
expect_pass "activity 라벨이 빈" "$(fixture_dump "$N" "$N" "")" "$N"
expect_pass "activity 라벨이 같은" "$(fixture_dump "$N" "$N" "$N")" "$N"
expect_pass "CRLF" "$(fixture_dump "$N" "$N" "" | awk '{ printf "%s\r\n", $0 }')" "$N"
expect_pass "이름에 탭이 있는" "$(fixture_dump "$TAB_N" "$TAB_N" "$TAB_N")" "$TAB_N"
expect_pass "이름에 icon='이 있는" "$(fixture_dump "$ICON_N" "$ICON_N" "$ICON_N")" "$ICON_N"
expect_pass "이름 안에 CR이 있는" "$(fixture_dump "$CR_N" "$CR_N" "")" "$CR_N"
expect_fail "기본 라벨이 다른" "$(fixture_dump "U4" "$N" "")" "$N" "$MISMATCH"
expect_fail "기본 라벨 끝이 잘린" "$(fixture_dump "U4 it's \\\"DEV" "$N" "")" "$N" "$MISMATCH"
expect_fail "로캘 라벨이 다른" "$(fixture_dump "$N" "U4" "")" "$N" "$MISMATCH"
expect_fail "activity 라벨이 다른" "$(fixture_dump "$N" "$N" "U4")" "$N" "$MISMATCH"
expect_fail "TV activity 라벨이 다른" "$(fixture_dump "$N" "$N" "" "$LEANBACK")" "$N" "$MISMATCH"
expect_fail "탭 뒤가 다른" "$(fixture_dump "U4	STG" "$TAB_N" "")" "$TAB_N" "$MISMATCH"
expect_fail "숫자 표기만 같은" "$(fixture_dump "1e3" "1e3" "")" "1000" "$MISMATCH"
expect_fail "뒤 공백만 다른" "$(fixture_dump "12" "12" "")" "12 " "$MISMATCH"
expect_fail "기본 라벨이 없는" "$(fixture_dump "$N" "$N" "" | grep -v '^application-label:')" "$N" \
  "application-label 라벨을 찾지 못했습니다"
expect_fail "activity 줄이 없는" "$(fixture_dump "$N" "$N" "" | grep -v '^launchable-activity:')" "$N" \
  "launchable-activity 라벨을 찾지 못했습니다"
expect_fail 빈 "" "$N" "application-label 라벨을 찾지 못했습니다"

# 기대값 변환: JSON 원문의 \·"·줄바꿈이 aapt2 표기로 바뀌고 '·한글·탭은 그대로여야 한다.
SELF_TMP=$(mktemp -d)
trap 'rm -rf "$SELF_TMP"' EXIT
printf '%s' '{"app": {"name": "U4 it'"'"'s \"개발\"\\x\n둘째\t셋"}}' >"$SELF_TMP/app_config.json"
GOT=$(expected_label "$SELF_TMP/app_config.json") || self_test_fail "expected_label이 실패했습니다"
WANT_ESCAPED="U4 it's \\\"개발\\\"\\\\x\\n둘째	셋"
[ "$GOT" = "$WANT_ESCAPED" ] ||
  self_test_fail "expected_label 표기가 다릅니다" "  기대: $WANT_ESCAPED
  실제: $GOT"
printf '%s' '{"app": {"name": ""}}' >"$SELF_TMP/empty.json"
if expected_label "$SELF_TMP/empty.json" 2>/dev/null; then
  self_test_fail "빈 app.name을 통과시켰습니다"
fi
# 파일 이름 → flavor
for case in "app-dev-debug.apk=dev" "x/app-prod-release.apk=prod" "app-release.apk=" \
  "app-dev-debug.apk.idsig=" "app-dev-debug-unsigned.apk="; do
  got=$(flavor_of "${case%%=*}")
  [ "$got" = "${case#*=}" ] || self_test_fail "flavor_of ${case%%=*}: 기대 '${case#*=}', 실제 '$got'"
done
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
  flavor=$(flavor_of "$apk")
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
