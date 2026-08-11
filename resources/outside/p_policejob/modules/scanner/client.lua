while not Config or not Config.Scanner do
    Citizen.Wait(50)
end

if not Config.Scanner.enabled then
    return
end

Scanner = {
    busy = false,
    pending = nil,
}

function hasScannerJobAccess()
    local job = Bridge.Framework.fetchPlayerJob()
    if not job then
        return nil
    end
    return Config.Jobs[job.name]
end

function Scanner.close(self)
    self.pending = nil
    SendNUIMessage({
        action = "setVisibleScanner",
        data = false,
    })
    SetNuiFocus(false, false)
end

function Scanner.open(self, targetId, targetPed)
    if self.busy then
        return
    end
    if not hasScannerJobAccess() then
        return
    end
    targetId = tonumber(targetId)
    if not targetId or targetId == 0 then
        return
    end
    if targetPed and targetPed ~= 0 and DoesEntityExist(targetPed) then
        -- use provided ped
    else
        targetPed = GetPlayerPed(GetPlayerFromServerId(targetId))
    end
    if not targetPed or targetPed == 0 then
        return
    end
    if Config.Scanner.requireItem then
        if Bridge.Inventory.getItemCount(Config.Scanner.item) < 1 then
            return Bridge.Notify.showNotify(locale("scanner_no_device"), "error")
        end
    end
    self.pending = {
        targetId = targetId,
        targetPed = targetPed,
    }
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "setVisibleScanner",
        data = true,
    })
    SendNUIMessage({
        action = "setScannerData",
        data = { status = "idle" },
    })
end

function getMugshotForPed(ped)
    if not Config.Scanner.showMugshot then
        return nil
    end
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        return nil
    end
    if GetResourceState("MugShotBase64") ~= "started" then
        lib.print.error("MugShotBase64 resource is not started - the scanner cannot take a headshot of the target ped")
        return nil
    end
    local success, mugshot = pcall(function()
        return exports.MugShotBase64:GetMugShotBase64(ped, true)
    end)
    if success and type(mugshot) == "string" and mugshot ~= "" then
        return mugshot
    end
    return nil
end

function Scanner.runScan(self)
    if self.busy then
        return
    end
    local pending = self.pending
    if not pending then
        SendNUIMessage({
            action = "setScannerData",
            data = { status = "idle" },
        })
        return
    end
    self.busy = true
    local targetId = pending.targetId
    local targetPed = pending.targetPed
    if targetPed and targetPed ~= 0 and DoesEntityExist(targetPed) then
        -- use cached ped
    else
        targetPed = GetPlayerPed(GetPlayerFromServerId(targetId))
    end
    local gender = IsPedMale(targetPed) and "male" or "female"
    SendNUIMessage({
        action = "setScannerData",
        data = { status = "scanning" },
    })
    local scanAnim = Config.Scanner.scanAnim
    if scanAnim and scanAnim.dict then
        lib.requestAnimDict(scanAnim.dict)
        TaskPlayAnim(
            cache.ped, scanAnim.dict, scanAnim.clip,
            8.0, -8.0, Config.Scanner.scanDuration,
            scanAnim.flag or 1, 0, false, false, false
        )
    end
    Wait(Config.Scanner.scanDuration)
    if scanAnim and scanAnim.dict then
        ClearPedTasks(cache.ped)
        RemoveAnimDict(scanAnim.dict)
    end
    local identity = lib.callback.await("p_policejob/scanner/identify", false, targetId)
    if not identity then
        SendNUIMessage({
            action = "setScannerData",
            data = { status = "not_found" },
        })
        self.busy = false
        return
    end
    SendNUIMessage({
        action = "setScannerData",
        data = {
            status = "complete",
            firstName = identity.firstName,
            lastName = identity.lastName,
            gender = gender,
            mugshot = getMugshotForPed(targetPed) or identity.mugshot,
        },
    })
    self.busy = false
end

AddEventHandler("p_policejob/scanner/scan", function(targetId, targetPed)
    Scanner:open(targetId, targetPed)
end)

RegisterNUICallback("scanner/start", function(_, cb)
    cb("ok")
    CreateThread(function()
        Scanner:runScan()
    end)
end)

RegisterNUICallback("hideFrame", function(data, cb)
    if data and data.name == "setVisibleScanner" then
        Scanner:close()
    end
    cb("ok")
end)

exports("scanFingerprint", function(targetId)
    Scanner:open(targetId)
end)
