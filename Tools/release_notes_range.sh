#!/usr/bin/env bash
set -euo pipefail

release_tag=${1:?usage: release_notes_range.sh RELEASE_TAG TAG_PATTERN}
tag_pattern=${2:?usage: release_notes_range.sh RELEASE_TAG TAG_PATTERN}
release_commit=$(git rev-parse --verify "${release_tag}^{commit}")
eligible_tags=$(git tag --sort=-version:refname | grep -E "$tag_pattern" || true)
if ! grep -Fxq -- "$release_tag" <<<"$eligible_tags"; then
    printf 'Release tag %s is missing or does not match %s.\n' "$release_tag" "$tag_pattern" >&2
    exit 1
fi

previous_tag=
previous_distance=
while IFS= read -r tag; do
    [ "$tag" != "$release_tag" ] || continue
    tag_commit=$(git rev-parse --verify "${tag}^{commit}")
    [ "$tag_commit" != "$release_commit" ] || continue
    git merge-base --is-ancestor "$tag_commit" "$release_commit" || continue
    distance=$(git rev-list --count "${tag_commit}..${release_commit}")
    if [ -z "$previous_distance" ] || [ "$distance" -lt "$previous_distance" ]; then
        previous_tag=$tag
        previous_distance=$distance
    fi
done <<<"$eligible_tags"

if [ -n "$previous_tag" ]; then
    previous_commit=$(git rev-parse --verify "${previous_tag}^{commit}")
    printf '%s..%s\n' "$previous_commit" "$release_commit"
else
    printf '%s\n' "$release_commit"
fi
