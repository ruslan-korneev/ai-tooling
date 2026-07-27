# ai-tooling — a portable AI Developer Workflow

An SDLC for coding agents that installs into **any** project, for **any** stack, without editing a single
core file. Skills, subagents, and machine-checkable gates live here; everything project-specific is data.

```
~/.config/ai-tooling/
├── install.sh              install · list · doctor · uninstall
├── skills/core/<id>/       17 stack-agnostic skills
├── agents/<name>.md        9 subagents, each defined by what it may NOT touch
├── scripts/                gate.sh · guard.sh · intake.sh · engines.sh · review.sh · worktree-*.sh
├── stacks/<name>.stack     command profiles: generic · node-ts · python · go · roblox
├── templates/              _STACK.md · dev-prompt · GROOM_LOG · BOARD · PROPOSALS · hooks · AGENTS block
└── tests/                  the gates' own test suite — bash + git, no other dependency
```

## The three layers (the law of this repo)

| Layer | What | Changes per project? |
| --- | --- | --- |
| **Core** — loop, gates, agents | `skills/core/`, `agents/`, `scripts/` | **Never.** Copied byte-for-byte |
| **Adapter** — how to lint/test/run *here*, which engines work, where tasks come from | `.tasks/_STACK.md` | Data, not code |
| **Domain** — economy rules, compliance, product canon | separate skills/agents, registered in `_STACK.md` | A separate problem |

Test of correctness: **if adopting this in a new project requires editing a file under `skills/core/`, the
design is broken.** Anything that differs must be expressible as data or as a separate skill.

## Install

**Interactively (recommended)** — a session that works out this project's real commands, intake and
engines, verifies the gates run, and offers to open a PR adding the harness:

```bash
bash ~/.config/ai-tooling/install.sh self-install    # once per machine: adds the /adw-install skill
cd /path/to/project && claude
/adw-install
```

A stack profile guesses `ruff check .`; the interactive install reads the Makefile, the CI workflow and
the dependency manager, **runs** each candidate command, and records only the ones that work — a gate
configured with a command that errors reports `SKIPPED` while the loop looks green.

**Mechanically:**

```bash
bash ~/.config/ai-tooling/install.sh install /path/to/project     # stack auto-detected
bash ~/.config/ai-tooling/install.sh install . --stack python
bash ~/.config/ai-tooling/install.sh install . --no-hooks         # skip the on-edit format hook
bash ~/.config/ai-tooling/install.sh doctor .                     # drift, unset commands, engines
bash ~/.config/ai-tooling/install.sh uninstall .                  # removes generated copies, keeps .tasks/
```

Then, once per project:

```bash
cd /path/to/project
$EDITOR .tasks/_STACK.md                     # check kit, paths, canon, shared resources
bash scripts/ai/engines.sh probe --write     # which engine CLIs actually work (installed ≠ usable)
bash scripts/ai/gate.sh static               # confirm the gates run
```

Generated copies are never clobbered when locally modified — the installer prints `SKIP (differs)` unless
`--force`.

## The loop

```
intake ─► triage ─► scout ─► plan + validation ─► groom passes (fresh context, rotating lens, ledger)
                                                          │ two quiet passes
                                                          ▼
                                              G2 · operator approves the plan
                                                          ▼
                                    ┌──── worktree (always, resources allocated) ────┐
                                    │ test-author → RED gate → builder → GREEN gate  │
                                    │        (may not touch src)  (may not touch tests)│
                                    │ validator → evidence gate                       │
                                    └──────────────────────┬──────────────────────────┘
                                                           ▼
                          lens reviewers ∥ wildcard ─► judge (dedupe + refute + rank)
                                                           ▼
                                              G7 · operator merges ─► harness-improver
```

Two human gates. Everything else is autonomous — except a `blocker`, which always stops the run.

## Gates are commands, not opinions

```bash
bash scripts/ai/gate.sh plan <id>      # plan + validation complete, acceptance mapped, no placeholders
bash scripts/ai/gate.sh groom <id>     # no open blocker + two consecutive quiet groom passes
bash scripts/ai/gate.sh red [path]     # tests MUST fail before the implementation exists
bash scripts/ai/gate.sh green          # static + tests pass
bash scripts/ai/gate.sh evidence <id>  # every validation check has evidence on disk
bash scripts/ai/guard.sh builder       # the implementer's diff may not touch tests
bash scripts/ai/review.sh 1 .tasks/<id>/VALIDATION.md --profile deep
```

An on-edit hook runs the project's formatter after every `Edit`/`Write` (`--no-hooks` to opt out).
Instructions are advisory; hooks and exit codes are not.

## The gates have their own gate

An exit code nobody checks is an opinion with better posture, so the gates are themselves tested —
against throwaway git repos, with no network, no `gh` and no engine CLI:

```bash
bash tests/run.sh                        # every case
bash tests/run.sh gate-plan              # one
ADW_TEST_SHELL=/bin/bash bash tests/run.sh   # under macOS's bash 3.2
```

CI runs both on Linux and macOS. A case may declare a **known gap** — the behaviour we want, asserted
where the code does not deliver it yet. A known gap keeps the suite green and reports itself; the day
it starts passing, the suite fails so the test gets promoted instead of quietly rotting. The current
three are printed by every run, and `tests/run.sh` ends by naming the surface it does **not** cover
(anything needing a remote, `gh`, or a live engine).

## Profiles — right-size the loop

`workflow-triage` picks from **blast radius**, not diff size, and can escalate mid-run.

| | `light` | `standard` | `deep` |
| --- | --- | --- | --- |
| Groom | 1 pass | loop-until-dry, 2 lenses | loop-until-dry, all lenses |
| Review | 1 reviewer | 3 lenses + wildcard | all lenses + wildcard + judge |
| Human gates | G7 | G2 + G7 | G2 + G7 |

## Agent identities = what they may not touch

| Agent | Forbidden |
| --- | --- |
| `context-scout` | writes nothing but the provenance index |
| `planner` | anything outside `.tasks/` |
| `groom-hardener` | product code (one lens per pass, ledger-aware) |
| `test-author` | source paths |
| `builder` | test files |
| `integration-verifier` | source and tests |
| `slice-reviewer`, `wildcard-reviewer`, `review-judge` | everything (read-only) |

`guard.sh` enforces this on the diff. A prompt that says "please don't" is not a boundary.

## Intake — any tracker, your own tooling, no MCP

The core knows a five-field contract (`id`, `title`, `body`, `url`, `status`) and runs **your** command
to satisfy it:

```ini
INTAKE=linear
INTAKE_CMD=linear-kit issue show <ref> --json
INTAKE_SKILL=linear-tasks
INTAKE_STATUS_CMD=linear-kit issue update <ref> --state "<value>"
INTAKE_COMMENT_CMD=linear-kit issue comment <ref> --message "<value>"
```

```bash
bash scripts/ai/intake.sh fetch SM-12          # → normalized JSON + extra_context/ticket.md
bash scripts/ai/intake.sh writeback SM-12 --comment "PR: <url>"
```

JSON output is mapped automatically (`identifier|key|id`, `title|name|summary`, `description|body`, …).
Anything else is handed to the agent with `INTAKE_SKILL` named. No `INTAKE_CMD` → manual paste. A new
tracker is one config line; a failed fetch is a stop, never an invented ticket. Writeback is off by
default and, when on, makes exactly two writes: in-progress at the start, PR link at the end.

## Engines — installed ≠ usable

A CLI on PATH can be unauthenticated, unpaid, or rate-limited; it then fails silently and a missing review
lens looks exactly like a clean one. So availability is **earned**:

```bash
bash scripts/ai/engines.sh candidates      # on PATH
bash scripts/ai/engines.sh probe --write   # actually call each; record the ones that answer
```

Entries can pin a model (`claude:opus`, `claude:sonnet`) — with one paid vendor, model rotation is still
real independence. Reviews are labelled `CROSS-ENGINE` > `CROSS-MODEL` > `DEGRADED`, and `DEGRADED` is
never presented as an independent verdict.

## Skills

| Skill | Phase |
| --- | --- |
| `adw-run` | drives the whole loop, stops at G2 and G7 |
| `task-intake` | ticket / prompt / bug report → `.tasks/<id>/` |
| `workflow-triage` | picks the profile from blast radius |
| `task-explore` · `task-plan` · `task-open-questions` · `task-checklist` | grooming artifacts |
| `slice-verify` | `VALIDATION.md`: acceptance → check → expected → evidence |
| `groom-harden` | adversarial passes with lens rotation + `GROOM_LOG.md` ledger |
| `dev-prompt` | gate check → self-contained implementation prompt |
| `test-author` · `slice-implement` | RED then GREEN, under mechanical guards |
| `verification-before-completion` | prove it before saying done |
| `slice-review` | rubric registry: lens blocks + judge rubric |
| `harness-improver` | proposals for improving this harness (never applies them) |
| `orchestrate` · `handoff` | parallel tasks; session compaction |

## Evolving it

`harness-improver` writes proposals; you decide. When a proposal is project-independent, edit the
canonical skill **here**, re-install with `--force`, and `doctor` will show which projects still drift.
