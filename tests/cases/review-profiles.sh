#!/usr/bin/env bash
# review.sh — only the parts that run without an engine CLI: profile resolution and the two refusals
# that must happen before any agent is spawned. The fan-out itself is not covered here.
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/harness.sh"

repo="$(fixture review)" || exit 1
stack "$repo" <<'INI'
DEFAULT_PROFILE=standard
BASE_BRANCH=main
INI

check     'unknown profile → misuse (exit 2)'          2 review "$repo" 1 --profile bogus
check_out 'and it lists the profiles that exist' 'superlight|light|standard|deep' \
  review "$repo" 1 --profile bogus

# superlight is a real profile, not an unknown one: it must get past profile resolution and fail on the
# next thing (the missing rubric), never on its own name.
check_out 'superlight is recognised, and stops at the rubric instead' 'rubric' \
  review "$repo" 1 --profile superlight

# Without the rubric there is nothing to review against, and a reviewer with no rubric returns
# plausible prose. Refusing is the only safe answer.
check     'no slice-review skill installed → exit 2'   2 review "$repo" 1 --profile light
check_out 'and it says what to install'  'slice-review' review "$repo" 1 --profile light

# A rubric that exists but has no reviewer section is the same failure wearing a different hat.
mkdir -p "$repo/.claude/skills/slice-review"
printf '# slice-review\n\nNothing here yet.\n' > "$repo/.claude/skills/slice-review/SKILL.md"
check     'rubric present but empty → exit 2'          2 review "$repo" 1 --profile light
check_out 'and it says the rubric could not be read' 'rubric' review "$repo" 1 --profile light

done_tests
