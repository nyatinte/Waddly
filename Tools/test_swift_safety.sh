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

"$checker" --expect-rule unchecked-sendable "$package_path/Fixtures/unchecked-sendable-enum.swift"
"$checker" --expect-rule unsafe-cast "$package_path/Fixtures/unsafe-downcast.swift"
"$checker" --expect-rule unsafe-pointer "$package_path/Fixtures/unsafe-unmanaged-generic.swift"

syntax_error_fixture=$(mktemp)
trap 'rm -f "$syntax_error_fixture"' EXIT
printf 'let broken = (\n' > "$syntax_error_fixture"
if output=$("$checker" --expect-rule unsafe-cast "$syntax_error_fixture" 2>&1); then
    printf 'Swift safety checker accepted malformed Swift syntax.\n' >&2
    exit 1
fi
if ! grep -q "SwiftSyntax could not parse" <<< "$output"; then
    printf 'Swift safety checker failed for an unexpected reason:\n%s\n' "$output" >&2
    exit 1
fi
