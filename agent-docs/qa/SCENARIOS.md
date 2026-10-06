# CM QA scenario registry

Stable IDs are declared in `resources/[dev]/cm-qa/shared/scenarios.lua`.

| Scenario | Resource | Required layer | Current evidence |
|---|---|---|---|
| qa.framework.smoke | cm-qa | server | COVERED when QA mode is enabled |
| qa.client.input-smoke | cm-qa | client | Physical E + cm-ui prompt + physical ESC without fullscreen NUI; requires one registered local client |
| qa.client.hold-smoke | cm-qa | client | Physical E hold measurement; requires one registered local client |
| qa.framework.unregistered-invisible | cm-qa | server | SERVER_INTEGRATION_PASS when no registered client or active run exists |
| qa.framework.registration-invisible | cm-qa | server | SERVER_INTEGRATION_PASS when registration has not assigned an active run |
| qa.framework.escape-cleanup | cm-qa | server | Requires connected-client lifecycle evidence; no active run may remain after ESC |
| qa.framework.post-pass-cleanup | cm-qa | server | Requires connected-client lifecycle evidence; no active run may remain after PASS |
| license.card.possession.validity | cm-license | server | PARTIAL; owner fixture contract required |
| license.test.start_session | cm-license | server | PARTIAL; owner fixture contract required |
| license.checkpoint.progression | cm-license | client | BLOCKED without registered client/route fixture |
| electrician.shift.start_end | cm-electrician | server | PARTIAL; owner fixture contract required |
| electrician.repair.lifecycle | cm-electrician | server | PARTIAL; owner snapshot/control contract required |
| electrician.panel.ui | cm-electrician | ui | COVERED by preview browser fixture |
| electrician.panel.physical-repair | cm-electrician | client | OWNER PILOT; gated snapshot/control contract, real shift-start path, physical E hold, server progression/reward assertion, and cleanup |
| electrician.panel.early-release | cm-electrician | client | OWNER PILOT; real physical early release with no completion/reward/progression assertion and cleanup |
| electrician.panel.shock | cm-electrician | client | OWNER PILOT; deterministic owner-forced shock with no completion/reward/progression assertion and cleanup |
| fishing.cast.lifecycle | cm-fishing | server | PARTIAL; compatibility alias for the owner snapshot/control contract |
| fishing.qa.owner-contract | cm-fishing | server | PARTIAL; contract and cleanup assertions require a paired QA character, not physical input |
| fishing.qa.blocked-cleanup | cm-fishing | server | SERVER_INTEGRATION_PASS for blocked-run cleanup and runner readiness |
| fishing.store.minigame.ui | cm-fishing | ui | COVERED by preview browser fixture |

Every scenario follows the intended setup/execute/assert/cleanup boundary. The
electrician owner fixture is development-only, invoking-resource checked, and
restores captured progression on cleanup. No scenario creates permanent
accounts, money, items, vehicles, props, or NPCs.
