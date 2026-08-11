local wardrobeCamera
local wardrobeOpen = false

local function wardrobeSex()
    return GetEntityModel(PlayerPedId()) == `mp_f_freemode_01` and 'female' or 'male'
end

local function lockWardrobe(locked)
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, locked)
    SetPedCanRagdoll(ped, not locked)
    if locked then ClearPedTasksImmediately(ped) end
    DisplayRadar(not locked)
    DisplayHud(not locked)
end

local function closeWardrobe()
    if not wardrobeOpen then return end
    wardrobeOpen = false
    RenderScriptCams(false, true, 350, true, true)
    if wardrobeCamera and DoesCamExist(wardrobeCamera) then DestroyCam(wardrobeCamera, false) end
    wardrobeCamera = nil
    lockWardrobe(false)
end

RegisterNUICallback('openWardrobeDressingRoom', function(_, cb)
    if wardrobeOpen then return cb({ ok = false }) end
    local state = LocalPlayer.state.cmEms
    if type(state) ~= 'table' then return cb({ ok = false }) end
    local items = lib.callback.await('cm-ems:server:emsWardrobeCatalog', false, wardrobeSex())
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local rad = math.rad(GetEntityHeading(ped))
    local distance, height = 4.35, 0.18
    local cameraPos = vector3(pos.x - math.sin(rad) * distance, pos.y + math.cos(rad) * distance, pos.z + height + 0.15)
    SetEntityHeading(ped, (GetHeadingFromVector_2d(pos.x - cameraPos.x, pos.y - cameraPos.y) + 180.0) % 360.0)
    wardrobeCamera = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', cameraPos.x, cameraPos.y, cameraPos.z,
        0.0, 0.0, 0.0, 38.0, false, 0)
    PointCamAtCoord(wardrobeCamera, pos.x, pos.y, pos.z + height)
    SetCamActive(wardrobeCamera, true)
    RenderScriptCams(true, false, 0, true, true)
    wardrobeOpen = true
    lockWardrobe(true)
    cb({ ok = true, items = items or {} })
end)

RegisterNUICallback('closeWardrobeDressingRoom', function(_, cb)
    closeWardrobe()
    cb({ ok = true })
end)

RegisterNUICallback('rotateWardrobePed', function(data, cb)
    if not wardrobeOpen then return cb({ ok = false }) end
    local delta = math.max(-25.0, math.min(25.0, tonumber(data and data.delta) or 0.0))
    SetEntityHeading(PlayerPedId(), (GetEntityHeading(PlayerPedId()) + delta) % 360.0)
    cb({ ok = true })
end)

AddEventHandler('cm-ems:client:forceDutyCleanup', closeWardrobe)

-- ============================================================
--  Duty clothing NPC -- the only way to wear/change a favorite outfit
--  (server/main.lua's wear_favorite_outfit requires standing here).
--  Going on duty only verifies you're already dressed correctly -- see
--  client/main.lua's toggle_duty payload building.
-- ============================================================

local function notify(message, kind)
    if lib and lib.notify then lib.notify({ title = 'EMS Wardrobe', description = message, type = kind or 'inform' }) end
end

local NpcLocation
local npcPed, npcBlip = nil, nil

local function spawnClothingNpc()
    if not NpcLocation then return end
    if npcPed and DoesEntityExist(npcPed) then DeleteEntity(npcPed) end
    if npcBlip and DoesBlipExist(npcBlip) then RemoveBlip(npcBlip) end

    local hash = GetHashKey((Config.Wardrobe or {}).NpcModel or 'mp_m_shopkeep_01')
    RequestModel(hash)
    local deadline = GetGameTimer() + 2000
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(0) end
    if not HasModelLoaded(hash) then return end

    npcPed = CreatePed(4, hash, NpcLocation.x, NpcLocation.y, NpcLocation.z - 1.0, NpcLocation.heading or 0.0, false, false)
    SetEntityInvincible(npcPed, true)
    FreezeEntityPosition(npcPed, true)
    SetBlockingOfNonTemporaryEvents(npcPed, true)
    SetModelAsNoLongerNeeded(hash)

    npcBlip = AddBlipForCoord(NpcLocation.x, NpcLocation.y, NpcLocation.z)
    SetBlipSprite(npcBlip, 366)
    SetBlipColour(npcBlip, 2)
    SetBlipAsShortRange(npcBlip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('EMS Wardrobe')
    EndTextCommandSetBlipName(npcBlip)
end

CreateThread(function()
    NpcLocation = lib.callback.await('cm-ems:server:clothingNpcLocation', false)
    spawnClothingNpc()
end)

RegisterNetEvent('cm-ems:client:clothingNpcUpdated', function(location)
    NpcLocation = location
    spawnClothingNpc()
end)

function OpenClothingNpcMenu()
    local state = LocalPlayer.state.cmEms
    if type(state) ~= 'table' then return notify('You must be an EMS member to do that.', 'error') end
    local data = lib.callback.await('cm-ems:server:dashboard', false, false, wardrobeSex())
    local options = {}
    if state.onDuty == true then
        options[#options + 1] = {
            title = 'End Shift', description = 'Go off duty and restore your personal clothing',
            icon = 'right-from-bracket',
            onSelect = function()
                local ok, message = lib.callback.await('cm-ems:server:action', false, 'toggle_duty', {})
                notify(message, ok and 'success' or 'error')
                if ok then TriggerEvent('cm-inventory:client:restoreEquippedClothing') end
            end,
        }
    end
    options[#options + 1] = {
        title = 'Build Duty Outfit', description = 'Try on EMS-approved clothing at this wardrobe',
        icon = 'shirt', onSelect = function() openWardrobe() end,
    }
    for _, favorite in ipairs((data and data.favoriteOutfits) or {}) do
        options[#options + 1] = {
            title = ('Slot %d · %s'):format(tonumber(favorite.slot) or 0, tostring(favorite.name)),
            description = tonumber(data.selectedFavoriteOutfitSlot) == tonumber(favorite.slot)
                and 'Currently your duty outfit' or 'Wear for duty',
            icon = 'shirt',
            onSelect = function()
                local ok, message, result = lib.callback.await('cm-ems:server:action', false,
                    'wear_favorite_outfit', { slot = favorite.slot, sex = wardrobeSex() })
                notify(message, ok and 'success' or 'error')
                if ok and result and result.outfit then applyOutfit(result.outfit) end
            end,
        }
    end
    lib.registerContext({ id = 'cm_ems_clothing_npc', title = 'EMS Wardrobe', options = options })
    lib.showContext('cm_ems_clothing_npc')
end

CreateThread(function()
    while true do
        local wait = 1000
        if NpcLocation then
            local coords = GetEntityCoords(PlayerPedId())
            local interactDistance = (Config.Wardrobe or {}).NpcInteractDistance or 2.5
            local dist = #(coords - vector3(NpcLocation.x, NpcLocation.y, NpcLocation.z))
            if dist <= interactDistance then
                wait = 0
                BeginTextCommandDisplayHelp('STRING')
                AddTextComponentSubstringPlayerName('Press ~INPUT_CONTEXT~ to open the EMS wardrobe.')
                EndTextCommandDisplayHelp(0, false, false, 1)
                if IsControlJustPressed(0, 38) then OpenClothingNpcMenu() end
            end
        end
        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if npcPed and DoesEntityExist(npcPed) then DeleteEntity(npcPed) end
    if npcBlip and DoesBlipExist(npcBlip) then RemoveBlip(npcBlip) end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then closeWardrobe() end
end)
