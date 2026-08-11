-- cm-police shared UI toolkit. Runs for EVERY connected client (not just
-- Police members -- impound.lua's release-fee menu and cuffs.lua's control
-- lock both need this too), same convention as impound.lua/cuffs.lua
-- already loading unconditionally. Replaces every ox_lib UI surface
-- (lib.notify/registerContext/showContext/showTextUI/hideTextUI/
-- alertDialog) with cm-police's own persistent NUI page (html/index.html +
-- html/app.js -- the same page already used for the F7 dashboard and the
-- Police Wardrobe dressing room). lib.callback (server RPC) is untouched --
-- it renders nothing, so it isn't part of this replacement.

-- ── Toast notifications (passive, no focus change) ────────────────────────
function PoliceNotify(message, kind, title)
    kind = kind or 'inform'
    if (kind == 'success' or kind == 'error') and GetResourceState('cm-hud') == 'started' then
        local delivered = pcall(function()
            exports['cm-hud']:Notify(tostring(message or ''), kind)
        end)
        if delivered then return end
    end
    SendNUIMessage({ action = 'notify', title = title or 'Police', description = tostring(message or ''), type = kind or 'inform' })
end

local policeNpcPromptOwner
local policeNpcPromptData
local policeNpcPromptSuppressed = false
local policeNpcPromptRendered = false
local policeNpcPromptSignature

local function npcInteractionBlocked()
    if policeNpcPromptSuppressed then return true end
    if IsPauseMenuActive() then return true end
    local ped = PlayerPedId()
    if ped and ped ~= 0 and IsPedInAnyVehicle(ped, false) then return true end
    return IsNuiFocused and IsNuiFocused() == true
end

local function renderNpcInteraction()
    if npcInteractionBlocked() or not policeNpcPromptOwner or not policeNpcPromptData then
        if policeNpcPromptRendered then
            SendNUIMessage({ action = 'npcInteraction:hide' })
            policeNpcPromptRendered = false
            policeNpcPromptSignature = nil
        end
        return
    end
    local signature = ('%s:%s:%s'):format(policeNpcPromptOwner, policeNpcPromptData.name, policeNpcPromptData.role)
    if policeNpcPromptRendered and policeNpcPromptSignature == signature then return end
    SendNUIMessage({ action = 'npcInteraction:show', key = 'E', label = 'INTERACTION',
        name = policeNpcPromptData.name, role = policeNpcPromptData.role })
    policeNpcPromptRendered = true
    policeNpcPromptSignature = signature
end

function PoliceDrawNpcName(location, name)
    if type(location) ~= 'table' then return end
    SetDrawOrigin(tonumber(location.x) or 0.0, tonumber(location.y) or 0.0, (tonumber(location.z) or 0.0) + 1.15, 0)
    SetTextFont(4); SetTextScale(0.0, 0.31); SetTextCentre(true); SetTextOutline()
    SetTextColour(255, 255, 255, 245)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(tostring(name or 'Police Officer'))
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

function PoliceShowNpcInteraction(owner, name, role, icon)
    owner = tostring(owner or 'police_npc')
    policeNpcPromptOwner = owner
    policeNpcPromptData = {
        name = tostring(name or 'Police Officer'),
        role = tostring(role or 'Police Services'),
    }
    renderNpcInteraction()
end

function PoliceHideNpcInteraction(owner)
    if policeNpcPromptOwner ~= tostring(owner or '') then return end
    policeNpcPromptOwner = nil
    policeNpcPromptData = nil
    renderNpcInteraction()
end

-- Cinematic dialogue suppresses the prompt without losing the nearby NPC's
-- current prompt data. When the cinematic closes, the prompt can return
-- immediately if that NPC is still active.
function PoliceSuppressNpcInteraction(suppressed)
    policeNpcPromptSuppressed = suppressed == true
    renderNpcInteraction()
end

-- Menu focus and vehicle state can change without the nearby NPC loop
-- changing its owner, so re-evaluate visibility independently. Messages are
-- emitted only on a state transition, not every tick.
CreateThread(function()
    while true do
        Wait(150)
        renderNpcInteraction()
    end
end)

-- ── Bottom-of-screen hint (passive, no focus change) ───────────────────────
-- One shared slot for every use case (radar reading, spike placement
-- prompt, escort prompts) -- they're never needed at the same instant, so a
-- second one would just be unused complexity.
function PoliceShowHint(text)
    SendNUIMessage({ action = 'showHint', text = tostring(text or '') })
end

function PoliceHideHint()
    SendNUIMessage({ action = 'hideHint' })
end

-- ── Focus-grabbing components (confirm dialog, quick menu) ────────────────
-- Both block the calling coroutine until the NUI answers -- RegisterCommand
-- handlers (and CreateThread bodies) each run in their own coroutine, so a
-- Wait(0) loop here only yields that one caller, never the whole resource.
-- No promise/async pattern exists elsewhere in this codebase to copy, so
-- this is a new (but standard FiveM) idiom, contained entirely in this file.

local function restoreDashboardFocus()
    local dashboardOpen = type(IsPoliceMenuOpen) == 'function' and IsPoliceMenuOpen() == true
    SetNuiFocus(dashboardOpen, dashboardOpen)
end

local pendingConfirmResult = nil
local confirmBusy = false
RegisterNUICallback('confirmResponse', function(data, cb)
    pendingConfirmResult = data.confirmed == true
    cb({ ok = true })
end)

function PoliceConfirm(title, message, yesLabel, noLabel)
    -- Queue, don't clobber: PoliceQuickMenu already guards re-entry by
    -- refusing it outright, but a confirm should still eventually show
    -- (e.g. a second Police invite arriving before the first is answered)
    -- rather than being dropped -- so this waits its turn instead. Without
    -- this, two overlapping calls shared one `pendingConfirmResult` and a
    -- single click could resolve both waiting calls with the same answer,
    -- one of them for a prompt the player never actually saw the text of.
    while confirmBusy do Wait(0) end
    confirmBusy = true
    pendingConfirmResult = nil
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'confirmOpen',
        title = title or 'Confirm',
        message = message or 'Are you sure?',
        yesLabel = yesLabel or 'Confirm',
        noLabel = noLabel or 'Cancel',
    })
    while pendingConfirmResult == nil do Wait(0) end
    SendNUIMessage({ action = 'confirmClose' })
    restoreDashboardFocus()
    local result = pendingConfirmResult == true
    confirmBusy = false
    return result
end

local pendingQuickMenuChoice = nil
local quickMenuOpen = false
RegisterNUICallback('quickMenuChoice', function(data, cb)
    pendingQuickMenuChoice = tonumber(data.index) or -1
    cb({ ok = true })
end)
RegisterNUICallback('quickMenuClosed', function(_, cb)
    pendingQuickMenuChoice = -1
    cb({ ok = true })
end)

-- items = { { title, description, icon, onSelect }, ... }. Only
-- title/description/icon are ever sent to the NUI -- onSelect is a Lua
-- closure and stays entirely on this side; the NUI just reports back which
-- index was clicked.
function PoliceQuickMenu(title, items)
    if quickMenuOpen or type(items) ~= 'table' or #items == 0 then return end
    quickMenuOpen = true
    pendingQuickMenuChoice = nil
    SetNuiFocus(true, true)
    local nuiItems = {}
    for index, item in ipairs(items) do
        nuiItems[index] = { title = item.title, description = item.description, icon = item.icon }
    end
    SendNUIMessage({ action = 'quickMenuOpen', title = title or 'Menu', items = nuiItems })
    while pendingQuickMenuChoice == nil do Wait(0) end
    quickMenuOpen = false
    SendNUIMessage({ action = 'quickMenuClose' })
    restoreDashboardFocus()
    local choice = items[pendingQuickMenuChoice]
    if choice and type(choice.onSelect) == 'function' then choice.onSelect() end
end
