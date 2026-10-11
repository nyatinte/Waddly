#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
script="$root/Tools/release_notes_range.sh"
repo=$(mktemp -d)
trap 'rm -rf "$repo"' EXIT

cd "$repo"
git init -q
git config user.name Test
git config user.email test@example.com

add_tagged_commit() {
    local message=$1 tag=$2
    printf '%s\n' "$message" >> history.txt
    git add history.txt
    git commit -q -m "$message"
    git tag "$tag"
}

assert_range() {
    local tag=$1 pattern=$2 expected=$3 actual
    actual=$(bash "$script" "$tag" "$pattern")
    if [ "$actual" != "$expected" ]; then
        printf 'Expected %s for %s, got %s\n' "$expected" "$tag" "$actual" >&2
        exit 1
    fi
}

assert_notes() {
    local tag=$1 pattern=$2 expected=$3 absent=$4 range notes
    range=$(bash "$script" "$tag" "$pattern")
    notes=$(git-cliff --config "$root/cliff.toml" --tag "$tag" --tag-pattern "$pattern" "$range")
    if ! grep -Fq -- "$expected" <<<"$notes" || grep -Fq -- "$absent" <<<"$notes"; then
        printf 'Unexpected notes for %s (%s):\n%s\n' "$tag" "$range" "$notes" >&2
        exit 1
    fi
}

add_tagged_commit 'fix: first stable' v0.1.0
add_tagged_commit 'feat: beta one' v0.2.0-beta.1
add_tagged_commit 'feat: settings: beta two' v0.2.0-beta.2
add_tagged_commit 'fix: stable two' v0.2.0
add_tagged_commit 'feat: later beta' v0.3.0-beta.1
add_tagged_commit 'fix: later stable' v0.3.0

stable_pattern='^v[0-9]+\.[0-9]+\.[0-9]+$'
beta_pattern='^v[0-9]+\.[0-9]+\.[0-9]+(-beta\.[0-9]+)?$'
assert_range v0.1.0 "$stable_pattern" v0.1.0
assert_range v0.2.0 "$stable_pattern" v0.1.0..v0.2.0
assert_range v0.2.0-beta.2 "$beta_pattern" v0.2.0-beta.1..v0.2.0-beta.2
assert_notes v0.2.0 "$stable_pattern" 'Stable two' 'Later stable'
assert_notes v0.2.0-beta.2 "$beta_pattern" 'Settings: beta two' 'Later beta'

printf 'Release-note ranges and rendering passed.\n'
