#!/usr/bin/env bash
# install.sh upgrade — the point of it is one distinction: a core file that is merely out of date
# versus one this project edited. Get it wrong in one direction and upgrades clobber local fixes; get
# it wrong in the other and nothing can ever be updated without a per-file argument.
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/harness.sh"

# Never touch the operator's real registry.
ADW_REGISTRY="$(tmpdir registry)/installs"; export ADW_REGISTRY

target="$(fixture target)" || exit 1
rm -rf "$target/scripts"                      # this test installs the scripts itself

installer() { local src="$1"; shift; bash "$src/install.sh" "$@"; }

# A copy of the canonical checkout we can move ahead of the target, the way a real repo does.
canon="$(tmpdir canon)"
cp -R "$ADW_ROOT"/agents "$ADW_ROOT"/bootstrap "$ADW_ROOT"/scripts "$ADW_ROOT"/skills \
      "$ADW_ROOT"/stacks "$ADW_ROOT"/templates "$ADW_ROOT"/install.sh "$canon/"

check 'install into a fresh project' 0 installer "$canon" install "$target" --tools claude --no-hooks

manifest_field() { python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get(sys.argv[2]))" \
  "$target/.ai-tooling.json" "$1"; }
hash_for() { python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['files'].get(sys.argv[2],'MISSING'))" \
  "$target/.ai-tooling.json" "$1"; }

check_out 'the manifest records the shape it was installed with' 'claude' manifest_field tools
check_empty 'and not the tool it was told to skip' \
  bash -c "python3 -c \"import json;print(json.load(open('$target/.ai-tooling.json'))['tools'])\" | grep codex || true"
canonical_hash() { python3 -c "import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())" "$1"; }
check_out 'a hash is recorded for a file it wrote' "$(canonical_hash "$ADW_ROOT/scripts/gate.sh")" \
  hash_for scripts/ai/gate.sh
check_out 'the install registers itself'          "$target"      cat "$ADW_REGISTRY"
check_out 'installs lists it'                     "$target"      installer "$canon" installs

# ── nothing moved: an upgrade is a no-op that says so ─────────────────────────
check     'upgrade with an unchanged source → 0'              0 installer "$canon" upgrade "$target"
check_out 'and reports everything as current'   '0 updated'     installer "$canon" upgrade "$target"

# ── the canonical moves ahead, and the project edits one file of its own ──────
printf '\n# the canonical moved ahead\n' >> "$canon/scripts/lib.sh"
printf '\n# a local fix nobody upstreamed\n' >> "$target/scripts/ai/guard.sh"

check_out 'dry-run: the untouched-but-stale file is an UPDATE' 'UPDATE   scripts/ai/lib.sh' \
  installer "$canon" upgrade "$target" --dry-run
check_out 'dry-run: the edited file is MODIFIED, and kept'  'MODIFIED scripts/ai/guard.sh' \
  installer "$canon" upgrade "$target" --dry-run
check_out 'dry-run writes nothing'  'nothing was written'    installer "$canon" upgrade "$target" --dry-run
check_out 'so the stale file is still stale afterwards' '' \
  bash -c "grep -c 'canonical moved ahead' '$target/scripts/ai/lib.sh' || true"

# ── apply ─────────────────────────────────────────────────────────────────────
check     'an upgrade that left files behind exits non-zero' 1 installer "$canon" upgrade "$target"
check_out 'the stale file was updated' 'canonical moved ahead' cat "$target/scripts/ai/lib.sh"
check_out 'the local fix was kept'   'a local fix nobody upstreamed' cat "$target/scripts/ai/guard.sh"
check_out 'and the version moved'  "$(grep -m1 '^VERSION=' "$canon/install.sh" | cut -d'"' -f2)" \
  manifest_field version

# The regression that matters: after an upgrade that KEPT a file, the manifest must still hold the old
# hash. Recording the local edit as ours would make the next upgrade read it as merely stale and
# overwrite it — losing the change the previous run deliberately protected.
check     'the second upgrade still calls it modified'       1 installer "$canon" upgrade "$target"
check_out 'and the local fix is still there'  'a local fix nobody upstreamed' cat "$target/scripts/ai/guard.sh"
check     'and a third'                                      1 installer "$canon" upgrade "$target"
check_out 'still there'                       'a local fix nobody upstreamed' cat "$target/scripts/ai/guard.sh"

# ── --force is the explicit way to discard a local edit ───────────────────────
check     '--force overwrites and exits 0'                   0 installer "$canon" upgrade "$target" --force
check_empty 'the local fix is gone' \
  bash -c "grep 'a local fix nobody upstreamed' '$target/scripts/ai/guard.sh' || true"
check     'and the next upgrade is a clean no-op'            0 installer "$canon" upgrade "$target"

# ── misuse ────────────────────────────────────────────────────────────────────
never="$(tmpdir never-installed)"
check     'upgrading a project that was never installed → error' 1 installer "$canon" upgrade "$never"
check_out 'and it says to install instead'  'was never installed' installer "$canon" upgrade "$never"
check     'unknown option → error'    1 installer "$canon" upgrade "$target" --regen-stack
check     'no target at all → error'  1 installer "$canon" upgrade

done_tests
