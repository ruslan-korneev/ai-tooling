#!/usr/bin/env bash
# gate.sh plan (G2) — the gate that decides whether a plan is reviewable. It is the cheapest place to
# catch a bad run, so its own failure modes matter: a missing section, an unmapped acceptance line, or
# a VALIDATION.md still full of placeholders must all be refusals, not warnings.
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/harness.sh"

plan_body() {
  cat <<'MD'
# Plan

**Profile:** light — reversible, no contract.

Touches: src/a.py
Depends-on: none
Out of scope: everything else
Decisions locked: keep the existing signature
MD
}
validation_body() {
  cat <<'MD'
| # | acceptance | check | expected | evidence |
| --- | --- | --- | --- | --- |
| 1 | it runs | pytest -q | exit 0 | evidence/1.txt |
MD
}

repo="$(fixture plan)" || exit 1
stack "$repo" <<'INI'
BASE_BRANCH=main
INI

check 'missing task id → misuse (exit 2)'      2 gate "$repo" plan
check 'unknown task workspace → misuse'        2 gate "$repo" plan nope-1

task "$repo" t-1
check 'no PLAN.md and no VALIDATION.md → fail' 1 gate "$repo" plan t-1

plan_body > "$repo/.tasks/t-1/PLAN.md"
check 'PLAN.md alone is not enough'            1 gate "$repo" plan t-1

validation_body > "$repo/.tasks/t-1/VALIDATION.md"
check 'plan + validation, complete → pass'     0 gate "$repo" plan t-1

# Each required section, dropped one at a time.
for section in Touches Depends-on 'Out of scope' 'Decisions locked'; do
  plan_body | grep -v "^$section" > "$repo/.tasks/t-1/PLAN.md"
  check "PLAN.md without '$section' → fail" 1 gate "$repo" plan t-1
done
plan_body > "$repo/.tasks/t-1/PLAN.md"

# An acceptance line with no runnable check is the failure this gate exists to catch.
printf '| # | acceptance | check |\n| --- | --- | --- |\n' > "$repo/.tasks/t-1/VALIDATION.md"
check 'VALIDATION.md with no numbered checks → fail' 1 gate "$repo" plan t-1

{ validation_body; printf '| 2 | later | TODO | TBD | evidence/2.txt |\n'; } > "$repo/.tasks/t-1/VALIDATION.md"
check     'VALIDATION.md still holding TODO/TBD → fail' 1 gate "$repo" plan t-1
check_out 'and it says which problem it found' 'placeholders' gate "$repo" plan t-1

{ validation_body; printf '| 2 | later | run <command> | exit 0 | evidence/2.txt |\n'; } > "$repo/.tasks/t-1/VALIDATION.md"
check 'VALIDATION.md holding an unfilled <template> → fail' 1 gate "$repo" plan t-1

done_tests
