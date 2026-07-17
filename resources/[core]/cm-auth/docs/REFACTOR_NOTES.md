# cm-auth 2.4.0 — refactor notes

This is a structural + security refactor of cm-auth 2.3.1. **All event names,
state bags, exports, and runtime behavior are unchanged**, so nothing else in the
CM framework needs modification.

## What changed

**Modular structure.** The single 1088-line `server/main.lua` is split into
focused modules under `server/modules/`:

- `util.lua` — logging, notify, sanitize, pcall-guarded oxmysql wrappers
- `crypto.lua` — SHA-256, password hash/verify, timing-safe compare, token gen
- `database.lua` — schema bootstrap + all account lookups
- `identity.lua` — license/HWID/IP extraction, email/password validation, session state
- `security.lua` — lockouts, failure/registration counting, per-player cooldowns
- `server.lua` — entry point wiring the net-event handlers

Config constants were extracted to `shared/config.lua` (read by both sides).
Entry points renamed to `server/server.lua` and `client/client.lua`.

## Security review (what was already good)

The original was already strong: trusted-device tokens stored **hashed** at rest,
DB-backed lockouts on IP+email, timing-safe hash comparison, license+HWID binding,
and no email enumeration on login/reset. Those were all preserved.

## Improvements made

- **Native bcrypt is now preferred hard.** The local salted-SHA-256 path is a
  fallback only, and it logs a loud warning whenever it is used. On a modern
  FXServer build with `GetPasswordHash`/`VerifyPasswordHash`, the weak path
  never runs. **Recommendation: confirm your artifact provides the native.**
- **Register account-id suffix** now uses the token RNG (`randomString`) instead
  of a single `math.random`, reducing collision churn at scale.
- **`util.log` fallback** guarantees warnings/errors reach the console even if
  cm-core is unavailable (previously they could be swallowed).
- Removed version-specific files (`CHANGELOG_v2.3.1.md`, `TEST_STEPS_v2.3.1.md`).

## Why no PolyZones / State-Bag-sync / setTick changes

cm-auth runs once per player at connect. It has no per-frame loops, no entity
iteration, and no world rendering — so the 1000-player client-optimization
patterns (distance grids, PolyZones, State Bag entity sync) do not apply here.
The state bags it already uses (`isLoggedIn`, `accountId`) are the correct tool
and were kept.

## The one real scaling note

Every login runs several sequential `MySQL.*.await` calls. Under a mass-join
these serialize per player. If you ever see connect-queue slowness at very high
concurrency, the fix is to move auth behind a **connection deferral**
(`playerConnecting` + `deferrals`) so hashing/DB work happens before the player
fully streams in — a larger change, called out here but intentionally not made,
since it would alter the connect flow other resources depend on.

## Validation performed

- All 8 Lua files pass `luac5.4 -p` syntax checks.
- The crypto module was round-trip tested standalone: correct passwords verify,
  wrong passwords reject, across varied inputs, with the native path disabled to
  exercise the fallback.
