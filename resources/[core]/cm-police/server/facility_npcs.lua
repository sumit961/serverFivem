local Locations = { armory_npc = nil, storage_npc = nil }

local function payload(location)
    if not location then return nil end
    return { x = location.x, y = location.y, z = location.z, heading = location.heading or 0.0,
        name = location.name, bucket = tonumber(location.bucket) or 0 }
end

function GetPoliceFacilityNpcLocation(locationType)
    return payload(Locations[tostring(locationType or '')])
end

function IsNearPoliceFacilityNpc(src, locationType)
    local location = Locations[tostring(locationType or '')]
    local ped = GetPlayerPed(src)
    if not location or not ped or ped == 0 then return false end
    if GetPlayerRoutingBucket(src) ~= (tonumber(location.bucket) or 0) then return false end
    return #(GetEntityCoords(ped) - vector3(location.x, location.y, location.z)) <= (Config.FacilityNpcs.InteractDistance or 2.5) + 1.0
end

function SetPoliceFacilityNpcLocation(locationType, value)
    if Locations[locationType] == nil and locationType ~= 'armory_npc' and locationType ~= 'storage_npc' then return false end
    Locations[locationType] = value
    TriggerClientEvent('cm-police:client:facilityNpcUpdated', -1, locationType, payload(value))
    return true
end

lib.callback.register('cm-police:server:facilityNpcLocations', function()
    return { armory = payload(Locations.armory_npc), storage = payload(Locations.storage_npc) }
end)

local function onDutyMember(src)
    local characterId = cid(src)
    local member = characterId and memberFor(characterId)
    if not member or dbBoolean(member.is_suspended) or not dbBoolean(member.on_duty) then return nil, characterId end
    return member, characterId
end

-- Shared preflight for restricted Police NPC cinematics. This only decides
-- which dialogue branch to show; each operation callback still performs its
-- own permission, duty, distance and routing-bucket checks before granting
-- access. Never trust the client simply because this preflight returned true.
lib.callback.register('cm-police:server:restrictedNpcAccess', function(src, npcType)
    local characterId = cid(src)
    local member = characterId and memberFor(characterId)
    if not member then
        return false, 'You are not a Police officer. This service is restricted to department personnel.'
    end
    if dbBoolean(member.is_suspended) then
        return false, 'Your Police access is suspended. I cannot assist you.'
    end
    npcType = tostring(npcType or '')
    -- Officers must be able to enter the wardrobe while off duty because an
    -- approved uniform is what starts their duty state.
    if npcType == 'wardrobe_npc' then return true end
    if not dbBoolean(member.on_duty) then
        return false, 'You need to report for duty in an approved uniform before I can assist you.'
    end
    return true
end)

lib.callback.register('cm-police:server:openPoliceStorage', function(src)
    local member, characterId = onDutyMember(src)
    if not member then return false, 'You must be an on-duty Police officer.' end
    if not IsNearPoliceFacilityNpc(src, 'storage_npc') then return false, 'You must be at the Police storage NPC.' end
    if not rateLimit(src, 'police_storage_open', 800) then return false, 'Please wait.' end
    if GetResourceState('cm-inventory') ~= 'started' then return false, 'Inventory is unavailable.' end
    local ok, opened, reason = pcall(function()
        return exports['cm-inventory']:OpenExternalInventory(src, {
            ownerType = 'police_storage', ownerId = 'department',
            slots = math.max(1, math.min(30, tonumber(Config.FacilityNpcs.StorageSlots) or 30)),
            displaySlots = 30, slotPrefix = 'police-', label = 'Police Department Storage',
            subtitle = 'Shared on-duty storage', kind = 'police_storage', icon = 'shield',
            canDeposit = true, canWithdraw = true, resource = GetCurrentResourceName(),
        })
    end)
    if not ok or opened ~= true then return false, reason or 'Could not open Police storage.' end
    log(characterId, 'police_storage_opened', {})
    return true, 'Police storage opened.'
end)

lib.callback.register('cm-police:server:closePoliceStorage', function(src)
    if GetResourceState('cm-inventory') == 'started' then
        pcall(function() exports['cm-inventory']:CloseExternalInventory(src) end)
    end
    return true
end)

CreateThread(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS cm_police_settings (
        setting_key VARCHAR(64) NOT NULL, setting_value LONGTEXT NOT NULL, updated_by VARCHAR(64) NULL,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, PRIMARY KEY (setting_key)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    local rows = MySQL.query.await("SELECT setting_key, setting_value FROM cm_police_settings WHERE setting_key IN ('armory_npc', 'storage_npc')") or {}
    for _, row in ipairs(rows) do
        local ok, decoded = pcall(json.decode, row.setting_value)
        if ok and type(decoded) == 'table' and tonumber(decoded.x)
            and (row.setting_key == 'armory_npc' or row.setting_key == 'storage_npc') then Locations[row.setting_key] = decoded end
    end
end)

-- The inventory export owns item movement, while Police owns access context.
-- Revoke an already-open department container if duty, location or bucket
-- becomes invalid; this also protects against a modified client suppressing
-- the normal walk-away close callback.
CreateThread(function()
    while true do
        Wait(1000)
        if GetResourceState('cm-inventory') == 'started' then
            for _, playerId in ipairs(GetPlayers()) do
                local src = tonumber(playerId)
                local ok, context = pcall(function() return exports['cm-inventory']:GetOpenExternalInventory(src) end)
                if ok and type(context) == 'table' and context.ownerType == 'police_storage' and context.ownerId == 'department' then
                    local member = select(1, onDutyMember(src))
                    if not member or not IsNearPoliceFacilityNpc(src, 'storage_npc') then
                        pcall(function() exports['cm-inventory']:CloseExternalInventory(src) end)
                    end
                end
            end
        end
    end
end)
