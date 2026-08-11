if not Config or not Config.Prison or not Config.Prison.Enabled then
    return
end

Prison = {
    isInPrison = false,
    sentenceData = nil,
    cellId = nil,
    prisonZone = nil,
    savedOutfit = nil,
    Map = nil,
}

CreateThread(function()
    while not Config.PrisonMap do
        Wait(100)
    end

    if type(Config.PrisonMap) == "string" then
        Prison.Map = lib.load(("maps.prisons.%s"):format(Config.PrisonMap))
    elseif type(Config.PrisonMap) == "table" then
        Prison.Map = lib.load(("maps.prisons.%s"):format(Config.PrisonMap[1]))
    end

    if not Prison.Map or type(Prison.Map) ~= "table" then
        lib.print.error("Failed to load prison map. Check Config.PrisonMap in config/shared.lua")
        return
    end

    Bridge.Debug("[Prison] Loaded prison map: " .. tostring(Config.PrisonMap))
end)

function Prison.hasJobAccess(self)
    local job = Bridge.Framework.fetchPlayerJob()
    if not job then
        return false
    end
    return Config.Jobs[job.name] ~= nil
end

function Prison.getJobGrade(self)
    local job = Bridge.Framework.fetchPlayerJob()
    if not job then
        return -1
    end
    if Config.Jobs[job.name] == nil then
        return -1
    end
    return tonumber(job.grade) or 0
end

function Prison.applyPrisonOutfit(self)
    local ped = cache.ped
    local isMale = GetEntityModel(ped) == 1885233650
    local outfitConfig = isMale and Config.Prison.PrisonOutfit.male or Config.Prison.PrisonOutfit.female
    if not outfitConfig then
        return
    end

    self.savedOutfit = {}
    local componentSlots = {
        tshirt = 8,
        torso = 11,
        decals = 10,
        arms = 3,
        pants = 4,
        shoes = 6,
        bags = 5,
    }

    for key in pairs(outfitConfig) do
        local componentName, slotIndex = key:match("(.-)_(%d+)")
        if componentName and tonumber(slotIndex) == 1 then
            local drawableId = componentSlots[componentName]
            if drawableId then
                self.savedOutfit[key] = GetPedDrawableVariation(ped, drawableId)
                self.savedOutfit[componentName .. "_2"] = GetPedTextureVariation(ped, drawableId)
            end
        end
    end

    local slotMap = {
        tshirt_1 = { 8, true },
        torso_1 = { 11, true },
        decals_1 = { 10, true },
        arms = { 3, true },
        pants_1 = { 4, true },
        shoes_1 = { 6, true },
    }

    for key, slot in pairs(slotMap) do
        local drawable = outfitConfig[key]
        if drawable then
            local textureKey = key:gsub("_1$", "_2")
            local texture = outfitConfig[textureKey] or 0
            SetPedComponentVariation(ped, slot[1], drawable, texture, 2)
        end
    end
end

function Prison.restoreOutfit(self)
    if not self.savedOutfit then
        return
    end

    local ped = cache.ped
    local slotMap = {
        tshirt_1 = 8,
        torso_1 = 11,
        decals_1 = 10,
        arms = 3,
        pants_1 = 4,
        shoes_1 = 6,
    }

    for key, drawableId in pairs(slotMap) do
        local savedDrawable = self.savedOutfit[key]
        local textureKey = key:gsub("_1$", "_2")
        local savedTexture = self.savedOutfit[textureKey] or 0
        if savedDrawable then
            SetPedComponentVariation(ped, drawableId, savedDrawable, savedTexture, 2)
        end
    end

    self.savedOutfit = nil
end

function Prison.teleportToPrison(self, coords)
    local targetCoords = coords
    if not targetCoords and Prison.Map then
        targetCoords = Prison.Map.location.spawn
    end

    DoScreenFadeOut(500)
    Wait(500)
    SetEntityCoords(cache.ped, targetCoords.x, targetCoords.y, targetCoords.z, false, false, false, true)
    SetEntityHeading(cache.ped, targetCoords.w or 0.0)
    Wait(700)
    DoScreenFadeIn(500)
end

function Prison.pushJailHud(self)
    if not self.isInPrison or not self.sentenceData then
        SendNUIMessage({ action = "setVisibleJailHud", data = false })
        return
    end

    if self.hudHidden then
        SendNUIMessage({ action = "setVisibleJailHud", data = false })
        return
    end

    local cellLabel = "General Population"
    if self.cellId and Prison.Map and Prison.Map.cells then
        for _, cell in ipairs(Prison.Map.cells) do
            if cell.id == self.cellId then
                cellLabel = cell.label or cellLabel
                break
            end
        end
    end

    local remaining = self.sentenceData.remaining or 0
    local isLife = remaining == -1
    local isCommunity = self.sentenceData.isCommunityService == true
    local sentenceType = isLife and "life" or (isCommunity and "community" or "prison")

    SendNUIMessage({ action = "setVisibleJailHud", data = true })
    SendNUIMessage({
        action = "setJailHudData",
        data = {
            prisonerName = self.sentenceData.playerName,
            officerName = self.sentenceData.officerName,
            reason = self.sentenceData.reason,
            cellLabel = cellLabel,
            sentenceType = sentenceType,
            totalSeconds = self.sentenceData.sentenceTime or 0,
            remainingSeconds = isLife and -1 or math.max(0, remaining),
        },
    })
end

function Prison.enter(self, sentenceData)
    if self.isInPrison then
        return
    end

    self.isInPrison = true
    self.sentenceData = sentenceData
    self.cellId = sentenceData.cellId

    LocalPlayer.state:set("isInPrison", true, true)
    LocalPlayer.state:set("prisonSentence", sentenceData.remaining, true)

    RemoveAllPedWeapons(cache.ped, true)
    self:applyPrisonOutfit()

    local cellCoords, cellLabel
    if self.cellId and Prison.Map and Prison.Map.cells then
        for _, cell in ipairs(Prison.Map.cells) do
            if cell.id == self.cellId then
                cellCoords = cell.coords
                cellLabel = cell.label
                break
            end
        end
    end

    self:teleportToPrison(sentenceData.solitaryCoords or cellCoords)

    local isLife = sentenceData.remaining == -1
    local minutes = math.ceil((sentenceData.remaining or sentenceData.sentenceTime or 0) / 60)
    local durationLabel = isLife and locale("prison_life_sentence_label") or locale("prison_minutes", minutes)
    local cellName = cellLabel or locale("prison_general_population")
    local officerName = sentenceData.officerName or locale("prison_unknown")

    lib.alertDialog({
        header = locale("prison_alert_jailed_header"),
        content = locale("prison_alert_jailed_body", sentenceData.reason or locale("prison_no_reason"), durationLabel, cellName, officerName),
        centered = true,
        cancel = false,
    })

    self:pushJailHud()

    if LocalPlayer.state.isCuffed then
        Wait(1000)
        if Interactions then
            Interactions.isCuffed = false
            Interactions:destroyCuffProp()
        end
        LocalPlayer.state:set("isCuffed", false, true)
        LocalPlayer.state:set("cuffType", "none", true)
        ClearPedTasks(cache.ped)
    end

    if Config.Prison.onPlayerJailed then
        Config.Prison.onPlayerJailed(cache.serverId, sentenceData)
    end

    Bridge.Debug("[Prison] Player entered prison, sentence: " .. tostring(sentenceData.remaining) .. "s")
end

function Prison.release(self)
    if not self.isInPrison then
        return
    end

    self.isInPrison = false
    self.sentenceData = nil
    self.cellId = nil

    LocalPlayer.state:set("isInPrison", false, true)
    LocalPlayer.state:set("prisonSentence", 0, true)

    self:restoreOutfit()
    self:teleportToPrison(Prison.Map and Prison.Map.location.release)

    SendNUIMessage({ action = "setPrisonTime", data = { remaining = 0 } })
    SendNUIMessage({ action = "setVisibleJailHud", data = false })

    Bridge.Notify.showNotify(locale("prison_released"), "success")

    if Config.Prison.onPlayerReleased then
        Config.Prison.onPlayerReleased(cache.serverId)
    end

    Bridge.Debug("[Prison] Player released from prison")
end

RegisterNetEvent("p_policejob/client/prison/enter", function(sentenceData)
    if not sentenceData or type(sentenceData) ~= "table" then
        return
    end
    Prison:enter(sentenceData)
end)

RegisterNetEvent("p_policejob/client/prison/release", function()
    Prison:release()
end)

RegisterNetEvent("p_policejob/client/prison/escaped", function()
    if not Prison.isInPrison then
        return
    end

    Prison.isInPrison = false
    Prison.sentenceData = nil
    Prison.cellId = nil

    LocalPlayer.state:set("isInPrison", false, true)
    LocalPlayer.state:set("prisonSentence", 0, true)

    SendNUIMessage({ action = "setPrisonTime", data = { remaining = 0 } })
    SendNUIMessage({ action = "setVisibleJailHud", data = false })

    Bridge.Debug("[Prison] Player escaped from prison")
end)

RegisterNetEvent("p_policejob/client/prison/updateSentence", function(remaining, sentenceTime)
    if not Prison.isInPrison then
        return
    end

    if Prison.sentenceData then
        Prison.sentenceData.remaining = remaining
        if sentenceTime then
            Prison.sentenceData.sentenceTime = sentenceTime
        end
    end

    LocalPlayer.state:set("prisonSentence", remaining, true)
    SendNUIMessage({ action = "setPrisonTime", data = { remaining = remaining } })
    Prison:pushJailHud()
end)

RegisterNetEvent("p_policejob/client/prison/moveToCell", function(cellId)
    if not Prison.isInPrison then
        return
    end

    Prison.cellId = cellId
    if not Prison.Map or not Prison.Map.cells then
        return
    end

    for _, cell in ipairs(Prison.Map.cells) do
        if cell.id == cellId then
            Prison:teleportToPrison(cell.coords)
            Bridge.Notify.showNotify(locale("prison_moved_to_cell", cell.label), "info")
            Prison:pushJailHud()
            break
        end
    end
end)

RegisterNetEvent("p_policejob/client/prison/moveToSolitary", function(solitaryCoords)
    if not Prison.isInPrison then
        return
    end

    local coords = solitaryCoords
    if not coords and Prison.Map and Prison.Map.solitary then
        local solitary = Prison.Map.solitary
        coords = solitary.x and solitary or solitary[1]
    end

    if not coords then
        return
    end

    Prison:teleportToPrison(coords)
    Bridge.Notify.showNotify(locale("prison_sent_to_solitary"), "error")
end)

RegisterNetEvent("p_policejob/client/prison/restoreState", function(sentenceData)
    if sentenceData and sentenceData.remaining and sentenceData.remaining > 0 then
        Prison:enter(sentenceData)
    end
end)

exports("isInPrison", function()
    return Prison.isInPrison
end)

exports("getPrisonSentence", function()
    return Prison.sentenceData
end)

RegisterCommand("jailhud", function()
    if not Prison.isInPrison then
        return
    end
    Prison.hudHidden = not Prison.hudHidden
    Prison:pushJailHud()
end, false)

RegisterKeyMapping("jailhud", "Toggle Jail HUD", "keyboard", "F10")
