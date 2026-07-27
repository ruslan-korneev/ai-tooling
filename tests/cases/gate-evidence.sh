#!/usr/bin/env bash
# gate.sh evidence (G5) — "the checks passed" is a claim; this gate is the only thing that makes it a
# fact on disk. It must refuse a run where a declared check left nothing behind.
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/harness.sh"

repo="$(fixture evidence)" || exit 1
stack "$repo" <<'INI'
BASE_BRANCH=main
INI
task "$repo" t-1

check 'no VALIDATION.md → misuse (exit 2)' 2 gate "$repo" evidence t-1

cat > "$repo/.tasks/t-1/VALIDATION.md" <<'MD'
| # | acceptance | check | expected | evidence |
| --- | --- | --- | --- | --- |
| 1 | it runs   | pytest -q | exit 0 | evidence/1.txt |
| 2 | it lints  | ruff .    | exit 0 | evidence/2.txt |
MD

check 'two checks, no evidence directory → fail' 1 gate "$repo" evidence t-1

write "$repo/.tasks/t-1/evidence/1.txt" 'pytest: 12 passed'
check     'two checks, one evidence file → fail'      1 gate "$repo" evidence t-1
check_out 'and it reports the shortfall as a count'   '2 check(s) declared, 1 evidence file(s)' \
  gate "$repo" evidence t-1

write "$repo/.tasks/t-1/evidence/2.txt" 'ruff: All checks passed'
check 'every check has evidence → pass' 0 gate "$repo" evidence t-1

# Evidence nested in a subdirectory still counts — reviewers file per-check folders.
task "$repo" t-2
cp "$repo/.tasks/t-1/VALIDATION.md" "$repo/.tasks/t-2/VALIDATION.md"
write "$repo/.tasks/t-2/evidence/check-1/out.txt" 'ok'
write "$repo/.tasks/t-2/evidence/check-2/out.txt" 'ok'
check 'evidence in subdirectories counts' 0 gate "$repo" evidence t-2

done_tests
