<!-- ai-tooling:begin -->
## AI Developer Workflow (installed from ~/.config/ai-tooling)

Skills live in `.claude/skills/` and `.codex/skills/`; subagents in `.claude/agents/`; gates in
`scripts/ai/`. These are **generated copies of a project-independent core** — edit the canonical source in
`~/.config/ai-tooling/` and re-install, or the next install overwrites your change.

Everything project-specific is **data in `.tasks/_STACK.md`**: check-kit commands, base branch, test/src
paths, engines, per-worktree resources, grooming and review lenses, canon location, intake source. If
something here needs a core file edited to fit this project, that is a bug in the harness, not in the
project.

### The loop

`task-intake` → `workflow-triage` → `context-scout` → `task-plan` + `slice-verify` → `groom-harden` ×N →
**G2 operator approval** → worktree → `test-author` (RED) → `builder` (GREEN) → validate → review fan-out
→ **G7 operator merge** → `harness-improver`. `adw-run` drives all of it; `orchestrate` runs several tasks
in parallel; `handoff` compacts a session.

### Gates are commands, not opinions

```bash
bash scripts/ai/gate.sh plan <id>       # plan + validation complete, acceptance mapped
bash scripts/ai/gate.sh groom <id>      # every required lens closed clean, no open blocker
bash scripts/ai/gate.sh workspace <id>  # own worktree + own branch + pushed + draft PR, BEFORE any code
bash scripts/ai/gate.sh committed       # after every step: nothing uncommitted, nothing unpushed
bash scripts/ai/gate.sh red [path]      # tests must FAIL before implementation exists
bash scripts/ai/gate.sh green           # static + tests pass
bash scripts/ai/gate.sh evidence <id>   # every validation check has evidence
bash scripts/ai/gate.sh ready <id>      # PR out of draft + body states what was NOT verified
bash scripts/ai/guard.sh builder        # the implementer may not edit tests
bash scripts/ai/review.sh <round> .tasks/<id>/VALIDATION.md --profile deep
```

**Implementation starts by creating the workspace, not by writing code**: worktree → branch → **commit
`.tasks/<id>/` as the first commit** → push → **draft PR** → move the ticket to in-progress →
`gate.sh workspace`. Then commit and push **after every step**. Work that is uncommitted or unpushed is
invisible to the operator, unreviewable in pieces, and lost if the run dies; a plan that never lands in
git leaves a diff nobody can judge.

Never declare a phase done without the gate's exit code. An on-edit hook runs the formatter after every
`Edit`/`Write`; instructions are advisory, hooks are not.

### Tools are declared, not discovered

This project's external tools — tracker, engines, check kit — are whatever `.tasks/_STACK.md` names, and
nothing else. A CLI installed on the machine, a tool used in another repo, or a skill you know how to
drive is **not** evidence that it belongs here. An unset value means "not configured" and the fallback is
to ask, never to go looking. Side effects in someone else's workspace do not fail loudly; they succeed in
the wrong place.

### Task workflow

- `.tasks/<id>/` holds `PLAN.md` (always), plus `VALIDATION.md`, `OPEN_QUESTIONS.md`, `CHECKLIST.md`,
  `GROOM_LOG.md`, `evidence/`, `FRICTION.md` as the work warrants. `.tasks/` is **committed** — it is the
  provenance record and how a fresh session resumes after compaction.
- A `blocker` in `OPEN_QUESTIONS.md` is a **STOP** signal: surface it and pause. Never guess past it.
- Profile (`light`/`standard`/`deep`) is chosen from blast radius by `workflow-triage`, not from diff size.

### Agent identities are defined by what they may not touch

`planner` writes only `.tasks/` · `test-author` may not touch source · `builder` may not touch tests ·
reviewers and the judge are read-only. `guard.sh` enforces this on the diff.

### Production bar

- Make ownership, runtime boundary, and source of truth explicit before implementing a system.
- Document contracts before implementation: source of truth, payload shape, writers, readers, validation,
  versioning, forbidden writes.
- Backend authority for money, permissions, progression, persistence. Client code is presentation, input,
  and requests — validate every client-originated request.
- Small modules, narrow public APIs. No API before a real consumer. No duplicated shared types or helpers
  (search first); no trivial one-line wrappers either.
- No backward-compat shims or fallback logic unless migration support was explicitly requested.
- Methods returning live mutable internal state are named unsafe; plain getters are read-only or snapshots.
- Tests where risk justifies it: pure rules, money, permissions, migrations, input validation, state machines.
- Never present a dummy, placeholder, or partial implementation as finished. Say what is done, what is not,
  and what remains.

### Review discipline

- Review after every tier: bugs, correctness, integration at **real call sites**, performance.
- Findings caused by the current change → fix before continuing. Findings outside scope → record them and
  tell the operator; do not silently fix.
- After an ownership or contract change, grep the old owners and verify the previous source of truth no
  longer writes competing state.
<!-- ai-tooling:end -->
