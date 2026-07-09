-- cm-spawn/client/tutorial.lua

local tutorialActive = false
local RESOURCE = 'CM-SPAWN'

local function cfg(key, fallback)
    if Config and Config[key] ~= nil then return Config[key] end
    return fallback
end

local function dprint(message)
    if cfg('Debug', false) or cfg('VerboseLogs', false) then
        print(('[%s] %s'):format(RESOURCE, tostring(message)))
    end
end

local tutorialSteps = {
    {
        title = 'Welcome to Grand RP',
        text = 'This is your new city. Learn the basics, find work, and build your story.',
        duration = 8000,
        pos = vector3(-1037.0, -2737.0, 20.0)
    },
    {
        title = 'Finding Work',
        text = 'Start with beginner-friendly jobs. More tasks unlock as your level and playtime increase.',
        duration = 8000,
        pos = vector3(-260.0, -970.0, 31.0)
    },
    {
        title = 'Banking',
        text = 'Use cash for small purchases and keep bigger savings safe in your bank.',
        duration = 8000,
        pos = vector3(150.0, -1040.0, 29.0)
    },
    {
        title = 'Organizations',
        text = 'Later you can join organizations such as police, army, companies, clubs, or gangs if they exist in the city.',
        duration = 7000,
        pos = vector3(0, 0, 0)
    }
}

RegisterNetEvent('cm-spawn:client:startTutorial')
AddEventHandler('cm-spawn:client:startTutorial', function()
    dprint('Tutorial starting')
    tutorialActive = true

    SendNUIMessage({
        action = 'showTutorial',
        step = 1,
        total = #tutorialSteps,
        title = tutorialSteps[1].title,
        text = tutorialSteps[1].text
    })

    for i, step in ipairs(tutorialSteps) do
        if not tutorialActive then break end

        SendNUIMessage({
            action = 'updateTutorial',
            step = i,
            total = #tutorialSteps,
            title = step.title,
            text = step.text
        })

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
            RenderScriptCams(false, false, 0, true, true)
            Wait(step.duration)
        end
    end

    if tutorialActive then
        SendNUIMessage({ action = 'hideTutorial' })
        TriggerServerEvent('cm-spawn:server:tutorialComplete')
        tutorialActive = false
        dprint('Tutorial complete')
    end

    TriggerEvent('cm-core:playerSpawned')
end)

RegisterCommand('skiptutorial', function()
    if tutorialActive then
        tutorialActive = false
        SendNUIMessage({ action = 'hideTutorial' })
        RenderScriptCams(false, false, 0, true, true)
        TriggerServerEvent('cm-spawn:server:tutorialComplete')
        dprint('Tutorial skipped')
    end
end)
