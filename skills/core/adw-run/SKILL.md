---
name: adw-run
description: Drive the full AI Developer Workflow for one task end to end — intake, triage, scout, plan, groom passes, worktree, RED/GREEN implementation, validation, review fan-out — pausing only at the human gates (plan approval and final review). Use when the operator says "run the workflow", "прогони воркфлоу", "take this task through the loop", or hands over a ticket id and expects the whole loop.
---

# adw-run — the orchestrator of one task through the loop

You drive the whole loop for a single task. You do not write production code yourself: you run phases,
enforce gates mechanically, and spawn specialist agents whose identities are defined by what they may not
touch. Everything project-specific comes from `.tasks/_STACK.md`; never hardcode a command.

## Human gates (only two — protect them)

- **G2 · plan approval.** After the plan and validation criteria exist and grooming converged, present a
  compact summary and **stop for the operator**. This is the highest-leverage review point: a bad plan
  line becomes hundreds of bad code lines.
- **G7 · merge.** After the review fan-out, present the ranked findings and **stop**. Merging is theirs.

Everywhere else you proceed autonomously — **except** on a `blocker`, which always stops the run.

## Phases

### 0 · Intake + triage
1. `task-intake` — turn the request (ticket / prompt / bug report) into `.tasks/<id>/` with the goal and a
   back-reference to its source.
2. `workflow-triage` — pick the profile (`light` / `standard` / `deep`) and record it in `PLAN.md`.
   Never ask the operator for the profile; state your choice and its reason in one line.

### 1 · Scout (agent: `context-scout`)
Read-only recon → provenance index. It burns its own context on grep/read/trace and returns conclusions,
so your context stays clean and the plan is not anchored on the first file anyone opened.

### 2 · Plan (`task-plan` + `slice-verify`)
`PLAN.md` (incl. `Touches` / `Depends-on` / scope OUT / decisions locked) and `VALIDATION.md` (every
acceptance line → ≥1 runnable check, with where evidence lands). Uncertainties → `OPEN_QUESTIONS.md`.

### 3 · Groom passes (`groom-harden`, agent: `groom-hardener`)
Loop until dry, one **fresh-context** pass per lens from `LENSES` in `_STACK.md`. Each pass reads
`GROOM_LOG.md` first and appends its row. Stop when the last two passes are `quiet`.
Check mechanically: `bash scripts/ai/gate.sh groom <id>`.

### 4 · G2 — stop for the operator
Present: goal, scope IN/OUT, the 3–5 decisions locked, open `clarify` assumptions, the check list, the
profile, and the estimated tier count. Wait. Fold their corrections back into the artifacts.

### 5 · Workspace — before any code
Worktree, branch, empty start commit, push, **draft PR** — in that order, before a single source file is
touched. Then `bash scripts/ai/gate.sh workspace <id>` must exit 0.

```bash
git worktree add ../<repo>-<id> -b <id>-<slug> && cd ../<repo>-<id>
bash scripts/ai/setup-worktree.sh
git commit --allow-empty -m "<type>(<scope>): start <id>" && git push -u origin HEAD
gh pr create --draft --title "<id>: <title>" --body "WIP. Plan: .tasks/<id>/PLAN.md"
```

Doing this at the end instead makes the whole run invisible: the operator cannot watch the diff grow, a
crash loses everything unpushed, and parallel slices collide in one checkout.

### 6 · RED (agent: `test-author`)
Tests first, written by an agent that may not touch source (`guard.sh test-author`). Gate:
`bash scripts/ai/gate.sh red` — the suite **must** fail, and the failure must be the intended assertion,
not an import error. No test command configured → say so plainly, skip RED, and rely on observation
checks; do not pretend TDD happened.

### 7 · GREEN (agent: `builder`)
Builder receives the plan, the tests, and the signatures — not the grooming history. It may not touch test
paths (`guard.sh builder`). Gate: `bash scripts/ai/gate.sh green`. **Cap 3 fix attempts per failing gate**;
on the 4th, stop and escalate with the raw error output rather than looping.

**Commit and push after every step**, then `bash scripts/ai/gate.sh committed`. The draft PR is the live
view of the run — an uncommitted step is invisible to the operator and lost if the run dies.

### 8 · Validate (agent: `validator`)
Run every `VALIDATION.md` check, save evidence to `.tasks/<id>/evidence/`.
Gate: `bash scripts/ai/gate.sh evidence <id>`. Do not open a PR with red or unrun checks.

### 9 · Review fan-out
Fill in the PR summary + how-to-verify, `gh pr ready` (it has been a draft since step 5), then
`bash scripts/ai/review.sh <round> .tasks/<id>/VALIDATION.md --profile <profile>` —
lens reviewers in parallel, plus a wildcard hunting what those lenses cannot see, plus (on `deep`) a judge
that dedupes and adversarially verifies. In parallel, run `harness-improver` on the diff + `FRICTION.md`.

### 10 · G7 — stop for the operator
Present the ranked, verified findings and the diversity label. `CHANGES_REQUESTED` → fix, re-validate,
re-run the round (**max 6**). Merge is the operator's.

## Rules

- **A `blocker` stops the run.** Write it to `OPEN_QUESTIONS.md`, surface it, wait. Never guess past it.
- **Gates are scripts, not opinions.** Never declare a phase done without the gate's exit code.
- **Log friction as you go** to `.tasks/<id>/FRICTION.md` — it feeds the harness-improver.
- Keep `CHECKLIST.md` current; it is how a fresh session resumes this run after compaction.
- Report degradation honestly: a skipped RED gate, a `DIVERSITY: DEGRADED` review, an unreproducible
  check — say it in the summary rather than letting a green-looking run hide it.
- Before the first review of a project, check `bash scripts/ai/engines.sh list`. If it warns that `ENGINES`
  is unset, run `probe --write` once — reviews routed to an unauthenticated CLI return nothing, and
  nothing looks like approval.
