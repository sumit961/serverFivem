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
        currentCheckpoint = tonumber(testData.currentCheckpoint) or 1,
        totalCheckpoints = tonumber(testData.totalCheckpoints) or #Checkpoints.Checkpoints,
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

    -- Keep the exam strip top-centre, clear of cm-hud's top-right identity and
    -- money modules. The layout is normalized, so it stays compact on common
    -- 16:9 resolutions without introducing another NUI surface.
    local hasMistakes = data.maxMistakes > 0
    local width = hasMistakes and 0.36 or 0.285
    local x, y, height = 0.5 - (width / 2), 0.028, 0.060

    DrawRect(x + width / 2 + 0.002, y + height / 2 + 0.003, width, height, 0, 0, 0, 55)
    DrawRect(x + width / 2, y + height / 2, width, height, 11, 23, 30, 225)
    DrawRect(x + 0.0015, y + height / 2, 0.003, height, 0, 229, 255, 235)
    DrawRect(x + width / 2, y + 0.001, width, 0.0015, 0, 229, 255, 180)

    drawText('LICENSE EXAM', x + 0.010, y + 0.011, 0.23, 0, 229, 255)

    local remaining = math.max(0, math.floor(((data.deadlineAt or 0) - GetGameTimer()) / 1000))
    local urgent = remaining <= 60
    drawText('CHECKPOINTS LEFT', x + 0.095, y + 0.009, 0.18, 194, 210, 220)
    local total = tonumber(data.totalCheckpoints) or 0
    local current = tonumber(data.currentCheckpoint) or 1
    local checkpointsLeft = math.max(0, total - current)
    drawText(tostring(checkpointsLeft), x + 0.095, y + 0.027, 0.31, 255, 255, 255)

    local timeX = x + (hasMistakes and 0.225 or 0.220)
    drawText('TIME', timeX, y + 0.009, 0.18, 194, 210, 220)
    drawText(('%02d:%02d'):format(math.floor(remaining / 60), remaining % 60),
        timeX, y + 0.027, 0.31, urgent and 255 or 255, urgent and 90 or 255, urgent and 90 or 255)

    if hasMistakes then
        local mistakesX = x + 0.300
        drawText('MISTAKES', mistakesX, y + 0.009, 0.18, 194, 210, 220)
        local overHalf = (data.mistakes or 0) > (data.maxMistakes / 2)
        drawText(('%d / %d'):format(data.mistakes or 0, data.maxMistakes),
            mistakesX, y + 0.027, 0.31, overHalf and 255 or 255, overHalf and 140 or 255, overHalf and 55 or 255)
    end
end

function HUD.StopTest()
    HUD.Active = false
    HUD.CurrentData = nil
    CMLog('HUD stopped')
end

return HUD
