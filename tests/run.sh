#!/usr/bin/env bash
# tests/run.sh — run the ADW harness self-tests.
#
# Usage:
#   bash tests/run.sh                 # every case in tests/cases/
#   bash tests/run.sh gate-plan       # only cases whose name contains "gate-plan"
#   ADW_TEST_SHELL=/bin/bash bash tests/run.sh
#                                     # run the cases under a specific shell (bash 3.2 check)
#
# Requires bash + git. No network, no gh, no engine CLIs — anything needing those is out of scope
# and listed under "not covered" below.
#
# Exit codes: 0 every case passed · 1 a case failed · 2 misuse.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILTER="${1:-}"
SHELL_UNDER_TEST="${ADW_TEST_SHELL:-bash}"

command -v git >/dev/null 2>&1 || { printf 'ERROR: git is required\n' >&2; exit 2; }
command -v "$SHELL_UNDER_TEST" >/dev/null 2>&1 \
  || { printf 'ERROR: shell not found: %s\n' "$SHELL_UNDER_TEST" >&2; exit 2; }

cases=()
while IFS= read -r f; do
  [[ -n "$FILTER" && "$f" != *"$FILTER"* ]] && continue
  cases+=("$f")
done < <(find "$HERE/cases" -name '*.sh' -type f | LC_ALL=C sort)

(( ${#cases[@]} )) || { printf 'ERROR: no cases matched %s\n' "${FILTER:-*}" >&2; exit 2; }

printf 'adw self-tests — %s (%s)\n\n' "$("$SHELL_UNDER_TEST" -c 'printf %s "$BASH_VERSION"')" "$SHELL_UNDER_TEST"

failed=()
for c in "${cases[@]}"; do
  printf '%s\n' "$(basename "$c" .sh)"
  "$SHELL_UNDER_TEST" "$c" || failed+=("$(basename "$c" .sh)")
  printf '\n'
done

# The harness makes claims about what it verifies; so must its own tests.
cat <<'NOTE'
not covered (needs a remote, gh, or a live engine CLI):
  gate.sh workspace · gate.sh ready · gate.sh committed (upstream branch)
  review.sh fan-out · engines.sh probe/run · intake.sh fetch/writeback
  install.sh: install + upgrade are covered; doctor, uninstall and hook registration are not
  static analysis: shellcheck runs in CI, not here — this suite needs only bash and git
NOTE

if (( ${#failed[@]} )); then
  printf '\nFAILED: %s\n' "${failed[*]}" >&2
  exit 1
fi
printf '\nall cases passed\n'
