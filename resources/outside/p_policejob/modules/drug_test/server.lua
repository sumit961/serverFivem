if not Config or not Config.DrugTestKit or not Config.DrugTestKit.enabled then
    return
end

DrugTestKit = {}

function DrugTestKit.hasJobAccess(playerId)
    local job = Bridge.Framework.getPlayerJob(playerId)
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

function DrugTestKit.normalizeResults(rawResults)
    local results = {
        positive = false,
        substances = {},
        details = {},
    }
    local resultType = type(rawResults)
    if resultType == "boolean" then
        results.positive = rawResults
    elseif resultType == "string" and rawResults ~= "" then
        results.positive = true
        results.substances = { rawResults }
    elseif resultType == "table" then
        results.positive = rawResults.positive == true
        if type(rawResults.substances) == "table" then
            for _, substance in ipairs(rawResults.substances) do
                if type(substance) == "string" and substance ~= "" then
                    results.substances[#results.substances + 1] = substance
                end
            end
        elseif type(rawResults.substance) == "string" and rawResults.substance ~= "" then
            results.substances = { rawResults.substance }
        end
        if type(rawResults.details) == "table" then
            results.details = rawResults.details
        end
        if not results.positive and #results.substances > 0 then
            results.positive = true
        end
    end
    return results
end

function DrugTestKit.use(self, playerId, targetId)
    if not DrugTestKit.hasJobAccess(playerId) then
        return Bridge.Notify.showNotify(playerId, locale("no_access_drug_test_kit"), "error")
    end
    local targetServerId = tonumber(targetId)
    if targetServerId and targetServerId ~= playerId and Config.DrugTestKit.requireConsent then
        local officerName = Bridge.Framework.getPlayerName and Bridge.Framework.getPlayerName(playerId) or ("ID " .. tostring(playerId))
        Bridge.Notify.showNotify(playerId, locale("test_request_sent"), "inform")
        local accepted = lib.callback.await("p_policejob/client/drugtest/requestConsent", targetServerId, officerName)
        if not accepted then
            return Bridge.Notify.showNotify(playerId, locale("drug_test_declined"), "error")
        end
    end
    TriggerClientEvent("p_policejob/client/drugtest/open", playerId, targetId)
end

function DrugTestKit.startTest(self, playerId, targetId)
    if not DrugTestKit.hasJobAccess(playerId) then
        Bridge.Notify.showNotify(playerId, locale("no_access_drug_test_kit"), "error")
        return nil
    end
    if not Editable:canInteract(playerId, targetId, Config.DrugTestKit.maxDistance) then
        Bridge.Notify.showNotify(playerId, locale("no_player_nearby"), "error")
        return nil
    end
    Config.DrugTestKit.onTestStart_Server(playerId, targetId)
    if Config.DrugTestKit.notifyTarget then
        local targetServerId = tonumber(targetId)
        if targetServerId and targetServerId ~= playerId then
            Bridge.Notify.showNotify(targetServerId, locale("drug_test_target_started"), "inform")
        end
    end
    local success, rawResults = pcall(Config.DrugTestKit.getDrugTestResults, targetId, playerId)
    if not success then
        Bridge.Debug(("[DrugTestKit] getDrugTestResults failed: %s"):format(rawResults))
        rawResults = {
            positive = false,
            substances = {},
            details = { error = "integration_failed" },
        }
    end
    local results = DrugTestKit.normalizeResults(rawResults)
    Config.DrugTestKit.onTestComplete_Server(playerId, targetId, results)
    if Config.DrugTestKit.notifyTarget then
        local targetServerId = tonumber(targetId)
        if targetServerId and targetServerId ~= playerId then
            local message = results.positive and locale("drug_test_target_positive") or locale("drug_test_target_negative")
            local notifyType = results.positive and "error" or "success"
            Bridge.Notify.showNotify(targetServerId, message, notifyType)
        end
    end
    return results
end

exports("useDrugTestKitItem", function(playerId, targetId)
    DrugTestKit:use(playerId, targetId)
end)

exports("drug_test_kit", function(eventName, _, playerData)
    if eventName == "usingItem" then
        DrugTestKit:use(playerData.id)
    end
end)

RegisterNetEvent("p_policejob/server/drugtest/use", function(targetId)
    DrugTestKit:use(source, targetId)
end)

lib.callback.register("p_policejob/server/drugtest/start", function(playerId, targetId)
    return DrugTestKit:startTest(playerId, targetId)
end)

local pendingConsent = {}

RegisterNetEvent("p_policejob/server/drugtest/requestConsent", function(targetId)
    local playerId = source
    if not DrugTestKit.hasJobAccess(playerId) then
        return
    end
    local targetServerId = tonumber(targetId)
    if not targetServerId then
        return Bridge.Notify.showNotify(playerId, locale("no_player_nearby"), "error")
    end
    if not Editable:canInteract(playerId, targetServerId, Config.DrugTestKit.maxDistance) then
        return Bridge.Notify.showNotify(playerId, locale("no_player_nearby"), "error")
    end
    if targetServerId == playerId or not Config.DrugTestKit.requireConsent then
        return TriggerClientEvent("p_policejob/client/drugtest/consentResult", playerId, targetServerId, true)
    end
    pendingConsent[targetServerId] = playerId
    local officerName = Bridge.Framework.getPlayerName and Bridge.Framework.getPlayerName(playerId) or ("ID " .. tostring(playerId))
    Bridge.Notify.showNotify(playerId, locale("test_request_sent"), "inform")
    TriggerClientEvent("p_policejob/client/drugtest/consentPrompt", targetServerId, officerName)
end)

RegisterNetEvent("p_policejob/server/drugtest/consentResponse", function(accepted)
    local targetId = source
    local officerId = pendingConsent[targetId]
    if not officerId then
        return
    end
    pendingConsent[targetId] = nil
    TriggerClientEvent("p_policejob/client/drugtest/consentResult", officerId, targetId, accepted == true)
end)

AddEventHandler("playerDropped", function()
    local playerId = source
    pendingConsent[playerId] = nil
    for targetId, officerId in pairs(pendingConsent) do
        if officerId == playerId then
            pendingConsent[targetId] = nil
        end
    end
end)
