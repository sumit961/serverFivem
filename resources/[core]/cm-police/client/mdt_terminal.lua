-- cm-police standalone MDT terminal (Tab key). A second, differently-
-- skinned entry point onto the exact same server-side MDT callbacks the F7
-- dashboard's own MDT tab already uses (server/mdt.lua) -- this file only
-- owns opening/closing the overlay, not any records logic. The F7 tab is
-- untouched and still works independently ("keep both" entry points).

local open = false

local function sexOf()
    return GetEntityModel(PlayerPedId()) == `mp_f_freemode_01` and 'female' or 'male'
end

local function restoreFocus()
    local dashboardOpen = type(IsPoliceMenuOpen) == 'function' and IsPoliceMenuOpen() == true
    SetNuiFocus(dashboardOpen, dashboardOpen)
end

local function closeTerminal()
    if not open then return end
    open = false
    SendNUIMessage({ action = 'closeMdtTerminal' })
    restoreFocus()
end

function PoliceCloseMdtTerminal()
    closeTerminal()
end

local function togglePoliceMdt()
    if open then return closeTerminal() end
    -- Do not trust the replicated state bag as an entry gate (same reasoning
    -- client/main.lua's own F7 command already documents: it can be briefly
    -- absent right after character/resource loading, which would otherwise
    -- reject a legitimately-eligible officer with a false "must be on duty"
    -- error). The dashboard callback is the authoritative membership check,
    -- and every MDT action beyond that (search/profile/etc.) independently
    -- re-checks on-duty + police.mdt server-side regardless of what this
    -- command does -- so there is no security gate being skipped here, only
    -- a race-prone UX pre-filter being removed.
    local data = lib.callback.await('cm-police:server:dashboard', false, false, sexOf())
    if not data or type(data.self) ~= 'table' or data.self.onDuty ~= true
        or type(data.capabilities) ~= 'table' or data.capabilities.useMdt ~= true then return end
    open = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'openMdtTerminal', data = data })
end

RegisterCommand('policemdtterminal', togglePoliceMdt, false)
RegisterNetEvent('cm-police:client:toggleMdt', togglePoliceMdt)

RegisterNUICallback('closeMdtTerminal', function(_, cb)
    closeTerminal()
    cb({ ok = true })
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and open then closeTerminal() end
end)
