-- ============================================================
--  cm-family | cl_npc.lua
--  Spawns the family registrar NPC and shows an E prompt near it. Pressing E
--  opens the create/join flow (or the menu, if already in a family). Reuses
--  cm-house's interaction prompt export when available so the on-screen style
--  matches; otherwise falls back to a native help text.
-- ============================================================

local npcPed = nil
local promptShown = false

-- The E key control id (INPUT_CONTEXT = 38). Overridable via Config.PromptKey.
local PROMPT_KEY = Config and Config.PromptKey or 38

local function houseInteractionAvailable()
    return GetResourceState(Config.HouseResource) == 'started'
end

-- The cm-house interaction prompt auto-expires (ttl), so it must be re-asserted
-- every frame while the player is in range rather than requested once.
local function assertPrompt(label)
    if houseInteractionAvailable() then
        pcall(function()
            exports[Config.HouseResource]:RequestInteraction('cm-family-npc', label, '', 20, { key = 'E', ttl = 250 })
        end)
        promptShown = true
    else
        BeginTextCommandDisplayHelp('STRING')
        AddTextComponentSubstringPlayerName('Press ~INPUT_CONTEXT~ to ' .. label)
        EndTextCommandDisplayHelp(0, false, true, -1)
        promptShown = true
    end
end

local function clearPrompt()
    if not promptShown then return end
    if houseInteractionAvailable() then
        pcall(function() exports[Config.HouseResource]:ClearInteraction('cm-family-npc') end)
    end
    promptShown = false
end

local function spawnNPC()
    if not Config.NPC.enabled then return end
    local model = joaat(Config.NPC.model)
    RequestModel(model)
    local timeout = GetGameTimer() + 8000
    while not HasModelLoaded(model) and GetGameTimer() < timeout do Wait(10) end
    if not HasModelLoaded(model) then return end

    local c = Config.NPC.coords
    npcPed = CreatePed(4, model, c.x, c.y, c.z - 1.0, c.w, false, true)
    SetEntityInvincible(npcPed, true)
    FreezeEntityPosition(npcPed, true)
    SetBlockingOfNonTemporaryEvents(npcPed, true)
    if Config.NPC.scenario then TaskStartScenarioInPlace(npcPed, Config.NPC.scenario, 0, true) end
    SetModelAsNoLongerNeeded(model)

    if Config.NPC.blip and Config.NPC.blip.enabled then
        local blip = AddBlipForCoord(c.x, c.y, c.z)
        SetBlipSprite(blip, Config.NPC.blip.sprite)
        SetBlipColour(blip, Config.NPC.blip.color)
        SetBlipScale(blip, Config.NPC.blip.scale)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(Config.NPC.blip.label)
        EndTextCommandSetBlipName(blip)
    end
end

-- Ask the server whether we're in a family, then open the right UI.
local function onInteract()
    local menu = lib.callback.await('cm-family:server:getMenu', false)
    if menu and menu.ok then
        TriggerEvent('cm-family:client:openMenu', menu)
    elseif menu and menu.invite then
        TriggerEvent('cm-family:client:openInvitePrompt', menu.invite)
    else
        -- Not in a family: open the create flow.
        TriggerEvent('cm-family:client:openCreate')
    end
end

CreateThread(function()
    Wait(1000)
    spawnNPC()

    local c = Config.NPC.coords
    while true do
        local sleep = 1000
        local ped = PlayerPedId()
        local pcoords = GetEntityCoords(ped)
        local dist = #(pcoords - vector3(c.x, c.y, c.z))

        if dist < Config.NPC.drawDistance then
            sleep = 0
            if dist < Config.NPC.interactionDistance then
                assertPrompt('manage family')
                if IsControlJustReleased(0, PROMPT_KEY) then
                    clearPrompt()
                    onInteract()
                    Wait(500)
                end
            else
                clearPrompt()
            end
        else
            clearPrompt()
        end
        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if npcPed and DoesEntityExist(npcPed) then DeleteEntity(npcPed) end
    clearPrompt()
end)

RegisterCommand(Config.MenuCommand or 'family', function()
    onInteract()
end, false)
