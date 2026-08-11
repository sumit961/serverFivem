-- cm-ems/client/patch.lua
-- Direct player-to-player "patch up": look at a player up close, press X.
-- A downed target is healed immediately by the server. A conscious target
-- instead gets a Y/N offer on their own screen (see the prompt below) --
-- the accept/decline UX mirrors cm-family's invite prompt (cl_invites.lua)
-- for a consistent feel across the framework.

local patchKey = tostring((Config.Patch or {}).key or 'X')
local maxDistance = tonumber((Config.Patch or {}).maxDistance) or 3.0

local function notify(message, kind)
    if lib and lib.notify then lib.notify({ title = 'EMS Patch', description = message, type = kind or 'inform' }) end
end

-- ---------------------------------------------------------------------------
-- Initiating side: on-duty EMS with ems.treat_player, looking at a player.
-- ---------------------------------------------------------------------------

local currentTargetServerId = nil
local promptShown = false
local promptText

local function myPatchEligible()
    local mine = LocalPlayer.state.cmEms
    if not mine or mine == false then return false end
    if mine.onDuty ~= true then return false end
    local permissions = mine.permissions or {}
    return mine.isLeader == true or permissions['ems.treat_player'] == true
end

-- Rough "who am I looking at" without a full raycast: nearest player within
-- range that the camera is roughly pointed at. Deliberately only runs while
-- the local player is eligible to patch (on-duty + permission), so this
-- doesn't add a background scan for the vast majority of players.
local function cameraForward()
    local rot = GetGameplayCamRot(2)
    local z = math.rad(rot.z)
    local x = math.rad(rot.x)
    local num = math.abs(math.cos(x))
    return vector3(-math.sin(z) * num, math.cos(z) * num, math.sin(x))
end

local function findPatchTarget()
    local myPed = PlayerPedId()
    local myCoords = GetEntityCoords(myPed)
    local camCoords = GetGameplayCamCoord()
    local forward = cameraForward()
    local myId = PlayerId()
    local best, bestDot = nil, 0.55 -- roughly a 56 degree half-cone

    for _, playerIndex in ipairs(GetActivePlayers()) do
        if playerIndex ~= myId then
            local targetPed = GetPlayerPed(playerIndex)
            if targetPed ~= 0 and DoesEntityExist(targetPed) then
                local targetCoords = GetEntityCoords(targetPed)
                if #(myCoords - targetCoords) <= maxDistance then
                    local dir = targetCoords - camCoords
                    local len = #dir
                    if len > 0.01 then
                        dir = dir / len
                        local dot = dir.x * forward.x + dir.y * forward.y + dir.z * forward.z
                        if dot > bestDot then
                            bestDot = dot
                            best = GetPlayerServerId(playerIndex)
                        end
                    end
                end
            end
        end
    end
    return best
end

RegisterCommand('cm_ems_patch', function()
    if not myPatchEligible() or not currentTargetServerId then return end
    TriggerServerEvent('cm-ems:server:requestPatch', currentTargetServerId)
end, false)
RegisterKeyMapping('cm_ems_patch', 'EMS: Patch up player', 'keyboard', patchKey)

RegisterNetEvent('cm-ems:client:beginSafeTreatment', function(targetSrc)
    notify('Safe treatment area confirmed. Starting field treatment.', 'success')
    TriggerServerEvent('cm-ems:server:requestPatch', tonumber(targetSrc))
end)

CreateThread(function()
    while true do
        local sleep = 1000
        if myPatchEligible() and LocalPlayer.state.isDead ~= true then
            sleep = 200
            currentTargetServerId = findPatchTarget()
            if currentTargetServerId then
                local treatment = Player(currentTargetServerId).state.cmEmsTreatment
                local nextPrompt = type(treatment) == 'table' and treatment.active == true
                    and ('Being treated by %s'):format(tostring(treatment.medicName or 'EMS'))
                    or ('[%s] Patch Up'):format(patchKey)
                if not promptShown or promptText ~= nextPrompt then
                    if promptShown then lib.hideTextUI() end
                    lib.showTextUI(nextPrompt)
                    promptShown = true
                    promptText = nextPrompt
                end
            elseif promptShown then
                lib.hideTextUI()
                promptShown = false
                promptText = nil
            end
        else
            currentTargetServerId = nil
            if promptShown then
                lib.hideTextUI()
                promptShown = false
                promptText = nil
            end
        end
        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if promptShown then lib.hideTextUI() end
end)

-- ---------------------------------------------------------------------------
-- Receiving side: a conscious player was offered treatment, Y accepts / N
-- declines. Pattern matches cm-family/client/cl_invites.lua exactly.
-- ---------------------------------------------------------------------------

local activeOffer
local respondingOffer

local function drawText(text, x, y, scale, r, g, b, a, centre)
    SetTextFont(4)
    SetTextScale(scale, scale)
    SetTextColour(r, g, b, a)
    SetTextCentre(centre == true)
    SetTextOutline()
    SetTextDropShadow()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

local function respond(accept)
    local offer = activeOffer
    if not offer or respondingOffer then return end
    respondingOffer = offer
    activeOffer = nil
    TriggerServerEvent('cm-ems:server:patchOfferResponse', accept == true)
end

RegisterNetEvent('cm-ems:client:patchOffer', function(timeoutMs, medicName)
    if activeOffer then return end
    activeOffer = {
        expiresGameTimer = GetGameTimer() + (tonumber(timeoutMs) or 15000),
        medicName = tostring(medicName or 'An EMS medic'),
    }
    respondingOffer = nil
end)

-- Key mapping plus native-control polling: the mapping respects custom
-- binds, native polling guarantees the displayed default Y/N works even if
-- another resource intercepts the mapped command first.
RegisterCommand('+cm_ems_patch_accept', function() respond(true) end, false)
RegisterCommand('-cm_ems_patch_accept', function() end, false)
RegisterCommand('+cm_ems_patch_decline', function() respond(false) end, false)
RegisterCommand('-cm_ems_patch_decline', function() end, false)
RegisterKeyMapping('+cm_ems_patch_accept', 'Accept EMS treatment offer', 'keyboard', 'Y')
RegisterKeyMapping('+cm_ems_patch_decline', 'Decline EMS treatment offer', 'keyboard', 'N')

-- Console/command fallbacks, useful if a player has previously rebound Y/N.
RegisterCommand('emspatchaccept', function() respond(true) end, false)
RegisterCommand('emspatchdecline', function() respond(false) end, false)

CreateThread(function()
    while true do
        local offer = activeOffer
        if not offer then
            Wait(400)
        else
            Wait(0)
            offer = activeOffer
            if offer then
                if GetGameTimer() >= offer.expiresGameTimer then
                    activeOffer = nil
                else
                    DisableControlAction(0, 246, true) -- Y / team chat
                    DisableControlAction(0, 249, true) -- N / push-to-talk
                    DisableControlAction(2, 246, true)
                    DisableControlAction(2, 249, true)

                    local remaining = math.max(0, math.ceil((offer.expiresGameTimer - GetGameTimer()) / 1000))

                    DrawRect(0.5, 0.105, 0.50, 0.090, 5, 11, 17, 220)
                    DrawRect(0.5, 0.061, 0.50, 0.004, 0, 240, 255, 245)
                    drawText(('%s requests permission to treat you.'):format(offer.medicName), 0.5, 0.073, 0.37, 245, 250, 255, 255, true)
                    drawText(('Press ~y~Y~s~ to accept   •   Press ~r~N~s~ to decline   (%ds)'):format(remaining),
                        0.5, 0.112, 0.31, 215, 226, 235, 255, true)

                    -- JustPressed instead of JustReleased: team-chat can consume Y
                    -- on release on some FiveM key configurations.
                    if IsDisabledControlJustPressed(0, 246) or IsDisabledControlJustPressed(2, 246) then
                        respond(true)
                    elseif IsDisabledControlJustPressed(0, 249) or IsDisabledControlJustPressed(2, 249) then
                        respond(false)
                    end
                end
            end
        end
    end
end)

-- Both players receive visible treatment feedback. The medic can move, but
-- the server cancels completion if either person leaves the allowed radius.
RegisterNetEvent('cm-ems:client:startPatchTreatment', function(duration, targetSrc, wasDead)
    duration = math.max(3000, tonumber(duration) or 8000)
    targetSrc = tonumber(targetSrc)
    if targetSrc then
        local playerIndex = GetPlayerFromServerId(targetSrc)
        if playerIndex ~= -1 then
            local targetPed = GetPlayerPed(playerIndex)
            if targetPed ~= 0 then
                TaskTurnPedToFaceEntity(PlayerPedId(), targetPed, 500)
                Wait(500)
            end
        end
    end
    local finished = false
    if lib and lib.progressCircle then
        finished = lib.progressCircle({
            duration = duration,
            label = wasDead == true and 'Reviving patient...' or 'Patching patient...',
            position = 'bottom',
            useWhileDead = false, canCancel = true,
            disable = { move = true, car = true, combat = true },
            anim = wasDead == true
                and { dict = 'mini@cpr@char_a@cpr_str', clip = 'cpr_pumpchest', flag = 1 }
                or { dict = 'amb@medic@standing@tendtodead@base', clip = 'base', flag = 1 },
        })
    else
        Wait(duration)
        finished = true
    end
    TriggerServerEvent('cm-ems:server:completePatchTreatment', finished == true)
end)

local patientTreatmentActive = false
RegisterNetEvent('cm-ems:client:cancelPatchTreatment', function()
    if lib and lib.cancelProgress then pcall(lib.cancelProgress) end
    ClearPedTasks(PlayerPedId())
end)

RegisterNetEvent('cm-ems:client:patchTreatmentStatus', function(status, duration, medicName, summary)
    status = tostring(status or '')
    if status == 'started' then
        patientTreatmentActive = true
        if lib and lib.notify then lib.notify({ title = 'EMS Treatment', description = ('%s is treating you. Stay near the medic.'):format(tostring(medicName or 'An EMS medic')), type = 'inform' }) end
        CreateThread(function()
            if lib and lib.progressBar then
                lib.progressBar({
                    duration = math.max(3000, tonumber(duration) or 8000),
                    label = ('Receiving treatment from %s...'):format(tostring(medicName or 'EMS')),
                    useWhileDead = true, canCancel = false,
                    disable = { move = true, car = true, combat = true },
                })
            else
                Wait(math.max(3000, tonumber(duration) or 8000))
            end
            patientTreatmentActive = false
        end)
    else
        if patientTreatmentActive and lib and lib.cancelProgress then pcall(lib.cancelProgress) end
        patientTreatmentActive = false
        if lib and lib.notify then
            lib.notify({
                title = 'EMS Treatment',
                description = tostring(summary or (status == 'completed' and 'Your treatment is complete.' or 'Treatment was cancelled.')),
                type = status == 'completed' and 'success' or 'error',
            })
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then activeOffer = nil end
end)
