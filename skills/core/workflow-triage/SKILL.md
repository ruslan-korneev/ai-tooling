---
name: workflow-triage
description: Decide how much workflow a task deserves — profile light / standard / deep — and record the choice with its reason in PLAN.md. Use at the start of every run, before planning. Prevents a typo fix from costing twenty agent runs and a persistence migration from getting one shallow review.
---

# workflow-triage — right-size the loop

The full loop costs ~15–20 agent runs. Some tasks deserve it; most don't. Pick the profile **from the
blast radius of being wrong**, not from the size of the diff. State the choice in one line and move on —
do not ask the operator.

## Profiles

| | `light` | `standard` | `deep` |
| --- | --- | --- | --- |
| Scout | skip (read the files directly) | yes | yes, multi-angle |
| Groom passes | 1 | loop-until-dry, 2 lenses | loop-until-dry, all lenses |
| TDD | optional | yes where a test command exists | yes, RED gate enforced |
| Review | 1 reviewer | 3 lenses + wildcard | all lenses + wildcard + judge |
| Human gates | G7 only | G2 + G7 | G2 + G7 |

## Choosing

Go **deep** when *any* holds:
- touches a contract others depend on (API, event, schema, replicated state)
- data migration, or anything that can lose or corrupt persisted data
- money, permissions, authentication, or progression state
- concurrency, ordering, or retry semantics
- a change that is hard to reverse once shipped (public interface, published asset, external side effect)

Go **light** when *all* hold:
- fully reversible in one revert, no state left behind
- no contract, no persisted data, no trust boundary
- the acceptance is observable in a single check
- an experienced engineer would review it in under two minutes

Otherwise **standard**. When genuinely torn, take the heavier one: an unnecessary review pass costs
tokens, a missed contract bug costs a migration.

## Escalation and de-escalation

The profile is not frozen. Escalate mid-run and say why:
- grooming surfaces an undefined contract or a trust boundary → `standard` → `deep`
- the diff grows past its planned scope → escalate one level
- a review round finds a blocker → next round runs `deep`

De-escalate only before implementation starts, never to avoid a failing gate.

## Output

One line in `PLAN.md` § Overview:

```markdown
**Profile:** deep — touches the reward contract + a profile schema migration (irreversible on rollback).
```

Plus a `Profile changed:` line under `Decisions locked` if it moves mid-run.

## Do not

- Don't pick `deep` for everything "to be safe" — it trains the operator to skim, and a skimmed gate is no gate.
- Don't pick `light` because the deadline is tight; that is exactly when the blast radius argument matters.
- Don't ask the operator to choose; state your reasoning and let them override.
