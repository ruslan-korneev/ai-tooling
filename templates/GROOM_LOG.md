# Groom log — <id>

Append-only ledger of `groom-harden` passes. Each pass runs in a **fresh context** and reads this file
first, so it does not re-derive what earlier passes already settled. `scripts/ai/gate.sh groom <id>`
parses the table: the gate opens when the **last two passes are `quiet`** and no blocker is open.

Pass outcome: `quiet` = no new blocker/major · `findings` = new blocker/major raised.

| Pass | Lens | Outcome | New blockers | New majors | Folded into |
| ---- | ---- | ------- | ------------ | ---------- | ----------- |
| P1 | contracts | findings | 1 | 2 | PLAN.md §Contracts, OPEN_QUESTIONS.md#3 |

## Closed — do not re-raise without new evidence

Items earlier passes examined and settled. A later pass that wants to reopen one must cite evidence that
did not exist before, not merely restate the concern.

| # | Item | Pass | Resolution |
| - | ---- | ---- | ---------- |

## Rejected findings

Raised by a pass, judged not real. Off the table — the same finding must not reappear each round.

| # | Finding | Pass | Why rejected |
| - | ------- | ---- | ------------ |
