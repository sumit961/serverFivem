-- Emergency app: forwards to the EXISTING owner dispatch contracts. cm-phone keeps no dispatch queue.
-- Location is resolved by the owners from the server-observed player ped; no client coordinates are used.
local S = CMPhone.Server
local Config = CMPhone.Config
local E = Config.Emergency

-- Adapter (replaceable by the dev self-test). Owner exports are called with literal names so the contract
-- scanner records cm-phone as a consumer of cm-ems:CreateAmbulanceCall and cm-law:CreateLawCall.
S.Dispatch = {
    ems = function(src, details)
        if GetResourceState('cm-ems') ~= 'started' then return false, 'Emergency services are unavailable right now.' end
        local ok, success, message = pcall(function()
            return exports['cm-ems']:CreateAmbulanceCall(src, { details = details, emergencyType = 'phone', priority = 2 })
        end)
        if not ok then return false, 'Emergency services are unavailable right now.' end
        return success == true, tostring(message or (success and 'Ambulance requested.' or 'Request failed.'))
    end,
    police = function(src, details)
        if GetResourceState('cm-law') ~= 'started' then return false, 'Emergency services are unavailable right now.' end
        local ok, success, message = pcall(function()
            return exports['cm-law']:CreateLawCall(src, '[Phone] ' .. details)
        end)
        if not ok then return false, 'Emergency services are unavailable right now.' end
        return success == true, tostring(message or (success and 'Police notified.' or 'Request failed.'))
    end,
}

-- service: 'police' | 'ems'
function S.SendEmergency(src, cid, service, rawDetails)
    if service ~= 'police' and service ~= 'ems' then return false, 'invalid_request' end
    local details = S.cleanText(rawDetails, E.detailsMax, false) or 'Phone emergency call'
    local ok, message = S.Dispatch[service](src, details)
    S.audit(src, 'cm_phone_emergency', { characterId = cid, service = service, accepted = ok == true })
    return ok == true, message
end
