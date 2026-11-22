#!/usr/bin/env bash
# iOS scheme·build configuration마다 Xcode가 실제로 적용하는 bundle ID와 앱 이름을 확인한다 (#38).
# test/app_display_name_test.dart는 파일 텍스트를 검사하고, 이 스크립트는 xcodebuild가 계산한 최종 값을 본다.
# 기대값은 ios/Flutter/AppInfo-<flavor>.xcconfig다(이 값과 설정 JSON·Android ID의 일치는 flutter test가 확인).
# 그래서 project.pbxproj나 scheme이 값을 덮어쓰거나 다른 flavor의 xcconfig를 쓰면 실패한다.
# Milestone Full CI가 쓴다. 실행: macOS에서 flutter pub get 후 bash tool/check_ios_flavors.sh
set -euo pipefail
cd "$(dirname "$0")/.."

# xcconfig의 KEY = value를 읽는다 (// 뒤는 주석).
xcconfig_value() {
  sed -n "s|//.*||; s|^[[:space:]]*$2[[:space:]]*=[[:space:]]*||p" "$1" | sed 's/[[:space:]]*$//'
}

status=0
for flavor in dev stg prod; do
  appinfo="ios/Flutter/AppInfo-$flavor.xcconfig"
  want_id=$(xcconfig_value "$appinfo" PRODUCT_BUNDLE_IDENTIFIER)
  want_name=$(xcconfig_value "$appinfo" APP_DISPLAY_NAME)
  for mode in Debug Release Profile; do
    config="$mode-$flavor"
    settings=$(xcodebuild -showBuildSettings -project ios/Runner.xcodeproj \
      -target Runner -configuration "$config" -sdk iphoneos 2>/dev/null)
    got_id=$(sed -n 's/^ *PRODUCT_BUNDLE_IDENTIFIER = //p' <<<"$settings")
    got_name=$(sed -n 's/^ *APP_DISPLAY_NAME = //p' <<<"$settings")
    if [[ "$got_id" == "$want_id" && "$got_name" == "$want_name" ]]; then
      echo "ok   $config: $got_id / $got_name"
    else
      echo "FAIL $config: '$got_id' / '$got_name' (기대: '$want_id' / '$want_name')" >&2
      status=1
    fi
  done

  # scheme이 그 flavor의 configuration을 쓰는지도 xcodebuild로 확인한다.
  scheme_config=$(xcodebuild -showBuildSettings -project ios/Runner.xcodeproj \
    -scheme "$flavor" -sdk iphoneos 2>/dev/null | sed -n 's/^ *CONFIGURATION = //p' | head -n1)
  if [[ "$scheme_config" == "Debug-$flavor" ]]; then
    echo "ok   scheme $flavor: $scheme_config"
  else
    echo "FAIL scheme $flavor: '$scheme_config' (기대: Debug-$flavor)" >&2
    status=1
  fi
done
exit $status
