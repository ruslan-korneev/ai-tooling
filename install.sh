#!/usr/bin/env bash
# ai-tooling — install a portable AI Developer Workflow (skills + agents + gates) into a project.
#
#   bash ~/.config/ai-tooling/install.sh install <target-dir> [options]
#   bash ~/.config/ai-tooling/install.sh list
#   bash ~/.config/ai-tooling/install.sh doctor <target-dir>
#   bash ~/.config/ai-tooling/install.sh uninstall <target-dir>
#
# Options for `install`:
#   --stack <name>        stack profile from stacks/ (auto-detected when omitted)
#   --skills a,b,c        install only these skill ids (default: all)
#   --tools claude,codex  which tool dirs to generate (default: claude,codex)
#   --no-agents           skip .claude/agents/
#   --no-scripts          skip scripts/ai/
#   --no-hooks            do NOT register the on-edit format hook in .claude/settings.json
#   --no-rules            skip the AGENTS.md section
#   --force               overwrite files that exist and differ (incl. locally edited copies)
#   --dry-run             print what would happen, change nothing
#
# The core (skills/agents/scripts) is identical in every project. Everything project-specific lives in
# .tasks/_STACK.md as data. If installing somewhere requires editing a core file, that is a bug.
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="2.0.0"
SCRIPT_FILES="lib.sh gate.sh guard.sh engines.sh intake.sh review.sh setup-worktree.sh worktree-alloc.sh"

die() { echo "[ai-tooling] ERROR: $*" >&2; exit 1; }
info() { echo "[ai-tooling] $*" >&2; }

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
  echo "  gate.sh    format|static|test|red|green|groom|plan|evidence|all"
  echo "  guard.sh   builder|test-author|reviewer|planner   (phase file-scope, mechanical)"
  echo "  review.sh  <round> [validation] --profile light|standard|deep   (lens fan-out + judge)"
  echo "  intake.sh  fetch <ref>|writeback <ref> --status|--comment|contract"
  echo "  engines.sh candidates|probe --write|list|pick-review|diversity|run"
  echo "  setup-worktree.sh · worktree-alloc.sh"
  echo
  echo "Stack profiles: $(all_stacks | tr '\n' ' ')"
}

detect_stack() {
  local t="$1"
  [[ -f "$t/default.project.json" || -f "$t/wally.toml" ]] && { echo roblox; return; }
  [[ -f "$t/go.mod" ]] && { echo go; return; }
  [[ -f "$t/pyproject.toml" || -f "$t/requirements.txt" || -f "$t/setup.py" ]] && { echo python; return; }
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
  if [[ -f "$out" && "$FORCE" != 1 ]]; then
    info "keep existing: .tasks/_STACK.md (project-owned; --force to regenerate)"; return 0
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
install_hooks() {
  local settings="$TARGET/.claude/settings.json" hook_src="$SRC/templates/settings.hooks.json"
  [[ "$DRY_RUN" == 1 ]] && { info "would register on-edit format hook in .claude/settings.json"; return 0; }
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
  WITH_AGENTS=1; WITH_SCRIPTS=1; WITH_RULES=1; WITH_HOOKS=1; FORCE=0; DRY_RUN=0

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
  seed_file "$SRC/templates/_dev-prompt-template.md" "$TARGET/.tasks/_dev-prompt-template.md"
  seed_file "$SRC/templates/GROOM_LOG.md" "$TARGET/.tasks/_templates/GROOM_LOG.md"
  seed_file "$SRC/templates/PROPOSALS.md" "$TARGET/.tasks/_harness/PROPOSALS.md"
  seed_file "$SRC/templates/BOARD.md" "$TARGET/.tasks/_orchestration/BOARD.md"

  (( WITH_RULES )) && install_rules
  (( WITH_HOOKS )) && install_hooks

  if [[ "$DRY_RUN" != 1 ]]; then
    printf '{\n  "version": "%s",\n  "source": "%s",\n  "stack": "%s",\n  "tools": "%s",\n  "hooks": %s,\n  "installedAt": "%s",\n  "skills": [%s]\n}\n' \
      "$VERSION" "$SRC" "$STACK" "$TOOLS" "$([[ $WITH_HOOKS == 1 ]] && echo true || echo false)" \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(printf '"%s",' "${installed[@]}" | sed 's/,$//')" \
      > "$TARGET/.ai-tooling.json"
  fi

  local cands; cands="$(cd "$TARGET" && bash scripts/ai/engines.sh candidates 2>/dev/null | tr '\n' ' ')"
  cat >&2 <<EOF

[ai-tooling] done. engine CLIs on PATH: ${cands:-none} (installed ≠ usable)
  next:
    1. fill in .tasks/_STACK.md (check kit, canon, shared resources)
    2. confirm which engines actually work:  bash scripts/ai/engines.sh probe --write
    3. verify the gates:  cd $TARGET && bash scripts/ai/gate.sh static
    4. run a task:        /adw-run <what you want built>
EOF
}

cmd_doctor() {
  local target="${1:-}"; [[ -n "$target" ]] || die "usage: doctor <target-dir>"
  target="$(cd "$target" && pwd)"
  echo "ai-tooling doctor — $target"
  [[ -f "$target/.ai-tooling.json" ]] && cat "$target/.ai-tooling.json" || echo "  (never installed here)"
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
    local empty; empty="$(sed -n '/^```ini/,/^```/p' "$stack" | grep -cE '^(LINT|TYPECHECK|TEST|FORMAT)_[A-Z_]*=$' || true)"
    [[ "${empty:-0}" -gt 0 ]] && echo "  WARN: $empty check-kit command(s) unset in .tasks/_STACK.md — those gates will report SKIPPED"
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
  echo "  declared usable:     ${usable:-none}"
  if [[ -f "$stack" ]] && ! grep -qE '^ENGINES=.+' "$stack"; then
    echo "  WARN: ENGINES unset — only the implement engine is assumed usable. Verify with: bash scripts/ai/engines.sh probe --write"
  fi
  [[ "$(cd "$target" 2>/dev/null && bash scripts/ai/engines.sh diversity 2>/dev/null)" == "DEGRADED" ]] \
    && echo "  NOTE: single usable engine → reviews are labelled DIVERSITY: DEGRADED (not independent)"
  true
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
  install)   shift; cmd_install "$@" ;;
  list|"")   cmd_list ;;
  doctor)    shift; cmd_doctor "$@" ;;
  uninstall) shift; cmd_uninstall "$@" ;;
  -h|--help) sed -n '2,24p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' ;;
  *) die "unknown command: $1 (install|list|doctor|uninstall)" ;;
esac
