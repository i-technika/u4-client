#!/usr/bin/env bash
# config/app_config.<flavor>.json을 config/app_config.schema.json으로 검증한다 (#4).
# Sub-issue Linux CI와 Milestone Full CI가 같이 쓴다. 의존성: tool/requirements-ci.txt
# 실행: bash tool/validate_config.sh (bash 3.2 이상)
#
# 앱 로더가 다시 검사하는 항목과 여기서만 막는 항목은 docs/phase-1-setup.md 5장에 적었다.
set -euo pipefail
cd "$(dirname "$0")/.."

SCHEMA=config/app_config.schema.json
# glob은 스키마 파일까지 잡으므로 뺀다. Flavor와 파일 목록이 같은지는 flutter test가 확인한다.
FILES=()
shopt -s nullglob
for f in config/app_config.*.json; do
  [[ "$f" == *.schema.json ]] || FILES+=("$f")
done
shopt -u nullglob
if [ "${#FILES[@]}" -eq 0 ]; then
  echo "검증할 설정 파일이 없습니다" >&2
  exit 1
fi

check-jsonschema --check-metaschema "$SCHEMA"
check-jsonschema --schemafile "$SCHEMA" "${FILES[@]}"

# 형식 검사가 실제로 동작하는지 확인한다. uri 검사 패키지가 빠지면 잘못된 URI도
# 조용히 통과한다. 다른 이유로 실패한 것을 동작으로 오인하지 않도록 실패 이유까지 본다.
FIXTURE=tool/fixtures/invalid_uri_config.json
if OUT=$(check-jsonschema --schemafile "$SCHEMA" "$FIXTURE" 2>&1); then
  echo "$FIXTURE가 통과했습니다: format: uri 검사가 동작하지 않습니다" >&2
  exit 1
fi
ERRORS=$(printf '%s\n' "$OUT" | grep -c "::\$\." || true)
if [ "$ERRORS" -ne 1 ] ||
  ! printf '%s\n' "$OUT" | grep -q "\$\.extras\.forceUpdate\.checkUrl: 'not a uri at all' is not a 'uri'"; then
  echo "$FIXTURE가 uri 형식 오류 하나로만 실패해야 합니다:" >&2
  printf '%s\n' "$OUT" >&2
  exit 1
fi
echo "ok -- uri 형식 검사 동작 확인"
