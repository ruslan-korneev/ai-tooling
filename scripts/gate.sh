#!/usr/bin/env bash
# scripts/ai/gate.sh — machine-checkable ADW gates. Core file: never edited per project.
# Every project-specific command comes from .tasks/_STACK.md.
#
#   gate.sh format [--changed]     run the writing formatter (on-edit hook uses --changed)
#   gate.sh static                 format-check + lint + typecheck
#   gate.sh test [path]            run the suite (or one target)
#   gate.sh red [path]             RED gate: tests MUST fail (TDD step 1)
#   gate.sh green [path]           GREEN gate: static + tests must pass
#   gate.sh groom <id>             G1: no open blocker + 2 quiet passes in GROOM_LOG.md
#   gate.sh plan <id>              G2: PLAN.md + VALIDATION.md complete, acceptance mapped
#   gate.sh workspace <id>         G3: linked worktree + own branch + pushed + draft PR open
#   gate.sh committed              after every step: nothing left uncommitted
#   gate.sh evidence <id>          G5: every VALIDATION.md check has evidence
#   gate.sh all <id>               plan + green + evidence
#
# Exit 0 = gate passed. Exit 1 = gate failed. Exit 2 = misuse/misconfiguration.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$here/lib.sh"

root="$(adw_repo_root)" || adw_die "not a git repo"
cd "$root"

cmd="${1:-}"; shift || true

changed_files() { git diff --name-only --diff-filter=ACMR HEAD 2>/dev/null; }

gate_format() {
  local fmt; fmt="$(adw_cfg FORMAT_CMD)"
  [[ -n "${fmt// }" ]] || { adw_log "format: SKIPPED (FORMAT_CMD not configured)"; return 0; }
  if [[ "${1:-}" == "--changed" ]]; then
    local files; files="$(changed_files | tr '\n' ' ')"
    [[ -n "${files// }" ]] || return 0
    # Formatters that accept paths get them; the rest run repo-wide.
    bash -c "$fmt $files" >/dev/null 2>&1 || bash -c "$fmt" >/dev/null 2>&1 || true
    return 0
  fi
  adw_run_cmd format "$fmt"
}

gate_static() {
  local fail=0
  adw_run_cmd format-check "$(adw_cfg FORMAT_CHECK_CMD)" || fail=1
  adw_run_cmd lint         "$(adw_cfg LINT_CMD)"         || fail=1
  adw_run_cmd typecheck    "$(adw_cfg TYPECHECK_CMD)"    || fail=1
  return $fail
}

test_command() {
  local target="${1:-}" one all
  one="$(adw_cfg TEST_ONE_CMD)"; all="$(adw_cfg TEST_CMD)"
  if [[ -n "$target" && -n "${one// }" ]]; then
    printf '%s' "${one//<path>/$target}"
  else
    printf '%s' "$all"
  fi
}

gate_test() { adw_run_cmd test "$(test_command "${1:-}")"; }

gate_red() {
  local cmd; cmd="$(test_command "${1:-}")"
  if [[ -z "${cmd// }" ]]; then
    adw_warn "RED gate: no TEST_CMD configured — this project cannot do TDD; use observation checks in VALIDATION.md"
    return 1
  fi
  adw_log "RED gate: expecting failure from: $cmd"
  local out; out="$(bash -c "$cmd" 2>&1)"; local rc=$?
  printf '%s\n' "$out"
  if (( rc == 0 )); then
    adw_warn "RED gate FAILED: the suite passed. A test that passes before the code exists proves nothing."
    return 1
  fi
  adw_log "RED gate OK (exit $rc). Confirm the failure reason is the intended assertion, not a syntax/import error."
  return 0
}

gate_green() {
  local fail=0
  gate_static || fail=1
  gate_test "${1:-}" || fail=1
  return $fail
}

require_task() { [[ -n "${1:-}" ]] || adw_die "usage: gate.sh $cmd <task-id>"; [[ -d ".tasks/$1" ]] || adw_die "no such task workspace: .tasks/$1"; }

gate_groom() {
  local id="$1" oq=".tasks/$1/OPEN_QUESTIONS.md" log=".tasks/$1/GROOM_LOG.md" fail=0
  if [[ -f "$oq" ]] && sed -n '/^## Blockers/,/^## /p' "$oq" | grep -qE '^[0-9]+\. \*\*'; then
    adw_warn "G1 FAILED: open blocker in $oq — STOP, resolve with the operator."
    fail=1
  fi
  if [[ ! -f "$log" ]]; then
    adw_warn "G1 FAILED: $log missing — run groom-harden at least once."
    return 1
  fi
  local quiet; quiet="$(grep -cE '^\|.*\| *(quiet|QUIET) *\|' "$log" || true)"
  local last_two; last_two="$(grep -E '^\| *P[0-9]+' "$log" | tail -2)"
  if [[ "$(printf '%s\n' "$last_two" | grep -cE '\| *(quiet|QUIET) *\|' || true)" -lt 2 ]]; then
    adw_warn "G1 FAILED: need 2 consecutive quiet passes (no new blocker/major). Quiet passes so far: ${quiet:-0}"
    fail=1
  fi
  (( fail )) || adw_log "G1 OK: groom converged"
  return $fail
}

gate_plan() {
  local id="$1" plan=".tasks/$1/PLAN.md" val=".tasks/$1/VALIDATION.md" fail=0
  [[ -f "$plan" ]] || { adw_warn "G2 FAILED: $plan missing"; fail=1; }
  [[ -f "$val"  ]] || { adw_warn "G2 FAILED: $val missing"; fail=1; }
  (( fail )) && return 1
  for section in 'Touches' 'Depends-on' 'Out of scope' 'Decisions locked'; do
    grep -qiF "$section" "$plan" || { adw_warn "G2: PLAN.md missing section '$section'"; fail=1; }
  done
  local checks; checks="$(grep -cE '^\| *[0-9]+ *\|' "$val" || true)"
  if [[ "${checks:-0}" -lt 1 ]]; then
    adw_warn "G2 FAILED: VALIDATION.md has no numbered checks"; fail=1
  else
    adw_log "G2: $checks validation check(s) declared"
  fi
  grep -qiE '\bTBD\b|\bTODO\b|<[a-z-]+>' "$val" && { adw_warn "G2: VALIDATION.md still has placeholders"; fail=1; }
  (( fail )) || adw_log "G2 OK: plan + validation complete"
  return $fail
}

# G3 — the workspace itself. Checked BEFORE any source file is touched: an implementation that starts in
# the operator's checkout, on the base branch, with nothing pushed and no PR, is invisible work. Nobody
# can see it, nothing else can run in parallel, and a crash loses it.
gate_workspace() {
  local id="$1" fail=0 base branch root common main_root
  base="$(adw_cfg BASE_BRANCH main)"
  root="$(git rev-parse --show-toplevel)"
  common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  main_root="$(dirname "$common")"
  branch="$(git rev-parse --abbrev-ref HEAD)"

  if [[ "$main_root" == "$root" ]]; then
    adw_warn "G3: this is the primary checkout, not a worktree. Create one first:"
    adw_warn "     git worktree add ../$(basename "$root")-$id -b $id-<slug> && cd ../$(basename "$root")-$id && bash scripts/ai/setup-worktree.sh"
    fail=1
  else
    adw_log "G3: worktree OK ($root)"
  fi

  if [[ "$branch" == "$base" || "$branch" == "HEAD" ]]; then
    adw_warn "G3: on '$branch' — implementation never happens on the base branch."
    fail=1
  fi

  if ! git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' >/dev/null 2>&1; then
    adw_warn "G3: branch has no upstream — push it now so the work is visible: git push -u origin HEAD"
    fail=1
  elif [[ -n "$(git log '@{upstream}..HEAD' --oneline 2>/dev/null)" ]]; then
    adw_warn "G3: local commits are not pushed — push after every step, not at the end."
    fail=1
  fi

  if command -v gh >/dev/null 2>&1; then
    local pr_state
    pr_state="$(gh pr view --json isDraft,state -q '.state + " draft=" + (.isDraft|tostring)' 2>/dev/null)" || pr_state=""
    if [[ -z "$pr_state" ]]; then
      adw_warn "G3: no pull request for this branch. Open it as a DRAFT before implementing:"
      adw_warn "     gh pr create --draft --title \"$id: <title>\" --body \"WIP. Plan: .tasks/$id/PLAN.md\""
      fail=1
    else
      adw_log "G3: PR $pr_state"
    fi
  else
    adw_warn "G3: gh not installed — cannot verify the draft PR. Open one by hand or say so in the summary."
  fi

  (( fail )) || adw_log "G3 OK: work is in its own worktree, on its own branch, pushed, with a PR open"
  return $fail
}

# Run after every step. A step that is not committed does not exist: it cannot be reviewed, reverted,
# or recovered, and a long uncommitted stretch turns into one unreviewable blob.
gate_committed() {
  local dirty; dirty="$(git status --porcelain 2>/dev/null | grep -v '^?? \.tasks/_worktree.env' || true)"
  if [[ -n "${dirty// }" ]]; then
    adw_warn "uncommitted changes — commit this step before starting the next one:"
    printf '%s\n' "$dirty" | head -20 >&2
    return 1
  fi
  if ! git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' >/dev/null 2>&1; then
    adw_warn "branch has no upstream — nothing has ever been pushed: git push -u origin HEAD"
    return 1
  fi
  local unpushed
  unpushed="$(git log '@{upstream}..HEAD' --oneline 2>/dev/null || true)"
  if [[ -n "${unpushed// }" ]]; then
    adw_warn "committed but not pushed ($(printf '%s\n' "$unpushed" | wc -l | tr -d ' ') commit(s)) — push so the PR reflects reality."
    return 1
  fi
  adw_log "step committed and pushed"
  return 0
}

gate_evidence() {
  local id="$1" val=".tasks/$1/VALIDATION.md" dir=".tasks/$1/evidence"
  [[ -f "$val" ]] || adw_die "no VALIDATION.md for $id"
  local checks; checks="$(grep -cE '^\| *[0-9]+ *\|' "$val" || true)"
  local files=0; [[ -d "$dir" ]] && files="$(find "$dir" -type f | wc -l | tr -d ' ')"
  if [[ "${files:-0}" -lt "${checks:-0}" ]]; then
    adw_warn "G5 FAILED: $checks check(s) declared, $files evidence file(s) in $dir"
    return 1
  fi
  adw_log "G5 OK: $files evidence file(s) for $checks check(s)"
  return 0
}

case "$cmd" in
  format)   gate_format "${1:-}" ;;
  static)   gate_static ;;
  test)     gate_test "${1:-}" ;;
  red)      gate_red "${1:-}" ;;
  green)    gate_green "${1:-}" ;;
  groom)     require_task "${1:-}"; gate_groom "$1" ;;
  plan)      require_task "${1:-}"; gate_plan "$1" ;;
  workspace) require_task "${1:-}"; gate_workspace "$1" ;;
  committed) gate_committed ;;
  evidence)  require_task "${1:-}"; gate_evidence "$1" ;;
  all)      require_task "${1:-}"; rc=0; gate_plan "$1" || rc=1; gate_green || rc=1; gate_evidence "$1" || rc=1; exit $rc ;;
  ""|-h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' ;;
  *) adw_die "unknown gate: $cmd" ;;
esac
