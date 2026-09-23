-- cm-law/server/photos.lua
-- Shared photo-capture primitive for citizen ID photos, officer duty photos,
-- and incident-report scene photos.
--
-- SECURITY NOTE: this deliberately mirrors embedded/police/server/booking.lua's
-- existing captureBookingMugshot(), which saves the JPG to a LOCAL file inside
-- this resource's own html/ folder via screenshot-basic's
-- requestClientScreenshot -- never requestScreenshotUpload to a webhook. The
-- outside/mdt reference resource this feature set was inspired by shipped a
-- live, pre-filled Discord webhook that silently uploaded every captured
-- screenshot to a third party (see that resource's security review); nothing
-- here uploads anywhere. If an operator wants remote backup of these images
-- that is a deliberate, separately-configured choice, not a default.
--
-- Capture always happens on the TARGET's own client (matches how the
-- existing booking mugshot works: the subject's own client freezes their ped,
-- points a close-up camera at their own face, and screenshots their own
-- screen) -- callers are responsible for any distance/online checks before
-- calling this for a target other than the requesting officer themselves.

local function sanitizeSegment(value)
    return tostring(value or ''):gsub('[^%w_-]', ''):sub(1, 64)
end

-- folder: 'citizens' | 'officers' | 'reports' (must match an html/captures/<folder>/
-- entry declared in fxmanifest.lua's files{} wildcard list).
-- Returns a relative URL (e.g. 'captures/citizens/xxx.jpg') on success, or nil.
function LawCapturePhoto(targetSrc, folder, prefix)
    targetSrc = tonumber(targetSrc)
    if not targetSrc or not GetPlayerName(targetSrc) then return nil end
    if GetResourceState('screenshot-basic') ~= 'started' then return nil end
    folder = sanitizeSegment(folder)
    if folder == '' then return nil end
    local filename = ('%s_%d_%06d.jpg'):format(sanitizeSegment(prefix), os.time(), math.random(0, 999999))
    local relativeUrl = ('captures/%s/%s'):format(folder, filename)
    local absolutePath = ('%s/html/captures/%s/%s'):format(GetResourcePath(GetCurrentResourceName()), folder, filename)

    local result, resolved = promise.new(), false
    local function finish(ok) if not resolved then resolved = true; result:resolve(ok) end end
    TriggerClientEvent('cm-law:client:preparePhotoCapture', targetSrc, 3000)
    Wait(600)
    local requested = pcall(function()
        exports['screenshot-basic']:requestClientScreenshot(targetSrc, {
            fileName = absolutePath, encoding = 'jpg', quality = 0.85,
        }, function(err) finish(err == nil or err == false) end)
    end)
    if not requested then TriggerClientEvent('cm-law:client:endPhotoCapture', targetSrc); return nil end
    SetTimeout(5000, function() finish(false) end)
    local captured = Citizen.Await(result)
    TriggerClientEvent('cm-law:client:endPhotoCapture', targetSrc)
    Wait(150)
    if not captured then return nil end
    return relativeUrl
end
