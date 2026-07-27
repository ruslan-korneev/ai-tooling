#!/usr/bin/env bash
# gate.sh committed — a step that is not committed and pushed does not exist: it cannot be reviewed,
# reverted or recovered. Both halves of that claim are checked here; the push half only as far as a
# fixture without a remote can go.
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/harness.sh"

repo="$(fixture committed)" || exit 1
stack "$repo" <<'INI'
BASE_BRANCH=main
INI
write "$repo/src/app.py" 'x = 1'
commit_all "$repo" 'seed the tree'
write "$repo/src/app.py" 'x = 2'

check     'uncommitted work → fail'                 1 gate "$repo" committed
check_out 'and it lists what is still dirty' 'src/app.py' gate "$repo" committed

commit_all "$repo" 'commit the step'
check     'committed but never pushed → still fail' 1 gate "$repo" committed
check_out 'and it says the branch has no upstream'  'upstream' gate "$repo" committed

# The worktree env file is machine-local and is deliberately not a reason to fail.
write "$repo/.tasks/_worktree.env" 'PORT=5001'
check_out 'the local _worktree.env is not counted as dirty work' 'upstream' gate "$repo" committed

done_tests
