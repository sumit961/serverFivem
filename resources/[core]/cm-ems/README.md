# cm-ems

F6 or `/ems` opens the organization-based EMS dashboard. Membership is always verified server-side; opening the dashboard also repairs a stale replicated member state after resource or character reloads.

## v5 mission system

- Patient transport uses a verified ambulance passenger seat and completes with a hospital-bay staff handoff, so the NPC does not need to be escorted through the hospital to a bed.
- Patient calls vary the patient model and health-only condition briefing, outdoor scenes add local safety props, and completion shows a server-calculated response grade and elapsed time.

- `/ems` → Employee Tasks contains scheduled missions, live public NPC emergencies and nearby co-op crews.
- One medic starts or accepts a call; nearby on-duty medics can join the same route.
- Any crew member may complete a stage, but only one stage action can run at a time.
- A medic must complete at least one stage to receive mission money, XP and task credit.
- Automatic NPC emergencies are created only while EMS is on duty and expire if nobody accepts.
- F11 → Quick Tools → Open EMS Management → Administration contains Mission Studio.
- Mission Studio saves custom multi-stage routes to the database. Choose **Place in world**, move to the route point, then press **E** to capture it.
- `sql/008_coop_mission_studio_v5.0.0.sql` is optional because startup creates the tables automatically.

The unique EMS leader automatically receives every permission declared in `Config.Permissions`; stored rank JSON cannot remove leader authority.

Activity logs are stored in `cm_ems_activity` and are returned to the NUI only for administrators or EMS ranks granted `ems.view_logs`. Assign that permission through **Ranks & access**.

Server-authoritative single EMS organization for the CM Framework.

## First release

- Exactly one Emergency Medical Services organization.
- One unique leader assigned from the `cm-admin` Developer launcher.
- Default EMS ranks plus server-authoritative custom rank management.
- G-menu invitation, promotion, demotion, and removal actions.
- Persistent duty state and a per-member EMS clothing wardrobe (see **Duty clothing** below).
- Going on duty applies the member's chosen EMS clothing; going off duty restores their own pre-duty outfit.

## Permissions

- Admin: `ems.admin.manage`
- Rank permissions: `ems.invite`, `ems.kick`, `ems.promote`, `ems.demote`, `ems.manage_outfits`, `ems.manage_ranks`, `ems.manage_permissions`, `ems.view_members`, `ems.view_logs`, `ems.manage_vehicles`, `ems.spawn_vehicles`, `ems.view_member_map`, `ems.set_meeting`.

## Duty clothing

The "Duty outfits" page is a small wardrobe, not a fixed uniform. It never touches the inventory — clothing is applied straight to the ped and always reverts to the member's own clothes the instant they go off duty (or the moment a live NUI pick swaps it while still on duty).

- **Presets** — anyone with `ems.manage_outfits` wears whatever they want, names it, and saves it from the **Duty outfits** page (`cm_ems_outfit_presets`, keyed by sex + name, up to 12 per sex). They can update a preset from their current clothing or delete it later.
- **Choosing a look** — any EMS member browses the presets for their own character model and clicks **Wear**. Their pick is remembered per character (`cm_ems_member_outfit`) so it's applied automatically the next time they go on duty — no need to re-pick every session.
- **Going on duty** resolves clothing server-side: the member's own chosen preset if it still exists, else the oldest preset available for their sex. If no preset has been configured yet for that sex, going on duty is blocked with a message asking a manager to save one first (same fail-closed behaviour as the original single-uniform system).
- Servers upgrading from the earlier single-uniform system have their existing male/female uniform copied once into a `"Default"` preset; the old `cm_ems_outfits` table is left in place, unused.

## Fleet vehicles

Vehicle *appearance* (model, label, category, captured image, paint/livery/wheels/tyres/etc) is configured entirely in `rn-vehicleshop`'s `/vehicleadmin` by setting a vehicle's catalog status to **"EMS fleet vehicle"**. cm-ems never stores its own copy of any of that — it reads it live via `rn-vehicleshop`'s `GetEmsCatalog` export, so re-customizing a vehicle there takes effect on the next spawn with no separate sync step.

cm-ems's Fleet tab only owns what's EMS-specific, stored in `cm_ems_fleet_vehicles` (keyed by model):
- **Spawn location** — set via the **H** key, not a form. Spawn the vehicle once (the first spawn drops it at your own position if it has no saved location yet), drive it to where it should live, then press **H** while in the driver's seat to save or update that spot. Car vs. helicopter is auto-detected from the vehicle's GTA class at that moment — there's no manual picker.
- **Minimum rank tier** — set inline from the Fleet list by anyone with `ems.manage_vehicles` (0 = any rank with `ems.spawn_vehicles`). The EMS leader can always spawn and drive everything regardless of tier.

Ranks with `ems.spawn_vehicles` (and on duty) can call any rank-qualifying, already-configured vehicle at its saved location. Each configured model owns one permanent `cm_owned_vehicles.id`, stored as `cm_ems_fleet_vehicles.vehicle_id`. A normal recall preserves the same live entity and network identity. If its physical entity is missing—or an older spawn is still quarantined with an unverified condition—EMS preserves the database vehicle and rebuilds only the entity through the same client-assisted create/finalize/promote pipeline used by `cm-house` garages.

**Driving is rank-gated, not just spawning.** Every client continuously locks the doors of nearby EMS fleet vehicles (`SetVehicleDoorsLockedForPlayer`, the same convention `cm-vehicles` already uses to protect owned vehicles) for players who aren't on duty or don't meet that vehicle's minimum tier. This is a client-side convention, not a hard anti-cheat guarantee — consistent with how the rest of the codebase already treats this native.

## Exports

- `GetMember(characterId)`
- `HasPermission(characterId, permission)`
- `IsOnDuty(characterId)`
- `CreateAmbulanceCall(source, details)` — creates a rate-limited dispatch call using the server-observed player position.

## Ambulance dispatch

- Players request medical help with `/ambulance [optional details]`.
- Only on-duty ranks with `ems.receive_dispatch` receive the dispatch card, notification and map blip.
- Press **F10** to open the live emergency-call board.
- Press **Y** to accept the newest call and set a GPS route.
- A call can be assigned to only one medic; `ems.manage_dispatch` allows removal of active calls.
- The cm-playerdata death-screen ambulance button creates the same permissioned dispatch call.
- Hospital respawn or revival resolves the call, alerts its assigned medic, and clears the dispatch GPS.
- If no dispatch-qualified EMS member is on duty, a temporary government doctor and ambulance respond automatically.
- Normal government EMS arrival is targeted for two minutes after the original call.
- Nearby government-doctor calls in the same routing bucket share one doctor within 40 metres; the doctor patches each downed caller in sequence.
- AI-claimed calls cannot be taken by player EMS. After finishing its queue, the doctor waits 30 seconds for additional nearby calls before leaving.
- After treatment, the ambulance drives away and both NPC entities are removed only after no connected player can still see them for 2.5 seconds.
- Ranks with `ems.send_gov_doctor` can send the government doctor from the F10 call row.
- Patients and dispatch-qualified EMS members receive live map positions for assigned player and government responders.
- Assigned medics can request priority backup with **B** by default.
- Authorized on-duty medics can activate an EMS panic with **F9** by default.
- Government-doctor auto response can be limited by
  `Config.Dispatch.governmentDoctor.minimumOnDutyEMS`.
- Calls are held in server memory for ten minutes and do not require a database migration.
- Creation and acceptance are recorded in `cm_ems_activity`; coordinates and server session IDs are not written to the activity detail.

## Simple patch and revive

- Look at a nearby player and press **X** to patch or revive them.
- The medic and patient receive synchronized progress feedback; unconscious
  patients use CPR presentation.
- A replicated treatment marker tells other EMS that the patient is already
  being treated, while the server owns the lock and cooldown.
- Successful revives connect to the patient's active dispatch incident and
  award reward, XP and task progress once per death.
- The G-menu can optionally load an unconscious player directly into the
  nearest configured ambulance.

## Installation

Place `ensure cm-ems` after `cm-admin`, `cm-playerdata`, and `cm-ui`. Tables are created safely at startup; `sql/001_cm_ems.sql` is supplied for manual installation.
