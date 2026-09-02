-- ============================================================
--  cm-family | cl_armory.lua
--  Thin NUI bridge for the family armory tab (html/js/family-v100.js).
--  Mirrors cm-gang/client/dashboard.lua's armory wiring: every callback just
--  forwards to the matching cm-family:server:* callback and returns the
--  result as-is -- all authority/validation happens server-side.
-- ============================================================

RegisterNUICallback('getArmory', function(_, cb)
    cb(lib.callback.await('cm-family:server:getArmory', false))
end)

RegisterNUICallback('armoryCheckout', function(payload, cb)
    payload = type(payload) == 'table' and payload or {}
    cb(lib.callback.await('cm-family:server:armoryCheckout', false, payload.itemId))
end)

RegisterNUICallback('armoryDeposit', function(payload, cb)
    payload = type(payload) == 'table' and payload or {}
    cb(lib.callback.await('cm-family:server:armoryDeposit', false, { itemId = payload.itemId, quantity = payload.quantity }))
end)

RegisterNUICallback('armoryManagement', function(_, cb)
    cb(lib.callback.await('cm-family:server:armoryManagement', false))
end)

RegisterNUICallback('armorySave', function(payload, cb)
    cb(lib.callback.await('cm-family:server:armorySave', false, type(payload) == 'table' and payload or {}))
end)

RegisterNUICallback('armoryLoadStock', function(_, cb)
    cb(lib.callback.await('cm-family:server:armoryLoadStock', false))
end)
