#!/usr/bin/env bash
set -euo pipefail

package_path="Tools/SwiftSafetyCheck"
swift build --package-path "$package_path"
checker="$package_path/.build/debug/swift-safety-check"

for pair in "force-cast:force_cast" "force-try:force_try" "force-unwrap:force_unwrapping"; do
    fixture_rule="${pair%%:*}"
    swiftlint_rule="${pair#*:}"
    fixture="$package_path/Fixtures/$fixture_rule.swift"
    if output="$(TOOLCHAIN_DIR="$(xcode-select -p)" mise exec aqua:realm/SwiftLint -- swiftlint lint --strict --config "$package_path/.swiftlint-fixtures.yml" "$fixture" 2>&1)"; then
        printf 'SwiftLint accepted unsafe fixture: %s\n' "$fixture_rule" >&2
        exit 1
    fi
    if ! grep -q "$swiftlint_rule" <<< "$output"; then
        printf 'SwiftLint failed for an unexpected reason in fixture: %s\n%s\n' "$fixture_rule" "$output" >&2
        exit 1
    fi
    printf 'Fixture rejected as expected: %s\n' "$fixture_rule"
done

for rule in actor-assumption preconcurrency semaphore-wait switch-default unchecked-sendable unsafe-cast unsafe-isolation unsafe-pointer; do
    "$checker" --expect-rule "$rule" "$package_path/Fixtures/$rule.swift"
done
