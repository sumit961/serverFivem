-- cm-carplay / server/sound.lua
--
-- Self-contained positional-audio relay used to play CarPlay music through a
-- vehicle speaker. The "ts-sounds:*" event names are internal to this
-- resource (naming carried over from the original author) -- NOT a real
-- external dependency.
--
-- The server owns no audio itself. It just tracks which sources/speakers
-- exist, relays play/pause/seek/volume commands to every client, and assigns
-- each source an "owner" (the client responsible for reporting playback
-- progress back via ts-sounds:server:AudioCallback) -- reassigning ownership
-- to the lowest-ping player whenever the current owner disconnects.

local audioSources = {}   -- tostring(sourceId) -> { url, options, playerId }
local audioCallbacks = {} -- tostring(sourceId) -> { [callbackName] = fn }

local CALLBACK_NAMES = {
    'onPlaybackStarted', 'onPlaybackPaused', 'onPlaybackResumed',
    'onAudioReady', 'onAudioError', 'onAudioEnded',
}

-- Source ID generation & ownership
-- ---------------------------------------------------------------------------

function createSourceID()
    local id = math.random(100000, 999999)
    while audioSources[tostring(id)] do
        id = math.random(100000, 999999)
    end
    return id
end

-- Picks the connected player with the lowest ping to "own" an audio source.
function AssignOwner()
    local lowestPing = math.huge
    local chosen = nil
    for _, playerId in ipairs(GetPlayers()) do
        local ping = GetPlayerPing(playerId)
        if lowestPing > ping then
            lowestPing = ping
            chosen = playerId
        end
    end
    return tonumber(chosen)
end

-- Audio source lifecycle
-- ---------------------------------------------------------------------------

function AddAudioSource(sourceId, url, options, callbacks)
    if not sourceId then
        sourceId = createSourceID()
    end
    if not url then
        return false
    end

    -- Only the callback names the caller actually provided are flagged to
    -- the client; every name still gets a no-op fallback registered here so
    -- ts-sounds:server:AudioCallback can always find a function to invoke.
    local providedCallbacks = {}
    if callbacks then
        local key = tostring(sourceId)
        for _, name in ipairs(CALLBACK_NAMES) do
            audioCallbacks[key] = audioCallbacks[key] or {}
            audioCallbacks[key][name] = callbacks[name] or function() end
            if callbacks[name] then
                providedCallbacks[name] = true
            end
        end
    end

    local owner = AssignOwner()
    audioSources[tostring(sourceId)] = { url = url, options = options, playerId = owner }

    TriggerClientEvent('ts-sounds:client:AddSource', -1, sourceId, url, options, providedCallbacks, true, owner)
end

function RemoveAudioSource(sourceId)
    local key = tostring(sourceId)
    if audioSources[key] then
        TriggerClientEvent('ts-sounds:client:RemoveSource', -1, sourceId)

        -- If the owner is already gone or a client fails to acknowledge the
        -- removal, do not leave server callbacks and source metadata forever.
        -- Natural playback still removes the entry immediately through the
        -- normal onAudioEnded callback below.
        SetTimeout(30000, function()
            if audioSources[key] then
                audioSources[key] = nil
                audioCallbacks[key] = nil
            end
        end)
    end
end

function AddSpeaker(speakerName, coords, options, sourceId)
    TriggerClientEvent('ts-sounds:client:AddSpeaker', -1, speakerName, coords, options, sourceId)
end

function SetLoop(sourceId, loop)
    TriggerClientEvent('ts-sounds:client:SetAudioLoop', -1, sourceId, loop)
end

function PlayAudioSource(sourceId)
    if audioSources[tostring(sourceId)] then
        TriggerClientEvent('ts-sounds:client:PlayAudio', -1, sourceId)
    end
end

function PauseAudioSource(sourceId)
    if audioSources[tostring(sourceId)] then
        TriggerClientEvent('ts-sounds:client:PauseAudio', -1, sourceId)
    end
end

function ResumeAudioSource(sourceId)
    if audioSources[tostring(sourceId)] then
        TriggerClientEvent('ts-sounds:client:ResumeAudio', -1, sourceId)
    end
end

function SeekAudioSource(sourceId, position)
    if audioSources[tostring(sourceId)] then
        TriggerClientEvent('ts-sounds:client:SeekAudio', -1, sourceId, position)
    end
end

function SetSpeakerVolume(speakerName, volumeMultiplier)
    TriggerClientEvent('ts-sounds:client:SetSpeakerVolume', -1, speakerName, volumeMultiplier)
end

-- Public exports (other resources may drive the relay directly)
-- ---------------------------------------------------------------------------

exports('SetSpeakerVolume', SetSpeakerVolume)
exports('AddAudioSource', AddAudioSource)
exports('RemoveAudioSource', RemoveAudioSource)
exports('AddSpeaker', AddSpeaker)
exports('PlayAudioSource', PlayAudioSource)
exports('PauseAudioSource', PauseAudioSource)
exports('ResumeAudioSource', ResumeAudioSource)
exports('SeekAudioSource', SeekAudioSource)
exports('SetLoop', SetLoop)

-- Client -> server callback relay
-- ---------------------------------------------------------------------------

-- The client fires this once it has actually removed a source client-side;
-- only then do we run the "onAudioEnded" callback and forget the source.
RegisterNetEvent('ts-sounds:server:RemoveAudioSource', function(sourceId)
    if audioSources[tostring(sourceId)] then
        TriggerEvent('ts-sounds:server:AudioCallback', sourceId, 'onAudioEnded')
    end
end)

RegisterNetEvent('ts-sounds:server:AudioCallback', function(sourceId, callbackName, ...)
    local key = tostring(sourceId)
    local callbacks = audioCallbacks[key]
    if not callbacks then return end

    local callback = callbacks[callbackName]
    if not callback then return end

    if callbackName == 'onAudioEnded' then
        audioSources[key] = nil
        audioCallbacks[key] = nil
    end

    callback(...)
end)

-- Ownership handoff on disconnect
-- ---------------------------------------------------------------------------

AddEventHandler('playerDropped', function()
    local src = source
    for sourceId, sourceData in pairs(audioSources) do
        if sourceData.playerId == src then
            sourceData.playerId = AssignOwner()
            TriggerClientEvent('ts-sounds:client:ChangeOwner', -1, sourceId, sourceData.playerId)
        end
    end
end)
