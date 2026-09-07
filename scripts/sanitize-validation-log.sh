#!/bin/bash
# docs/validation/artifacts/ 에 커밋할 xcodebuild 로그에서 머신·계정 식별자를 제거한다.
#
#   scripts/sanitize-validation-log.sh <로그파일> [로그파일...]
#
# 제거 대상과 근거:
#   - /Users/<계정>/...        홈 경로에 계정명과 로컬 워크트리 배치가 드러난다.
#   - export USER 등 소유자    빌드 환경이 계정명을 그대로 기록한다.
#   - export PATH              설치된 도구 목록 전체가 드러난다. 진단 가치는 없다.
#   - destination id           Mac 하드웨어 provisioning UDID다.
#
# 번들 식별자(com.<계정>.AllYouNeedQuickLook)는 제품 설정이므로 건드리지 않는다.
# 치환은 멱등이다. 커밋 전에 실행하고, 실행 후 grep 으로 잔여 식별자를 확인한다.
set -euo pipefail

USER_NAME="${SANITIZE_USER:-${USER:-}}"
if [ -z "$USER_NAME" ]; then
  echo "계정명을 확인할 수 없다. SANITIZE_USER 를 지정한다." >&2
  exit 1
fi
if [ "$#" -eq 0 ]; then
  echo "사용법: $0 <로그파일> [로그파일...]" >&2
  exit 1
fi

export SANITIZE_TARGET_USER="$USER_NAME"

for log in "$@"; do
  [ -f "$log" ] || { echo "파일 없음: $log" >&2; exit 1; }
  perl -pi -e '
    BEGIN { $u = quotemeta($ENV{SANITIZE_TARGET_USER}); }
    s{/Users/$u\b}{/Users/<user>}g;
    s{^(\s*export (?:USER|ALTERNATE_OWNER|INSTALL_OWNER|VERSION_INFO_BUILDER)\\=)$u$}{$1<user>}g;
    s{^(\s*export PATH\\=).*$}{$1<redacted>};
    s{\bid:[0-9A-F]{8}-[0-9A-F]{16}\b}{id:<device-id>}g;
  ' "$log"
  echo "정리함: $log"
done
