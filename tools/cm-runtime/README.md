# CM local runtime controller

Development-only tooling for the repository's txAdmin-managed FXServer. It discovers the `txData` profile and current `fxserver.log`, records a byte offset per execution, extracts only new blocking errors, and exposes a loopback-only, allowlisted FiveM RCon bridge. It never reads or changes `server.local.cfg`, runs migrations, captures the FiveM client F8 console, or operates a production server.

## One-time setup

Copy `runtime.example.json` to ignored `runtime.local.json` and set `fxServerPath` if it cannot be discovered. Keep `developmentOnly` true. The server starts in txAdmin monitor mode with `+set serverProfile <profile>`; it is not launched with `+exec`.

For commands, configure `rcon_password` manually in the already ignored local server config, restrict the endpoint with the local firewall, and put the same value only in the current process environment:

```powershell
$env:CM_FIVEM_RCON_PASSWORD = Read-Host -AsSecureString | ConvertFrom-SecureString -AsPlainText
```

The secret is never persisted or printed. FiveM RCon uses UDP out-of-band datagrams on the FXServer game port (`fivemPort`, normally `30120`), not the txAdmin web port. Requests use the Cfx format: four `0xFF` prefix bytes followed by `rcon <password> <command>` as exact-length UTF-8 text. Response reads have a bounded timeout and support multiple datagrams. Automatic commands are limited to `status`, `refresh`, `ensure|restart|start|stop cm-*`, and the exact existing Arsenal QA commands `cm_arsenal_start`, `cm_arsenal_cancel`, `cm_arsenal_status`, and `cm_arsenal_check [safe-run-id]`. The bridge refuses arbitrary text, extra Arsenal arguments, and non-loopback hosts. FiveM server-side console/admin authorization remains authoritative.

`status` is implemented by the optional `rconlog` resource. If the UDP command is sent but recent console state shows `rconlog` unavailable, the bridge reports `RCON_TRANSPORT_OK_BUT_RCONLOG_STATUS_UNAVAILABLE`; it does not classify the whole transport as broken or add `ensure rconlog` automatically. Resource lifecycle commands and `refresh` do not require `rconlog`.

## Commands

```powershell
.\tools\cm-runtime\server-status.ps1
.\tools\cm-runtime\start-server.ps1
.\tools\cm-runtime\wait-ready.ps1
.\tools\cm-runtime\tail-console.ps1 -Tail 100
.\tools\cm-runtime\tail-console.ps1 -Tail 100 -Resource cm-gang
.\tools\cm-runtime\tail-console.ps1 -Follow
.\tools\cm-runtime\read-errors.ps1
.\tools\cm-runtime\send-command.ps1 "restart cm-gang"
.\tools\cm-runtime\send-command.ps1 "cm_arsenal_status"
.\tools\cm-runtime\send-command.ps1 "cm_arsenal_check"
.\tools\cm-runtime\send-command.ps1 "cm_arsenal_start"
.\tools\cm-runtime\send-command.ps1 "cm_arsenal_cancel"
.\tools\cm-runtime\runtime-controller.ps1 -StartIfNeeded -ChangedResource cm-gang
.\tools\cm-runtime\stop-server.ps1
```

Ctrl+C stops the controller/tail process and leaves FXServer running. Use `stop-server.ps1` for deliberate shutdown; it stops only FXServer processes whose command line matches the configured txData/profile. The existing `tools/cm-autopilot/STOP` file prevents new runtime cycles.

`runtime-controller.ps1` is the deterministic supervisor around Codex repair cycles: establish the current execution window, send a UDP restart for the smallest changed `cm-*` resource, require new `Stopping resource` and `Started resource` log evidence, extract only errors after the pre-command byte offset, and return exit code 2 with `CODEX_REPAIR_REQUIRED`. UDP response text alone is never treated as proof that a restart completed. The Codex execution prompt directs the next cycle to inspect and repair the root cause, re-run static validation, and repeat up to three attempts. Database/schema requirements are recorded as `DATABASE_ACTION_REQUIRED`; migrations are never executed automatically.
