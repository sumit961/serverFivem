--[[ Main Client File]]

client = {
    framework = shared.getFrameworkObject(),
    load = false,
    uiLoad = false,
    uiOpen = false,
    exports = {},
    -- global --
    currentTask = nil,
    lobby = {}, --[[@type Lobby]]
}

--[[ require ]]

require "modules.bridge.init"
require "modules.exports.client"

local Utils = require "modules.utils.client"
local Target = require "modules.target.client"

--[[ local variables ]]

local infoBoxKeyBind = nil
local isInfoBoxHidden = false

--[[ helper functions ]]

local function isPlayerNearSellNpc()
    local playerCoords = GetEntityCoords(cache.ped)
    for _, npc in pairs(Config.SellNpc.locations or {}) do
        if #(playerCoords - vec3(npc)) < 5.0 then
            return true
        end
    end
    return false
end

local function hideFrame()
    client.sendReactMessage("ui:setVisible", false)
    SetNuiFocus(false, false)
    client.uiOpen = false
end

local function clearClient()
    if client.uiOpen then hideFrame() end
    client.uiOpen = false
    Market.onUnload()
    MultiplayerTasksClient.onUnload()
    client.sendReactMessage("ui:onUnload")
    TriggerServerEvent(_e("server:onPlayerLogout"))
end

---Prepare the frontend and send the data
local function setupUI()
    if client.uiLoad then return end
    local defaultLocale = GetConvar("ox:locale", "en")
    client.sendReactMessage("ui:setupUI", {
        setLocale = lib.loadJson(("locales.%s"):format(defaultLocale)).ui,
        setConfig = {
            InventoryImagesFolder = Config.InventoryImagesFolder,
            InfoBoxAlign = Config.InfoBoxAlign,
        },
        setMarketItems = Market.getDataItems(),
        setHelpTexts = Config.HelpText,
        setMultiplayerTasksConfigs = MultiplayerTasksClient.configs,
    }, true)
end

local function openMenu()
    if not client.uiLoad then return end

    if Config.FarmingMenu.allowedJobs and #Config.FarmingMenu.allowedJobs > 0 then
        if not client.hasPlayerGotGroup(Config.FarmingMenu.allowedJobs) then
            Utils.notify(locale("you_do_not_have_permission"), "error")
            return
        end
    end

    client.sendReactMessage("ui:setPage", "home")
    client.sendReactMessage("ui:setPlayerNearSellNpc", isPlayerNearSellNpc())
    client.sendReactMessage("ui:setVisible", true)

    client.uiOpen = true
    if (Profile.get().source == -1) then
        Profile.fetch()
        Profile.updateUI()
    end

    SetNuiFocus(true, true)

    -- ui:setPlayerInventory
    lib.callback(_e("server:inventory:getPlayerInventory"), false, function(response)
        if not response then return end
        client.sendReactMessage("ui:setPlayerInventory", response)
    end)
end

local function spawnSellNpc()
    local model = Config.SellNpc.model
    local blip = Config.SellNpc.blip
    local locations = Config.SellNpc.locations

    lib.requestModel(model)
    for _, coords in pairs(locations) do
        local npc = CreatePed(4, model, coords.x, coords.y, coords.z, coords.w or 0.0, false, true)
        while not DoesEntityExist(npc) do Wait(0) end

        SetEntityCoords(npc, coords.x, coords.y, coords.z)
        FreezeEntityPosition(npc, true)
        SetEntityInvincible(npc, true)
        SetPedDiesWhenInjured(npc, false)
        TaskSetBlockingOfNonTemporaryEvents(npc, true)
        SetBlockingOfNonTemporaryEvents(npc, true)

        if blip and blip.active then
            Utils.addBlip(npc, blip)
        end

        Target.addLocalEntity(npc, { {
            label = locale("open_sell_menu"),
            icon = "fas fa-shopping-cart",
            distance = 2.0,
            onSelect = function()
                openMenu()
            end
        } }, true)
    end
    SetModelAsNoLongerNeeded(model)
end

--[[ functions ]]

---Sends message to the ReactUI.
---@param action string
---@param data any
function client.sendReactMessage(action, data)
    SendNUIMessage({ action = action, data = data })
end

---@param text string
---@param type "error"|"success"
function client.sendReactAlert(text, type)
    client.sendReactMessage("ui:setAlert", { type = type, text = text })
end

function client.onPlayerLoad(isLoggedIn)
    if not isLoggedIn then
        clearClient()
        Utils.hideTextUI()
        PersonalChallengesClient.clear()
    else
        PersonalChallengesClient.init()
        spawnSellNpc()
    end

    client.load = isLoggedIn
end

function client.hideUI()
    hideFrame()
end

function client.setOutfit(outfit)
    local framework = shared.framework

    if outfit then
        if framework == "esx" then
            client.framework.TriggerServerCallback("esx_skin:getPlayerSkin", function(skin)
                if skin then
                    TriggerEvent("skinchanger:loadClothes", skin, outfit)
                end
            end)
        else
            TriggerEvent("qb-clothing:client:loadOutfit", { outfitData = outfit })
        end
    else
        if framework == "esx" then
            client.framework.TriggerServerCallback("esx_skin:getPlayerSkin", function(skin)
                if skin then TriggerEvent("skinchanger:loadSkin", skin) end
            end)
        elseif framework == "qb" then
            TriggerServerEvent("qb-clothes:loadPlayerSkin")
        else
            TriggerEvent("illenium-appearance:client:reloadSkin", true)
        end
    end
end

function client.setInfoBoxDisabledState(state)
    infoBoxKeyBind:disable(state)
    isTaskInfoMenuHidden = false
end

function client.getClosestSellNpc()
    local playerCoords = GetEntityCoords(cache.ped)
    local closestNpc = nil
    local closestDistance = -1

    for _, npc in pairs(Config.SellNpc.locations) do
        local distance = #(playerCoords - vector3(npc.x, npc.y, npc.z))
        if closestDistance == -1 or distance < closestDistance then
            closestDistance = distance
            closestNpc = npc
        end
    end

    return closestNpc, closestDistance
end

--[[ events ]]

RegisterNUICallback("nui:client:loadUI", function(_, resultCallback)
    resultCallback(true)
    setupUI()
end)

RegisterNUICallback("nui:client:onLoadUI", function(_, resultCallback)
    resultCallback(true)
    client.uiLoad = true
end)

RegisterNUICallback("nui:client:hideFrame", function(_, resultCallback)
    hideFrame()
    resultCallback(true)
end)

AddEventHandler("onResourceStart", function(resource)
    if resource ~= shared.resource then return end
    Citizen.Wait(2000)
    if not client.isPlayerLoaded() then return end
    client.onPlayerLoad(true)
end)

AddEventHandler("onResourceStop", function(resource)
    if resource ~= shared.resource then return end
    client.onPlayerLoad(false)
end)

if Config.FarmingMenu.openWithCommand and Config.FarmingMenu.openWithCommand.active then
    RegisterCommand(Config.FarmingMenu.openWithCommand.command, openMenu)
end

if Config.FarmingMenu.openWithKey and Config.FarmingMenu.openWithKey.active then
    lib.addKeybind({
        name = "farming_v2_open_menu",
        description = "Open menu",
        defaultKey = Config.FarmingMenu.openWithKey.key,
        onPressed = openMenu
    })
end

RegisterNetEvent("0r-farming-v2:client:openMenu", function()
    if not client.uiLoad then
        setupUI()
    end
    openMenu()
end)

RegisterNetEvent("client:farming-v2:notify", function(title, type, description, duration)
    Utils.notify(title, type, duration, description)
end)

infoBoxKeyBind = lib.addKeybind({
    name = "toggle_farming_v2_info_box",
    description = "Toggle farming v2 info box",
    defaultKey = Config.ToggleInfoBoxKey,
    onPressed = function(self)
        self:disable(true)
        client.sendReactMessage("ui:setInfoBox", {
            hidden = not isTaskInfoMenuHidden,
            texts = client.currentTask and client.currentTask.infoBoxTable or {},
        })
        isTaskInfoMenuHidden = not isTaskInfoMenuHidden
        Citizen.SetTimeout(1000, function()
            self:disable(false)
        end)
    end,
    disabled = true,
})
