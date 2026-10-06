-- Thin player-facing bridge for the cm-vehicles legal self-service contract.
-- cm-vehicles remains authoritative for character ownership, legal state,
-- pricing, payment, expiry and all mutations.

local VEHICLE_RESOURCE = 'cm-vehicles'

local function unavailable()
    return {
        ok = false,
        error = 'vehicle_services_unavailable',
        message = 'Vehicle registration services are unavailable right now.',
    }
end

local function vehicleServicesReady()
    return GetResourceState(VEHICLE_RESOURCE) == 'started'
end

local function isFiniteNumber(value)
    return type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge
end

local function getOverview(src)
    if not vehicleServicesReady() then return unavailable() end

    local ok, result = pcall(function()
        return exports[VEHICLE_RESOURCE]:GetPlayerVehicleLegalOverview(tonumber(src))
    end)

    if not ok or type(result) ~= 'table' then return unavailable() end
    return result
end

local function purchaseService(src, data)
    if not vehicleServicesReady() then return unavailable() end
    if type(data) ~= 'table' then
        return { ok = false, error = 'invalid_request', message = 'Invalid vehicle service request.' }
    end

    local vehicleId = tonumber(data.vehicleId)
    local service = tostring(data.service or '')
    local requestId = data.requestId
    local expectedPrice = tonumber(data.expectedPrice)

    if not isFiniteNumber(vehicleId) or vehicleId < 1 or vehicleId % 1 ~= 0 then
        return { ok = false, error = 'invalid_request', message = 'Invalid vehicle selection.' }
    end
    if service ~= 'registration' and service ~= 'insurance' then
        return { ok = false, error = 'invalid_request', message = 'Invalid vehicle service.' }
    end
    if requestId ~= nil and (type(requestId) ~= 'string' or #requestId < 1 or #requestId > 80) then
        return { ok = false, error = 'invalid_request', message = 'Invalid service request token.' }
    end
    if expectedPrice ~= nil and (not isFiniteNumber(expectedPrice) or expectedPrice < 0 or expectedPrice % 1 ~= 0) then
        return { ok = false, error = 'invalid_request', message = 'Invalid service price confirmation.' }
    end

    local ok, result = pcall(function()
        return exports[VEHICLE_RESOURCE]:PurchaseVehicleLegalService(tonumber(src), vehicleId, service, {
            requestId = requestId,
            expectedPrice = expectedPrice,
        })
    end)

    if not ok or type(result) ~= 'table' then return unavailable() end
    result.detail = nil
    return result
end

lib.callback.register('cm-hub:server:getVehicleRegistry', function(src)
    return getOverview(src)
end)

lib.callback.register('cm-hub:server:purchaseVehicleService', function(src, data)
    return purchaseService(src, data)
end)
