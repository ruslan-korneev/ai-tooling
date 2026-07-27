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

# ── nothing configured ────────────────────────────────────────────────────────
# The honest answer is "this proved nothing". Today every command is SKIPPED and the gate returns 0,
# which is indistinguishable from a project where everything ran and passed. Tracked, not yet fixed.
none="$(fixture green-unconfigured)" || exit 1
stack "$none" <<'INI'
BASE_BRANCH=main
INI
check_out 'static: unconfigured commands are announced as SKIPPED' 'SKIPPED' gate "$none" static
check_xfail 'static: nothing configured must not report success'  1 gate "$none" static
check_xfail 'green: nothing configured must not report success'   1 gate "$none" green

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

done_tests
