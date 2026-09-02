---
name: fivem-runtime-debug
description: Use when diagnosing FiveM startup, resource, FXServer, txAdmin, console, RCon, callback, export, query, or runtime errors.
---

# FiveM Runtime Debugging

Use the existing `tools/cm-runtime/` scripts. Their command bridge is FiveM UDP out-of-band RCon, not TCP Source RCon. Use `server-status.ps1`, `start-server.ps1`, `tail-console.ps1`, `read-errors.ps1`, `send-command.ps1`, and `runtime-controller.ps1`. Confirm restarts from the server command log and read only new execution windows. Fix evidenced code-level failures, not gameplay-only problems; after three meaningful attempts report `RUNTIME BLOCKER`.
