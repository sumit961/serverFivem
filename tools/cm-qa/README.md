# CM QA

`cm-qa` is a development-only, fail-closed QA harness for the CM FiveM
repository. It composes the existing validator, contract scanner, runtime
controller, local browser, and an explicitly registered FiveM client.

It does not ensure itself from `server.cfg`, edit tracked production config,
or expose gameplay mutation APIs. Run `bootstrap.ps1` to create the ignored
`tools/cm-runtime/runtime.local.json` from the example and discover local paths.
The server resource requires `cm_environment=development` and the console-only
`cm_qa_enable` command.

```powershell
.\tools\cm-qa\bootstrap.ps1
.\tools\cm-qa\run.ps1 -Resource cm-electrician
.\tools\cm-qa\run.ps1 -Resource cm-electrician -Layer UI
.\tools\cm-qa\connect-client.ps1
.\tools\cm-qa\connect-client.ps1 -WaitForCharacter
.\tools\cm-qa\run.ps1 -Scenario qa.client.input-smoke
.\tools\cm-qa\run.ps1 -Scenario qa.client.hold-smoke
.\tools\cm-qa\run.ps1 -Scenario qa.client.input-smoke,qa.client.hold-smoke
.\tools\cm-qa\run.ps1 -Resource cm-qa -RestartAffected
.\tools\cm-qa\report.ps1
```

Reports are written to ignored `cm-agent-out/qa/latest.json` and
`cm-agent-out/qa/latest.md`, with bounded run and screenshot retention.

## Runtime commands

The RCon bridge accepts only exact QA commands after local safety checks:
`cm_qa_enable`, `cm_qa_disable`, `cm_qa_status`, `cm_qa_list`,
`cm_qa_run <stable-id>`, `cm_qa_run_resource <resource>`,
`cm_qa_run_changed`, `cm_qa_cancel`, `cm_qa_report`,
`cm_qa_register <source>`, `cm_qa_pair_character <characterId>`, and
`cm_qa_clients`. It does not accept `set`,
`exec`, or arbitrary commands.

## Honest results and client setup

`agent-docs/qa/BASELINE.json` contains only explicitly approved stable issues.
Reports preserve them as `KNOWN_BASELINE_FAILURE`; unrelated existing dirty
work is `UNRELATED_DIRTY_WORKTREE_FAILURE`; new relevant failures are `FAIL`;
unavailable runtime/client layers are `BLOCKED`.

The one-time local setup is an ignored `tools/cm-runtime/runtime.local.json`
entry such as `qa: { "autoPair": true, "characterId": 12 }`. Character ID is
the authoritative in-game identity; do not put source IDs, identifiers, or
tokens in that file. The first client setup may require opening
`fivem://connect/127.0.0.1:<port>`, logging into FiveM, and
creating/selecting that character. `connect-client.ps1 -WaitForCharacter` can
wait and pair it, but never clicks login or character-selection UI.

Before a client-required scenario, the harness reuses an exact ready pairing
or calls the console-only `cm_qa_pair_character <characterId>`, then waits up
to 15 seconds for the readiness handshake. It never guesses a player or
requires a source-ID lookup. Results distinguish `QA_CLIENT_NOT_CONNECTED`,
`QA_CLIENT_NOT_PAIRED`, and `QA_CLIENT_NOT_READY`. Scenario-only runs preserve
a healthy cm-qa runtime by default. Use `-RestartAffected` or
`-RuntimeValidation` only for an explicit restart-validation phase; a cm-qa
restart requires pairing again.

The physical input smoke sends a real E press, verifies the shared cm-ui prompt,
and sends a real ESC cancellation without opening a fullscreen QA NUI. Its
authoritative result is `CANCELLED`, with prompt, focus, and run state cleared
while QA registration remains. The hold smoke
measures a real E key-down/key-up interval and may pass normally. Both paths
record before/during/after PNGs under ignored
`cm-agent-out/qa/client-screenshots/`. Electrician physical repair remains an
early pilot and is blocked until its owner-side QA contract exists; it must
never invoke production repair logic merely to make QA pass.
