-- ============================================================
-- cm-family | cl_invites.lua | v1.1.4
-- Immediate top-screen family invitation prompt.
-- Y accepts, N declines. Uses a server event + acknowledgement instead of a
-- blocking callback so both response paths always complete visibly.
-- ============================================================

local activeInvite
local respondingInvite
local pendingRequestToken
local responseSequence = 0

local function cleanText(value, fallback)
    local text = tostring(value or fallback or '')
    text = text:gsub('~', ''):gsub('[\r\n]', ' ')
    return text
end

local function notify(message, kind)
    message = tostring(message or '')
    kind = kind or 'inform'
    if lib and type(lib.notify) == 'function' then
        lib.notify({
            title = 'Family',
            description = message,
            type = kind == 'inform' and 'inform' or kind,
        })
        return
    end
    TriggerEvent('cm-playerdata:client:interactionNotify', message, kind)
end

local function hexToRgb(hex)
    hex = tostring(hex or '#00f0ff'):gsub('#', '')
    if #hex ~= 6 then return 0, 240, 255 end
    return tonumber(hex:sub(1, 2), 16) or 0,
           tonumber(hex:sub(3, 4), 16) or 240,
           tonumber(hex:sub(5, 6), 16) or 255
end

local function drawText(text, x, y, scale, r, g, b, a, centre)
    SetTextFont(4)
    SetTextScale(scale, scale)
    SetTextColour(r, g, b, a)
    SetTextCentre(centre == true)
    SetTextOutline()
    SetTextDropShadow()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

local function closePrompt(expectedInvite)
    -- Do not let a late response for an older invitation close a newer prompt.
    if expectedInvite and activeInvite ~= expectedInvite then
        if respondingInvite == expectedInvite then respondingInvite = nil end
        return false
    end

    local closingInvite = activeInvite
    activeInvite = nil
    if not expectedInvite or respondingInvite == expectedInvite or respondingInvite == closingInvite then
        respondingInvite = nil
        pendingRequestToken = nil
    end
    return true
end

local function newRequestToken(invite)
    responseSequence = responseSequence + 1
    return ('%s:%s:%s'):format(
        tostring(GetPlayerServerId(PlayerId())),
        tostring(GetGameTimer()),
        tostring(responseSequence)
    )
end

local function respond(accept)
    local invite = activeInvite
    if not invite or respondingInvite ~= nil then return end

    respondingInvite = invite
    invite.processing = true
    invite.processingAccept = accept == true

    local requestToken = newRequestToken(invite)
    pendingRequestToken = requestToken

    -- Do not use lib.callback.await here. The accept path performs more work than
    -- decline (membership insert, state sync, house refresh), and a stalled
    -- callback previously left the client with no result. The server always ACKs
    -- this request through cm-family:client:inviteResponse.
    TriggerServerEvent('cm-family:server:respondInvitePrompt', {
        requestToken = requestToken,
        inviteId = invite.inviteId,
        familyId = invite.familyId,
        accept = accept == true,
    })

    -- Fail visibly instead of leaving the prompt permanently locked if a server
    -- event is lost or the resource is restarted mid-request.
    SetTimeout(15000, function()
        if pendingRequestToken ~= requestToken then return end
        if respondingInvite ~= invite then return end

        pendingRequestToken = nil
        respondingInvite = nil
        if activeInvite == invite then
            invite.processing = false
            invite.processingAccept = nil
        end
        notify('The family invitation response timed out. Please try again.', 'error')
    end)
end

RegisterNetEvent('cm-family:client:inviteResponse', function(payload)
    payload = type(payload) == 'table' and payload or {}
    local requestToken = tostring(payload.requestToken or '')
    if requestToken == '' or requestToken ~= tostring(pendingRequestToken or '') then return end

    local invite = respondingInvite
    pendingRequestToken = nil

    -- A newer invitation may have replaced this one while the server was working.
    if not invite or activeInvite ~= invite then
        respondingInvite = nil
        return
    end

    local accepted = payload.accept == true
    if payload.ok == true then
        notify(accepted and 'Family invitation accepted.' or 'Family invitation declined.',
            accepted and 'success' or 'inform')
        closePrompt(invite)
        return
    end

    respondingInvite = nil
    invite.processing = false
    invite.processingAccept = nil

    local reason = tostring(payload.reason or 'Family invitation failed.')
    notify(reason, 'error')

    local lowerReason = reason:lower()
    if lowerReason:find('expired', 1, true)
        or lowerReason:find('no pending', 1, true)
        or lowerReason:find('already in a family', 1, true) then
        closePrompt(invite)
    end
end)

RegisterNetEvent('cm-family:client:inviteReceived', function(data)
    data = type(data) == 'table' and data or {}
    local now = GetGameTimer()
    local seconds = math.max(5, tonumber(data.promptSeconds) or 30)
    activeInvite = {
        inviteId = data.inviteId,
        familyId = tonumber(data.familyId),
        familyName = cleanText(data.familyName, 'a family'),
        familyTag = cleanText(data.familyTag, ''),
        invitedBy = cleanText(data.invitedBy, 'A player'),
        color = data.color,
        expiresGameTimer = now + (seconds * 1000),
        processing = false,
    }
    respondingInvite = nil
    pendingRequestToken = nil
end)

-- Key mapping plus native-control polling. The mapping respects custom binds;
-- native polling guarantees the displayed default Y/N controls work immediately.
RegisterCommand('+cmfamily_accept_invite', function() respond(true) end, false)
RegisterCommand('-cmfamily_accept_invite', function() end, false)
RegisterCommand('+cmfamily_decline_invite', function() respond(false) end, false)
RegisterCommand('-cmfamily_decline_invite', function() end, false)
RegisterKeyMapping('+cmfamily_accept_invite', 'Accept family invitation', 'keyboard', 'Y')
RegisterKeyMapping('+cmfamily_decline_invite', 'Decline family invitation', 'keyboard', 'N')

-- Console/command fallbacks are useful if a player has previously rebound Y/N.
RegisterCommand('familyaccept', function() respond(true) end, false)
RegisterCommand('familydecline', function() respond(false) end, false)

CreateThread(function()
    while true do
        local invite = activeInvite
        if not invite then
            Wait(400)
        else
            Wait(0)

            invite = activeInvite
            if invite then
                if not invite.processing and GetGameTimer() >= invite.expiresGameTimer then
                    closePrompt(invite)
                else
                    DisableControlAction(0, 246, true) -- Y / team chat
                    DisableControlAction(0, 249, true) -- N / push-to-talk
                    DisableControlAction(2, 246, true)
                    DisableControlAction(2, 249, true)

                    local r, g, b = hexToRgb(invite.color)
                    local tag = invite.familyTag ~= '' and ('[' .. invite.familyTag .. '] ') or ''
                    local title = ('%s invited you to join %s%s'):format(
                        invite.invitedBy, tag, invite.familyName)
                    local remaining = math.max(0, math.ceil((invite.expiresGameTimer - GetGameTimer()) / 1000))

                    DrawRect(0.5, 0.105, 0.50, 0.090, 5, 11, 17, 220)
                    DrawRect(0.5, 0.061, 0.50, 0.004, r, g, b, 245)
                    drawText(title, 0.5, 0.073, 0.37, 245, 250, 255, 255, true)

                    if invite.processing then
                        drawText(invite.processingAccept and 'Accepting invitation…' or 'Declining invitation…',
                            0.5, 0.112, 0.31, 215, 226, 235, 255, true)
                    else
                        drawText(('Press ~y~Y~s~ to accept   •   Press ~r~N~s~ to decline   (%ds)'):format(remaining),
                            0.5, 0.112, 0.31, 215, 226, 235, 255, true)

                        -- JustPressed is used instead of JustReleased. Team-chat can
                        -- consume Y on release on some FiveM key configurations.
                        if IsDisabledControlJustPressed(0, 246)
                            or IsDisabledControlJustPressed(2, 246) then
                            respond(true)
                        elseif IsDisabledControlJustPressed(0, 249)
                            or IsDisabledControlJustPressed(2, 249) then
                            respond(false)
                        end
                    end
                end
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then closePrompt() end
end)
