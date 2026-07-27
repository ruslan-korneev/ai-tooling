#!/usr/bin/env bash
# guard.sh — agent identity is "what you may not touch", and a prompt that says "please don't" is not a
# boundary. These are the assertions that make it one.
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/harness.sh"

repo="$(fixture guard)" || exit 1
stack "$repo" <<'INI'
SRC_PATHS=src
TEST_PATHS=tests
BASE_BRANCH=main
INI
write "$repo/src/app.py"      'x = 1'
write "$repo/tests/test_a.py" 'assert True'
write "$repo/.tasks/t-1/PLAN.md" '# Plan'
commit_all "$repo" 'seed the tree'
git_in "$repo" checkout -b t-1-slice

check 'clean branch → every role is in scope' 0 guard "$repo" builder

# ── builder ───────────────────────────────────────────────────────────────────
write "$repo/src/app.py" 'x = 2'
check 'builder editing source → allowed' 0 guard "$repo" builder
write "$repo/tests/test_a.py" 'assert False'
check     'builder editing a test → blocked'          1 guard "$repo" builder
check_out 'and it names the file'    'tests/test_a.py'  guard "$repo" builder
check_out 'and it says to hand it back, not edit it' 'hand it back' guard "$repo" builder

# ── test-author, the mirror image ─────────────────────────────────────────────
check 'test-author editing source → blocked' 1 guard "$repo" test-author
git_in "$repo" checkout -- src/app.py
check 'test-author editing only tests → allowed' 0 guard "$repo" test-author

# ── planner and reviewer ──────────────────────────────────────────────────────
check 'planner touching a test file → blocked' 1 guard "$repo" planner
git_in "$repo" checkout -- tests/test_a.py
write "$repo/.tasks/t-1/PLAN.md" '# Plan v2'
check 'planner touching only .tasks/ → allowed' 0 guard "$repo" planner
check 'reviewer with any diff at all → blocked' 1 guard "$repo" reviewer
git_in "$repo" checkout -- .tasks/t-1/PLAN.md
check 'reviewer with an empty diff → allowed' 0 guard "$repo" reviewer

# ── committed changes count, not just the working tree ────────────────────────
write "$repo/tests/test_a.py" 'assert 1 == 1'
commit_all "$repo" 'edit a test and commit it'
check 'a violation that was already committed is still a violation' 1 guard "$repo" builder
check '--head scopes to the working tree only' 0 guard "$repo" builder --head

# ── misuse ────────────────────────────────────────────────────────────────────
check 'no role → exit 2'      2 guard "$repo"
check 'unknown role → exit 2' 2 guard "$repo" architect
check 'unknown scope → exit 2' 2 guard "$repo" builder --everything

# ── siblings ──────────────────────────────────────────────────────────────────
solo="$(fixture guard-siblings)" || exit 1
stack "$solo" <<'INI'
BASE_BRANCH=main
INI
check_out 'no SIBLING_REPOS → nothing to check' 'nothing to check' guard "$solo" siblings

sib="$(fixture guard-sibling-repo)" || exit 1
commit_all "$sib" 'sibling starts clean'
multi="$(fixture guard-multi)" || exit 1
stack "$multi" <<INI
BASE_BRANCH=main
SIBLING_REPOS=$sib:ro
INI
check 'a clean read-only sibling → allowed' 0 guard "$multi" siblings
write "$sib/core.py" 'changed next door'
check     'a dirty read-only sibling → blocked'   1 guard "$multi" siblings
check_out 'and it shows what changed there' 'core.py' guard "$multi" siblings

done_tests
