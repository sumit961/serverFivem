-- cm-ems/server/patch.lua
-- Direct player-to-player "patch up": an on-duty EMS member with
-- ems.treat_player heals another player up close (X key, see client/patch.lua).
--
-- A downed target is healed immediately -- an unconscious player cannot
-- meaningfully consent, matching street-patch and the government doctor.
-- A conscious target instead gets a Y/N offer first, since force-healing
-- someone who's fine and didn't ask for it is unwanted.
--
-- Reuses (never duplicates):
--   cm-playerdata  IsDead / Heal -- the same export the government doctor
--                  uses (Heal already handles both "revive a downed player
--                  in place" and "top up a conscious player" correctly).

local PendingPatchOffers = {} -- [targetSrc] = { from = healerSrc, expires = ms }
local PendingPatchTreatments = {} -- [medicSrc] = treatment state
local PatchCooldowns = {} -- [src] = next allowed game timer

local function notify(src, message, kind)
    TriggerClientEvent('cm-playerdata:client:interactionNotify', tonumber(src), tostring(message), kind or 'inform')
end

local function patchMember(src)
    local characterId = cid(tonumber(src))
    local member = characterId and memberFor(characterId)
    if not member or dbBoolean(member.is_suspended) or not dbBoolean(member.on_duty) or not has(member, 'ems.treat_player') then
        return nil, characterId
    end
    return member, characterId
end

local function maxPatchDistance()
    return tonumber((Config.Patch or {}).maxDistance) or 3.0
end

local function cooldownRemaining(src)
    return math.max(0, (tonumber(PatchCooldowns[tonumber(src)]) or 0) - GetGameTimer())
end

local function applyPatchCooldown(medicSrc, targetSrc)
    local untilTimer = GetGameTimer() + math.max(0, math.floor(tonumber((Config.Patch or {}).cooldownMs) or 5000))
    PatchCooldowns[tonumber(medicSrc)] = untilTimer
    PatchCooldowns[tonumber(targetSrc)] = untilTimer
end

local function setTreatmentState(targetSrc, state)
    if not targetSrc or not GetPlayerName(targetSrc) then return end
    Player(targetSrc).state:set('cmEmsTreatment', state or false, true)
end

local function cancelTreatment(medicSrc, treatment, reason)
    local targetSrc = treatment and tonumber(treatment.target)
    PendingPatchTreatments[tonumber(medicSrc)] = nil
    setTreatmentState(targetSrc, false)
    applyPatchCooldown(medicSrc, targetSrc)
    if GetPlayerName(medicSrc) then
        TriggerClientEvent('cm-ems:client:cancelPatchTreatment', medicSrc)
        notify(medicSrc, reason or 'Treatment cancelled.', 'error')
    end
    if targetSrc and GetPlayerName(targetSrc) then
        TriggerClientEvent('cm-ems:client:patchTreatmentStatus', targetSrc, 'cancelled', 0, nil,
            reason or 'Treatment was cancelled.')
    end
end

-- Distance alone is not enough: two peds can be numerically close while in
-- different routing buckets (separate instances), which would let a patch
-- reach across instances that are supposed to be isolated from each other.
local function withinPatchRange(a, b)
    if GetPlayerRoutingBucket(a) ~= GetPlayerRoutingBucket(b) then return false end
    local pedA, pedB = GetPlayerPed(a), GetPlayerPed(b)
    if not pedA or pedA == 0 or not pedB or pedB == 0 then return false end
    local dist = #(GetEntityCoords(pedA) - GetEntityCoords(pedB))
    return dist <= maxPatchDistance()
end

local function beginPatchTreatment(medicSrc, targetSrc, medicCharacterId, wasDead)
    local remaining = math.max(cooldownRemaining(medicSrc), cooldownRemaining(targetSrc))
    if remaining > 0 then
        notify(medicSrc, ('Treatment is cooling down for %d more second%s.'):format(
            math.ceil(remaining / 1000), remaining > 1000 and 's' or ''), 'error')
        return false
    end
    if PendingPatchTreatments[medicSrc] then
        notify(medicSrc, 'You are already treating someone.', 'error')
        return false
    end
    for _, treatment in pairs(PendingPatchTreatments) do
        if treatment.target == targetSrc then
            notify(medicSrc, 'Another medic is already treating that patient.', 'error')
            return false
        end
    end
    local duration = math.max(3000, math.floor(tonumber((Config.Patch or {}).treatmentMs) or 8000))
    PendingPatchTreatments[medicSrc] = {
        target = targetSrc, characterId = tostring(medicCharacterId), wasDead = wasDead == true,
        startedAt = GetGameTimer(), duration = duration,
    }
    local medicName = nameFor(medicCharacterId)
    setTreatmentState(targetSrc, {
        active = true, medicCharacterId = tostring(medicCharacterId), medicName = medicName,
        endsAt = os.time() + math.ceil(duration / 1000),
    })
    notify(medicSrc, ('Treatment started for Character ID %s. Stay nearby.'):format(tostring(cid(targetSrc) or '?')), 'inform')
    TriggerClientEvent('cm-ems:client:startPatchTreatment', medicSrc, duration, targetSrc, wasDead == true)
    TriggerClientEvent('cm-ems:client:patchTreatmentStatus', targetSrc, 'started', duration, medicName)
    return true
end

RegisterNetEvent('cm-ems:server:requestPatch', function(targetSrc)
    local src = source
    if not rateLimit(src, 'ems_patch_request', 1500) then return end
    targetSrc = tonumber(targetSrc)
    if not targetSrc or targetSrc == src or not GetPlayerName(targetSrc) then return end
    local remaining = math.max(cooldownRemaining(src), cooldownRemaining(targetSrc))
    if remaining > 0 then
        notify(src, ('Treatment is cooling down for %d more second%s.'):format(
            math.ceil(remaining / 1000), remaining > 1000 and 's' or ''), 'error')
        return
    end

    local member, characterId = patchMember(src)
    if not member then
        notify(src, 'You are not authorized to treat players.', 'error')
        return
    end

    if not withinPatchRange(src, targetSrc) then
        notify(src, 'Move closer to patch them up.', 'error')
        return
    end

    local isDead = false
    pcall(function() isDead = exports[Config.PlayerDataResource]:IsDead(targetSrc) == true end)

    if isDead then
        beginPatchTreatment(src, targetSrc, characterId, true)
        return
    end

    -- Conscious: needs their consent first.
    local existing = PendingPatchOffers[targetSrc]
    if existing and GetGameTimer() < existing.expires then
        notify(src, 'They already have a pending treatment offer.', 'error')
        return
    end
    local timeoutMs = tonumber((Config.Patch or {}).offerTimeoutMs) or 15000
    PendingPatchOffers[targetSrc] = { from = src, expires = GetGameTimer() + timeoutMs }
    notify(src, 'Offer sent. Waiting for their response.', 'inform')
    TriggerClientEvent('cm-ems:client:patchOffer', targetSrc, timeoutMs, nameFor(characterId))
end)

RegisterNetEvent('cm-ems:server:patchOfferResponse', function(accepted)
    local src = source
    local offer = PendingPatchOffers[src]
    PendingPatchOffers[src] = nil
    if not offer or GetGameTimer() >= offer.expires or not GetPlayerName(offer.from) then return end

    if accepted ~= true then
        notify(offer.from, 'They declined treatment.', 'error')
        return
    end

    -- Re-validate everything server-side: the healer may have gone off duty,
    -- lost the permission, or walked away during the wait. Never trust that
    -- the original request check still holds by the time of a delayed reply.
    local member = patchMember(offer.from)
    if not member then
        notify(src, 'The medic is no longer able to treat you.', 'error')
        return
    end
    if not withinPatchRange(offer.from, src) then
        notify(offer.from, 'They moved too far away.', 'error')
        return
    end

    notify(offer.from, 'Treatment request accepted.', 'success')
    beginPatchTreatment(offer.from, src, cid(offer.from), false)
end)

RegisterNetEvent('cm-ems:server:completePatchTreatment', function(finished)
    local medicSrc = source
    local treatment = PendingPatchTreatments[medicSrc]
    PendingPatchTreatments[medicSrc] = nil
    if not treatment then return end
    local targetSrc = tonumber(treatment.target)
    setTreatmentState(targetSrc, false)
    applyPatchCooldown(medicSrc, targetSrc)
    if finished ~= true then
        notify(medicSrc, 'Treatment cancelled.', 'error')
        if GetPlayerName(targetSrc) then TriggerClientEvent('cm-ems:client:patchTreatmentStatus', targetSrc, 'cancelled') end
        return
    end
    if GetGameTimer() - treatment.startedAt < math.floor(treatment.duration * 0.85) then return end
    if not GetPlayerName(targetSrc) or not patchMember(medicSrc) or not withinPatchRange(medicSrc, targetSrc) then
        notify(medicSrc, 'Treatment cancelled because the patient is no longer nearby.', 'error')
        if GetPlayerName(targetSrc) then TriggerClientEvent('cm-ems:client:patchTreatmentStatus', targetSrc, 'cancelled') end
        return
    end
    local isDead = false
    pcall(function() isDead = exports[Config.PlayerDataResource]:IsDead(targetSrc) == true end)
    if treatment.wasDead and not isDead then
        notify(medicSrc, 'That patient has already been revived.', 'error')
        TriggerClientEvent('cm-ems:client:patchTreatmentStatus', targetSrc, 'cancelled')
        return
    end
    local ok = false
    pcall(function() ok = exports[Config.PlayerDataResource]:Heal(targetSrc, 100, 'ems_patch') == true end)
    if not ok then
        notify(medicSrc, 'Could not complete treatment.', 'error')
        TriggerClientEvent('cm-ems:client:patchTreatmentStatus', targetSrc, 'cancelled')
        return
    end
    local targetCharacterId = cid(targetSrc)
    local incidentId
    if treatment.wasDead and targetCharacterId then
        if EMSLinkTreatmentToDispatch then
            incidentId = EMSLinkTreatmentToDispatch(medicSrc, targetSrc)
        end
        local deathCount = 0
        pcall(function()
            local info = exports[Config.PlayerDataResource]:GetDeathInfo(targetSrc)
            deathCount = tonumber(info and info.deathCount) or 0
        end)
        if EMSAddTaskProgress then
            EMSAddTaskProgress(treatment.characterId, 'patient_revives', 1,
                ('patient:%s:death:%d'):format(targetCharacterId, deathCount))
        end
        pcall(function() exports['cm-ems']:AwardMedicReward(medicSrc, targetSrc, 'ems_treatment_reward') end)
    end
    log(treatment.characterId, 'patch_player', { targetCharacterId = targetCharacterId, downed = treatment.wasDead })
    TriggerEvent('cm-ems:server:recordMedicalEvent', targetSrc, {
        event = treatment.wasDead and 'ems_field_revive' or 'ems_field_treatment',
        incidentId = incidentId, medicSource = medicSrc,
        treatment = treatment.wasDead and 'Field resuscitation and full stabilization' or 'Field treatment and full stabilization',
        outcome = treatment.wasDead and 'revived_on_scene' or 'treated_on_scene',
    })
    notify(medicSrc, treatment.wasDead and 'Patient revived successfully.' or 'Treatment completed successfully.', 'success')
    TriggerClientEvent('cm-ems:client:patchTreatmentStatus', targetSrc, 'completed', 0,
        nameFor(treatment.characterId),
        treatment.wasDead and 'You were revived and stabilized on scene.' or 'Your injuries were treated and stabilized.')
end)

AddEventHandler('playerDropped', function()
    local src = source
    PendingPatchOffers[src] = nil
    PatchCooldowns[src] = nil
    local ownTreatment = PendingPatchTreatments[src]
    if ownTreatment then cancelTreatment(src, ownTreatment, 'Treatment stopped because the medic disconnected.') end
    for medicSrc, treatment in pairs(PendingPatchTreatments) do
        if treatment.target == src then
            cancelTreatment(medicSrc, treatment, 'Treatment stopped because the patient disconnected.')
        end
    end
end)

AddEventHandler('cm-ems:server:memberWentOffDuty', function(src)
    src = tonumber(src)
    if not src then return end
    PendingPatchOffers[src] = nil
    for targetSrc, offer in pairs(PendingPatchOffers) do
        if tonumber(offer.from) == src then
            PendingPatchOffers[targetSrc] = nil
            if GetPlayerName(targetSrc) then
                TriggerClientEvent('cm-ems:client:patchTreatmentStatus', targetSrc, 'cancelled', 0, nil,
                    'The medic is no longer available.')
            end
        end
    end
    local treatment = PendingPatchTreatments[src]
    if not treatment then return end
    cancelTreatment(src, treatment, 'Treatment stopped because the medic left duty.')
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, treatment in pairs(PendingPatchTreatments) do
        setTreatmentState(treatment.target, false)
    end
end)

CreateThread(function()
    while true do
        Wait(500)
        for medicSrc, treatment in pairs(PendingPatchTreatments) do
            local targetSrc = tonumber(treatment.target)
            local cancelReason
            if not GetPlayerName(medicSrc) or not GetPlayerName(targetSrc) then
                cancelReason = 'A player disconnected.'
            elseif not patchMember(medicSrc) then
                cancelReason = 'The medic is no longer available or on duty.'
            elseif not withinPatchRange(medicSrc, targetSrc) then
                cancelReason = 'Medic and patient moved too far apart.'
            else
                local medicDead, targetDead = false, false
                local medicPed, targetPed = GetPlayerPed(medicSrc), GetPlayerPed(targetSrc)
                pcall(function() medicDead = exports[Config.PlayerDataResource]:IsDead(medicSrc) == true end)
                pcall(function() targetDead = exports[Config.PlayerDataResource]:IsDead(targetSrc) == true end)
                if medicDead then
                    cancelReason = 'The medic became incapacitated.'
                elseif treatment.wasDead ~= true and targetDead then
                    cancelReason = 'Treatment stopped because the patient became unconscious.'
                elseif medicPed and medicPed ~= 0 and GetVehiclePedIsIn(medicPed, false) ~= 0 then
                    cancelReason = 'Treatment stopped when the medic entered a vehicle.'
                elseif targetPed and targetPed ~= 0 and GetVehiclePedIsIn(targetPed, false) ~= 0 then
                    cancelReason = 'Treatment stopped when the patient entered a vehicle.'
                end
            end
            if cancelReason then
                cancelTreatment(medicSrc, treatment, cancelReason)
            end
        end
    end
end)
