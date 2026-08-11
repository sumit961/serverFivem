local function decodeLocation(value)
    if type(value) == 'string' then local ok, decoded = pcall(json.decode, value); if ok then value = decoded end end
    return type(value) == 'table' and value or nil
end

local function teleport(location)
    location = decodeLocation(location)
    if not location then return end
    local ped = PlayerPedId()
    SetEntityCoords(ped, tonumber(location.x) or 0.0, tonumber(location.y) or 0.0, tonumber(location.z) or 0.0, false, false, false, false)
    SetEntityHeading(ped, tonumber(location.heading) or 0.0)
end

RegisterNetEvent('cm-prison:client:enter', function(location) teleport(location) end)
RegisterNetEvent('cm-prison:client:release', function(location) teleport(location) end)

local function remainingTime(releaseAt)
    local now = GetCloudTimeAsInt()
    if not now or now <= 0 then now = os.time() end
    local seconds = math.max(0, math.floor((tonumber(releaseAt) or 0) - now))
    local minutes = math.floor(seconds / 60)
    return ('%02d:%02d'):format(minutes, seconds % 60)
end

local function hudText(text, x, y, scale, red, green, blue, centre)
    SetTextFont(4); SetTextScale(0.0, scale); SetTextColour(red, green, blue, 255)
    SetTextOutline(); SetTextCentre(centre == true)
    BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

local function drawPrisonHud(state)
    local red, green, blue = 225, 76, 84
    -- Compact upper-left cinematic banner, matching the segmented reference.
    DrawRect(0.500, 0.076, 0.390, 0.105, 4, 8, 11, 196)
    DrawRect(0.500, 0.023, 0.390, 0.003, 138, 156, 165, 95)
    DrawRect(0.423, 0.076, 0.0015, 0.092, red, green, blue, 230)
    DrawRect(0.484, 0.076, 0.0015, 0.092, red, green, blue, 230)

    hudText(remainingTime(state.releaseAt), 0.352, 0.050, 0.72, red, green, blue, true)

    -- Prison-cell icon constructed from native rectangles, so no texture is required.
    DrawRect(0.454, 0.069, 0.031, 0.003, red, green, blue, 255)
    DrawRect(0.454, 0.096, 0.031, 0.003, red, green, blue, 255)
    DrawRect(0.439, 0.082, 0.002, 0.030, red, green, blue, 255)
    DrawRect(0.469, 0.082, 0.002, 0.030, red, green, blue, 255)
    DrawRect(0.449, 0.082, 0.002, 0.026, red, green, blue, 220)
    DrawRect(0.459, 0.082, 0.002, 0.026, red, green, blue, 220)

    hudText('YOU ARE IN JAIL', 0.502, 0.038, 0.25, red, green, blue, false)
    hudText('ARRESTED BY', 0.502, 0.059, 0.39, 245, 247, 248, false)
    hudText(tostring(state.arrestedBy or 'Police Department'):upper(), 0.502, 0.084, 0.25, 170, 178, 182, false)
end

CreateThread(function()
    while true do
        local state = LocalPlayer.state.cmPrison
        if type(state) == 'table' and state.active == true then
            drawPrisonHud(state)
            Wait(0)
        else
            Wait(750)
        end
    end
end)

CreateThread(function()
    while true do
        local state = LocalPlayer.state.cmPrison
        if type(state) ~= 'table' or state.active ~= true or type(state.spawn) ~= 'table' then Wait(1000)
        else
            Wait(1000)
            local coords = GetEntityCoords(PlayerPedId())
            local spawn = vector3(tonumber(state.spawn.x) or 0, tonumber(state.spawn.y) or 0, tonumber(state.spawn.z) or 0)
            if #(coords - spawn) > 35.0 then teleport(state.spawn) end
        end
    end
end)
