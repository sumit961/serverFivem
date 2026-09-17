-- cm-carplay / server/main.lua
--
-- Server-side logic for the CarPlay in-vehicle infotainment system:
-- per-vehicle CarPlay/tuner-chip/modifications
-- persistence (all keyed by plate via Resource KVP), and the music playback
-- relay built on top of server/sound.lua.

local resourceName = GetCurrentResourceName()
local basePath = GetResourcePath(resourceName)

-- Cached YouTube audio HTTP delivery
-- ---------------------------------------------------------------------------

os.execute('mkdir "' .. basePath .. '/cache/youtube" 2>nul')

-- Serves cached YouTube-resolved audio files back
-- to the NUI (server/server.js's resolveYoutubeAudio downloads YouTube
-- audio-only streams to cache/youtube/ once per video id so they can be
-- played as a plain local file -- see its file banner for why: routing
-- through a cross-origin YouTube iframe can never reach Web Audio's
-- PannerNode/BiquadFilter, so real positional audio requires a real local
-- file).
local function getRequestHeader(request, name)
    local headers = request and request.headers
    if type(headers) ~= 'table' then return nil end
    local wanted = name:lower()
    for key, value in pairs(headers) do
        if type(key) == 'string' and key:lower() == wanted then
            return value
        end
    end
    return nil
end

local function serveFile(response, diskPath, contentType, request)
    local file = io.open(diskPath, 'rb')
    if not file then
        response.writeHead(404)
        response.send('')
        return
    end

    local fileSize = file:seek('end') or 0
    local range = getRequestHeader(request, 'range')
    local startByte, endByte = 0, fileSize - 1
    local statusCode = 200

    if type(range) == 'string' then
        local requestedStart, requestedEnd = range:match('bytes=(%d*)%-(%d*)')
        requestedStart, requestedEnd = tonumber(requestedStart), tonumber(requestedEnd)
        if range:match('^bytes=') and (requestedStart or requestedEnd) then
            if requestedStart then
                startByte = requestedStart
                endByte = requestedEnd or endByte
            else
                local suffixLength = requestedEnd or 0
                startByte = math.max(0, fileSize - suffixLength)
            end
            endByte = math.min(endByte, fileSize - 1)
            if startByte < 0 or startByte > endByte or startByte >= fileSize then
                file:close()
                response.writeHead(416, { ['Content-Range'] = 'bytes */' .. tostring(fileSize) })
                response.send('')
                return
            end
            statusCode = 206
        end
    end

    local length = math.max(0, endByte - startByte + 1)
    file:seek('set', startByte)
    response.writeHead(statusCode, {
        ['Content-Type'] = contentType,
        ['Content-Length'] = tostring(length),
        ['Accept-Ranges'] = 'bytes',
        ['Access-Control-Allow-Origin'] = '*',
        ['Cache-Control'] = 'public, max-age=86400',
        ['Content-Range'] = statusCode == 206 and ('bytes ' .. startByte .. '-' .. endByte .. '/' .. fileSize) or nil,
    })

    -- FiveM builds differ: newer builds expose response.write for chunked
    -- delivery, while older builds only expose response.send. Use chunks when
    -- available so a large audio file is never copied fully into Lua memory.
    if response.write then
        local remaining = length
        while remaining > 0 do
            local chunk = file:read(math.min(256 * 1024, remaining))
            if not chunk or #chunk == 0 then break end
            response.write(chunk)
            remaining = remaining - #chunk
        end
        file:close()
        response.send('')
    else
        local content = file:read(length) or ''
        file:close()
        response.send(content)
    end
end

SetHttpHandler(function(request, response)
    if request.method ~= 'GET' then
        response.send('')
        return
    end

    local subPath, contentType = nil, nil
    local youtubeFile = request.path:match('^/cache/youtube/([%w_-]+%.v2%.m4a)$')
    local youtubeWebmFile = request.path:match('^/cache/youtube/([%w_-]+%.v2%.webm)$')

    local diskPath
    if youtubeFile then
        subPath, contentType = youtubeFile, 'audio/mp4'
        diskPath = basePath .. '/cache/youtube/' .. subPath
    elseif youtubeWebmFile then
        subPath, contentType = youtubeWebmFile, 'audio/webm'
        diskPath = basePath .. '/cache/youtube/' .. subPath
    else
        response.send('')
        return
    end

    -- Reject path traversal / directory separators before touching disk.
    if subPath:find('%.%.') or subPath:find('/') or subPath:find('\\') then
        response.send('')
        return
    end

    serveFile(response, diskPath, contentType, request)
end)

-- Bridges client/main.lua's playMusic NUI callback (client-side) to
-- server/server.js's resolveYoutubeAudio Node export (server-side scripts
-- can't be called directly from client Lua) -- downloads/caches the video's
-- audio-only stream once, then tells the client which local cache/youtube/
-- filename to build a playable URL from.
RegisterNetEvent('prism-carplay:server:resolveYoutubeAudio', function(url, videoId)
    local src = source
    if type(url) ~= 'string' or type(videoId) ~= 'string'
        or not videoId:match('^[%w_%-]+$') or #videoId ~= 11
        or not url:lower():find('youtube.com', 1, true) and not url:lower():find('youtu.be', 1, true) then
        TriggerClientEvent('prism-carplay:client:receiveYoutubeAudioResolved', src, videoId, { success = false, error = 'Invalid request' })
        return
    end

    local ok, err = pcall(function()
        exports[resourceName]:resolveYoutubeAudio(url, videoId, function(result)
            TriggerClientEvent('prism-carplay:client:receiveYoutubeAudioResolved', src, videoId, result)
        end)
    end)

    if not ok then
        print('^1[CarPlay]^7 resolveYoutubeAudio export call failed: ' .. tostring(err))
        TriggerClientEvent('prism-carplay:client:receiveYoutubeAudioResolved', src, videoId, { success = false, error = 'Server error' })
    end
end)

-- Vehicle-ownership security check & debounce
-- ---------------------------------------------------------------------------

-- Every handler below that trusts a client-supplied plate re-validates it
-- against the vehicle the triggering player is actually sitting in, so a
-- player can't read/write CarPlay data for a vehicle they're not inside.
-- Also returns the vehicle's model hash, re-derived server-side rather than
-- trusted from the client, for the CarPlay-by-model check below.
local function getPlateOfVehiclePlayerIsIn(src, vehicleNetId)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end

    local vehicle = 0
    if tonumber(vehicleNetId) and tonumber(vehicleNetId) > 0 then
        local ok, networkVehicle = pcall(NetworkGetEntityFromNetworkId, tonumber(vehicleNetId))
        if ok and networkVehicle and networkVehicle ~= 0 then
            vehicle = networkVehicle
        end
    end
    if vehicle == 0 then
        vehicle = GetVehiclePedIsIn(ped, false)
    end
    if not vehicle or vehicle == 0 then return nil end
    if GetVehiclePedIsIn(ped, false) ~= vehicle then return nil end

    local plate = GetVehicleNumberPlateText(vehicle):gsub('%s+', ''):upper()
    -- Spawned/test vehicles can legitimately have no plate text. Do not let
    -- every such vehicle share the empty-string music/KVP key; use its
    -- network identity as a stable session key instead.
    if plate == '' then
        local ok, netId = pcall(NetworkGetNetworkIdFromEntity, vehicle)
        if ok and type(netId) == 'number' and netId > 0 then
            plate = ('__net_%s'):format(netId)
        end
    end
    return plate, GetEntityModel(vehicle), vehicle
end

local function playerIsInVehicleWithPlate(src, plate)
    if not src or type(plate) ~= 'string' then return false end
    local currentPlate = getPlateOfVehiclePlayerIsIn(src)
    if not currentPlate then return false end
    return currentPlate == plate:gsub('%s+', ''):upper()
end

-- Collapses duplicate rapid-fire triggers (e.g. a double click) into one
-- call within a 1-second window, keyed per player+action.
local lastActionAt = {}

local function debounce(id, action)
    local now = os.time()
    local key = id .. '_' .. action
    if lastActionAt[key] and (now - lastActionAt[key]) < 1 then
        return true
    end
    lastActionAt[key] = now
    return false
end

CreateThread(function()
    while true do
        Wait(60000)
        local now = os.time()
        for key, timestamp in pairs(lastActionAt) do
            if (now - timestamp) > 60 then
                lastActionAt[key] = nil
            end
        end
    end
end)

-- Home-screen map bounds
-- ---------------------------------------------------------------------------
-- cm-admin owns both the stitched map image and its calibrated world bounds.
-- CarPlay receives only those four public numeric bounds; admin/player data and
-- privileged map actions never cross this integration.
local DEFAULT_ADMIN_MAP_BOUNDS = { minX = -3900, maxX = 4619, minY = -4764, maxY = 7510 }

local function normalizeAdminMapBounds(bounds)
    if type(bounds) ~= 'table' then return nil end
    local minX, maxX = tonumber(bounds.minX), tonumber(bounds.maxX)
    local minY, maxY = tonumber(bounds.minY), tonumber(bounds.maxY)
    if not minX or not maxX or not minY or not maxY then return nil end
    if maxX <= minX or maxY <= minY then return nil end
    if math.abs(minX) > 20000 or math.abs(maxX) > 20000
        or math.abs(minY) > 20000 or math.abs(maxY) > 20000 then return nil end
    return { minX = minX, maxX = maxX, minY = minY, maxY = maxY }
end

local function getAdminMapBounds()
    if GetResourceState('cm-admin') == 'started' then
        local ok, bounds = pcall(function()
            return exports['cm-admin']:GetMapBounds()
        end)
        if ok then
            bounds = normalizeAdminMapBounds(bounds)
            if bounds then return bounds end
        end
    end
    return DEFAULT_ADMIN_MAP_BOUNDS
end

RegisterNetEvent('prism-carplay:server:getMapBounds', function()
    local src = source
    if debounce(src, 'getMapBounds') then return end
    TriggerClientEvent('prism-carplay:client:receiveMapBounds', src, getAdminMapBounds())
end)

-- KVP keys are built from the plate with whitespace stripped but NOT
-- uppercased -- existing saved data relies on this exact casing behavior.
local function plateKvpKey(prefix, plate)
    return prefix .. plate:gsub('%s+', '')
end

-- CarPlay install persistence
-- ---------------------------------------------------------------------------

local function saveCarplayInstalledKvp(plate, installed)
    if not plate then return end
    SetResourceKvp(plateKvpKey('carplay_', plate), json.encode({ installed = installed == true }))
end

-- modelHash is optional: when known (re-derived server-side from the
-- vehicle the player is actually in -- never trusted from the client), a
-- model flagged for CarPlay in rn-vehicleshop's Manage Vehicles is always
-- available on ANY vehicle of that model -- test drives, showroom previews,
-- trainer/admin spawns -- not only vehicles with a cm_owned_vehicles row.
-- Falls back to the per-vehicle item-install flag either way.
local function isCarplayEnabledForPlate(plate, modelHash)
    if not plate then return false, 'invalid_plate' end
    local normalizedPlate = plate:gsub('%s+', '')
    if Config.Debug then
        print(('^3[CarPlay debug]^7 checking plate "%s" modelHash=%s | rn-vehicleshop=%s'):format(
            normalizedPlate, tostring(modelHash), GetResourceState('rn-vehicleshop')))
    end

    if modelHash and GetResourceState('rn-vehicleshop') == 'started' then
        local ok, flagged = pcall(function()
            return exports['rn-vehicleshop']:IsCarplayModelHash(modelHash)
        end)
        if Config.Debug then
            print(('^3[CarPlay debug]^7 IsCarplayModelHash(%s) = %s (ok=%s)'):format(tostring(modelHash), tostring(flagged), tostring(ok)))
        end
        if ok and flagged == true then return true, 'catalog_model' end
    end

    local raw = GetResourceKvpString('carplay_' .. normalizedPlate)
    if raw then
        local decoded = json.decode(raw)
        if decoded and decoded.installed == true then return true, 'installed_item' end
    end
    return false, 'not_installed'
end

RegisterNetEvent('prism-carplay:server:getCarplayInstalled', function(plate)
    local src = source
    if not (plate and type(plate) == 'string') then return end

    -- This is a read-only eligibility check. Derive the current vehicle from
    -- the player's server-side ped and evaluate its MODEL. Manage Vehicles is
    -- model-wide, so differences in client/server plate formatting must not
    -- reject the request. The authoritative plate is used only for the
    -- optional per-vehicle item-install fallback.
    local actualPlate, modelHash = getPlateOfVehiclePlayerIsIn(src)
    if not actualPlate then
        TriggerClientEvent('prism-carplay:client:receiveCarplayInstalled', src, plate, false, 'vehicle_not_found')
        return
    end

    local installed, reason = isCarplayEnabledForPlate(actualPlate, modelHash)
    TriggerClientEvent('prism-carplay:client:receiveCarplayInstalled', src, plate, installed, reason)
end)

RegisterNetEvent('prism-carplay:server:saveCarplayInstalled', function(plate, installed)
    local src = source
    if not plate then return end

    local actualPlate, modelHash = getPlateOfVehiclePlayerIsIn(src)
    if not actualPlate or actualPlate ~= plate:gsub('%s+', ''):upper() then
        print('^1[Prism-CarPlay]^7 Security: Player ' .. src .. ' attempted to modify carplay data for vehicle they are not in')
        return
    end

    local wasEnabled = isCarplayEnabledForPlate(plate, modelHash)
    saveCarplayInstalledKvp(plate, installed)

    if wasEnabled and not installed then
        RemoveCarplayItem(src, plate)
    end

    TriggerClientEvent('prism-carplay:client:carplayInstalledUpdated', -1, plate, installed == true)
end)

-- Tuner chip persistence
-- ---------------------------------------------------------------------------

local function saveTunerChipDataKvp(plate, data)
    if not plate then return end
    SetResourceKvp(plateKvpKey('tunerchip_', plate), json.encode(data))
end

local function getTunerChipDataKvp(plate)
    if not plate then return nil end
    local raw = GetResourceKvpString(plateKvpKey('tunerchip_', plate))
    if raw then return json.decode(raw) end
    return nil
end

local function clampTunerPercent(value)
    if type(value) ~= 'number' then return 0 end
    return math.max(0, math.min(100, value))
end

-- Clamps every tuner stat to Config.TunerChip's 0-100% range regardless of
-- what the client sends.
local function sanitizeTunerChipData(data)
    if type(data) ~= 'table' then return nil end
    return {
        installed = data.installed == true,
        boostPower = clampTunerPercent(data.boostPower),
        gearChange = clampTunerPercent(data.gearChange),
        acceleration = clampTunerPercent(data.acceleration),
        brakes = clampTunerPercent(data.brakes),
    }
end

RegisterNetEvent('prism-carplay:server:getTunerChipData', function(plate)
    local src = source
    if not (plate and type(plate) == 'string') then return end
    if not playerIsInVehicleWithPlate(src, plate) then return end

    TriggerClientEvent('prism-carplay:client:receiveTunerChipData', src, plate, getTunerChipDataKvp(plate))
end)

RegisterNetEvent('prism-carplay:server:saveTunerChipData', function(plate, data)
    local src = source
    if not plate or not data then return end

    if not playerIsInVehicleWithPlate(src, plate) then
        print('^1[Prism-CarPlay]^7 Security: Player ' .. src .. ' attempted to modify tuner chip data for vehicle they are not in')
        return
    end

    data = sanitizeTunerChipData(data)
    if not data then return end

    local existing = getTunerChipDataKvp(plate)
    if existing and existing.installed and not data.installed then
        RemoveTunerChip(src, plate)
    end

    saveTunerChipDataKvp(plate, data)
    TriggerClientEvent('prism-carplay:client:tunerChipDataUpdated', -1, plate, data)
end)

-- Vehicle modifications persistence (drive mode + neon)
-- ---------------------------------------------------------------------------

local function saveModificationsDataKvp(plate, data)
    if not plate then return end
    SetResourceKvp(plateKvpKey('modifications_', plate), json.encode(data))
end

local function getModificationsDataKvp(plate)
    if not plate then return nil end
    local raw = GetResourceKvpString(plateKvpKey('modifications_', plate))
    if raw then return json.decode(raw) end
    return nil
end

RegisterNetEvent('prism-carplay:server:getModificationsData', function(plate)
    local src = source
    if not (plate and type(plate) == 'string') then return end
    if not playerIsInVehicleWithPlate(src, plate) then return end

    TriggerClientEvent('prism-carplay:client:receiveModificationsData', src, plate, getModificationsDataKvp(plate))
end)

RegisterNetEvent('prism-carplay:server:saveModificationsData', function(plate, data)
    local src = source
    if not plate or not data then return end

    if not playerIsInVehicleWithPlate(src, plate) then
        print('^1[Prism-CarPlay]^7 Security: Player ' .. src .. ' attempted to modify vehicle data they are not in')
        return
    end

    if type(data) ~= 'table' then return end

    saveModificationsDataKvp(plate, data)
    TriggerClientEvent('prism-carplay:client:modificationsDataUpdated', -1, plate, data)
end)

-- Music playback relay
-- ---------------------------------------------------------------------------

-- session vehicle key (__net_<id>) -> playback state. Music is attached to
-- the live entity and must not be keyed or authorized by its number plate.
local musicState = {}
local musicGeneration = {}

local function getPlayerMusicVehicle(src)
    local _, _, vehicle = getPlateOfVehiclePlayerIsIn(src)
    if not vehicle or vehicle == 0 then return nil end

    local ok, vehicleNetId = pcall(NetworkGetNetworkIdFromEntity, vehicle)
    if not ok or type(vehicleNetId) ~= 'number' or vehicleNetId <= 0 then return nil end
    return ('__net_%s'):format(vehicleNetId), vehicleNetId
end

local function playerIsInMusicVehicle(src, musicKey)
    local state = musicState[musicKey]
    if not state then return false end
    local currentKey, currentNetId = getPlayerMusicVehicle(src)
    return currentKey == musicKey and currentNetId == state.vehicleNetId
end

local function isCurrentMusicState(plate, generation)
    return musicState[plate] and musicState[plate].generation == generation
end

local function sanitizeString(value, maxLength)
    if type(value) ~= 'string' then return nil end
    return value:sub(1, maxLength)
end

local function isFiniteNumber(value)
    return type(value) == 'number' and value == value and value < math.huge and value > -math.huge
end

local function isSafeMusicFilePath(value)
    return type(value) == 'string' and #value > 0 and #value <= 200
        and value:match('^[%w_%-]+%.[%w]+$') ~= nil
end

local function isConfiguredMusicFilePath(value)
    if not isSafeMusicFilePath(value) then return false end
    for _, entry in ipairs(Config.MusicLibrary or {}) do
        if type(entry) == 'table' and entry.filePath == value then
            return true
        end
    end
    return false
end

local function isAllowedMusicUrl(value)
    if type(value) ~= 'string' or #value > 500 or value:find('%.%.') then return false end
    local resourcePrefix = 'https://cfx%-nui%-' .. resourceName:gsub('%-', '%%-')
    local soundFile = value:match('^' .. resourcePrefix .. '/web/dist/sounds/([%w_%-]+%.[%w]+)$')
    if soundFile and isConfiguredMusicFilePath(soundFile) then return true end
    if value:match('^' .. resourcePrefix .. '/cache/youtube/[%w_%-]+%.v2%.(?:m4a|webm)$') then return true end
    if value:lower():match('^https://youtube%.com/')
        or value:lower():match('^http://youtube%.com/')
        or value:lower():match('^https://www%.youtube%.com/')
        or value:lower():match('^http://www%.youtube%.com/')
        or value:lower():match('^https://youtu%.be/')
        or value:lower():match('^http://youtu%.be/') then return true end
    return false
end

local function sanitizeMusicTrackData(track)
    if type(track) ~= 'table' then return nil end
    return {
        id = sanitizeString(track.id, 100),
        title = sanitizeString(track.title, 200) or 'Unknown',
        artist = sanitizeString(track.artist, 200) or 'Unknown',
        filePath = isConfiguredMusicFilePath(track.filePath) and track.filePath or nil,
        url = isAllowedMusicUrl(track.url) and track.url or nil,
        thumbnail = sanitizeString(track.thumbnail, 500),
        isYouTube = track.isYouTube == true,
        videoId = sanitizeString(track.videoId, 20),
        duration = isFiniteNumber(track.duration)
            and track.duration >= 0 and track.duration <= 86400 and track.duration or nil,
    }
end

RegisterNetEvent('prism-carplay:server:playMusic', function(plate, track, vehicleNetId)
    local src = source
    if type(track) ~= 'table' then return end

    -- Ignore both client identity hints. The server derives the occupied
    -- entity, session key and speaker net ID itself.
    local actualMusicKey, actualVehicleNetId = getPlayerMusicVehicle(src)
    if not actualMusicKey then
        print('^1[Prism-CarPlay]^7 Security: Player ' .. src .. ' attempted to play music on vehicle they are not in')
        return
    end
    plate = actualMusicKey
    vehicleNetId = actualVehicleNetId

    if debounce(src, 'playMusic') then return end
    track = sanitizeMusicTrackData(track)
    if not (track and (track.url or track.filePath)) then return end

    musicGeneration[plate] = (musicGeneration[plate] or 0) + 1
    local generation = musicGeneration[plate]
    local audioSourceName = plate .. 'carplay_' .. tostring(generation)
    local speakerName = plate .. 'carplay_speaker_' .. tostring(generation)

    if musicState[plate] then
        RemoveAudioSource(musicState[plate].audioSourceId)
        TriggerClientEvent('prism-carplay:client:musicStopped', -1, plate)
    end

    musicState[plate] = {
        currentSong = track,
        isPlaying = false,
        volume = 100,
        vehicleNetId = vehicleNetId,
        startedBy = src,
        generation = generation,
        audioSourceId = audioSourceName,
        speakerId = speakerName,
    }

    AddAudioSource(audioSourceName, track.url or track.filePath, { loop = false, volume = 1.0 }, {
        onAudioReady = function(info)
            if info and info.duration and isCurrentMusicState(plate, generation) then
                musicState[plate].actualDuration = info.duration
            end

            if not isCurrentMusicState(plate, generation) then return end

            AddSpeaker(speakerName, vec3(0, 0, 0), {
                maxDistance = 25.0,
                rolloffFactor = 0.8,
                volumeMultiplier = musicState[plate].volume / 100,
                netID = vehicleNetId,
                -- Starts true: playMusic already requires the triggering
                -- player to be inside this exact vehicle, so defaulting to
                -- "inside" avoids a quiet/attenuated burst of audio for
                -- them right as playback begins, before client/sound.lua's
                -- 100ms occupancy thread gets a chance to confirm it. Any
                -- other nearby client gets corrected to false on their own
                -- next tick either way.
                pannerDisabled = true,
            }, audioSourceName)

            PlayAudioSource(audioSourceName)
        end,

        onPlaybackStarted = function()
            local state = musicState[plate]
            if state and state.generation == generation then
                state.isPlaying = true
                local duration = track.duration
                if not (type(duration) == 'number' and duration > 0) then
                    duration = state.actualDuration
                end
                local songInfo = {
                    id = track.id,
                    title = track.title,
                    artist = track.artist,
                    filePath = track.filePath,
                    url = track.url,
                    thumbnail = track.thumbnail,
                    isYouTube = track.isYouTube,
                    videoId = track.videoId,
                    duration = duration,
                }
                state.currentSong = songInfo
                TriggerClientEvent('prism-carplay:client:musicStarted', -1, plate, songInfo, audioSourceName)
            end
        end,

        onPlaybackPaused = function()
            if isCurrentMusicState(plate, generation) then
                musicState[plate].isPlaying = false
                TriggerClientEvent('prism-carplay:client:playbackStatus', -1, plate, false)
            end
        end,

        onPlaybackResumed = function()
            if isCurrentMusicState(plate, generation) then
                musicState[plate].isPlaying = true
                TriggerClientEvent('prism-carplay:client:playbackStatus', -1, plate, true)
            end
        end,

        onAudioError = function(info)
            if not isCurrentMusicState(plate, generation) then return end
            local message = type(info) == 'table' and info.message or 'The audio source could not be played'
            print('^1[Prism-CarPlay]^7 Audio error for ' .. plate .. ': ' .. tostring(message))
            musicState[plate] = nil
            RemoveAudioSource(audioSourceName)
            TriggerClientEvent('prism-carplay:client:musicError', -1, plate, tostring(message))
        end,

        onAudioEnded = function()
            local state = musicState[plate]
            if state and state.generation == generation then
                musicState[plate] = nil
                TriggerClientEvent('prism-carplay:client:trackEnded', -1, plate)
            end
        end,
    })
end)

RegisterNetEvent('prism-carplay:server:toggleMusic', function(plate)
    local src = source
    if not (plate and musicState[plate]) then return end
    if not playerIsInMusicVehicle(src, plate) then return end

    local audioSourceName = musicState[plate].audioSourceId
    if musicState[plate].isPlaying then
        PauseAudioSource(audioSourceName)
    else
        ResumeAudioSource(audioSourceName)
    end
end)

RegisterNetEvent('prism-carplay:server:stopMusic', function(plate)
    local src = source
    if not plate then return end
    if not playerIsInMusicVehicle(src, plate) then return end
    if debounce(src, 'stopMusic') then return end

    local state = musicState[plate]
    if not state then return end
    RemoveAudioSource(state.audioSourceId)
    musicState[plate] = nil
    TriggerClientEvent('prism-carplay:client:musicStopped', -1, plate)
end)

RegisterNetEvent('prism-carplay:server:seekMusic', function(plate, position)
    local src = source
    if not (plate and musicState[plate]) then return end
    if not playerIsInMusicVehicle(src, plate) then return end
    if not isFiniteNumber(position) or position < 0 or position > 86400 then return end

    SeekAudioSource(musicState[plate].audioSourceId, position)
end)

RegisterNetEvent('prism-carplay:server:setMusicVolume', function(plate, volume)
    local src = source
    if not (plate and musicState[plate]) then return end
    if not playerIsInMusicVehicle(src, plate) then return end
    if not isFiniteNumber(volume) or volume < 0 or volume > 100 then return end

    musicState[plate].volume = volume
    SetSpeakerVolume(musicState[plate].speakerId, volume / 100)
end)

RegisterNetEvent('prism-carplay:server:getMusicState', function(plate)
    local src = source
    if musicState[plate] and playerIsInMusicVehicle(src, plate) then
        TriggerClientEvent('prism-carplay:client:syncMusicState', src, plate, musicState[plate])
    end
end)
