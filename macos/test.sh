#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

SWIFTC=$(xcrun --find swiftc)
TESTING_PLUGIN="$(dirname "$SWIFTC")/../lib/swift/host/plugins/testing"

if [ -f "$TESTING_PLUGIN/libTestingMacros.dylib" ]; then
  exec swift test -Xswiftc -plugin-path -Xswiftc "$TESTING_PLUGIN" "$@"
fi

exec swift test "$@"
