Config = {}

Config.PlayerDataResource = 'cm-playerdata'
Config.AdminResource = 'cm-admin'
Config.InventoryResource = 'cm-inventory'
-- This organization's own id, used to self-register with cm-admin's
-- centralized Organizations registry (exports['cm-admin']:RegisterOrganization)
-- and to ask it whether a character already belongs to a different
-- registered organization (exports['cm-admin']:FindRivalMembership) --
-- see server/main.lua.
Config.OrganizationId = 'ems'
Config.AdminPermission = 'ems.admin.manage'
Config.MenuCommand = 'ems'
Config.MenuKey = 'F7' -- physical mapping is owned centrally by cm-police/client/org_keys.lua
Config.InviteSeconds = 120
Config.LogLimit = 100

-- Public hospital appearance services. cm-characters remains authoritative
-- for editing and saving the active character's appearance.
Config.AppearanceServices = {
    {
        id = 'pillbox_gender',
        name = 'Dr. Maya Carter',
        label = 'Gender Consultation',
        service = 'gender',
        model = 's_f_y_scrubs_01',
        coords = vector4(326.3022, -571.8286, 43.2676, 159.8508),
    },
    {
        id = 'pillbox_surgery',
        name = 'Dr. Ethan Hayes',
        label = 'DNA & Appearance',
        service = 'surgery',
        model = 's_m_m_doctor_01',
        coords = vector4(331.8241, -574.0176, 43.2677, 163.8636),
    },
    {
        id = 'sandy_gender',
        name = 'Dr. Olivia Morgan',
        label = 'Gender Consultation',
        service = 'gender',
        model = 's_f_y_scrubs_01',
        coords = vector4(1852.1561, 3705.7805, 38.5925, 216.7076),
    },
    {
        id = 'sandy_surgery',
        name = 'Dr. Noah Bennett',
        label = 'DNA & Appearance',
        service = 'surgery',
        model = 's_m_m_doctor_01',
        coords = vector4(1840.2535, 3699.7029, 38.5925, 218.7079),
    },
}

Config.Operations = {
    treatmentPrice = 250,
    deathRespawnPrice = 500,
    medicReward = 100,
    aiArrivalMs = 120000,
    sharedResponseRadius = 40,
    hospitalEnabled = true,
    autoDispatchEnabled = true,
}

-- Lightweight employee engagement. Tasks rotate automatically by date/week,
-- require real on-duty EMS actions, and pay to the employee's bank on claim.
Config.EmployeeTasks = {
    daily = {
        { id = 'daily_duty', metric = 'duty_minutes', label = 'Stay on duty', description = 'Complete 30 minutes of EMS duty.', target = 30, reward = 250 },
        { id = 'daily_calls', metric = 'dispatch_responses', label = 'Answer emergency calls', description = 'Respond to 2 unique dispatch incidents.', target = 2, reward = 350, permission = 'ems.receive_dispatch' },
        { id = 'daily_revives', metric = 'patient_revives', label = 'Revive patients', description = 'Revive 2 unconscious patients.', target = 2, reward = 500, permission = 'ems.treat_player' },
        { id = 'daily_reports', metric = 'medical_reports', label = 'Complete reports', description = 'Submit 1 medical report.', target = 1, reward = 250, permission = 'ems.write_medical_reports' },
        { id = 'daily_mission', metric = 'missions_completed', label = 'Complete an EMS mission', description = 'Finish 1 mission from the EMS mission board.', target = 1, reward = 400 },
    },
    weekly = {
        { id = 'weekly_duty', metric = 'duty_minutes', label = 'Weekly service', description = 'Complete 4 hours of EMS duty.', target = 240, reward = 2500 },
        { id = 'weekly_calls', metric = 'dispatch_responses', label = 'Weekly responder', description = 'Respond to 12 unique dispatch incidents.', target = 12, reward = 3000, permission = 'ems.receive_dispatch' },
        { id = 'weekly_revives', metric = 'patient_revives', label = 'Weekly lifesaver', description = 'Revive 10 unconscious patients.', target = 10, reward = 4000, permission = 'ems.treat_player' },
        { id = 'weekly_reports', metric = 'medical_reports', label = 'Weekly paperwork', description = 'Submit 5 medical reports.', target = 5, reward = 1500, permission = 'ems.write_medical_reports' },
        { id = 'weekly_missions', metric = 'missions_completed', label = 'Mission specialist', description = 'Finish 5 missions from the EMS mission board.', target = 5, reward = 3000 },
    },
}

-- EMS career progression is separate from organization ranks and permissions.
-- It rewards real work but never promotes a member or grants access by itself.
Config.EmployeeProgression = {
    xpByMetric = {
        dispatch_responses = 20,
        patient_revives = 40,
        medical_reports = 10,
    },
    levels = {
        { level = 1, xp = 0, label = 'Trainee Responder' },
        { level = 2, xp = 150, label = 'First Responder' },
        { level = 3, xp = 400, label = 'Emergency Medic' },
        { level = 4, xp = 800, label = 'Advanced Medic' },
        { level = 5, xp = 1400, label = 'Veteran Responder' },
        { level = 6, xp = 2200, label = 'Elite Lifesaver' },
    },
}

-- Simple field transport: J deploys/stores a stretcher and E pushes,
-- releases, loads or unloads it. Patient placement/removal is in the G menu.
Config.Stretcher = {
    enabled = true,
    model = 'v_med_bed2',
    deployKey = 'J',
    interactKey = 'E',
    maxDeployDistance = 3.0,
    interactDistance = 2.6,
    patientDistance = 4.0,
    vehicleDistance = 5.0,
    returnCommand = 'emsreturnstretcher',
    allowedVehicles = { 'ambulance' },
    -- While pushed, the stretcher follows the terrain in front of the medic;
    -- it is not attached to a body bone (which makes it bob like a held prop).
    pushDistance = 1.35,
    pushGroundClearance = 0.03,
    pushHeadingOffset = 180.0,
    patientOffset = { x = 0.0, y = 0.0, z = 0.78, rx = 0.0, ry = 0.0, rz = 90.0 },
    vehicleOffset = { x = 0.0, y = -1.25, z = 0.15, rx = 0.0, ry = 0.0, rz = 0.0 },
}

Config.HospitalAdmissions = {
    enabled = true,
    bayRadius = 22.0,
    hospitals = {
        {
            id = 'pillbox', label = 'Pillbox Hospital',
            bay = { x = 365.7646, y = -568.5619, z = 28.8474 },
            bed = { x = 316.9794, y = -583.0529, z = 43.2677, h = 269.6746 },
        },
        {
            id = 'sandy', label = 'Sandy Hospital',
            bay = { x = 1844.4478, y = 3689.9319, z = 24.1276 },
            bed = { x = 1849.9167, y = 3697.7371, z = 34.8925, h = 52.9699 },
        },
    },
}

-- Shared scene/hospital anchors for the "field response" mission shape
-- (treat on scene, load, drive to hospital, unload, walk to bed). Every
-- mission built with fieldResponseRoutes()/fieldTransportRoutes() below picks
-- a random scene from this pool each time it is offered, instead of a fixed
-- 1-2 hardcoded locations -- so the same mission stops landing in the same
-- spot run after run. All coordinates here are already in production use
-- elsewhere in this file (verified in-game), so this only recombines them.
local Hospitals = {
    pillbox = {
        name = 'Pillbox',
        pharmacy = { location = 'Pillbox Pharmacy', coords = { x = 311.2, y = -597.1, z = 43.28 } },
        depot = { location = 'Los Santos Medical Depot', coords = { x = 897.7, y = -1035.7, z = 35.1 } },
        checkIn = { location = 'Pillbox Hospital', coords = { x = 316.98, y = -583.05, z = 43.27 } },
        bay = { location = 'Pillbox Ambulance Bay', coords = { x = 365.7646, y = -568.5619, z = 28.8474 } },
        bed = { location = 'Pillbox Treatment Bed', coords = { x = 316.9794, y = -583.0529, z = 43.2677 }, heading = 269.6746 },
    },
    sandy = {
        name = 'Sandy',
        pharmacy = { location = 'Sandy Hospital', coords = { x = 1849.92, y = 3697.74, z = 34.89 } },
        depot = { location = 'Sandy Medical Depot', coords = { x = 1692.4, y = 3761.5, z = 34.71 } },
        checkIn = { location = 'Sandy Hospital', coords = { x = 1849.92, y = 3697.74, z = 34.89 } },
        bay = { location = 'Sandy Ambulance Bay', coords = { x = 1844.4478, y = 3689.9319, z = 24.1276 } },
        bed = { location = 'Sandy Treatment Bed', coords = { x = 1849.9167, y = 3697.7371, z = 34.8925 }, heading = 52.9699 },
    },
}

local FieldScenes = {
    { hospital = 'pillbox', location = 'Vespucci Boulevard', coords = { x = -285.8, y = -886.7, z = 31.08 } },
    { hospital = 'pillbox', location = 'La Puerta Freeway', coords = { x = -579.5, y = -1784.7, z = 22.5 } },
    { hospital = 'pillbox', location = 'East Vinewood Road', coords = { x = 1153.74, y = -772.74, z = 57.59 } },
    { hospital = 'pillbox', location = 'Davis Loading Dock', coords = { x = 1200.0, y = -1473.0, z = 34.86 } },
    { hospital = 'sandy', location = 'Harmony', coords = { x = 557.5, y = 2672.4, z = 42.16 } },
    { hospital = 'sandy', location = 'Sandy Shores Road', coords = { x = 1690.6, y = 3581.4, z = 35.62 } },
    { hospital = 'sandy', location = 'Sandy Medical Depot Yard', coords = { x = 1692.4, y = 3761.5, z = 34.71 } },
}

-- One route per scene, each stage built by buildStages(scene, hospital).
local function fieldTransportRoutes(scenes, hospitals, buildStages)
    local routes = {}
    for _, scene in ipairs(scenes) do
        local hospital = hospitals[scene.hospital]
        if hospital then routes[#routes + 1] = { patient = true, stages = buildStages(scene, hospital) } end
    end
    return routes
end

-- The common 5-stage shape shared by cardiac/overdose/collision/roadside/
-- workplace missions: treat on scene, load, drive to that scene's nearest
-- hospital, unload, walk the patient to a bed. Only the treat stage's label
-- and duration differ between mission types.
local function fieldResponseRoutes(scenes, hospitals, treatLabel, treatDuration)
    return fieldTransportRoutes(scenes, hospitals, function(scene, hospital)
        return {
            { type = 'treat', label = treatLabel, location = scene.location, coords = scene.coords, duration = treatDuration },
            { type = 'board_vehicle', label = 'Load the patient into an ambulance', location = scene.location, coords = scene.coords, duration = 4000, requireTransportVehicle = true },
            { type = 'transport', label = ('Drive to the %s ambulance bay'):format(hospital.name), location = hospital.bay.location, coords = hospital.bay.coords, duration = 3000, requireTransportVehicle = true },
            { type = 'hospital_handoff', label = 'Hand the patient to hospital staff', location = hospital.bay.location, coords = hospital.bay.coords, duration = 5000 },
        }
    end)
end

-- On-duty employees choose one mission from /ems > Employee Tasks. Routes are
-- deliberately lightweight: GPS checkpoints, short actions, ambulance or
-- helicopter validation, a visible local patient, and server-paid rewards.
Config.EMSMissions = {
    cooldownSeconds = 900,
    cancelledRetrySeconds = 60,
    stageRadius = 18.0,
    -- Releases a co-op objective automatically if a client disconnects,
    -- cancels a progress action or never sends the completion callback.
    actionLockGraceMs = 15000,
    allowedTransportVehicles = { 'ambulance', 'polmav' },
    coOp = {
        enabled = true,
        maximumMedics = 6,
        joinRadius = 300.0,
        -- Every medic must complete at least one objective to receive money,
        -- XP and daily/weekly task credit. This prevents idle reward farming.
        requireContributionForReward = true,
    },
    automaticEmergencies = {
        enabled = true,
        minimumIntervalSeconds = 480,
        maximumIntervalSeconds = 900,
        lifetimeSeconds = 1200,
        maximumOpenCalls = 3,
        -- Calls are only generated while at least one conscious EMS employee
        -- is online and on duty.
        requireOnDutyEMS = true,
        notificationSeconds = 20,
    },
    -- One admin-placed NPC hands each member a single random mission per
    -- real calendar day at a boosted reward, on top of the self-service
    -- board above -- see server/missions.lua's requestDailyMission.
    dailyNpcMission = {
        npcModel = 's_m_m_paramedic_01',
        interactDistance = 2.5,
        rewardMultiplier = 3,
    },
    definitions = {
        {
            id = 'medical_supply', label = 'Medical Supply Delivery', category = 'SUPPLY',
            description = 'Collect a sealed cold-chain supply crate and deliver it to the requesting hospital before stock runs out.', reward = 700, xp = 35,
            routes = {
                { stages = {
                    { type = 'pickup', label = 'Collect sealed supplies', location = 'Los Santos Medical Depot', coords = { x = 897.7, y = -1035.7, z = 35.1 }, duration = 6000 },
                    { type = 'deliver', label = 'Deliver supplies to Pillbox Hospital', location = 'Pillbox Hospital', coords = { x = 316.98, y = -583.05, z = 43.27 }, duration = 5000 },
                } },
                { stages = {
                    { type = 'pickup', label = 'Collect sealed supplies', location = 'Sandy Medical Depot', coords = { x = 1692.4, y = 3761.5, z = 34.71 }, duration = 6000 },
                    { type = 'deliver', label = 'Deliver supplies to Sandy Hospital', location = 'Sandy Hospital', coords = { x = 1849.92, y = 3697.74, z = 34.89 }, duration = 5000 },
                } },
            },
        },
        {
            id = 'urgent_medicine', label = 'Urgent Medicine Run', category = 'URGENT',
            description = 'Dispatch flags a patient in respiratory distress. Collect emergency medication and administer it before the window closes.', reward = 950, xp = 50, timeLimitSeconds = 600,
            automaticEmergency = true,
            routes = fieldTransportRoutes(FieldScenes, Hospitals, function(scene, hospital)
                return {
                    { type = 'pickup', label = 'Collect emergency medication', location = hospital.pharmacy.location, coords = hospital.pharmacy.coords, duration = 5000 },
                    { type = 'treat', label = 'Administer medication to the waiting patient', location = scene.location, coords = scene.coords, duration = 8000 },
                }
            end),
        },
        {
            id = 'cardiac_arrest', label = 'Cardiac Arrest Call', category = 'CARDIAC',
            description = '911 caller reports a collapse, not breathing. Begin CPR immediately -- every minute without compressions lowers survival odds.',
            reward = 1800, xp = 115, timeLimitSeconds = 480, automaticEmergency = true,
            routes = fieldResponseRoutes(FieldScenes, Hospitals, 'Begin CPR and stabilize the patient', 15000),
        },
        {
            id = 'overdose_response', label = 'Overdose Response', category = 'OVERDOSE',
            description = 'A bystander found someone unresponsive and barely breathing. Administer emergency reversal medication and get them to hospital.',
            reward = 1400, xp = 85, timeLimitSeconds = 540, automaticEmergency = true,
            routes = fieldResponseRoutes(FieldScenes, Hospitals, 'Administer reversal medication', 7000),
        },
        {
            id = 'traffic_collision', label = 'Multi-Vehicle Collision', category = 'TRAUMA',
            description = 'A serious pileup has trapped an injured driver. Extricate and stabilize the patient before transporting them to hospital.',
            reward = 1600, xp = 100, automaticEmergency = true,
            routes = fieldResponseRoutes(FieldScenes, Hospitals, 'Extricate and stabilize the trapped patient', 14000),
        },
        {
            id = 'workplace_injury', label = 'Workplace Injury', category = 'INDUSTRIAL',
            description = 'A worker was hurt on site. Treat the injury on scene and complete a routine, non-urgent hospital transport.', reward = 1200, xp = 70,
            routes = fieldResponseRoutes(FieldScenes, Hospitals, 'Treat the injured worker', 10000),
        },
        {
            id = 'roadside_rescue', label = 'Roadside Rescue', category = 'LAND RESCUE',
            description = 'Stabilize an injured road user, load them and transport them to hospital.', reward = 1300, xp = 75,
            automaticEmergency = true,
            routes = fieldResponseRoutes(FieldScenes, Hospitals, 'Stabilize the injured patient', 10000),
        },
        {
            id = 'water_rescue', label = 'Water Rescue', category = 'WATER RESCUE',
            description = 'Recover and stabilize a patient near the water, then transport them to hospital.', reward = 1600, xp = 95,
            automaticEmergency = true,
            routes = {
                { patient = true, stages = {
                    { type = 'recover', label = 'Recover the patient from the shoreline', location = 'Del Perro Beach', coords = { x = -1605.2, y = -1076.7, z = 13.02 }, duration = 10000 },
                    { type = 'treat', label = 'Perform CPR and stabilize the patient', location = 'Del Perro Beach', coords = { x = -1605.2, y = -1076.7, z = 13.02 }, duration = 12000 },
                    { type = 'board_vehicle', label = 'Load the patient into an ambulance', location = 'Del Perro Beach', coords = { x = -1605.2, y = -1076.7, z = 13.02 }, duration = 4000, requireTransportVehicle = true },
                    { type = 'transport', label = 'Drive to the Pillbox ambulance bay', location = 'Pillbox Ambulance Bay', coords = { x = 365.7646, y = -568.5619, z = 28.8474 }, duration = 3000, requireTransportVehicle = true },
                    { type = 'hospital_handoff', label = 'Hand the patient to Pillbox staff', location = 'Pillbox Ambulance Bay', coords = { x = 365.7646, y = -568.5619, z = 28.8474 }, duration = 5000 },
                } },
            },
        },
        {
            id = 'mountain_rescue', label = 'Mountain Rescue', category = 'MOUNTAIN RESCUE',
            description = 'Locate a stranded hiker, stabilize them and evacuate by ambulance or helicopter.', reward = 1900, xp = 120,
            automaticEmergency = true,
            routes = {
                { patient = true, stages = {
                    { type = 'treat', label = 'Locate and stabilize the injured hiker', location = 'Mount Chiliad Trail', coords = { x = -425.2, y = 1596.8, z = 356.1 }, duration = 12000 },
                    { type = 'board_vehicle', label = 'Load the hiker into an EMS vehicle', location = 'Mount Chiliad Trail', coords = { x = -425.2, y = 1596.8, z = 356.1 }, duration = 5000, requireTransportVehicle = true },
                    { type = 'transport', label = 'Evacuate the hiker to the Sandy ambulance bay', location = 'Sandy Ambulance Bay', coords = { x = 1844.4478, y = 3689.9319, z = 24.1276 }, duration = 3000, requireTransportVehicle = true },
                    { type = 'hospital_handoff', label = 'Hand the hiker to Sandy staff', location = 'Sandy Ambulance Bay', coords = { x = 1844.4478, y = 3689.9319, z = 24.1276 }, duration = 5000 },
                } },
            },
        },
        {
            -- New coordinates (not yet used elsewhere in this config) --
            -- verify ped/vehicle spawn placement in-game before relying on
            -- this in production; automaticEmergency stays off until then.
            id = 'paleto_response', label = 'Paleto Bay Response', category = 'RURAL RESPONSE',
            description = 'A remote call from Paleto Bay -- the nearest hospital is a long drive away, so stabilize the patient thoroughly before transport.',
            reward = 1700, xp = 100, automaticEmergency = false,
            routes = {
                { patient = true, stages = {
                    { type = 'treat', label = 'Stabilize the patient', location = 'Paleto Bay Main Street', coords = { x = -448.9, y = 6008.6, z = 31.7 }, duration = 13000 },
                    { type = 'board_vehicle', label = 'Load the patient into an ambulance', location = 'Paleto Bay Main Street', coords = { x = -448.9, y = 6008.6, z = 31.7 }, duration = 4000, requireTransportVehicle = true },
                    { type = 'transport', label = 'Drive to the Sandy ambulance bay', location = 'Sandy Ambulance Bay', coords = { x = 1844.4478, y = 3689.9319, z = 24.1276 }, duration = 3000, requireTransportVehicle = true },
                    { type = 'hospital_handoff', label = 'Hand the patient to Sandy staff', location = 'Sandy Ambulance Bay', coords = { x = 1844.4478, y = 3689.9319, z = 24.1276 }, duration = 5000 },
                } },
            },
        },
        {
            -- New coordinates (not yet used elsewhere in this config) --
            -- verify ped/vehicle spawn placement in-game before relying on
            -- this in production; automaticEmergency stays off until then.
            id = 'farm_accident', label = 'Grapeseed Farm Accident', category = 'RURAL RESPONSE',
            description = 'A farm worker was hurt operating machinery out in Grapeseed. Treat the injury on scene, then make the long transport to hospital.',
            reward = 1500, xp = 90, automaticEmergency = false,
            routes = {
                { patient = true, stages = {
                    { type = 'treat', label = 'Treat the machinery injury', location = 'Grapeseed Farm Road', coords = { x = 2437.8, y = 4968.2, z = 46.55 }, duration = 12000 },
                    { type = 'board_vehicle', label = 'Load the patient into an ambulance', location = 'Grapeseed Farm Road', coords = { x = 2437.8, y = 4968.2, z = 46.55 }, duration = 4000, requireTransportVehicle = true },
                    { type = 'transport', label = 'Drive to the Sandy ambulance bay', location = 'Sandy Ambulance Bay', coords = { x = 1844.4478, y = 3689.9319, z = 24.1276 }, duration = 3000, requireTransportVehicle = true },
                    { type = 'hospital_handoff', label = 'Hand the patient to Sandy staff', location = 'Sandy Ambulance Bay', coords = { x = 1844.4478, y = 3689.9319, z = 24.1276 }, duration = 5000 },
                } },
            },
        },
        {
            id = 'hospital_transfer', label = 'Hospital Transfer', category = 'TRANSPORT',
            description = 'Collect a stable patient and complete a hospital-to-hospital transfer.', reward = 1100, xp = 65,
            routes = {
                { patient = true, stages = {
                    { type = 'pickup_patient', label = 'Check in and collect the transfer patient', location = 'Pillbox Hospital', coords = { x = 316.98, y = -583.05, z = 43.27 }, duration = 6000 },
                    { type = 'escort_patient', label = 'Escort the patient to the Pillbox ambulance bay', location = 'Pillbox Ambulance Bay', coords = { x = 365.7646, y = -568.5619, z = 28.8474 }, duration = 3000 },
                    { type = 'board_vehicle', label = 'Load the patient into an EMS vehicle', location = 'Pillbox Ambulance Bay', coords = { x = 365.7646, y = -568.5619, z = 28.8474 }, duration = 4000, requireTransportVehicle = true },
                    { type = 'transport', label = 'Drive to the Sandy ambulance bay', location = 'Sandy Ambulance Bay', coords = { x = 1844.4478, y = 3689.9319, z = 24.1276 }, duration = 3000, requireTransportVehicle = true },
                    { type = 'hospital_handoff', label = 'Hand the transfer patient to Sandy staff', location = 'Sandy Ambulance Bay', coords = { x = 1844.4478, y = 3689.9319, z = 24.1276 }, duration = 5000 },
                } },
                { patient = true, stages = {
                    { type = 'pickup_patient', label = 'Check in and collect the transfer patient', location = 'Sandy Hospital', coords = { x = 1849.92, y = 3697.74, z = 34.89 }, duration = 6000 },
                    { type = 'escort_patient', label = 'Escort the patient to the Sandy ambulance bay', location = 'Sandy Ambulance Bay', coords = { x = 1844.4478, y = 3689.9319, z = 24.1276 }, duration = 3000 },
                    { type = 'board_vehicle', label = 'Load the patient into an EMS vehicle', location = 'Sandy Ambulance Bay', coords = { x = 1844.4478, y = 3689.9319, z = 24.1276 }, duration = 4000, requireTransportVehicle = true },
                    { type = 'transport', label = 'Drive to the Pillbox ambulance bay', location = 'Pillbox Ambulance Bay', coords = { x = 365.7646, y = -568.5619, z = 28.8474 }, duration = 3000, requireTransportVehicle = true },
                    { type = 'hospital_handoff', label = 'Hand the transfer patient to Pillbox staff', location = 'Pillbox Ambulance Bay', coords = { x = 365.7646, y = -568.5619, z = 28.8474 }, duration = 5000 },
                } },
            },
        },
        {
            id = 'repair_supply', label = 'Fleet Repair Response', category = 'FLEET SUPPORT',
            description = 'Collect repair supplies, assist a stranded EMS unit and return the equipment.', reward = 900, xp = 50,
            routes = {
                { stages = {
                    { type = 'pickup', label = 'Collect the fleet repair equipment', location = 'Davis Fire Station', coords = { x = 1200.0, y = -1473.0, z = 34.86 }, duration = 6000 },
                    { type = 'repair', label = 'Repair the stranded EMS unit', location = 'La Puerta Freeway', coords = { x = -579.5, y = -1784.7, z = 22.5 }, duration = 12000, spawnVehicle = 'ambulance', vehicleHeading = 145.0 },
                    { type = 'deliver', label = 'Return the repair equipment to Pillbox', location = 'Pillbox Hospital', coords = { x = 316.98, y = -583.05, z = 43.27 }, duration = 4000 },
                } },
            },
        },
    },
}

-- Direct player-to-player "patch up" (X key, look at a player up close).
-- A downed target is healed immediately -- they cannot meaningfully consent.
-- A conscious target instead gets a Y/N offer (see client/patch.lua).
Config.Patch = {
    key = 'X',
    maxDistance = 3.0,
    offerTimeoutMs = 15000,
    treatmentMs = 8000,
    -- Enforced by the server for both the medic and patient after any
    -- completed/cancelled treatment, preventing rapid request spam.
    cooldownMs = 5000,
    -- Optional one-click G-menu transport into the nearest configured
    -- ambulance. The patient must be unconscious and both players must be
    -- close to the same server-validated vehicle.
    allowDirectAmbulanceLoad = true,
    ambulanceLoadDistance = 6.0,
}

-- Admin-placed NPC: the only place a member can change/wear their duty
-- outfit (server/main.lua's wear_favorite_outfit/choose_outfit both
-- require standing here). Going on duty only verifies you're already
-- dressed for it -- see toggle_duty.
Config.Wardrobe = {
    NpcModel = 'mp_m_shopkeep_01',
    NpcInteractDistance = 2.5,
}

Config.Dispatch = {
    command = 'ambulance',
    callCooldownMs = 60000,
    callLifetimeMs = 600000,
    cardLifetimeMs = 18000,
    blipLifetimeMs = 300000,
    responseKey = 'Y',
    menuKey = 'F10',
    backupKey = 'B',
    panicKey = 'F9',
    onSceneDistance = 30.0,
    governmentDoctor = {
        enabled = true,
        -- Government response is automatic when fewer than this many
        -- dispatch-qualified EMS members are on duty. Keep at 1 to preserve
        -- the previous "only when nobody is available" behaviour.
        minimumOnDutyEMS = 1,
        vehicleModel = 'ambulance',
        pedModel = 's_m_m_paramedic_01',
        minimumResponseMs = 5000,
        -- GTA pauses distant NPC vehicle AI until a player streams it. Keep
        -- the government ambulance inside the caller's active simulation
        -- area so it begins driving immediately without teleporting.
        spawnMinDistance = 55.0,
        spawnMaxDistance = 100.0,
        targetRouteDistance = 90.0,
        minimumRouteDistance = 35.0,
        maximumRouteDistance = 180.0,
        maximumRouteFactor = 2.5,
        spawnClearRadius = 9.0,
        spawnCollisionTimeoutMs = 3000,
        streamingRadius = 300.0,
        driveSpeed = 22.0,
        sceneStopMinDistance = 14.0,
        sceneStopMaxDistance = 28.0,
        routeTimeoutMs = 60000,
        footApproachTimeoutMs = 25000,
        treatmentMs = 10000,
        treatmentRetryDelayMs = 4000,
        protectionSafetyMs = 30000,
        sharedResponseRadius = 40.0,
        sharedResponseWaitMs = 30000,
        -- Both entities must remain unseen by every player for this long.
        -- There is deliberately no maximum visible lifetime.
        cleanupHiddenForMs = 2500,
        maxAttempts = 4,
        retryDelayMs = 7000,
        -- Target two minutes from call creation to arrival. The ambulance is
        -- spawned near the end of this window, then completes the visible road
        -- approach. Urgent bleed-out shortening is disabled by request.
        arrivalMinMs = 120000,
        arrivalMaxMs = 120000,
        estimatedTravelMs = 15000,
        allowUrgentArrival = false,
    },
}

Config.Permissions = {
    ['ems.invite'] = 'Invite members',
    ['ems.kick'] = 'Remove members',
    ['ems.promote'] = 'Promote members',
    ['ems.demote'] = 'Demote members',
    ['ems.manage_outfits'] = 'Manage duty outfits',
    ['ems.manage_ranks'] = 'Create, edit and delete ranks',
    ['ems.manage_permissions'] = 'Assign rank permissions',
    ['ems.view_members'] = 'View member roster',
    ['ems.view_logs'] = 'View activity logs',
    ['ems.manage_vehicles'] = 'Manage EMS vehicles',
    ['ems.spawn_vehicles'] = 'Spawn EMS fleet vehicles',
    ['ems.view_member_map'] = 'View EMS members on map',
    ['ems.set_meeting'] = 'Set EMS meeting point',
    ['ems.receive_dispatch'] = 'Receive and respond to EMS dispatch calls',
    ['ems.manage_dispatch'] = 'Remove EMS dispatch calls',
    ['ems.send_gov_doctor'] = 'Send a government doctor to an EMS call',
    ['ems.treat_player'] = 'Patch up other players (X, look at player)',
    ['ems.use_wardrobe'] = 'Use hospital EMS wardrobe',
    ['ems.use_storage'] = 'Use hospital medical storage',
    ['ems.drive_ambulance'] = 'Drive and call ambulance fleet vehicles',
    ['ems.fly_helicopter'] = 'Fly and call air ambulance vehicles',
    ['ems.administer_medication'] = 'Administer medication to patients',
    ['ems.write_medical_reports'] = 'Create medical reports',
    ['ems.view_medical_reports'] = 'View patient medical history',
    ['ems.request_backup'] = 'Request dispatch backup',
    ['ems.use_panic'] = 'Use the EMS panic button',
    ['ems.manage_hospital'] = 'Manage hospitals and operational settings',
    ['ems.manage_billing'] = 'Manage treatment prices and EMS rewards',
    ['ems.suspend_members'] = 'Suspend and reinstate EMS members',
    ['ems.sell_medicine'] = 'Sell medical supplies to other players',
    ['ems.manage_missions'] = 'Set the daily mission NPC location',
}

-- On-duty medics with ems.sell_medicine can sell this catalog to nearby
-- players through the G-menu. Both medic sales and cm-doctor pharmacy sales
-- draw from the same server-authoritative hospital stock below.
Config.MedicineSales = {
    enabled = true,
    permission = 'ems.sell_medicine',
    maxDistance = 3.0,
    offerTimeoutMs = 15000,
    catalog = {
        { item = 'bandage', label = 'Bandage', price = 40, stockCost = 1 },
        { item = 'painkillers', label = 'Painkillers', price = 60, stockCost = 1 },
        { item = 'antibiotics', label = 'Antibiotics', price = 90, stockCost = 1 },
        { item = 'adrenaline_shot', label = 'Adrenaline Shot', price = 150, stockCost = 2 },
        { item = 'medikit', label = 'Medikit', price = 350, stockCost = 4 },
    },
}

-- Shared Pillbox medicine stock and the low-stock delivery mission.
-- The task can only be accepted by an on-duty EMS member who can drive an
-- ambulance. It appears at the supply doctor only when stock is at or below
-- triggerPercent. One run is active server-wide to prevent duplicate refills.
Config.MedicineStock = {
    enabled = true,
    maxUnits = 100,
    initialUnits = 100,
    triggerPercent = 40,
    refillToFull = true,
    permission = 'ems.drive_ambulance',
    truckModel = 'mule3',
    reward = 1400,
    xp = 80,
    pickupDurationMs = 10000,
    returnDurationMs = 8000,
    interactionDistance = 5.0,
    taskNpc = {
        id = 'pillbox_supply_doctor',
        coords = { x = 301.5257, y = -579.6008, z = 28.8474, h = 279.7823 },
    },
    truckSpawn = {
        x = 365.0297, y = -569.6835, z = 28.8474, h = 242.9317,
    },
    pickupLocations = {
        { label = 'Humane Labs loading point A', x = 3594.9790, y = 3661.8184, z = 33.8717, h = 251.4257 },
        { label = 'Humane Labs loading point B', x = 3595.2209, y = 3669.8718, z = 33.8717, h = 263.9323 },
    },
    itemCosts = {
        bandage = 1,
        painkillers = 1,
        antibiotics = 1,
        adrenaline_shot = 2,
        medikit = 4,
    },
}

-- Fleet vehicle configurator/spawner (Config.Permissions.ems.manage_vehicles /
-- ems.spawn_vehicles above gate who can use it). The model picker itself is
-- populated live from every vehicle streamed on the server (see
-- client/vehicles.lua's scanVehicleModelsForClass), not from a config list.
Config.VehicleFleet = {
    maxPresets = 24,
    spawnCooldownMs = 15000,
}

-- Fixed organization ranks for the first EMS release. Leader is unique and
-- can only be assigned through the server-authoritative admin flow.
Config.Ranks = {
    { tier = 100, name = 'EMS Leader', leader = true, permissions = 'ALL' },
    { tier = 90, name = 'Chief Paramedic', permissions = {
        'ems.invite', 'ems.kick', 'ems.promote', 'ems.demote',
        'ems.manage_outfits', 'ems.manage_ranks', 'ems.manage_permissions',
        'ems.view_members', 'ems.view_logs',
        'ems.manage_vehicles', 'ems.spawn_vehicles', 'ems.view_member_map', 'ems.set_meeting',
        'ems.receive_dispatch', 'ems.manage_dispatch', 'ems.send_gov_doctor', 'ems.treat_player',
        'ems.use_wardrobe', 'ems.use_storage', 'ems.drive_ambulance', 'ems.fly_helicopter',
        'ems.administer_medication', 'ems.write_medical_reports', 'ems.view_medical_reports',
        'ems.request_backup', 'ems.use_panic', 'ems.manage_hospital', 'ems.manage_billing', 'ems.suspend_members', 'ems.sell_medicine',
        'ems.manage_missions',
    } },
    { tier = 70, name = 'EMS Supervisor', permissions = {
        'ems.invite', 'ems.promote', 'ems.demote', 'ems.view_members', 'ems.view_logs',
        'ems.spawn_vehicles', 'ems.receive_dispatch', 'ems.manage_dispatch', 'ems.send_gov_doctor',
        'ems.treat_player', 'ems.use_wardrobe', 'ems.use_storage', 'ems.drive_ambulance', 'ems.fly_helicopter',
        'ems.administer_medication', 'ems.write_medical_reports', 'ems.view_medical_reports',
        'ems.request_backup', 'ems.use_panic', 'ems.sell_medicine',
    } },
    { tier = 50, name = 'Paramedic', permissions = {
        'ems.view_members', 'ems.spawn_vehicles', 'ems.receive_dispatch', 'ems.send_gov_doctor', 'ems.treat_player',
        'ems.use_wardrobe', 'ems.use_storage', 'ems.drive_ambulance', 'ems.fly_helicopter',
        'ems.administer_medication', 'ems.write_medical_reports', 'ems.view_medical_reports',
        'ems.request_backup', 'ems.use_panic', 'ems.sell_medicine',
    } },
    { tier = 30, name = 'EMT', permissions = {
        'ems.view_members', 'ems.receive_dispatch', 'ems.treat_player', 'ems.use_wardrobe',
        'ems.use_storage', 'ems.drive_ambulance', 'ems.write_medical_reports', 'ems.request_backup', 'ems.use_panic', 'ems.sell_medicine',
    } },
    { tier = 10, name = 'Recruit', permissions = { 'ems.view_members', 'ems.use_wardrobe' } },
}
