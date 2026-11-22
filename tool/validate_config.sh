#!/usr/bin/env bash
# config/app_config.<flavor>.json을 config/app_config.schema.json으로 검증한다 (#4).
# Sub-issue Linux CI와 Milestone Full CI가 같이 쓴다. 의존성: tool/requirements-ci.txt
#
# 앱 로더가 다시 검사하는 항목과 여기서만 막는 항목은 docs/phase-1-setup.md 5장에 적었다.
set -euo pipefail
cd "$(dirname "$0")/.."

SCHEMA=config/app_config.schema.json
# glob은 스키마 파일까지 잡으므로 뺀다. Flavor와 파일 목록이 같은지는 flutter test가 확인한다.
mapfile -t FILES < <(ls config/app_config.*.json | grep -v '\.schema\.json$')
if [ "${#FILES[@]}" -eq 0 ]; then
  echo "검증할 설정 파일이 없습니다" >&2
  exit 1
fi

check-jsonschema --check-metaschema "$SCHEMA"
check-jsonschema --schemafile "$SCHEMA" "${FILES[@]}"

# 형식 검사가 실제로 동작하는지 확인한다. rfc3987이 빠지면 잘못된 URI도 조용히 통과한다.
FIXTURE=tool/fixtures/invalid_uri_config.json
if check-jsonschema --schemafile "$SCHEMA" "$FIXTURE" >/dev/null 2>&1; then
  echo "$FIXTURE가 통과했습니다: format: uri 검사가 동작하지 않습니다" >&2
  exit 1
fi
echo "ok -- uri 형식 검사 동작 확인"
