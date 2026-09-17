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

RegisterNUICallback('closeWardrobeDressingRoom', function(data, cb)
    closeWardrobe()
    if data and data.npcMode == true then SetNuiFocus(false, false) end
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
local wardrobePromptVisible = false

local function normalizeLocation(location)
    if type(location) ~= 'table' then return nil end
    if type(location.value) == 'table' then location = location.value end
    local x, y, z = tonumber(location.x), tonumber(location.y), tonumber(location.z)
    if not x or not y or not z then return nil end
    return { x = x, y = y, z = z, heading = tonumber(location.heading or location.w) or 0.0 }
end

local function drawNpcName()
    if not NpcLocation then return end
    SetDrawOrigin(NpcLocation.x, NpcLocation.y, NpcLocation.z + 1.15, 0)
    SetTextFont(4); SetTextScale(0.0, 0.31); SetTextCentre(true); SetTextOutline()
    SetTextColour(255, 255, 255, 245)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName((Config.Wardrobe or {}).NpcName or 'EMS Wardrobe')
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

local function setWardrobePrompt(visible)
    if wardrobePromptVisible == visible then return end
    wardrobePromptVisible = visible
    SendNUIMessage(visible and {
        action = 'npcInteraction:show', name = (Config.Wardrobe or {}).NpcName or 'EMS Wardrobe',
        role = (Config.Wardrobe or {}).NpcRole or 'Duty Clothing',
    } or { action = 'npcInteraction:hide' })
end

local function spawnClothingNpc()
    if npcPed and DoesEntityExist(npcPed) then DeleteEntity(npcPed) end
    if npcBlip and DoesBlipExist(npcBlip) then RemoveBlip(npcBlip) end
    npcPed, npcBlip = nil, nil
    if not NpcLocation then return end

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
    AddTextComponentSubstringPlayerName((Config.Wardrobe or {}).NpcName or 'EMS Wardrobe')
    EndTextCommandSetBlipName(npcBlip)
end

CreateThread(function()
    NpcLocation = normalizeLocation(lib.callback.await('cm-ems:server:clothingNpcLocation', false))
    spawnClothingNpc()
end)

RegisterNetEvent('cm-ems:client:clothingNpcUpdated', function(location)
    NpcLocation = normalizeLocation(location)
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
        icon = 'shirt', onSelect = OpenEmsWardrobe,
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
        if NpcLocation and not wardrobeOpen then
            local coords = GetEntityCoords(PlayerPedId())
            local interactDistance = (Config.Wardrobe or {}).NpcInteractDistance or 2.5
            local dist = #(coords - vector3(NpcLocation.x, NpcLocation.y, NpcLocation.z))
            if dist <= 12.0 then
                wait = 0
                drawNpcName()
                local blocked = IsPauseMenuActive() or IsPedInAnyVehicle(PlayerPedId(), false) or (IsNuiFocused and IsNuiFocused())
                setWardrobePrompt(dist <= interactDistance and not blocked)
                if dist <= interactDistance and not blocked and IsControlJustPressed(0, 38) then
                    setWardrobePrompt(false)
                    local member = type(LocalPlayer.state.cmEms) == 'table'
                    EmsOpenNpcDialogue(npcPed, {
                        name = (Config.Wardrobe or {}).NpcName or 'EMS Wardrobe',
                        role = (Config.Wardrobe or {}).NpcRole or 'Duty Clothing',
                        quote = member and 'I can help you build an approved EMS uniform and prepare you for duty.' or 'This wardrobe is restricted to EMS personnel.',
                        continueLabel = member and 'Open EMS wardrobe' or 'Leave',
                    }, member and OpenEmsWardrobe or nil)
                end
            else
                setWardrobePrompt(false)
            end
        else
            setWardrobePrompt(false)
        end
        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if npcPed and DoesEntityExist(npcPed) then DeleteEntity(npcPed) end
    if npcBlip and DoesBlipExist(npcBlip) then RemoveBlip(npcBlip) end
    setWardrobePrompt(false)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then closeWardrobe() end
end)
