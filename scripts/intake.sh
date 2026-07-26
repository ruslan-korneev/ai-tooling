#!/usr/bin/env bash
# scripts/ai/intake.sh — normalize an incoming task from any tracker. Core file.
#
#   intake.sh fetch <ref>                     → normalized JSON on stdout + ticket body on disk
#   intake.sh writeback <ref> --status <s>    → move the ticket (only if INTAKE_WRITEBACK=true)
#   intake.sh writeback <ref> --comment <txt> → post one comment (only if INTAKE_WRITEBACK=true)
#   intake.sh contract                        → print the five fields the core needs
#
# The core knows a CONTRACT, never a tracker. Whatever the project already uses — an in-house CLI, `gh`,
# `jira`, curl against an API — is configured as a command template in .tasks/_STACK.md:
#
#   INTAKE_CMD=<your-cli> issue show <ref> --json
#
# Nothing here infers a tracker. An unset INTAKE_CMD means manual intake, not "look for a CLI you know".
#
# `<ref>` is substituted with the ticket key. If the command emits JSON, this script maps the usual
# field names itself. If it emits something else, it exits 4 and hands the raw output to the agent,
# which normalizes it using the skill named in INTAKE_SKILL. No MCP required, no adapter to write.
#
# Exit codes: 0 normalized · 3 manual intake (agent asks the operator) · 4 raw output needs the agent ·
#             2 misconfiguration/failure.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$here/lib.sh"

root="$(adw_repo_root)" || adw_die "not a git repo"
cd "$root"

print_contract() {
  cat <<'EOF'
The core needs exactly five fields from any tracker:

  id      stable key → .tasks/<id>/   (required; lowercased, e.g. sm-12, gh-431)
  title   one line                    (required)
  body    description, markdown       (required, may be empty)
  url     backlink for PR + provenance(optional)
  status  the human-facing state      (optional)

Anything else — epics, sprints, points, custom fields — is not the core's business.
EOF
}

# The mapper must receive the tracker output on stdin, so the program itself cannot come from stdin
# (a `python3 - <<EOF` heredoc would eat it and the mapper would silently see an empty document).
read -r -d '' NORMALIZE_PY <<'PY'
import json, sys

raw = sys.stdin.read()
try:
    d = json.loads(raw)
except Exception:
    sys.stderr.write("[adw] intake: output is not JSON\n"); sys.exit(4)

if isinstance(d, list):
    if len(d) != 1:
        sys.stderr.write("[adw] intake: command returned %d items, expected one issue\n" % len(d))
        sys.exit(4)
    d = d[0]
if not isinstance(d, dict):
    sys.stderr.write("[adw] intake: unexpected JSON shape\n"); sys.exit(4)

def pick(*names):
    for n in names:
        if n in d and d[n] not in (None, ""):
            return d[n]
    return None

def flatten(v):
    # trackers nest these: {"state": {"name": "In Progress"}}
    if isinstance(v, dict):
        for k in ("name", "title", "value", "identifier"):
            if k in v:
                return v[k]
        return None
    return v

ident = pick("identifier", "key", "number", "id")
title = pick("title", "name", "summary")
body  = pick("description", "body", "content") or ""
url   = pick("url", "permalink", "html_url", "webUrl")
state = flatten(pick("state", "status", "workflowState", "column"))

missing = [n for n, v in (("id", ident), ("title", title)) if v in (None, "")]
if missing:
    sys.stderr.write("[adw] intake: could not map required field(s): %s\n" % ", ".join(missing))
    sys.exit(4)

print(json.dumps({
    "id": str(ident).lower(),
    "title": str(title),
    "body": str(body),
    "url": url or "",
    "status": state or "",
}, ensure_ascii=False, indent=2))
PY

read -r -d '' TICKET_PY <<'PY'
import json, sys, pathlib
d = json.load(sys.stdin)
pathlib.Path(sys.argv[1]).write_text(
    "# %s — %s\n\n%s\n\n---\nsource: %s\nstatus at intake: %s\n"
    % (d["id"], d["title"], d["body"] or "_(no description)_", d["url"] or "n/a", d["status"] or "n/a")
)
PY

normalize_json() { python3 -c "$NORMALIZE_PY"; }  # stdin: raw output → stdout: contract JSON, or exit 4

fetch() {
  local ref="${1:-}"
  [[ -n "$ref" ]] || adw_die "usage: intake.sh fetch <ref>"

  local mode cmd skill
  mode="$(adw_cfg INTAKE manual)"
  cmd="$(adw_cfg INTAKE_CMD)"
  skill="$(adw_cfg INTAKE_SKILL)"

  if [[ "$mode" == "manual" || -z "${cmd// }" ]]; then
    adw_log "INTAKE=$mode with no INTAKE_CMD → manual intake."
    print_contract >&2
    adw_log "Ask the operator for the ticket text and normalize it yourself. Quote their wording verbatim."
    exit 3
  fi

  local resolved="${cmd//<ref>/$ref}"
  adw_log "intake: $resolved"
  local out rc
  out="$(bash -c "$resolved" 2>&1)"; rc=$?
  if (( rc != 0 )) || [[ -z "${out// }" ]]; then
    adw_warn "intake command failed (exit $rc):"
    printf '%s\n' "$out" | head -20 >&2
    adw_warn "Fix INTAKE_CMD in .tasks/_STACK.md, or fall back to manual intake — do not invent the ticket."
    exit 2
  fi

  local normalized
  if normalized="$(printf '%s' "$out" | normalize_json 2>/dev/null)"; then
    local id; id="$(printf '%s' "$normalized" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
    mkdir -p ".tasks/$id/extra_context"
    printf '%s' "$normalized" | python3 -c "$TICKET_PY" ".tasks/$id/extra_context/ticket.md"
    adw_log "ticket body → .tasks/$id/extra_context/ticket.md (do NOT copy it into PLAN.md — link it)"
    printf '%s\n' "$normalized"
    return 0
  fi

  adw_warn "could not map the output to the contract automatically."
  [[ -n "${skill// }" ]] && adw_warn "load the '$skill' skill and normalize the raw output below yourself."
  print_contract >&2
  printf '%s\n' "$out"
  exit 4
}

writeback() {
  local ref="${1:-}"; shift || true
  [[ -n "$ref" ]] || adw_die "usage: intake.sh writeback <ref> --status <s> | --comment <text>"
  [[ "$(adw_cfg INTAKE_WRITEBACK false)" == "true" ]] || {
    adw_log "INTAKE_WRITEBACK is not true → skipping tracker write (read-only intake)."; return 0; }

  local kind="" value=""
  case "${1:-}" in
    --status)  kind=status;  value="${2:-}" ;;
    --comment) kind=comment; value="${2:-}" ;;
    *) adw_die "expected --status or --comment" ;;
  esac
  [[ -n "$value" ]] || adw_die "empty $kind"

  local tmpl
  case "$kind" in
    status)  tmpl="$(adw_cfg INTAKE_STATUS_CMD)" ;;
    comment) tmpl="$(adw_cfg INTAKE_COMMENT_CMD)" ;;
  esac
  [[ -n "${tmpl// }" ]] || { adw_warn "no INTAKE_${kind^^}_CMD configured → skipping"; return 0; }

  local resolved="${tmpl//<ref>/$ref}"
  resolved="${resolved//<value>/$value}"
  adw_log "writeback ($kind): $resolved"
  bash -c "$resolved" || adw_warn "writeback failed — the run continues; the tracker is not the source of truth for engineering state."
}

case "${1:-}" in
  fetch)     shift; fetch "$@" ;;
  writeback) shift; writeback "$@" ;;
  contract)  print_contract ;;
  *) adw_die "usage: intake.sh fetch <ref> | writeback <ref> --status|--comment <v> | contract" ;;
esac
