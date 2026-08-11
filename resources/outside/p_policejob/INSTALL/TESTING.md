# p_policejob — Feature Testing Guide

A reference of every command, keybind and major feature so you can walk through and test the resource end-to-end.

> **Note**
> - Most commands are restricted to the police job (and certain grades) — log in as a cop before testing.
> - All keybinds shown below are **defaults**. Players can rebind any `lib.addKeybind` / `RegisterKeyMapping` entry from `Settings → Key Bindings → FiveM` in the pause menu.
> - Items used as "use" triggers (handcuffs, body_cam, breathalyzer, photo, etc.) require the inventory items to be installed (see [`INSTALL/ITEMS/`](ITEMS/)).

---

## 1. Quick command reference

| Command | What it does | Default key | Module |
|---|---|---|---|
| `/policemenu` | Opens the main police radial / context menu | `F6` | interactions |
| `/wardrobe` | Opens the police wardrobe (outfits, save/load) | – | wardrobe |
| `/escort` | Quick-escort the closest cuffed/grabbed player | – | interactions |
| `/issueTicket` | Issue a fine to the closest player | – | tickets |
| `/handsup` (configurable) | Toggle hands-up animation | `X` | handsup |
| `/seat [number]` | Switch seats inside a vehicle (no arg = cycle) | – | heli |
| `/cctv_creator` | Place a new CCTV camera prop | – | cctv |
| CCTV target zone | Open the CCTV viewing menu (target the `cctv` point in maps/departments) | – | cctv |
| `/speedcam_creator` | Place a new speed camera | – | speedcam |
| `/speedcam_manager` | List / remove placed speed cameras | – | speedcam |
| `/trafficmenu` | Open the traffic management menu (cones, signs, barriers) | – | traffic |
| `/openObjectMenu` | Spawn deployable props (cones/barriers/etc.) | – | objects |
| `/trunk_editor` | Edit per-vehicle trunk presets | – | trunks |
| `/entertrunk` | Climb into the trunk of the closest vehicle | – | trunks |
| `/exittrunk` | Climb out of the trunk | – | trunks |
| `/radarconfig` | Toggle radar HUD edit mode (drag/resize) | – | vehicle_radar |
| `/test_wanted` | Dev: trigger a fake "wanted" alert on radar | – | vehicle_radar |
| `/jailhud` | Toggle the jail HUD overlay | `F10` | prison |
| `/mugshot` | Take a mugshot of the closest player | – | prison/mugshot |
| `/prisontasks` | Open the officer-side prison tasks menu | – | prison |
| `/prisonmanagement` | Open the prison management menu (sentences, jobs) | – | prison |

## 2. Keybind reference (default keys)

| Action | Key | Configurable in |
|---|---|---|
| Police menu | `F6` | [`modules/interactions/config.lua`](../modules/interactions/config.lua) → `PoliceMenu` |
| Hands up | `X` | [`modules/handsup/config.lua`](../modules/handsup/config.lua) |
| Stop carrying a player | `E` | [`modules/interactions/config.lua`](../modules/interactions/config.lua) → `Carry.stopCarryKey` |
| Helicam toggle | `F4` | [`modules/heli/config.lua`](../modules/heli/config.lua) → `Keys.toggle` |
| Helicam cycle vision (Normal/NV/Thermal) | `N` | `Keys.cycleVision` |
| Helicam toggle spotlight | `L` | `Keys.toggleLight` |
| Helicam lock target | `E` | `Keys.lockTarget` |
| Vehicle radar toggle | `F7` | [`modules/vehicle_radar/config.lua`](../modules/vehicle_radar/config.lua) → `Keys.toggle` |
| Vehicle radar lock front antenna | `[` (`OEM_4`) | `Keys.lockFront` |
| Vehicle radar lock rear antenna | `]` (`OEM_6`) | `Keys.lockRear` |
| Vehicle radar cycle direction filter | `\` (`OEM_5`) | `Keys.cycleMode` |
| Diving suit deactivate | `G` | [`modules/divingsuit/config.lua`](../modules/divingsuit/config.lua) → `deactivateKey` |
| K9 spawn menu | `INSERT` | [`modules/k9/client.lua`](../modules/k9/client.lua) (`k9_spawn`) |
| K9 dismiss | `DELETE` | (`k9_dismiss`) |
| K9 actions menu | `HOME` | (`k9_actions`) |
| Toggle Jail HUD | `F10` | [`modules/prison/client.lua`](../modules/prison/client.lua) |

---

## 3. Feature-by-feature test plan

### 3.1 Interactions — police menu, cuffs, carry, escort
- Press `F6` (or `/policemenu`) to open the radial menu — verify it shows job-grade-appropriate entries.
- Use the **handcuffs** item on a nearby player (or the radial entry) → player should be cuffed (animation + state).
- With a cuffed player nearby, run `/escort` (or use the menu) to quickly grab them.
- Pick someone up with the **carry** action; press `E` to drop them.
- If `Config.Interactions.Cuffs.cuffKeys = true`, uncuffing requires the `cuffs_key` item — verify you can't uncuff without it.
- Try cuffing variants: zipties (`cable_ties`), mouthtape (`mouthtape`), headbag (`headbag`).

### 3.2 Wardrobe
- Run `/wardrobe` near a wardrobe ped/zone → outfits UI opens.
- Save a new outfit (officer with create permission). It writes to `p_policejob_outfits`.
- Load and delete outfits. Verify gender + grade filtering works.

### 3.3 Tickets / fines
- Stand near a player and run `/issueTicket` → fine UI opens.
- Submit a ticket → recipient should receive a notification and money deduction (per framework).

### 3.4 Body camera, breathalyzer, photo, drug test
- Use the `body_cam` item → toggles bodycam UI overlay.
- Use the `breathalyzer` item → opens breathalyzer; aim at a target, take reading.
- Use the `photo` item (camera) → take photo / open camera UI.
- Use the `drug_test_kit` near a target → captures drug result.

### 3.5 Evidence
- Use `evidence_kit` near blood/casing/fingerprint markers → collects an evidence item.
- Visit the **evidence lab** and **evidence storage** stashes (prefixes `p_policejob_evidence_lab` / `p_policejob_evidence_storage`).
- Run reconstructions with `evidence_reconstructor`; clean scenes with `cleaning_kit` + `broom`.

### 3.6 Tracking band
- Apply the `tracking_band` item to a (cuffed) player → server stores entry in `p_policejob_bands`.
- Use the `tracking_vehicle` item on a vehicle → vehicle appears in `GlobalState.p_policejob_vehicleTrackers`.
- Open GPS / tracker UI (police menu → tracker) and verify markers update.

### 3.7 Helicopter cam (Helicam)
- Get into a helicopter, press `F4` to start helicam.
- `N` cycles Normal / Night Vision / Thermal.
- `L` toggles spotlight (must be enabled in config).
- `E` locks onto closest ped/vehicle in view.
- `/seat 2` — switch to seat 2; `/seat` cycles seats.

### 3.8 Vehicle radar
- Sit in a police vehicle, press `F7` to toggle the radar HUD.
- `[` / `]` lock the front / rear antenna readings.
- `\` cycles direction filter (BOTH → SAME → OPP).
- Run `/radarconfig` to enter UI edit mode — drag/resize the HUD; layout is saved to localStorage.
- Run `/test_wanted` for a fake wanted alert (dev only).

### 3.9 K9
- Press `INSERT` → spawn menu (pick breed/name).
- Use the radial / `HOME` for actions: follow, sit, attack, search, etc.
- Press `DELETE` to dismiss; record persists in `p_policejob_k9` while active.

### 3.10 CCTV (world cameras)
- Run `/cctv_creator` to place a camera (admin/officer with permission).
- Target the CCTV control point (the `cctv` zone in maps/departments) to open the viewer; cycle between placed cameras (stored in `p_policejob_cctv`).
- Shoot/break a camera → `broken` flag set; viewer skips broken cams.

### 3.11 Speed cameras
- `/speedcam_creator` places one; `/speedcam_manager` lists/removes.
- Drive past it over the threshold speed → fine triggered (or alert, depending on config).

### 3.12 Traffic management
- `/trafficmenu` → place cones, barriers, road signs, spike strips.
- Test deploying and clearing layouts.

### 3.13 Objects menu
- `/openObjectMenu` → quick spawn deployable objects (medkit, ducktape, etc.).

### 3.14 Trunks
- `/trunk_editor` configures storage capacity per vehicle model.
- `/entertrunk` near a vehicle → enter the trunk; `/exittrunk` to leave.

### 3.15 Diving suit
- Use `police_diving_suit` / `diving_suit` item near water → suit equips, oxygen overlay.
- Press `G` to deactivate manually.

### 3.16 Prison system
- Press `F10` (`/jailhud`) to toggle the inmate HUD when jailed.
- `/prisontasks` (officer): patrol routes, cell inspections, headcount.
- `/prisonmanagement`: review/edit `p_policejob_prison_sentences`, `_jobs`.
- `/mugshot` near a player → takes mugshot (uploads via configured image API).

### 3.17 Hands up / megaphone / band / locker / mugshot
- `X` — hands up animation toggle.
- Megaphone item → press the on-screen prompt to broadcast voice.
- Locker zone — opens stash with prefix `p_policejob_locker_<id>`.
- Vests: use `vest_normal` / `vest_strong` → armor sets to corresponding value.

### 3.18 Garage / vehicleshop / impound / clamp
- Visit the police garage → spawn a service vehicle (per `spawnerMode` + `preconfiguredVehicles`).
- Vehicleshop blip/zone → buy a personal vehicle (writes to framework's `owned_vehicles` / `player_vehicles`).
- Impound zone → tow a nearby vehicle / retrieve impounded.
- Use `wheel_clamp` on a parked vehicle → clamp animation, vehicle becomes immobile until removed.

### 3.19 Wardrobe & departments
- Departments map (`maps/departments/fm-mrpd.lua`) defines garages, lockers, wardrobe, armories, evidence stashes — visit each blip in-game to confirm everything is reachable.

---

## 4. Testing checklist

- [ ] Database tables auto-created (or imported via [`install.sql`](install.sql))
- [ ] All inventory items installed (pick the right file from [`ITEMS/`](ITEMS/))
- [ ] `F6` police menu opens for cops, hidden for civilians
- [ ] Cuff / uncuff loop works, cuff_key gate respected
- [ ] Body cam + breathalyzer + camera item triggers UIs
- [ ] Helicam keys functional in air unit
- [ ] Vehicle radar HUD draggable via `/radarconfig`
- [ ] K9 spawn / dismiss / actions
- [ ] CCTV placement + viewer
- [ ] Speedcam triggers fine
- [ ] Prison: jail, jail HUD, mugshot, release, community service
- [ ] Wardrobe save/load/delete persists across reconnect
- [ ] Tracking band + vehicle tracker visible on map
- [ ] Garage spawn + impound + clamp end-to-end
