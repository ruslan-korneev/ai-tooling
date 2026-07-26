---
name: slice-implement
description: The implementer playbook for an approved task — worktree, gate re-check, RED tests first, tier-by-tier GREEN implementation under mechanical guards, validation with evidence, PR, then review fan-out and the review loop. Use when running an implementation seeded by a dev-prompt, in a background task or a fresh session.
---

# slice-implement — from an approved plan to a reviewed PR

You implement one approved task. Your plan is `.tasks/<id>/PLAN.md`, your acceptance is
`.tasks/<id>/VALIDATION.md`, your commands come from `.tasks/_STACK.md`. Do not rely on prior chat context.

## 0 · Setup + gate re-check

- Branch `<id>-<slug>` in a **worktree** (always — parallel runs and a clean operator tree are worth the
  two seconds). Never work on the base branch.
- `bash scripts/ai/setup-worktree.sh` — links dependency dirs from the primary checkout, copies local-only
  config, and allocates per-worktree resources (ports, DB schema) into `.tasks/_worktree.env`. Source that
  file before running anything that binds a port. Never run a package install through a symlinked dep dir.
- Re-read `PLAN.md` + `OPEN_QUESTIONS.md`, then `bash scripts/ai/gate.sh plan <id>`. A **new blocker** (the
  plan missed something, a contradiction, a missing contract) → **STOP**: record it as a `blocker`,
  escalate, touch no code. Never guess; never push a broken PR.

## 1 · RED (see `test-author`)

Tests first, written by the test-author identity, verified by `bash scripts/ai/gate.sh red`. The suite must
fail for the intended reason. Commit the RED state. No test command configured → skip explicitly and say
so; the acceptance then rides on observation checks.

## 2 · GREEN, tier by tier

- You receive the plan, the tests, and the signatures. Implement the minimum that makes the tests pass and
  the acceptance true — no abstractions the plan does not call for.
- **You may not edit test files.** `bash scripts/ai/guard.sh builder` enforces it. A test you believe is
  wrong goes back to the test-author with the reason; you do not bend it.
- Reuse analogous existing code; match the surrounding style. Record deliberate deviations as
  `Decisions locked` in `PLAN.md` — never diverge silently.
- Small, reviewable commits; `CHECKLIST.md` current. In a worktree, scope every `git` call to it
  (`git -C <worktree> …`): the shell cwd can reset between tool calls and a commit then lands elsewhere.
- Gate per tier: `bash scripts/ai/gate.sh green`. **Cap 3 fix attempts per failing gate** — on the 4th,
  stop and escalate with the raw error output. Ping-ponging against a gate burns budget and hides a real
  design problem.
- Deep self-review after each tier: correctness, integration at **real call sites** (not just the edited
  file), performance, architectural fit. Fix findings before moving on.

## 3 · Validate + evidence

- `bash scripts/ai/gate.sh green` clean, then run **every** check in `VALIDATION.md`, saving evidence to
  `.tasks/<id>/evidence/`. Confirm with `bash scripts/ai/gate.sh evidence <id>`.
- Shared or manual resources (one staging slot, one device, a paid budget) go **through the operator**:
  say what you need, stop, wait for their go. Never seize, restart, or repoint a shared resource.
- Do not open the PR with red or unrun checks.

## 4 · Friction

Log harness friction as you hit it to `.tasks/<id>/FRICTION.md`: stale guidance, missing commands, work you
had to do by hand twice. Raw material for `harness-improver`.

## 5 · PR + review fan-out

- `gh pr create` with a summary + how-to-verify citing the evidence.
- Review goes **only** through `bash scripts/ai/review.sh <round> .tasks/<id>/VALIDATION.md --profile <p>`
  — lens reviewers in parallel, a wildcard for what they cannot see, a judge on `deep`. An ad-hoc agent
  review is not a substitute, including in a session that also did the grooming.
- In parallel, run `harness-improver` on the diff + `FRICTION.md`.

## 6 · Review loop (≤6 rounds)

`VERDICT: APPROVED` → done. `CHANGES_REQUESTED` → fix, re-validate, re-run with `<round+1>`. Not converged
after 6 → STOP and escalate. Watch for a degraded review (`DIVERSITY: DEGRADED`) and say so in your summary.

## 7 · Done

- Reconcile out-of-band changes (authored assets, dashboards, infra) into the repo or document them as
  externally owned.
- Remaining follow-ups → `OPEN_QUESTIONS.md`.
- **Merge is the operator's.** Do not merge yourself.

## Guardrails

Backend authority for money, permissions, progression, persistence; validate every client-originated
request. `.tasks/` is committed. No force-push to the base branch. No secrets in code or logs. No silent
TODO, `any`, or skipped test. Blocker → STOP.
