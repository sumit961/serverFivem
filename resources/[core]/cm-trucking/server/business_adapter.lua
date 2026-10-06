-- cm-trucking/server/business_adapter.lua
-- Generic broker (cm-contracts) provider adapter for Commercial Freight Trucking.
--
-- This module coordinates with cm-contracts for:
-- 1. Provider registration ('trucking' provider type for verified 'business_supply' contracts).
-- 2. Broker contract queries and worker claim management.
-- 3. Atomic state advancement: Claim -> MarkActive -> Complete -> Release/Fail.
-- 4. Disconnect reporting and grace period handling.
--
-- Contract Source Integrity:
--   'business_supply' has a verified publisher in cm-commercial-ownership.
--   'bulk_material_transport' is currently deferred as no publisher exists in the repo.
--
-- This resource never creates money/items, touches business database tables, or directly credits stock.
-- Stock and business order authority remain exclusively with cm-commercial-ownership.

local Config = CMTrucking.Config
CMTrucking = CMTrucking or {}
CMTrucking.BusinessAdapter = CMTrucking.BusinessAdapter or {}
local BusinessAdapter = CMTrucking.BusinessAdapter

local BROKER = 'cm-contracts'

local function isBrokerReady()
    return GetResourceState(BROKER) == 'started'
end

local function brokerCall(exportName, ...)
    if not isBrokerReady() then
        return false, 'broker_unavailable'
    end
    local args = table.pack(...)
    local ok, res1, res2 = pcall(function()
        return exports[BROKER][exportName](exports[BROKER], table.unpack(args, 1, args.n))
    end)
    if not ok then
        return false, 'broker_call_failed'
    end
    return res1, res2
end

-- =========================================================================
-- Provider Registration
-- =========================================================================

function BusinessAdapter.Register()
    if not isBrokerReady() then return false, 'broker_unavailable' end

    -- Register only contract types that have real source publishers in the repository
    local ok, result = brokerCall('RegisterProvider', Config.Broker.providerType or 'trucking', {
        types = Config.Broker.supportedTypes or { 'business_supply' },
        eligibilityExport = 'ContractEligible',
        eventExport = 'ContractEvent',
        disconnectPolicy = 'grace',
        graceSeconds = 120,
    })

    if ok and type(result) == 'table' then
        if Config.Debug then
            print(('[CM-TRUCKING] Registered with cm-contracts broker as provider: %s'):format(result.providerType or 'trucking'))
        end
        return true, result
    end

    return false, result or 'registration_failed'
end

-- Re-register when cm-contracts signals ready (e.g. after broker restart or sweep)
AddEventHandler('cm-contracts:server:providerRegistryReady', function()
    BusinessAdapter.Register()
end)

-- Initial registration attempt on startup
CreateThread(function()
    Wait(1500)
    BusinessAdapter.Register()
end)

-- =========================================================================
-- Broker Callbacks (Invoked by cm-contracts)
-- =========================================================================

-- Eligibility callback: broker verifies worker before awarding a claim
exports('ContractEligible', function(characterId, view)
    local invoker = GetInvokingResource()
    if invoker and invoker ~= BROKER then
        return false, 'forbidden'
    end

    if not characterId or tostring(characterId) == '' then
        return false, 'invalid_character'
    end

    -- Character must not already have an active conflicting trucking session
    if CMTrucking.Server and CMTrucking.Server.HasActiveSessionForCharacter then
        if CMTrucking.Server.HasActiveSessionForCharacter(tostring(characterId)) then
            return false, 'already_working'
        end
    end

    return true
end)

-- Event callback: broker notifies provider of state changes (lease expiry, fallback, cancellation, release)
exports('ContractEvent', function(reference, characterId, event, reason)
    local invoker = GetInvokingResource()
    if invoker and invoker ~= BROKER then
        return false, 'forbidden'
    end

    if Config.Debug then
        print(('[CM-TRUCKING] ContractEvent: ref=%s cid=%s event=%s reason=%s'):format(
            tostring(reference), tostring(characterId), tostring(event), tostring(reason)))
    end

    if CMTrucking.Server and CMTrucking.Server.HandleBrokerEvent then
        CMTrucking.Server.HandleBrokerEvent(reference, characterId, event, reason)
    end

    return true
end)

-- =========================================================================
-- Broker Provider API Methods (Consumed by server/main.lua)
-- =========================================================================

function BusinessAdapter.ListAvailableContracts(characterId, filters)
    filters = type(filters) == 'table' and filters or {}
    -- Enforce real publisher contract type
    if not filters.contractType then
        filters.contractType = 'business_supply'
    end
    return brokerCall('ListAvailableContracts', Config.Broker.providerType or 'trucking', filters, characterId)
end

function BusinessAdapter.GetWorkerContracts(characterId)
    return brokerCall('GetWorkerContracts', Config.Broker.providerType or 'trucking', characterId)
end

function BusinessAdapter.ClaimContract(reference, characterId, opts)
    opts = type(opts) == 'table' and opts or {}
    return brokerCall('ClaimContract', reference, characterId, opts)
end

function BusinessAdapter.MarkContractActive(reference, characterId, opts)
    opts = type(opts) == 'table' and opts or {}
    return brokerCall('MarkContractActive', reference, characterId, opts)
end

function BusinessAdapter.CompleteContract(reference, characterId, payload)
    local opts = {
        payload = type(payload) == 'table' and payload or nil,
    }
    return brokerCall('CompleteContract', reference, characterId, opts)
end

function BusinessAdapter.ReleaseContract(reference, characterId, reason)
    return brokerCall('ReleaseContract', reference, characterId, tostring(reason or 'player_cancelled'))
end

function BusinessAdapter.FailContract(reference, characterId, reason)
    return brokerCall('FailContract', reference, characterId, tostring(reason or 'work_failed'))
end

function BusinessAdapter.ReportWorkerDisconnected(characterId)
    return brokerCall('ReportWorkerDisconnected', Config.Broker.providerType or 'trucking', characterId)
end

exports('GetBusinessSupplyAdapter', function()
    return BusinessAdapter
end)

