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

# Two different strippings, because the two rules need different things.
#
# Comments only, for bash-4 expansions: `"${have,,}"` lives INSIDE double quotes almost every time it
# appears, so stripping quoted strings would blind the check to exactly what it is looking for. Verified
# by putting `${have,,}` back in gate.sh and watching a quote-stripping version report nothing.
code_lines() { sed -E 's/#.*$//' "$@"; }
# Comments and quoted strings, for tool names: naming a binary in a warning ("no shasum/sha256sum here")
# is not a use of it. Blind spot, accepted: a real call hidden in a quoted command string is invisible.
code_lines_bare() { sed -E 's/"[^"]*"//g; s/#.*$//' "$@"; }

# Constructs that need bash 4+. The portable replacements: `lower`/`upper` in lib.sh for case folding,
# and `while IFS= read -r l; do a+=("$l"); done < <(cmd)` for mapfile.
bash4_free() {
  local hits
  hits="$(code_lines "$ADW_ROOT"/scripts/*.sh "$ADW_ROOT"/install.sh \
          | grep -nE 'mapfile|readarray|declare -A|\$\{[A-Za-z_][A-Za-z0-9_]*(,,|\^\^)')" || return 0
  printf '%s\n' "$hits"
  return 1
}
check 'core scripts avoid bash-4-only constructs' 0 bash4_free

# The replacements themselves, exercised under the oldest shell rather than trusted.
folds_under_32() {
  /bin/bash -c 'source "$1"/scripts/lib.sh
    [[ "$(lower ABC-12)" == "abc-12" ]] || { echo "lower failed: $(lower ABC-12)"; exit 1; }
    [[ "$(upper status)" == "STATUS" ]] || { echo "upper failed: $(upper status)"; exit 1; }
    a=(); while IFS= read -r l; do a+=("$l"); done < <(printf "x\ny\n")
    [[ "${#a[@]}" == 2 && "${a[1]}" == "y" ]] || { echo "array read failed"; exit 1; }' _ "$ADW_ROOT"
}
if [[ -x /bin/bash ]]; then
  check 'lower/upper and the mapfile replacement work under /bin/bash' 0 folds_under_32
fi

# Bash 3.2 aborts on "${arr[@]}" and "${arr[*]}" when the array is EMPTY and set -u is on — not a
# warning, `unbound variable` and exit 127. Bash 4.4 made it legal, so this is invisible on Linux CI and
# on any machine with Homebrew bash, and the lines themselves look perfectly portable. Grep alone would
# have missed the class, which is why the runtime assertion below exists as well.
#
# The rule is blanket: every [@] expansion carries the `${arr[@]+"${arr[@]}"}` guard, every [*] carries
# `-`. Whether a particular array can really be empty is a judgement no static check can make, and one
# guard costs nothing.
guarded_arrays() {
  local hits
  # The guarded form CONTAINS the bare one — ${a[@]+"${a[@]}"} — so strip the whole guarded construct
  # first and flag whatever bare expansion is left over.
  hits="$(code_lines "$ADW_ROOT"/scripts/*.sh "$ADW_ROOT"/install.sh \
          | sed -E 's/\$\{[A-Za-z_][A-Za-z0-9_]*\[@\]\+"\$\{[A-Za-z_][A-Za-z0-9_]*\[@\]\}"\}//g' \
          | grep -nE '"\$\{[A-Za-z_][A-Za-z0-9_]*\[[@*]\]\}"')" || return 0
  printf '%s\n' "$hits"
  return 1
}
check 'array expansions are guarded for the empty case' 0 guarded_arrays

empty_arrays_under_32() {
  /bin/bash -c 'set -uo pipefail
    a=()
    for e in ${a[@]+"${a[@]}"}; do :; done
    printf "%s" "${a[*]-}" >/dev/null
    (( ${#a[@]} )) && exit 1
    b=(x y)
    for e in ${b[@]+"${b[@]}"}; do :; done
    [[ "$e" == y ]] || exit 1'
}
if [[ -x /bin/bash ]]; then
  check 'the guarded forms survive an empty array under /bin/bash' 0 empty_arrays_under_32
fi

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
  hits="$(code_lines_bare "$ADW_ROOT"/scripts/*.sh "$ADW_ROOT"/install.sh \
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
