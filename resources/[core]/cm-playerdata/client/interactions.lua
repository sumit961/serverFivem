-- cm-playerdata/client/interactions.lua
-- V1.5: NUI-rendered overhead identity labels (custom font) + look-at-player G prompt
-- + numbered hex interaction menu (Grand-RP style, number keys 1-9, RMB = back).
-- Privacy rule unchanged: real names only after same org/family, shared ID, or handshake.
-- Server ID/source stays internal; only database character IDs are ever shown.

local Root = CMPlayerData or {}
local Config = Root.Config or {}
local InteractionConfig = Config.Interactions or {}

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
local lastLabelPush = 0
local currentTargetLastSeen = 0


-- Extensible G-menu registry. Future resources can register pages/options without
-- editing cm-playerdata. cm-playerdata only owns target detection, character ID
-- display, distance validation bridge and built-in basic/document actions.
local extensionPages = {}
local extensionOptions = {}
local extensionSequence = 0

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

-- True while the local player is sitting in (or entering) any vehicle.
local function IsLocalPlayerInVehicle()
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) == true then return true end
    if type(IsPedSittingInAnyVehicle) == 'function' and IsPedSittingInAnyVehicle(ped) == true then return true end
    local ok, veh = pcall(GetVehiclePedIsIn, ped, false)
    if ok and veh and veh ~= 0 then return true end
    return false
end

local function CanInteract()
    if not IsReadyForInteraction() then return false end
    if LocalPlayer and LocalPlayer.state and LocalPlayer.state.isDead == true then return false end
    -- No player G-menu/prompt while the viewer is inside a vehicle. Overhead
    -- labels still show; only the interaction target/prompt is suppressed.
    if GetCfg('BlockInteractionWhenViewerInVehicle', true) ~= false and IsLocalPlayerInVehicle() then return false end
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

-- A player is "downed"/unconscious when the framework flags them dead via the
-- replicated state bag. IsEntityDead is NOT reliable here: this framework keeps
-- a downed player alive at Vitals.DamageThreshold, so the ped never reports as
-- dead to natives. We prefer the state bag and only fall back to the native.
local function IsPedDowned(ped, serverId)
    if not ped or ped == 0 then return false end

    if not serverId then
        local idx = NetworkGetPlayerIndexFromPed(ped)
        if idx and idx ~= -1 then
            serverId = GetPlayerServerId(idx)
        end
    end

    if serverId and serverId > 0 then
        local ok, state = pcall(function() return Player(serverId).state end)
        if ok and state and state.isDead == true then return true end
    end

    -- Hard fallback for a genuinely dead ped (0 HP) with no state bag yet.
    if IsEntityDead(ped) then return true end
    return false
end

-- Interaction (G menu) still requires the target to be alive.
local function IsTargetInVehicle(ped)
    if not IsPedValidLabelTarget(ped) then return false end

    -- Remote peds can report vehicle state inconsistently for one frame.
    -- Check every cheap native so a seated player never stays targetable for G.
    if IsPedInAnyVehicle(ped, false) == true then return true end
    if type(IsPedSittingInAnyVehicle) == 'function' and IsPedSittingInAnyVehicle(ped) == true then return true end

    local ok, veh = pcall(GetVehiclePedIsIn, ped, false)
    if ok and veh and veh ~= 0 then return true end

    return false
end

local function IsPedValidPlayerTarget(ped)
    if not IsPedValidLabelTarget(ped) then return false end
    if IsEntityDead(ped) then return false end
    -- Labels stay visible in vehicles, but player G-menu interactions are disabled
    -- while the target is inside a vehicle. Vehicle interaction belongs to the
    -- vehicle G-menu/resource, not playerdata.
    if GetCfg('BlockInteractionWhenTargetInVehicle', true) ~= false and IsTargetInVehicle(ped) then return false end
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

local function GetAdminTag(serverId)
    serverId = tonumber(serverId)
    if not serverId or serverId <= 0 then return nil end

    local state = Player(serverId).state
    local tag = state and state.cm_admin_tag or nil
    if type(tag) ~= 'table' or tag.active ~= true then return nil end
    if tag.noclip == true or (state and state.cm_admin_noclip == true) then return nil end

    return tag
end

local function HexToRgb(hex)
    hex = tostring(hex or '#00f0ff'):gsub('#', '')
    if #hex ~= 6 then return { r = 0, g = 240, b = 255, a = 245 } end
    return {
        r = tonumber(hex:sub(1, 2), 16) or 0,
        g = tonumber(hex:sub(3, 4), 16) or 240,
        b = tonumber(hex:sub(5, 6), 16) or 255,
        a = 245,
    }
end

local FAMILY_SYMBOLS = {
    crown = { texture = 'crown', glyph = '♛' },
    flower = { texture = 'flower', glyph = '✿' },
    star = { texture = 'star', glyph = '★' },
    shield = { texture = 'shield', glyph = '⬟' },
    diamond = { texture = 'diamond', glyph = '♦' },
    skull = { glyph = '☠' },
    heart = { glyph = '♥' },
    bolt = { glyph = 'ϟ' },
    moon = { glyph = '☾' },
    sun = { glyph = '☀' },
}

local FAMILY_SYMBOL_TXD = 'cm_family_symbols'
local familySymbolTextureReady = {}

CreateThread(function()
    local okTxd, txd = pcall(CreateRuntimeTxd, FAMILY_SYMBOL_TXD)
    if not okTxd or not txd then return end
    for key, entry in pairs(FAMILY_SYMBOLS) do
        if entry.texture then
        -- CreateRuntimeTextureFromImage resolves files declared in the current
        -- resource manifest, so no server-only filesystem path lookup is used.
        local path = ('ui/family_symbols/%s.png'):format(entry.texture)
        local ok = pcall(CreateRuntimeTextureFromImage, txd, entry.texture, path)
        familySymbolTextureReady[key] = ok == true
        end
    end
end)

local function IsFamilySymbolMasked(state)
    if GetCfg('HideFamilySymbolWhenMasked', true) ~= true or not state then return false end
    local keys = GetCfg('FamilyMaskedStateKeys', { 'cm_masked', 'masked', 'isMasked', 'mask_on' })
    for _, key in ipairs(keys) do
        local value = state[key]
        if value == true or value == 1 or value == '1' then return true end
    end
    return false
end

local function GetFamilySymbol(serverId)
    if GetCfg('ShowFamilySymbols', true) ~= true then return nil, nil end
    local state = Player(tonumber(serverId) or -1).state
    local family = state and state.cmFamily or nil
    if type(family) ~= 'table' or family.active ~= true or family.symbolVisible == false then return nil, nil end
    if IsFamilySymbolMasked(state) then return nil, nil end

    local symbol = tostring(family.symbol or 'shield'):lower()
    if not FAMILY_SYMBOLS[symbol] then symbol = 'shield' end
    return symbol, HexToRgb(family.symbolColor or family.color)
end

local function GetIdentityTitle(serverId, allowLoading)
    local identity = GetIdentity(serverId)
    local charId = GetCharacterIdForServerId(serverId)
    local adminTag = GetAdminTag(serverId)

    if adminTag then
        local adminName = adminTag.name or identity.displayName or 'Admin'
        local adminId = adminTag.characterId or charId

        -- If the admin character ID is still loading, do not show server/source ID.
        if not adminId then
            if allowLoading == true then
                return GetCfg('AdminLabelText', 'Administrator'), adminName .. ' (...)', true
            end
            return nil, nil
        end

        return GetCfg('AdminLabelText', 'Administrator'), ('%s  ID: %s'):format(adminName, adminId), true
    end

    -- IMPORTANT: server ID/source is internal only and is never shown to players.
    if not charId then
        if allowLoading == true then
            return identity.displayName or 'Stranger', '(...)', false
        end
        return nil, nil
    end

    return identity.displayName or 'Stranger', ('ID: %s'):format(charId), false
end

local function GetIdentityLabel(serverId, allowLoading, ped, isTarget)
    local nameLine, idLine, isAdmin = GetIdentityTitle(serverId, allowLoading)
    if not nameLine or not idLine then return nil, nil, isAdmin, nil, nil, nil end

    local statusLine = nil
    if not isAdmin and ped and IsPedValidLabelTarget(ped) and IsPedDowned(ped, serverId) then
        statusLine = GetCfg('DownedLabelText', 'Unconscious')
    end

    local familySymbol, familyColour
    if not isAdmin or GetCfg('ShowFamilySymbolInAdminMode', false) == true then
        familySymbol, familyColour = GetFamilySymbol(serverId)
    end
    return nameLine, idLine, isAdmin, statusLine, familySymbol, familyColour
end

-- Vehicle the ped is in, ENTERING (mid F-animation), or attached to (trunk).
-- Including the entering vehicle is what keeps the label from dropping to car
-- level during the get-in animation.
local function GetLabelVehicleForPed(ped)
    local okv, v = pcall(GetVehiclePedIsIn, ped, false)
    if okv and v and v ~= 0 then return v end
    local oke, ent = pcall(GetVehiclePedIsEntering, ped)
    if oke and ent and ent ~= 0 then return ent end
    local oka, att = pcall(GetEntityAttachedTo, ped)
    if oka and att and att ~= 0 and IsEntityAVehicle(att) then return att end
    return nil
end

-- Cached vehicle-local label offset per player, so a seated label becomes a fixed
-- point in the car's frame -- it moves ONLY when the car moves, with no per-frame
-- head-bone jitter/swim while driving.
local vehicleLabelOffsets = {}

local function ComputeVehicleLocalOffset(ped, veh, base)
    local refX, refY, refZ = base.x, base.y, base.z + 0.62
    local okh, head = pcall(GetPedBoneCoords, ped, 0x796E, 0.0, 0.0, 0.0)
    if okh and head and head.x then
        refX, refY, refZ = head.x, head.y, head.z
    end
    local lift = tonumber(GetCfg('VehicleHeadLift', 0.58)) or 0.58
    local oko, off = pcall(GetOffsetFromEntityGivenWorldCoords, veh, refX, refY, refZ)
    if oko and off and off.x then
        return off.x, off.y, off.z + lift
    end
    return nil
end

-- Which seat the ped occupies (-1 driver, 0 front passenger, 1.. rear). Used so a
-- seat change re-settles the locked label at the new seat instead of staying put.
local function GetPedVehicleSeat(veh, ped)
    local seats = GetVehicleModelNumberOfSeats(GetEntityModel(veh))
    if not seats or seats < 1 then seats = 8 end
    for seat = -1, seats - 2 do
        if GetPedInVehicleSeat(veh, seat) == ped then
            return seat
        end
    end
    return nil
end

local function GetOverheadLabelCoords(ped, serverId)
    local base = GetEntityCoords(ped)

    if IsPedDowned(ped, serverId) then
        if serverId then vehicleLabelOffsets[serverId] = nil end
        return vector3(base.x, base.y, base.z + GetCfg('DeadZOffset', 0.45))
    end

    -- Fully seated in a vehicle -> rigid, cached, car-locked anchor.
    local seatedVeh = nil
    local oks, sv = pcall(GetVehiclePedIsIn, ped, false)
    if oks and sv and sv ~= 0 then seatedVeh = sv end

    if seatedVeh and serverId then
        local now = GetGameTimer()
        local seat = GetPedVehicleSeat(seatedVeh, ped)
        local cache = vehicleLabelOffsets[serverId]
        -- Re-settle when the vehicle OR the seat changes, so switching seats moves
        -- the label to the new seat instead of staying locked to the old one.
        if not cache or cache.veh ~= seatedVeh or cache.seat ~= seat then
            cache = { veh = seatedVeh, seat = seat, since = now, locked = false }
            vehicleLabelOffsets[serverId] = cache
        end

        -- Settle window: track the head briefly so it lands cleanly after the
        -- get-in / seat-shuffle animation, THEN lock the offset for good so it
        -- stops moving relative to the car while driving.
        if not cache.locked then
            local ox, oy, oz = ComputeVehicleLocalOffset(ped, seatedVeh, base)
            if ox then cache.ox, cache.oy, cache.oz = ox, oy, oz end
            if now - cache.since > (tonumber(GetCfg('VehicleLabelLockDelay', 700)) or 700) then
                cache.locked = true
            end
        end

        if cache.ox then
            local world = GetOffsetFromEntityInWorldCoords(seatedVeh, cache.ox, cache.oy, cache.oz)
            if world and world.x then
                return world
            end
        end
    end

    -- Entering (F) or attached (trunk), not yet seated: live head-follow so it
    -- slides in smoothly. It locks via the cache once fully seated (above).
    local veh = seatedVeh or GetLabelVehicleForPed(ped)
    if veh then
        local ox, oy, oz = ComputeVehicleLocalOffset(ped, veh, base)
        if ox then
            local world = GetOffsetFromEntityInWorldCoords(veh, ox, oy, oz)
            if world and world.x then
                return world
            end
        end
        return vector3(base.x, base.y, base.z + 1.2)
    end

    -- On foot: clear any stale cache, then use entity origin + stable offset
    -- (avoids head-bone idle animation jitter).
    if serverId then vehicleLabelOffsets[serverId] = nil end
    return vector3(base.x, base.y, base.z + GetCfg('OverheadZOffset', 1.06))
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

local function IsAdminNoclipHidden(serverId)
    serverId = tonumber(serverId)
    if not serverId or serverId <= 0 then return false end
    local state = Player(serverId).state
    return state and state.cm_admin_noclip == true
end

local function IsLocalAdminNoclip()
    return LocalPlayer and LocalPlayer.state and LocalPlayer.state.cm_admin_noclip == true
end

local function GetTargetFromPed(ped)
    if not IsPedValidLabelTarget(ped) then return nil end

    local playerIndex = NetworkGetPlayerIndexFromPed(ped)
    if playerIndex == -1 or playerIndex == PlayerId() then return nil end

    local serverId = GetPlayerServerId(playerIndex)
    if not serverId or serverId <= 0 or IsAdminNoclipHidden(serverId) then return nil end

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
    -- This scoring is only for the G prompt. Labels use a separate path and
    -- still show for dead players and players inside vehicles.
    if not IsPedValidPlayerTarget(ped) then return nil end

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

local function IsTargetInteractable(target, maxDistance)
    if not target or not target.ped then return false end
    if not IsPedValidPlayerTarget(target.ped) then return false end
    local localCoords = GetEntityCoords(PlayerPedId())
    local targetCoords = GetEntityCoords(target.ped)
    if #(localCoords - targetCoords) > (tonumber(maxDistance) or GetCfg('LookDistance', 4.5)) then return false end
    target.coords = targetCoords
    return true
end

local function FindLookTarget()
    local maxDistance = GetCfg('LookDistance', GetCfg('Distance', 4.5))

    local rayTarget = RaycastCamera(maxDistance)
    if IsTargetInteractable(rayTarget, maxDistance) then
        return rayTarget
    end

    local bestTarget = GetBestLookAtPlayer(maxDistance)
    if IsTargetInteractable(bestTarget, maxDistance) then
        return bestTarget
    end

    return nil
end

-- ---------------------------------------------------------------------------
-- Slow scan: keep a short list of players inside label/look range.
-- The per-frame loop only ever touches this list.
-- ---------------------------------------------------------------------------
local function RefreshNearbyPlayers()
    local list = {}

    -- Admin noclip is invisible and should have a clean screen: no overhead
    -- labels and no G-menu targets while flying.
    if IsLocalAdminNoclip() then
        nearbyPlayers = list
        return
    end

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
                    if sid and sid > 0 and not IsAdminNoclipHidden(sid) then
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
    if IsLocalAdminNoclip() then
        return labels, nil
    end

    local useNativeLabels = GetCfg('UseNativeOverheadLabels', true) == true
    local localPed = PlayerPedId()
    local distanceLimit = GetCfg('OverheadDistance', 18.0)
    local targetServerId = (not menuOpen and currentTarget) and currentTarget.serverId or nil
    local gPrompt = nil

    for _, entry in ipairs(nearbyPlayers) do
        local ped = entry.ped
        if IsPedValidLabelTarget(ped) then
            local coords = GetEntityCoords(ped)
            local dist = #(GetEntityCoords(localPed) - coords)
            local isDeadPed = IsPedDowned(ped, entry.serverId)
            local isTarget = (entry.serverId == targetServerId)

            if (labelsEnabled and dist <= distanceLimit and HasClearView(localPed, ped)) or isTarget then
                if not useNativeLabels then
                    local nameLine, idLine, isAdmin, statusLine, familySymbol, familyColour = GetIdentityLabel(entry.serverId, isTarget, ped, isTarget)
                    if nameLine and idLine then
                        local labelCoords = GetOverheadLabelCoords(ped, entry.serverId)
                        local onScreen, sx, sy = World3dToScreen2d(labelCoords.x, labelCoords.y, labelCoords.z)
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
                                status = statusLine or nil,
                                familySymbol = familySymbol or nil,
                                familyColor = familyColour and ('rgb(%d,%d,%d)'):format(familyColour.r, familyColour.g, familyColour.b) or nil,
                                t = isTarget or nil,
                                admin = isAdmin or nil
                            }
                        end
                    end
                end

                if isTarget and IsTargetInteractable(currentTarget, GetCfg('LookDistance', GetCfg('Distance', 4.5))) then
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


local function DrawNativeTextLine(text, y, scale, r, g, b, a, font, outline)
    SetTextFont(font or 0)
    SetTextProportional(1)
    SetTextScale(0.0, scale)
    SetTextCentre(true)
    SetTextColour(r, g, b, a)
    if outline then
        SetTextOutline()
    end
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(tostring(text or ''))
    EndTextCommandDisplayText(0.0, y)
end

local function DrawNativeHeadLabel(x, y, z, nameLine, idLine, scale, isAdmin, isTarget, statusLine, familySymbol, familyColour)
    SetDrawOrigin(x, y, z, 0)

    local font = tonumber(GetCfg('OverheadFont', 0)) or 0
    local outline = GetCfg('OverheadTextOutline', true) ~= false
    local gap = scale * (tonumber(GetCfg('OverheadLineGap', 0.075)) or 0.075)
    local row = 0

    if statusLine then
        local red = GetCfg('DownedLabelColour', { r = 235, g = 45, b = 45, a = 250 })
        DrawNativeTextLine(statusLine, row * gap, scale * 0.92, red.r or 235, red.g or 45, red.b or 45, red.a or 250, font, outline)
        row = row + 1
    end

    -- The family-wide symbol sits directly above the normal player name.
    if familySymbol and (not isAdmin or GetCfg('ShowFamilySymbolInAdminMode', false) == true) then
        local c = familyColour or { r = 0, g = 240, b = 255, a = 245 }
        local entry = FAMILY_SYMBOLS[familySymbol] or FAMILY_SYMBOLS.shield
        local factor = math.max(0.58, scale / (tonumber(GetCfg('OverheadScale', 0.32)) or 0.32))
        local width = (tonumber(GetCfg('FamilySymbolWidth', 0.016)) or 0.016) * factor
        local height = (tonumber(GetCfg('FamilySymbolHeight', 0.028)) or 0.028) * factor
        local y = row * gap

        if familySymbolTextureReady[familySymbol] == true then
            DrawSprite(FAMILY_SYMBOL_TXD, entry.texture, 0.0, y, width, height, 0.0,
                c.r or 0, c.g or 240, c.b or 255, c.a or 245)
        else
            DrawNativeTextLine(entry.glyph, y, scale * 1.02,
                c.r or 0, c.g or 240, c.b or 255, c.a or 245, font, outline)
        end
        row = row + 1.15
    end

    local nameY, idY = row * gap, (row + 1) * gap
    if isAdmin then
        DrawNativeTextLine(nameLine, nameY, scale, 255, 35, 35, 245, font, outline)
        DrawNativeTextLine(idLine, idY, scale * 0.84, 255, 35, 35, 235, font, outline)
    else
        DrawNativeTextLine(nameLine, nameY, scale, 245, 252, 255, 245, font, outline)
        if isTarget then
            local accent = GetCfg('AccentColour', { r = 0, g = 230, b = 255, a = 255 })
            DrawNativeTextLine(idLine, idY, scale * 0.84, accent.r or 0, accent.g or 230, accent.b or 255, 235, font, outline)
        else
            DrawNativeTextLine(idLine, idY, scale * 0.84, 245, 252, 255, 235, font, outline)
        end
    end

    ClearDrawOrigin()
end

local function DrawNativeOverheadLabels()
    if labelsEnabled ~= true or GetCfg('UseNativeOverheadLabels', true) ~= true then return end
    if IsLocalAdminNoclip() then return end

    local localPed = PlayerPedId()
    local localCoords = GetEntityCoords(localPed)
    local distanceLimit = GetCfg('OverheadDistance', 18.0)
    local targetServerId = (not menuOpen and currentTarget) and currentTarget.serverId or nil
    local baseScale = tonumber(GetCfg('OverheadScale', 0.32)) or 0.32

    for _, entry in ipairs(nearbyPlayers) do
        local ped = entry.ped
        if IsPedValidLabelTarget(ped) then
            local coords = GetEntityCoords(ped)
            local dist = #(localCoords - coords)
            local isTarget = (entry.serverId == targetServerId)

            if (dist <= distanceLimit and HasClearView(localPed, ped)) or isTarget then
                local targetable = isTarget and IsTargetInteractable(currentTarget, GetCfg('LookDistance', GetCfg('Distance', 4.5))) == true
                local nameLine, idLine, isAdmin, statusLine, familySymbol, familyColour = GetIdentityLabel(entry.serverId, targetable, ped, targetable)
                if nameLine and idLine then
                    local scaleFactor = 1.15 - (dist * 0.026)
                    if scaleFactor < 0.58 then scaleFactor = 0.58 end
                    if scaleFactor > 1.10 then scaleFactor = 1.10 end

                    local labelCoords = GetOverheadLabelCoords(ped, entry.serverId)
                    DrawNativeHeadLabel(labelCoords.x, labelCoords.y, labelCoords.z, nameLine, idLine, baseScale * scaleFactor, isAdmin == true, targetable, statusLine, familySymbol, familyColour)
                end
            end
        end
    end
end

-- The G prompt lives on its own NUI channel ('gprompt'), completely separate
-- from the overhead 'labels' channel. This is deliberate: with native overhead
-- labels on, the render loop clears the NUI 'labels' channel every frame, which
-- previously wiped the G prompt one frame after each push and made it blink.
-- Its own channel + change-detection keeps it perfectly steady.
local gWasVisible = false
local lastGX, lastGY = -1.0, -1.0

local function PushGPrompt(gPrompt)
    if gPrompt and type(gPrompt.x) == 'number' then
        local moved = (math.abs(gPrompt.x - lastGX) > 0.0008) or (math.abs(gPrompt.y - lastGY) > 0.0008)
        if not gWasVisible or moved then
            SendNUIMessage({ action = 'gprompt', g = gPrompt })
            lastGX, lastGY = gPrompt.x, gPrompt.y
            gWasVisible = true
        end
    elseif gWasVisible then
        SendNUIMessage({ action = 'gprompt', g = false })
        gWasVisible = false
        lastGX, lastGY = -1.0, -1.0
    end
end

local function HideGPrompt()
    PushGPrompt(nil)
end

-- ---------------------------------------------------------------------------
-- Interaction arbiter (single-prompt coordination with the vehicle menu).
--
-- The player menu (this resource) and the vehicle menu (a separate resource)
-- each own their own logic, but publish their current target's distance to the
-- shared local statebag so only ONE G shows at a time. This keeps clean resource
-- boundaries -- no merging, no cross-resource edits -- while avoiding double G.
--
-- Vehicle resource must cooperate with the mirror of this (see the snippet in
-- docs/INTERACTION_ARBITER.md): publish LocalPlayer.state.cmVehicleInteractDist
-- and suppress its own prompt when the player wins.
-- ---------------------------------------------------------------------------
local lastPublishedInteractDist = false

local function PublishPlayerInteractDist(dist)
    local value = (type(dist) == 'number') and dist or false
    if value ~= lastPublishedInteractDist then
        lastPublishedInteractDist = value
        LocalPlayer.state:set('cmPlayerInteractDist', value, false)
    end
end

-- Returns true when the vehicle menu should own the prompt this frame, so this
-- resource hides its G and refuses to open. Only consulted when we actually have
-- a player target.
local function VehicleInteractionWins(myDist)
    if GetCfg('InteractionArbiter', true) == false then return false end

    local vDist = LocalPlayer.state.cmVehicleInteractDist
    if type(vDist) ~= 'number' then return false end -- vehicle has no target -> player is free

    local mode = tostring(GetCfg('InteractionPriority', 'closest'))
    if mode == 'player' then return false end -- player always wins when it has a target
    if mode == 'vehicle' then return true end -- vehicle always wins when it has a target

    -- 'closest': nearer target wins; near-ties fall to the player.
    if type(myDist) ~= 'number' then return true end
    local tie = tonumber(GetCfg('InteractionArbiterTie', 0.1)) or 0.1
    return vDist < (myDist - tie)
end

-- Exposed so a separate interaction resource (e.g. the vehicle menu) can mirror
-- these EXACT arbiter settings at runtime instead of hardcoding them, keeping a
-- single source of truth here in cm-playerdata's config.
exports('GetInteractionArbiter', function()
    return {
        enabled = GetCfg('InteractionArbiter', true) ~= false,
        priority = tostring(GetCfg('InteractionPriority', 'closest')),
        tie = tonumber(GetCfg('InteractionArbiterTie', 0.1)) or 0.1
    }
end)

local function PushLabels()
    local labels, gPrompt = BuildLabelPayload()

    -- Overhead labels channel (used only when native labels are OFF; under native
    -- mode this array is always empty and simply clears once).
    if #labels == 0 then
        if labelsWereVisible then
            SendNUIMessage({ action = 'labels', labels = {} })
            labelsWereVisible = false
        end
    else
        SendNUIMessage({ action = 'labels', labels = labels })
        labelsWereVisible = true
    end

    -- G prompt: in native mode the glyph is drawn per-frame on the body (steady,
    -- no camera-move lag), so the NUI G stays hidden. NUI label mode uses the channel.
    if GetCfg('UseNativeOverheadLabels', true) == true then
        PushGPrompt(nil)
    else
        PushGPrompt(gPrompt)
    end
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

-- Native per-frame G glyph, anchored to the target's body. Drawn every frame via
-- SetDrawOrigin so it is locked to the player and only moves when the PLAYER
-- moves — it never lags or wobbles when the viewer moves the camera (which is
-- what the throttled NUI prompt used to do).
local function DrawNativeGPrompt(target)
    if not target or not target.ped or not IsPedValidPlayerTarget(target.ped) then return end

    local base = GetEntityCoords(target.ped)
    local z = base.z + (tonumber(GetCfg('PromptZOffset', 0.12)) or 0.12)
    local accent = GetCfg('AccentColour', { r = 0, g = 230, b = 255, a = 255 })
    local scale = tonumber(GetCfg('PromptNativeScale', 0.44)) or 0.44
    local font = tonumber(GetCfg('OverheadFont', 0)) or 0

    SetDrawOrigin(base.x, base.y, z, 0)
    SetTextFont(font)
    SetTextProportional(1)
    SetTextScale(0.0, scale)
    SetTextCentre(true)
    SetTextColour(accent.r or 0, accent.g or 230, accent.b or 255, accent.a or 255)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName('G')
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

-- ---------------------------------------------------------------------------
-- Extensible G-menu registry
-- ---------------------------------------------------------------------------
local function NormalizeMenuId(value)
    if value == nil then return nil end
    local id = tostring(value):lower():gsub('%s+', '_')
    id = id:gsub('[^%w_:%.-]', '')
    if id == '' then return nil end
    return id
end

local function SafeString(value, fallback)
    if value == nil or value == '' then return fallback end
    return tostring(value)
end

local function SortOptions(options)
    table.sort(options, function(a, b)
        local ao = tonumber(a.order) or 100
        local bo = tonumber(b.order) or 100
        if ao == bo then
            return (tonumber(a._seq) or 0) < (tonumber(b._seq) or 0)
        end
        return ao < bo
    end)
    return options
end

local function RegisterInteractionPage(page)
    if type(page) ~= 'table' then return false, 'invalid_page' end
    local id = NormalizeMenuId(page.id or page.page or page.name)
    if not id then return false, 'invalid_id' end

    extensionPages[id] = {
        id = id,
        label = SafeString(page.label or page.title, id),
        icon = SafeString(page.icon, 'dot'),
        order = tonumber(page.order) or 50,
        emptyLabel = SafeString(page.emptyLabel, 'No actions available'),
        showWhenEmpty = page.showWhenEmpty == true
    }
    extensionOptions[id] = extensionOptions[id] or {}
    return true
end

local function NormalizeInteractionOption(pageId, option)
    if type(option) ~= 'table' then return nil, 'invalid_option' end
    local id = NormalizeMenuId(option.id or option.action or option.event)
    if not id then return nil, 'invalid_option_id' end

    extensionSequence = extensionSequence + 1
    return {
        id = id,
        label = SafeString(option.label or option.title, id),
        icon = SafeString(option.icon, 'dot'),
        type = SafeString(option.type, 'extension'),
        action = SafeString(option.action or id, id),
        event = option.event and tostring(option.event) or nil,
        payload = type(option.payload) == 'table' and option.payload or nil,
        page = pageId,
        order = tonumber(option.order) or 100,
        close = option.close ~= false,
        allowDeadTarget = option.allowDeadTarget == true,
        deadOnly = option.deadOnly == true,
        _seq = extensionSequence
    }
end

local function RegisterInteractionOption(pageId, option)
    local pid = NormalizeMenuId(pageId or (type(option) == 'table' and option.page))
    if not pid then return false, 'invalid_page_id' end
    if not extensionPages[pid] then
        RegisterInteractionPage({ id = pid, label = pid, icon = 'dot', order = 80 })
    end

    local normalized, err = NormalizeInteractionOption(pid, option)
    if not normalized then return false, err end
    extensionOptions[pid] = extensionOptions[pid] or {}
    extensionOptions[pid][normalized.id] = normalized
    return true
end

local function UnregisterInteractionOption(pageId, optionId)
    local pid = NormalizeMenuId(pageId)
    local oid = NormalizeMenuId(optionId)
    if not pid or not oid or not extensionOptions[pid] then return false end
    extensionOptions[pid][oid] = nil
    return true
end

local function ClearInteractionOptions(pageId)
    local pid = NormalizeMenuId(pageId)
    if not pid then return false end
    extensionOptions[pid] = {}
    return true
end

local function RegisterInteractionMenu(menu)
    if type(menu) ~= 'table' then return false, 'invalid_menu' end

    if type(menu.pages) == 'table' then
        for _, page in ipairs(menu.pages) do
            RegisterInteractionPage(page)
        end
    end

    if type(menu.options) == 'table' then
        for _, option in ipairs(menu.options) do
            RegisterInteractionOption(option.page, option)
        end
    end

    return true
end

local function RegisterConfiguredExtensionPages()
    local pages = GetCfg('ExtensionPages', {})
    if type(pages) ~= 'table' then return end
    for id, page in pairs(pages) do
        if type(page) == 'table' then
            page.id = page.id or id
            RegisterInteractionPage(page)
        end
    end
end

local function IsExtensionOptionVisible(option, targetDead)
    if not option then return false end
    if targetDead then
        return option.allowDeadTarget == true or option.deadOnly == true
    end
    if option.deadOnly == true then return false end
    return true
end

local function CountVisibleExtensionOptions(pageId, targetDead)
    local count = 0
    local options = extensionOptions[pageId] or {}
    for _, option in pairs(options) do
        if IsExtensionOptionVisible(option, targetDead) then
            count = count + 1
        end
    end
    return count
end

local function AppendExtensionPageEntries(options, targetDead)
    local showEmpty = GetCfg('ShowEmptyExtensionPages', false) == true
    local entries = {}

    for id, page in pairs(extensionPages) do
        local count = CountVisibleExtensionOptions(id, targetDead)
        if count > 0 or showEmpty or page.showWhenEmpty == true then
            entries[#entries + 1] = {
                id = 'ext_page_' .. id,
                label = page.label,
                icon = page.icon,
                type = 'page',
                page = 'ext:' .. id,
                order = tonumber(page.order) or 50,
                _seq = tonumber(page.order) or 50
            }
        end
    end

    SortOptions(entries)
    for _, entry in ipairs(entries) do
        options[#options + 1] = entry
    end
end

exports('RegisterInteractionPage', RegisterInteractionPage)
exports('RegisterInteractionOption', RegisterInteractionOption)
exports('RegisterInteractionMenu', RegisterInteractionMenu)
exports('UnregisterInteractionOption', UnregisterInteractionOption)
exports('ClearInteractionOptions', ClearInteractionOptions)

RegisterNetEvent('cm-playerdata:client:registerInteractionPage', function(page)
    RegisterInteractionPage(page)
end)

RegisterNetEvent('cm-playerdata:client:registerInteractionOption', function(pageId, option)
    RegisterInteractionOption(pageId, option)
end)

RegisterNetEvent('cm-playerdata:client:registerInteractionMenu', function(menu)
    RegisterInteractionMenu(menu)
end)

RegisterNetEvent('cm-playerdata:client:clearInteractionOptions', function(pageId)
    ClearInteractionOptions(pageId)
end)

RegisterConfiguredExtensionPages()
TriggerEvent('cm-playerdata:client:interactionRegistryReady')

-- ---------------------------------------------------------------------------
-- Hex menu (NUI). No NUI focus: number keys 1-9 select, RMB = back, ESC/G = close.
-- ---------------------------------------------------------------------------
local function BuildPage(page)
    page = page or 'main'
    local showWIP = GetCfg('ShowWIPActions', false) == true
    local targetDead = menuTarget and menuTarget.ped and IsPedDowned(menuTarget.ped, menuTarget.serverId) or false

    if page == 'main' then
        local options = {
            { id = 'basic', label = 'Basic Actions', icon = 'people', type = 'page', page = 'basic', order = 10 },
            { id = 'documents', label = 'Documents', icon = 'documents', type = 'page', page = 'documents', order = 20 }
        }

        AppendExtensionPageEntries(options, targetDead)

        options[#options + 1] = { id = 'status', label = 'Check Status', icon = 'status', type = 'client', action = 'check_status', order = 800 }
        options[#options + 1] = { id = 'close', label = 'Close', icon = 'close', type = 'close', order = 900 }
        return SortOptions(options)
    elseif page == 'basic' then
        local options = {
            { id = 'handshake', label = 'Handshake', icon = 'handshake', type = 'server', action = 'handshake', order = 10 },
            { id = 'show_id', label = 'Share ID', icon = 'id', type = 'server', action = 'share_id', order = 20 },
            { id = 'greet', label = 'Say Hello', icon = 'hello', type = 'server', action = 'greet', order = 30 },
            { id = 'give_cash', label = 'Give Cash', icon = 'cash', type = 'cash', order = 40 }
        }
        if showWIP then
            options[#options + 1] = { id = 'search_player', label = 'Search Player', icon = 'search', type = 'server', action = 'search_player', order = 50 }
            options[#options + 1] = { id = 'escort_player', label = 'Escort / Carry', icon = 'escort', type = 'server', action = 'escort_player', order = 60 }
        end
        options[#options + 1] = { id = 'back', label = 'Back', icon = 'back', type = 'back', order = 900 }
        return SortOptions(options)
    elseif page == 'documents' then
        return SortOptions({
            { id = 'show_id', label = 'Show ID Card', icon = 'id', type = 'server', action = 'share_id', order = 10 },
            { id = 'show_license', label = 'Show License', icon = 'license', type = 'server', action = 'show_license', order = 20 },
            { id = 'show_documents', label = 'Show Documents', icon = 'documents', type = 'server', action = 'show_documents', order = 30 },
            { id = 'back', label = 'Back', icon = 'back', type = 'back', order = 900 }
        })
    elseif page == 'dead' then
        local options = {
            { id = 'check_pulse', label = 'Check Pulse', icon = 'status', type = 'client', action = 'check_status', order = 10 },
            { id = 'treat_player', label = 'Patch / Treat', icon = 'people', type = 'server', action = 'treat_player', order = 20 }
        }
        AppendExtensionPageEntries(options, true)
        options[#options + 1] = { id = 'close', label = 'Close', icon = 'close', type = 'close', order = 900 }
        return SortOptions(options)
    elseif page:sub(1, 4) == 'ext:' then
        local pageId = NormalizeMenuId(page:sub(5))
        local options = {}
        if pageId then
            for _, option in pairs(extensionOptions[pageId] or {}) do
                if IsExtensionOptionVisible(option, targetDead) then
                    options[#options + 1] = option
                end
            end
        end

        if #options == 0 then
            local pageMeta = pageId and extensionPages[pageId] or nil
            options[#options + 1] = {
                id = 'ext_empty',
                label = pageMeta and pageMeta.emptyLabel or 'No actions available',
                icon = 'dot',
                type = 'noop',
                order = 1
            }
        end

        options[#options + 1] = { id = 'back', label = 'Back', icon = 'back', type = 'back', order = 900 }
        return SortOptions(options)
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
    TriggerEvent('cm-playerdata:client:interactionTargetChanged', nil)
    currentPage = 'main'
    currentOptions = {}
    pageStack = {}
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeRadial' })
end

local function OpenMenu(target)
    if not target or not target.serverId then return end
    if not IsPedValidPlayerTarget(target.ped) then
        if target.ped and DoesEntityExist(target.ped) and IsTargetInVehicle(target.ped) then
            Notify('Use the vehicle interaction menu for players inside vehicles.', 'error')
        end
        return
    end
    menuOpen = true
    menuTarget = target
    -- Let extension resources synchronously rebuild target-specific pages before
    -- BuildPage reads the registry. No client-provided permission is trusted;
    -- cm-playerdata and the extension resource validate again on the server.
    TriggerEvent('cm-playerdata:client:interactionTargetChanged', target.serverId)
    -- Unconscious body: only treatment actions make sense.
    currentPage = IsPedDowned(target.ped, target.serverId) and 'dead' or 'main'
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
    elseif option.type == 'noop' then
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

    if option.type == 'clientEvent' and option.event then
        TriggerEvent(tostring(option.event), targetServerId, option.id, option.payload or {})
        if option.close ~= false then CloseMenu() else SendMenuPage() end
        return
    elseif option.type == 'extension' or option.type == 'external' then
        local action = tostring(option.action or option.id or 'unknown')
        TriggerServerEvent('cm-playerdata:server:extensionInteraction', targetServerId, action, option.payload or {})
        TriggerEvent('cm-playerdata:client:extensionInteractionSelected', action, targetServerId, option)
        if option.close ~= false then CloseMenu() else SendMenuPage() end
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

        if GetCfg('BlockInteractionWhenTargetInVehicle', true) ~= false and IsTargetInVehicle(menuTarget.ped) then
            Notify('Use the vehicle interaction menu for players inside vehicles.', 'error')
            CloseMenu()
            return
        end

        -- Target died while the menu was open: switch to the treatment page.
        if IsPedDowned(menuTarget.ped, menuTarget.serverId) and currentPage ~= 'dead' then
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
            HideGPrompt()
        elseif #nearbyPlayers > 0 or menuOpen then
            sleep = tonumber(GetCfg('LabelUpdateInterval', 50)) or 50
            if sleep < 16 then sleep = 16 end

            local viewerCanInteract = CanInteract()
            if menuOpen and not viewerCanInteract then
                CloseMenu()
            end

            local now = GetGameTimer()
            if not menuOpen and viewerCanInteract and now - lastTargetScan >= GetCfg('TargetScanInterval', 70) then
                lastTargetScan = now
                local foundTarget = FindLookTarget()
                if foundTarget then
                    currentTarget = foundTarget
                    currentTargetLastSeen = now
                elseif currentTarget and IsTargetInteractable(currentTarget, GetCfg('LookDistance', GetCfg('Distance', 4.5))) then
                    -- Prevent G prompt flicker from one missed raycast/frame while still
                    -- looking at the same player. It will disappear quickly after look-away.
                    local holdMs = tonumber(GetCfg('TargetHoldMs', 420)) or 420
                    if now - currentTargetLastSeen > holdMs then
                        currentTarget = nil
                    end
                else
                    currentTarget = nil
                end
            elseif not viewerCanInteract then
                currentTarget = nil
            end

            if labelsEnabled == true and GetCfg('UseNativeOverheadLabels', true) == true then
                DrawNativeOverheadLabels()
                if labelsWereVisible then
                    SendNUIMessage({ action = 'labels', labels = {} })
                    labelsWereVisible = false
                end
                -- Keep this loop render-frame smooth only while nearby labels/targets exist.
                sleep = 0
            end

            local labelInterval = tonumber(GetCfg('LabelUpdateInterval', 50)) or 50
            if labelInterval < 16 then labelInterval = 16 end
            if now - lastLabelPush >= labelInterval then
                lastLabelPush = now
                PushLabels()
            end

            if menuOpen then
                sleep = 0
                HandleMenuControls()
            elseif currentTarget then
                sleep = 0
                -- Distance to the player target, shared for single-prompt arbitration.
                local tp = currentTarget.ped
                local myDist = nil
                if tp and DoesEntityExist(tp) then
                    myDist = #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(tp))
                end
                PublishPlayerInteractDist(myDist)

                -- Only show the player G if the vehicle menu isn't the closer/priority
                -- target this frame, so at most one G is ever on screen.
                if not VehicleInteractionWins(myDist) then
                    DrawTargetMarker(currentTarget)
                    if GetCfg('UseNativeOverheadLabels', true) == true then
                        DrawNativeGPrompt(currentTarget)
                    end
                else
                    HideGPrompt()
                end
            else
                PublishPlayerInteractDist(nil)
            end
        else
            currentTarget = nil
            PublishPlayerInteractDist(nil)
            if labelsWereVisible then
                SendNUIMessage({ action = 'labels', labels = {} })
                labelsWereVisible = false
            end
            HideGPrompt()
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
    if IsPedDowned(ped) then return end

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
        -- If the vehicle menu owns the prompt this frame, let it handle G instead.
        local tp = currentTarget.ped
        local myDist = (tp and DoesEntityExist(tp)) and #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(tp)) or nil
        if VehicleInteractionWins(myDist) then return end

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


RegisterNetEvent('cm-playerdata:client:familyIdentityChanged', function()
    RequestNearbyIdentities(true)
end)
