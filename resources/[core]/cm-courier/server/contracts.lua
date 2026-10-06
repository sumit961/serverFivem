-- cm-courier/server/contracts.lua
-- Fail-closed commercial-order adapter. Municipal courier routes never depend on this file.
--
-- cm-contracts defines the 'courier_delivery' type (provider 'courier'), but no trusted SOURCE in
-- cm-contracts/config.lua is allowed to publish it, so no authoritative courier order or payout can
-- exist. Nothing is queried, fabricated or priced here. When a source is added, listing/claim/complete
-- must be wired here against that source's real payout and route data.

CourierContracts = {}

local NO_SOURCE = 'no_authoritative_courier_source'

--- Genuine commercial courier orders. Always unavailable until a trusted source publishes them.
---@return boolean ok, table|string contractsOrReason
function CourierContracts.GetAvailableCommercialContracts(_charId)
    return false, {}, NO_SOURCE
end

--- A commercial order is claimable only with an authoritative payout and cycle time. None exist yet.
---@return boolean claimable, table|nil info, string reason
function CourierContracts.EvaluateCommercialOrder(_contract, _meta)
    return false, nil, 'No authoritative payout or route data is published for this order, so its pay rate cannot be compared with the municipal route.'
end

function CourierContracts.ReleaseContract(_reference, _charId, _reason)
    return false, NO_SOURCE
end
