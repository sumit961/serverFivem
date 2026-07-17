# cm-vehicles v2.5.0 — Service, HUD, Mods, Keys

This build retunes crash/fuel behaviour and adds future-proof hooks so a **petrol
pump prop**, a **gas-can item**, a **repair kit / mechanic**, a **car wash**, a
**tuning shop**, and a **key-management UI** can all be added later **without
editing cm-vehicles or any weapon/item resource**. You only call the exports /
events listed here.

---

## 1. Tuning changes (already live, no action needed)

| Behaviour            | Before                    | Now |
|----------------------|---------------------------|-----|
| Crash engine damage  | 120 health per hit        | **~1% (10 health) per hard hit** |
| Engine stops on crash| every ejection-level crash | **only severe crashes, rolled at random (22%)** |
| Seatbelt warning     | chime sound               | **HUD flag only, no sound** |
| Engine start beep    | played on F-tap re-enable | **removed** |
| Fuel drain           | very slow                 | **faster + realistic (~20–30 min/tank)** |
| Cruise control key   | Caps Lock                 | **X** |

All values live in `shared/config.lua` under `Damage`, `Fuel`, `Seatbelt`,
`Engine`, and `Controls`. Tune freely.

> Note: `X` is also GTA's default vehicle handbrake. If that clash bothers you,
> change `Controls.cruiseKey` in `shared/config.lua` to any free key.

---

## 2. Refueling (petrol pump + gas can)

**No weapon/item edits needed.** When you add the gas-can item or pump prop,
just call these client exports on use:

```lua
-- Gas can: adds a fixed % (Config.Service.gasCanRefillAmount, default 25)
exports['cm-vehicles']:AddFuel(nil, 25.0)   -- nil = nearest/current vehicle

-- Petrol pump timed fill: set exact % (call in a loop for a live pump)
exports['cm-vehicles']:SetFuelExact(nil, 100.0)

-- Read fuel anywhere (also used by cm-hud)
local pct = exports['cm-vehicles']:GetVehicleFuel(nil)
```

Both persist to the DB automatically. `Config.Service` controls amounts:
`gasCanRefillAmount`, `pumpRefillPerSecond`, `maxFuel`.

**Example gas-can item handler (in cm-items / your item resource, later):**
```lua
-- when the 'gas_can' item is used:
exports['cm-vehicles']:AddFuel(nil)  -- uses config default
```

**Example petrol-pump zone (later):**
```lua
CreateThread(function()
    while filling do
        exports['cm-vehicles']:AddFuel(nil, Config.Service.pumpRefillPerSecond)
        Wait(1000)
    end
end)
```

---

## 3. Repair (repair kit / mechanic)

```lua
-- Repair kit: adds config amounts to engine + body
exports['cm-vehicles']:RepairVehicle(nil, {})                       -- kit amounts
exports['cm-vehicles']:RepairVehicle(nil, { engine = 200, body = 200 })

-- Mechanic full repair (everything to 1000, deformation fixed)
exports['cm-vehicles']:RepairVehicle(nil, { full = true })
```

Persists automatically. Amounts in `Config.Service.repairKitEngineAmount` /
`repairKitBodyAmount`.

Server-side (for a server-run mechanic job or admin command) you can also do it
without any client:
```lua
exports['cm-vehicles']:ServiceVehicle('CMAB12', { engineHealth = 1000, bodyHealth = 1000 })
```

---

## 4. Car wash + dirt

Dirt now accumulates while driving (`Config.Dirt`) and persists via the normal
save loop. To clean:

```lua
exports['cm-vehicles']:WashVehicle(nil)   -- resets dirt to Config.Service.washResetsDirtTo
```

Add a wash zone/prop later and just call this.

---

## 5. cm-hud live feed

cm-vehicles publishes one state bag every 250ms (`Config.Hud`). **cm-hud needs no
hard dependency** — just read it:

```lua
-- inside cm-hud, on a render tick:
local v = LocalPlayer.state.cmVehicleHud
if v and v.inVehicle then
    -- v.fuel          number  (0-100, one decimal)
    -- v.lowFuel       bool    (<= Config.Fuel.lowFuelWarnPercent)
    -- v.engineHealth  number  (0-1000)
    -- v.engineOn      bool
    -- v.seatbelt      bool    (belt on)
    -- v.seatbeltWarn  bool    (moving unbelted -> flash belt icon)
    -- v.cruise        bool
    -- v.harness       bool
    -- v.speedKmh      number
end
```

Suggested cm-hud additions: a fuel gauge, a belt icon that flashes when
`seatbeltWarn`, a cruise indicator, and a low-fuel warning when `lowFuel`.

---

## 6. Cosmetic / mod persistence (tuning shop)

New `mods` column stores colors, extras, wheels, tuning, neons, livery, tint.
On spawn, saved mods are re-applied automatically.

After a tuning shop applies changes to the vehicle, persist them:
```lua
-- reads current cosmetic state off the vehicle and saves it
exports['cm-vehicles']:SaveVehicleMods(nil)

-- or pass an explicit mods table (see applyVehicleMods in client/spawn.lua for shape)
exports['cm-vehicles']:SaveVehicleMods(nil, {
    primaryColor = 27, secondaryColor = 0,
    mods = { ['11'] = 3, ['12'] = 2 },   -- modType = modIndex
    extras = { ['1'] = true },
    neons = { true, true, true, true },
})
```

---

## 7. Key lending / revoking

Owner-facing key management over the existing temp-key system.

```lua
-- Lend a key to an online player (owner only)
TriggerServerEvent('cm-vehicles:server:lendKey', plate, targetServerId)

-- List current key holders (server export)
local holders = exports['cm-vehicles']:GetLentKeys('CMAB12')
-- -> { { charId, name, at }, ... }

-- Revoke a specific holder's key
TriggerServerEvent('cm-vehicles:server:revokeKey', plate, targetCharId)
```

Backed by a new `cm-vehiclekeys` export `RevokeTempKeyByChar(plate, charId)`.
`Config.Keys.maxLentKeysPerVehicle` caps how many keys one car can have out.

---

## 8. Full export/event reference (new in 2.5.0)

**Client exports (cm-vehicles):**
- `GetVehicleFuel(veh)` → %
- `AddFuel(veh, amount?)` → new %
- `SetFuelExact(veh, percent)` → new %
- `RepairVehicle(veh, { engine?, body?, full? })` → ok, {engineHealth, bodyHealth}
- `WashVehicle(veh)` → ok
- `SaveVehicleMods(veh, mods?)` → ok, mods

**Server exports (cm-vehicles):**
- `ServiceVehicle(plate, { fuel?, engineHealth?, bodyHealth?, tankHealth?, dirtLevel? })`
- `GetLentKeys(plate)` → list

**Server events (cm-vehicles):**
- `cm-vehicles:server:persistService` (plate, patch)  — called by client helpers
- `cm-vehicles:server:saveMods` (plate, mods)
- `cm-vehicles:server:lendKey` (plate, targetSrc)
- `cm-vehicles:server:revokeKey` (plate, targetCharId)

**Server exports (cm-vehiclekeys):**
- `RevokeTempKeyByChar(plate, charId)`
- `RevokeTempKey(src, plate)`

**Client state bag:** `LocalPlayer.state.cmVehicleHud`

---

## 9. Database

New column added automatically on start (`ensureColumn`):
```
mods LONGTEXT NULL
```
No manual SQL required. Existing cars simply have `mods = NULL` until first saved.
