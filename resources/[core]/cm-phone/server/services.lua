-- cm-phone Service Marketplace: FiveM wiring for server/services_core.lua. See docs/SERVICES.md.
-- Source owners register an adapter for the service they own; the phone calls that adapter (create / status / cancel)
-- with the CHARACTER id resolved from the live session. No request or history is stored here.
local S = CMPhone.Server
local Config = CMPhone.Config
local Core = CMPhone.ServicesCore

-- pcall'd cross-resource call that fails closed when the owner resource is not started.
local function call(resource, name, ...)
    if GetResourceState(resource) ~= 'started' then return false, 'resource_unavailable' end
    local args = table.pack(...)
    local res = table.pack(pcall(function() return exports[resource][name](exports[resource], table.unpack(args, 1, args.n)) end))
    if not res[1] then return false, 'call_failed' end
    return true, res[2], res[3]
end

S.Services = Core.New({
    cfg = Config,
    call = call,
    started = function(resource) return GetResourceState(resource) == 'started' end,
    now = os.time,
    rateLimit = function(cid, bucket) return S.RateLimit(cid, bucket) end,
    cleanText = S.cleanText,
    audit = S.audit,
    position = function(src)
        local ped = GetPlayerPed(src)
        if not ped or ped == 0 then return nil end
        local c = GetEntityCoords(ped)
        local okBucket, bucket = pcall(GetPlayerRoutingBucket, src)
        return { x = c.x, y = c.y, z = c.z, bucket = okBucket and bucket or 0 }
    end,
    isDead = function(src)
        local api = S.playerData()
        if not api then return false end
        local ok, dead = pcall(function() return api:IsDead(src) end)
        return ok and dead == true
    end,
    emit = function(cid, event, payload)
        local src = S.SourceOf(cid)
        if not src then return false end
        return S.Emit(src, event, payload)
    end,
})

-- ---- Public contracts (docs/SERVICES.md) -------------------------------------------------------------------------

-- RegisterPhoneService(serviceId, { create='Export', status='Export', cancel='Export'?, availability='Export'? }) -> ok, reason.
-- Only resources in Config.Services.Sources for that service id may register; display data stays in the phone catalog.
exports('RegisterPhoneService', function(serviceId, definition)
    return S.Services:RegisterAdapter(GetInvokingResource(), serviceId, definition)
end)

exports('UnregisterPhoneService', function()
    local invoking = GetInvokingResource()
    if invoking then S.Services:UnregisterResource(invoking) end
    return true
end)

-- PushPhoneServiceStatus(characterId, serviceId, status) -> ok, reason. Only the registered owner of that service may push;
-- the status is reduced to the whitelisted public shape and shown to the requester as a toast (event-driven, no polling).
exports('PushPhoneServiceStatus', function(characterId, serviceId, status)
    return S.Services:Push(GetInvokingResource(), characterId, serviceId, status)
end)

-- TranslateContractStatus(contractStatus, completionMode) -> player-facing state key. Pure helper for source owners that
-- publish to cm-contracts: broker states never need to be shown to players.
exports('TranslateContractStatus', function(status, mode)
    return Core.MapContractState(status, mode)
end)

AddEventHandler('onResourceStop', function(resource)
    S.Services:UnregisterResource(resource)
end)

-- Adapters live in memory; ask owners to register again after a phone restart.
CreateThread(function()
    Wait(1500)
    TriggerEvent('cm-phone:server:serviceRegistryReady')
end)
