#!/usr/bin/env bash
# Download the OFL-licensed Japanese webfont used by the promo composition.
# Not committed to git (9.6 MB); everything else in the project is.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/assets/fonts/NotoSansJP.ttf"
URL="https://raw.githubusercontent.com/google/fonts/main/ofl/notosansjp/NotoSansJP%5Bwght%5D.ttf"

mkdir -p "$(dirname "$DEST")"
if [ -s "$DEST" ]; then
  echo "already present: $DEST"
  exit 0
fi

curl -fsSL --retry 3 -o "$DEST" "$URL"
echo "downloaded $(du -h "$DEST" | cut -f1) -> $DEST"
