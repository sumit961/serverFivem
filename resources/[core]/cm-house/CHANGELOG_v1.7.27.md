# cm-house v1.7.27 — Restore interior on rejoin

## Bug fix
- A player who disconnected while inside a house or garage now rejoins back
  inside that actual interior, not just at its raw coordinates. Previously
  `cm-playerdata`/`cm-spawn` correctly restored the last x/y/z, but for any
  interior using an `ipl` source (a native GTA interior room) the room never
  rendered until its IPL was explicitly requested, and the routing bucket
  that keeps that room private to its own occupants was lost on disconnect
  -- so the player landed floating in an empty void instead of the actual
  garage/house. `world`/`shell`-sourced interiors (e.g. the current family
  garage) were never affected, since that geometry is always loaded.
- `SendToHouse`/`SendToGarage`/`SendToWorld` (`server/sv_buckets.lua`) now
  write through to a new `cm_house_last_interior` table on every enter and
  clear it on every explicit exit.
- On `cm-spawn:server:spawned` -- fired only after the client confirms its own
  spawn is complete, deliberately NOT the earlier `cm-playerdata:server:characterLoaded`
  (that fires seconds before cm-spawn actually places the ped, and cm-spawn's
  own spawn-completion handler unconditionally resets the player's routing
  bucket to 0; restoring the garage bucket before that reset just got
  silently wiped, which is what caused the garage's networked vehicles to
  fail with "deleted during initialization" / "never reached OneSync" --
  `server/sv_interior.lua` reads the saved record back, re-checks
  `CanAccessProperty` (so a house sold or a family membership lost while
  offline safely does nothing), confirms the player is actually standing
  near the recorded interior (`playerNear`, so a death/hospital respawn
  elsewhere doesn't drag stale interior state onto an unrelated spawn),
  re-applies the correct routing bucket, and sends the client the same
  template payload `enterHome`/`enterGarage` would have sent.
- `client/cl_interior.lua` handles the new `cm-house:client:restoreInterior`
  event: it calls `RequestIpl` for `ipl` sources and rebuilds the local
  interior state so the E-prompt and door menu work immediately, without
  teleporting the player -- they are already standing in the right spot.
  The garage branch also waits for `HasCollisionLoadedAroundEntity` before
  asking the server to spawn networked garage vehicles, matching what every
  other entry path already guarantees via `goTo()`.

## Migration
- Run `sql/019_last_interior_v1.7.27.sql` (safe to run repeatedly).
