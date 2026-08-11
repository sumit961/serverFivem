-- cm-police Police Wardrobe dressing room (client). Builds an in-place
-- camera around the officer's current position -- no teleport, no
-- dependency on nv_cloth at runtime beyond the shared cm-items catalog
-- data already used by policeWardrobeCatalog/previewWardrobeItem
-- (server/main.lua and client/main.lua respectively, both unchanged by
-- this file). Camera positioning math is nv_cloth's own proven "body"
-- preset (client/cl_camera.lua), reused directly rather than reinvented.

local cam = nil
local roomOpen = false
local roomFromNpc = false
local NpcLocation
local npcPed = nil
local npcBlip = nil
local wardrobePromptVisible = false

local function setWardrobeNpcPreviewHidden(hidden)
    if wardrobePromptVisible then
        PoliceHideNpcInteraction('wardrobe_npc')
        wardrobePromptVisible = false
    end
    if not npcPed or not DoesEntityExist(npcPed) then return end
    SetEntityVisible(npcPed, not hidden, false)
    SetEntityCollision(npcPed, not hidden, true)
    FreezeEntityPosition(npcPed, true)
end

local function notify(message, kind)
    PoliceNotify(message, kind)
end

local function canManageOutfits()
    local state = LocalPlayer.state.cmPolice
    if type(state) ~= 'table' then return false end
    local permissions = state.permissions or {}
    return state.isLeader == true or permissions['police.manage_outfits'] == true
end

local function wardrobeSex()
    return GetEntityModel(PlayerPedId()) == `mp_f_freemode_01` and 'female' or 'male'
end

local function setRoomLocked(locked)
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, locked)
    SetPedCanRagdoll(ped, not locked)
    if locked then ClearPedTasksImmediately(ped) end
    DisplayRadar(not locked)
    DisplayHud(not locked)
end

local function openCamera()
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local rad = math.rad(GetEntityHeading(ped))
    local dist = Config.Wardrobe.CameraDistance or 4.35
    local heightOffset = Config.Wardrobe.CameraHeightOffset or 0.18
    local camPos = vector3(
        pos.x - math.sin(rad) * dist,
        pos.y + math.cos(rad) * dist,
        pos.z + heightOffset + 0.15
    )
    local faceHeading = GetHeadingFromVector_2d(pos.x - camPos.x, pos.y - camPos.y) % 360.0
    SetEntityHeading(ped, faceHeading)
    cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', camPos.x, camPos.y, camPos.z, 0.0, 0.0, 0.0, Config.Wardrobe.CameraFov or 38.0, false, 0)
    PointCamAtCoord(cam, pos.x, pos.y, pos.z + heightOffset)
    SetCamActive(cam, true)
    RenderScriptCams(true, false, 0, true, true)
end

local function closeCamera()
    RenderScriptCams(false, true, 350, true, true)
    if cam and DoesCamExist(cam) then DestroyCam(cam, false) end
    cam = nil
end

local function closeRoom()
    if not roomOpen then return end
    if roomFromNpc then setWardrobeNpcPreviewHidden(false) end
    roomOpen = false
    closeCamera()
    setRoomLocked(false)
end

RegisterNUICallback('openWardrobeDressingRoom', function(_, cb)
    if roomOpen then return cb({ ok = false }) end
    if not canManageOutfits() then
        notify('Your rank cannot manage Police clothing.', 'error')
        return cb({ ok = false })
    end
    roomFromNpc = false
    local items = lib.callback.await('cm-police:server:policeWardrobeCatalog', false, wardrobeSex())
    roomOpen = true
    setRoomLocked(true)
    openCamera()
    cb({ ok = true, items = items or {} })
end)

RegisterNUICallback('openPoliceNpcCloset', function(_, cb)
    if roomOpen then return cb({ ok = false }) end
    local closet, reason = lib.callback.await('cm-police:server:wardrobeClosetData', false)
    if not closet then notify(reason or 'Could not open the Police closet.', 'error'); return cb({ ok = false }) end
    local items = lib.callback.await('cm-police:server:policeWardrobeCatalog', false, wardrobeSex()) or {}
    roomFromNpc = true; roomOpen = true; setWardrobeNpcPreviewHidden(true); setRoomLocked(true); openCamera()
    cb({ ok = true, items = items, favorites = closet.favorites or {}, maxSlots = closet.maxSlots or 5 })
end)

RegisterNUICallback('saveWardrobeFavorite', function(data, cb)
    local ok, message, favorites = lib.callback.await('cm-police:server:saveWardrobeFavorite', false, data and data.name, captureOutfit())
    notify(message, ok and 'success' or 'error')
    cb({ ok = ok == true, favorites = favorites or {} })
end)

RegisterNUICallback('removeWardrobeFavorite', function(data, cb)
    local ok, message, favorites = lib.callback.await('cm-police:server:removeWardrobeFavorite', false, data and data.slot)
    notify(message, ok and 'success' or 'error')
    cb({ ok = ok == true, favorites = favorites or {} })
end)

RegisterNUICallback('wearWardrobeFavorite', function(data, cb)
    local ok, message, outfit = lib.callback.await('cm-police:server:wearWardrobeFavorite', false, data and data.slot)
    if ok and type(outfit) == 'table' then applyOutfit(outfit) end
    notify(message, ok and 'success' or 'error')
    cb({ ok = ok == true })
end)

RegisterNUICallback('finishWardrobeDuty', function(_, cb)
    if not roomOpen or not roomFromNpc then return cb({ ok = false }) end
    local ok, message = lib.callback.await('cm-police:server:finishWardrobeDuty', false, captureOutfit(), wardrobeSex())
    notify(message, ok and 'success' or 'error')
    cb({ ok = ok == true })
end)

RegisterNUICallback('closeWardrobeDressingRoom', function(_, cb)
    local dropFocus = roomFromNpc
    closeRoom()
    roomFromNpc = false
    if dropFocus then SetNuiFocus(false, false) end
    cb({ ok = true })
end)

RegisterNUICallback('rotateWardrobePed', function(data, cb)
    if not roomOpen then return cb({ ok = false }) end
    local delta = tonumber(data and data.delta) or 0.0
    delta = math.max(-25.0, math.min(25.0, delta))
    SetEntityHeading(PlayerPedId(), (GetEntityHeading(PlayerPedId()) + delta) % 360.0)
    cb({ ok = true })
end)

-- Defensive cleanup: a resource restart wipes the NUI's own state (it will
-- reopen closed), but the camera/freeze are real client-side game state
-- that would otherwise survive and leave the officer stuck.
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and roomOpen then closeRoom() end
end)

-- ============================================================
--  Wardrobe NPC -- the only way to actually wear a duty preset (see
--  server/wardrobe.lua). Location fetched once at resource start and kept
--  live via the update event -- deploy can happen before the F7 dashboard
--  has ever fetched/shown it, same reasoning as the impound kiosk location.
-- ============================================================

local function spawnWardrobeNpc()
    if npcPed and DoesEntityExist(npcPed) then DeleteEntity(npcPed) end
    if npcBlip and DoesBlipExist(npcBlip) then RemoveBlip(npcBlip) end
    npcPed, npcBlip = nil, nil
    if not NpcLocation then return end

    local hash = GetHashKey(Config.Wardrobe.NpcModel or 'mp_m_shopkeep_01')
    RequestModel(hash)
    local deadline = GetGameTimer() + 2000
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(0) end
    if not HasModelLoaded(hash) then return end

    npcPed = CreatePed(4, hash, NpcLocation.x, NpcLocation.y, NpcLocation.z - 1.0, NpcLocation.heading or 0.0, false, false)
    SetEntityInvincible(npcPed, true)
    FreezeEntityPosition(npcPed, true)
    SetBlockingOfNonTemporaryEvents(npcPed, true)
    if roomOpen and roomFromNpc then setWardrobeNpcPreviewHidden(true) end
    SetModelAsNoLongerNeeded(hash)

    npcBlip = AddBlipForCoord(NpcLocation.x, NpcLocation.y, NpcLocation.z)
    SetBlipSprite(npcBlip, 366)
    SetBlipColour(npcBlip, 3)
    SetBlipAsShortRange(npcBlip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Police Wardrobe')
    EndTextCommandSetBlipName(npcBlip)
end

CreateThread(function()
    NpcLocation = lib.callback.await('cm-police:server:wardrobeNpcLocation', false)
    spawnWardrobeNpc()
end)

RegisterNetEvent('cm-police:client:wardrobeNpcUpdated', function(location)
    NpcLocation = location
    spawnWardrobeNpc()
end)

-- Assign/reassign one quick-slot from the full preset list -- reused by
-- both an empty top-level slot row and the "Manage Quick Slots" submenu.
local function pickPresetForSlot(slot, presets, reopen)
    local options = {}
    for _, preset in ipairs(presets or {}) do
        options[#options + 1] = {
            title = preset.name,
            description = ('Assign to Quick Slot %d'):format(slot),
            icon = 'shirt',
            onSelect = function()
                local ok, message = lib.callback.await('cm-police:server:setWardrobeSlot', false, slot, preset.id)
                notify(message, ok and 'success' or 'error')
                reopen()
            end,
        }
    end
    if #options == 0 then
        notify('No clothing presets exist yet -- ask a manager to save one.', 'error')
        return reopen()
    end
    options[#options + 1] = {
        title = 'Clear Slot',
        description = 'Remove whatever is assigned to this slot',
        icon = 'xmark',
        onSelect = function()
            lib.callback.await('cm-police:server:setWardrobeSlot', false, slot, nil)
            reopen()
        end,
    }
    PoliceQuickMenu(('Assign Quick Slot %d'):format(slot), options)
end

local function openManageSlots(data)
    local options = {}
    for slot = 1, (Config.Wardrobe.MaxQuickSlots or 5) do
        local entry = data.slots and data.slots[slot]
        options[#options + 1] = {
            title = entry and ('Slot %d: %s'):format(slot, entry.presetName) or ('Slot %d: Empty'):format(slot),
            description = 'Change what this quick slot points to',
            icon = 'shirt',
            onSelect = function() pickPresetForSlot(slot, data.presets, function() openManageSlots(data) end) end,
        }
    end
    PoliceQuickMenu('Manage Quick Slots', options)
end

function OpenWardrobeNpcMenu()
    local state = LocalPlayer.state.cmPolice
    if type(state) ~= 'table' then return notify('You must be a Police member to do that.', 'error') end
    local data = lib.callback.await('cm-police:server:wardrobeMenuData', false, wardrobeSex())
    if not data then return notify('Could not load the wardrobe.', 'error') end

    local options = {}
    for slot = 1, (Config.Wardrobe.MaxQuickSlots or 5) do
        local entry = data.slots and data.slots[slot]
        if entry then
            options[#options + 1] = {
                title = ('Slot %d: %s'):format(slot, entry.presetName),
                description = 'Wear this outfit',
                icon = 'shirt',
                onSelect = function()
                    if not PoliceConfirm('Wear Outfit', ('Put on "%s"?'):format(entry.presetName), 'Wear', 'Cancel') then return end
                    local ok, message, result = lib.callback.await('cm-police:server:wearOutfit', false, entry.presetId, wardrobeSex())
                    notify(message, ok and 'success' or 'error')
                    if ok and type(result) == 'table' and result.outfit then applyOutfit(result.outfit) end
                end,
            }
        else
            options[#options + 1] = {
                title = ('Slot %d: Empty'):format(slot),
                description = 'Assign a clothing preset to this slot',
                icon = 'plus',
                onSelect = function() pickPresetForSlot(slot, data.presets, OpenWardrobeNpcMenu) end,
            }
        end
    end
    options[#options + 1] = {
        title = 'Manage Quick Slots',
        description = 'Reassign or clear any of your quick slots',
        icon = 'gear',
        onSelect = function() openManageSlots(data) end,
    }
    PoliceQuickMenu('Police Wardrobe', options)
end

local function OpenPoliceVisualCloset()
    SendNUIMessage({ action = 'policeCloset:open' })
    SetNuiFocus(true, true)
end

CreateThread(function()
    while true do
        local wait = 1000
        if NpcLocation and not roomOpen then
            local coords = GetEntityCoords(PlayerPedId())
            local dist = #(coords - vector3(NpcLocation.x, NpcLocation.y, NpcLocation.z))
            if dist <= 12.0 then
                wait = 0
                PoliceDrawNpcName(NpcLocation, Config.Wardrobe.NpcName or 'Officer Taylor')
                if dist <= (Config.Wardrobe.NpcInteractDistance or 2.5) then
                    if not wardrobePromptVisible then
                        PoliceShowNpcInteraction('wardrobe_npc', Config.Wardrobe.NpcName, Config.Wardrobe.NpcRole, 'shirt')
                        wardrobePromptVisible = true
                    end
                    if IsControlJustPressed(0, 38) then
                        PoliceHideNpcInteraction('wardrobe_npc'); wardrobePromptVisible = false
                        PoliceOpenRestrictedNpcDialogue(npcPed, { owner = 'wardrobe_npc', name = Config.Wardrobe.NpcName, role = Config.Wardrobe.NpcRole,
                            quote = 'I can help you build an approved Police outfit and save it to your favorites.', continueLabel = 'Open Police closet' }, 'wardrobe_npc', OpenPoliceVisualCloset)
                    end
                elseif wardrobePromptVisible then
                    PoliceHideNpcInteraction('wardrobe_npc'); wardrobePromptVisible = false
                end
            elseif wardrobePromptVisible then
                PoliceHideNpcInteraction('wardrobe_npc'); wardrobePromptVisible = false
            end
        elseif wardrobePromptVisible then
            PoliceHideNpcInteraction('wardrobe_npc'); wardrobePromptVisible = false
        end
        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if wardrobePromptVisible then PoliceHideNpcInteraction('wardrobe_npc') end
    if npcPed and DoesEntityExist(npcPed) then DeleteEntity(npcPed) end
    if npcBlip and DoesBlipExist(npcBlip) then RemoveBlip(npcBlip) end
end)
