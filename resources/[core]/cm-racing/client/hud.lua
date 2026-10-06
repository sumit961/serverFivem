CMRacing = CMRacing or {}
CMRacing.Client = CMRacing.Client or {}
CMRacing.Client.HUD = {}

local HUD = CMRacing.Client.HUD
local isHudVisible = false
local currentRouteName = ''
local currentCheckpoint = 0
local totalCheckpoints = 0
local startedAtMs = 0

function HUD.Show(routeName, totalCps)
    currentRouteName = routeName or 'Sanctioned Race'
    totalCheckpoints = totalCps or 0
    currentCheckpoint = 0
    startedAtMs = GetGameTimer()
    isHudVisible = true

    SendNUIMessage({
        action = 'showHud',
        routeName = currentRouteName,
        currentCheckpoint = currentCheckpoint,
        totalCheckpoints = totalCheckpoints,
    })
end

function HUD.Hide()
    isHudVisible = false
    SendNUIMessage({ action = 'hideHud' })
end

function HUD.UpdateCheckpoint(cpIndex, totalCps)
    currentCheckpoint = cpIndex
    totalCheckpoints = totalCps or totalCheckpoints

    SendNUIMessage({
        action = 'updateHud',
        currentCheckpoint = currentCheckpoint,
        totalCheckpoints = totalCheckpoints,
    })
end

function HUD.ShowCountdown(seconds, callback)
    SendNUIMessage({ action = 'startCountdown', count = seconds })

    CreateThread(function()
        local remaining = seconds
        while remaining > 0 do
            PlaySoundFrontend(-1, 'CHECKPOINT_NORMAL', 'HUD_MINI_GAME_SOUNDSET', true)
            Wait(1000)
            remaining = remaining - 1
        end
        PlaySoundFrontend(-1, 'CHECKPOINT_PERFECT', 'HUD_MINI_GAME_SOUNDSET', true)
        if callback then callback() end
    end)
end

function HUD.ShowResults(results)
    HUD.Hide()
    SendNUIMessage({
        action = 'showResults',
        results = results
    })
    PlaySoundFrontend(-1, 'RACE_PLACED', 'HUD_AWARDS', true)
end

-- Tick loop to update elapsed time on the HUD
CreateThread(function()
    while true do
        if isHudVisible then
            local nowMs = GetGameTimer()
            local elapsedMs = math.max(0, nowMs - startedAtMs)
            local ped = PlayerPedId()
            local veh = GetVehiclePedIsIn(ped, false)
            local speedKmh = 0
            if veh ~= 0 then
                speedKmh = math.floor(GetEntitySpeed(veh) * 3.6)
            end

            SendNUIMessage({
                action = 'tickHud',
                elapsedMs = elapsedMs,
                speed = speedKmh
            })
            Wait(50)
        else
            Wait(350)
        end
    end
end)
