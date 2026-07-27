#!/usr/bin/env bash
# gate.sh static / test / green — the gates every run leans on. The dangerous case is not a failing
# check, it is a check that was never configured: an unconfigured command reports SKIPPED and still
# exits 0, so a project with nothing wired up produces a green run over zero verification.
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/harness.sh"

# ── everything configured and passing ─────────────────────────────────────────
ok="$(fixture green-ok)" || exit 1
stack "$ok" <<'INI'
FORMAT_CHECK_CMD=true
LINT_CMD=true
TYPECHECK_CMD=true
TEST_CMD=true
INI
check 'static: all three pass'        0 gate "$ok" static
check 'test: suite passes'            0 gate "$ok" test
check 'green: static + tests pass'    0 gate "$ok" green

# ── a failing check must fail the gate, and must not hide the checks after it ──
bad="$(fixture green-lint-fails)" || exit 1
stack "$bad" <<'INI'
FORMAT_CHECK_CMD=true
LINT_CMD=false
TYPECHECK_CMD=true
TEST_CMD=true
INI
check     'static: lint fails → gate fails'   1 gate "$bad" static
check_out 'static: typecheck still ran after lint failed' 'typecheck' gate "$bad" static
check     'green: static failure fails green' 1 gate "$bad" green

tf="$(fixture green-test-fails)" || exit 1
stack "$tf" <<'INI'
LINT_CMD=true
TEST_CMD=false
INI
check 'test: failing suite → exit 1'  1 gate "$tf" test
check 'green: failing suite → exit 1' 1 gate "$tf" green

# ── nothing configured → DEGRADED (exit 3), which is neither pass nor fail ────
none="$(fixture green-unconfigured)" || exit 1
stack "$none" <<'INI'
BASE_BRANCH=main
INI
check_out 'static: unconfigured commands are announced as SKIPPED' 'SKIPPED' gate "$none" static
check     'static: no check ran → degraded, not success'  3 gate "$none" static
check_out 'and it says so in one word'         'DEGRADED'   gate "$none" static
check     'green: nothing ran at all → degraded'          3 gate "$none" green
check_out 'and it spells out what green would mean here' 'we looked at nothing' gate "$none" green

# An unset command with a stated reason is a decision, not an omission. It reads differently — and it
# still does not count as verification, because no linter still means no lint coverage.
declared="$(fixture green-declared-none)" || exit 1
stack "$declared" <<'INI'
FORMAT_CHECK_CMD=       # none: the formatter is not idempotent in this toolchain
LINT_CMD=               # none: no linter for Luau
TYPECHECK_CMD=          # none: no type checker
TEST_CMD=true
INI
check_out 'a declared "none" is quoted back, not reported as missing config' 'declared none' \
  gate "$declared" static
check 'declared "none" everywhere still means nothing ran' 3 gate "$declared" static

# ── partial: something ran, so it passes, but the gap is reported ─────────────
partial="$(fixture green-partial)" || exit 1
stack "$partial" <<'INI'
LINT_CMD=true
TEST_CMD=true
INI
check     'static: one of three configured and passing → pass' 0 gate "$partial" static
check_out 'and it names what was never configured'  'never configured' gate "$partial" static

no_tests="$(fixture green-no-suite)" || exit 1
stack "$no_tests" <<'INI'
LINT_CMD=true
INI
check     'test: no TEST_CMD → degraded'                     3 gate "$no_tests" test
check     'green: static ran, no suite → pass, not degraded' 0 gate "$no_tests" green
check_out 'and it flags the half that never ran' 'PARTIAL' gate "$no_tests" green

no_static="$(fixture green-no-static)" || exit 1
stack "$no_static" <<'INI'
TEST_CMD=true
INI
check     'green: suite ran, no static check → pass'  0 gate "$no_static" green
check_out 'and it flags that half too'      'PARTIAL' gate "$no_static" green

# A real failure still outranks every degradation.
mixed="$(fixture green-fail-beats-degraded)" || exit 1
stack "$mixed" <<'INI'
LINT_CMD=false
INI
check 'a failing check with everything else unconfigured → fail, not degraded' 1 gate "$mixed" green

# ── TEST_ONE_CMD targeting ────────────────────────────────────────────────────
one="$(fixture green-test-one)" || exit 1
stack "$one" <<'INI'
TEST_CMD=echo whole-suite
TEST_ONE_CMD=echo one <path>
INI
check_out 'test <path>: TEST_ONE_CMD wins and <path> is substituted' 'one tests/test_x.py' \
  gate "$one" test tests/test_x.py
check_out 'test: no target → TEST_CMD' 'whole-suite' gate "$one" test

check 'unknown gate name → exit 2' 2 gate "$ok" no-such-gate

# ── `all` aggregates three gates: a failure outranks a degradation, which outranks a pass ─────
plan_and_validation() {
  local dir="$1"
  task "$dir" t-1
  printf 'Touches: a\nDepends-on: none\nOut of scope: none\nDecisions locked: none\n' \
    > "$dir/.tasks/t-1/PLAN.md"
  printf '| # | acceptance | check | expected | evidence |\n| --- | --- | --- | --- | --- |\n| 1 | runs | true | exit 0 | evidence/1.txt |\n' \
    > "$dir/.tasks/t-1/VALIDATION.md"
  write "$dir/.tasks/t-1/evidence/1.txt" 'ok'
}
plan_and_validation "$ok"
check 'all: everything configured and passing → 0' 0 gate "$ok" all t-1

plan_and_validation "$none"
check 'all: plan and evidence fine, but nothing ran → 3' 3 gate "$none" all t-1

plan_and_validation "$tf"
check 'all: a failing suite outranks any degradation → 1' 1 gate "$tf" all t-1

done_tests
