#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

SWIFTC=$(xcrun --find swiftc)
TESTING_PLUGIN="$(dirname "$SWIFTC")/../lib/swift/host/plugins/testing"

if [ -f "$TESTING_PLUGIN/libTestingMacros.dylib" ]; then
  set -- -Xswiftc -plugin-path -Xswiftc "$TESTING_PLUGIN" "$@"
fi

STATUS_FILE=$(mktemp)
OUTPUT_FILE=$(mktemp)
trap 'rm -f "$STATUS_FILE" "$OUTPUT_FILE"' EXIT

{ set +e; swift test "$@"; printf '%s\n' "$?" > "$STATUS_FILE"; } | tee "$OUTPUT_FILE"

STATUS=$(cat "$STATUS_FILE")
STARTED=$(grep -c 'Test run started' "$OUTPUT_FILE" || true)
COMPLETED=$(grep -Ec 'Test run with [0-9]+ tests?([[:space:]]|$)' "$OUTPUT_FILE" || true)

if [ "$STATUS" -eq 0 ] && [ "$STARTED" -gt "$COMPLETED" ]; then
  printf 'error: %s Swift Testing run(s) started but only %s reported completion; the test process exited early.\n' "$STARTED" "$COMPLETED" >&2
  exit 1
fi

exit "$STATUS"
