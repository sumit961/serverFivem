-- cm-playerdata/client/interactions.lua
-- V1.5: NUI-rendered overhead identity labels (custom font) + look-at-player G prompt
-- + numbered hex interaction menu (Grand-RP style, number keys 1-9, RMB = back).
-- Privacy rule unchanged: real names only after same org/family, shared ID, or handshake.
-- Server ID/source stays internal; only database character IDs are ever shown.

local Root = CMPlayerData or {}
local Config = Root.Config or {}
local InteractionConfig = Config.Interactions or {}

print('[CM-PLAYERDATA-INTERACTIONS] client/interactions.lua loaded (v1.5 NUI labels)')

local identityCache = {}
local nearbyPlayers = {}        -- refreshed slowly; only players inside label/look range
local currentTarget = nil
local menuOpen = false
local menuTarget = nil
local currentPage = 'main'
local currentOptions = {}
local pageStack = {}
local lastTargetScan = 0
local lastIdentityRequest = 0
local labelsWereVisible = false
local labelsEnabled = InteractionConfig.OverheadLabels ~= false
local debugEnabled = InteractionConfig.Debug == true

-- Controls: number row 1-9 (weapon-select controls), RMB (aim), ESC, G
local NUMBER_CONTROLS = { 157, 158, 160, 164, 165, 159, 161, 162, 163 }
local CONTROL_RMB = 25
local CONTROL_ESC = 200
local CONTROL_G = 47

local function Debug(message)
    if debugEnabled then
        print('[CM-PLAYERDATA-INTERACTIONS] ' .. tostring(message))
    end
end

local function GetCfg(name, fallback)
    local value = InteractionConfig[name]
    if value == nil then return fallback end
    return value
end

local function Notify(message, msgType)
    msgType = msgType or 'inform'

    if GetResourceState('ox_lib') == 'started' and type(lib) == 'table' and type(lib.notify) == 'function' then
        lib.notify({
            title = 'Player Interaction',
            description = message,
            type = msgType
        })
        return
    end

    TriggerEvent('chat:addMessage', {
        color = msgType == 'error' and {255, 80, 80} or {120, 220, 255},
        args = {'Player Interaction', message}
    })
end

-- Labels stay visible even while the viewer is dead (you can watch who is
-- around your body). Only opening the interaction menu requires being alive.
local function IsReadyForInteraction()
    if GetCfg('Enabled', true) == false then return false end
    if IsPauseMenuActive() then return false end
    if LocalPlayer and LocalPlayer.state then
        if LocalPlayer.state.isInCharacterSelector == true then return false end
    end
    return true
end

local function CanInteract()
    if not IsReadyForInteraction() then return false end
    if LocalPlayer and LocalPlayer.state and LocalPlayer.state.isDead == true then return false end
    return true
end

-- Labels stay visible on dead players (bodies keep their name/ID).
local function IsPedValidLabelTarget(ped)
    if not ped or ped == 0 then return false end
    if not DoesEntityExist(ped) then return false end
    if not IsEntityAPed(ped) then return false end
    if not IsPedAPlayer(ped) then return false end
    return true
end

-- Interaction (G menu) still requires the target to be alive.
local function IsPedValidPlayerTarget(ped)
    if not IsPedValidLabelTarget(ped) then return false end
    if IsEntityDead(ped) then return false end
    return true
end

local function GetIdentity(serverId)
    serverId = tonumber(serverId)
    if not serverId then
        return { serverId = nil, displayName = 'Stranger', known = false, reason = 'none', identityId = nil }
    end

    return identityCache[serverId] or {
        serverId = serverId, -- internal only, never shown in UI
        displayName = 'Stranger',
        known = false,
        reason = 'waiting_for_character_id',
        identityId = nil
    }
end

local function GetCharacterIdForServerId(serverId)
    local identity = GetIdentity(serverId)
    return tonumber(identity.identityId or identity.characterId or identity.charId)
end

local function GetIdentityTitle(serverId, allowLoading)
    local identity = GetIdentity(serverId)
    local charId = GetCharacterIdForServerId(serverId)

    -- IMPORTANT: server ID/source is internal only and is never shown to players.
    if not charId then
        if allowLoading == true then
            return identity.displayName or 'Stranger', 'ID: Loading...'
        end
        return nil, nil
    end

    return identity.displayName or 'Stranger', ('ID: %s'):format(charId)
end

local function RotationToDirection(rotation)
    local z = math.rad(rotation.z)
    local x = math.rad(rotation.x)
    local num = math.abs(math.cos(x))

    return vector3(
        -math.sin(z) * num,
        math.cos(z) * num,
        math.sin(x)
    )
end

local function GetTargetFromPed(ped)
    if not IsPedValidLabelTarget(ped) then return nil end

    local playerIndex = NetworkGetPlayerIndexFromPed(ped)
    if playerIndex == -1 or playerIndex == PlayerId() then return nil end

    local serverId = GetPlayerServerId(playerIndex)
    if not serverId or serverId <= 0 then return nil end

    return {
        player = playerIndex,
        serverId = serverId,
        ped = ped,
        coords = GetEntityCoords(ped)
    }
end

-- Synchronous probe: result is valid immediately, unlike StartShapeTestRay
-- whose handle is often "not ready" when read on the same frame.
local function RaycastCamera(maxDistance)
    local camCoords = GetGameplayCamCoords()
    local direction = RotationToDirection(GetGameplayCamRot(2))
    local destination = camCoords + (direction * (maxDistance or 5.0))

    local handle = StartExpensiveSynchronousShapeTestLosProbe(
        camCoords.x, camCoords.y, camCoords.z,
        destination.x, destination.y, destination.z,
        12,
        PlayerPedId(),
        7
    )

    local _, hit, endCoords, _, entityHit = GetShapeTestResult(handle)
    if hit == 1 then
        local target = GetTargetFromPed(entityHit)
        if target then
            target.hitCoords = endCoords
            return target
        end
    end

    return nil
end

local function HasClearView(localPed, targetPed)
    if GetCfg('RequireLineOfSight', false) == false then return true end
    if HasEntityClearLosToEntity(localPed, targetPed, 17) then return true end
    if type(HasEntityClearLosToEntityInFront) == 'function' and HasEntityClearLosToEntityInFront(localPed, targetPed) then return true end
    return false
end

local function ScorePlayerLookTarget(entry, localPed, localCoords, camCoords, camDirection, maxDistance)
    local ped = entry.ped
    if not IsPedValidLabelTarget(ped) then return nil end

    local coords = GetEntityCoords(ped)
    local distanceFromPlayer = #(localCoords - coords)
    if distanceFromPlayer > maxDistance then return nil end
    if not HasClearView(localPed, ped) then return nil end

    local points = {
        GetPedBoneCoords(ped, 0x796E, 0.0, 0.0, 0.08), -- head
        GetPedBoneCoords(ped, 0x60F0, 0.0, 0.0, 0.0), -- chest/spine
        vector3(coords.x, coords.y, coords.z + 0.85),
        vector3(coords.x, coords.y, coords.z + 0.45)
    }

    local bestScore = nil
    local requiredDot = GetCfg('LookDotThreshold', 0.90)

    for _, point in ipairs(points) do
        local toTarget = point - camCoords
        local targetDist = #(toTarget)
        if targetDist > 0.1 then
            local dirToTarget = vector3(toTarget.x / targetDist, toTarget.y / targetDist, toTarget.z / targetDist)
            local dot = camDirection.x * dirToTarget.x + camDirection.y * dirToTarget.y + camDirection.z * dirToTarget.z

            if dot >= requiredDot then
                local score = dot - (distanceFromPlayer * 0.006)
                if not bestScore or score > bestScore then
                    bestScore = score
                end
            end
        end
    end

    if not bestScore then return nil end

    return {
        player = entry.player,
        serverId = entry.serverId,
        ped = ped,
        coords = coords,
        score = bestScore
    }
end

local function GetBestLookAtPlayer(maxDistance)
    local localPed = PlayerPedId()
    local localCoords = GetEntityCoords(localPed)
    local camCoords = GetGameplayCamCoords()
    local camDirection = RotationToDirection(GetGameplayCamRot(2))

    local bestTarget = nil
    local bestScore = -999.0

    for _, entry in ipairs(nearbyPlayers) do
        local target = ScorePlayerLookTarget(entry, localPed, localCoords, camCoords, camDirection, maxDistance)
        if target and target.score > bestScore then
            bestScore = target.score
            bestTarget = target
        end
    end

    return bestTarget
end

local function FindLookTarget()
    local maxDistance = GetCfg('LookDistance', GetCfg('Distance', 4.5))

    local rayTarget = RaycastCamera(maxDistance)
    if rayTarget then
        local localCoords = GetEntityCoords(PlayerPedId())
        if #(localCoords - rayTarget.coords) <= maxDistance then
            return rayTarget
        end
    end

    return GetBestLookAtPlayer(maxDistance)
end

-- ---------------------------------------------------------------------------
-- Slow scan: keep a short list of players inside label/look range.
-- The per-frame loop only ever touches this list.
-- ---------------------------------------------------------------------------
local function RefreshNearbyPlayers()
    local list = {}
    local localCoords = GetEntityCoords(PlayerPedId())
    local limit = math.max(GetCfg('OverheadDistance', 18.0), GetCfg('LookDistance', 4.5)) + 3.0
    local myIndex = PlayerId()

    for _, playerIndex in ipairs(GetActivePlayers()) do
        if playerIndex ~= myIndex then
            local ped = GetPlayerPed(playerIndex)
            if IsPedValidLabelTarget(ped) then
                local coords = GetEntityCoords(ped)
                local dist = #(localCoords - coords)
                if dist <= limit then
                    local sid = GetPlayerServerId(playerIndex)
                    if sid and sid > 0 then
                        list[#list + 1] = {
                            player = playerIndex,
                            ped = ped,
                            serverId = sid,
                            dist = dist
                        }
                    end
                end
            end
        end
    end

    nearbyPlayers = list
end

local function RequestNearbyIdentities(force)
    local now = GetGameTimer()
    local interval = GetCfg('IdentityRefreshInterval', 2000)
    if not force and now - lastIdentityRequest < interval then return end
    lastIdentityRequest = now

    local ids = {}
    for _, entry in ipairs(nearbyPlayers) do
        ids[#ids + 1] = entry.serverId
    end

    if #ids > 0 then
        TriggerServerEvent('cm-playerdata:server:requestIdentityBatch', ids)
    end
end

-- ---------------------------------------------------------------------------
-- NUI overhead labels + target prompt
-- ---------------------------------------------------------------------------
local function BuildLabelPayload()
    local labels = {}
    local localPed = PlayerPedId()
    local distanceLimit = GetCfg('OverheadDistance', 18.0)
    local targetServerId = (not menuOpen and currentTarget) and currentTarget.serverId or nil
    local gPrompt = nil

    for _, entry in ipairs(nearbyPlayers) do
        local ped = entry.ped
        if IsPedValidLabelTarget(ped) then
            local coords = GetEntityCoords(ped)
            local dist = #(GetEntityCoords(localPed) - coords)
            local isDeadPed = IsEntityDead(ped)
            local isTarget = (entry.serverId == targetServerId)

            if (labelsEnabled and dist <= distanceLimit and HasClearView(localPed, ped)) or isTarget then
                local nameLine, idLine = GetIdentityTitle(entry.serverId, isTarget)
                if nameLine and idLine then
                    -- Anchor to the entity position, not a bone: head/idle animation
                    -- movement must never make the label wobble.
                    local base = GetEntityCoords(ped)
                    local zOffset = GetCfg('OverheadZOffset', 1.06)
                    if isDeadPed then
                        -- Body is lying down; hover the label just above it.
                        zOffset = GetCfg('DeadZOffset', 0.45)
                    end
                    local onScreen, sx, sy = World3dToScreen2d(base.x, base.y, base.z + zOffset)
                    if onScreen then
                        local scale = 1.18 - (dist * 0.034)
                        if scale < 0.55 then scale = 0.55 end
                        if scale > 1.15 then scale = 1.15 end

                        labels[#labels + 1] = {
                            x = sx,
                            y = sy,
                            s = math.floor(scale * 100) / 100,
                            name = nameLine,
                            id = idLine,
                            t = isTarget or nil
                        }
                    end
                end

                if isTarget then
                    local base = GetEntityCoords(ped)
                    local bodyOnScreen, bx, by = World3dToScreen2d(base.x, base.y, base.z + GetCfg('PromptZOffset', 0.12))
                    if bodyOnScreen then
                        gPrompt = { x = bx, y = by }
                    end
                end
            end
        end
    end

    return labels, gPrompt
end

local function PushLabels()
    local labels, gPrompt = BuildLabelPayload()

    if #labels == 0 and not gPrompt then
        if labelsWereVisible then
            SendNUIMessage({ action = 'labels', labels = {} })
            labelsWereVisible = false
        end
        return
    end

    SendNUIMessage({
        action = 'labels',
        labels = labels,
        g = gPrompt
    })
    labelsWereVisible = true
end

local function DrawTargetMarker(target)
    if not target or not IsPedValidPlayerTarget(target.ped) then return end

    local accent = GetCfg('AccentColour', { r = 0, g = 230, b = 255, a = 255 })
    local coords = GetEntityCoords(target.ped)
    local groundZ = coords.z - 0.95

    DrawMarker(
        25,
        coords.x, coords.y, groundZ,
        0.0, 0.0, 0.0,
        0.0, 0.0, 0.0,
        0.82, 0.82, 0.035,
        accent.r or 0, accent.g or 210, accent.b or 255, 150,
        false, false, 2, false, nil, nil, false
    )
end

-- ---------------------------------------------------------------------------
-- Hex menu (NUI). No NUI focus: number keys 1-9 select, RMB = back, ESC/G = close.
-- ---------------------------------------------------------------------------
local function BuildPage(page)
    page = page or 'main'
    local showWIP = GetCfg('ShowWIPActions', false) == true

    if page == 'main' then
        return {
            { id = 'basic', label = 'Basic Actions', icon = 'people', type = 'page', page = 'basic' },
            { id = 'documents', label = 'Documents', icon = 'documents', type = 'page', page = 'documents' },
            { id = 'organization', label = 'Organization', icon = 'organization', type = 'page', page = 'organization' },
            { id = 'family', label = 'Family Menu', icon = 'family', type = 'page', page = 'family' },
            { id = 'status', label = 'Check Status', icon = 'status', type = 'client', action = 'check_status' },
            { id = 'close', label = 'Close', icon = 'close', type = 'close' }
        }
    elseif page == 'basic' then
        local options = {
            { id = 'handshake', label = 'Handshake', icon = 'handshake', type = 'server', action = 'handshake' },
            { id = 'show_id', label = 'Share ID', icon = 'id', type = 'server', action = 'share_id' },
            { id = 'greet', label = 'Say Hello', icon = 'hello', type = 'server', action = 'greet' },
            { id = 'give_cash', label = 'Give Cash', icon = 'cash', type = 'cash' }
        }
        if showWIP then
            options[#options + 1] = { id = 'search_player', label = 'Search Player', icon = 'search', type = 'server', action = 'search_player' }
            options[#options + 1] = { id = 'escort_player', label = 'Escort / Carry', icon = 'escort', type = 'server', action = 'escort_player' }
        end
        options[#options + 1] = { id = 'back', label = 'Back', icon = 'back', type = 'back' }
        return options
    elseif page == 'documents' then
        return {
            { id = 'show_id', label = 'Show ID Card', icon = 'id', type = 'server', action = 'share_id' },
            { id = 'show_license', label = 'Show License', icon = 'license', type = 'server', action = 'show_license' },
            { id = 'show_documents', label = 'Show Documents', icon = 'documents', type = 'server', action = 'show_documents' },
            { id = 'back', label = 'Back', icon = 'back', type = 'back' }
        }
    elseif page == 'organization' then
        return {
            { id = 'org_invite', label = 'Invite to Org', icon = 'organization', type = 'server', action = 'org_invite' },
            { id = 'org_rank', label = 'Org Rank', icon = 'documents', type = 'server', action = 'org_rank' },
            { id = 'back', label = 'Back', icon = 'back', type = 'back' }
        }
    elseif page == 'dead' then
        return {
            { id = 'check_pulse', label = 'Check Pulse', icon = 'status', type = 'client', action = 'check_status' },
            { id = 'treat_player', label = 'Patch / Treat', icon = 'people', type = 'server', action = 'treat_player' },
            { id = 'close', label = 'Close', icon = 'close', type = 'close' }
        }
    elseif page == 'family' then
        return {
            { id = 'family_invite', label = 'Invite Family', icon = 'family', type = 'server', action = 'family_invite' },
            { id = 'family_info', label = 'Family Info', icon = 'people', type = 'server', action = 'family_info' },
            { id = 'back', label = 'Back', icon = 'back', type = 'back' }
        }
    end

    return BuildPage('main')
end

local function SendMenuPage()
    if not menuOpen or not menuTarget then return end

    currentOptions = BuildPage(currentPage)

    local nameLine, idLine = GetIdentityTitle(menuTarget.serverId, true)
    SendNUIMessage({
        action = 'openRadial',
        page = currentPage,
        title = nameLine,
        subtitle = idLine,
        hint = 'CLICK OR PRESS 1-9 TO SELECT  |  RIGHT MOUSE = BACK  |  ESC = CLOSE',
        options = currentOptions
    })
end

local function CloseMenu()
    menuOpen = false
    menuTarget = nil
    currentPage = 'main'
    currentOptions = {}
    pageStack = {}
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeRadial' })
end

local function OpenMenu(target)
    if not target or not target.serverId then return end
    menuOpen = true
    menuTarget = target
    -- Unconscious body: only treatment actions make sense.
    currentPage = IsEntityDead(target.ped) and 'dead' or 'main'
    pageStack = {}
    -- Cursor visible, camera frozen, all keyboard/mouse input goes to the UI.
    -- KeepInput explicitly false: another resource may have toggled it globally,
    -- which would leak clicks/keys into the game (shooting/reloading in menu).
    SetNuiFocusKeepInput(false)
    SetNuiFocus(true, true)
    SendMenuPage()
end

local function BackMenu()
    if #pageStack > 0 then
        currentPage = pageStack[#pageStack]
        pageStack[#pageStack] = nil
        SendMenuPage()
    else
        CloseMenu()
    end
end

local function HandleOption(option)
    if not option or not menuTarget then return end

    local targetPed = menuTarget.ped
    local targetServerId = menuTarget.serverId

    if not IsPedValidLabelTarget(targetPed) then
        Notify('Target player is no longer nearby.', 'error')
        CloseMenu()
        return
    end

    if option.type == 'close' then
        CloseMenu()
        return
    elseif option.type == 'back' then
        BackMenu()
        return
    elseif option.type == 'page' then
        pageStack[#pageStack + 1] = currentPage
        currentPage = option.page or 'main'
        SendMenuPage()
        return
    elseif option.type == 'client' and option.action == 'check_status' then
        local health = GetEntityHealth(targetPed)
        local armor = GetPedArmour(targetPed)
        local charId = GetCharacterIdForServerId(targetServerId)
        Notify(('Character ID %s | Health %s | Armor %s'):format(charId or 'Loading', health, armor), 'inform')
        CloseMenu()
        return
    elseif option.type == 'cash' then
        local sid = targetServerId
        CloseMenu()
        CreateThread(function()
            local amount = 100
            if GetResourceState('ox_lib') == 'started' and type(lib) == 'table' and type(lib.inputDialog) == 'function' then
                local maxGift = GetCfg('MaxCashGift', 1000)
                local input = lib.inputDialog('Give Cash', {
                    { type = 'number', label = ('Amount ($1 - $%s)'):format(maxGift), default = 100, min = 1, max = maxGift, required = true }
                })
                if not input or not tonumber(input[1]) then return end
                amount = math.floor(tonumber(input[1]))
            end
            TriggerServerEvent('cm-playerdata:server:giveCashToPlayer', sid, amount)
        end)
        return
    end

    local action = tostring(option.action or 'unknown')
    TriggerServerEvent('cm-playerdata:server:playerInteraction', targetServerId, action)
    TriggerEvent('cm-playerdata:client:interactionSelected', action, targetServerId)
    CloseMenu()
end

local function HandleMenuControls()
    -- Input is handled by NUI while the menu has focus. These disables are a
    -- safety net in case any resource re-enables game input under NUI focus:
    -- no shooting, aiming, reloading or weapon switching under the menu.
    DisableControlAction(0, 24, true)  -- attack
    DisableControlAction(0, 25, true)  -- aim
    DisableControlAction(0, 45, true)  -- reload
    DisableControlAction(0, 37, true)  -- weapon wheel
    DisableControlAction(0, 140, true)
    DisableControlAction(0, 141, true)
    DisableControlAction(0, 142, true)
    DisableControlAction(0, 257, true)
    DisableControlAction(0, 263, true)

    -- Watchdog: auto-close if the target left or walked out of validation range.
    -- (Dead bodies are valid targets: the dead page offers treatment actions.)
    if menuTarget then
        if not IsPedValidLabelTarget(menuTarget.ped) then
            CloseMenu()
            return
        end

        -- Target died while the menu was open: switch to the treatment page.
        if IsEntityDead(menuTarget.ped) and currentPage ~= 'dead' then
            currentPage = 'dead'
            pageStack = {}
            SendMenuPage()
            return
        end
        local dist = #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(menuTarget.ped))
        if dist > (GetCfg('ServerMaxDistance', 5.0) + 1.5) then
            Notify('Target player moved away.', 'error')
            CloseMenu()
        end
    end
end

-- ---------------------------------------------------------------------------
-- Threads
-- ---------------------------------------------------------------------------
CreateThread(function()
    while true do
        RefreshNearbyPlayers()
        RequestNearbyIdentities(false)
        Wait(400)
    end
end)

CreateThread(function()
    while true do
        local sleep = 250

        if not IsReadyForInteraction() then
            currentTarget = nil
            if menuOpen then CloseMenu() end
            if labelsWereVisible then
                SendNUIMessage({ action = 'labels', labels = {} })
                labelsWereVisible = false
            end
        elseif #nearbyPlayers > 0 or menuOpen then
            sleep = 0

            local viewerCanInteract = CanInteract()
            if menuOpen and not viewerCanInteract then
                CloseMenu()
            end

            local now = GetGameTimer()
            if not menuOpen and viewerCanInteract and now - lastTargetScan >= GetCfg('TargetScanInterval', 70) then
                lastTargetScan = now
                currentTarget = FindLookTarget()
            elseif not viewerCanInteract then
                currentTarget = nil
            end

            PushLabels()

            if menuOpen then
                HandleMenuControls()
            elseif currentTarget then
                DrawTargetMarker(currentTarget)
            end
        else
            currentTarget = nil
            if labelsWereVisible then
                SendNUIMessage({ action = 'labels', labels = {} })
                labelsWereVisible = false
            end
        end

        Wait(sleep)
    end
end)

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
RegisterNetEvent('cm-playerdata:client:identityBatch', function(items)
    if type(items) ~= 'table' then return end
    for _, item in ipairs(items) do
        local sid = tonumber(item.id or item.serverId)
        if sid then
            identityCache[sid] = item
        end
    end
    if menuOpen then SendMenuPage() end
end)

RegisterNetEvent('cm-playerdata:client:identityUpdate', function(item)
    if type(item) ~= 'table' then return end
    local sid = tonumber(item.id or item.serverId)
    if sid then
        identityCache[sid] = item
    end
    if menuOpen then SendMenuPage() end
end)

-- Server IDs are recycled by FiveM. Purge the cache entry the moment a player
-- drops so a new player reusing that ID never inherits the old identity/name.
RegisterNetEvent('cm-playerdata:client:identityRemove', function(serverId)
    local sid = tonumber(serverId)
    if not sid then return end
    identityCache[sid] = nil
    if menuOpen and menuTarget and menuTarget.serverId == sid then
        CloseMenu()
    end
end)

RegisterNetEvent('cm-playerdata:client:interactionNotify', function(message, msgType)
    Notify(message, msgType)
end)

-- ---------------------------------------------------------------------------
-- NUI callbacks (menu has focus while open: clicks, number keys, RMB, ESC)
-- ---------------------------------------------------------------------------
RegisterNUICallback('selectOption', function(payload, cb)
    cb({})
    local index = tonumber(payload and payload.index)
    if menuOpen and index and currentOptions[index] then
        HandleOption(currentOptions[index])
    end
end)

RegisterNUICallback('backMenu', function(_, cb)
    cb({})
    if menuOpen then BackMenu() end
end)

RegisterNUICallback('closeMenu', function(_, cb)
    cb({})
    if menuOpen then CloseMenu() end
end)

-- ---------------------------------------------------------------------------
-- Interaction animations. kind maps into Config.Interactions.Anims; if the
-- other player's server ID is given, face them first (handshakes look right).
-- ---------------------------------------------------------------------------
RegisterNetEvent('cm-playerdata:client:interactionAnim', function(kind, otherServerId)
    local anims = GetCfg('Anims', {})
    if anims.Enabled == false then return end

    local anim = anims[tostring(kind)]
    if not anim or not anim.dict or not anim.clip then return end

    local ped = PlayerPedId()
    if IsEntityDead(ped) then return end

    -- Turn toward the other participant so paired emotes line up.
    otherServerId = tonumber(otherServerId)
    if otherServerId then
        local otherIndex = GetPlayerFromServerId(otherServerId)
        if otherIndex ~= -1 then
            local otherPed = GetPlayerPed(otherIndex)
            if otherPed ~= 0 and DoesEntityExist(otherPed) then
                TaskTurnPedToFaceEntity(ped, otherPed, 750)
                Wait(750)
            end
        end
    end

    RequestAnimDict(anim.dict)
    local tries = 0
    while not HasAnimDictLoaded(anim.dict) and tries < 100 do
        Wait(10)
        tries = tries + 1
    end
    if not HasAnimDictLoaded(anim.dict) then return end

    ped = PlayerPedId()
    TaskPlayAnim(ped, anim.dict, anim.clip, 8.0, -8.0, anim.duration or 3000, anim.flag or 0, 0.0, false, false, false)

    SetTimeout((anim.duration or 3000) + 200, function()
        local currentPed = PlayerPedId()
        if IsEntityPlayingAnim(currentPed, anim.dict, anim.clip, 3) then
            StopAnimTask(currentPed, anim.dict, anim.clip, 1.0)
        end
    end)
end)

-- ---------------------------------------------------------------------------
-- Passport-style ID card (shown when someone shares their ID with you).
-- ---------------------------------------------------------------------------
RegisterNetEvent('cm-playerdata:client:showIdCard', function(card)
    if type(card) ~= 'table' then return end
    SendNUIMessage({
        action = 'showIdCard',
        card = card,
        duration = GetCfg('IdCardDuration', 10000)
    })
end)

RegisterCommand('cmplayerlabels', function()
    labelsEnabled = not labelsEnabled
    Notify(('Overhead labels %s'):format(labelsEnabled and 'enabled' or 'disabled'), 'inform')
end, false)

-- ---------------------------------------------------------------------------
-- Rebindable interact key (default G). Players can change it in
-- GTA Settings > Key Bindings > FiveM.
-- ---------------------------------------------------------------------------
RegisterCommand('+cm_interact', function()
    if menuOpen then
        CloseMenu()
        return
    end
    if not CanInteract() then return end
    if currentTarget then
        RequestNearbyIdentities(true)
        OpenMenu(currentTarget)
    end
end, false)
RegisterCommand('-cm_interact', function() end, false)
RegisterKeyMapping('+cm_interact', 'Interact with player', 'keyboard', 'G')

-- ---------------------------------------------------------------------------
-- Handshake consent: the target sees an accept prompt and must press E.
-- ---------------------------------------------------------------------------
local handshakePending = false

RegisterNetEvent('cm-playerdata:client:handshakeRequest', function(fromLabel, timeoutMs)
    if handshakePending then return end
    handshakePending = true

    local expires = GetGameTimer() + (tonumber(timeoutMs) or 15000)

    CreateThread(function()
        while handshakePending and GetGameTimer() < expires do
            Wait(0)

            if not IsReadyForInteraction() then break end

            BeginTextCommandDisplayHelp('STRING')
            AddTextComponentSubstringPlayerName(('%s offers a handshake. Press ~INPUT_PICKUP~ to accept.'):format(tostring(fromLabel or 'Someone')))
            EndTextCommandDisplayHelp(0, false, false, 1)

            if IsControlJustPressed(0, 38) then -- E
                TriggerServerEvent('cm-playerdata:server:handshakeResponse', true)
                Notify('You accepted the handshake.', 'success')
                break
            end
        end
        handshakePending = false
    end)
end)
