while not Config or not Config.Scanner do
    Citizen.Wait(50)
end

if not Config.Scanner.enabled then
    return
end

function findMugshotByName(fullName)
    if not Config.Scanner.showMugshot then
        return nil
    end
    if not Mugshot or not Mugshot.records then
        return nil
    end
    local searchName = fullName:lower()
    for i = 1, #Mugshot.records do
        local record = Mugshot.records[i]
        if record.suspect and record.suspect:lower() == searchName then
            return record.url
        end
    end
    return nil
end

lib.callback.register("p_policejob/scanner/identify", function(source, targetId)
    targetId = tonumber(targetId)
    if not targetId or targetId == 0 then
        return false
    end
    local job = Bridge.Framework.getPlayerJob(source)
    if not job or not Config.Jobs[job.name] then
        return false
    end
    local scannerPed = GetPlayerPed(source)
    local targetPed = GetPlayerPed(targetId)
    if not targetPed or targetPed == 0 then
        return false
    end
    if #(GetEntityCoords(scannerPed) - GetEntityCoords(targetPed)) > Config.Scanner.maxDistance then
        return false
    end
    local firstName, lastName = Bridge.Framework.getPlayerName(targetId, true)
    if not firstName then
        return false
    end
    if not lastName then
        lastName = ""
    end
    local fullName = ("%s %s"):format(firstName, lastName):gsub("%s+$", "")
    local webhook = ""
    if Config.Webhooks then
        webhook = Config.Webhooks.scanner or Config.Webhooks.objects or ""
    end
    Bridge.Logs.Send(source, "Scanner", locale("scanner_log_identified", fullName), webhook)
    return {
        firstName = firstName,
        lastName = lastName,
        mugshot = findMugshotByName(fullName),
    }
end)

exports("getPlayerIdentity", function(playerId)
    playerId = tonumber(playerId)
    if not playerId or playerId == 0 then
        return nil
    end
    local firstName, lastName = Bridge.Framework.getPlayerName(playerId, true)
    if not firstName then
        return nil
    end
    if not lastName then
        lastName = ""
    end
    local fullName = ("%s %s"):format(firstName, lastName):gsub("%s+$", "")
    return {
        firstName = firstName,
        lastName = lastName,
        mugshot = findMugshotByName(fullName),
    }
end)
