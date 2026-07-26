#!/usr/bin/env bash
# scripts/ai/lib.sh — shared helpers for the ADW gate scripts. Sourced, not run.
# Core file: identical in every project. All project-specific values come from .tasks/_STACK.md.

adw_repo_root() { git rev-parse --show-toplevel 2>/dev/null; }

# adw_cfg <KEY> [default] — read KEY from any ```ini block in .tasks/_STACK.md.
adw_cfg() {
  local key="$1" default="${2:-}" root value
  root="$(adw_repo_root)" || { printf '%s' "$default"; return 0; }
  [[ -f "$root/.tasks/_STACK.md" ]] || { printf '%s' "$default"; return 0; }
  value="$(sed -n '/^```ini/,/^```/p' "$root/.tasks/_STACK.md" \
    | grep -m1 -E "^${key}=" | sed -E "s/^${key}=//" | sed -E 's/[[:space:]]+$//')"
  [[ -n "$value" ]] || value="$default"
  printf '%s' "$value"
}

adw_log()  { printf '[adw] %s\n' "$*" >&2; }
adw_warn() { printf '[adw] WARN: %s\n' "$*" >&2; }
adw_die()  { printf '[adw] ERROR: %s\n' "$*" >&2; exit 2; }

# adw_run_cmd <label> <command-string> — run a configured command; empty => SKIPPED, exit 0.
adw_run_cmd() {
  local label="$1" cmd="$2"
  if [[ -z "${cmd// }" ]]; then
    adw_log "$label: SKIPPED (not configured in .tasks/_STACK.md)"
    return 0
  fi
  adw_log "$label: $cmd"
  bash -c "$cmd"
}
