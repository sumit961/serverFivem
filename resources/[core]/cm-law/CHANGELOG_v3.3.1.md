# cm-law v3.3.1 — Persistent Fleet Recovery Hardening

- Generic Law and Police fleet reconciliation now attempts server-side persistent vehicle creation at startup and every 60 seconds, including when no players are online.
- Unsupported streamed/add-on models remain queued and use the existing client-assisted creation path when a suitable bucket-0 player is available.
- Recovery is serialized by authoritative `vehicle_id`, validates organization ownership, reuses registered or orphaned world entities, and preserves each database vehicle identity.
- Startup reconciliation preserves saved damage and fuel. Manual recall continues to repair and refuel.
- The trusted `cm-vehicles` persistent-world API restores saved condition and defers client-dependent mods through the existing finalization state.
- No fleet schema, UI, or gameplay redesign was introduced. Vehicle G-menu files and Organization Hub visuals were not changed.
- Runtime behavior for server-supported models depends on OneSync and the server's available model handling; unsupported streamed models require a suitable client before physical creation.
