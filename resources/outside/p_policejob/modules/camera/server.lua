while not Config or not Config.Camera do
    Citizen.Wait(500)
end

if not Config.Camera.Enabled then
    return
end

RegisterNetEvent("p_policejob/server/camera/TakePhoto", function(photoUrl)
    local playerId = source
    local job = Bridge.Framework.getPlayerJob(playerId)

    if Config.Camera.CameraAccess then
        local requiredGrade = Config.Camera.CameraAccess[job.name]
        if not requiredGrade or requiredGrade > job.grade then
            return Bridge.Notify.showNotify(playerId, locale("camera_item_no_access"), "error")
        end
    end

    local playerName = Bridge.Framework.getPlayerName(playerId)
    local uniqueId = Bridge.Framework.getUniqueId(playerId)
    local timestamp = os.time()

    local metadata = {
        url = photoUrl,
        playerName = playerName,
        playerIdentifier = uniqueId,
        jobName = job.name,
        jobGrade = job.grade,
        timestamp = timestamp,
    }

    local description = locale(
        "camera_photo_description",
        playerName,
        job.name,
        os.date("%Y-%m-%d %H:%M", timestamp)
    )

    Bridge.Inventory.addItem(playerId, "photo", 1, metadata, nil, description)
    Bridge.Notify.showNotify(playerId, locale("photo_taken"), "success")
    Bridge.Debug(("[Camera] Player %s took a photo (url=%s)"):format(playerId, tostring(photoUrl)))

    if Config.Webhooks and Config.Webhooks.camera then
        Bridge.Logs.Send(
            playerId,
            "Camera",
            ("Photo taken by %s"):format(playerName),
            Config.Webhooks.camera
        )
    end
end)

lib.callback.register("p_policejob/server/screenshot/uploadTarget", function(source)
    if not ScreenshotConfig or not ScreenshotConfig.Url or ScreenshotConfig.Url == "" then
        return nil
    end
    if not ScreenshotConfig.ClientUpload then
        return { clientUpload = false }
    end

    if ScreenshotConfig.ApiKey and ScreenshotConfig.ApiKey ~= "" then
        local apiKey = tostring(ScreenshotConfig.ApiKey)
        if not apiKey:find("KEY_HERE") then
            return {
                clientUpload = true,
                url = ScreenshotConfig.Url,
                field = ScreenshotConfig.Field or "file",
                encoding = ScreenshotConfig.Encoding or "jpg",
                quality = ScreenshotConfig.Quality or 0.85,
                headers = { Authorization = ScreenshotConfig.ApiKey },
            }
        end
    end

    print("^8[ERROR] MEDIA PROVIDER API KEY NOT SET - edit MediaProvider/ApiKey in config/server.lua^7")
    return nil
end)

lib.callback.register("p_policejob/server/screenshot/resolveUrl", function(source, response)
    if type(response) ~= "string" or response == "" then
        return nil
    end

    local url = ScreenshotConfig.GetUrl(response)
    if type(url) == "string" and url:match("^https://") then
        Bridge.Debug(("[Camera] Client uploaded screenshot for player %s -> %s"):format(source, url))
        return url
    end

    Bridge.Debug(("[Camera] Client upload response could not be resolved to a URL: %s"):format(response:sub(1, 120)))
    return nil
end)

lib.callback.register("p_policejob/server/screenshotCapture", function(source)
    local capturePromise = promise.new()

    if not ScreenshotConfig or not ScreenshotConfig.Url or ScreenshotConfig.Url == "" then
        print("^8[ERROR] SET SCREENSHOT UPLOAD URL IN ScreenshotConfig (config/server.lua)^7")
        return nil
    end

    if not ScreenshotConfig.ApiKey or ScreenshotConfig.ApiKey == "" then
        print("^8[ERROR] MEDIA PROVIDER API KEY NOT SET - edit MediaProvider/ApiKey in config/server.lua^7")
        return nil
    end

    local apiKey = tostring(ScreenshotConfig.ApiKey)
    if apiKey:find("KEY_HERE") then
        print("^8[ERROR] MEDIA PROVIDER API KEY NOT SET - edit MediaProvider/ApiKey in config/server.lua^7")
        return nil
    end

    local encoding = ScreenshotConfig.Encoding or "jpg"

    exports["screenshot-basic"]:requestClientScreenshot(source, {
        encoding = encoding,
        quality = ScreenshotConfig.Quality or 0.85,
    }, function(errorMessage, screenshotData)
        if errorMessage then
            print("^8[ERROR] FAILED TO CAPTURE SCREENSHOT: " .. tostring(errorMessage) .. "^7")
            capturePromise:resolve(nil)
            return
        end

        if not screenshotData or screenshotData == "" then
            print("^8[ERROR] SCREENSHOT DATA EMPTY - is the `screenshot-basic` resource started before p_policejob?^7")
            capturePromise:resolve(nil)
            return
        end

        screenshotData = screenshotData:gsub("^data:image/[%w%+%-.]+;base64,", "")
        Bridge.Debug(("[Camera] Screenshot captured (%d base64 bytes)"):format(#screenshotData))

        local requestBody, contentType
        if ScreenshotConfig.BuildRequest then
            requestBody, contentType = ScreenshotConfig.BuildRequest(screenshotData, encoding)
        else
            requestBody = json.encode({ base64 = screenshotData })
            contentType = "application/json"
        end

        Bridge.Debug(("[Camera] Uploading %s (%d body bytes) to %s"):format(
            encoding, #requestBody, tostring(ScreenshotConfig.Url)
        ))

        PerformHttpRequest(ScreenshotConfig.Url, function(statusCode, responseBody)
            if statusCode == 200 then
                local url = ScreenshotConfig.GetUrl(responseBody)
                Bridge.Debug(("[Camera] Screenshot uploaded for player %s -> %s"):format(source, tostring(url)))
                capturePromise:resolve(url)
            else
                print("^8[ERROR] SCREENSHOT UPLOAD FAILED (" .. statusCode .. "): " .. tostring(responseBody) .. "^7")
                Bridge.Debug(("[Camera] Screenshot upload failed (status=%s)"):format(statusCode))
                capturePromise:resolve(nil)
            end
        end, "POST", requestBody, {
            ["Content-Type"] = contentType,
            Authorization = ScreenshotConfig.ApiKey,
        })
    end)

    return Citizen.Await(capturePromise)
end)

exports("photo", function(event, item, inventory, slot, data)
    if event == "usingItem" then
        local itemSlot = Bridge.Inventory.getItemSlot(inventory.id, slot)
        if itemSlot and itemSlot.metadata and itemSlot.metadata.url then
            TriggerClientEvent(
                "p_policejob/client/camera/ShowPhoto",
                inventory.id,
                itemSlot.metadata.url
            )
        end
    end
end)
