#!/usr/bin/env bash
# tests/lib/harness.sh — fixtures and assertions for the ADW script tests. Sourced, not run.
#
# Every case in tests/cases/ sources this file and gets:
#
#   fixture <name>                 → throwaway git repo with scripts/ai/ installed; echoes its path
#   stack <dir> <<'INI' … INI      → writes .tasks/_STACK.md wrapping the ini body from stdin
#   task <dir> <id>                → creates .tasks/<id>/
#   gate|guard|review <dir> <args> → runs that script inside <dir>
#   check       <label> <rc> cmd…  → assert exit code
#   check_out   <label> <needle> cmd…
#                                  → assert the combined output contains <needle>
#   check_empty <label> cmd…       → assert the command produced nothing at all
#   check_xfail <label> <rc> cmd…  → a gap we know about and have not closed yet. The assertion is
#                                    expected to FAIL; if it starts passing the suite fails, so the
#                                    test gets promoted to check() instead of quietly rotting.
#   done_tests                     → print the tally, exit 0 (all held) or 1 (something failed)
#
# Fixtures live under one mktemp -d and are removed on every exit path.
# Requires: bash, git. No network, no gh, no engines.
set -uo pipefail

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADW_ROOT="$(cd "$HARNESS_DIR/../.." && pwd)"

_tmp_root=""
_pass=0
_fail=0
_xfail=0

_cleanup() { [[ -n "$_tmp_root" && -d "$_tmp_root" ]] && rm -rf "${_tmp_root:?}"; return 0; }
trap _cleanup EXIT

# ── fixtures ──────────────────────────────────────────────────────────────────

fixture() {
  local name="${1:?usage: fixture <name>}" dir
  [[ -n "$_tmp_root" ]] || _tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/adw-tests.XXXXXX")"
  dir="$_tmp_root/$name"
  mkdir -p "$dir/scripts/ai" "$dir/.tasks"
  cp "$ADW_ROOT"/scripts/*.sh "$dir/scripts/ai/"
  (
    cd "$dir" || exit 1
    git init -q .
    git symbolic-ref HEAD refs/heads/main          # portable default branch, pre-2.28 git included
    git config user.email adw@test.invalid
    git config user.name  "ADW Test"
    git config commit.gpgsign false
    printf 'fixture\n' > README.md
    git add README.md && git commit -qm seed
  ) >/dev/null 2>&1 || { printf 'fixture: git init failed in %s\n' "$dir" >&2; return 1; }
  printf '%s' "$dir"
}

# stack <dir> — the ini body comes from stdin; the fences are added here.
stack() {
  local dir="${1:?usage: stack <dir> <<INI}"
  { printf '# _STACK.md — test fixture\n\n```ini\n'; cat; printf '```\n'; } > "$dir/.tasks/_STACK.md"
}

task() {
  local dir="${1:?usage: task <dir> <id>}" id="${2:?usage: task <dir> <id>}"
  mkdir -p "$dir/.tasks/$id"
}

commit_all() { ( cd "$1" && git add -A && git commit -qm "${2:-step}" ) >/dev/null 2>&1; }
git_in()     { local d="$1"; shift; ( cd "$d" && git "$@" ) >/dev/null 2>&1; }
write()      { mkdir -p "$(dirname "$1")" && printf '%s\n' "${2:-x}" > "$1"; }

# ── script runners ────────────────────────────────────────────────────────────

gate()   { local d="$1"; shift; ( cd "$d" && bash scripts/ai/gate.sh   "$@" ); }
guard()  { local d="$1"; shift; ( cd "$d" && bash scripts/ai/guard.sh  "$@" ); }
review() { local d="$1"; shift; ( cd "$d" && bash scripts/ai/review.sh "$@" ); }

# ── assertions ────────────────────────────────────────────────────────────────

_run() { _out="$("$@" 2>&1)"; _rc=$?; }

check() {
  local label="$1" want="$2"; shift 2
  _run "$@"
  if (( _rc == want )); then
    printf '  ok   %s\n' "$label"; _pass=$(( _pass + 1 ))
  else
    printf '  FAIL %s — expected exit %s, got %s\n' "$label" "$want" "$_rc"
    printf '%s\n' "$_out" | sed 's/^/       │ /'
    _fail=$(( _fail + 1 ))
  fi
}

check_out() {
  local label="$1" needle="$2"; shift 2
  _run "$@"
  if printf '%s' "$_out" | grep -qF -- "$needle"; then
    printf '  ok   %s\n' "$label"; _pass=$(( _pass + 1 ))
  else
    printf '  FAIL %s — output does not contain %s\n' "$label" "$needle"
    printf '%s\n' "$_out" | sed 's/^/       │ /'
    _fail=$(( _fail + 1 ))
  fi
}

check_empty() {
  local label="$1"; shift
  _run "$@"
  if [[ -z "${_out//[[:space:]]/}" ]]; then
    printf '  ok   %s\n' "$label"; _pass=$(( _pass + 1 ))
  else
    printf '  FAIL %s — expected no output, got:\n' "$label"
    printf '%s\n' "$_out" | sed 's/^/       │ /'
    _fail=$(( _fail + 1 ))
  fi
}

# A known gap, asserted the way we WANT it to behave. Failing is the expected state and keeps the
# suite green; passing means someone fixed it and the test must be promoted to check().
check_xfail() {
  local label="$1" want="$2"; shift 2
  _run "$@"
  if (( _rc == want )); then
    printf '  XPASS %s — the gap is closed, promote this to check()\n' "$label"
    _fail=$(( _fail + 1 ))
  else
    printf '  xfail %s (known gap: wants exit %s, gets %s)\n' "$label" "$want" "$_rc"
    _xfail=$(( _xfail + 1 ))
  fi
}

done_tests() {
  printf '  ── %s passed · %s failed · %s known gaps\n' "$_pass" "$_fail" "$_xfail"
  (( _fail == 0 ))
}
