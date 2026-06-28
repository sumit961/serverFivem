# rn-vehicleshop CM Adapted

This version keeps the rn-vehicleshop showroom UI but removes QBCore, qb-target, player_vehicles and qb-vehiclekeys.

Ownership now goes through your current `cm-vehicles` resource:

- Purchases create rows in `cm_owned_vehicles` using `exports['cm-vehicles']:CreateOwnedVehicle(...)`.
- Trunk level is saved into the owned vehicle row.
- `/vehicleadmin` controls which cars are allowed on the server.
- Cars that are not saved/enabled in `/vehicleadmin` are hidden and should not be used.

## Install

1. Replace your old `rn-vehicleshop` folder with this folder.
2. In `server.cfg`, ensure order is:

```cfg
ensure oxmysql
ensure cm-vehiclekeys
ensure cm-vehicles
ensure rn-vehicleshop
```

3. Restart the server.
4. In game, run:

```text
/vehicleadmin
```

For each car:

- Set price.
- Set trunk level.
- Tick **Available in server** if it should be visible/allowed.
- Tick **Available in store** if players can buy it.

Event/task vehicles: tick only **Available in server**. They will show in the store as Event / Task only and cannot be bought.

Normal dealership vehicles: tick both **Available in server** and **Available in store**.

Hidden / unused vehicles: untick both or press **Disable / Hide**.

## Giving event vehicles

Admins can give any enabled catalog vehicle to themselves:

```text
/vehgivecatalog sultan
```

Other scripts can use:

```lua
local ok, vehicleData = exports['rn-vehicleshop']:GiveCatalogVehicle(source, 'sultan', {
    source = 'event_reward'
})
```

Only cars enabled in the vehicle admin catalog can be given.

## What changed in this build

Four fixes/features were added on top of the CM adaptation:

### 1. Money now uses cm-core (same as cm-gunstore)

Purchases and test drives charge money through `exports['cm-core']:RemoveMoney(src, account, amount)`
and refund with `AddMoney`, exactly like the gun store. The account is chosen by
`Config.PaymentAccount` ('cash' or 'bank') resolved through `Config.Accounts`.
The old `cm-playerdata`/`characters` DB path was removed. `cm-core` is now a
dependency in `fxmanifest.lua`.

### 2. Showroom no longer drops you into the sky

Entering the showroom and all exit teleports now wait for map collision to stream
in (`RequestCollisionAtCoord` + `HasCollisionLoadedAroundEntity`) and snap to the
real ground height (`GetGroundZFor_3dCoord`) before freezing the player. This
removes the "press E and float into the sky / stuck" bug.

### 3. Mouse inspection works immediately

You can rotate the car with the mouse and zoom with the scroll wheel the moment you
select a vehicle — no need to press **Preview** first. **Preview** now only hides the
side panels for a clean look.

### 4. Transparent vehicle images are required to enable a car (admin)

This mirrors the clothing store's screenshot-basic capture and uses the **same green
prop** (`prop_ld_greenscreen_01`, shipped in `stream/`).

How it works now:

- A vehicle **cannot be enabled** (Available in store / Available in server) unless it
  has a transparent image. The server refuses to enable an imageless car.
- In `/vehicleadmin`, fill in the details, tick the box(es), and press **Save / Enable**.
  If the car has no image yet, it is **automatically photographed** against the green
  screen, the background is removed in the UI, the PNG is saved into
  `ui/images/vehicles/`, and the save is then completed — all in one click.
- The image path is stored in the `cm_vehicle_catalog.image` column and shows as a
  thumbnail in the admin list and as a preview under the form, plus in the store.
- Use **Recapture Image** to replace the photo later without changing anything else.

**Requirements:**

```cfg
ensure screenshot-basic   # before rn-vehicleshop (required for capture)
ensure cm-core
ensure cm-vehicles
ensure rn-vehicleshop
```

- `screenshot-basic` must be started.
- `stream/prop_ld_greenscreen_01.ydr` must stay in place (it ships with the resource).
  If it is missing, capture falls back to a flat green rectangle.
- The `ui/images/vehicles/` folder must exist (ships with a `.keep`) and be writable.
- The `image` column is added automatically on start for existing installs.

Tuning (`config.lua` → `Config.ImageCapture`): `background`, `crop`, `padding`,
`chroma` thresholds, and `Backdrop` (prop `model`, `pieces`, `spacing`,
`distanceBehindVehicle`, `zOffset`, `rotation`, `headingOffset`). If the green wall
is not square-on to the camera in your showroom, adjust `headingOffset`.



## NPC greet, RP talk, and per-player dimension (this build)

- The dealer NPC stands at `Config.Dealer.coords` (currently inside the Pacific Bluffs
  MLO at -2261.85, 391.45, 174.67). Walk up and the dealer greets you with a spoken
  bark + a text bubble (random lines from `Config.Ped.greetings`).
- Within `Config.Interact.distance`, an on-screen **[E] Talk to Dealer** prompt appears.
  Press **E** to open a short RP dialog (the dealer speaks a line), then choose
  **Show me the catalog** to open the shop or **Maybe later** to walk away (farewell bark).
- When the catalog opens, the player is moved into their **own routing bucket**
  (`Config.Dimension.base + serverId`) so the preview car and green-screen capture never
  clash with other players shopping at the same time. They return to bucket 0 on close,
  buy, test drive, or disconnect.
- The in-store preview car spawns at `Config.Showroom.vehicle` (-2268.13, 383.24, 174.82).

Tuning: edit `Config.Ped` (greetings/farewells/voices/dialog), `Config.Interact`
(distance, prompt text, key), and `Config.Dimension` (enable/disable, base id). To move
the NPC or preview spot, stand where you want it, run `/vehcoords`, and paste the printed
values into `Config.Dealer.coords` / `Config.Showroom`.

## This build's fixes

- Money now matches cm-gunstore exactly (cm-core RemoveMoney/AddMoney, default 'bank').
- Player is hidden (invisible + no collision) while in the showroom camera, restored on exit.
- The [E] interaction prompt is force-hidden the moment the showroom opens.
- Buying a car registers ownership only and does NOT spawn the car (parking system later).
  If you see "Character not found", check F8 server console for the printed CreateOwnedVehicle
  failure line; it shows the resolved charId so you can see what cm-vehicles needs.
- NPC Z is taken exactly from Config.Dealer.coords (no terrain ground-snap, which sinks
  peds inside MLOs). If the dealer still floats/sinks, run /vehcoords standing on the floor
  and paste the Z into Config.Dealer.coords.

### Test commands
- /vehcoords         -> print your current coords to paste into config.
- /mycar <model>     -> TEST spawn a vehicle next to you and put you in it (no ownership).

## "Character is not loaded" fix

cm-vehicles' CreateOwnedVehicle resolves the character only from the player's state
bag (Player(src).state.charId). In some sessions (notably while in a custom routing
bucket) that lookup returns "Character is not loaded" even when a valid charId exists.

Fixes in this build:
- The per-player dimension is OFF by default (Config.Dimension.enabled = false), which
  was the trigger.
- If the cm-vehicles export ever still fails but we resolved a valid charId, the shop
  writes the cm_owned_vehicles row directly using the IDENTICAL schema and plate format
  (CM + 6 digits) and an audit row, so the purchase always completes and the row is
  indistinguishable from a normal cm-vehicles create. /myvehicles will list it.
