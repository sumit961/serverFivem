if not Config.Bodycam.Enabled then
    return
end

Bodycam = {
    activeBodycams = {},
    watchers = {},
    recordings = {},
}

function isScreencaptureStarted()
    return GetResourceState("screencapture") == "started"
end

function Bodycam.stopRecording(self, targetId, watcherId)
    local recording = self.recordings[targetId]
    if not recording then
        return false
    end
    if watcherId and recording.watcherId ~= watcherId then
        return false
    end

    self.recordings[targetId] = nil

    if isScreencaptureStarted() then
        local ok, err = pcall(function()
            exports.screencapture:INTERNAL_stopServerCaptureStream(recording.watcherId)
        end)
        if not ok and Config.Debug then
            print(("[Bodycam] Failed to stop recording for %s: %s"):format(targetId, err))
        end
    end

    return true
end

function Bodycam.startRecording(self, targetId, watcherId)
    local recordingConfig = Config.Bodycam.Recording
    if not recordingConfig or not recordingConfig.Enabled then
        return false
    end
    if not isScreencaptureStarted() then
        Bridge.Debug("screencapture resource is not started - recording disabled")
        return false
    end
    if not self.activeBodycams[targetId] then
        return false
    end
    if self.recordings[targetId] then
        return false
    end

    local uploadConfig = BodycamRecordingConfig or {}
    if not uploadConfig.Url or uploadConfig.Url == "" then
        return false
    end

    self.recordings[targetId] = {
        watcherId = watcherId,
        startedAt = os.time(),
    }

    local streamOptions = {
        headers = {
            Authorization = uploadConfig.ApiKey or "",
        },
        formField = uploadConfig.FormField or "file",
        filename = ("bodycam_%s_%s"):format(targetId, os.time()),
        maxWidth = recordingConfig.MaxWidth or 1280,
        maxHeight = recordingConfig.MaxHeight or 720,
    }

    local ok, err = pcall(function()
        exports.screencapture:remoteUploadStream(watcherId, uploadConfig.Url, streamOptions, function(response)
            local url = uploadConfig.GetUrl and uploadConfig.GetUrl(response) or nil
            local targetName = Bridge.Framework.getPlayerName(targetId) or ("ID " .. tostring(targetId))
            local watcherName = watcherId and (
                Bridge.Framework.getPlayerName(watcherId) or ("ID " .. tostring(watcherId))
            ) or "Unknown"

            if url then
                if watcherId then
                    TriggerClientEvent("p_policejob/client/bodycam/recordingUploaded", watcherId, url)
                end
                Bridge.Logs.Send(
                    watcherId or targetId,
                    "Bodycam",
                    locale("bodycam_recording_log", watcherName, targetName, url),
                    Config.Webhooks.bodycam
                )
            else
                if watcherId then
                    TriggerClientEvent("p_policejob/client/bodycam/recordingFailed", watcherId)
                end
                if Config.Debug then
                    print(("[Bodycam] Recording upload failed for target %s"):format(targetId))
                end
            end
        end)
    end)

    if not ok then
        self.recordings[targetId] = nil
        if Config.Debug then
            print(("[Bodycam] Failed to start recording for %s: %s"):format(targetId, err))
        end
        return false
    end

    return true
end

function Bodycam.notifyWatchersToStop(self, targetId)
    local watchers = self.watchers[targetId]
    if not watchers then
        return
    end
    for watcherId in pairs(watchers) do
        TriggerClientEvent("p_policejob/client/bodycam/forceStopWatching", watcherId)
    end
    self.watchers[targetId] = nil
end

function Bodycam.addWatcher(self, targetId, watcherId)
    if not self.watchers[targetId] then
        self.watchers[targetId] = {}
    end
    self.watchers[targetId][watcherId] = true
end

function Bodycam.removeWatcher(self, targetId, watcherId)
    local watchers = self.watchers[targetId]
    if not watchers then
        return
    end
    watchers[watcherId] = nil
    if not next(watchers) then
        self.watchers[targetId] = nil
    end
end

function Bodycam.enable(self, playerId)
    local job = Bridge.Framework.getPlayerJob(playerId)
    if not Config.Jobs[job.name] then
        return Bridge.Notify.showNotify(playerId, locale("bodycam_not_allowed"), "error")
    end

    local bodycamData = {
        name = Bridge.Framework.getPlayerName(playerId),
        badge = "000",
        jobName = job.name,
    }

    self.activeBodycams[playerId] = bodycamData
    GlobalState["p_policejob/BodyCams"] = self.activeBodycams
    TriggerClientEvent("p_policejob/client/bodycam/toggle", playerId, true, bodycamData)
    Bridge.Logs.Send(playerId, "Bodycam", locale("player_enabled_bodycam"), Config.Webhooks.bodycam)
end

function Bodycam.disable(self, playerId)
    if not self.activeBodycams[playerId] then
        return
    end
    if self.recordings[playerId] then
        self:stopRecording(playerId)
    end
    self:notifyWatchersToStop(playerId)
    self.activeBodycams[playerId] = nil
    GlobalState["p_policejob/BodyCams"] = self.activeBodycams
    TriggerClientEvent("p_policejob/client/bodycam/toggle", playerId, false)
    Bridge.Logs.Send(playerId, "Bodycam", locale("player_disabled_bodycam"), Config.Webhooks.bodycam)
end

function Bodycam.toggle(self, playerId)
    if self.activeBodycams[playerId] then
        self:disable(playerId)
    else
        self:enable(playerId)
    end
end

function Bodycam.getList(self, playerId)
    local job = Bridge.Framework.getPlayerJob(playerId)
    if Config.Bodycam.jobRestricted then
        local filtered = {}
        for serverId, bodycamData in pairs(self.activeBodycams) do
            if bodycamData.jobName == job.name then
                filtered[serverId] = bodycamData
            end
        end
        return filtered
    end
    return self.activeBodycams
end

function Bodycam.getPlayerCoords(self, playerId)
    local ped = GetPlayerPed(playerId)
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        return false
    end
    return GetEntityCoords(ped)
end

exports("useBodyCamItem", function(playerId)
    Bodycam:toggle(playerId)
end)

exports("body_cam", function(event, item, inventory, slot, data)
    if event == "usingItem" then
        Bodycam:toggle(inventory.id)
    end
end)

RegisterNetEvent("p_policejob/server/bodycam/toggle", function()
    Bodycam:toggle(source)
end)

AddEventHandler("playerDropped", function()
    local playerId = source

    if Bodycam.recordings[playerId] then
        Bodycam:stopRecording(playerId)
    end

    for targetId, recording in pairs(Bodycam.recordings) do
        if recording.watcherId == playerId then
            Bodycam:stopRecording(targetId)
        end
    end

    if Bodycam.activeBodycams[playerId] then
        Bodycam:notifyWatchersToStop(playerId)
        Bodycam.activeBodycams[playerId] = nil
        GlobalState["p_policejob/BodyCams"] = Bodycam.activeBodycams
    end
end)

lib.callback.register("p_policejob/server/bodycam/startRecording", function(source, targetId)
    if not targetId or not Bodycam.watchers[targetId] or not Bodycam.watchers[targetId][source] then
        return false
    end
    return Bodycam:startRecording(targetId, source)
end)

RegisterNetEvent("p_policejob/server/bodycam/stopRecording", function(targetId)
    if not targetId then
        return
    end
    Bodycam:stopRecording(targetId, source)
end)

lib.callback.register("p_policejob/server/bodycam/fetchList", function(source)
    return Bodycam:getList(source)
end)

lib.callback.register("p_policejob/server/bodycam/fetchPlayerCoords", function(source, targetId)
    return Bodycam:getPlayerCoords(targetId)
end)

AddStateBagChangeHandler("isInBodycam", nil, function(bagName, _, value, _, replicated)
    if not bagName then
        return
    end

    local playerId = GetPlayerFromStateBagName(bagName)
    if not playerId then
        return
    end

    if value then
        Config.Bodycam.onStartWatching_Server(playerId)
        Bodycam:addWatcher(value, playerId)
        if Config.Debug then
            print(("[Bodycam] Player %s started watching bodycam of player %s"):format(playerId, value))
        end
    else
        Config.Bodycam.onStopWatching_Server(playerId)

        for targetId, recording in pairs(Bodycam.recordings) do
            if recording.watcherId == playerId then
                Bodycam:stopRecording(targetId)
            end
        end

        for targetId in pairs(Bodycam.watchers) do
            Bodycam:removeWatcher(targetId, playerId)
        end

        if Config.Debug then
            print(("[Bodycam] Player %s stopped watching bodycam"):format(playerId))
        end
    end
end)

if Bridge.Inventory.registerHook then
    Bridge.Inventory.registerHook("swapItems", function(payload)
        local fromInventory = payload.fromInventory
        if payload.action == "swap" or payload.action == "move" then
            if fromInventory ~= payload.toInventory and payload.fromType == "player" then
                if Bodycam.activeBodycams[fromInventory] then
                    Bodycam:disable(fromInventory)
                end
            end
        end
    end, {
        itemFilter = { body_cam = true },
    })
end
