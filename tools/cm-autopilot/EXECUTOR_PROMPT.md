# Execution cycle

Read the approved goal, plan, state, completion history, blockers, decisions, runtime tests, current Git status, and previous cycle result supplied by the runner.

Choose the next unfinished safe approved plan item. Inspect the current implementation and all affected contracts before editing. Implement that item completely, run proportionate validation, and fix failures before moving to another feature. Always include the repository validator, CM scanner check, and `git diff --check` when relevant.

For each distinct validation failure, keep the current plan item in repair mode. Trace the root cause, repair it, rerun the failed check, and record the attempt in `STATE.json` and `BLOCKED.md`. Do not exceed the configured repair-attempt limit. At the limit, mark that item blocked with the exact error, affected files, attempted repairs, likely reason, and required manual action; then select an independent item if one exists.

Update `STATE.json`, `COMPLETED.md`, `BLOCKED.md`, `DECISIONS.md`, and `RUNTIME_TESTS.md` as applicable. Use `status: executing` while work remains, `status: review_ready` when all implementable items are finished, or `status: blocked` only when no independent work remains. Never work outside approved scope. Then exit so the supervisor can launch the next cycle.

After static validation succeeds, use `tools/cm-runtime/runtime-controller.ps1` for local development runtime validation when the change can be exercised server-side. Pass only changed `cm-*` resources and prefer the smallest safe restart. Read `agent-docs/runtime/ERRORS.md`; repair code-level failures, rerun static validation, and repeat. Limit speculative repairs for one distinct failure to the configured maximum. Never run database migrations automatically: record `DATABASE_ACTION_REQUIRED` with the migration and required schema. When verification needs a FiveM client, visual judgment, physical interaction, multiple players, vehicle driving, or unobservable OneSync behaviour, append exact steps to `agent-docs/runtime/MANUAL_TESTS.md` and stop at the manual gameplay gate. The runtime console is not the client F8 console.
