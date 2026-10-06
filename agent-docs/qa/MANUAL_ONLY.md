# Remaining manual-only or judgment-required QA

cm-qa must record, rather than hide, behavior it cannot safely exercise.

- Real FiveM physical keyboard/mouse behavior: E tap/hold, ESC focus, mouse
  hitboxes, driving through checkpoints, and input timing require a connected
  local client and the optional `tools/cm-qa/client-driver.ps1`.
- First client setup is manual: open the loopback `fivem://connect` endpoint,
  log in, create/select the QA character, and explicitly run
  `cm_qa_register <source>` from the local console bridge.
- During an active QA scenario, ESC is an explicit cancellation test. The
  expected result is `CANCELLED`, followed by no prompt, overlay, cursor,
  focus, or active server run. Resource restart, disable, disconnect, and
  character change must have the same invisible end state.
- Electrician physical repair and early-release checks are intentionally early
  pilots. They must prove the owner-side begin/hold/complete contract before
  the QA harness may invoke or assert gameplay state.
- Multiplayer behavior requires two independently registered QA clients; one
  client must never be treated as two players.
- Subjective visual quality remains human review even after viewport and
  screenshot assertions pass.
- Database-backed scenarios remain blocked when oxmysql or a safe fixture
  character is unavailable. No migration is run automatically.
- Owner-resource gameplay scenarios without a narrow, server-side
  `GetInvokingResource() == 'cm-qa'` snapshot/control API remain blocked.
  Fishing now has that contract; its owner scenario still needs a paired QA
  character, while physical casting and minigame behavior remain deferred.
- OneSync entity streaming, vehicle physics, world positioning, and client F8
  errors require manual or connected-client evidence.
