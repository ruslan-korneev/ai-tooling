#!/usr/bin/env bash
# Portability — the core scripts run on whatever the operator's machine ships. macOS ships bash 3.2 as
# /bin/bash, and `#!/usr/bin/env bash` finds a newer one only if Homebrew put it on PATH. A bash-4-only
# expansion there is not a style issue: `${var,,}` aborts the shell with "bad substitution", and
# `mapfile` is simply not a command, so the gate dies mid-run instead of returning a verdict.
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/harness.sh"

# Every core script must at least parse under the oldest bash we support.
parses_under() {
  local sh="$1" f rc=0
  for f in "$ADW_ROOT"/scripts/*.sh "$ADW_ROOT"/install.sh; do
    "$sh" -n "$f" || { printf 'parse error: %s\n' "$f"; rc=1; }
  done
  return $rc
}
if [[ -x /bin/bash ]]; then
  check 'every core script parses under /bin/bash' 0 parses_under /bin/bash
fi

# Constructs that need bash 4+. Known offenders as of this commit:
#   scripts/gate.sh:290    ${have,,} / ${want,,}   — ticket-state comparison in G3
#   scripts/intake.sh:293  ${kind^^}               — building the INTAKE_<KIND>_CMD name
#   scripts/review.sh:76-77 mapfile                — reading the engine list
bash4_free() {
  local hits
  hits="$(grep -nE 'mapfile|readarray|declare -A|\$\{[A-Za-z_][A-Za-z0-9_]*(,,|\^\^)' \
          "$ADW_ROOT"/scripts/*.sh "$ADW_ROOT"/install.sh)" || return 0
  printf '%s\n' "$hits"
  return 1
}
check_xfail 'core scripts avoid bash-4-only constructs' 0 bash4_free

# GNU-only tools are the other half of the same problem: absent from a stock macOS, so a script that
# reaches for one works on CI and dies on the operator's laptop. `timeout` is not in this list on
# purpose — engines.sh implements its own `with_timeout` rather than shelling out to coreutils.
# Comments and double-quoted strings are stripped first, so naming a tool in a warning ("no
# shasum/sha256sum/openssl here") is not a use of it. A line that tests for the tool with `command -v`
# before calling it is the documented way to reach for one anyway — it degrades with a message instead
# of dying — so those lines are compliant too.
# Blind spot, accepted: a genuine call hidden inside a double-quoted command string is invisible here.
gnu_free() {
  local hits
  hits="$(sed -E 's/"[^"]*"//g; s/#.*$//' "$ADW_ROOT"/scripts/*.sh "$ADW_ROOT"/install.sh \
          | grep -nE '(^|[^[:alnum:]_-])(realpath|sha256sum|tac|readlink -f|date -d|stat -c|grep -P|xargs -r)([^[:alnum:]_-]|$)' \
          | grep -v 'command -v')" || return 0
  printf '%s\n' "$hits"
  return 1
}
check 'core scripts avoid GNU-only tools' 0 gnu_free

# BSD sed requires an argument to -i, so `sed -i.bak` is portable and bare `sed -i` is not.
# `sed -E` is portable; `sed -r` is GNU-only.
sed_portable() {
  local hits
  hits="$(grep -nE "sed( -[a-zA-Z]+)* -(i([[:space:]]|$)|r)" \
          "$ADW_ROOT"/scripts/*.sh "$ADW_ROOT"/install.sh)" || return 0
  printf '%s\n' "$hits"
  return 1
}
check 'core scripts use sed portably (-i needs a suffix, -E not -r)' 0 sed_portable

done_tests
