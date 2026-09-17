-- CM License System — Client HUD Display

HUD = {}

HUD.Active = false
HUD.CurrentData = nil

function HUD.Init()
    CMLog('HUD system initialized')

    CreateThread(function()
        while true do
            if HUD.Active and HUD.CurrentData then
                Wait(0)
                HUD.Draw()
            else
                Wait(400)
            end
        end
    end)
end

function HUD.StartTest(testData)
    HUD.Active = true
    HUD.CurrentData = {
        licenseType = testData.licenseType,
        licenseLabel = testData.licenseLabel,
        startedAt = GetGameTimer(),
        deadlineAt = GetGameTimer() + ((tonumber(testData.secondsRemaining) or tonumber(testData.timeoutSeconds) or 1200) * 1000),
        currentCheckpoint = 0,
        totalCheckpoints = #Checkpoints.Checkpoints,
        mistakes = 0,
        maxMistakes = tonumber(testData.maxMistakes) or 0,
    }
    CMLog('HUD started')
end

function HUD.UpdateCheckpoint(data)
    if not HUD.CurrentData then return end
    HUD.CurrentData.currentCheckpoint = tonumber(data.currentCheckpoint) or HUD.CurrentData.currentCheckpoint
    HUD.CurrentData.totalCheckpoints = tonumber(data.totalCheckpoints) or HUD.CurrentData.totalCheckpoints
    if tonumber(data.secondsRemaining) then
        HUD.CurrentData.deadlineAt = GetGameTimer() + (tonumber(data.secondsRemaining) * 1000)
    end
end

function HUD.UpdateMistakes(data)
    if not HUD.CurrentData then return end
    HUD.CurrentData.mistakes = tonumber(data.mistakes) or HUD.CurrentData.mistakes
    HUD.CurrentData.maxMistakes = tonumber(data.maxMistakes) or HUD.CurrentData.maxMistakes
end

function HUD.SyncDeadline(seconds)
    if not HUD.CurrentData or not tonumber(seconds) then return end
    HUD.CurrentData.deadlineAt = GetGameTimer() + (tonumber(seconds) * 1000)
end

local function drawText(text, x, y, scale, r, g, b, a)
    SetTextFont(4)
    SetTextScale(scale, scale)
    SetTextColour(r, g, b, a or 255)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentString(text)
    EndTextCommandDisplayText(x, y)
end

function HUD.Draw()
    local data = HUD.CurrentData
    if not data then return end

    -- Positioned below the shared CM identity/money HUD in the top-right.
    local x, y, width = 0.835, 0.185, 0.14
    local height = data.maxMistakes > 0 and 0.100 or 0.086

    DrawRect(x + width / 2 + 0.002, y + height / 2 + 0.003, width, height, 0, 0, 0, 55)
    DrawRect(x + width / 2, y + height / 2, width, height, 5, 16, 24, 155)
    DrawRect(x + 0.0015, y + height / 2, 0.003, height, 0, 229, 255, 235)
    DrawRect(x + width / 2, y + 0.001, width, 0.0015, 0, 229, 255, 100)

    drawText('LICENSE EXAM', x + 0.010, y + 0.008, 0.29, 0, 229, 255)

    local remaining = math.max(0, math.floor(((data.deadlineAt or 0) - GetGameTimer()) / 1000))
    local urgent = remaining <= 60
    drawText(('Time Left   %02d:%02d'):format(math.floor(remaining / 60), remaining % 60),
        x + 0.010, y + 0.030, 0.32, urgent and 255 or 255, urgent and 90 or 255, urgent and 90 or 255)

    local total = data.totalCheckpoints or 0
    if total > 0 then
        drawText(('Checkpoint  %d / %d'):format(data.currentCheckpoint or 0, total),
            x + 0.010, y + 0.052, 0.30, 210, 230, 240)
    end

    if data.maxMistakes > 0 then
        local overHalf = (data.mistakes or 0) > (data.maxMistakes / 2)
        drawText(('Mistakes    %d / %d'):format(data.mistakes or 0, data.maxMistakes),
            x + 0.010, y + 0.074, 0.30, overHalf and 255 or 210, overHalf and 160 or 230, overHalf and 90 or 240)
    end
end

function HUD.StopTest()
    HUD.Active = false
    HUD.CurrentData = nil
    CMLog('HUD stopped')
end

return HUD
