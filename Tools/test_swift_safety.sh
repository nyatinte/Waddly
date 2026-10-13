#!/usr/bin/env bash
set -euo pipefail

package_path="Tools/SwiftSafetyCheck"
swift build --package-path "$package_path"
checker="$package_path/.build/debug/swift-safety-check"

for fixture in "$package_path"/Fixtures/*.swift; do
    rule="$(basename "$fixture" .swift)"
    "$checker" --expect-rule "$rule" "$fixture"
done
