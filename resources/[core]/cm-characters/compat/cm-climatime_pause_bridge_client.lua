-- Optional compatibility bridge for cm-climatime client.
-- Put this into cm-climatime/client/main.lua or include it as a client script.
-- Then wrap your main weather/time sync loop with:
--     if not CmClimatimeCharacterPaused then
--         -- normal cm-climatime sync work
--     end

CmClimatimeCharacterPaused = CmClimatimeCharacterPaused or false

local function setCharacterPaused(state)
    CmClimatimeCharacterPaused = state == true
    LocalPlayer.state:set('cmClimatimePaused', CmClimatimeCharacterPaused, true)
end

RegisterNetEvent('cm-climatime:client:setPaused', function(state, reason)
    if reason == nil or tostring(reason) == 'cm-characters' then
        setCharacterPaused(state)
    end
end)

RegisterNetEvent('cm-climatime:client:pause', function(state)
    setCharacterPaused(state)
end)

RegisterNetEvent('cm-climatime:client:characterScreen', function(state)
    setCharacterPaused(state)
end)

RegisterNetEvent('cm-climatime:client:SetCharacterScreenMode', function(state)
    setCharacterPaused(state)
end)

exports('SetPaused', function(state, reason)
    if reason == nil or tostring(reason) == 'cm-characters' then
        setCharacterPaused(state)
    end
end)

exports('Pause', function(state)
    setCharacterPaused(state)
end)

exports('SetCharacterScreenMode', function(state)
    setCharacterPaused(state)
end)

exports('IsCharacterPaused', function()
    return CmClimatimeCharacterPaused == true
end)
