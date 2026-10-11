#!/usr/bin/env bash
set -euo pipefail

release_tag=${1:?usage: release_notes_range.sh RELEASE_TAG TAG_PATTERN}
tag_pattern=${2:?usage: release_notes_range.sh RELEASE_TAG TAG_PATTERN}

eligible_tags=$(git tag --sort=-version:refname | grep -E "$tag_pattern" || true)
if ! grep -Fxq -- "$release_tag" <<<"$eligible_tags"; then
    printf 'Release tag %s is missing or does not match %s.\n' "$release_tag" "$tag_pattern" >&2
    exit 1
fi

previous_tag=$(
    printf '%s\n' "$eligible_tags" |
        awk -v release_tag="$release_tag" '
            $0 == release_tag { found = 1; next }
            found { print; exit }
        '
)

if [ -n "$previous_tag" ]; then
    printf '%s..%s\n' "$previous_tag" "$release_tag"
else
    printf '%s\n' "$release_tag"
fi
