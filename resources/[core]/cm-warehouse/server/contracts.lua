-- cm-warehouse/server/contracts.lua
-- Fail-closed commercial-order adapter. Municipal shifts never depend on this file.
--
-- cm-contracts has no trusted SOURCE or registered 'warehouse' PROVIDER, so no authoritative
-- warehouse order or payout can exist. Every operation fails closed without calling the broker, and
-- nothing is fabricated. If a source is added later, wire listing/claim/complete/release here.

WarehouseContracts = {}

local NO_SOURCE = 'no_authoritative_warehouse_source'

-- Returns ok=false, an EMPTY table (safe to iterate), and the reason.
function WarehouseContracts.GetAvailablePremiumContracts(_charId)
    return false, {}, NO_SOURCE
end

function WarehouseContracts.ClaimContract(_reference, _charId, _meta)
    return false, NO_SOURCE
end

function WarehouseContracts.CompleteContract(_reference, _charId, _payload)
    return false, NO_SOURCE
end

function WarehouseContracts.ReleaseContract(_reference, _charId, _reason)
    return false, NO_SOURCE
end
