-- cm-mechanic client: a small mechanic work panel (NUI) and the customer's quote confirmation (cm-ui).
-- Presentation only. The server resolves the work order from the character, the business, the vehicle identity, the price and the
-- completion; the client merely supplies "the vehicle I am standing next to" (a handle the server re-validates) and runs the progress bar.
local panelOpen = false
local busy = false
local quotePrompt = false

local function hudNotify(message, kind)
    TriggerEvent('cm-hud:client:notify', message, kind or 'info')
end

local function money(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    return '$' .. s:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
end

-- The vehicle the mechanic is next to (or sitting in). Returns netId, entity or nil.
local function nearbyVehicle()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then
        local c = GetEntityCoords(ped)
        veh = GetClosestVehicle(c.x, c.y, c.z, 8.0, 0, 71)
    end
    if veh == 0 or not DoesEntityExist(veh) or not NetworkGetEntityIsNetworked(veh) then return nil, 0 end
    return NetworkGetNetworkIdFromEntity(veh), veh
end

local function sendState(data)
    SendNUIMessage({ action = 'state', data = data })
end

local function refresh()
    local res = lib.callback.await('cm-mechanic:state', false)
    sendState(res)
    return res
end

local function closePanel()
    if not panelOpen then return end
    panelOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function openPanel()
    if panelOpen then return end
    local res = lib.callback.await('cm-mechanic:state', false)
    if not res or res.ok ~= true then
        hudNotify(res and res.error == 'not_mechanic' and 'You are not a mechanic at any workshop.' or 'Mechanic service is unavailable right now.', 'error')
        return
    end
    panelOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open' })
    sendState(res)
end

RegisterCommand('mechanic', function() if panelOpen then closePanel() else openPanel() end end, false)
exports('OpenMechanicPanel', openPanel)
exports('CloseMechanicPanel', closePanel)

-- ---------------------------------------------------------------------- NUI callbacks

RegisterNUICallback('close', function(_, cb) closePanel(); cb({ ok = true }) end)
RegisterNUICallback('refresh', function(_, cb) cb(refresh() or { ok = false }) end)

local function guarded(fn)
    return function(data, cb)
        if busy then cb({ ok = false, error = 'busy' }); return end
        busy = true
        local ok, res = pcall(fn, data or {})
        busy = false
        cb(ok and res or { ok = false, error = 'failed' })
        if panelOpen then refresh() end
    end
end

RegisterNUICallback('claim', guarded(function(d)
    local res = lib.callback.await('cm-mechanic:claim', false, tostring(d.contract or ''), type(d.business) == 'string' and d.business or nil)
    if res and res.ok and res.data and res.data.customerPosition then
        local p = res.data.customerPosition
        SetNewWaypoint(p.x + 0.0, p.y + 0.0)
        hudNotify('Customer location marked on your map.', 'info')
    end
    return res
end))
RegisterNUICallback('diagnose', guarded(function()
    local netId = nearbyVehicle()
    if not netId then return { ok = false, error = 'no_vehicle_nearby' } end
    return lib.callback.await('cm-mechanic:diagnose', false, netId)
end))
RegisterNUICallback('quote', guarded(function(d)
    local netId = nearbyVehicle()
    if not netId then return { ok = false, error = 'no_vehicle_nearby' } end
    return lib.callback.await('cm-mechanic:quote', false, tostring(d.service or ''), netId)
end))
RegisterNUICallback('tuning', guarded(function(d)
    local netId = nearbyVehicle()
    if not netId then return { ok = false, error = 'no_vehicle_nearby' } end
    local res = lib.callback.await('cm-mechanic:startTuning', false, netId, tostring(d.shop or ''))
    -- cm-tuning opens its own tuning UI for the mechanic on success (the mechanic panel steps aside).
    if res and res.ok then closePanel() end
    return res
end))
RegisterNUICallback('abandon', guarded(function() return lib.callback.await('cm-mechanic:abandon', false) end))
RegisterNUICallback('service', guarded(function()
    local netId, veh = nearbyVehicle()
    if not netId then return { ok = false, error = 'no_vehicle_nearby' } end
    local started = lib.callback.await('cm-mechanic:startService', false, netId)
    if not started or started.ok ~= true then return started end
    -- Shared timed animation + progress bar from cm-vehicles; the SERVER enforces the minimum duration, this is presentation.
    local okRun, done = pcall(function()
        return exports['cm-vehicles']:RunServiceProgress('repair', veh, (tonumber(started.data.durationSeconds) or 10) * 1000)
    end)
    if okRun and done == false then
        hudNotify('Service interrupted. Start it again when ready.', 'error')
        return { ok = false, error = 'interrupted' }
    end
    local finished = lib.callback.await('cm-mechanic:finishService', false, netId)
    if finished and finished.ok then hudNotify('Service completed.', 'success') end
    return finished
end))

-- ------------------------------------------------------------- server -> client events

-- Mechanic: order changed (customer decision, payment, cancellation). Cosmetic; the panel re-reads authoritative state.
local MESSAGES = {
    declined = 'The customer declined your quote.', paid = 'Payment received. You can start the service.', completed = 'Work order completed.',
    cancelled = 'The work order was cancelled.', quoted = 'Quote sent. Waiting for the customer.', invoice_expired = 'The invoice expired. Send a new quote.', invoice_voided = 'The invoice was cancelled.',
}
RegisterNetEvent('cm-mechanic:client:update', function(info)
    if type(info) ~= 'table' then return end
    local text = MESSAGES[info.kind]
    if text then hudNotify(text, (info.kind == 'paid' or info.kind == 'completed') and 'success' or 'info') end
    if panelOpen then refresh() end
end)

-- Customer: approve or decline the mechanic's server-calculated quote (cm-ui shared confirmation).
RegisterNetEvent('cm-mechanic:client:quote', function(q)
    if type(q) ~= 'table' or quotePrompt then return end
    quotePrompt = true
    CreateThread(function()
        local message = ('%s\n\nService: %s\nPrice: %s\n\nApproving sends the invoice to your Bills. The vehicle is serviced after you pay.')
            :format(tostring(q.business or 'Mechanic'), tostring(q.service or 'Service'), money(q.amount))
        if type(q.detail) == 'string' and q.detail ~= '' then message = message .. '\n\nIncludes: ' .. q.detail end
        local okC, approved = pcall(function()
            return exports['cm-ui']:Confirm({ title = 'CONFIRM SERVICE QUOTE', message = message, confirmText = 'APPROVE', cancelText = 'DECLINE' })
        end)
        quotePrompt = false
        local res = lib.callback.await('cm-mechanic:respondQuote', false, okC and approved == true)
        if res and res.ok and res.data and res.data.approved then
            hudNotify('Quote approved. Open Bills to pay.', 'success')
        elseif res and not res.ok and res.error == 'quote_changed' then
            hudNotify('The vehicle condition changed. The mechanic must send a new quote.', 'error')
        elseif res and not res.ok and res.error == 'quote_expired' then
            hudNotify('The quote expired.', 'error')
        end
    end)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if panelOpen then SetNuiFocus(false, false) end
end)
