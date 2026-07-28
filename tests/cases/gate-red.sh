#!/usr/bin/env bash
# gate.sh red — TDD step 1. Two ways to fake it, both mechanical here: a suite that passes before the
# code exists, and a test that would pass on the base branch too (asserting nothing the slice adds).
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/harness.sh"

# ── a project with no suite cannot do TDD, and must say so ────────────────────
none="$(fixture red-no-suite)" || exit 1
stack "$none" <<'INI'
BASE_BRANCH=main
INI
check     'no TEST_CMD → RED fails rather than passing vacuously' 1 gate "$none" red
check_out 'and it names the alternative' 'observation checks'     gate "$none" red

# ── a passing suite is a failed RED gate ──────────────────────────────────────
green="$(fixture red-suite-passes)" || exit 1
stack "$green" <<'INI'
TEST_CMD=true
BASE_BRANCH=main
INI
check     'suite passes before the code exists → fail' 1 gate "$green" red
check_out 'and it says why that proves nothing' 'proves nothing' gate "$green" red

# ── a failing suite is the point ──────────────────────────────────────────────
red="$(fixture red-suite-fails)" || exit 1
stack "$red" <<'INI'
TEST_CMD=false
BASE_BRANCH=main
INI
check     'suite fails → RED passes'                     0 gate "$red" red
check_out 'no changed test files → base check is skipped, loudly' 'nothing to verify' \
  gate "$red" red
check_out '--no-base is reported, not silent'            'skipped' gate "$red" red --no-base

# ── the tautology check: new tests that also pass on the base branch ──────────
# The suite fails on HEAD (marker present) and passes in a checkout of main (marker absent) — exactly
# the shape of a test that asserts nothing the slice adds.
taut="$(fixture red-tautology)" || exit 1
stack "$taut" <<'INI'
TEST_CMD=bash tests/probe.sh
TEST_PATHS=tests
BASE_BRANCH=main
INI
write "$taut/tests/probe.sh" '[ -f head-only.txt ] && exit 1 || exit 0'
write "$taut/head-only.txt"  'present on HEAD only'
check     'tests that pass on the base branch → fail' 1 gate "$taut" red
check_out 'and it names the offending test file'  'tests/probe.sh' gate "$taut" red

# The same run with the base check disabled passes — which is why the skip is reported.
check 'the same tautology slips through --no-base' 0 gate "$taut" red --no-base

# The scratch worktree lives inside a mktemp -d. `git worktree remove` takes the worktree away and
# leaves the directory that held it, so every RED gate used to leave one behind for the life of the
# machine.
#
# TMPDIR is not usable to make this countable: BSD mktemp (macOS) ignores it and uses the per-user
# _CS_DARWIN_USER_TEMP_DIR, so a TMPDIR-based fixture would watch an empty directory and pass no matter
# what the code did — the same "skipped looks like passed" failure this suite exists to catch. So ask
# mktemp itself where it writes, and diff the tmp.* entries there across the run.
#
# Race, accepted: another process may create a tmp.* directory during the run. That direction produces a
# false FAILURE, never a false pass.
leaves_no_tmpdir() {
  local probe parent before after leaked
  probe="$(mktemp -d)"; parent="$(dirname "$probe")"; rmdir "$probe"
  before="$(find "$parent" -maxdepth 1 -type d -name 'tmp.*' 2>/dev/null | LC_ALL=C sort)"
  ( cd "$taut" && bash scripts/ai/gate.sh red >/dev/null 2>&1 )
  after="$(find "$parent" -maxdepth 1 -type d -name 'tmp.*' 2>/dev/null | LC_ALL=C sort)"
  leaked="$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after"))"
  [[ -z "${leaked// }" ]] || { printf 'left behind in %s:\n%s\n' "$parent" "$leaked"; return 1; }
}
check 'the RED/base check cleans up its temp directory' 0 leaves_no_tmpdir

done_tests
