-- cm-spawn/client/tutorial.lua

local tutorialActive = false
local tutorialSteps = {
    {
        title = 'Welcome to Los Santos',
        text = 'This is your new home. Explore the city, find work, and build your life.',
        duration = 8000,
        pos = vector3(-1037.0, -2737.0, 20.0)
    },
    {
        title = 'Finding Work',
        text = 'Visit the job center to find employment. You need money to survive.',
        duration = 8000,
        pos = vector3(-260.0, -970.0, 31.0)
    },
    {
        title = 'Banking',
        text = 'Keep your money safe at the bank. You can deposit and withdraw cash.',
        duration = 8000,
        pos = vector3(150.0, -1040.0, 29.0)
    },
    {
        title = 'Stay Safe',
        text = 'The city has dangerous areas. Stay alert and make allies.',
        duration = 6000,
        pos = vector3(0, 0, 0) -- Return to player
    }
}

RegisterNetEvent('cm-spawn:client:startTutorial')
AddEventHandler('cm-spawn:client:startTutorial', function()
    print('[CM-SPAWN] Tutorial starting...')
    tutorialActive = true
    
    -- Show first message
    SendNUIMessage({
        action = 'showTutorial',
        step = 1,
        total = #tutorialSteps,
        title = tutorialSteps[1].title,
        text = tutorialSteps[1].text
    })
    
    -- Camera tour
    local ped = PlayerPedId()
    local startPos = GetEntityCoords(ped)
    
    for i, step in ipairs(tutorialSteps) do
        if not tutorialActive then break end
        
        -- Update UI
        SendNUIMessage({
            action = 'updateTutorial',
            step = i,
            total = #tutorialSteps,
            title = step.title,
            text = step.text
        })
        
        -- Move camera
        if step.pos and step.pos.x ~= 0 then
            local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
            SetCamCoord(cam, step.pos.x, step.pos.y, step.pos.z + 50.0)
            PointCamAtCoord(cam, step.pos.x, step.pos.y, step.pos.z)
            SetCamFov(cam, 60.0)
            SetCamActive(cam, true)
            RenderScriptCams(true, true, 2000, true, true)
            
            Wait(step.duration)
            
            RenderScriptCams(false, true, 1000, true, true)
            DestroyCam(cam, false)
        else
            -- Last step: focus on player
            RenderScriptCams(false, false, 0, true, true)
            Wait(step.duration)
        end
    end
    
    -- Tutorial complete
    if tutorialActive then
        SendNUIMessage({action = 'hideTutorial'})
        TriggerServerEvent('cm-spawn:server:tutorialComplete')
        tutorialActive = false
        print('[CM-SPAWN] Tutorial complete')
    end
    
    -- Trigger player spawned event
    TriggerEvent('cm-core:playerSpawned')
end)

-- Skip tutorial command
RegisterCommand('skiptutorial', function()
    if tutorialActive then
        tutorialActive = false
        SendNUIMessage({action = 'hideTutorial'})
        RenderScriptCams(false, false, 0, true, true)
        TriggerServerEvent('cm-spawn:server:tutorialComplete')
        print('[CM-SPAWN] Tutorial skipped')
    end
end)