# cm-gunstore v1.9.0 — refactor, security & performance pass

## New: buy ammo with the gun (no more standalone ammo column)
- The player store no longer lists ammo as its own items. Selecting a weapon now
  reveals an **Add ammunition** panel populated from that weapon's linked ammo
  (resolved server-side from cm-weapons). Toggle it on, pick a round count, and
  the gun + ammo are delivered together in one validated purchase.
- Weapon + ammo is charged and delivered atomically: if the ammo leg fails, the
  weapon leg is rolled back (refund + stock release + best-effort item removal)
  so a player is never left half-paid.
- New server export `GetWeaponAmmo(weaponItemName)` and NUI round-trip
  `requestWeaponAmmo` → `weaponAmmo`.
- The standalone **Ammo tab is now admin-only** (hidden in the player store).

## Performance (tuned for 1000+ players)
- The client interaction loop now uses **distance-based sleep**: `farSleep`
  (1500ms) when no shop is within markerDistance, `nearSleep` (400ms) inside the
  zone, and `activeSleep` (0ms) only at the counter. Idle players cost almost
  nothing. Tunable in `Config.Perf`.
- All distance checks use squared vector math `#(a - b)` (no `Vdist` /
  `GetDistanceBetweenCoords`).
- Removed the permanently-disabled ox_target code path (~120 dead lines) and its
  retry threads.
- cm-weapons: the optional client damage-modifier loop no longer runs a
  per-frame native for unarmed players (the common case); it sleeps unless the
  player is actually holding a weapon with a damage rule.

## Security / exploit prevention
- Every state-changing net event verifies `source` server-side; no handler
  trusts a client-supplied player id anymore.
  - **Fixed:** `armorImageReady` previously accepted a client-supplied `src`
    argument, letting a crafted trigger target another admin's armor-prefill UI.
    It now only ever acts on `source`, and only for admins. The server-to-server
    `ReceiveArmorImage` export validates the target is an admin.
- Buys are **rate-limited/debounced** per player (`Config.BuyCooldownMs`, default
  600ms) on top of the existing in-flight purchase lock, so buy-spam can't race
  the stock check against the decrement or double-charge.
- Server-side distance check (`isNearShop`) still gates every buy.
- Stock reservation stays atomic (`UPDATE ... WHERE stock >= ?`).

## Structure / code quality
- Shared helpers (`normalizeItemName`, `boolInt`, group labels, etc.) moved to a
  single `shared/util.lua` exposed as `CMGun`, and localized in each file for
  speed. No new globals leaked into the shared environment.
- Faster table-driven base64 decoder on the server.
- Every `RegisterNUICallback` calls `cb(...)` exactly once (prevents CEF leaks /
  hung NUI threads).

## Config additions
- `Config.Perf` — interaction loop sleep tiers.
- `Config.WeaponAmmo` — offer ammo with weapon, default/max bundle rounds.
- `Config.BuyCooldownMs` — per-player buy debounce.
- `Config.AmmoQuantity.default` bumped to 30.
