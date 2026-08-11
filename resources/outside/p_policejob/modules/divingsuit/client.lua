while not Config or not Config.DivingSuit do
    Citizen.Wait(500)
end

if not Config.DivingSuit.enabled then
    return
end

DivingSuit = {
    isActive = false,
    originalOutfit = {},
    hudThread = false,
}

function DivingSuit.startHudThread(self)
    if self.hudThread then
        return
    end
    self.hudThread = true
    SendNUIMessage({
        action = "setVisibleDivingSuitHud",
        data = true,
    })
    CreateThread(function()
        local maxTime = Config.DivingSuit.underwaterTime
        if maxTime <= 0 then
            maxTime = 1.0
        end
        while self.isActive do
            local remaining = GetPlayerUnderwaterTimeRemaining(cache.playerId)
            if remaining < 0 then
                remaining = 0
            end
            if maxTime < remaining then
                remaining = maxTime
            end
            local percent = math.floor(remaining / maxTime * 100 + 0.5)
            SendNUIMessage({
                action = "setDivingSuitOxygen",
                data = {
                    remaining = remaining,
                    percent = percent,
                    max = maxTime,
                },
            })
            Wait(500)
        end
        SendNUIMessage({
            action = "setVisibleDivingSuitHud",
            data = false,
        })
        self.hudThread = false
    end)
end

exports("isDivingSuitActive", function()
    return DivingSuit.isActive
end)

exports("toggleDivingSuit", function()
    if DivingSuit.isActive then
        DivingSuit:deactivate()
    else
        DivingSuit:activate()
    end
end)

function DivingSuit.saveOutfit(self)
    self.originalOutfit = {}
    local ped = cache.ped
    for _, component in ipairs(Config.DivingSuit.outfit) do
        table.insert(self.originalOutfit, {
            component = component.component,
            drawable = GetPedDrawableVariation(ped, component.component),
            texture = GetPedTextureVariation(ped, component.component),
        })
    end
end

function DivingSuit.applyOutfit(self, outfit)
    local ped = cache.ped
    for _, component in ipairs(outfit) do
        SetPedComponentVariation(ped, component.component, component.drawable, component.texture, 0)
    end
end

function DivingSuit.activate(self)
    if self.isActive then
        return
    end
    local completed = lib.progressBar({
        duration = Config.DivingSuit.progressBarDuration,
        label = locale("using_diving_suit"),
        useWhileDead = false,
        canCancel = true,
        allowSwimming = true,
        disable = {
            car = true,
            move = true,
            combat = true,
        },
        anim = {
            dict = "clothingshirt",
            clip = "try_shirt_positive_d",
            flag = 1,
        },
    })
    if not completed then
        Bridge.Notify.showNotify(locale("diving_suit_cancelled"), "error")
        return
    end
    self:saveOutfit()
    self:applyOutfit(Config.DivingSuit.outfit)
    local ped = cache.ped
    if Config.DivingSuit.scubaEnabled then
        SetEnableScuba(ped, true)
        SetPedMaxTimeUnderwater(ped, Config.DivingSuit.underwaterTime)
    end
    self.isActive = true
    Config.DivingSuit.onSuitActivated()
    Bridge.Notify.showNotify(locale("diving_suit_activated"), "success")
    if Config.DivingSuit.scubaEnabled then
        self:startHudThread()
    end
    ClearPedTasks(ped)
end

RegisterNetEvent("p_policejob/client/divingsuit/activate", function()
    DivingSuit:activate()
end)

function DivingSuit.deactivate(self)
    if not self.isActive then
        return
    end
    local completed = lib.progressBar({
        duration = Config.DivingSuit.progressBarDuration,
        label = locale("removing_diving_suit"),
        useWhileDead = false,
        canCancel = true,
        allowSwimming = true,
        disable = {
            car = true,
            move = true,
            combat = true,
        },
        anim = {
            dict = "clothingshirt",
            clip = "try_shirt_positive_d",
            flag = 1,
        },
    })
    if not completed then
        Bridge.Notify.showNotify(locale("diving_suit_removal_cancelled"), "error")
        return
    end
    if #self.originalOutfit > 0 then
        self:applyOutfit(self.originalOutfit)
    else
        local success, skin = pcall(function()
            return Bridge.Appearance.fetchDatabaseSkin()
        end)
        if success and skin then
            pcall(function()
                Bridge.Appearance.setPlayerSkin(skin)
            end)
        end
    end
    local ped = cache.ped
    if Config.DivingSuit.scubaEnabled then
        SetEnableScuba(ped, false)
        SetPedMaxTimeUnderwater(ped, 10.0)
    end
    self.isActive = false
    self.originalOutfit = {}
    Config.DivingSuit.onSuitDeactivated()
    Bridge.Notify.showNotify(locale("diving_suit_removed"), "success")
    ClearPedTasks(ped)
end

RegisterNetEvent("p_policejob/client/divingsuit/deactivate", function()
    DivingSuit:deactivate()
end)

if Config.DivingSuit.allowKeybindRemoval then
    lib.addKeybind({
        name = "divingsuit_deactivate",
        description = locale("diving_suit_deactivate_keybind"),
        defaultKey = Config.DivingSuit.deactivateKey,
        onPressed = function()
            if DivingSuit.isActive then
                DivingSuit:deactivate()
            end
        end,
    })
end

local hudEditMode = false

function DivingSuit.toggleHudEdit(enabled)
    hudEditMode = enabled
    if enabled then
        SetNuiFocus(true, true)
        SendNUIMessage({
            action = "setVisibleDivingSuitHud",
            data = true,
        })
        SendNUIMessage({
            action = "setDivingSuitOxygen",
            data = {
                remaining = 30,
                percent = 75,
                max = 40,
            },
        })
        SendNUIMessage({
            action = "setDivingSuitHudEdit",
            data = true,
        })
    else
        SendNUIMessage({
            action = "setDivingSuitHudEdit",
            data = false,
        })
        SetNuiFocus(false, false)
        if not DivingSuit.isActive then
            SendNUIMessage({
                action = "setVisibleDivingSuitHud",
                data = false,
            })
        end
    end
end

RegisterCommand(Config.DivingSuit.hudMoveCommand or "divingsuithud", function()
    DivingSuit:toggleHudEdit(not hudEditMode)
end, false)

RegisterNUICallback("hideFrame", function(data, cb)
    if data and data.name == "setVisibleDivingSuitHud" and hudEditMode then
        hudEditMode = false
        SetNuiFocus(false, false)
        if not DivingSuit.isActive then
            SendNUIMessage({
                action = "setVisibleDivingSuitHud",
                data = false,
            })
        end
    end
    cb("ok")
end)
