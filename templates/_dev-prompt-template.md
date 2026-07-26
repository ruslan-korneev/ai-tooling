# Dev-prompt — template

Emitted by the `dev-prompt` skill once both gates exit 0 and the operator approved the plan. Fill every
`<…>` from `.tasks/<id>/PLAN.md` + `VALIDATION.md`. The result must stand alone — a fresh background
session gets no prior conversation.

```
Implement <id> (<name>). Plan: .tasks/<id>/PLAN.md. Rules: AGENTS.md. Check kit: .tasks/_STACK.md.
Profile: <light|standard|deep>.

BRANCH: <id>-<slug>   (worktree: yes)

SETUP: bash scripts/ai/setup-worktree.sh
  Links dependency dirs from the primary checkout, copies local-only config, and allocates this
  worktree's ports/schema into .tasks/_worktree.env. Source it before running anything that binds a
  port: `set -a; . .tasks/_worktree.env; set +a`. Never run a package install through a symlinked dep dir.

STEP 0 (gate): re-read PLAN.md + OPEN_QUESTIONS.md, then:
  bash scripts/ai/gate.sh plan <id>
  Any NEW blocker (the plan missed something, a contradiction, a missing contract) → STOP: write it to
  OPEN_QUESTIONS.md as a `blocker` and ask the operator. Do NOT touch code while a blocker is open.

GOAL (verifiable acceptance): <one line>.

SCOPE IN:  <from PLAN tiers/deliverables>.
SCOPE OUT: <what we do NOT touch>.

STEP 1 — RED (tests first):
  Write the failing tests for the acceptance. You may NOT touch source paths in this step:
    bash scripts/ai/guard.sh test-author --head
  Then: bash scripts/ai/gate.sh red
  The suite MUST fail, and the failure must be the intended assertion — not an import or syntax error.
  Commit the RED state. No test command configured → say so, skip RED, rely on observation checks.
  Do not fake a TDD step.

STEP 2 — GREEN (tier by tier):
  Implement the minimum that makes the tests pass and the acceptance true. You may NOT edit test files:
    bash scripts/ai/guard.sh builder --head
  A test you believe is wrong goes back with a reason — you do not bend it.
  Per tier: bash scripts/ai/gate.sh green
  CAP 3 fix attempts per failing gate; on the 4th, STOP and escalate with the raw error output.
  Deep self-review per tier: correctness, integration at REAL call sites, performance, architectural fit.
  Record deliberate deviations as "Decisions locked" in PLAN.md — never diverge silently.

STEP 3 — VALIDATE:
  Run EVERY check in .tasks/<id>/VALIDATION.md; evidence → .tasks/<id>/evidence/
  Confirm: bash scripts/ai/gate.sh evidence <id>
  SHARED/MANUAL RESOURCES (<name them: staging slot, device, paid API budget>): ask the operator, STOP
  and WAIT for their "go", then run your checks and report "done". Never seize or restart a shared
  resource yourself.

STEP 4 — PR + REVIEW (in parallel):
  1. gh pr create — summary + how-to-verify citing the evidence.
  2. bash scripts/ai/review.sh 1 .tasks/<id>/VALIDATION.md --profile <profile>
     Lens reviewers in parallel + a wildcard + (deep) a judge. Findings are posted to the PR.
  3. harness-improver on the diff + .tasks/<id>/FRICTION.md → HARNESS_PROPOSALS.md (proposals only).
  4. APPROVED → done. CHANGES_REQUESTED → fix, re-validate, re-run with round+1. MAX 6 rounds, then
     STOP and escalate. Report if the review ran with DIVERSITY: DEGRADED.

GUARDRAILS (AGENTS.md):
  - Backend authority for money / permissions / progression / persistence; validate every
    client-originated request.
  - .tasks/ is committed. No force-push to the base branch. No secrets in code or logs.
  - No silent TODO / `any` / skipped test. Keep diffs reviewable.
  - Blocker → STOP + OPEN_QUESTIONS.md; never push a broken PR.

DoD: gate.sh green · gate.sh evidence <id> · every VALIDATION.md check green with evidence · acceptance
  met · PR opened. Merge is the operator's, after APPROVED.

Keep CHECKLIST.md + OPEN_QUESTIONS.md current. Log friction in FRICTION.md.
```
