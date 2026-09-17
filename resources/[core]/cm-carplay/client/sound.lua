--[[
    cm-carplay - Positional 3D audio engine ("ts-sounds")

    This is a self-contained audio playback system that the resource uses to
    play CarPlay music (and any other positional audio) through the NUI's own
    Web Audio pipeline instead of native GTA audio natives. It tracks:

      - "audio sources": a URL/file plus playback state (playing, currentTime,
        owner client, event callbacks).
      - "speakers": a positional emitter that points an audio source at a
        world position or an attached entity, with falloff/config sent to
        the NUI so it can pan/attenuate the Web Audio node.

    Every frame-ish, a background thread pushes listener + speaker positions
    to the NUI so it can do the actual 3D panning/volume math in JS; this
    Lua side is bookkeeping, native-side helpers (raycasts, entity queries),
    and the ts-sounds:* event/export surface.

    client/main.lua (loaded after this file) calls into several of the
    globals defined here directly (GetCurrentTime, FetchData) since both
    files are client_scripts sharing one Lua environment.
]]

local audioSources = {}      -- audioSourceId -> { url, config, playing, currentTime, isLocalFile, audioOwner }
local audioCallbacks = {
    onPlaybackStarted = {},
    onPlaybackStopped = {},
    onPlaybackPaused = {},
    onPlaybackResumed = {},
    onAudioReady = {},
    onAudioError = {},
    onAudioEnded = {},
}
local speakers = {}          -- speakerId -> { position, config, audioSourceId, lastUpdate, frameCount, lastFilterUpdate }
local resourceName = GetCurrentResourceName()

local POSITION_UPDATE_INTERVAL_MS = 50
local lastSpeakerPositions = {}          -- speakerId -> last position sent to NUI
local FORCE_UPDATE_FRAME_INTERVAL = 5    -- force a position push at least this often even if unmoved
local applyLowPassFilterGlobally = true
local speakerLowPassFilterEnabled = {}   -- speakerId -> bool
local OUTSIDE_CLOSED_VOLUME_FACTOR = 0.15
local OUTSIDE_OPEN_VOLUME_FACTOR = 0.15
local OUTSIDE_CLOSED_LOWPASS_FREQUENCY = 1100
local OUTSIDE_CLOSED_LOWPASS_REDUCTION = 45

local SPEAKER_CONFIG_DEFAULTS = {
    refDistance = 1.0,
    maxDistance = 50.0,
    rolloffFactor = 1.0,
    coneInnerAngle = 360,
    coneOuterAngle = 360,
    coneOuterGain = 0.0,
    fadeDurationMs = 1000,
    volumeMultiplier = 1.0,
    lowPassGainReductionPercent = 0,
    lowPassFrequency = 0,
    attachedEntity = nil,
    attachedOffset = nil,
    isInVehicle = false,
    pannerDisabled = false,
    pannerManuallySet = false,
    outsideVolumeFactor = OUTSIDE_CLOSED_VOLUME_FACTOR,
}

local AUDIO_SOURCE_CONFIG_DEFAULTS = {
    loop = false,
    volume = 1.0,
    playbackRate = 1.0,
    fadeInDuration = 0,
    fadeOutDuration = 0,
}

-- Audio sources ---------------------------------------------------------

local function isYoutubeUrl(url)
    local youtubePatterns = {
        "youtube.com/watch%?v=",
        "youtu.be/",
        "youtube.com/embed/",
        "youtube.com/shorts/",
        "youtube.com/live/",
    }

    -- A bare 11-char video ID (no URL at all) also counts.
    if string.match(url, "^[a-zA-Z0-9_-]+$") and string.len(url) == 11 then
        return true
    end

    for _, pattern in ipairs(youtubePatterns) do
        if string.find(url, pattern) then
            return true
        end
    end

    return false
end
IsYoutubeUrl = isYoutubeUrl

local function createSourceId()
    local id = math.random(100000, 999999)
    while audioSources[tostring(id)] do
        id = math.random(100000, 999999)
    end
    return id
end
createSourceID = createSourceId

local function addAudioSource(audioSourceId, url, config, callbacks, audioOwner, ownerGiven)
    if not url then
        return false
    end

    if not audioSourceId then
        audioSourceId = tostring(createSourceID())
    end

    if audioSources[audioSourceId] then
        StopAudioSource(audioSourceId)
    end

    config = config or AUDIO_SOURCE_CONFIG_DEFAULTS
    local isHttpUrl = string.match(url, "^https://") or string.match(url, "^http://")
    local isLocalFile = not isHttpUrl and not IsYoutubeUrl(url)

    local resolvedOwner = ownerGiven
    if not audioOwner or not ownerGiven then
        resolvedOwner = GetPlayerServerId(PlayerId())
    end

    audioSources[audioSourceId] = {
        url = url,
        config = config,
        playing = false,
        currentTime = 0,
        isLocalFile = isLocalFile,
        audioOwner = resolvedOwner,
    }

    if callbacks then
        local callbackEvents = {
            "onPlaybackStarted", "onPlaybackStopped", "onPlaybackPaused",
            "onPlaybackResumed", "onAudioReady", "onAudioError", "onAudioEnded",
        }
        for _, eventName in ipairs(callbackEvents) do
            local handler = callbacks[eventName]
            if handler then
                if type(handler) ~= "function" then
                    handler = function() end
                end
                RegisterAudioCallback(audioSourceId, eventName, handler, audioOwner)
            end
        end
    end

    SendNUIMessage({
        type = "addAudioSource",
        audioSourceId = audioSourceId,
        url = url,
        config = config,
    })

    return true
end
AddAudioSource = addAudioSource

local function removeAudioSource(audioSourceId)
    local source = audioSources[audioSourceId]
    if not source then
        return false
    end

    local owner = source.audioOwner
    StopAudioSource(audioSourceId)

    for speakerId, speaker in pairs(speakers) do
        if speaker.audioSourceId == audioSourceId then
            RemoveSpeaker(speakerId)
        end
    end

    audioSources[audioSourceId] = nil

    for eventName in pairs(audioCallbacks) do
        audioCallbacks[eventName][audioSourceId] = nil
    end

    SendNUIMessage({
        type = "removeAudioSource",
        audioSourceId = audioSourceId,
    })

    -- Only tell the server if we were the ones who registered the source.
    if owner == GetPlayerServerId(PlayerId()) then
        TriggerServerEvent("ts-sounds:server:RemoveAudioSource", audioSourceId)
    end

    return true
end
RemoveAudioSource = removeAudioSource

RegisterNetEvent("ts-sounds:client:AddSource", AddAudioSource)
RegisterNetEvent("ts-sounds:client:RemoveSource", RemoveAudioSource)
exports("AddAudioSource", AddAudioSource)
exports("RemoveAudioSource", RemoveAudioSource)

local function setAudioLoop(audioSourceId, loop)
    local source = audioSources[audioSourceId]
    if not source then
        return false
    end

    if source.config then
        source.config.loop = loop
    else
        source.config = { loop = loop }
    end

    SendNUIMessage({
        type = "setLoop",
        audioSourceId = audioSourceId,
        loop = loop,
    })

    return true
end
SetAudioLoop = setAudioLoop
RegisterNetEvent("ts-sounds:client:SetAudioLoop", SetAudioLoop)
exports("SetAudioLoop", SetAudioLoop)

local function playAudioSource(audioSourceId)
    local source = audioSources[audioSourceId]
    if not source then
        return false
    end

    source.playing = true
    SendNUIMessage({ type = "playAudioSource", audioSourceId = audioSourceId })
    return true
end
PlayAudioSource = playAudioSource
RegisterNetEvent("ts-sounds:client:PlayAudio", PlayAudioSource)
exports("PlayAudioSource", PlayAudioSource)

local function stopAudioSource(audioSourceId)
    local source = audioSources[audioSourceId]
    if not source then
        return false
    end

    source.playing = false
    SendNUIMessage({ type = "stopAudioSource", audioSourceId = audioSourceId })
    return true
end
StopAudioSource = stopAudioSource

local function isAudioSourcePlaying(audioSourceId)
    local source = audioSources[audioSourceId]
    return source ~= nil and source.playing or false
end
IsAudioSourcePlaying = isAudioSourcePlaying

local function getAudioSourceTime(audioSourceId)
    local source = audioSources[audioSourceId]
    if not source then
        return 0
    end
    return source.currentTime or 0
end
GetAudioSourceTime = getAudioSourceTime

-- Speakers ----------------------------------------------------------------

local function addSpeaker(speakerId, position, config, audioSourceId)
    if not (speakerId and position) or not audioSourceId then
        return false
    end

    local source = audioSources[audioSourceId]
    if not source then
        print("Error: Audio source " .. audioSourceId .. " not found")
        return false
    end

    config = config or {}
    local resolvedConfig = {
        refDistance = config.refDistance or SPEAKER_CONFIG_DEFAULTS.refDistance,
        maxDistance = config.maxDistance or SPEAKER_CONFIG_DEFAULTS.maxDistance,
        rolloffFactor = config.rolloffFactor or SPEAKER_CONFIG_DEFAULTS.rolloffFactor,
        coneInnerAngle = config.coneInnerAngle or SPEAKER_CONFIG_DEFAULTS.coneInnerAngle,
        coneOuterAngle = config.coneOuterAngle or SPEAKER_CONFIG_DEFAULTS.coneOuterAngle,
        coneOuterGain = config.coneOuterGain or SPEAKER_CONFIG_DEFAULTS.coneOuterGain,
        fadeDurationMs = config.fadeDurationMs or SPEAKER_CONFIG_DEFAULTS.fadeDurationMs,
        volumeMultiplier = config.volumeMultiplier or SPEAKER_CONFIG_DEFAULTS.volumeMultiplier,
        lowPassGainReductionPercent = config.lowPassGainReductionPercent or SPEAKER_CONFIG_DEFAULTS.lowPassGainReductionPercent,
        lowPassFrequency = config.lowPassFrequency or SPEAKER_CONFIG_DEFAULTS.lowPassFrequency,
        attachedOffset = config.attachedOffset or SPEAKER_CONFIG_DEFAULTS.attachedOffset,
        isInVehicle = false,
        pannerDisabled = false,
        pannerManuallySet = false,
        outsideVolumeFactor = config.outsideVolumeFactor or SPEAKER_CONFIG_DEFAULTS.outsideVolumeFactor,
    }

    -- netID (a network id) takes priority over a raw attachedEntity handle.
    -- NetworkGetEntityFromNetworkId returns 0 (not nil) when the entity
    -- hasn't streamed in on this client yet -- and 0 is truthy in Lua, so
    -- this must be checked explicitly or a not-yet-resolved vehicle gets
    -- permanently treated as "attached" to entity handle 0.
    local attachedEntity = config.attachedEntity
    if config.netID then
        local netEntity = NetworkGetEntityFromNetworkId(config.netID)
        if netEntity and netEntity ~= 0 then
            attachedEntity = netEntity
        end
    end
    resolvedConfig.netID = config.netID
    resolvedConfig.attachedEntity = attachedEntity

    speakers[speakerId] = {
        position = position,
        config = resolvedConfig,
        audioSourceId = audioSourceId,
        lastUpdate = 0,
        frameCount = 0,
    }
    lastSpeakerPositions[speakerId] = position

    SendNUIMessage({
        type = "addSpeaker",
        speakerId = speakerId,
        position = { position.x, position.y, position.z },
        config = resolvedConfig,
        audioSourceId = audioSourceId,
    })

    return true
end
AddSpeaker = addSpeaker
RegisterNetEvent("ts-sounds:client:AddSpeaker", AddSpeaker)

local function removeSpeaker(speakerId)
    if not speakers[speakerId] then
        return false
    end

    speakers[speakerId] = nil
    lastSpeakerPositions[speakerId] = nil
    speakerLowPassFilterEnabled[speakerId] = nil

    SendNUIMessage({ type = "removeSpeaker", speakerId = speakerId })
    return true
end
RemoveSpeaker = removeSpeaker
exports("AddSpeaker", AddSpeaker)
exports("RemoveSpeaker", RemoveSpeaker)

local function hasPositionChanged(a, b, threshold)
    threshold = threshold or 0.05
    if not a or not b then
        return true
    end

    local dx = a.x - b.x
    local dy = a.y - b.y
    local dz = a.z - b.z
    return (dx * dx + dy * dy + dz * dz) > (threshold * threshold)
end
HasPositionChanged = hasPositionChanged

local function updateSpeakerPosition(speakerId, position)
    local speaker = speakers[speakerId]
    if not speaker then
        return false
    end

    if HasPositionChanged(position, speaker.position) then
        speaker.position = position
        lastSpeakerPositions[speakerId] = position
    end

    return true
end
UpdateSpeakerPosition = updateSpeakerPosition

local function updateSpeakerConfig(speakerId, configPatch)
    local speaker = speakers[speakerId]
    if not speaker then
        return false
    end

    for key, value in pairs(configPatch) do
        speaker.config[key] = value
    end

    SendNUIMessage({
        type = "updateSpeakerConfig",
        speakerId = speakerId,
        config = speaker.config,
    })

    return true
end
UpdateSpeakerConfig = updateSpeakerConfig

local function getSpeakerVolume(speakerId)
    local speaker = speakers[speakerId]
    if not speaker then
        return 0
    end
    return speaker.config.volumeMultiplier
end
GetSpeakerVolume = getSpeakerVolume

local function setSpeakerVolume(speakerId, volume)
    if not speakers[speakerId] then
        return false
    end
    if volume < 0 then
        return false
    end
    UpdateSpeakerConfig(speakerId, { volumeMultiplier = volume })
end
SetSpeakerVolume = setSpeakerVolume
RegisterNetEvent("ts-sounds:client:SetSpeakerVolume", SetSpeakerVolume)
exports("SetSpeakerVolume", SetSpeakerVolume)

-- Listener/speaker position broadcast tick --------------------------------
-- Every 50ms, push the camera listener transform plus any speaker whose
-- position moved (or hasn't refreshed in FORCE_UPDATE_FRAME_INTERVAL frames
-- once it's outside 70% of its own max distance) to the NUI for 3D panning.

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(POSITION_UPDATE_INTERVAL_MS)

        local playerPed = PlayerPedId()
        local listenerPos = GetEntityCoords(playerPed)
        local forward = GetEntityForwardVector(playerPed)
        local camRot = GetGameplayCamRot(2)
        local up = RotationToDirection(camRot)
        local upVector = vector3(0.0, 0.0, 1.0)

        local speakerUpdates = {}
        local updatedCount = 0

        for speakerId, speaker in pairs(speakers) do
            speaker.frameCount = (speaker.frameCount or 0) + 1

            local speakerPos = speaker.position
            local distance = #(listenerPos - speakerPos)

            local shouldUpdate = true
            if distance > speaker.config.maxDistance * 0.7 then
                shouldUpdate = speaker.frameCount >= FORCE_UPDATE_FRAME_INTERVAL
            end

            -- Close speakers update every tick; far ones only every Nth tick
            -- (unless they've genuinely never been sent to the NUI yet).
            if shouldUpdate or not lastSpeakerPositions[speakerId] then
                speaker.frameCount = 0

                local direction
                if distance > 0.01 then
                    direction = (speakerPos - listenerPos) / distance
                else
                    direction = vector3(0.0, 0.0, 1.0)
                end

                updatedCount = updatedCount + 1
                table.insert(speakerUpdates, {
                    id = speakerId,
                    position = { speakerPos.x, speakerPos.y, speakerPos.z },
                    orientation = { direction.x, direction.y, direction.z },
                    distance = distance,
                    lowPassFilterFade = 0.0,
                })
                lastSpeakerPositions[speakerId] = speakerPos
            end
        end

        if updatedCount > 0 then
            SendNUIMessage({
                type = "update",
                applyLowPassFilter = applyLowPassFilterGlobally,
                listener = {
                    position = { listenerPos.x, listenerPos.y, listenerPos.z },
                    forward = { forward.x, forward.y, forward.z },
                    up = { upVector.x, upVector.y, upVector.z },
                },
                speakers = speakerUpdates,
            })
        end
    end
end)

-- Geometry helpers ----------------------------------------------------------

-- Converts GTA pitch/roll/yaw (degrees) into a forward-facing direction vector.
local function rotationToDirection(rotation)
    local rad = {
        x = (math.pi / 180) * rotation.x,
        y = (math.pi / 180) * rotation.y,
        z = (math.pi / 180) * rotation.z,
    }

    local direction = {
        x = -math.sin(rad.z) * math.abs(math.cos(rad.x)),
        y = math.cos(rad.z) * math.abs(math.cos(rad.x)),
        z = math.sin(rad.x),
    }

    return vector3(direction.x, direction.y, direction.z)
end
RotationToDirection = rotationToDirection

local function isObstructed(from, to)
    local rayHandle = StartShapeTestRay(from.x, from.y, from.z, to.x, to.y, to.z, -1, -1, 1)
    local _, hit = GetShapeTestResult(rayHandle)
    return hit == 1
end
IsObstructed = isObstructed

local function calculateOcclusionStrength(from, to)
    if not IsObstructed(from, to) then
        return 0.0
    end
    return 0.8
end
CalculateOcclusionStrength = calculateOcclusionStrength

local function cleanupAudioResources()
    for speakerId in pairs(speakers) do
        RemoveSpeaker(speakerId)
    end
    for audioSourceId in pairs(audioSources) do
        RemoveAudioSource(audioSourceId)
    end
    lastSpeakerPositions = {}
    for eventName in pairs(audioCallbacks) do
        audioCallbacks[eventName] = {}
    end
end
CleanupAudioResources = cleanupAudioResources

local function setSpeakerLowPassFilter(speakerId, enabled)
    if not speakers[speakerId] then
        return false
    end

    speakerLowPassFilterEnabled[speakerId] = enabled

    SendNUIMessage({
        type = "setSpeakerFilter",
        speakerId = speakerId,
        enabled = enabled,
    })

    return true
end
SetSpeakerLowPassFilter = setSpeakerLowPassFilter

local function setSpeakerLowPassFilterPercentage(speakerId, percent)
    local speaker = speakers[speakerId]
    if not speaker or not percent then
        return false
    end
    if percent < 0 or percent > 100 then
        return false
    end

    speaker.config.lowPassGainReductionPercent = percent

    SendNUIMessage({
        type = "updateSpeakerConfig",
        speakerId = speakerId,
        config = speaker.config,
    })

    return true
end
SetSpeakerLowPassFilterPercentage = setSpeakerLowPassFilterPercentage

local function setSpeakerLowPassFilterFrequency(speakerId, frequency)
    local speaker = speakers[speakerId]
    if not speaker then
        return false
    end

    frequency = tonumber(frequency)
    if not (frequency and frequency >= 20 and frequency <= 22050) then
        return false
    end

    speaker.config.lowPassFrequency = frequency

    SendNUIMessage({
        type = "updateSpeakerConfig",
        speakerId = speakerId,
        config = speaker.config,
    })

    return true
end
SetSpeakerLowPassFilterFrequency = setSpeakerLowPassFilterFrequency

local function updateAllSpeakersLowPassFilter(percent)
    for speakerId, speaker in pairs(speakers) do
        if percent ~= nil then
            speaker.config.lowPassGainReductionPercent = percent
        end
        SendNUIMessage({
            type = "updateSpeakerConfig",
            speakerId = speakerId,
            config = speaker.config,
        })
    end
end
UpdateAllSpeakersLowPassFilter = updateAllSpeakersLowPassFilter

AddEventHandler("onResourceStop", function(stoppedResource)
    if stoppedResource == resourceName then
        CleanupAudioResources()
    end
end)

local function seekAudioSource(audioSourceId, position)
    if not audioSources[audioSourceId] then
        return false
    end

    SendNUIMessage({
        type = "seekAudioSource",
        audioSourceId = audioSourceId,
        position = position,
    })

    return true
end
SeekAudioSource = seekAudioSource
RegisterNetEvent("ts-sounds:client:SeekAudio", SeekAudioSource)
exports("SeekAudioSource", SeekAudioSource)

-- Entity-attached speakers --------------------------------------------------

local function attachSpeakerToEntity(speakerId, entity, offset)
    local speaker = speakers[speakerId]
    if not speaker then
        print("Error: Speaker " .. speakerId .. " not found")
        return false
    end

    if not DoesEntityExist(entity) then
        print("Error: Entity " .. entity .. " does not exist")
        return false
    end

    offset = offset or vector3(0.0, 0.0, 0.0)

    speaker.config.attachedEntity = entity
    speaker.config.attachedOffset = offset

    return true
end
AttachSpeakerToEntity = attachSpeakerToEntity

local function detachSpeakerFromEntity(speakerId)
    local speaker = speakers[speakerId]
    if not speaker then
        return false
    end

    if not speaker.config.attachedEntity then
        return false
    end

    speaker.config.attachedEntity = nil
    speaker.config.attachedOffset = nil
    return true
end
DetachSpeakerFromEntity = detachSpeakerFromEntity

-- Converts pitch/roll/yaw (degrees) into a 3x3 rotation matrix, GTA-native convention.
local function rotationToMatrix(rotation)
    local x = (math.pi / 180) * rotation.x
    local y = (math.pi / 180) * rotation.y
    local z = (math.pi / 180) * rotation.z

    local sx, cx = math.sin(x), math.cos(x)
    local sy, cy = math.sin(y), math.cos(y)
    local sz, cz = math.sin(z), math.cos(z)

    return {
        { cz * cy, cz * sy * sx - sz * cx, cz * sy * cx + sz * sx },
        { sz * cy, sz * sy * sx + cz * cx, sz * sy * cx - cz * sx },
        { -sy, cy * sx, cy * cx },
    }
end
RotationToMatrix = rotationToMatrix

local function applyRotationToOffset(matrix, offset)
    return vector3(
        matrix[1][1] * offset.x + matrix[1][2] * offset.y + matrix[1][3] * offset.z,
        matrix[2][1] * offset.x + matrix[2][2] * offset.y + matrix[2][3] * offset.z,
        matrix[3][1] * offset.x + matrix[3][2] * offset.y + matrix[3][3] * offset.z
    )
end
ApplyRotationToOffset = applyRotationToOffset

exports("AttachSpeakerToEntity", AttachSpeakerToEntity)
exports("DetachSpeakerFromEntity", DetachSpeakerFromEntity)

exports("CreateAttachedSpeaker", function(speakerId, entity, config, audioSourceId, offset)
    if not (speakerId and entity) or not audioSourceId then
        print("Error: Missing required parameters for CreateAttachedSpeaker")
        return false
    end

    if not DoesEntityExist(entity) then
        print("Error: Entity " .. entity .. " does not exist")
        return false
    end

    local entityPos = GetEntityCoords(entity)
    config = config or SPEAKER_CONFIG_DEFAULTS
    offset = offset or vector3(0.0, 0.0, 0.0)

    config.attachedEntity = entity
    config.attachedOffset = offset

    if not AddSpeaker(speakerId, entityPos, config, audioSourceId) then
        return false
    end

    return true
end)

local function isEntityVehicle(entity)
    if not entity then
        return false
    end
    return GetEntityType(entity) == 2
end
IsEntityVehicle = isEntityVehicle

local function isPlayerInEntity(entity)
    if not (entity and DoesEntityExist(entity)) then
        return false
    end
    return GetVehiclePedIsIn(PlayerPedId(), false) == entity
end
IsPlayerInEntity = isPlayerInEntity

-- A vehicle counts as "open" (for the low-pass "muffled" cutoff) if any door
-- is open past a hair, or if it's fully sealed but its windows are down.
local function isVehicleOpenOrDamaged(vehicle)
    if not (vehicle and DoesEntityExist(vehicle)) then
        return false
    end

    for doorIndex = 0, 5 do
        if DoesVehicleHaveDoor(vehicle, doorIndex) then
            if GetVehicleDoorAngleRatio(vehicle, doorIndex) > 0.1 then
                return true
            end
        end
    end

    -- Broken/missing windows count as "open" outright; intact windows only
    -- count as open if they've been rolled down via the CarPlay toggle.
    local listenerVehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if not AreAllVehicleWindowsIntact(vehicle) or (listenerVehicle == vehicle and windowsOpen) then
        return true
    end

    return false
end
IsVehicleOpenOrDamaged = isVehicleOpenOrDamaged

local function toggleSpeakerPanner(speakerId, disabled)
    local speaker = speakers[speakerId]
    if speaker then
        speaker.config.pannerDisabled = disabled
        speaker.config.pannerManuallySet = true

        SendNUIMessage({
            type = "updateVehicleSpeaker",
            speakerId = speakerId,
            priority = true,
            config = {
                pannerDisabled = speaker.config.pannerDisabled,
                lowPassFrequency = speaker.config.lowPassFrequency,
                lowPassGainReductionPercent = speaker.config.lowPassGainReductionPercent,
                isInVehicle = speaker.config.isInVehicle,
                outsideVolumeFactor = speaker.config.outsideVolumeFactor,
            },
        })

        speaker.lastFilterUpdate = GetGameTimer()
    end
end
ToggleSpeakerPanner = toggleSpeakerPanner
exports("ToggleSpeakerPanner", ToggleSpeakerPanner)

local function resetSpeakerPannerOverride(speakerId)
    local speaker = speakers[speakerId]
    if speaker then
        speaker.config.pannerManuallySet = false
        return true
    end
    return false
end
ResetSpeakerPannerOverride = resetSpeakerPannerOverride
exports("ResetSpeakerPannerOverride", ResetSpeakerPannerOverride)

-- Keeps a vehicle-attached speaker's panner/low-pass state in sync with
-- whether the player is inside that (closed) vehicle: muffled from outside,
-- clean from inside, and moderately muffled from inside an open/damaged one.
local function updateVehicleSpeakerAudio(speakerId)
    local speaker = speakers[speakerId]
    if not (speaker and speaker.config.attachedEntity) then
        return
    end

    local vehicle = speaker.config.attachedEntity
    if not IsEntityVehicle(vehicle) then
        return
    end

    local playerInside = IsPlayerInEntity(vehicle)
    local vehicleOpen = IsVehicleOpenOrDamaged(vehicle)
    local changed = false

    if speaker.config.isInVehicle ~= playerInside then
        speaker.config.isInVehicle = playerInside
        changed = true
    end

    if playerInside then
        if not speaker.config.pannerManuallySet and speaker.config.pannerDisabled ~= true then
            speaker.config.pannerDisabled = true
            changed = true
        end

        local currentLowPass = (speaker.config.lowPassFrequency and speaker.config.lowPassFrequency > 0)
            and speaker.config.lowPassFrequency or speaker.config.lowPassGainReductionPercent
        if currentLowPass > 0 then
            speaker.config.lowPassFrequency = 0
            speaker.config.lowPassGainReductionPercent = 0
            changed = true
        end
        if speaker.config.outsideVolumeFactor ~= 1.0 then
            speaker.config.outsideVolumeFactor = 1.0
            changed = true
        end
    else
        if not speaker.config.pannerManuallySet and speaker.config.pannerDisabled ~= false then
            speaker.config.pannerDisabled = false
            changed = true
        end

        if vehicleOpen then
            -- Outside with a door/window open: sound is still positional, but
            -- much less occluded than a sealed cabin.
            local currentLowPass = (speaker.config.lowPassFrequency and speaker.config.lowPassFrequency > 0)
                and speaker.config.lowPassFrequency or speaker.config.lowPassGainReductionPercent
            if currentLowPass > 0 then
                speaker.config.lowPassFrequency = 0
                speaker.config.lowPassGainReductionPercent = 0
                changed = true
            end
            if speaker.config.outsideVolumeFactor ~= OUTSIDE_OPEN_VOLUME_FACTOR then
                speaker.config.outsideVolumeFactor = OUTSIDE_OPEN_VOLUME_FACTOR
                changed = true
            end
        else
            -- Outside a sealed vehicle: apply a realistic closed-door
            -- occlusion profile while retaining enough mids to identify the
            -- song. Distance is applied independently by the Web Audio panner.
            local currentLowPass = (speaker.config.lowPassFrequency and speaker.config.lowPassFrequency ~= OUTSIDE_CLOSED_LOWPASS_FREQUENCY)
                and speaker.config.lowPassFrequency or speaker.config.lowPassGainReductionPercent
            if currentLowPass ~= OUTSIDE_CLOSED_LOWPASS_REDUCTION then
                speaker.config.lowPassFrequency = OUTSIDE_CLOSED_LOWPASS_FREQUENCY
                speaker.config.lowPassGainReductionPercent = OUTSIDE_CLOSED_LOWPASS_REDUCTION
                changed = true
            end
            if speaker.config.outsideVolumeFactor ~= OUTSIDE_CLOSED_VOLUME_FACTOR then
                speaker.config.outsideVolumeFactor = OUTSIDE_CLOSED_VOLUME_FACTOR
                changed = true
            end
        end
    end

    if changed then
        SendNUIMessage({
            type = "updateVehicleSpeaker",
            speakerId = speakerId,
            priority = true,
            config = {
                pannerDisabled = speaker.config.pannerDisabled,
                lowPassFrequency = speaker.config.lowPassFrequency,
                lowPassGainReductionPercent = speaker.config.lowPassGainReductionPercent,
                isInVehicle = speaker.config.isInVehicle,
                outsideVolumeFactor = speaker.config.outsideVolumeFactor,
            },
        })
        speaker.lastFilterUpdate = GetGameTimer()
    end
end
UpdateVehicleSpeakerAudio = updateVehicleSpeakerAudio

local function updateEntitySpeakerAudio(speakerId)
    local speaker = speakers[speakerId]
    if not (speaker and speaker.config.attachedEntity) then
        return
    end

    local entity = speaker.config.attachedEntity
    if not DoesEntityExist(entity) then
        return
    end

    if IsEntityVehicle(entity) then
        UpdateVehicleSpeakerAudio(speakerId)
    elseif IsEntityAPed(entity) then
        if not speaker.config.pannerManuallySet and speaker.config.pannerDisabled then
            speaker.config.pannerDisabled = false
            SendNUIMessage({
                type = "updateSpeakerConfig",
                speakerId = speakerId,
                config = { pannerDisabled = false },
            })
        end
    elseif IsEntityAnObject(entity) then
        if not speaker.config.pannerManuallySet and speaker.config.pannerDisabled then
            speaker.config.pannerDisabled = false
            SendNUIMessage({
                type = "updateSpeakerConfig",
                speakerId = speakerId,
                config = { pannerDisabled = false },
            })
        end
    end
end
UpdateEntitySpeakerAudio = updateEntitySpeakerAudio

local function pauseAudioSource(audioSourceId)
    if not audioSources[audioSourceId] then
        return false
    end
    SendNUIMessage({ type = "pauseAudioSource", audioSourceId = audioSourceId })
    return true
end
PauseAudioSource = pauseAudioSource

local function resumeAudioSource(audioSourceId)
    if not audioSources[audioSourceId] then
        return false
    end
    SendNUIMessage({ type = "resumeAudioSource", audioSourceId = audioSourceId })
    return true
end
ResumeAudioSource = resumeAudioSource

RegisterNetEvent("ts-sounds:client:PauseAudio", PauseAudioSource)
RegisterNetEvent("ts-sounds:client:ResumeAudio", ResumeAudioSource)
exports("PauseAudioSource", PauseAudioSource)
exports("ResumeAudioSource", ResumeAudioSource)

-- Entity-attached speaker position/lifecycle thread ------------------------
-- Every 100ms: for each speaker attached to an entity, if the entity no
-- longer exists, park its speaker in a "stale" bucket (and tear it down
-- after 30s of staying gone); otherwise keep its position updated and, for
-- vehicles, keep exactly one active speaker registered per vehicle per tick
-- (extra speakers on the same vehicle this tick get detached instead of
-- double-updating the same vehicle's panner state).

local ATTACHED_UPDATE_INTERVAL_MS = 100

Citizen.CreateThread(function()
    local entitySpeakersThisTick = {}
    local staleEntitySpeakers = {}

    while true do
        Citizen.Wait(ATTACHED_UPDATE_INTERVAL_MS)

        entitySpeakersThisTick = {}

        for speakerId, speaker in pairs(speakers) do
            local attachedEntity = speaker.config.attachedEntity

            -- Self-heal a speaker whose vehicle hadn't streamed in yet when
            -- it was first added (see AddSpeaker's netID resolution) -- keep
            -- retrying every tick instead of leaving it stuck unattached.
            if not attachedEntity and speaker.config.netID then
                local netEntity = NetworkGetEntityFromNetworkId(speaker.config.netID)
                if netEntity and netEntity ~= 0 then
                    attachedEntity = netEntity
                    speaker.config.attachedEntity = netEntity
                end
            end

            if attachedEntity then
                if not DoesEntityExist(attachedEntity) then
                    -- Entity is gone (disconnected/despawned): bucket the
                    -- speaker for delayed cleanup instead of removing it
                    -- immediately, and drop its audio source once nothing
                    -- else references it.
                    local bucket = staleEntitySpeakers[attachedEntity]
                    if not bucket then
                        bucket = {}
                        staleEntitySpeakers[attachedEntity] = bucket
                    end
                    table.insert(bucket, speakerId)

                    local orphanedAudioSourceId = speaker.audioSourceId
                    RemoveSpeaker(speakerId)

                    local stillReferenced = false
                    for _, otherSpeaker in pairs(speakers) do
                        if otherSpeaker.audioSourceId == orphanedAudioSourceId then
                            stillReferenced = true
                            break
                        end
                    end
                    if not stillReferenced then
                        RemoveAudioSource(orphanedAudioSourceId)
                    end
                else
                    local alreadySeen = entitySpeakersThisTick[attachedEntity]
                    if alreadySeen then
                        if IsEntityVehicle(attachedEntity) then
                            -- Vehicles only track one active speaker at a time;
                            -- detach any extra speaker seen this tick.
                            speaker.config.attachedEntity = nil
                            speaker.config.attachedOffset = nil
                        else
                            table.insert(alreadySeen, speakerId)
                        end
                    else
                        if IsEntityVehicle(attachedEntity) then
                            entitySpeakersThisTick[attachedEntity] = speakerId
                            UpdateVehicleSpeakerAudio(speakerId)
                        else
                            entitySpeakersThisTick[attachedEntity] = { speakerId }
                        end
                    end

                    UpdateAttachedSpeakerPosition(speakerId, speaker)
                end
            end
        end

        local now = GetGameTimer()
        for entity, bucket in pairs(staleEntitySpeakers) do
            if not bucket.timestamp then
                bucket.timestamp = now
            elseif now - bucket.timestamp > 30000 then
                staleEntitySpeakers[entity] = nil
            end
        end
    end
end)

function UpdateAttachedSpeakerPosition(speakerId, speaker)
    local attachedEntity = speaker.config.attachedEntity
    if not (attachedEntity and DoesEntityExist(attachedEntity)) then
        return false
    end

    local position = GetEntityCoords(attachedEntity)
    local offset = speaker.config.attachedOffset

    if offset and not (offset.x == 0 and offset.y == 0 and offset.z == 0) then
        local rotation = GetEntityRotation(attachedEntity, 2)
        local matrix = RotationToMatrix(rotation)
        local rotatedOffset = ApplyRotationToOffset(matrix, offset)
        position = vector3(position.x + rotatedOffset.x, position.y + rotatedOffset.y, position.z + rotatedOffset.z)
    end

    if HasPositionChanged(position, speaker.position) then
        UpdateSpeakerPosition(speakerId, position)
        return true
    end

    return false
end

-- Audio event callbacks -----------------------------------------------------

local function registerAudioCallback(audioSourceId, eventName, callback, isServer)
    if not audioSources[audioSourceId] then
        if Config and Config.Debug then
            print("Warning: Registering callback for non-existent audio source: " .. audioSourceId)
        end
    end

    if not audioCallbacks[eventName] then
        print("Error: Invalid audio event type: " .. eventName)
        return false
    end

    if not audioCallbacks[eventName][audioSourceId] then
        audioCallbacks[eventName][audioSourceId] = {}
    end

    table.insert(audioCallbacks[eventName][audioSourceId], { callback = callback, isServer = isServer })
    return true
end
RegisterAudioCallback = registerAudioCallback

RegisterNetEvent("ts-sounds:client:ChangeOwner", function(audioSourceId, newOwner)
    local source = audioSources[audioSourceId]
    if not source then
        return
    end
    source.audioOwner = newOwner
end)

local function triggerAudioCallbacks(audioSourceId, eventName, ...)
    local handlers = audioCallbacks[eventName] and audioCallbacks[eventName][audioSourceId]
    if not handlers then
        return
    end

    for _, entry in ipairs(handlers) do
        if entry.isServer then
            local owner = audioSources[audioSourceId] and audioSources[audioSourceId].audioOwner
            if owner == GetPlayerServerId(PlayerId()) then
                TriggerServerEvent("ts-sounds:server:AudioCallback", audioSourceId, eventName, ...)
            end
        else
            entry.callback(...)
        end
    end
end
TriggerAudioCallbacks = triggerAudioCallbacks

-- NUI-driven async round trips (fetching page titles / current playback time) -

local pendingFetchDataCallbacks = {}   -- url -> { callback, ... }
local pendingFetchDataTimeouts = {}    -- url -> true while a timeout is armed
local pendingCurrentTimePromises = {}  -- audioSourceId -> promise

local function fetchData(url, callback)
    if type(url) ~= 'string' or url == '' or type(callback) ~= 'function' then
        return false
    end

    pendingFetchDataCallbacks[url] = pendingFetchDataCallbacks[url] or {}
    table.insert(pendingFetchDataCallbacks[url], callback)

    SendNUIMessage({ type = "fetchData", url = url })

    if not pendingFetchDataTimeouts[url] then
        pendingFetchDataTimeouts[url] = true
        SetTimeout(12000, function()
            local callbacks = pendingFetchDataCallbacks[url]
            pendingFetchDataCallbacks[url] = nil
            pendingFetchDataTimeouts[url] = nil
            if not callbacks then return end
            for _, waitingCallback in ipairs(callbacks) do
                waitingCallback({ url = url, status = "error", error = "YouTube metadata request timed out" })
            end
        end)
    end
    return true
end
FetchData = fetchData
exports("FetchData", FetchData)

local function getCurrentTime(audioSourceId)
    if not audioSources[audioSourceId] then
        return false
    end

    local timePromise = promise.new()
    pendingCurrentTimePromises[audioSourceId] = timePromise

    SetTimeout(1500, function()
        if pendingCurrentTimePromises[audioSourceId] == timePromise then
            pendingCurrentTimePromises[audioSourceId] = nil
            timePromise:resolve(0)
        end
    end)

    SendNUIMessage({ type = "getCurrentTime", audioSourceId = audioSourceId })

    Citizen.Await(timePromise)
    return math.floor(timePromise.value or 0)
end
GetCurrentTime = getCurrentTime
exports("GetCurrentTime", GetCurrentTime)

RegisterNUICallback("currentTime", function(data, cb)
    local audioSourceId = data.audioSourceId
    local currentTime = data.currentTime

    local pending = pendingCurrentTimePromises[audioSourceId]
    if pending then
        pending:resolve(currentTime)
        pendingCurrentTimePromises[audioSourceId] = nil
    end

    cb("ok")
end)

RegisterNUICallback("receiveTitle", function(data, cb)
    local callbacks = pendingFetchDataCallbacks[data.url]
    if callbacks then
        pendingFetchDataCallbacks[data.url] = nil
        pendingFetchDataTimeouts[data.url] = nil
        for _, pending in ipairs(callbacks) do
            pending(data)
        end
    end
    cb("ok")
end)

RegisterNUICallback("audioEvent", function(data, cb)
    cb({})

    local eventType = data.eventType
    local audioSourceId = data.audioSourceId
    local eventData = data.data

    if not audioSourceId or not eventType then
        return
    end

    local eventToCallbackName = {
        playbackStarted = "onPlaybackStarted",
        playbackPaused = "onPlaybackPaused",
        playbackResumed = "onPlaybackResumed",
        ready = "onAudioReady",
        error = "onAudioError",
        ended = "onAudioEnded",
    }

    local callbackName = eventToCallbackName[eventType]
    if not callbackName then
        return
    end

    if eventType == "playbackStarted" then
        local source = audioSources[audioSourceId]
        if source then
            source.playing = true
        end
    elseif eventType == "playbackPaused" then
        local source = audioSources[audioSourceId]
        if source then
            source.playing = false
        end
    elseif eventType == "playbackResumed" then
        local source = audioSources[audioSourceId]
        if source then
            source.playing = true
        end
    elseif eventType == "ended" then
        if audioSources[audioSourceId] then
            RemoveAudioSource(audioSourceId)
            audioSources[audioSourceId] = nil
        end
    end

    TriggerAudioCallbacks(audioSourceId, callbackName, eventData)
end)

exports("RegisterAudioCallback", RegisterAudioCallback)
