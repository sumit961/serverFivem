-- Fixture: server-side FiveM script for cm-fivem-map tests.
-- Covers: a matching handler for the client trigger, a TriggerClientEvent
-- back to the client handler, a second handler for the same event (multiple
-- handlers case), static and local-variable-resolved MySQL calls, a fully
-- dynamic MySQL call, an export definition, NUI callbacks (one used, one
-- orphaned), an ox_lib callback registration, and a command with an ACE
-- permission check.

RegisterNetEvent('fixture:doThing')
AddEventHandler('fixture:doThing', function(a, b)
    TriggerClientEvent('fixture:clientReady', -1)
end)

-- second handler for the same event: exercises the "multiple handlers" case
AddEventHandler('fixture:doThing', function(a, b)
    print('second handler')
end)

lib.callback.register('fixture:askServer', function(source, flag, n)
    return flag and n or 0
end)

exports('GetFixtureValue', function()
    return 42
end)

RegisterNUICallback('fixtureNuiAction', function(data, cb)
    cb('ok')
end)

RegisterNUICallback('fixtureUnusedCallback', function(data, cb)
    cb('ok')
end)

MySQL.query.await('SELECT id, name FROM fixture_items WHERE id = ?', {1})

local insertSql = "INSERT INTO fixture_events (name, ts) VALUES (?, ?)"
MySQL.insert(insertSql, {'x', 0})

MySQL.update(buildDynamicQuery(), {})

RegisterCommand('fixturecmd', function(source, args)
    if not IsPlayerAceAllowed(source, 'fixture.admin') then
        return
    end
    print('ran fixturecmd')
end, true)
