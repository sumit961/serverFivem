-- CM License System — Client HUD Display

HUD = {}

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
        startedAt = GetGameTimer()
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
end

-- Draw HUD
function HUD.Draw()
    if not HUD.Active or not HUD.CurrentData then return end
    
    local data = HUD.CurrentData
    -- Positioned below the shared CM identity/money HUD in the top-right.
    local x, y, width, height = 0.835, 0.185, 0.14, 0.066
    DrawRect(x + width / 2 + 0.002, y + height / 2 + 0.003, width, height, 0, 0, 0, 55)
    DrawRect(x + width / 2, y + height / 2, width, height, 5, 16, 24, 155)
    DrawRect(x + 0.0015, y + height / 2, 0.003, height, 0, 229, 255, 235)
    DrawRect(x + width / 2, y + 0.001, width, 0.0015, 0, 229, 255, 100)
    
    -- Title
    BeginTextCommandDisplayText('STRING')
    AddTextComponentString('LICENSE EXAM')
    SetTextFont(4)
    SetTextScale(0.29, 0.29)
    SetTextColour(0, 229, 255, 255)
    EndTextCommandDisplayText(x + 0.010, y + 0.008)
    
    local elapsed = math.max(0, math.floor((GetGameTimer() - (data.startedAt or GetGameTimer())) / 1000))
    BeginTextCommandDisplayText('STRING')
    AddTextComponentString(('Driving Time   %02d:%02d'):format(math.floor(elapsed / 60), elapsed % 60))
    SetTextFont(4)
    SetTextScale(0.34, 0.34)
    SetTextColour(255, 255, 255, 255)
    EndTextCommandDisplayText(x + 0.010, y + 0.035)
end

-- Stop test HUD
function HUD.StopTest()
    HUD.Active = false
    HUD.CurrentData = nil
    print('^3[CM-License]^7 HUD stopped')
end

return HUD
