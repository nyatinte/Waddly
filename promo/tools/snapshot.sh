#!/usr/bin/env bash
# Snapshot one language of the promo.
#
#   ./tools/snapshot.sh ja --at 1.85,4.60,18.90 -o snapshots/ja
#   ./tools/snapshot.sh en --frames 5
#
# The project npm script supplies the pinned HyperFrames version. Snapshot has
# no --variables flag, so the language is flipped in index.html during capture.
set -euo pipefail

LANG_CODE="${1:-ja}"
shift || true

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$ROOT/tools/with-lang.sh" "$LANG_CODE" -- npm run snapshot -- "$ROOT" "$@"
