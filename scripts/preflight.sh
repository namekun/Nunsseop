#!/bin/bash
# Everything that must pass before a release: run by release.sh first, and on its own any time.
#
#   scripts/preflight.sh            all checks
#   scripts/preflight.sh --local    skip the checks that need main pushed and CI finished
set -euo pipefail
cd "$(dirname "$0")/.."

LOCAL=0
[[ "${1:-}" == "--local" ]] && LOCAL=1
LOG="$(mktemp -d)"
step() { echo "▸ $*" >&2; }
fail() { echo "✘ $*" >&2; exit 1; }

if (( ! LOCAL )); then
    step "main, clean and the same as origin/main"
    [[ "$(git branch --show-current)" == "main" ]] || fail "Not on main"
    [[ -z "$(git status --porcelain)" ]] || fail "Working tree is not clean"
    git fetch -q origin main
    [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || fail "main is not origin/main; pull or push first"

    step "CI passed on this commit"
    CI="$(gh run list --commit "$(git rev-parse HEAD)" --workflow CI --json status,conclusion \
        -q '.[0] | "\(.status) \(.conclusion)"')"
    [[ "$CI" == "completed success" ]] || fail "CI on this commit is '${CI:-not run}'; wait for it to pass"
fi

step "A clean build has no warnings"
swift build --scratch-path "$LOG/build" >"$LOG/build.txt" 2>&1 || { tail -30 "$LOG/build.txt" >&2; fail "Build failed"; }
if grep -q "warning:" "$LOG/build.txt"; then
    grep "warning:" "$LOG/build.txt" | sort -u >&2
    fail "Fix the warnings above"
fi

# Three runs in a row, so a test that passes only sometimes is caught here rather than after the release.
for run in 1 2 3; do
    step "Tests, run $run of 3"
    ./scripts/test.sh >"$LOG/test-$run.txt" 2>&1 || { grep -E "✘|error:" "$LOG/test-$run.txt" | head -40 >&2; fail "Tests failed on run $run"; }
    grep -E "Test run with" "$LOG/test-$run.txt" >&2
done

step "Site"
bash scripts/site-test.sh >&2 || fail "Site test failed"

rm -rf "$LOG"
echo "✔ Preflight passed" >&2
