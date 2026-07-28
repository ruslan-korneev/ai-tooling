#!/usr/bin/env bash
# ai-tooling — install a portable AI Developer Workflow (skills + agents + gates) into a project.
#
#   bash ~/.config/ai-tooling/install.sh install <target-dir> [options]
#   bash ~/.config/ai-tooling/install.sh upgrade <target-dir> [--dry-run] [--force]
#   bash ~/.config/ai-tooling/install.sh upgrade --all [--dry-run]
#   bash ~/.config/ai-tooling/install.sh installs         # every project installed from this checkout
#   bash ~/.config/ai-tooling/install.sh list
#   bash ~/.config/ai-tooling/install.sh doctor <target-dir>
#   bash ~/.config/ai-tooling/install.sh uninstall <target-dir>
#   bash ~/.config/ai-tooling/install.sh self-install     # put the /adw-install skill in ~/.claude/skills
#
# `upgrade` re-copies the core using the options the project was installed with, and knows the
# difference between a file that is merely out of date and one the project edited: the manifest records
# a hash per installed file, so an untouched copy is replaced silently and a modified one is reported
# and left alone until you pass --force.
#
# Options for `install`:
#   --stack <name>        stack profile from stacks/ (auto-detected when omitted)
#   --skills a,b,c        install only these skill ids (default: all)
#   --tools claude,codex  which tool dirs to generate (default: claude,codex)
#   --no-agents           skip .claude/agents/
#   --no-scripts          skip scripts/ai/
#   --no-hooks            do NOT register the on-edit format hook in .claude/settings.json
#   --no-rules            skip the AGENTS.md section
#   --force               overwrite generated copies that exist and differ (skills/agents/scripts)
#   --regen-stack         overwrite .tasks/_STACK.md from the profile (backs the old one up first);
#                         --force alone never touches it — it holds config only you can reproduce
#   --dry-run             print what would happen, change nothing
#
# The core (skills/agents/scripts) is identical in every project. Everything project-specific lives in
# .tasks/_STACK.md as data. If installing somewhere requires editing a core file, that is a bug.
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="2.3.1"
SCRIPT_FILES="lib.sh gate.sh guard.sh engines.sh intake.sh review.sh setup-worktree.sh worktree-alloc.sh"

REGISTRY="${ADW_REGISTRY:-$HOME/.config/ai-tooling/installs}"

die() { echo "[ai-tooling] ERROR: $*" >&2; exit 1; }
info() { echo "[ai-tooling] $*" >&2; }

# Content hash of one file. Every platform has one of these three; none of them is guaranteed, so a
# machine with no hasher degrades to "differs → ask" rather than silently overwriting.
file_hash() {
  if command -v shasum >/dev/null 2>&1;      then shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"    2>/dev/null | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1;   then openssl dgst -sha256 "$1" 2>/dev/null | awk '{print $NF}'
  else return 1; fi
}
have_hasher() { file_hash "${BASH_SOURCE[0]}" >/dev/null 2>&1; }

# Every install appends itself here so `upgrade --all` has something to iterate. One line per path,
# deduplicated; a path that no longer exists is reported and skipped, never removed behind your back.
register_install() {
  local path="$1"
  mkdir -p "$(dirname "$REGISTRY")"
  [[ -f "$REGISTRY" ]] && grep -qxF "$path" "$REGISTRY" && return 0
  printf '%s\n' "$path" >> "$REGISTRY"
}

all_skills() { ls -1 "$SRC/skills/core" 2>/dev/null; }
all_agents() { ls -1 "$SRC/agents" 2>/dev/null | sed 's/\.md$//'; }
all_stacks() { ls -1 "$SRC/stacks" 2>/dev/null | sed 's/\.stack$//'; }

cmd_list() {
  echo "ai-tooling v$VERSION — $SRC"
  echo
  echo "Skills (skills/core):"
  for s in $(all_skills); do
    desc="$(sed -n 's/^description: //p' "$SRC/skills/core/$s/SKILL.md" | head -1 | cut -c1-92)"
    printf '  %-28s %s…\n' "$s" "$desc"
  done
  echo
  echo "Agents (agents/):"
  for a in $(all_agents); do
    desc="$(sed -n 's/^description: //p' "$SRC/agents/$a.md" | head -1 | cut -c1-92)"
    printf '  %-28s %s…\n' "$a" "$desc"
  done
  echo
  echo "Gates (scripts/ai/):"
  echo "  gate.sh    format|static|test|red|green|workspace|committed|groom|plan|evidence|ready|all"
  echo "  guard.sh   builder|test-author|reviewer|planner   (phase file-scope, mechanical)"
  echo "  review.sh  <round> [validation] --profile superlight|light|standard|deep   (fan-out + judge)"
  echo "  intake.sh  fetch <ref>|writeback <ref> --status|--comment|contract"
  echo "  engines.sh candidates|probe --write|list|pick-review|diversity|run"
  echo "  setup-worktree.sh · worktree-alloc.sh"
  echo
  echo "Stack profiles: $(all_stacks | tr '\n' ' ')"
  echo
  echo "Bootstrap: install.sh self-install → /adw-install skill (interactive setup inside a repo)"
}

detect_stack() {
  local t="$1"
  [[ -f "$t/default.project.json" || -f "$t/wally.toml" ]] && { echo roblox; return; }
  [[ -f "$t/go.mod" ]] && { echo go; return; }
  # SwiftPM and Xcode need different commands; a Package.swift alongside an .xcodeproj means SwiftPM drives.
  [[ -f "$t/Package.swift" ]] && { echo swift; return; }
  compgen -G "$t/*.xcworkspace" >/dev/null 2>&1 && { echo swift-xcode; return; }
  compgen -G "$t/*.xcodeproj"  >/dev/null 2>&1 && { echo swift-xcode; return; }
  if [[ -f "$t/pyproject.toml" || -f "$t/requirements.txt" || -f "$t/setup.py" ]]; then
    # uv.lock means every tool must run through `uv run` to hit the locked environment
    [[ -f "$t/uv.lock" ]] && { echo python-uv; return; }
    echo python; return
  fi
  [[ -f "$t/package.json" ]] && { echo node-ts; return; }
  echo generic
}

copy_file() {
  local src="$1" dest="$2"
  if [[ -f "$dest" ]] && ! cmp -s "$src" "$dest" && [[ "$FORCE" != 1 ]]; then
    info "SKIP (differs, use --force): ${dest#$TARGET/}"; return 0
  fi
  [[ "$DRY_RUN" == 1 ]] && { info "would write: ${dest#$TARGET/}"; return 0; }
  mkdir -p "$(dirname "$dest")"; cp "$src" "$dest"
  # Recorded so a later `upgrade` can tell "out of date" from "the project edited this".
  WROTE_FILES+=("${dest#$TARGET/}")
}

# The manifest is what `upgrade` reads: the options this project was installed with, plus a hash of
# every file we wrote. Without the hashes an upgrade cannot tell a stale copy from an edited one, and
# has to choose between clobbering the project's changes and refusing to move at all.
write_manifest() {
  local skills_csv; skills_csv="$(printf '%s,' "$@" | sed 's/,$//')"
  # Hashes carried over from an upgrade that deliberately did NOT write a file come first; a fresh hash
  # of a file we wrote overrides them.
  local hashes="${KEEP_HASHES:-}" f h
  if have_hasher; then
    for f in ${WROTE_FILES[@]+"${WROTE_FILES[@]}"}; do
      h="$(file_hash "$TARGET/$f")" || continue
      hashes="$hashes$f	$h
"
    done
  fi
  ADW_VERSION="$VERSION" ADW_SRC="$SRC" ADW_STACK="$STACK" ADW_TOOLS="$TOOLS" \
  ADW_HOOKS="$([[ $WITH_HOOKS == 1 ]] && echo true || echo false)" \
  ADW_AGENTS="$([[ $WITH_AGENTS == 1 ]] && echo true || echo false)" \
  ADW_SCRIPTS="$([[ $WITH_SCRIPTS == 1 ]] && echo true || echo false)" \
  ADW_RULES="$([[ $WITH_RULES == 1 ]] && echo true || echo false)" \
  ADW_SKILLS="$skills_csv" ADW_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)" ADW_HASHES="$hashes" \
  python3 - "$TARGET/.ai-tooling.json" <<'PY'
import json, os, sys
files = {}
for line in os.environ.get("ADW_HASHES", "").splitlines():
    if "\t" in line:
        path, h = line.split("\t", 1)
        files[path] = h
doc = {
    "version": os.environ["ADW_VERSION"],
    "source": os.environ["ADW_SRC"],
    "stack": os.environ["ADW_STACK"],
    "tools": os.environ["ADW_TOOLS"],
    "hooks": os.environ["ADW_HOOKS"] == "true",
    "agents": os.environ["ADW_AGENTS"] == "true",
    "scripts": os.environ["ADW_SCRIPTS"] == "true",
    "rules": os.environ["ADW_RULES"] == "true",
    "installedAt": os.environ["ADW_AT"],
    "skills": [s for s in os.environ["ADW_SKILLS"].split(",") if s],
    "files": files,
}
with open(sys.argv[1], "w") as fh:
    json.dump(doc, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY
}

manifest_get() { # <target> <key> — one scalar, or a csv for a list. Empty when absent.
  python3 - "$1/.ai-tooling.json" "$2" <<'PY' 2>/dev/null
import json, sys
try:
    doc = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
v = doc.get(sys.argv[2], "")
print(",".join(v) if isinstance(v, list) else ("true" if v is True else "false" if v is False else v))
PY
}

seed_file() {
  local src="$1" dest="$2"
  [[ -f "$dest" ]] && { info "keep existing: ${dest#$TARGET/}"; return 0; }
  [[ "$DRY_RUN" == 1 ]] && { info "would seed: ${dest#$TARGET/}"; return 0; }
  mkdir -p "$(dirname "$dest")"; cp "$src" "$dest"
}

render_stack_md() {
  local profile="$SRC/stacks/$STACK.stack" out="$TARGET/.tasks/_STACK.md"
  [[ -f "$profile" ]] || die "unknown stack '$STACK' (have: $(all_stacks | tr '\n' ' '))"
  # NOT covered by --force: this file is the project's own configuration — commands, engines, intake,
  # shared resources. Regenerating it silently discards work that only the operator can reproduce.
  if [[ -f "$out" && "$REGEN_STACK" != 1 ]]; then
    info "keep existing: .tasks/_STACK.md (project-owned; --regen-stack to overwrite)"; return 0
  fi
  if [[ -f "$out" && "$REGEN_STACK" == 1 ]]; then
    local backup="$out.bak-$(date -u +%Y%m%dT%H%M%SZ)"
    [[ "$DRY_RUN" == 1 ]] || cp "$out" "$backup"
    info "backed up existing config → ${backup#$TARGET/}"
  fi
  local body; body="$(cat "$SRC/templates/_STACK.md.tmpl")"
  while IFS='=' read -r key value; do
    [[ -z "$key" || "$key" == \#* ]] && continue
    body="${body//\{\{$key\}\}/$value}"
  done < "$profile"
  body="$(printf '%s' "$body" | sed -E 's/\{\{[A-Z_]+\}\}//g')"
  [[ "$DRY_RUN" == 1 ]] && { info "would render: .tasks/_STACK.md (stack=$STACK)"; return 0; }
  mkdir -p "$TARGET/.tasks"; printf '%s\n' "$body" > "$out"
}

install_rules() {
  local snippet="$SRC/templates/AGENTS.snippet.md" agents_md="$TARGET/AGENTS.md"
  [[ "$DRY_RUN" == 1 ]] && { info "would update: AGENTS.md (ai-tooling block)"; return 0; }
  if [[ -f "$agents_md" ]] && grep -q 'ai-tooling:begin' "$agents_md"; then
    awk '/<!-- ai-tooling:begin -->/{skip=1} !skip{print} /<!-- ai-tooling:end -->/{skip=0}' \
      "$agents_md" > "$agents_md.tmp" && mv "$agents_md.tmp" "$agents_md"
  fi
  [[ -f "$agents_md" ]] || printf '# AGENTS.md\n\nRules for coding agents in this repository.\n\n' > "$agents_md"
  printf '\n' >> "$agents_md"; cat "$snippet" >> "$agents_md"
  info "updated: AGENTS.md (ai-tooling block)"
}

# Merge our hook into .claude/settings.json without disturbing the user's other settings.
# Measure what the formatter would do to files it has never touched. Turning a hook on over an
# unformatted codebase makes the first edit rewrite whole files, burying the actual change.
format_churn_ratio() { # prints a percentage, or nothing when it cannot tell
  local fmt="$1" sample tmp total=0 changed=0 f
  command -v git >/dev/null 2>&1 || return 0
  sample="$(cd "$TARGET" && git ls-files | grep -E '\.(swift|py|ts|tsx|js|jsx|go|rs|rb|kt|java|lua|luau|sh)$' | head -3)"
  [[ -n "${sample// }" ]] || return 0
  tmp="$(mktemp -d)"
  while IFS= read -r f; do
    [[ -f "$TARGET/$f" ]] || continue
    mkdir -p "$tmp/$(dirname "$f")"; cp "$TARGET/$f" "$tmp/$f"
  done <<< "$sample"
  ( cd "$tmp" && bash -c "$fmt" >/dev/null 2>&1 ) || { rm -rf "$tmp"; return 0; }
  while IFS= read -r f; do
    [[ -f "$tmp/$f" ]] || continue
    local lines diff_lines
    lines="$(wc -l < "$TARGET/$f" | tr -d ' ')"
    diff_lines="$(diff "$TARGET/$f" "$tmp/$f" 2>/dev/null | grep -cE '^[<>]' || true)"
    total=$(( total + lines )); changed=$(( changed + diff_lines / 2 ))
  done <<< "$sample"
  rm -rf "$tmp"
  (( total > 0 )) && printf '%d' $(( changed * 100 / total ))
}

install_hooks() {
  local settings="$TARGET/.claude/settings.json" hook_src="$SRC/templates/settings.hooks.json"
  [[ "$DRY_RUN" == 1 ]] && { info "would register on-edit format hook in .claude/settings.json"; return 0; }

  local fmt; fmt="$(sed -n '/^```ini/,/^```/p' "$TARGET/.tasks/_STACK.md" 2>/dev/null \
                    | grep -m1 -E '^FORMAT_CMD=' | sed -E 's/^FORMAT_CMD=//; s/[[:space:]]+#[[:space:]].*$//; s/[[:space:]]+$//')"
  if [[ -z "${fmt// }" ]]; then
    info "hook NOT registered: FORMAT_CMD is empty — an on-edit hook that formats nothing is pure overhead."
    info "  Fill FORMAT_CMD in .tasks/_STACK.md and re-run install to enable it."
    return 0
  fi

  local churn; churn="$(format_churn_ratio "$fmt")"
  if [[ -n "$churn" ]] && (( churn > 25 )); then
    info "hook NOT registered: the formatter rewrites ~${churn}% of lines in files it has never touched."
    info "  Enabling it now would make the first edit to any file a full-file rewrite that buries the real change."
    info "  Format the repository once in its own commit, then re-run install."
    return 0
  fi
  [[ -n "$churn" ]] && info "formatter churn on untouched files: ~${churn}% — safe to hook"

  command -v python3 >/dev/null 2>&1 || { info "python3 not found — skipping hook registration (add it by hand from templates/settings.hooks.json)"; return 0; }
  command -v python3 >/dev/null 2>&1 || { info "python3 not found — skipping hook registration (add it by hand from templates/settings.hooks.json)"; return 0; }
  mkdir -p "$(dirname "$settings")"
  python3 - "$settings" "$hook_src" <<'PY'
import json, sys, os
settings_path, hook_path = sys.argv[1], sys.argv[2]
settings = {}
if os.path.exists(settings_path):
    try:
        with open(settings_path) as f:
            settings = json.load(f)
    except json.JSONDecodeError:
        print("[ai-tooling] WARN: .claude/settings.json is not valid JSON — leaving it alone", file=sys.stderr)
        raise SystemExit(0)
with open(hook_path) as f:
    ours = json.load(f)["hooks"]
hooks = settings.setdefault("hooks", {})
changed = False
for event, entries in ours.items():
    bucket = hooks.setdefault(event, [])
    for entry in entries:
        cmds = [h.get("command", "") for grp in bucket for h in grp.get("hooks", [])]
        if any("scripts/ai/gate.sh" in c for c in cmds):
            continue
        bucket.append(entry); changed = True
if changed:
    with open(settings_path, "w") as f:
        json.dump(settings, f, indent=2); f.write("\n")
    print("[ai-tooling] registered on-edit format hook in .claude/settings.json", file=sys.stderr)
else:
    print("[ai-tooling] hook already registered", file=sys.stderr)
PY
}

remove_hooks() {
  local settings="$TARGET/.claude/settings.json"
  [[ -f "$settings" ]] || return 0
  command -v python3 >/dev/null 2>&1 || return 0
  python3 - "$settings" <<'PY'
import json, sys
p = sys.argv[1]
try:
    with open(p) as f: s = json.load(f)
except Exception: raise SystemExit(0)
hooks = s.get("hooks", {})
for event in list(hooks):
    kept = []
    for grp in hooks[event]:
        grp["hooks"] = [h for h in grp.get("hooks", []) if "scripts/ai/" not in h.get("command", "")]
        if grp["hooks"]: kept.append(grp)
    if kept: hooks[event] = kept
    else: del hooks[event]
if not hooks: s.pop("hooks", None)
with open(p, "w") as f: json.dump(s, f, indent=2); f.write("\n")
print("[ai-tooling] removed ADW hooks from .claude/settings.json", file=sys.stderr)
PY
}

cmd_install() {
  TARGET="${1:-}"; shift || true
  [[ -n "$TARGET" ]] || die "usage: install <target-dir> [options]"
  TARGET="$(cd "$TARGET" 2>/dev/null && pwd)" || die "no such directory"

  STACK=""; SKILLS=""; TOOLS="claude,codex"
  WITH_AGENTS=1; WITH_SCRIPTS=1; WITH_RULES=1; WITH_HOOKS=1; FORCE=0; DRY_RUN=0; REGEN_STACK=0
  WROTE_FILES=(); KEEP_HASHES=""

  while (( $# )); do
    case "$1" in
      --stack) STACK="${2:-}"; shift 2 ;;
      --skills) SKILLS="${2:-}"; shift 2 ;;
      --tools) TOOLS="${2:-}"; shift 2 ;;
      --no-agents) WITH_AGENTS=0; shift ;;
      --no-scripts) WITH_SCRIPTS=0; shift ;;
      --no-hooks) WITH_HOOKS=0; shift ;;
      --no-rules) WITH_RULES=0; shift ;;
      --force) FORCE=1; shift ;;
      --regen-stack) REGEN_STACK=1; shift ;;
      --dry-run) DRY_RUN=1; shift ;;
      *) die "unknown option: $1" ;;
    esac
  done

  [[ -n "$STACK" ]] || { STACK="$(detect_stack "$TARGET")"; info "detected stack: $STACK"; }
  [[ -n "$SKILLS" ]] || SKILLS="$(all_skills | tr '\n' ',' | sed 's/,$//')"

  info "target: $TARGET"
  [[ "$DRY_RUN" == 1 ]] && info "DRY RUN — nothing will be written"

  local installed=()
  IFS=',' read -ra skill_list <<< "$SKILLS"
  IFS=',' read -ra tool_list <<< "$TOOLS"
  for id in "${skill_list[@]}"; do
    id="$(echo "$id" | tr -d ' ')"
    [[ -d "$SRC/skills/core/$id" ]] || die "unknown skill: $id"
    for tool in "${tool_list[@]}"; do
      case "$tool" in
        claude) dest_root="$TARGET/.claude/skills/$id" ;;
        codex)  dest_root="$TARGET/.codex/skills/$id" ;;
        *) die "unknown tool: $tool (claude|codex)" ;;
      esac
      while IFS= read -r rel; do copy_file "$SRC/skills/core/$id/$rel" "$dest_root/$rel"; done \
        < <(cd "$SRC/skills/core/$id" && find . -type f | sed 's|^\./||')
    done
    installed+=("$id")
  done
  info "skills installed: ${#installed[@]} → ${TOOLS}"

  if (( WITH_AGENTS )); then
    for a in $(all_agents); do copy_file "$SRC/agents/$a.md" "$TARGET/.claude/agents/$a.md"; done
    info "agents installed: $(all_agents | wc -l | tr -d ' ')"
  fi

  if (( WITH_SCRIPTS )); then
    for f in $SCRIPT_FILES; do
      copy_file "$SRC/scripts/$f" "$TARGET/scripts/ai/$f"
      [[ "$DRY_RUN" == 1 ]] || chmod +x "$TARGET/scripts/ai/$f" 2>/dev/null || true
    done
    info "gates installed: scripts/ai/"
  fi

  render_stack_md
  copy_file "$SRC/templates/_dev-prompt-template.md" "$TARGET/.tasks/_dev-prompt-template.md"
  copy_file "$SRC/templates/GROOM_LOG.md" "$TARGET/.tasks/_templates/GROOM_LOG.md"
  seed_file "$SRC/templates/PROPOSALS.md" "$TARGET/.tasks/_harness/PROPOSALS.md"
  seed_file "$SRC/templates/BOARD.md" "$TARGET/.tasks/_orchestration/BOARD.md"

  (( WITH_RULES )) && install_rules
  (( WITH_HOOKS )) && install_hooks

  if [[ "$DRY_RUN" != 1 ]]; then
    write_manifest "${installed[@]}"
    register_install "$TARGET"
  fi

  # Files the installer writes can be silently swallowed by a global gitignore: the .codex copies get
  # committed, the .claude ones do not, and nobody notices until a fresh clone behaves differently.
  local ignored=() p
  for p in .claude .codex scripts/ai .tasks AGENTS.md; do
    [[ -e "$TARGET/$p" ]] || continue
    ( cd "$TARGET" && git check-ignore -q "$p" 2>/dev/null ) && ignored+=("$p")
  done
  if (( ${#ignored[@]} )); then
    info ""
    info "IGNORED BY GIT — these paths were written but git will not see them:"
    for p in "${ignored[@]}"; do info "    $p   ($(cd "$TARGET" && git check-ignore -v "$p" 2>/dev/null | cut -d: -f1-2))"; done
    info "  Decide deliberately: commit the harness with 'git add -f <path>', or leave it untracked and"
    info "  know that a fresh clone of this repo has no harness. Half-tracked is the bad outcome."
  fi

  local cands; cands="$(cd "$TARGET" && bash scripts/ai/engines.sh candidates 2>/dev/null | tr '\n' ' ')"
  cat >&2 <<EOF

[ai-tooling] done. engine CLIs on PATH: ${cands:-none} (installed ≠ usable)
  next:
    1. fill in .tasks/_STACK.md (check kit, canon, shared resources)
    2. confirm which engines actually work:  bash scripts/ai/engines.sh probe --write
    3. verify the gates:  cd $TARGET && bash scripts/ai/gate.sh static
       exit 3 = DEGRADED: nothing is configured yet, so the gate verified nothing. Go back to 1.
    4. run a task:        /adw-run <what you want built>
EOF
}

# Classify one destination file against the new canonical and against what we last wrote there.
#   current   — already identical to canonical, nothing to do
#   stale     — differs from canonical, matches the hash we recorded → the project never touched it
#   modified  — differs from both → somebody edited it here; that edit is theirs to keep or discard
#   unknown   — no recorded hash (older manifest, or a file install skipped) → treated as modified
classify_file() {
  local src="$1" dest="$2" recorded="$3"
  [[ -f "$dest" ]] || { printf 'missing'; return; }
  cmp -s "$src" "$dest" && { printf 'current'; return; }
  [[ -n "$recorded" ]] || { printf 'unknown'; return; }
  local now; now="$(file_hash "$dest")" || { printf 'unknown'; return; }
  [[ "$now" == "$recorded" ]] && printf 'stale' || printf 'modified'
}

cmd_upgrade() {
  local first="${1:-}"; [[ -n "$first" ]] || die "usage: upgrade <target-dir> [--dry-run] [--force]  |  upgrade --all"
  if [[ "$first" == "--all" ]]; then shift; cmd_upgrade_all "$@"; return $?; fi

  TARGET="$(cd "$first" 2>/dev/null && pwd)" || die "no such directory: $first"
  shift
  FORCE=0; DRY_RUN=0; REGEN_STACK=0; WROTE_FILES=(); KEEP_HASHES=""
  while (( $# )); do
    case "$1" in
      --force)   FORCE=1; shift ;;
      --dry-run) DRY_RUN=1; shift ;;
      *) die "unknown option: $1 (upgrade takes --dry-run and --force)" ;;
    esac
  done

  [[ -f "$TARGET/.ai-tooling.json" ]] \
    || die "no .ai-tooling.json in $TARGET — this project was never installed from here. Use: install $TARGET"

  local from; from="$(manifest_get "$TARGET" version)"
  info "upgrade: $TARGET"
  info "  ${from:-unknown} → $VERSION   (source: $SRC)"
  [[ "$from" == "$VERSION" ]] && info "  already at $VERSION — re-copying anyway, in case the checkout moved ahead of its own version"
  have_hasher || info "  WARN: no shasum/sha256sum/openssl here. Cannot tell a stale copy from an edited one;"
  have_hasher || info "        every differing file will be reported as modified and left alone."

  # The shape of the install is the project's decision, made at install time. An upgrade re-applies the
  # same shape; changing it (adding codex, dropping hooks) is a re-install, deliberately.
  STACK="$(manifest_get "$TARGET" stack)";  [[ -n "$STACK" ]]  || STACK="$(detect_stack "$TARGET")"
  TOOLS="$(manifest_get "$TARGET" tools)";  [[ -n "$TOOLS" ]]  || TOOLS="claude,codex"
  SKILLS="$(manifest_get "$TARGET" skills)"
  [[ -n "$SKILLS" ]] || SKILLS="$(all_skills | tr '\n' ',' | sed 's/,$//')"
  WITH_HOOKS=1;   [[ "$(manifest_get "$TARGET" hooks)"   == "false" ]] && WITH_HOOKS=0
  WITH_AGENTS=1;  [[ "$(manifest_get "$TARGET" agents)"  == "false" ]] && WITH_AGENTS=0
  WITH_SCRIPTS=1; [[ "$(manifest_get "$TARGET" scripts)" == "false" ]] && WITH_SCRIPTS=0
  WITH_RULES=1;   [[ "$(manifest_get "$TARGET" rules)"   == "false" ]] && WITH_RULES=0

  local recorded; recorded="$(python3 - "$TARGET/.ai-tooling.json" <<'PY' 2>/dev/null
import json, sys
try:
    doc = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
for path, h in (doc.get("files") or {}).items():
    print("%s\t%s" % (path, h))
PY
)"
  hash_of() { printf '%s\n' "$recorded" | awk -F'\t' -v p="$1" '$1==p {print $2; exit}'; }

  # Build the canonical list: source path <tab> destination path, exactly as install would write it.
  local plan="" id tool a f rel
  IFS=',' read -ra _skills <<< "$SKILLS"
  IFS=',' read -ra _tools  <<< "$TOOLS"
  for id in "${_skills[@]}"; do
    id="$(printf '%s' "$id" | tr -d ' ')"
    [[ -d "$SRC/skills/core/$id" ]] || { info "  GONE  skill '$id' no longer exists in the source — left in place"; continue; }
    for tool in "${_tools[@]}"; do
      case "$tool" in claude) rel=".claude/skills/$id" ;; codex) rel=".codex/skills/$id" ;; *) continue ;; esac
      while IFS= read -r f; do plan="$plan$SRC/skills/core/$id/$f	$rel/$f
"; done < <(cd "$SRC/skills/core/$id" && find . -type f | sed 's|^\./||')
    done
  done
  (( WITH_AGENTS ))  && for a in $(all_agents); do plan="$plan$SRC/agents/$a.md	.claude/agents/$a.md
"; done
  (( WITH_SCRIPTS )) && for f in $SCRIPT_FILES; do plan="$plan$SRC/scripts/$f	scripts/ai/$f
"; done
  plan="$plan$SRC/templates/_dev-prompt-template.md	.tasks/_dev-prompt-template.md
$SRC/templates/GROOM_LOG.md	.tasks/_templates/GROOM_LOG.md
"

  local n_current=0 n_stale=0 n_modified=0 n_missing=0 modified_list="" verdict src dest
  while IFS='	' read -r src dest; do
    [[ -n "$dest" ]] || continue
    verdict="$(classify_file "$src" "$TARGET/$dest" "$(hash_of "$dest")")"
    case "$verdict" in
      current)  n_current=$(( n_current + 1 )); WROTE_FILES+=("$dest") ;;
      missing)  n_missing=$(( n_missing + 1 ))
                [[ "$DRY_RUN" == 1 ]] && info "  ADD      $dest" || { mkdir -p "$TARGET/$(dirname "$dest")"; cp "$src" "$TARGET/$dest"; WROTE_FILES+=("$dest"); } ;;
      stale)    n_stale=$(( n_stale + 1 ))
                [[ "$DRY_RUN" == 1 ]] && info "  UPDATE   $dest" || { cp "$src" "$TARGET/$dest"; WROTE_FILES+=("$dest"); } ;;
      *)        n_modified=$(( n_modified + 1 )); modified_list="$modified_list  $dest
"
                if (( FORCE )) && [[ "$DRY_RUN" != 1 ]]; then
                  cp "$src" "$TARGET/$dest"; WROTE_FILES+=("$dest")
                else
                  # Carry the OLD hash forward. Re-hashing a file we chose not to write would record the
                  # local edit as ours, and the next upgrade would read it as merely stale and clobber
                  # it — losing exactly the edit this branch exists to protect.
                  KEEP_HASHES="$KEEP_HASHES$dest	$(hash_of "$dest")
"
                fi
                if [[ "$DRY_RUN" == 1 ]]; then
                  info "  MODIFIED $dest   $( (( FORCE )) && echo '(--force would overwrite)' || echo '(kept)')"
                fi ;;
    esac
  done <<< "$plan"

  [[ "$DRY_RUN" != 1 && "$WITH_SCRIPTS" == 1 ]] && chmod +x "$TARGET"/scripts/ai/*.sh 2>/dev/null
  info "  $n_current current · $n_stale updated · $n_missing added · $n_modified modified here"
  if (( n_modified )); then
    if (( FORCE )); then
      info "  --force: the local edits above were overwritten."
    else
      info "  Kept as they are — an edited core file is either a local fix worth upstreaming or drift"
      info "  worth discarding, and only you know which:"
      printf '%s' "$modified_list" >&2
      info "  Overwrite them with: install.sh upgrade $TARGET --force"
    fi
  fi

  if [[ "$DRY_RUN" == 1 ]]; then info "  DRY RUN — nothing was written"; return 0; fi

  # .tasks/_STACK.md is never regenerated: it is the project's own configuration.
  (( WITH_RULES )) && install_rules
  (( WITH_HOOKS )) && install_hooks

  IFS=',' read -ra _installed <<< "$SKILLS"
  write_manifest "${_installed[@]}"
  register_install "$TARGET"
  info "  manifest updated → .ai-tooling.json (version $VERSION)"
  # Files left behind means the upgrade is not fully applied; --force leaves nothing behind.
  (( n_modified )) && (( ! FORCE )) && return 1
  return 0
}

cmd_upgrade_all() {
  local args=("$@")
  [[ -f "$REGISTRY" ]] || die "no installs recorded yet ($REGISTRY). Install somewhere first, or upgrade one path by name."
  local path rc=0 seen=0
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    seen=$(( seen + 1 ))
    if [[ ! -f "$path/.ai-tooling.json" ]]; then
      info "SKIP $path — gone, moved, or uninstalled (still listed in $REGISTRY)"; continue
    fi
    echo >&2
    cmd_upgrade "$path" ${args[@]+"${args[@]}"} || rc=1
  done < "$REGISTRY"
  echo >&2
  info "upgrade --all: $seen path(s) in the registry"
  (( rc )) && info "at least one project has locally modified core files — see above"
  return $rc
}

cmd_installs() {
  [[ -f "$REGISTRY" ]] || { echo "no installs recorded ($REGISTRY)"; return 0; }
  echo "ai-tooling installs — canonical $VERSION at $SRC"
  local path v
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    if [[ ! -f "$path/.ai-tooling.json" ]]; then printf '  %-52s %s\n' "$path" "GONE"; continue; fi
    v="$(manifest_get "$path" version)"
    printf '  %-52s %s%s\n' "$path" "${v:-unknown}" \
      "$([[ "$v" == "$VERSION" ]] && echo "" || echo "   ← differs from canonical")"
  done < "$REGISTRY"
}

cmd_doctor() {
  local target="${1:-}"; [[ -n "$target" ]] || die "usage: doctor <target-dir>"
  target="$(cd "$target" && pwd)"
  echo "ai-tooling doctor — $target"
  if [[ -f "$target/.ai-tooling.json" ]]; then
    local iv; iv="$(manifest_get "$target" version)"
    echo "  installed: ${iv:-unknown}   canonical: $VERSION   ($SRC)"
    if [[ -n "$iv" && "$iv" != "$VERSION" ]]; then
      echo "  BEHIND — bring it forward with: install.sh upgrade $target"
    fi
    echo "  stack: $(manifest_get "$target" stack)   tools: $(manifest_get "$target" tools)   hooks: $(manifest_get "$target" hooks)"
    echo "  installed at: $(manifest_get "$target" installedAt)"
  else
    echo "  (never installed here)"
  fi
  echo
  local drift=0
  for id in $(all_skills); do
    for dest in "$target/.claude/skills/$id/SKILL.md" "$target/.codex/skills/$id/SKILL.md"; do
      [[ -f "$dest" ]] || continue
      cmp -s "$SRC/skills/core/$id/SKILL.md" "$dest" || { echo "  DRIFT  ${dest#$target/}"; drift=1; }
    done
  done
  for a in $(all_agents); do
    local dest="$target/.claude/agents/$a.md"
    [[ -f "$dest" ]] || continue
    cmp -s "$SRC/agents/$a.md" "$dest" || { echo "  DRIFT  ${dest#$target/}"; drift=1; }
  done
  for f in $SCRIPT_FILES; do
    local dest="$target/scripts/ai/$f"
    [[ -f "$dest" ]] || { echo "  MISSING  scripts/ai/$f"; drift=1; continue; }
    cmp -s "$SRC/scripts/$f" "$dest" || { echo "  DRIFT  scripts/ai/$f"; drift=1; }
  done
  (( drift )) || echo "  core: clean — matches canonical"
  echo
  local stack="$target/.tasks/_STACK.md"
  if [[ -f "$stack" ]]; then
    # An empty value with a stated reason is a decision; without one it is an omission. Report them apart.
    local k v note undecided=0
    for k in LINT_CMD TYPECHECK_CMD FORMAT_CMD FORMAT_CHECK_CMD TEST_CMD; do
      local line; line="$(sed -n '/^```ini/,/^```/p' "$stack" | grep -m1 -E "^$k=")" || continue
      v="$(printf '%s' "$line" | sed -E "s/^$k=//; s/[[:space:]]+#[[:space:]].*$//; s/[[:space:]]+$//")"
      note="$(printf '%s' "$line" | grep -oE '#[[:space:]].*$' | sed -E 's/^#[[:space:]]*//')"
      [[ -n "$v" ]] && continue
      if [[ -n "$note" ]]; then
        echo "  $k: not set — $note"
      else
        echo "  WARN: $k unset with no reason. Either fill it in, or record why: '$k=   # none: <reason>'"
        undecided=$((undecided+1))
      fi
    done
    (( undecided )) && echo "  ($undecided command(s) unexplained — an unexplained gap is indistinguishable from a forgotten one)"
  else
    echo "  WARN: no .tasks/_STACK.md — gates cannot run"
  fi
  if [[ -f "$target/.claude/settings.json" ]] && grep -q 'scripts/ai/' "$target/.claude/settings.json" 2>/dev/null; then
    echo "  hooks: registered"
  else
    echo "  hooks: not registered (re-install without --no-hooks to enable on-edit formatting)"
  fi
  local cands usable
  cands="$(cd "$target" 2>/dev/null && bash scripts/ai/engines.sh candidates 2>/dev/null | tr '\n' ' ')"
  usable="$(cd "$target" 2>/dev/null && bash scripts/ai/engines.sh list 2>/dev/null | tr '\n' ' ')"
  echo "  engine CLIs on PATH: ${cands:-none}"
  echo "  declared in _STACK:  ${usable:-none}   (declared, not re-verified here — 'engines.sh probe' checks)"
  if [[ -f "$stack" ]] && ! grep -qE '^ENGINES=.+' "$stack"; then
    echo "  WARN: ENGINES unset — only the implement engine is assumed usable. Verify with: bash scripts/ai/engines.sh probe --write"
  fi
  [[ "$(cd "$target" 2>/dev/null && bash scripts/ai/engines.sh diversity 2>/dev/null)" == "DEGRADED" ]] \
    && echo "  NOTE: single usable engine → reviews are labelled DIVERSITY: DEGRADED (not independent)"
  true
}

# The bootstrap skill has to exist BEFORE a project has the harness, so it lives at user level.
cmd_self_install() {
  local dest="$HOME/.claude/skills/adw-install"
  mkdir -p "$dest"
  cp "$SRC/bootstrap/adw-install/SKILL.md" "$dest/SKILL.md"
  echo "[ai-tooling] installed /adw-install → $dest/SKILL.md"
  echo "[ai-tooling] run it inside any repository to set the harness up there, interactively."
}

cmd_uninstall() {
  TARGET="${1:-}"; [[ -n "$TARGET" ]] || die "usage: uninstall <target-dir>"
  TARGET="$(cd "$TARGET" && pwd)"
  echo "Removing generated copies from $TARGET (task artifacts in .tasks/<id>/ are kept):"
  for id in $(all_skills); do rm -rf "$TARGET/.claude/skills/$id" "$TARGET/.codex/skills/$id"; done
  for a in $(all_agents); do rm -f "$TARGET/.claude/agents/$a.md"; done
  for f in $SCRIPT_FILES; do rm -f "$TARGET/scripts/ai/$f"; done
  rm -f "$TARGET/.ai-tooling.json"
  remove_hooks
  if [[ -f "$TARGET/AGENTS.md" ]] && grep -q 'ai-tooling:begin' "$TARGET/AGENTS.md"; then
    awk '/<!-- ai-tooling:begin -->/{skip=1} !skip{print} /<!-- ai-tooling:end -->/{skip=0}' \
      "$TARGET/AGENTS.md" > "$TARGET/AGENTS.md.tmp" && mv "$TARGET/AGENTS.md.tmp" "$TARGET/AGENTS.md"
  fi
  echo "done. Kept: .tasks/ (workspaces + _STACK.md), AGENTS.md minus the ai-tooling block."
}

case "${1:-}" in
  install)      shift; cmd_install "$@" ;;
  upgrade)      shift; cmd_upgrade "$@" ;;
  installs)     cmd_installs ;;
  self-install) cmd_self_install ;;
  list|"")   cmd_list ;;
  doctor)    shift; cmd_doctor "$@" ;;
  uninstall) shift; cmd_uninstall "$@" ;;
  -h|--help) sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' ;;
  *) die "unknown command: $1 (install|upgrade|installs|self-install|list|doctor|uninstall)" ;;
esac
