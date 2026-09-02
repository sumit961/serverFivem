Config = {}

Config.PlayerDataResource = 'cm-playerdata'
Config.AdminResource = 'cm-admin'
Config.AdminPermission = 'police.admin.manage'
Config.VehiclesResource = 'cm-vehicles'
Config.ShopResource = 'rn-vehicleshop'
-- This organization's own id, used to self-register with cm-admin's
-- centralized Organizations registry (exports['cm-admin']:RegisterOrganization)
-- and to ask it whether a character already belongs to a different
-- registered organization (exports['cm-admin']:FindRivalMembership) --
-- see server/main.lua.
Config.OrganizationId = 'police'
Config.MenuCommand = 'police'
Config.MenuKey = 'F6'
-- Dedicated Police administration entry; server permission is checked before
-- the admin workspace can be opened.
Config.AdminMenuCommand = 'policeadmin'
Config.InviteSeconds = 60
-- Default key for the cuff/uncuff bind. cm-law and cm-police both ship 'X',
-- which gives players two entries on the same key in the keybind settings.
-- The shared cmCuffed statebag means the systems interoperate correctly
-- either way -- this only exists so one of them can be moved off X without
-- editing client code. Players can also rebind it themselves in Settings.
Config.CuffKey = 'X'
Config.LogLimit = 100

-- Retention sweeps (server/retention.lua). Body-cam and impound captures are
-- written into html/img/bodycam/ by screenshot-basic and were never cleaned
-- up, so the folder grew without limit and shipped to every joining player.
Config.EvidenceRetentionDays = 30   -- delete cm_police_evidence rows + their .jpg after this many days
Config.LogRetentionDays = 90        -- delete cm_police_activity rows after this many days
Config.IncidentRetentionDays = 30   -- delete closed/expired dispatch calls after this many days
Config.RetentionSweepMs = 21600000  -- how often to sweep (6 hours)

Config.Permissions = {
    ['police.invite'] = 'Invite members',
    ['police.kick'] = 'Remove members',
    ['police.promote'] = 'Promote members',
    ['police.demote'] = 'Demote members',
    ['police.manage_outfits'] = 'Manage duty outfits',
    ['police.manage_ranks'] = 'Create, edit and delete ranks',
    ['police.manage_permissions'] = 'Assign rank permissions',
    ['police.view_members'] = 'View member roster',
    ['police.view_logs'] = 'View activity logs',
    ['police.manage_vehicles'] = 'Manage Police vehicles',
    ['police.spawn_vehicles'] = 'Spawn Police fleet vehicles',
    ['police.view_member_map'] = 'View Police members on map',
    ['police.set_meeting'] = 'Set Police meeting point',
    ['police.suspend_members'] = 'Suspend and reinstate Police members',
    ['police.cuff'] = 'Cuff, escort and transport suspects',
    ['police.book'] = 'Book and release suspects from holding',
    ['police.manage_booking'] = 'Configure the holding cell location',
    ['police.cite'] = 'Issue citations',
    ['police.impound'] = 'Impound and tow vehicles',
    ['police.radar'] = 'Use the speed radar',
    ['police.spike'] = 'Deploy spike strips',
    ['police.mdt'] = 'Use the MDT records lookup',
    ['police.receive_dispatch'] = 'Receive 911 dispatch calls',
    ['police.manage_armory'] = 'Manage armory weapons, ammunition, and vests',
    ['police.manage_alpr'] = 'Manage ALPR camera locations',
    ['police.k9'] = 'Deploy and command a K9 unit',
    ['police.sign_off_cadets'] = 'Sign off cadets from FTO restrictions',
    ['police.manage_impound'] = 'Configure Impound Operator locations',
    ['police.barricade'] = 'Deploy and recall barricades',
    ['police.manage_barricades'] = 'Configure the barricade prop model',
    ['police.clamp'] = 'Apply and remove wheel clamps',
}

-- Fixed organization ranks for the first Police release. Leader is unique
-- and can only be assigned through the server-authoritative admin flow.
-- Fully editable afterwards through Ranks & Permissions (same as EMS).
Config.Ranks = {
    { tier = 100, name = 'Police Chief', leader = true, permissions = 'ALL' },
    { tier = 80, name = 'Captain', permissions = {
        'police.invite', 'police.kick', 'police.promote', 'police.demote',
        'police.manage_outfits', 'police.manage_ranks', 'police.manage_permissions',
        'police.view_members', 'police.view_logs', 'police.manage_vehicles',
        'police.spawn_vehicles', 'police.view_member_map', 'police.set_meeting',
        'police.suspend_members', 'police.cuff', 'police.book', 'police.manage_booking', 'police.cite', 'police.impound', 'police.radar', 'police.spike', 'police.mdt', 'police.receive_dispatch', 'police.manage_armory', 'police.manage_alpr', 'police.k9', 'police.sign_off_cadets', 'police.manage_impound', 'police.barricade', 'police.manage_barricades', 'police.clamp',
    } },
    { tier = 50, name = 'Sergeant', permissions = {
        'police.invite', 'police.view_members', 'police.view_logs',
        'police.spawn_vehicles', 'police.view_member_map', 'police.set_meeting', 'police.cuff', 'police.book', 'police.cite', 'police.impound', 'police.radar', 'police.spike', 'police.mdt', 'police.receive_dispatch', 'police.k9', 'police.barricade', 'police.clamp',
    } },
    { tier = 20, name = 'Officer', permissions = { 'police.view_members', 'police.spawn_vehicles', 'police.cuff', 'police.book', 'police.cite', 'police.impound', 'police.radar', 'police.spike', 'police.mdt', 'police.receive_dispatch', 'police.k9', 'police.barricade', 'police.clamp' } },
    { tier = 1, name = 'Cadet', permissions = { 'police.view_members', 'police.cuff', 'police.book', 'police.cite', 'police.impound', 'police.radar', 'police.spike', 'police.mdt', 'police.receive_dispatch', 'police.k9', 'police.barricade', 'police.clamp' } },
}

-- Booking / holding cell (Config.Permissions.police.book gates who can use
-- it, police.manage_booking gates who can set the holding cell location).
-- No item/inventory dependency, matching Cuffing & Arrest's standing
-- "no item-gated police tools" instruction.
Config.Booking = {
    MinutesPerWantedStar = 15, -- 1 star = 15 min, 5 stars = 75 min, 6 stars = 90 min
    BookingRadius = 8.0,
    HandoffTimeoutMs = 10000,
    -- Used only to warn administrators before saving a jail intake outside
    -- the configured CM Prison area. Actual confinement uses the admin-set
    -- jail spawns owned by cm-prison.
    PrisonArea = { Label = 'Alcatraz', X = 3945.0, Y = 20.0, Z = 22.0, Radius = 180.0 },
}

Config.ServiceNpc = {
    Model = 's_f_y_cop_01',
    Name = 'Officer Morgan',
    Role = 'Police Front Desk',
    InteractDistance = 2.5,
    DrawDistance = 7.0,
    OrganizationLabel = 'Los Santos Police Department',
    IdleScenario = 'WORLD_HUMAN_CLIPBOARD',
    Greetings = {
        morning = 'Good morning. Welcome to the Police Department. How may I assist you?',
        afternoon = 'Good afternoon. What Police service do you need today?',
        evening = 'Good evening. The front desk is available. How can I help?',
        wanted = 'Remain calm and keep your hands visible. I can process a voluntary surrender.',
        officer = 'Welcome back, officer. How can the front desk assist you?',
    },
}

Config.FacilityNpcs = {
    InteractDistance = 2.5,
    DrawDistance = 7.0,
    ArmoryModel = 's_m_y_cop_01',
    StorageModel = 's_m_y_cop_01',
    ArmoryName = 'Officer Hayes',
    ArmoryRole = 'Police Quartermaster',
    StorageName = 'Officer Brooks',
    StorageRole = 'Police Storekeeper',
    StorageSlots = 30,
}

Config.JailNpc = {
    Name = 'Officer Daniels',
    Role = 'Prison Intake Officer',
    InteractDistance = 2.5,
    DrawDistance = 6.0,
}

-- Miranda rights -- shown to a suspect the moment they're cuffed (see
-- server/cuffs.lua), purely a roleplay flavor prompt, admin-editable text.
Config.Miranda = {
    Text = 'You have the right to remain silent. Anything you say can and will be used against you in a court of law. You have the right to an attorney.',
}

-- Tickets / citations (Config.Permissions.police.cite gates who can issue
-- them). Works on any nearby player, cuffed or not -- unlike Booking, this
-- isn't location-anchored. Fines are deducted from the target's bank and
-- deposited into the Police department fund (cm_police_organization.fund_balance),
-- never the issuing officer -- see server/citations.lua. A starting list,
-- fully admin-adjustable by editing this file.
Config.Citations = {
    Violations = {
        -- jailMinutes is a SUGGESTED sentence only (MDT Phase 2) -- 0 for a
        -- pure infraction. It does not auto-book anyone; the officer still
        -- manually books through the existing G-menu booking system; the
        -- authoritative wanted-star rating determines the final sentence.
        { id = 'speeding', label = 'Speeding', fine = 250, jailMinutes = 0 },
        { id = 'reckless_driving', label = 'Reckless Driving', fine = 500, jailMinutes = 10 },
        { id = 'failure_to_comply', label = 'Failure to Comply', fine = 300, jailMinutes = 10 },
        { id = 'no_license', label = "No Driver's License", fine = 150, jailMinutes = 0 },
        { id = 'illegal_parking', label = 'Illegal Parking', fine = 100, jailMinutes = 0 },
        { id = 'resisting_arrest', label = 'Resisting Arrest', fine = 750, jailMinutes = 20 },
    },
}

-- Vehicle impound & tow (Config.Permissions.police.impound gates who can
-- use it). Officers must physically deliver a vehicle with an approved tow
-- truck to the configured kiosk/drop-off before its persistent state changes.
-- Completing delivery despawns it and flips cm-vehicles to IMPOUND; paying to release it
-- just flips that state back to STORED, so it becomes retrievable through
-- cm-vehicles' own normal retrieval system. See server/impound.lua.
Config.Impound = {
    Fee = 750, -- flat fee, same economy scale as citations
    MaxDistance = 8.0, -- how close an officer must be to a vehicle to impound/tow it
    -- Public release kiosk (Config.Permissions.police.manage_impound gates who
    -- can set its location). Release fails closed until a Captain sets it;
    -- citizens must always be physically present at the configured kiosk.
    KioskRadius = 2.5,
    KioskInteractKey = 38, -- E (INPUT_CONTEXT)
    KioskBlipSprite = 68,
    KioskBlipColour = 5,
    DropoffRadius = 18.0,
    TowAttachDistance = 10.0,
    TowModels = { 'towtruck', 'towtruck4' },
    OperatorModel = 's_m_y_cop_01',
    OperatorName = 'Officer Martinez',
    OperatorRole = 'Impound Operator',
    OperatorDrawDistance = 7.0,
}

-- Speed radar (Config.Permissions.police.radar gates who can use it).
-- Handheld/aim-based only, display-only -- no auto-citation (the officer
-- still has to pull the vehicle over and use the existing Citations
-- G-menu). Unit/multiplier convention matches cm-hud's own speedometer
-- (cm-hud/client/main.lua). See client/radar.lua.
Config.Radar = {
    Unit = 'KM/H', -- 'MPH' or 'KM/H'
    MaxDistance = 150.0,
    UpdateIntervalMs = 200,
    -- Held device prop, purely visual (no gameplay effect) -- a base-game
    -- model, no custom asset/weapons.meta registration needed. Bone id and
    -- offset/rotation shape match the already-proven attachProp helper in
    -- cm-vehicles/client/menu.lua (57005 = right hand).
    HandProp = {
        Model = 'prop_cs_tablet',
        Bone = 57005,
        Offset = vector3(0.35, 0.02, -0.02),
        Rotation = vector3(-130.0, -50.0, 0.0),
    },
}

-- Contextual E-prompt for dragging/seating a cuffed suspect (client/escort.lua).
-- Additive on top of the G-menu's own Grab/Release/Put in Vehicle/Take Out
-- options (client/gmenu.lua, server/cuffs.lua) -- both paths call the exact
-- same server-validated extension actions.
Config.Cuffs = {
    InteractDistance = 2.5, -- metres, same rough scale as cm-ems's stretcher interactDistance
    VehicleSeatDistance = 6.0, -- matches server/cuffs.lua's own nearbyFreeSeatVehicle radius
}

-- Spike strips (Config.Permissions.police.spike gates who can use it). No
-- server-side collision detection exists anywhere in this codebase, so
-- tire-bursting is applied client-side by each driver's own client to
-- their own vehicle only, on contact with a tagged strip object -- the
-- same shape every FiveM resource that implements this uses. See
-- server/spikes.lua and client/spikes.lua.
Config.SpikeStrips = {
    Model = 'p_ld_stinger_s', -- base-game GTA prop, no stream/asset files needed
    DeployDistance = 3.0, -- metres in front of the officer
    MaxActive = 1, -- per-officer cap on simultaneously deployed strips -- recall the current one before placing another
    LifetimeMs = 120000, -- auto-despawn an unclaimed strip after this long
    BurstDistance = 0.6, -- metres from a wheel bone to the strip to burst that tyre
    -- How long the server holds an officer's reserved slot open while they're
    -- still positioning the placement preview (client/spikes.lua), and how
    -- long the client itself will let placement run before auto-cancelling.
    -- Both sides use this SAME value so they can never silently disagree --
    -- previously the server's reservation (10s, hardcoded) could expire
    -- while the client had no time limit at all, letting an officer confirm
    -- placement after the server had already freed the slot, creating a
    -- real, networked, un-recallable strip the server never tracked.
    PlacementTimeoutMs = 45000,
}

-- Barricades (Config.Permissions.police.barricade gates who can deploy
-- one; police.manage_barricades gates who can change the prop model).
-- Unlike spike strips, a barricade is solid (collision left on once
-- placed) and meant to stay up until an officer clears it -- LifetimeMs
-- here is a long safety-net sweep (leak prevention if an officer
-- disconnects mid-scene), not a real gameplay timer. See
-- server/barricades.lua and client/barricades.lua.
Config.Barricades = {
    DeployDistance = 3.0, -- metres in front of the officer at the start of placement
    MaxActive = 2, -- per-officer cap on simultaneously deployed barricades
    LifetimeMs = 1800000, -- 30 min safety-net auto-clear, not a real gameplay timer
    PlacementTimeoutMs = 45000, -- matches spike strips' own value
    -- Seeds cm_police_barricade_catalog only if it's ever completely empty
    -- (same "seed fresh installs, never touch existing rows" spirit as
    -- Config.Ranks) -- admins add/remove further models from the F7
    -- dashboard's Barricades card afterwards.
    DefaultModels = { 'prop_barrier_work05' },
}

-- Wheel clamp (Config.Permissions.police.clamp gates who can toggle it).
-- prop_clamp is GTA Online's own vanilla wheel-clamp prop -- no custom
-- asset/ytyp registration needed. Session-only physical state, same class
-- as spike strips/barricades -- nothing persisted. See server/clamp.lua
-- and client/clamp.lua.
Config.Clamp = {
    Model = 'prop_clamp',
    Bone = 'wheel_lf',
    Offset = vector3(-0.1, 0.1, -0.2),
    Rotation = vector3(180.0, 200.0, 90.0),
    MaxDistance = 3.0, -- how close an officer must be to toggle it
}

-- Shared by client/placement.lua for BOTH spike strips and barricades --
-- how close/far the officer can push the placement preview from
-- themselves with the scroll wheel. Previously arrow-key nudging had no
-- distance limit at all; this is the actual fix for that.
Config.Placement = {
    MinDistance = 1.0,
    MaxDistance = 5.0,
}

-- MDT records lookup (Config.Permissions.police.mdt gates who can use it --
-- the same permission covers both searching and adding notes). A new tab
-- inside the existing F7 dashboard, not a G-menu action or command -- see
-- server/mdt.lua.
Config.Mdt = {
    SearchLimit = 20,
    -- Must never exceed cm_police_notes.note's column width
    -- (VARCHAR(500) in server/mdt.lua's CREATE TABLE) -- raising this alone
    -- without also widening that column causes silent over-truncation (or a
    -- DB error, depending on sql_mode) instead of the intended Lua-side
    -- truncation just below where this value is used.
    NoteMaxLength = 500,
    -- Tracked/settable in the MDT (Phase 2), and enforced for driving
    -- (Phase 3, client/licenses.lua) and firearms purchases (Phase 3+4,
    -- cm-gunstore). An officer can still manually cite "No Driver's
    -- License" the same way as before any of this existed.
    LicenseTypes = { 'drivers', 'firearms', 'commercial', 'hunting', 'pilot', 'boating' },
    -- Only 'firearms' has an actual purchase flow right now (the
    -- cm-gunstore vendor NPC's "Buy a firearms license" dialog option) --
    -- the rest are priced so a future vendor for them is a config-only
    -- addition, not a new schema change.
    LicensePrices = { firearms = 2500, drivers = 1000, commercial = 5000, hunting = 500 },
    -- Use-of-force reporting: same permission tier as notes/evidence/BOLO
    -- (police.mdt) -- record-keeping, not enforcement. Filed against a free-
    -- text subject (name/CID/description), not necessarily an MDT profile.
    UseOfForceTypes = { 'Firearm', 'Taser', 'Baton', 'Empty Hand', 'K9', 'Vehicle', 'Other' },
}

-- 911/dispatch (Config.Permissions.police.receive_dispatch gates who
-- receives a call). /reportcrime is deliberately its OWN command, not
-- '911' -- cm-ems already owns a working '911' RegisterCommand, and
-- registering a second one here would silently override theirs (FiveM
-- keeps only the last registration of a given command name). See
-- server/dispatch.lua.
Config.Dispatch = {
    Cooldown = 30000, -- ms between /reportcrime uses per player, anti-spam
    ExpireAfterMs = 600000, -- 10 minutes, auto-expire a call nobody resolved
    BlipSprite = 161,
    BlipColour = 3,
    HistoryLimit = 50,
    -- Automatic "heavy gunfire" calls (client/gunfire.lua): each client
    -- watches its OWN player's shots (same IsPedShooting polling shape
    -- cm-inventory's own ammo tracker already uses, ~120ms per tick) and
    -- reports once it crosses this threshold within the rolling window.
    -- Anonymous by design (a real gunfire-detection system can't identify
    -- who's shooting) -- see server/dispatch.lua's reportGunfire handler.
    GunfireShotThreshold = 8,
    GunfireWindowMs = 10000,
    GunfireCooldownMs = 120000, -- per-player, prevents one gunfight spamming repeat calls
    GunfireCoordinateTolerance = 12.0, -- reject spoofed client coordinates; the server position is authoritative
}

-- Backup request (J quick-menu). Deliberately much lighter than a dispatch
-- call: no accept/resolve workflow, no persisted table -- just a
-- rate-limited broadcast with a client-side blip that expires on its own.
-- See server/dispatch.lua's requestBackup callback and client/dispatch.lua's
-- backupRequested handler.
Config.Backup = {
    Cooldown = 60000, -- ms between backup requests per officer
    PanicCooldown = 30000,
    PanicKey = '', -- no physical default; F9 is shared organization dispatch
    BlipLifetimeMs = 60000,
    BlipSprite = 161, -- same sprite family as the dispatch call blip
    BlipColour = 1, -- red -- visually distinct from Config.Dispatch.BlipColour (3)
}

-- ALPR (automatic license plate reader) cameras (Config.Permissions.police.manage_alpr
-- gates who can place/remove them). Fixed installations, not officer-
-- deployable -- see server/alpr.lua. Reads the vehicle's rendered plate
-- text (police-issued license_number if registered, blank otherwise) and
-- cross-references it against active BOLO plates only -- an unregistered
-- vehicle alone never triggers an alert.
Config.Alpr = {
    DetectionRadius = 20.0, -- metres from a camera a passing vehicle is read at
    CheckIntervalMs = 3000,
    AlertCooldownMs = 300000, -- 5 min per camera+plate, prevents repeat-spam while a flagged car idles nearby
}

-- K9 unit (Config.Permissions.police.k9 gates who can deploy/command one,
-- granted to every rank same as radar/spike -- a normal patrol tool, not a
-- command-staff privilege). The dog is a server-owned networked companion
-- visible to players in the handler's routing bucket -- see
-- client/k9.lua. "Tracking" is a location reveal (GTA5-style wanted stars,
-- this session's system), not literal dog-runs-to-suspect AI pathing.
Config.K9 = {
    Model = 'a_c_shepherd', -- base-game GTA ped, no stream assets needed
    TrackRadius = 150.0,
    TrackUpdateMs = 5000,
    TrackDurationMs = 60000,
    CommandDistance = 35.0,
    ChaseDistance = 75.0,
    SearchDistance = 4.0,
    AttackDistance = 20.0,
    ThreatMemoryMs = 120000,
}

-- FTO/cadet mode: a brand-new Cadet (tier 1) starts restricted from the
-- higher-stakes tools (issuing fines, booking, impounding) until a
-- Captain+ signs them off (cm_police_members.fto_signed_off, gated by
-- police.sign_off_cadets). Lower-stakes tools (cuff/escort, MDT lookups,
-- radar/spike) stay available immediately -- restriction only applies to
-- actions with real financial/liberty consequences for another player.
Config.Fto = {
    RestrictedTier = 1, -- matches Config.Ranks' Cadet tier
}

-- Police Wardrobe dressing room (Duty Outfits tab, gated by the existing
-- police.manage_outfits permission). Camera framing numbers are nv_cloth's
-- own proven-tuned "body" preset (cl_camera.lua) reused directly rather
-- than guessed -- a torso-level framing matching the real in-game store's
-- own dressing-room screen. See client/wardrobe.lua.
Config.Wardrobe = {
    CameraDistance = 4.35,
    CameraHeightOffset = 0.18,
    CameraFov = 38.0,
    RotateSensitivity = 0.45,
    -- Wearing a duty preset only works while standing at this admin-placed
    -- NPC (police.manage_outfits sets its location) -- see server/wardrobe.lua
    -- and client/wardrobe.lua. mp_m_shopkeep_01 is a real base-game ped, no
    -- custom asset needed.
    NpcModel = 'mp_m_shopkeep_01',
    NpcName = 'Officer Taylor',
    NpcRole = 'Police Wardrobe Specialist',
    NpcInteractDistance = 2.5,
    MaxQuickSlots = 5, -- personal pointers into the shared preset list
}

-- Fleet vehicle configurator/spawner (Config.Permissions.police.manage_vehicles /
-- police.spawn_vehicles above gate who can use it). The model picker itself is
-- populated live from rn-vehicleshop's "Police fleet vehicle" catalog status
-- (GetPoliceCatalog export), not from a config list.
Config.VehicleFleet = {
    maxPresets = 24,
    spawnCooldownMs = 15000,
}
