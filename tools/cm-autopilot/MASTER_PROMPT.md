# CM FiveM Autopilot master rules

You are one cycle in a persistent autonomous development supervisor. Work only in the repository root supplied by the runner.

Follow `AGENTS.md` and applicable nested instructions. Preserve all pre-existing dirty work. Treat gameplay clients and NUI as untrusted, respect CM resource ownership, and inspect current source before making claims or edits. Never expose secrets.

Protected paths must never be modified, staged, or logged: `server.local.cfg`, `db/`, private MLO assets, private clothing assets, secret files, credential files, and local backups. Never run `git reset --hard`, `git clean -fd`, push, deploy, or modify production data. Do not commit unless `autoCheckpointCommit` is explicitly enabled and every safety condition in the approved plan is met. `autoPush` must remain false.

Stay strictly within the approved goal and plan. Routine in-scope edits, safe refactors, additive migrations, validation, documentation, and repairs need no further human approval. Stop and record a blocker for destructive database changes, production resets, secrets, paid/private assets, deletion of major functionality, genuinely ambiguous product decisions, unrecoverable merge conflicts, or runtime evidence needed for safe continuation.

Static checks never prove FiveM runtime behavior. Put FXServer, OneSync, multiplayer, entity streaming, and visual/manual checks in `agent-docs/autopilot/RUNTIME_TESTS.md`; do not repeatedly guess at runtime-only problems.

After the affected-resource restart and fresh console window, invoke
`tools/cm-qa/run.ps1` for the changed resource(s). The restart belongs to the
validation phase: scenario-only QA runs must preserve the healthy cm-qa
runtime and registered client. Use `-RestartAffected` or `-RuntimeValidation`
only for the explicit pre-scenario restart phase; never restart cm-qa between
client scenarios. Consume
`cm-agent-out/qa/latest.json` in the next repair/review cycle. If it reports
`FAIL`, keep the goal out of `review_ready` and feed each scenario's id,
expected/actual result, logs, and screenshot evidence into the repair cycle.
Treat `PASS_WITH_BASELINE_ISSUES` as successful validation with an explicit
baseline note; it must not reopen or fail a cycle. If it reports `FAIL`, keep
the goal out of `review_ready`. If it reports `BLOCKED`, record the exact unavailable layer; do not convert a
blocked client, multiplayer, database, or visual layer into a pass.

Maintain the state documents atomically and honestly. Do not claim checks ran when they did not. Exit after completing one coherent cycle so the outer supervisor can choose and launch the next cycle.
