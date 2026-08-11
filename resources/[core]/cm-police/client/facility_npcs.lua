local Locations = { armory_npc = nil, storage_npc = nil }
local Peds = {}
local StorageOpen = false
local PromptKind

local function npcPresentation(kind)
    if kind == 'armory_npc' then
        return Config.FacilityNpcs.ArmoryName or 'Officer Hayes', Config.FacilityNpcs.ArmoryRole or 'Police Quartermaster', 'gun'
    end
    return Config.FacilityNpcs.StorageName or 'Officer Brooks', Config.FacilityNpcs.StorageRole or 'Police Storekeeper', 'box-archive'
end

local function removePed(kind)
    if Peds[kind] and DoesEntityExist(Peds[kind]) then DeleteEntity(Peds[kind]) end
    Peds[kind] = nil
end

local function spawnPed(kind)
    removePed(kind)
    local location = Locations[kind]
    if not location then return end
    local modelName = kind == 'armory_npc' and Config.FacilityNpcs.ArmoryModel or Config.FacilityNpcs.StorageModel
    local model = GetHashKey(modelName or 's_m_y_cop_01')
    RequestModel(model)
    local deadline = GetGameTimer() + 3000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(0) end
    if not HasModelLoaded(model) then return end
    local ped = CreatePed(4, model, location.x, location.y, location.z - 1.0, location.heading or 0.0, false, false)
    SetEntityInvincible(ped, true); FreezeEntityPosition(ped, true); SetBlockingOfNonTemporaryEvents(ped, true)
    Peds[kind] = ped
    SetModelAsNoLongerNeeded(model)
end

local function openArmory()
    TriggerEvent('cm-police:client:openArmory')
end

local function interact(kind)
    if kind == 'armory_npc' then return openArmory() end
    local ok, message = lib.callback.await('cm-police:server:openPoliceStorage', false)
    StorageOpen = ok == true
    if not ok then PoliceNotify(message, 'error') end
end

CreateThread(function()
    local locations = lib.callback.await('cm-police:server:facilityNpcLocations', false) or {}
    Locations.armory_npc, Locations.storage_npc = locations.armory, locations.storage
    spawnPed('armory_npc'); spawnPed('storage_npc')
    while true do
        local wait = 1000
        local coords = GetEntityCoords(PlayerPedId())
        for kind, location in pairs(Locations) do
            if location then
                local distance = #(coords - vector3(location.x, location.y, location.z))
                if distance <= (Config.FacilityNpcs.DrawDistance or 18.0) then
                    wait = 0
                    local name, role, icon = npcPresentation(kind)
                    PoliceDrawNpcName(location, name)
                    if distance <= (Config.FacilityNpcs.InteractDistance or 2.5) then
                        if PromptKind ~= kind then
                            if PromptKind then PoliceHideNpcInteraction(PromptKind) end
                            PoliceShowNpcInteraction(kind, name, role, icon); PromptKind = kind
                        end
                        if IsControlJustPressed(0, 38) then
                            PoliceHideNpcInteraction(kind); PromptKind = nil
                            local quote = kind == 'armory_npc' and 'I manage department-issued weapons for on-duty officers.' or 'I can open the shared Police department storage for you.'
                            local continueLabel = kind == 'armory_npc' and 'View the armory' or 'Open Police storage'
                            PoliceOpenRestrictedNpcDialogue(Peds[kind], { owner = kind, name = name, role = role, quote = quote, continueLabel = continueLabel }, kind, function() interact(kind) end)
                            Wait(500); break
                        end
                    end
                end
            end
        end
        if PromptKind then
            local active = Locations[PromptKind]
            if not active or #(coords - vector3(active.x, active.y, active.z)) > (Config.FacilityNpcs.InteractDistance or 2.5) then
                PoliceHideNpcInteraction(PromptKind); PromptKind = nil
            end
        end
        if StorageOpen then
            local storage = Locations.storage_npc
            if not storage or #(coords - vector3(storage.x, storage.y, storage.z)) > 5.0 then
                lib.callback.await('cm-police:server:closePoliceStorage', false)
                StorageOpen = false
            end
        end
        Wait(wait)
    end
end)

RegisterNetEvent('cm-police:client:facilityNpcUpdated', function(kind, location)
    if kind ~= 'armory_npc' and kind ~= 'storage_npc' then return end
    Locations[kind] = type(location) == 'table' and location or nil
    if kind == 'storage_npc' and not Locations[kind] then StorageOpen = false end
    spawnPed(kind)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if PromptKind then PoliceHideNpcInteraction(PromptKind) end
    removePed('armory_npc'); removePed('storage_npc')
end)
