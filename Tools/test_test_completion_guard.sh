#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

fake_bin=$(mktemp -d)
trap 'rm -rf "$fake_bin"' EXIT
args_file="$fake_bin/args.txt"

# run_case NAME EXPECTED_EXIT FAKE_SWIFT_BODY
# Installs a fake `swift` on PATH so macos/test.sh exercises the real guard
# without building or running the Waddly suites.
run_case() {
    local name=$1
    local expected=$2
    local body=$3
    {
        printf '#!/bin/sh\n'
        printf '%s\n' "$body"
    } > "$fake_bin/swift"
    chmod +x "$fake_bin/swift"

    local status=0
    PATH="$fake_bin:$PATH" WADDLY_TEST_ARGS_FILE="$args_file" ./macos/test.sh --no-parallel \
        > "$fake_bin/$name.stdout" 2> "$fake_bin/$name.stderr" || status=$?

    if [ "$status" -ne "$expected" ]; then
        printf 'FAIL %s: expected exit %s, got %s\n' "$name" "$expected" "$status" >&2
        cat "$fake_bin/$name.stdout" >&2
        cat "$fake_bin/$name.stderr" >&2
        exit 1
    fi
    printf 'PASS %s (exit %s)\n' "$name" "$status"
}

run_case "incomplete-run-fails" 1 \
    "printf '◇ Test run started.\n'"
run_case "complete-run-passes" 0 \
    "printf '◇ Test run started.\n✔ Test run with 1 tests in 0 suites passed after 0.1 seconds.\n'"
run_case "nonzero-exit-preserved" 7 \
    "printf '◇ Test run started.\n'; exit 7"
run_case "multiple-runs-incomplete-fails" 1 \
    "printf '◇ Test run started.\n✔ Test run with 3 tests in 0 suites passed after 0.1 seconds.\n◇ Test run started.\n'"
run_case "help-list-passes" 0 \
    "printf 'OVERVIEW: Run the selected tests.\n'"
run_case "stderr-diagnostic-passes" 0 \
    "printf 'warning: build noise\n' >&2; printf '◇ Test run started.\n✔ Test run with 2 tests in 0 suites passed after 0.2 seconds.\n'"
run_case "xctest-footer-not-completion-fails" 1 \
    "printf '◇ Test run started.\nExecuted 0 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds\n'"

if ! grep -q 'warning: build noise' "$fake_bin/stderr-diagnostic-passes.stderr"; then
    printf 'FAIL stderr-diagnostic-passes: diagnostic was not forwarded to stderr\n' >&2
    exit 1
fi

cat > "$fake_bin/swift" <<'FAKE'
#!/bin/sh
printf '%s\n' "$@" > "$WADDLY_TEST_ARGS_FILE"
printf '◇ Test run started.\n✔ Test run with 1 tests in 0 suites passed after 0.1 seconds.\n'
FAKE
chmod +x "$fake_bin/swift"
PATH="$fake_bin:$PATH" WADDLY_TEST_ARGS_FILE="$args_file" ./macos/test.sh --no-parallel \
    > /dev/null 2>&1
if ! grep -qx 'test' "$args_file"; then
    printf 'FAIL cli-args-forwarded: the guard did not forward the test subcommand\n' >&2
    cat "$args_file" >&2
    exit 1
fi
if ! grep -qx -- '--no-parallel' "$args_file"; then
    printf 'FAIL cli-args-forwarded: the guard did not forward the caller arguments\n' >&2
    cat "$args_file" >&2
    exit 1
fi
printf 'PASS cli-args-forwarded\n'
