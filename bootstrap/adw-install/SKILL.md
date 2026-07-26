---
name: adw-install
description: Install or update the AI Developer Workflow harness in the current repository — run the installer, work out this project's real check commands, intake adapter and engines, verify the gates actually run, and optionally open a PR adding it. Use when the user says "install ai-tooling here", "set up the harness", "поставь харнесс", or wants to refresh an existing install.
---

# adw-install — bring the harness into this repository

`~/.config/ai-tooling/install.sh` copies the core. Everything it cannot know — what this project's
commands really are, where tasks come from, which engines work, what must never be seized — is your job.
A harness installed with wrong commands is worse than none: every gate reports `SKIPPED` and the loop
looks green while checking nothing.

**Detect first, ask second.** Every question you ask that the repository could have answered is a question
the operator has to think about for no reason. Aim for three or four questions total.

## 1 · Install the core

```bash
bash ~/.config/ai-tooling/install.sh install . 
```

Already installed → run `doctor` first and report drift before touching anything; then re-install with
`--force` to refresh generated copies. `--force` never touches `.tasks/_STACK.md` — that file holds the
project's own configuration.

## 2 · Work out the real check kit

Do not trust the stack profile's defaults. Find what this project actually runs, in this order:

1. `Makefile` targets (`make test`, `make lint`) — often the real entry point, wrapping the rest.
2. `package.json` scripts · `pyproject.toml` `[tool.*]` · `noxfile.py` / `tox.ini` · `justfile`.
3. The CI workflow (`.github/workflows/*`, `.gitlab-ci.yml`) — CI is the definition of "green" the team
   already agreed on; match it rather than inventing a parallel one.
4. A dependency manager that must wrap every command: `uv run …`, `poetry run …`, `pdm run …`,
   `bundle exec …`, `pnpm …`. Getting this wrong is the most common cause of a dead gate.

Then **run each one** and put only working commands into `.tasks/_STACK.md`. A command that errors goes in
empty with a note, not in broken — an empty value reports `SKIPPED (not configured)`, which is honest.

Also fill from the repo, without asking:
- `BASE_BRANCH` — `git symbolic-ref refs/remotes/origin/HEAD`, or the branch the repo actually uses.
- `TEST_PATHS` / `SRC_PATHS` — from the real layout; the builder/test-author guards depend on them.
- `DEP_DIRS` / `LOCAL_ONLY_FILES` — heavy gitignored dirs and local-only config, for worktree setup.

## 3 · Intake adapter

Detect, then confirm in one line:
- a tracker CLI config in the repo (e.g. a `.<tool>.toml` binding) → that tool, with its own skill named
  in `INTAKE_SKILL`;
- otherwise a GitHub remote + `gh` → `gh issue view <ref> --json number,title,body,url,state`;
- otherwise `manual`.

Never assume a tracker because it is installed on the machine or used in another repository. If nothing is
configured, `manual` is the correct answer, not a guess.

If a tracker is configured, also set `INTAKE_STATES_CMD` so tickets move by intent rather than by a
hardcoded state name, and verify with `bash scripts/ai/intake.sh states <any-ref>`.

`INTAKE_WRITEBACK` — ask. It writes to a shared workspace, so it is the operator's decision, and the
default is off.

## 4 · Engines

```bash
bash scripts/ai/engines.sh probe --write
```

Installed is not usable: an unauthenticated CLI fails silently mid-review and a missing lens looks exactly
like a clean one. Report what answered. Single vendor → suggest pinning two models
(`ENGINES=claude:opus,claude:sonnet`) so reviews are `CROSS-MODEL` rather than `DEGRADED`.

## 5 · Ask what cannot be detected

Keep it to what actually changes behaviour:

1. **Shared or manual resources** — one staging slot, one device, a paid API budget, a single test
   merchant. These go in `_STACK.md`; an implementer must ask for them instead of seizing them. Nothing
   detects this, and getting it wrong means an agent takes something out from under a human.
2. **Product canon** — where "what are we building and why" lives (a docs dir, a wiki repo, a tracker).
3. **Domain lenses** — anything this codebase gets wrong repeatedly that the default grooming and review
   lenses would miss (money, compliance, accessibility, multi-tenancy). Optional; skip if nothing comes
   to mind.

## 6 · Verify — do not declare success from a file listing

```bash
bash scripts/ai/gate.sh static      # must exit 0, or report exactly what failed
bash ~/.config/ai-tooling/install.sh doctor .
```

Report honestly: which gates ran, which are `SKIPPED (not configured)` and why, engine diversity, and
whether hooks were registered. An install with three skipped gates is a valid outcome — silently calling
it ready is not.

## 7 · Offer the PR

The harness is a real change to the repository: `.claude/`, `.codex/`, `scripts/ai/`, `.tasks/`, and a
block in `AGENTS.md`. On a shared repository the team should see it as a normal change, not find it in a
later diff.

Ask: **"Open a PR adding the harness to this repo?"**

- **Yes** → branch `chore/adw-harness`, commit the generated files with a body explaining what the harness
  is, what it adds, and that `.tasks/` is committed on purpose (it is the provenance record);
  `gh pr create` with a short how-to-try. Do not merge it — that is the operator's, as always.
- **No** → leave the files in place, uncommitted, and say plainly which paths are new so nothing gets
  swept into an unrelated commit later.

Ask before doing either. Never push to the default branch.

## Do not

- Don't fill `_STACK.md` with commands you have not run.
- Don't ask what the repository can tell you.
- Don't enable writeback, open a PR, or commit without an explicit yes.
- Don't overwrite an existing `_STACK.md`: re-installing preserves it, and `--regen-stack` (which backs it
  up first) is only for when the operator asks for a clean slate.
