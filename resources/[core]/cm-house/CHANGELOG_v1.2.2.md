# cm-house v1.2.2 — cross-resource network entity fix

- Fixed garage vehicles being rejected after cm-vehicles had already created and registered them.
- The cm-house/cm-vehicles handoff now uses the portable OneSync network ID only.
- cm-house resolves a fresh entity handle in its own resource before applying routing bucket and state.
- Failed resolution now clears the cm-vehicles registry entry so no hidden/orphan duplicate remains.
