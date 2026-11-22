# tool/의 APK 검사 스크립트가 source해서 쓰는 Android SDK 도구 찾기 함수 (#36, #39).
# 직접 실행하지 않는다.

# aapt2 경로를 출력한다. $AAPT2가 있으면 그 값을 쓰고, 없으면
# $ANDROID_HOME(또는 $ANDROID_SDK_ROOT)/build-tools의 최신 정식 버전을 고른다.
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
  local v exe
  # rc·preview 같은 미리보기 버전은 빼고 정식 버전(숫자.숫자.숫자)만 고른다.
  for v in $(ls "$sdk/build-tools" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V -r); do
    for exe in aapt2 aapt2.exe; do
      if [ -x "$sdk/build-tools/$v/$exe" ]; then
        echo "$sdk/build-tools/$v/$exe"
        return
      fi
    done
  done
  echo "$sdk/build-tools에 aapt2가 있는 정식 버전이 없습니다" >&2
  return 1
}
