-- CM License System — Client HUD Display

local Constants = require 'shared.constants'

local HUD = {}

HUD.Active = false
HUD.CurrentData = nil

function HUD.Init()
    print('^2[CM-License HUD]^7 HUD system initialized')

    -- Start HUD draw loop
    Citizen.CreateThread(function()
        while true do
            Wait(0)
            if HUD.Active and HUD.CurrentData then
                HUD.Draw()
            end
        end
    end)
end

-- Start test HUD
function HUD.StartTest(testData)
    HUD.Active = true
    HUD.CurrentData = {
        licenseType = testData.licenseType,
        licenseLabel = testData.licenseLabel,
        currentCheckpoint = 0,
        totalCheckpoints = 0,
        distance = 0,
        mistakes = 0,
        maxMistakes = 0,
        altitude = 0,
        speed = 0
    }
    print('^2[CM-License]^7 HUD started')
end

-- Update checkpoint info
function HUD.UpdateCheckpoint(data)
    if not HUD.CurrentData then return end
    HUD.CurrentData.currentCheckpoint = data.currentCheckpoint
    HUD.CurrentData.totalCheckpoints = data.totalCheckpoints
end

-- Update test state
function HUD.Update(data)
    if not HUD.Active or not HUD.CurrentData then return end

    local ped = PlayerPedId()

    if IsPedInAnyVehicle(ped, false) then
        local vehicle = GetVehiclePedIsIn(ped, false)

        -- Get vehicle speed (km/h)
        local speed = math.floor(GetEntitySpeed(vehicle) * 3.6)
        HUD.CurrentData.speed = speed

        -- Get altitude for aircraft
        local coords = GetEntityCoords(ped)
        HUD.CurrentData.altitude = math.floor(coords.z)
    end
end

-- Draw HUD
function HUD.Draw()
    if not HUD.Active or not HUD.CurrentData then return end

    local data = HUD.CurrentData
    local safeZone = GetSafeZoneSize()
    local safeZoneX = 1.0 - safeZone - 0.04
    local safeZoneY = 0.04

    -- Calculate position (right side of screen)
    local x = safeZoneX
    local y = safeZoneY
    local width = 0.22
    local height = 0.35

    -- Background panel
    DrawRect(x + width / 2, y + height / 2, width, height, 8, 18, 34, 200)

    -- Border
    DrawRect(x + width / 2, y + height / 2, width, height, 0, 229, 255, 100)

    -- Title
    BeginTextCommandDisplayText('STRING')
    AddTextComponentString('~c~' .. string.upper(data.licenseType) .. ' TEST')
    SetTextFont(4)
    SetTextScale(0.5, 0.5)
    SetTextColour(0, 229, 255, 255)
    EndTextCommandDisplayText(x + 0.01, y + 0.01)

    local yOffset = y + 0.05

    -- Checkpoint info
    BeginTextCommandDisplayText('STRING')
    AddTextComponentString('Checkpoint')
    SetTextFont(4)
    SetTextScale(0.35, 0.35)
    SetTextColour(200, 200, 200, 255)
    EndTextCommandDisplayText(x + 0.01, yOffset)

    yOffset = yOffset + 0.025

    BeginTextCommandDisplayText('STRING')
    AddTextComponentString(string.format('%02d / %02d', data.currentCheckpoint, data.totalCheckpoints))
    SetTextFont(1)
    SetTextScale(0.4, 0.4)
    SetTextColour(0, 229, 255, 255)
    EndTextCommandDisplayText(x + 0.01, yOffset)

    yOffset = yOffset + 0.035

    -- Distance info (if applicable)
    if data.licenseType ~= 'air' then
        BeginTextCommandDisplayText('STRING')
        AddTextComponentString('Distance')
        SetTextFont(4)
        SetTextScale(0.35, 0.35)
        SetTextColour(200, 200, 200, 255)
        EndTextCommandDisplayText(x + 0.01, yOffset)

        yOffset = yOffset + 0.025

        BeginTextCommandDisplayText('STRING')
        AddTextComponentString(string.format('%dm', data.distance or 0))
        SetTextFont(1)
        SetTextScale(0.4, 0.4)
        SetTextColour(0, 229, 255, 255)
        EndTextCommandDisplayText(x + 0.01, yOffset)

        yOffset = yOffset + 0.035
    end

    -- Speed
    if data.licenseType == 'driver' then
        BeginTextCommandDisplayText('STRING')
        AddTextComponentString('Speed')
        SetTextFont(4)
        SetTextScale(0.35, 0.35)
        SetTextColour(200, 200, 200, 255)
        EndTextCommandDisplayText(x + 0.01, yOffset)

        yOffset = yOffset + 0.025

        BeginTextCommandDisplayText('STRING')
        AddTextComponentString(string.format('%d km/h', data.speed or 0))
        SetTextFont(1)
        SetTextScale(0.4, 0.4)
        SetTextColour(0, 229, 255, 255)
        EndTextCommandDisplayText(x + 0.01, yOffset)

        yOffset = yOffset + 0.035

        -- Mistakes
        if data.maxMistakes > 0 then
            BeginTextCommandDisplayText('STRING')
            AddTextComponentString('Mistakes')
            SetTextFont(4)
            SetTextScale(0.35, 0.35)
            SetTextColour(200, 200, 200, 255)
            EndTextCommandDisplayText(x + 0.01, yOffset)

            yOffset = yOffset + 0.025

            local mistakeColor = (data.mistakes >= data.maxMistakes) and {255, 0, 0, 255} or {0, 229, 255, 255}

            BeginTextCommandDisplayText('STRING')
            AddTextComponentString(string.format('%d / %d', data.mistakes, data.maxMistakes))
            SetTextFont(1)
            SetTextScale(0.4, 0.4)
            SetTextColour(mistakeColor[1], mistakeColor[2], mistakeColor[3], mistakeColor[4])
            EndTextCommandDisplayText(x + 0.01, yOffset)
        end
    elseif data.licenseType == 'air' then
        -- Altitude for aircraft
        BeginTextCommandDisplayText('STRING')
        AddTextComponentString('Altitude')
        SetTextFont(4)
        SetTextScale(0.35, 0.35)
        SetTextColour(200, 200, 200, 255)
        EndTextCommandDisplayText(x + 0.01, yOffset)

        yOffset = yOffset + 0.025

        BeginTextComponentString(string.format('%dm', data.altitude or 0))
        SetTextFont(1)
        SetTextScale(0.4, 0.4)
        SetTextColour(0, 229, 255, 255)
        EndTextCommandDisplayText(x + 0.01, yOffset)
    end
end

-- Stop test HUD
function HUD.StopTest()
    HUD.Active = false
    HUD.CurrentData = nil
    print('^3[CM-License]^7 HUD stopped')
end

return HUD
