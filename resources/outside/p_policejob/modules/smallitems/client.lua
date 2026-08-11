while not Config or not Config.SmallItems do
    Citizen.Wait(500)
end

if not Config.SmallItems.Enabled then
    return
end

SmallItems = {
    savedProps = {},
    nightVision = {
        isWearing = false,
        isActive = false,
    },
    thermalVision = {
        isWearing = false,
        isActive = false,
    },
}

function SmallItems.hasJobAccess(self)
    local job = Bridge.Framework.fetchPlayerJob()
    if not job or not Config.Jobs then
        return false
    end
    return Config.Jobs[job.name] ~= nil
end

function SmallItems.applyHat(self, hatConfig)
    if not hatConfig or not hatConfig.enabled then
        return
    end
    local ped = PlayerPedId()
    if self.savedProps[hatConfig.propIndex] == nil then
        self.savedProps[hatConfig.propIndex] = {
            drawable = GetPedPropIndex(ped, hatConfig.propIndex),
            texture = GetPedPropTextureIndex(ped, hatConfig.propIndex),
        }
    end
    local appearance = GetEntityModel(ped) == 1885233650 and hatConfig.male or hatConfig.female
    SetPedPropIndex(ped, hatConfig.propIndex, appearance.drawable, appearance.texture, true)
end

function SmallItems.restoreHat(self, hatConfig)
    if not hatConfig or not hatConfig.enabled then
        return
    end
    local saved = self.savedProps[hatConfig.propIndex]
    if saved == nil then
        return
    end
    local ped = PlayerPedId()
    if saved.drawable == -1 then
        ClearPedProp(ped, hatConfig.propIndex)
    else
        SetPedPropIndex(ped, hatConfig.propIndex, saved.drawable, saved.texture, true)
    end
    self.savedProps[hatConfig.propIndex] = nil
end

function SmallItems.setNightVisionActive(self, active)
    self.nightVision.isActive = active
    SetNightvision(active)
    if active and self.thermalVision.isActive then
        self.thermalVision.isActive = false
        SetSeethrough(false)
    end
end

function SmallItems.setThermalVisionActive(self, active)
    self.thermalVision.isActive = active
    SetSeethrough(active)
    if active and self.nightVision.isActive then
        self.nightVision.isActive = false
        SetNightvision(false)
    end
end

function SmallItems.toggleNightVision(self)
    local config = Config.SmallItems.NightVision
    if self.nightVision.isWearing then
        if not Bridge.Progress.Start({
            duration = config.putOnTime,
            label = locale("nightvision_taking_off"),
            useWhileDead = false,
            canCancel = true,
            disable = config.disableControls,
            anim = config.putOnAnim,
        }) then
            return
        end
        self.nightVision.isWearing = false
        self:setNightVisionActive(false)
        if self.thermalVision.isWearing then
            self:applyHat(Config.SmallItems.ThermalVision.hat)
        else
            self:restoreHat(config.hat)
        end
        Bridge.Notify.showNotify(locale("nightvision_removed"), "inform")
    else
        if config.requireJob and not self:hasJobAccess() then
            Bridge.Notify.showNotify(locale("no_access"), "error")
            return
        end
        if not Bridge.Progress.Start({
            duration = config.putOnTime,
            label = locale("nightvision_putting_on"),
            useWhileDead = false,
            canCancel = true,
            disable = config.disableControls,
            anim = config.putOnAnim,
        }) then
            return
        end
        self.nightVision.isWearing = true
        self:setNightVisionActive(true)
        self:applyHat(config.hat)
        Bridge.Notify.showNotify(locale("nightvision_equipped"), "success")
    end
end

function SmallItems.toggleThermalVision(self)
    local config = Config.SmallItems.ThermalVision
    if self.thermalVision.isWearing then
        if not Bridge.Progress.Start({
            duration = config.putOnTime,
            label = locale("thermalvision_taking_off"),
            useWhileDead = false,
            canCancel = true,
            disable = config.disableControls,
            anim = config.putOnAnim,
        }) then
            return
        end
        self.thermalVision.isWearing = false
        self:setThermalVisionActive(false)
        if self.nightVision.isWearing then
            self:applyHat(Config.SmallItems.NightVision.hat)
        else
            self:restoreHat(config.hat)
        end
        Bridge.Notify.showNotify(locale("thermalvision_removed"), "inform")
    else
        if config.requireJob and not self:hasJobAccess() then
            Bridge.Notify.showNotify(locale("no_access"), "error")
            return
        end
        if not Bridge.Progress.Start({
            duration = config.putOnTime,
            label = locale("thermalvision_putting_on"),
            useWhileDead = false,
            canCancel = true,
            disable = config.disableControls,
            anim = config.putOnAnim,
        }) then
            return
        end
        self.thermalVision.isWearing = true
        self:setThermalVisionActive(true)
        self:applyHat(config.hat)
        Bridge.Notify.showNotify(locale("thermalvision_equipped"), "success")
    end
end

function SmallItems.onPlayerDead(self)
    if self.nightVision.isActive then
        SetNightvision(false)
    end
    self.nightVision.isActive = false
    self.nightVision.isWearing = false
    if self.thermalVision.isActive then
        SetSeethrough(false)
    end
    self.thermalVision.isActive = false
    self.thermalVision.isWearing = false
    self:restoreHat(Config.SmallItems.NightVision.hat)
    self:restoreHat(Config.SmallItems.ThermalVision.hat)
end

if Config.SmallItems.NightVision.enabled then
    exports("isNightVisionActive", function()
        return SmallItems.nightVision.isActive
    end)

    RegisterNetEvent("p_policejob/client/smallitems/nightvision/use", function()
        SmallItems:toggleNightVision()
    end)
end

if Config.SmallItems.ThermalVision.enabled then
    exports("isThermalVisionActive", function()
        return SmallItems.thermalVision.isActive
    end)

    RegisterNetEvent("p_policejob/client/smallitems/thermalvision/use", function()
        SmallItems:toggleThermalVision()
    end)
end

AddEventHandler("onResourceStop", function(resourceName)
    if GetCurrentResourceName() ~= resourceName then
        return
    end
    SetNightvision(false)
    SetSeethrough(false)
    SmallItems:restoreHat(Config.SmallItems.NightVision.hat)
    SmallItems:restoreHat(Config.SmallItems.ThermalVision.hat)
end)

AddStateBagChangeHandler("isDead", ("player:%s"):format(cache.serverId), function(_, _, value)
    if not value then
        return
    end
    SmallItems:onPlayerDead()
end)
