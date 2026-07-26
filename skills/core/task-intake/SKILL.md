---
name: task-intake
description: Turn an incoming request — a tracker ticket, an operator prompt, or a bug report — into a .tasks/<id>/ workspace with the goal, source reference, and intake type recorded. Use as the first step of any run. Keeps the tracker as the source of truth for what and why, and .tasks/ for how.
---

# task-intake — the adapter at the front of the loop

The loop must start the same way regardless of where work comes from. This skill normalizes the entry and
records provenance, so nothing downstream needs to know whether the task came from Linear, an issue, or a
sentence the operator typed.

## Ownership (do not duplicate state)

| Layer | Owns | Written by |
| --- | --- | --- |
| Tracker (Linear / GitHub Issues / …) | **what** and **why**, priority, status for humans | people |
| `.tasks/<id>/` | **how**: plan, questions, criteria, evidence | agents + operator |
| `_orchestration/BOARD.md` | **runtime**: what is in flight right now | orchestrator |

One fact, one home. Never mirror the ticket description into `PLAN.md` — link it.

## Intake types

Read `INTAKE` from `.tasks/_STACK.md`; the operator's explicit instruction overrides it.

### `manual`
The operator described the work in the session. Derive `<id>` as a short kebab-case slug from the goal,
and quote their request verbatim under **Source** so later sessions see the original wording, not your
paraphrase of it.

### `linear` / `github-issues`
The task exists in a tracker. `<id>` = the ticket key, lowercased (`sm-12`, `gh-431`).
- Fetch the ticket (`linear-tasks` skill, `gh issue view <n>`, or the configured adapter).
- Copy the description **into `extra_context/ticket.md`**, not into `PLAN.md`.
- Record the ticket URL and current status under **Source**.
- Set the ticket to in-progress if the operator wants the tracker to reflect the run.
- At the end, the PR links back to the ticket; the ticket is not updated by agents beyond status.

### `bug`
A defect report, not a feature. It takes the shorter path: **Report → Reproduce → Diagnose → Fix →
Verify**. A bug run must produce a **failing test that reproduces the defect** before any fix (that test
is the RED gate). No reproduction → the first task is reproducing it, and "cannot reproduce" is a valid,
reportable outcome — not a licence to change code speculatively.

## What this skill writes

`.tasks/<id>/PLAN.md` skeleton, § Overview only:

```markdown
# <id> — <title>

## Overview
- **Type:** feature | bug | tech-task | refactor | audit
- **Intake:** linear · https://linear.app/…/SM-12  (or: manual · operator prompt 2026-07-26)
- **Goal (verbatim from the source):** …
- **Profile:** _(set by workflow-triage)_
- **Status:** grooming
```

Plus `extra_context/` for any pasted asset, ticket body, screenshot, or log.

## Do not

- Don't start planning here — this skill only normalizes the entry and hands off to `workflow-triage`.
- Don't paraphrase the request in the Source field; paraphrase belongs in the crux, the original does not.
- Don't invent an id that collides with an existing `.tasks/` folder — check first.
- Don't let a bug report enter the feature path; the reproduction-first rule exists because a "fix"
  without a reproduction is a guess.
