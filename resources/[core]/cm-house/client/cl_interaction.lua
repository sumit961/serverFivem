-- Unified CM house interaction arbiter.
-- Every world interaction requests the same transparent cyan E prompt. The
-- arbiter chooses the highest-priority request and hides the prompt whenever
-- any focused NUI, inventory, wardrobe or house menu is open.
CMHouseInteraction = CMHouseInteraction or {}
local I = CMHouseInteraction
local requests = {}
local shownKey = nil
local manuallySuppressed = false
local blockedUntil = 0
local busyContexts = {}

local function clean(text)
    text = tostring(text or '')
    text = text:gsub('~[%w_]+~', '')
    text = text:gsub('%s+', ' ')
    text = text:gsub('^%s+', ''):gsub('%s+$', '')
    text = text:gsub('^%[E%]%s*', '')
    return text
end

function I.Request(id, label, sublabel, priority, options)
    id = tostring(id or 'interaction')
    options = type(options) == 'table' and options or {}
    requests[id] = {
        id = id,
        label = clean(label ~= '' and label or 'Interact'),
        sublabel = clean(sublabel or ''),
        key = tostring(options.key or Config.Prompt.keyLabel or 'E'),
        status = tostring(options.status or ''),
        priority = tonumber(priority) or 10,
        expires = GetGameTimer() + math.max(100, tonumber(options.ttl) or 220),
        disabled = options.disabled == true,
    }
end

function I.Clear(id)
    requests[tostring(id or '')] = nil
end

function I.Suppress(value)
    manuallySuppressed = value == true
end

-- Temporarily removes the prompt while an external UI is being opened. Once
-- the inventory/wardrobe receives NUI focus, automatic suppression takes over.
function I.BlockFor(milliseconds)
    blockedUntil = math.max(blockedUntil, GetGameTimer() + math.max(0, tonumber(milliseconds) or 0))
end

-- External CM resources can explicitly mark a UI context busy. This is useful
-- for inventory implementations that do not use normal NUI focus.
function I.SetBusy(context, value)
    context = tostring(context or 'external')
    if value == true then busyContexts[context] = true else busyContexts[context] = nil end
end

local function bestRequest()
    local now = GetGameTimer()
    local best
    for id, req in pairs(requests) do
        if req.expires < now then
            requests[id] = nil
        elseif not best or req.priority > best.priority then
            best = req
        end
    end
    return best
end

local function playerStateBusy()
    if not LocalPlayer or not LocalPlayer.state then return false end
    local state = LocalPlayer.state
    return state.invOpen == true
        or state.inventoryOpen == true
        or state.wardrobeOpen == true
        or state.storageOpen == true
end

local function focusedNui()
    if type(IsNuiFocused) ~= 'function' then return false end
    local ok, value = pcall(IsNuiFocused)
    return ok and value == true
end

local function shouldSuppress()
    if manuallySuppressed or GetGameTimer() < blockedUntil then return true end
    if focusedNui() or IsPauseMenuActive() or playerStateBusy() then return true end
    for _, active in pairs(busyContexts) do
        if active == true then return true end
    end
    return false
end

CreateThread(function()
    while true do
        Wait(50)
        local req = not shouldSuppress() and bestRequest() or nil
        local key = req and table.concat({
            req.id, req.label, req.key, tostring(req.disabled)
        }, '|') or nil

        if key ~= shownKey then
            shownKey = key
            if req then
                SendNUIMessage({ action = 'interaction:show', data = req })
            else
                SendNUIMessage({ action = 'interaction:hide' })
            end
        end
    end
end)

RegisterNetEvent('cm-house:client:setInteractionBusy', function(context, value)
    I.SetBusy(context, value)
end)

exports('RequestInteraction', I.Request)
exports('ClearInteraction', I.Clear)
exports('SuppressInteractions', I.Suppress)
exports('BlockInteractionsFor', I.BlockFor)
exports('SetInteractionBusy', I.SetBusy)
