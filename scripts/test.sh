#!/bin/bash
# Runs the tests. With only the Command Line Tools selected, SwiftPM can't find Testing.framework
# on its own, so point the compiler and the test runner at it. With Xcode selected (CI), it finds it.
#
#   scripts/test.sh              three passes that never overlap: everything else, the tests that draw views, then the exhaustive tests
#   scripts/test.sh --filter X   one run, with the arguments passed to `swift test`
#
# The exhaustive tests sweep all of Unicode or draw thousands of glyphs: seconds of CPU on every core, which on a
# three core CI runner starves the tests that wait for a real event with a deadline. They have `exhaustive` at the
# start of their name (and the `.exhaustive` tag; see PermissionTestSupport.swift), and `swift test` can't select by tag.
# The tests that draw views run on the main actor, one after the other, and each holds it for most of a second (text recognition of what was drawn
# among them): all together about thirteen seconds that every other test of the main actor waits behind, which on a machine ten times as slow is two
# minutes in which a test that waits for a real event on that actor gets no turn. They are the suites named in `DRAWING` (`DrawingPassTests` keeps
# the list whole), and wait for nothing, so they are no worse for running alone.
# CI runs this script, so it runs the same three passes.
#
# A pass that hangs fails instead: after TEST_PASS_TIMEOUT seconds (600), or at once when the test process has crashed and
# `swift test` waits for a process the tests left behind (see `give_up`). It ends only processes of the pass (see `pass_victims`): never
# this script, what started it (CI's runner included) or anything else on the machine.
set -euo pipefail
cd "$(dirname "$0")/.."

EXHAUSTIVE='/exhaustive'
DRAWING='NunsseopTests\.(PermissionLayoutTests|PermissionQuestionLayoutTests|CodexPermissionLayoutTests|PermissionAllowlistTests|AgentFooterRenderTests|LiveEarRenderTests|HeaderTabWidthTests|OnboardingRenderTests|RecapRenderTests|HUDLineRenderTests)/'

swift_test() {
    local CLT=/Library/Developer/CommandLineTools/Library/Developer
    if [[ "$(xcode-select -p 2>/dev/null || true)" == /Library/Developer/CommandLineTools && -d "$CLT/Frameworks/Testing.framework" ]]; then
        swift test -Xswiftc -F"$CLT/Frameworks" \
            -Xlinker -rpath -Xlinker "$CLT/Frameworks" -Xlinker -rpath -Xlinker "$CLT/usr/lib" "$@"
    else
        swift test "$@"
    fi
}

if (( $# > 0 )); then
    swift_test "$@"
    exit
fi

LOG="$(mktemp -d)"
trap 'kill $(jobs -p) 2>/dev/null || true; rm -rf "$LOG"' EXIT
status=0

PASS_TIMEOUT="${TEST_PASS_TIMEOUT:-600}"

# The processes a pass may end, one per line as "pid reason", and nothing else:
#   - the tree of the pass: the subshell that runs `swift test` ($2) and everything below it;
#   - the orphans of the pass (their parent is launchd, 1): the stand-ins a test left behind when its process ended. They are the ones that
#     have the pass's output file ($1) open, or hold a pipe that a process of the tree holds the other end of.
# Never this script and what it descends from (up to launchd: the shell of a CI step, the runner), `tail` ($3), another user's processes, the
# system's, and, as a last guard, anything that is the GitHub runner. So a process that merely shares a descriptor with the pass can't be a victim.
pass_victims() {
    local ps_file="$LOG/victims.ps" file_holders="$LOG/victims.files" pipe_ends="$LOG/victims.pipes"
    ps -axo pid=,ppid=,uid=,command= > "$ps_file"
    lsof -t "$1" > "$file_holders" 2>/dev/null || true
    # pid, the pipe's own end, the other end of it: lsof prints "->0x..." last for a pipe.
    lsof -n -w 2>/dev/null | awk '$5 == "PIPE" { print $2, $6, ($NF ~ /^->/ ? substr($NF, 3) : "-") }' > "$pipe_ends" || true
    awk -v root="$2" -v tail_pid="$3" -v self="$$" -v uid="$(id -u)" '
        FILENAME == ARGV[1] { pid = $1; parent[pid] = $2; owner[pid] = $3; sub(/^ *[0-9]+ +[0-9]+ +[0-9]+ +/, ""); command[pid] = $0; next }
        FILENAME == ARGV[2] { holds_output[$1] = 1; next }
        { pipes[$1] = pipes[$1] " " $2 " " $3 }
        function in_tree(p,   n) { for (n = 0; p != "" && p != 0 && p != 1 && n < 1000; n++) { if (p == root) return 1; p = parent[p] } return 0 }
        END {
            for (p = self; p != "" && p != 0; p = parent[p]) protected[p] = 1
            protected[tail_pid] = 1
            # The pipe ends the tree holds, both of each pipe.
            for (p in parent) if (in_tree(p)) { n = split(pipes[p], e, " "); for (i = 1; i <= n; i++) if (e[i] != "-") tree_end[e[i]] = 1 }
            for (p in parent) {
                if (p in protected || owner[p] != uid) continue
                if (command[p] ~ /Runner\.Listener|Runner\.Worker|hosted-compute|^\/System\//) continue
                if (in_tree(p)) { print p, "process of the pass (below pid " root ")"; continue }
                if (parent[p] != 1) continue
                if (p in holds_output) { print p, "orphan with the pass output file open"; continue }
                n = split(pipes[p], e, " ")
                for (i = 1; i <= n; i += 2) if (e[i] in tree_end) { print p, "orphan holding a pipe of the pass"; break }
            }
        }' "$ps_file" "$file_holders" "$pipe_ends" | sort -n
}

# Where the test process crashed, from a crash report: the frames of the thread that crashed.
crash_frames() {
    python3 -I -c '
import json, sys
body = json.loads(open(sys.argv[1]).read().split("\n", 1)[1])
print(*(frame.get("symbol", "?")[:150] for frame in body["threads"][body["faultingThread"]]["frames"][:10]), sep="\n")' "$1" 2>/dev/null || true
}

# Says where a pass stands, then ends its processes (see `pass_victims`) after saying which and why: them by their command, a stack sample
# of the test process if it is still there and, if it crashed, where.
give_up() {
    local name="$1" why="$2" tail_pid="$3" root="$4" pid reason report victims
    printf '\n✘ Pass %s: %s\n' "$name" "$why" >&2
    victims="$(pass_victims "$LOG/$name.txt" "$root" "$tail_pid")"
    while read -r pid reason; do
        [[ -n "$pid" ]] || continue
        ps -o pid=,ppid=,stat=,etime=,command= -p "$pid" | cut -c1-200 >&2 || true
        echo "    will end it: $reason" >&2
        case "$(ps -o command= -p "$pid" 2>/dev/null)" in
            *swiftpm-testing-helper*|*xctest*)
                sample "$pid" 3 -file "$LOG/$name.sample.txt" >/dev/null 2>&1 || true
                head -n 150 "$LOG/$name.sample.txt" >&2 || true ;;
        esac
    done <<< "$victims"
    report="$(ls -t "$HOME"/Library/Logs/DiagnosticReports/swiftpm-testing-helper*.ips 2>/dev/null | head -n 1 || true)"
    if [[ -n "$report" && "$report" -nt "$LOG/$name.txt" ]]; then
        echo "The test process crashed: $report" >&2
        crash_frames "$report" >&2
    fi
    victims="$(echo "$victims" | awk 'NF { print $1 }')"
    kill $victims 2>/dev/null || true
    sleep 1
    kill -9 $victims 2>/dev/null || true
}

# Whether the test process has ended and not been collected: a zombie below `$1` that is the test process (or `swift test` itself), by its
# command or by being at most two levels below `$1`. When the test process crashes while a stand-in it started still holds the output,
# `swift test` keeps waiting for it and the dead process stays as it is. A zombie anywhere else in the tree (a short-lived child of a test) isn't it.
has_uncollected() {
    ps -axo pid=,ppid=,stat=,command= | awk -v root="$1" '
        { pid = $1; parent[pid] = $2; stat[pid] = $3; sub(/^ *[0-9]+ +[0-9]+ +[^ ]+ +/, ""); command[pid] = $0 }
        END { for (p in parent) {
                  if (stat[p] !~ /^Z/ || p == root) continue
                  near = parent[p] == root || parent[parent[p]] == root
                  q = p; for (n = 0; q != "" && q != 0 && q != root && n < 1000; n++) q = parent[q]
                  if (q == root && (near || command[p] ~ /swiftpm-testin|xctest/)) found = 1 }
              exit !found }'
}

# A filter that matches nothing "passes" with 0 tests, so a pass with none is a failure.
run_pass() {
    local name="$1"; shift
    local out="$LOG/$name.txt" waited=0 uncollected=0 hung="" code=0
    echo "▸ Pass: $name" >&2
    : > "$out"
    # The output goes to a file, not into a pipe: a process that holds a pipe open keeps whatever reads the pipe from ending.
    # It has no standard input and no descriptor of this script's or of what started it (CI's runner has pipes open here): a process of the pass
    # that holds one is, to the watchdog and to the runner, a process of the runner.
    (
        trap - EXIT
        for fd in /dev/fd/*; do
            fd="${fd##*/}"
            if (( fd > 2 && fd != 255 )); then eval "exec $fd>&-" 2>/dev/null || true; fi
        done
        swift_test "$@"
    ) < /dev/null > "$out" 2>&1 &
    local test_pid=$!
    tail -f "$out" < /dev/null &
    local tail_pid=$!
    while kill -0 "$test_pid" 2>/dev/null; do
        sleep 1
        waited=$((waited + 1))
        if has_uncollected "$test_pid"; then uncollected=$((uncollected + 1)); else uncollected=0; fi
        if (( uncollected >= 10 )); then hung="the test process ended and swift test is stuck, waiting for a process the tests left that holds its output"; fi
        if (( waited > PASS_TIMEOUT )); then hung="still running after $PASS_TIMEOUT seconds"; fi
        if [[ -n "$hung" ]]; then
            give_up "$name" "$hung" "$tail_pid" "$test_pid"
            break
        fi
    done
    wait "$test_pid" || code=$?
    sleep 1
    kill "$tail_pid" 2>/dev/null || true
    wait "$tail_pid" 2>/dev/null || true
    if [[ -n "$hung" || $code -ne 0 ]]; then
        echo "✘ Pass failed: $name" >&2
        status=1
    elif ! grep -qE "Test run with [1-9][0-9]* tests?" "$out"; then
        echo "✘ Pass ran no tests: $name" >&2
        status=1
    fi
}

run_pass "everything-else" --skip "$EXHAUSTIVE" --skip "$DRAWING"
run_pass "drawing" --filter "$DRAWING" --skip "$EXHAUSTIVE"
run_pass "exhaustive" --filter "$EXHAUSTIVE"

echo "▸ Summaries" >&2
for name in everything-else drawing exhaustive; do
    echo "$name: $(grep -E 'Test run with' "$LOG/$name.txt" | tail -1)" >&2
done
exit "$status"
