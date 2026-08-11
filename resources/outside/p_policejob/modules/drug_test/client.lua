while not Config or not Config.DrugTestKit do
    Citizen.Wait(500)
end

if not Config.DrugTestKit.enabled then
    return
end

DrugTestKit = {
    isOpen = false,
    targetId = nil,
    awaitingConsent = false,
}

function DrugTestKit.requestConsentDialog(officerName)
    local response = lib.alertDialog({
        header = locale("drug_test_consent_header"),
        content = locale("drug_test_consent_content"):format(officerName or "?"),
        centered = true,
        cancel = true,
        labels = {
            confirm = locale("drug_test_consent_accept"),
            cancel = locale("drug_test_consent_decline"),
        },
    })
    return response == "confirm"
end

function DrugTestKit.hasJobAccess(self)
    local job = Bridge.Framework.fetchPlayerJob()
    if not job or not job.name then
        return false
    end
    local requiredGrade = Config.Jobs[job.name]
    if requiredGrade == nil then
        return false
    end
    if requiredGrade == true then
        return true
    end
    local grade = job.grade or 0
    local minimumGrade = tonumber(requiredGrade) or 0
    return grade >= minimumGrade
end

function DrugTestKit.getClosestTarget(self)
    local closestPlayer = lib.getClosestPlayer(GetEntityCoords(cache.ped), Config.DrugTestKit.maxDistance, false)
    if not closestPlayer or closestPlayer == 0 then
        return nil
    end
    local serverId = GetPlayerServerId(closestPlayer)
    if serverId == cache.serverId then
        return nil
    end
    return serverId
end

function DrugTestKit.getTargetName(self, targetId)
    local playerId = GetPlayerFromServerId(targetId)
    if playerId and playerId ~= -1 then
        local name = GetPlayerName(playerId)
        if name and name ~= "" then
            return name
        end
    end
    return ("ID %s"):format(targetId)
end

function DrugTestKit.open(self, targetId)
    if not self:hasJobAccess() then
        return Bridge.Notify.showNotify(locale("no_access_drug_test_kit"), "error")
    end
    targetId = targetId or self:getClosestTarget()
    if not targetId then
        return Bridge.Notify.showNotify(locale("no_player_nearby"), "error")
    end
    self.targetId = targetId
    self.isOpen = true
    Config.DrugTestKit.onOpen(self.targetId)
    local officerName = GetPlayerName(PlayerId()) or ("ID %s"):format(cache.serverId)
    SendNUIMessage({
        action = "setDrugTestKitData",
        data = {
            status = "idle",
            officerName = officerName,
            targetId = self.targetId,
            targetName = self:getTargetName(self.targetId),
            positive = false,
            substances = {},
            details = {},
            testDuration = Config.DrugTestKit.testDuration or 6000,
        },
    })
    SendNUIMessage({ action = "setVisibleDrugTestKit", data = true })
    SetNuiFocus(true, true)
end

function DrugTestKit.close(self)
    if not self.isOpen then
        return
    end
    Config.DrugTestKit.onClose(self.targetId)
    self.isOpen = false
    self.targetId = nil
    SendNUIMessage({ action = "setVisibleDrugTestKit", data = false })
    SetNuiFocus(false, false)
end

function DrugTestKit.showResults(self, targetId, results)
    local options = {
        {
            title = locale("drug_test_result_target"),
            description = self:getTargetName(targetId) or ("ID %s"):format(targetId),
            icon = "user",
            readOnly = true,
        },
        {
            title = locale("drug_test_result_status"),
            description = results.positive and locale("drug_test_result_positive") or locale("drug_test_result_negative"),
            icon = results.positive and "triangle-exclamation" or "check",
            iconColor = results.positive and "#ff5d5d" or "#5dd9a4",
            readOnly = true,
        },
    }
    local substances = results.substances or {}
    if #substances > 0 then
        for _, substance in ipairs(substances) do
            options[#options + 1] = {
                title = tostring(substance),
                icon = "flask",
                iconColor = "#ff5d5d",
                readOnly = true,
            }
        end
    elseif results.positive then
        options[#options + 1] = {
            title = locale("drug_test_result_unknown"),
            icon = "circle-question",
            readOnly = true,
        }
    else
        options[#options + 1] = {
            title = locale("drug_test_result_no_substances"),
            icon = "check",
            readOnly = true,
        }
    end
    if type(results.details) == "table" then
        for key, value in pairs(results.details) do
            if value ~= nil then
                options[#options + 1] = {
                    title = tostring(key),
                    description = tostring(value),
                    icon = "circle-info",
                    readOnly = true,
                }
            end
        end
    end
    lib.registerContext({
        id = "p_policejob_drug_test_result",
        title = locale("drug_test_result_title"),
        options = options,
    })
    lib.showContext("p_policejob_drug_test_result")
end

function DrugTestKit.runTargetTest(self, targetId)
    if not self:hasJobAccess() then
        return Bridge.Notify.showNotify(locale("no_access_drug_test_kit"), "error")
    end
    targetId = tonumber(targetId)
    if not targetId then
        return Bridge.Notify.showNotify(locale("no_player_nearby"), "error")
    end
    if self.awaitingConsent then
        return Bridge.Notify.showNotify(locale("drug_test_pending"), "error")
    end
    self.targetId = targetId
    self.awaitingConsent = true
    TriggerServerEvent("p_policejob/server/drugtest/requestConsent", targetId)
end

function DrugTestKit.onConsentResult(self, targetId, accepted)
    self.awaitingConsent = false
    targetId = tonumber(targetId)
    if not targetId then
        self.targetId = nil
        return
    end
    if not accepted then
        Bridge.Notify.showNotify(locale("drug_test_declined"), "error")
        self.targetId = nil
        return
    end
    self.targetId = targetId
    Config.DrugTestKit.onTestStart(targetId)
    if not Bridge.Progress.Start({
        duration = Config.DrugTestKit.testDuration or 6000,
        label = locale("performing_drug_test"),
        useWhileDead = false,
        canCancel = true,
        disable = { car = true, move = true, combat = true },
        anim = Config.DrugTestKit.progressAnim,
    }) then
        self.targetId = nil
        return
    end
    local results = lib.callback.await("p_policejob/server/drugtest/start", false, targetId)
    if not results then
        self.targetId = nil
        return
    end
    Config.DrugTestKit.onTestComplete(targetId, results)
    self:showResults(targetId, results)
    self.targetId = nil
end

function DrugTestKit.startTest(self)
    if not self.targetId then
        Bridge.Notify.showNotify(locale("no_player_nearby"), "error")
        return nil
    end
    Config.DrugTestKit.onTestStart(self.targetId)
    SendNUIMessage({
        action = "setDrugTestKitData",
        data = {
            status = "testing",
            targetId = self.targetId,
            targetName = self:getTargetName(self.targetId),
        },
    })
    local results = lib.callback.await("p_policejob/server/drugtest/start", false, self.targetId)
    if not results then
        SendNUIMessage({
            action = "setDrugTestKitData",
            data = {
                status = "idle",
                targetId = self.targetId,
                targetName = self:getTargetName(self.targetId),
            },
        })
        return nil
    end
    local payload = {
        status = "complete",
        targetId = self.targetId,
        targetName = self:getTargetName(self.targetId),
        positive = results.positive == true,
        substances = results.substances or {},
        details = results.details or {},
    }
    Config.DrugTestKit.onTestComplete(self.targetId, payload)
    SendNUIMessage({ action = "setDrugTestKitData", data = payload })
    return payload
end

exports("OpenDrugTestKit", function(targetId)
    DrugTestKit:open(targetId)
end)

exports("useDrugTestKit", function(targetId)
    DrugTestKit:open(targetId)
end)

exports("runDrugTestTarget", function(targetId)
    DrugTestKit:runTargetTest(targetId)
end)

RegisterNUICallback("drugtest:start", function(_, cb)
    local results = DrugTestKit:startTest()
    cb(results or { success = false })
end)

RegisterNUICallback("drugtest:reset", function(_, cb)
    if not DrugTestKit.targetId then
        cb({ success = false })
        return
    end
    SendNUIMessage({
        action = "setDrugTestKitData",
        data = {
            status = "idle",
            targetId = DrugTestKit.targetId,
            targetName = DrugTestKit:getTargetName(DrugTestKit.targetId),
            positive = false,
            substances = {},
            details = {},
        },
    })
    cb({ success = true })
end)

RegisterNUICallback("drugtest:close", function(_, cb)
    DrugTestKit:close()
    cb({ success = true })
end)

RegisterNUICallback("hideFrame", function(data, cb)
    if data and data.name == "setVisibleDrugTestKit" then
        DrugTestKit:close()
    end
    cb("ok")
end)

RegisterNetEvent("p_policejob/client/drugtest/open", function(targetId)
    DrugTestKit:open(targetId)
end)

RegisterNetEvent("p_policejob/client/drugtest/close", function()
    DrugTestKit:close()
end)

RegisterNetEvent("p_policejob/client/drugtest/consentPrompt", function(officerName)
    local accepted = DrugTestKit.requestConsentDialog(officerName)
    TriggerServerEvent("p_policejob/server/drugtest/consentResponse", accepted)
end)

RegisterNetEvent("p_policejob/client/drugtest/consentResult", function(targetId, accepted)
    DrugTestKit:onConsentResult(targetId, accepted)
end)

lib.callback.register("p_policejob/client/drugtest/requestConsent", function(officerName)
    return DrugTestKit.requestConsentDialog(officerName)
end)
