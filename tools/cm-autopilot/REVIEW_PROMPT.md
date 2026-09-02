# Final review cycle

Re-read the original goal and approved plan. Inspect the final diff and current source, cross-resource contracts, state documents, unresolved TODO/FIXME markers introduced by the work, and every acceptance condition. Run the required validator, CM scanner check, `git diff --check`, and applicable syntax/build/dependency checks.

If a fixable in-scope defect exists, set `STATE.json` status to `executing`, identify the reopened plan item and defect, update the state documents, and exit; the supervisor will resume execution automatically.

If only runtime verification remains and it is required before safe completion, set status to `blocked` and record exact reproduction steps and expected results in `RUNTIME_TESTS.md` and the blocker in `BLOCKED.md`.

Review `agent-docs/runtime/RUNTIME_STATE.json`, `ERRORS.md`, and `MANUAL_TESTS.md`. Do not claim server runtime validation unless the current execution ID and log window are clean. Do not claim access to the FiveM client F8 console. Treat recorded database action or manual gameplay gates as explicit remaining evidence.

Only when the approved goal and acceptance conditions are genuinely complete, set `STATE.json` status to `complete`. Write `COMPLETED.md` with what was built, changed files/resources, migrations, validation, and runtime tests still required. Generate 3–5 unimplemented ideas in `NEXT_IDEAS.md`, each with benefit, affected resources, risk, and estimated scope. Do not implement those ideas. Do not push or deploy.
