#!/usr/bin/env bash
# Pin nix/package.nix to a published Apple Silicon DMG.
# Usage: nix/update.sh [version]
set -euo pipefail

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"

version="${1:-}"
if [[ "$version" == v* ]]; then
  version="${version#v}"
fi

if [[ -z "$version" ]]; then
  tag=$(gh release view --repo nyatinte/Waddly --json tagName --jq .tagName)
  version="${tag#v}"
fi

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf 'Version must look like 1.2.3, got %s\n' "$version" >&2
  exit 1
fi

package="nix/package.nix"
current=$(
  python3 - "$package" <<'PY'
import pathlib, re, sys
text = pathlib.Path(sys.argv[1]).read_text()
match = re.search(r'^  version = "([^"]+)";', text, re.M)
print(match.group(1) if match else "")
PY
)

if [[ -n "$current" && "$current" != "$version" ]]; then
  older=$(printf '%s\n%s\n' "$version" "$current" | sort -V | head -n 1)
  if [[ "$older" == "$version" ]]; then
    printf 'nix/package.nix is already at %s, which is newer than %s\n' "$current" "$version"
    exit 0
  fi
fi

url="https://github.com/nyatinte/Waddly/releases/download/v${version}/Waddly-${version}-macos-arm64.dmg"
printf 'Prefetching %s\n' "$url"

hash_json=$(nix store prefetch-file --hash-type sha256 --json "$url")
sri=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["hash"])' <<<"$hash_json")
published=$(curl -fsSL "${url}.sha256" | awk 'NF { print $1; exit }')
got=$(python3 -c 'import base64,sys; print(base64.b64decode(sys.argv[1].split("-", 1)[1]).hex())' "$sri")

if [[ "$got" != "$published" ]]; then
  printf 'Prefetched hash %s does not match the published checksum %s\n' "$got" "$published" >&2
  exit 1
fi

python3 - "$package" "$version" "$sri" <<'PY'
import pathlib, re, sys

path, version, sri = sys.argv[1:]
file = pathlib.Path(path)
text = file.read_text()
updated, version_count = re.subn(
    r'^  version = "[^"]+";',
    f'  version = "{version}";',
    text,
    count=1,
    flags=re.M,
)
updated, hash_count = re.subn(
    r'^    hash = "sha256-[^"]+";',
    f'    hash = "{sri}";',
    updated,
    count=1,
    flags=re.M,
)
if version_count != 1 or hash_count != 1:
    raise SystemExit(
        f"expected to replace version and hash once, got version={version_count} hash={hash_count}"
    )
file.write_text(updated)
PY

printf 'Pinned Nix package to %s (%s)\n' "$version" "$sri"
