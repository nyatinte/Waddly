#!/usr/bin/env bash
# Snapshot one language of the promo.
#
#   ./tools/snapshot.sh ja --at 1.85,4.60,18.90 -o snapshots/ja
#   ./tools/snapshot.sh en --frames 5
#
# `hyperframes snapshot` has no --variables flag, so the language is flipped in
# index.html for the duration of the capture and always restored.
set -euo pipefail

LANG_CODE="${1:-ja}"
shift || true

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$ROOT/tools/with-lang.sh" "$LANG_CODE" -- hyperframes snapshot "$ROOT" "$@"
