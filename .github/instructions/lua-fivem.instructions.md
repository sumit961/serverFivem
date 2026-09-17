---
applyTo: "**/*.lua"
---

# Lua/FiveM

- Distinguish client, server, and shared runtime code; never use client-only natives server-side.
- Audit OneSync and native availability before relying on runtime behavior.
- Use `RegisterNetEvent` only when networking is required, and validate every server-facing event with defensive type, identity, permission, ownership, distance, routing-bucket, entity, state, cooldown, and operation-lock checks as applicable.
- Prefer owner-resource exports over duplicated state and preserve existing contracts.
- Keep FiveM source/server ID separate from persistent character ID/CID.
- Normalize oxmysql booleans safely and handle missing values explicitly.
- Avoid unnecessary loops and `Wait(0)` except where rendering or input requires it.
- Clean state on `playerDropped` and resource stop.
