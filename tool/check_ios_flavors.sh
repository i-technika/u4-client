#!/usr/bin/env bash
# iOS scheme·build configuration마다 Xcode가 실제로 적용하는 bundle ID와 앱 이름을 확인한다 (#38).
# test/app_display_name_test.dart는 파일 텍스트를 검사하고, 이 스크립트는 xcodebuild가 계산한 최종 값을 본다
# (다른 xcconfig를 거친 값, 기기·시뮬레이터 SDK별 조건부 값 포함).
# 기대값은 ios/Flutter/AppInfo-<flavor>.xcconfig다. 이 값과 설정 JSON·Android ID의 일치는 flutter test가 확인한다.
# CocoaPods를 쓰지 않으므로(#52) 어느 configuration에도 PODS_* 설정이 없어야 한다.
# Milestone Full CI가 쓴다. 실행: macOS에서 flutter pub get 후 bash tool/check_ios_flavors.sh
set -uo pipefail
cd "$(dirname "$0")/.."

status=0
fail() {
  echo "FAIL $*" >&2
  status=1
}

# xcconfig의 KEY = value를 읽는다 (// 뒤는 주석).
xcconfig_value() {
  sed -n "s|//.*||; s|^[[:space:]]*$2[[:space:]]*=[[:space:]]*||p" "$1" | sed 's/[[:space:]]*$//'
}

# xcodebuild -showBuildSettings 결과에서 KEY 값을 읽는다.
setting() {
  sed -n "s/^ *$1 = //p" <<<"$2" | head -n1
}

# xcodebuild는 없는 configuration을 받아도 경고만 내고 기본 configuration 값을 보여 준다.
# 그래서 CONFIGURATION 값도 비교하고, 실패하면 출력 끝부분을 남긴다.
show_settings() {
  local out
  if ! out=$(xcodebuild -showBuildSettings -project ios/Runner.xcodeproj "$@" 2>&1); then
    echo "$out" | tail -n 20 >&2
    return 1
  fi
  echo "$out"
}

for flavor in dev stg prod; do
  appinfo="ios/Flutter/AppInfo-$flavor.xcconfig"
  want_id=$(xcconfig_value "$appinfo" PRODUCT_BUNDLE_IDENTIFIER)
  want_name=$(xcconfig_value "$appinfo" APP_DISPLAY_NAME)
  if [[ -z "$want_id" || -z "$want_name" ]]; then
    fail "$appinfo: PRODUCT_BUNDLE_IDENTIFIER 또는 APP_DISPLAY_NAME이 없습니다"
    continue
  fi

  for mode in Debug Release Profile; do
    config="$mode-$flavor"
    for sdk in iphoneos iphonesimulator; do
      if ! settings=$(show_settings -target Runner -configuration "$config" -sdk "$sdk"); then
        fail "$config ($sdk): xcodebuild 실패"
        continue
      fi
      got_config=$(setting CONFIGURATION "$settings")
      got_id=$(setting PRODUCT_BUNDLE_IDENTIFIER "$settings")
      got_name=$(setting APP_DISPLAY_NAME "$settings")
      if [[ "$got_config" == "$config" && "$got_id" == "$want_id" && "$got_name" == "$want_name" ]]; then
        echo "ok   $config ($sdk): $got_id / $got_name"
      else
        fail "$config ($sdk): '$got_config' '$got_id' / '$got_name' (기대: '$config' '$want_id' / '$want_name')"
      fi
      # Pods xcconfig가 어떤 경로로든 다시 포함되면 PODS_ROOT 등이 생긴다.
      pods=$(grep -E '^ *PODS_[A-Z_]* = ' <<<"$settings" | sed 's/^ *//' | head -n3)
      if [[ -n "$pods" ]]; then
        fail "$config ($sdk): CocoaPods 설정이 남아 있습니다: $(tr '\n' ';' <<<"$pods")"
      fi
    done
  done

  # scheme이 그 flavor의 configuration을 쓰는지도 확인한다 (flutter run은 scheme의 Debug configuration을 쓴다).
  if ! settings=$(show_settings -scheme "$flavor" -sdk iphoneos); then
    fail "scheme $flavor: xcodebuild 실패"
    continue
  fi
  got_config=$(setting CONFIGURATION "$settings")
  if [[ "$got_config" == "Debug-$flavor" ]]; then
    echo "ok   scheme $flavor: $got_config"
  else
    fail "scheme $flavor: '$got_config' (기대: Debug-$flavor)"
  fi
done
exit $status
