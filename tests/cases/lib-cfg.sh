#!/usr/bin/env bash
# lib.sh — adw_cfg / adw_cfg_note. Every gate reads its commands through these two functions, so a
# parsing slip here silently rewires every project at once.
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/harness.sh"

repo="$(fixture cfg)" || exit 1
stack "$repo" <<'INI'
LINT_CMD=ruff check .
TYPECHECK_CMD=            # none: no type checker in this toolchain
TEST_CMD=pytest -q
LENSES=contracts,adversary
INI

cfg()  { local d="$1"; shift; ( cd "$d" && source scripts/ai/lib.sh && adw_cfg      "$@" && echo ); }
note() { local d="$1"; shift; ( cd "$d" && source scripts/ai/lib.sh && adw_cfg_note "$@" ); }

check_out 'plain value'                    'ruff check .'  cfg "$repo" LINT_CMD
check_out 'value keeps its own spaces'     'pytest -q'     cfg "$repo" TEST_CMD
check_empty 'trailing "# note" is not part of the command' cfg "$repo" TYPECHECK_CMD
check_out 'the note itself is readable'    'none: no type checker' note "$repo" TYPECHECK_CMD
check_out 'missing key falls back'         'fallback'      cfg "$repo" NO_SUCH_KEY fallback
check_out 'empty value falls back too'     'mypy'          cfg "$repo" TYPECHECK_CMD mypy

# A project with no _STACK.md at all must yield defaults, never an error or a partial read.
bare="$(fixture cfg-bare)" || exit 1
check_out 'no _STACK.md → default' 'standard' cfg "$bare" DEFAULT_PROFILE standard

done_tests
