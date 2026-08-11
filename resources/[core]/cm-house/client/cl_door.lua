-- ============================================================
--  cm-house | cl_door.lua
--  The door prompt is a plain [E] on screen with a distance check.
--
--  It is NOT an ox_target box zone. A box has to be rotated to the door's
--  heading, and if it is placed even slightly off-axis it never fires --
--  which is exactly why pressing E did nothing. Distance has no rotation
--  to get wrong.
-- ============================================================

local Houses  = {}   -- [id] = client-safe record
local Blips   = {}
local near    = nil  -- the house we are currently standing at
local menuOpen = false
local pendingDoorId = nil
local pendingDoorToken = nil
local pendingLiveCam = nil
local doorRenderConfirmed = false
local nuiBootReady = false
local doorNuiReady = false

MyHouses = {}        -- [houseId] = true

-- ------------------------------------------------------------
--  Blips
-- ------------------------------------------------------------
local function refreshBlip(h)
    if Blips[h.id] then RemoveBlip(Blips[h.id]) Blips[h.id] = nil end

    local mine = MyHouses[h.id]
    if not mine and not h.forSale and not Config.HouseBlip.showOthers then
        return   -- do not paint 500 white dots across the map
    end

    local b = AddBlipForCoord(h.door.x, h.door.y, h.door.z)
    SetBlipSprite(b, Config.HouseBlip.sprite)
    SetBlipScale(b, Config.HouseBlip.scale)
    SetBlipAsShortRange(b, true)
    SetBlipColour(b,
        mine and Config.HouseBlip.colorOwned
        or (h.forSale and Config.HouseBlip.colorForSale)
        or Config.HouseBlip.colorOther)
    BeginTextCommandSetBlipName('STRING')
    -- Keep one shared pause-map legend category. Numbered selection remains in
    -- the property/admin menus instead of creating hundreds of legend rows.
    AddTextComponentString('House')
    EndTextCommandSetBlipName(b)
    Blips[h.id] = b
end

-- ------------------------------------------------------------
--  Helipad
-- ------------------------------------------------------------
local helipadBusy = false
local MarkerTypeHelicopterSymbol = 34
local VisibleHelipads = {}

local function refreshVisibleHelipads()
    local callbackOk, houseIds = pcall(lib.callback.await,
        'cm-house:server:visibleHelipads', false)
    local visible = {}
    if callbackOk and type(houseIds) == 'table' then
        for _, houseId in ipairs(houseIds) do
            houseId = tonumber(houseId)
            if houseId then visible[houseId] = true end
        end
    end
    VisibleHelipads = visible
end

local function openHelipad(house)
    if helipadBusy then return end
    helipadBusy = true
    local callbackOk, vehicles, why = pcall(lib.callback.await,
        'cm-house:server:helipadVehicles', false, house.id)
    helipadBusy = false
    if not callbackOk then
        return lib.notify({
            description = 'The helipad service is still starting. Restart cm-house and try again.',
            type = 'error',
        })
    end
    if type(vehicles) ~= 'table' then
        return lib.notify({ description = why or 'The helipad is unavailable.', type = 'error' })
    end
    if #vehicles == 0 then
        return lib.notify({ description = 'No accessible helicopters were found.', type = 'inform' })
    end

    local options = {}
    for _, vehicle in ipairs(vehicles) do
        local vehicleId = tonumber(vehicle.id)
        options[#options + 1] = {
            title = tostring(vehicle.label or vehicle.model or 'Helicopter'),
            description = ('%s%s'):format(tostring(vehicle.plate or ''), vehicle.family and ' · Family' or ''),
            icon = 'helicopter',
            onSelect = function()
                local callbackWorked, ok, message = pcall(lib.callback.await,
                    'cm-house:server:callHelicopter', false, house.id, vehicleId)
                if not callbackWorked then
                    return lib.notify({ description = 'The helipad service restarted. Try again.', type = 'error' })
                end
                lib.notify({ description = message or (ok and 'Helicopter called.' or 'Call failed.'),
                    type = ok and 'success' or 'error' })
            end,
        }
    end
    lib.registerContext({
        id = ('cm_house_helipad_%s'):format(house.id),
        title = ('House #%s Helipad'):format(house.houseNumber or '?'),
        options = options,
    })
    lib.showContext(('cm_house_helipad_%s'):format(house.id))
end

CreateThread(function()
    while true do
        local sleep = 750
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        local closest, closestDistance

        for _, house in pairs(Houses) do
            local pad = house.helipad
            if pad and VisibleHelipads[tonumber(house.id)] then
                local distance = #(coords - vector3(pad.x, pad.y, pad.z))
                if distance <= 35.0 then
                    sleep = 0
                    DrawMarker(MarkerTypeHelicopterSymbol,
                        pad.x, pad.y, pad.z + 0.15, 0.0, 0.0, 0.0,
                        0.0, 0.0, pad.h or 0.0, 1.35, 1.35, 1.35, 60, 210, 255, 185,
                        false, false, 2, false, nil, nil, false)
                    if not closestDistance or distance < closestDistance then
                        closest, closestDistance = house, distance
                    end
                end
            end
        end

        if closest and closestDistance <= 3.0 and not menuOpen then
            if CMHouseInteraction and CMHouseInteraction.Request then
                CMHouseInteraction.Request(('house-helipad:%s'):format(closest.id),
                    'Open helipad', nil, 60)
            end
            if IsControlJustReleased(0, Config.Prompt.key) then openHelipad(closest) end
        end
        Wait(sleep)
    end
end)

CreateThread(function()
    while true do
        refreshVisibleHelipads()
        Wait(15000)
    end
end)

-- ------------------------------------------------------------
--  3D text prompt
-- ------------------------------------------------------------
local function draw3d(x, y, z, text)
    if CMHouseInteraction and CMHouseInteraction.Request then
        CMHouseInteraction.Request(('house-door:%s'):format(tostring(near and near.id or 0)),
            text, nil, 60)
    end
end

-- SetTextColour is spelled both ways across FiveM builds.
function SetTextcolour(...) SetTextColour(...) end

-- ------------------------------------------------------------
--  The prompt loop.
--  Two-tier: a slow scan for "is any house near", and a fast loop only
--  while one actually is. A single Wait(0) thread over every house on the
--  server would cost real frames at 1000 players.
-- ------------------------------------------------------------
CreateThread(function()
    while true do
        local sleep = 500
        local ped = PlayerPedId()
        local pc  = GetEntityCoords(ped)

        local best, bestDist = nil, Config.Prompt.drawDist
        for _, h in pairs(Houses) do
            local d = #(pc - vector3(h.door.x, h.door.y, h.door.z))
            if d < bestDist then
                best, bestDist = h, d
            end
        end

        near = best
        if best then sleep = 0 end

        if best and bestDist <= Config.Prompt.distance and not menuOpen then
            local label = best.owned and 'Open property' or 'View property'
            draw3d(best.door.x, best.door.y, best.door.z + 0.6, label)

            if IsControlJustReleased(0, Config.Prompt.key) then
                OpenDoorMenu(best.id)
            end
        end

        Wait(sleep)
    end
end)

-- ------------------------------------------------------------
--  The menu
-- ------------------------------------------------------------
local liveCam = nil

--- Legacy live-camera helpers remain for admin previews, but the door card
--- now reads the locally saved property image and never takes over gameplay view.
local function validPhotoCam(c)
    return type(c) == 'table'
       and tonumber(c.x) ~= nil
       and tonumber(c.y) ~= nil
       and tonumber(c.z) ~= nil
end

local function startLiveCam(c)
    if not validPhotoCam(c) then return false end

    local x, y, z = tonumber(c.x), tonumber(c.y), tonumber(c.z)
    local rx = tonumber(c.rx) or -10.0
    local rz = tonumber(c.rz) or 0.0
    local fov = tonumber(c.fov) or 55.0

    -- Destroy the previous one first. Calling CreateCam again without this
    -- leaks a camera every time the menu opens, and the leaked ones keep
    -- rendering -- which is one way to end up stuck looking at nothing.
    if liveCam then
        if DoesCamExist(liveCam) then DestroyCam(liveCam, false) end
        liveCam = nil
    end

    liveCam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    if not liveCam or not DoesCamExist(liveCam) then
        liveCam = nil
        return false
    end

    SetCamCoord(liveCam, x, y, z)
    SetCamRot(liveCam, rx, 0.0, rz, 2)
    SetCamFov(liveCam, fov)

    -- The world has to stream in around the CAMERA, not the player, or it
    -- frames a void where the house should be.
    SetFocusPosAndVel(x, y, z, 0.0, 0.0, 0.0)

    -- No interpolation. A 500ms blend means a release fired DURING the blend
    -- can be swallowed -- and the player is left inside the camera with no way
    -- out. Snapping is less pretty and cannot strand anybody.
    RenderScriptCams(true, false, 0, true, true)
    return true
end

local function stopLiveCam()
    -- Always release the render, even if the handle is somehow gone. Bailing
    -- early on a nil handle is exactly how a player stays stuck.
    RenderScriptCams(false, false, 0, true, true)
    ClearFocus()

    if not liveCam then return end
    if DoesCamExist(liveCam) then DestroyCam(liveCam, false) end
    liveCam = nil
end

local fallbackContextOpen = false
local closingDoorMenu = false

local function formatMoney(value)
    local s = tostring(math.floor(tonumber(value) or 0))
    local changed
    repeat
        s, changed = s:gsub('^(-?%d+)(%d%d%d)', '%1,%2')
    until changed == 0
    return s
end

--- Global so every NUI callback, the fallback menu and /housefix can reach it.
function CloseDoorMenu()
    if closingDoorMenu then return end
    closingDoorMenu = true

    menuOpen = false
    pendingDoorId = nil
    pendingDoorToken = nil
    pendingLiveCam = nil
    doorRenderConfirmed = false
    stopLiveCam()
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'closeDoor' })

    if fallbackContextOpen then
        fallbackContextOpen = false
        pcall(function() lib.hideContext(false) end)
    end

    closingDoorMenu = false
end

local closeMenu = CloseDoorMenu

--- The custom deed panel is preferred, but the player must never lose the
--- ability to buy/enter a house because Chromium cached an old script or a CEF
--- build rejected JavaScript. ox_lib is already a hard dependency, so this is
--- a safe independent purchase menu.
local function openFallbackDoorMenu(view)
    if not menuOpen or fallbackContextOpen then return end

    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'closeDoor' })
    fallbackContextOpen = true

    local can = view.can or {}
    local options = {
        {
            title = ('%s  #%s'):format(view.label or 'House', view.houseNumber or '?'),
            description = ('Owner: %s | Price: $%s | Government value: $%s')
                :format(view.ownerName or 'For sale', formatMoney(view.price or 0), formatMoney(view.govValue or 0)),
            icon = 'house',
            disabled = true,
        }
    }

    if can.buy then
        options[#options + 1] = {
            title = 'Buy this house',
            description = ('Purchase for $%s from your %s account.')
                :format(formatMoney(view.price or 0), Config.Purchase.account or 'bank'),
            icon = 'cart-shopping',
            onSelect = function()
                local ok, msg = lib.callback.await('cm-house:server:buyHouse', false, view.id)
                lib.notify({ description = msg, type = ok and 'success' or 'error' })
                CloseDoorMenu()
            end,
        }
    end

    if can.enter then
        options[#options + 1] = {
            title = 'Enter home',
            description = 'Enter this property.',
            icon = 'door-open',
            onSelect = function()
                CloseDoorMenu()
                TriggerEvent('cm-house:client:enterHome', view.id)
            end,
        }
    end

    if can.garage and view.hasGarage then
        options[#options + 1] = {
            title = 'Open garage',
            description = view.garageLabel or 'Manage this property garage.',
            icon = 'warehouse',
            onSelect = function()
                CloseDoorMenu()
                TriggerEvent('cm-house:client:openGarage', view.id)
            end,
        }
    end

    if can.lock then
        options[#options + 1] = {
            title = view.locked and 'Unlock house' or 'Lock house',
            description = 'Change the property door state.',
            icon = view.locked and 'lock-open' or 'lock',
            onSelect = function()
                local ok, msg = lib.callback.await('cm-house:server:toggleLock', false, view.id)
                lib.notify({ description = msg, type = ok and 'success' or 'error' })
                CloseDoorMenu()
            end,
        }
    end

    if can.sell then
        options[#options + 1] = {
            title = 'Sell this house',
            description = ('Government payout: $%s.'):format(formatMoney(view.govValue or 0)),
            icon = 'money-bill-transfer',
            onSelect = function()
                local confirm = lib.alertDialog({
                    header = 'Sell this house?',
                    content = 'It goes back on the market and stored contents are removed. This cannot be undone.',
                    centered = true,
                    cancel = true,
                    labels = { confirm = 'Sell it', cancel = 'Keep it' },
                })
                if confirm == 'confirm' then
                    local ok, msg = lib.callback.await('cm-house:server:sellHouse', false, view.id)
                    lib.notify({ description = msg, type = ok and 'success' or 'error' })
                end
                CloseDoorMenu()
            end,
        }
    end

    options[#options + 1] = {
        title = 'Close',
        icon = 'xmark',
        onSelect = function()
            CloseDoorMenu()
        end,
    }

    lib.registerContext({
        id = 'cm_house_door_fallback',
        title = 'Property menu',
        canClose = true,
        onExit = function()
            if fallbackContextOpen and not closingDoorMenu then
                fallbackContextOpen = false
                CloseDoorMenu()
            end
        end,
        options = options,
    })

    lib.showContext('cm_house_door_fallback')
    print(('[cm-house] Door UI did not confirm visibility; opened ox_lib fallback for house %s. coreReady=%s doorReady=%s safePayload=true')
        :format(tostring(view.id), tostring(nuiBootReady), tostring(doorNuiReady)))
end

-- Build a strict JSON-safe object for SendNUIMessage.
-- Never pass the raw ox_lib callback table into Chromium: nested values such
-- as photoCam may be FiveM vector/MsgPack objects. One unsupported value can
-- make CEF drop the entire message even though the NUI page itself is ready.
local function buildDoorNuiPayload(view, requestId)
    local can = type(view.can) == 'table' and view.can or {}

    local function text(value)
        if value == nil then return nil end
        return tostring(value)
    end

    local function number(value, fallback)
        local n = tonumber(value)
        if n == nil or n ~= n or n == math.huge or n == -math.huge then
            return fallback
        end
        return n
    end

    return {
        id              = number(view.id, 0),
        requestId       = tostring(requestId or ''),
        houseNumber     = text(view.houseNumber) or '000',
        label           = text(view.label) or 'House',
        houseType       = text(view.houseType) or '',
        image           = text(view.image),
        ownerName       = text(view.ownerName),
        familyName      = text(view.familyName),
        insurance       = number(view.insurance, 0),
        price           = number(view.price, 0),
        govValue        = number(view.govValue, 0),
        dailyCost       = number(view.dailyCost, 0),
        paidUntil       = text(view.paidUntil),
        daysRemaining   = number(view.daysRemaining, nil),
        stars           = number(view.stars, 0),
        locked          = view.locked == true,
        forSale         = view.forSale == true,
        garageLabel     = text(view.garageLabel),
        garageCapacity  = number(view.garageCapacity, 0),
        hasGarage       = view.hasGarage == true,
        hasHelipad      = view.hasHelipad == true,
        liveView        = false,
        can = {
            lock    = can.lock == true,
            enter   = can.enter == true,
            garage  = can.garage == true,
            sell    = can.sell == true,
            activity = can.activity == true,
            buy     = can.buy == true,
        },
    }
end

function OpenDoorMenu(houseId)
    if menuOpen then return end

    -- Claim the lock before awaiting the server. The prompt runs every frame;
    -- without this, one E press can create overlapping callbacks.
    menuOpen = true

    stopLiveCam()
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)

    local view = lib.callback.await('cm-house:server:getDoorView', false, houseId)

    if not view then
        menuOpen = false
        lib.notify({ description = 'That house is not registered.', type = 'error' })
        return
    end

    pendingDoorId = tonumber(view.id) or tonumber(houseId)
    pendingDoorToken = ('%s:%s:%s'):format(
        tostring(GetPlayerServerId(PlayerId())),
        tostring(pendingDoorId or houseId),
        tostring(GetGameTimer())
    )
    -- The door card uses the locally saved property image. Opening it never
    -- hijacks the gameplay camera; a missing file shows the built-in placeholder.
    pendingLiveCam = nil
    doorRenderConfirmed = false
    fallbackContextOpen = false

    -- Only JSON-safe primitives cross into Chromium. photoCam stays in Lua;
    -- the door card renders the locally saved image path instead.
    local nuiView = buildDoorNuiPayload(view, pendingDoorToken)
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'openDoor', data = nuiView })

    -- Retry the already-sanitised payload while NUI is finishing startup. The
    -- fallback remains available, but it no longer hides a valid custom panel
    -- because one non-JSON camera value poisoned the message.
    CreateThread(function()
        local thisDoor = pendingDoorId
        local thisToken = pendingDoorToken
        local deadline = GetGameTimer() + 3500
        while menuOpen and pendingDoorId == thisDoor
              and pendingDoorToken == thisToken
              and not doorRenderConfirmed and not fallbackContextOpen
              and GetGameTimer() < deadline do
            Wait(350)
            if menuOpen and pendingDoorId == thisDoor
               and pendingDoorToken == thisToken
               and not doorRenderConfirmed and not fallbackContextOpen then
                SendNUIMessage({ action = 'openDoor', data = nuiView })
            end
        end

        if menuOpen and pendingDoorId == thisDoor
           and pendingDoorToken == thisToken
           and not doorRenderConfirmed and not fallbackContextOpen then
            openFallbackDoorMenu(view)
        end
    end)

    -- ESC/BACKSPACE remains available even if the custom browser crashes.
    CreateThread(function()
        while menuOpen do
            if IsControlJustReleased(0, 322)
               or IsControlJustReleased(0, 202) then
                CloseDoorMenu()
                return
            end
            Wait(0)
        end
    end)
end

-- Sent once after app.js has installed all message/click listeners.
RegisterNUICallback('nuiReady', function(d, cb)
    nuiBootReady = true
    print(('[cm-house] Door NUI ready (v%s).'):format(tostring(d and d.version or 'unknown')))
    cb({ ok = true })
end)

-- This is an enhancement acknowledgement, not a gate. The menu is already
-- visible and usable. We only begin the live camera after the browser confirms
-- that the deed panel exists on screen.
RegisterNUICallback('doorUiReady', function(d, cb)
    doorNuiReady = d and d.rootFound == true
    print(('[cm-house] Isolated door UI ready (v%s, root=%s).')
        :format(tostring(d and d.version or 'unknown'), tostring(doorNuiReady)))
    cb({ ok = true })
end)

RegisterNUICallback('doorRendered', function(d, cb)
    local id = d and tonumber(d.houseId)
    local token = d and tostring(d.requestId or '') or ''
    local visible = d and d.visible == true
    local matches = menuOpen
        and pendingDoorId ~= nil
        and pendingDoorToken ~= nil
        and id == pendingDoorId
        and token == pendingDoorToken

    if matches and visible then
        doorRenderConfirmed = true
    elseif Config.Debug then
        print(('[cm-house] Door render acknowledgement rejected: id=%s expected=%s tokenMatch=%s visible=%s size=%sx%s')
            :format(tostring(id), tostring(pendingDoorId), tostring(token == pendingDoorToken),
                    tostring(visible), tostring(d and d.width), tostring(d and d.height)))
    end

    if matches and visible and pendingLiveCam then
        local camData = pendingLiveCam
        pendingLiveCam = nil
        if startLiveCam(camData) then
            SendNUIMessage({ action = 'doorLiveStarted' })
        else
            SendNUIMessage({ action = 'doorLiveUnavailable' })
        end
    end
    cb({ ok = true, accepted = matches and visible })
end)

RegisterNUICallback('door:getPhoto', function(d, cb)
    local houseId = d and tonumber(d.houseId)
    if not menuOpen or not houseId or houseId ~= pendingDoorId then
        cb({ ok = false, message = 'Property menu is no longer active.' })
        return
    end

    local ok, result = lib.callback.await('cm-house:server:getPhotoData', false, houseId)
    cb({
        ok = ok == true,
        dataUri = ok == true and result or nil,
        message = ok == true and nil or result,
    })
end)

RegisterNUICallback('door:clientError', function(d, cb)
    print(('[cm-house] Door NUI error (%s): %s')
        :format(tostring(d and d.phase or 'unknown'), tostring(d and d.message or 'unknown error')))
    cb({ ok = true })
end)

RegisterNUICallback('door:close', function(_, cb)
    closeMenu()
    cb({})
end)

RegisterNUICallback('door:toggleLock', function(d, cb)
    local ok, msg, locked = lib.callback.await('cm-house:server:toggleLock', false, d.houseId)
    if not ok then
        lib.notify({ description = msg, type = 'error' })
    else
        PlaySoundFrontend(-1, locked and 'Lock' or 'Unlock',
            'DLC_HEIST_HACKING_SNAKE_SOUNDS', true)
    end
    cb({ ok = ok, locked = locked, message = msg })
end)

RegisterNUICallback('door:enterHome', function(d, cb)
    cb({})
    closeMenu()
    TriggerEvent('cm-house:client:enterHome', d.houseId)
end)

RegisterNUICallback('door:openGarage', function(d, cb)
    cb({})
    closeMenu()
    TriggerEvent('cm-house:client:openGarage', d.houseId)
end)

RegisterNUICallback('door:activity', function(d, cb)
    local rows, reason = lib.callback.await('cm-house:server:getHouseActivity', false, d.houseId)
    if type(rows) ~= 'table' then
        lib.notify({ description = reason or 'Activity is unavailable.', type = 'error' })
        cb({ ok = false })
        return
    end
    local options = {}
    for _, row in ipairs(rows) do
        local detail = type(row.detail) == 'string' and row.detail or ''
        options[#options + 1] = {
            title = tostring(row.action or 'house activity'):gsub('_', ' '),
            description = ('%s (CID %s) · %s%s'):format(
                tostring(row.actorName or 'System'), tostring(row.cid or '—'),
                tostring(row.created_at or ''), detail ~= '' and (' · ' .. detail) or ''),
            icon = tostring(row.action or ''):find('weapon', 1, true) and 'gun'
                or (tostring(row.action or ''):find('garage', 1, true) and 'car'
                or (tostring(row.action or ''):find('heli', 1, true) and 'helicopter' or 'box-open')),
            disabled = true,
        }
    end
    if #options == 0 then options[1] = { title = 'No house activity yet', disabled = true } end
    closeMenu()
    lib.registerContext({ id = 'cm_house_activity', title = 'House Activity', options = options })
    lib.showContext('cm_house_activity')
    cb({ ok = true })
end)

RegisterNUICallback('door:buy', function(d, cb)
    local ok, msg = lib.callback.await('cm-house:server:buyHouse', false, d.houseId)
    lib.notify({ description = msg, type = ok and 'success' or 'error' })
    if ok then closeMenu() end
    cb({ ok = ok, message = msg })
end)

RegisterNUICallback('door:sell', function(d, cb)
    local confirm = lib.alertDialog({
        header   = 'Sell this house?',
        content  = 'It goes back on the market and you lose everything stored inside. This cannot be undone.',
        centered = true, cancel = true,
        labels   = { confirm = 'Sell it', cancel = 'Keep it' },
    })
    if confirm ~= 'confirm' then cb({ ok = false }) return end

    local ok, msg = lib.callback.await('cm-house:server:sellHouse', false, d.houseId)
    lib.notify({ description = msg, type = ok and 'success' or 'error' })
    if ok then closeMenu() end
    cb({ ok = ok, message = msg })
end)

-- ------------------------------------------------------------
--  Sync
-- ------------------------------------------------------------
RegisterNetEvent('cm-house:client:syncHouse', function(h)
    Houses[h.id] = h
    refreshBlip(h)

    -- The return zone is where you DRIVE IN to park. cl_garage watches it.
    if h.garage then
        TriggerEvent('cm-house:client:syncGarageZone', h.id, h.garage)
    end
end)

RegisterNetEvent('cm-house:client:syncOwnership', function(owned)
    MyHouses = owned or {}
    for _, h in pairs(Houses) do refreshBlip(h) end
    CreateThread(refreshVisibleHelipads)
end)

RegisterNetEvent('cm-house:client:syncLock', function(houseId, locked)
    local h = Houses[houseId]
    if h then h.locked = locked end
    if menuOpen then
        SendNUIMessage({ action = 'updateLock', data = { houseId = houseId, locked = locked } })
    end
end)

local function bootstrap()
    local list = lib.callback.await('cm-house:server:getAllHouses', false)
    for _, h in ipairs(list or {}) do
        Houses[h.id] = h
        refreshBlip(h)
        if h.garage then
            TriggerEvent('cm-house:client:syncGarageZone', h.id, h.garage)
        end
    end
    if Config.Debug then
        print(('[cm-house] %d houses loaded'):format(#(list or {})))
    end
    refreshVisibleHelipads()
end

AddEventHandler('onClientResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    Wait(500)
    bootstrap()
end)

RegisterNetEvent('cm-playerdata:client:characterLoaded', function()
    bootstrap()
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, b in pairs(Blips) do RemoveBlip(b) end
    menuOpen = false
    stopLiveCam()
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    FreezeEntityPosition(PlayerPedId(), false)
end)

--- /housefix -- break out of a stuck menu or camera.
--- The NUI can, in principle, swallow every key. This cannot.
RegisterCommand('housefix', function()
    CloseDoorMenu()
    SetNuiFocus(false, false)
    RenderScriptCams(false, false, 0, true, true)
    ClearFocus()
    DisplayRadar(true)
    FreezeEntityPosition(PlayerPedId(), false)
    DoScreenFadeIn(200)
    lib.notify({ description = 'Menu and camera reset.', type = 'success' })
end, false)
