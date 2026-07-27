#!/usr/bin/env bash
# gate.sh groom (G1) — the lens set is the coverage, so this gate is really two claims: every lens
# required by the profile ran, and the last run of each one came back clean. Both have to be
# mechanical, or "we groomed it" degrades into "we ran the cheap lens twice".
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/harness.sh"

repo="$(fixture groom)" || exit 1
stack "$repo" <<'INI'
LENSES=contracts,failure-modes,adversary,meta
DEFAULT_PROFILE=standard
INI

log_header() { printf '| pass | lens | outcome | blockers | majors | minors |\n| --- | --- | --- | --- | --- | --- |\n'; }
row() { printf '| P%s | %s | %s | %s | %s | %s |\n' "$1" "$2" "${3:-quiet}" "${4:-0}" "${5:-0}" "${6:-0}"; }
plan_with_profile() { printf '# Plan\n\n**Profile:** %s — fixture.\n' "$1"; }

task "$repo" t-1
check 'no GROOM_LOG.md → fail' 1 gate "$repo" groom t-1

# ── light: one lens is the whole requirement ──────────────────────────────────
plan_with_profile light > "$repo/.tasks/t-1/PLAN.md"
{ log_header; row 1 contracts; } > "$repo/.tasks/t-1/GROOM_LOG.md"
check 'light: first lens clean → pass' 0 gate "$repo" groom t-1

# ── standard: contracts + adversary, both required ────────────────────────────
plan_with_profile standard > "$repo/.tasks/t-1/PLAN.md"
check     'standard: adversary never ran → fail'    1 gate "$repo" groom t-1
check_out 'and it names the missing lens'  'adversary' gate "$repo" groom t-1

{ log_header; row 1 contracts; row 2 adversary; } > "$repo/.tasks/t-1/GROOM_LOG.md"
check 'standard: both lenses clean → pass' 0 gate "$repo" groom t-1

# A lens that found majors is not closed, however many other passes happened afterwards.
{ log_header; row 1 contracts; row 2 adversary 'majors found' 0 2; } > "$repo/.tasks/t-1/GROOM_LOG.md"
check 'a lens whose last pass found majors → fail' 1 gate "$repo" groom t-1

{ log_header; row 1 contracts; row 2 adversary 'majors found' 0 2; row 3 adversary; } \
  > "$repo/.tasks/t-1/GROOM_LOG.md"
check 'the lens re-ran clean after folding them in → pass' 0 gate "$repo" groom t-1

{ log_header; row 1 contracts; row 2 adversary quiet 1 0; } > "$repo/.tasks/t-1/GROOM_LOG.md"
check 'a lens holding a blocker → fail' 1 gate "$repo" groom t-1

# Minors never gate: re-running a lens to clear them is the ceremony this gate refuses to reward.
{ log_header; row 1 contracts quiet 0 0 4; row 2 adversary quiet 0 0 3; } > "$repo/.tasks/t-1/GROOM_LOG.md"
check 'minors do not block' 0 gate "$repo" groom t-1

# ── deep: every configured lens ───────────────────────────────────────────────
plan_with_profile deep > "$repo/.tasks/t-1/PLAN.md"
check 'deep: two of four lenses → fail' 1 gate "$repo" groom t-1
{ log_header; row 1 contracts; row 2 failure-modes; row 3 adversary; row 4 meta; } \
  > "$repo/.tasks/t-1/GROOM_LOG.md"
check 'deep: all four lenses clean → pass' 0 gate "$repo" groom t-1

# ── an open blocker stops the run regardless of the ledger ────────────────────
cat > "$repo/.tasks/t-1/OPEN_QUESTIONS.md" <<'MD'
## Blockers

1. **Which store owns the balance?** Nobody could say.

## Clarify
MD
check     'open blocker → fail even with every lens clean' 1 gate "$repo" groom t-1
check_out 'and it points at the file'  'OPEN_QUESTIONS.md' gate "$repo" groom t-1

done_tests
